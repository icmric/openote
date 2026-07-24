//! The page **mirror** model and its deterministic merge.
//!
//! A page mirror is the exact JSON the app writes to the `page_mirror` table
//! (see `app/lib/store/repository.dart::writePage`): the open, human-readable
//! projection of a page. Its shape is:
//!
//! ```json
//! {
//!   "schema": "onote-page/1",
//!   "pageId": "…",
//!   "page":   { "background": "grid", "gridSize": 20, "pageWidth": 1100 },
//!   "blocks": [ { "id": "…", "type": "text", "updatedAt": 173…, … }, … ]
//! }
//! ```
//!
//! We deserialize only the fields merge reasons about (`id`, `updatedAt`, and,
//! for stable ordering, `z`) and keep everything else verbatim in a flattened
//! map, so a round-trip is lossless and forward-compatible: a block field this
//! version of the core has never heard of still survives a merge untouched
//! (Data Model Spec §2 "unknown fields round-trip").

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::cmp::Ordering;
use std::collections::BTreeMap;

/// One block, reduced to what merge needs plus a verbatim tail of every other
/// field so nothing is lost across a merge/serialize round-trip.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Block {
    pub id: String,
    /// Last-write timestamp (epoch ms). Absent → 0, so a block that never
    /// declared one always loses to one that did.
    #[serde(rename = "updatedAt", default)]
    pub updated_at: i64,
    /// Every other field on the block, preserved exactly (`type`, `x`, `y`,
    /// `content`, `z`, unknown future fields, …).
    #[serde(flatten)]
    pub rest: Map<String, Value>,
}

impl Block {
    fn z(&self) -> i64 {
        self.rest.get("z").and_then(Value::as_i64).unwrap_or(0)
    }
}

/// A full page snapshot in mirror form.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageMirror {
    #[serde(default)]
    pub schema: String,
    #[serde(rename = "pageId", default)]
    pub page_id: String,
    /// Page-level properties, kept as an opaque value (merge treats the page
    /// props as a single last-writer-wins unit — they are tiny and rarely
    /// contended).
    #[serde(default)]
    pub page: Value,
    #[serde(default)]
    pub blocks: Vec<Block>,
}

impl PageMirror {
    /// Parse a mirror JSON string. Returns the serde error on malformed input
    /// rather than panicking — callers decide how to surface it.
    pub fn parse(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    /// Serialize back to the mirror JSON shape.
    pub fn to_json(&self) -> String {
        // Serialization of a value we just deserialized cannot fail.
        serde_json::to_string(self).expect("PageMirror serializes")
    }

    /// The newest `updatedAt` across this page's blocks (0 if empty).
    fn max_updated_at(&self) -> i64 {
        self.blocks.iter().map(|b| b.updated_at).max().unwrap_or(0)
    }

    /// Freshness used to pick the winning page-level props. Prefers an explicit
    /// page-level `updatedAt` when present, so a props-only edit (e.g. changing
    /// the background with no block touched) can win; otherwise falls back to
    /// the newest block edit as a proxy. (The Dart writer does not emit
    /// `page.updatedAt` yet — until it does, props-only edits still rely on the
    /// block proxy; the field is honoured here so wiring it later needs no core
    /// change. See review finding M6.)
    fn props_time(&self) -> i64 {
        let explicit = self
            .page
            .get("updatedAt")
            .and_then(Value::as_i64)
            .unwrap_or(0);
        explicit.max(self.max_updated_at())
    }
}

/// Is `candidate` the winning version of a block that also exists as
/// `incumbent`? Newer `updatedAt` wins; on a tie we compare the blocks'
/// canonical serialization — a **side-independent** rule, so two replicas that
/// call `merge(self, other)` in opposite orders still converge to byte-identical
/// output (the old "local always wins" tie-break diverged on equal timestamps —
/// review finding M5).
fn candidate_wins(candidate: &Block, incumbent: &Block) -> bool {
    match candidate.updated_at.cmp(&incumbent.updated_at) {
        Ordering::Greater => true,
        Ordering::Less => false,
        Ordering::Equal => {
            serde_json::to_string(candidate).unwrap_or_default()
                > serde_json::to_string(incumbent).unwrap_or_default()
        }
    }
}

/// Merge two page snapshots into one, deterministically and without conflicts.
///
/// Semantics (the "snapshot exchange" CRDT-lite that seeds SYNC-1/2):
/// * **Blocks** are keyed by `id`. The union of both sides is kept; when both
///   sides carry the same block, the one with the greater `updatedAt` wins
///   (ties resolve to `local`, so the operation is stable and order-free
///   across replicas that agree on which side is "local").
/// * **Page props** take whichever side's blocks are newer overall (its most
///   recent edit is a good proxy for the freshest page state); ties keep local.
/// * The result's block order is canonical — sorted by `z` then `id` — so two
///   replicas that merged the same pair get byte-identical output.
///
/// This is commutative and associative *up to* the local-wins tie-break, and
/// idempotent (`merge(a, a) == a`). Deletions are **not** yet propagated: a
/// block absent from one side is treated as "not present here", not "deleted",
/// so it survives (add-wins). Real delete propagation needs tombstones and is
/// the job of the Loro-backed engine that replaces this function (ADR-0002);
/// this slice deliberately stops short of inventing a second tombstone scheme.
pub fn merge(local: &PageMirror, remote: &PageMirror) -> PageMirror {
    // BTreeMap → deterministic iteration regardless of insertion order.
    let mut by_id: BTreeMap<&str, &Block> = BTreeMap::new();
    for b in local.blocks.iter().chain(remote.blocks.iter()) {
        match by_id.get(b.id.as_str()) {
            Some(existing) if !candidate_wins(b, existing) => {}
            _ => {
                by_id.insert(b.id.as_str(), b);
            }
        }
    }

    let mut blocks: Vec<Block> = by_id.into_values().cloned().collect();
    blocks.sort_by(|a, b| a.z().cmp(&b.z()).then_with(|| a.id.cmp(&b.id)));

    // Page props: whichever side is newer overall; on an exact tie keep the
    // side whose props serialize larger, so the choice is order-independent too.
    let remote_newer = match remote.props_time().cmp(&local.props_time()) {
        Ordering::Greater => true,
        Ordering::Less => false,
        Ordering::Equal => {
            // Deterministic, side-independent: compare the canonical text form.
            let (l, r) = (local.page.to_string(), remote.page.to_string());
            r > l
        }
    };
    let page = if remote_newer {
        remote.page.clone()
    } else {
        local.page.clone()
    };

    PageMirror {
        schema: pick_nonempty(&local.schema, &remote.schema),
        page_id: pick_nonempty(&local.page_id, &remote.page_id),
        page,
        blocks,
    }
}

/// Convenience: merge two mirror JSON strings, returning merged JSON. Returns
/// the parse error if either side is malformed. This is the shape the Flutter
/// bridge calls.
pub fn merge_json(local_json: &str, remote_json: &str) -> Result<String, serde_json::Error> {
    let local = PageMirror::parse(local_json)?;
    let remote = PageMirror::parse(remote_json)?;
    Ok(merge(&local, &remote).to_json())
}

fn pick_nonempty(a: &str, b: &str) -> String {
    if a.is_empty() { b.to_string() } else { a.to_string() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn mirror(blocks: Value) -> String {
        json!({
            "schema": "onote-page/1",
            "pageId": "p1",
            "page": {"background": "blank", "gridSize": 20, "pageWidth": 1100},
            "blocks": blocks,
        })
        .to_string()
    }

    #[test]
    fn newer_block_wins_and_union_is_kept() {
        let local = mirror(json!([
            {"id": "a", "type": "text", "z": 0, "updatedAt": 1, "content": {"text": "old A"}},
            {"id": "b", "type": "text", "z": 1, "updatedAt": 5, "content": {"text": "only local B"}},
        ]));
        let remote = mirror(json!([
            {"id": "a", "type": "text", "z": 0, "updatedAt": 10, "content": {"text": "new A"}},
            {"id": "c", "type": "text", "z": 2, "updatedAt": 7, "content": {"text": "only remote C"}},
        ]));

        let merged = PageMirror::parse(&merge_json(&local, &remote).unwrap()).unwrap();
        let ids: Vec<_> = merged.blocks.iter().map(|b| b.id.as_str()).collect();
        assert_eq!(ids, vec!["a", "b", "c"], "union of blocks, canonical order");

        let a = merged.blocks.iter().find(|b| b.id == "a").unwrap();
        assert_eq!(a.rest["content"]["text"], json!("new A"), "newer A wins");
    }

    #[test]
    fn merge_is_idempotent() {
        let m = mirror(json!([
            {"id": "a", "type": "text", "z": 0, "updatedAt": 3},
            {"id": "b", "type": "text", "z": 1, "updatedAt": 4},
        ]));
        let once = merge_json(&m, &m).unwrap();
        let twice = merge_json(&once, &once).unwrap();
        assert_eq!(once, twice, "merge(a,a) is stable");
    }

    #[test]
    fn merge_is_commutative_in_content() {
        let local = mirror(json!([
            {"id": "a", "type": "text", "z": 0, "updatedAt": 1},
            {"id": "b", "type": "text", "z": 1, "updatedAt": 9},
        ]));
        let remote = mirror(json!([
            {"id": "a", "type": "text", "z": 0, "updatedAt": 8},
            {"id": "b", "type": "text", "z": 1, "updatedAt": 2},
        ]));
        // Order-independent for the winning block versions (a→remote, b→local).
        let lr = merge_json(&local, &remote).unwrap();
        let rl = merge_json(&remote, &local).unwrap();
        let win = |json: &str, id: &str| {
            PageMirror::parse(json)
                .unwrap()
                .blocks
                .iter()
                .find(|b| b.id == id)
                .unwrap()
                .updated_at
        };
        assert_eq!(win(&lr, "a"), 8);
        assert_eq!(win(&lr, "b"), 9);
        // Byte-identical regardless of argument order (symmetric tie-break).
        assert_eq!(lr, rl, "merge output is order-independent");
    }

    #[test]
    fn equal_timestamp_tie_break_is_symmetric() {
        // Same id, same updatedAt, different content: both merge orders must
        // pick the SAME survivor, else two peers never converge.
        let local = mirror(json!([
            {"id": "a", "type": "text", "z": 0, "updatedAt": 5, "content": {"t": "L"}},
        ]));
        let remote = mirror(json!([
            {"id": "a", "type": "text", "z": 0, "updatedAt": 5, "content": {"t": "R"}},
        ]));
        assert_eq!(
            merge_json(&local, &remote).unwrap(),
            merge_json(&remote, &local).unwrap(),
            "tie-break must not depend on which side is local"
        );
    }

    #[test]
    fn hash_is_independent_of_field_order() {
        // Two mirrors identical except for the ORDER of fields within a block
        // must hash the same (canonical serialization sorts keys). Guards the
        // serde_json default-map (BTreeMap) determinism assumption — review M4.
        let a = r#"{"schema":"onote-page/1","pageId":"p","page":{},
                    "blocks":[{"id":"x","type":"text","updatedAt":1,"x":1,"y":2}]}"#;
        let b = r#"{"schema":"onote-page/1","pageId":"p","page":{},
                    "blocks":[{"y":2,"x":1,"updatedAt":1,"type":"text","id":"x"}]}"#;
        assert_eq!(
            crate::ids::page_content_hash(a).unwrap(),
            crate::ids::page_content_hash(b).unwrap(),
            "field order within a block must not change the hash"
        );
    }

    #[test]
    fn unknown_fields_survive_round_trip() {
        let local = mirror(json!([
            {"id": "a", "type": "text", "z": 0, "updatedAt": 1,
             "someFutureField": {"nested": [1, 2, 3]}},
        ]));
        let remote = mirror(json!([]));
        let merged = merge_json(&local, &remote).unwrap();
        assert!(
            merged.contains("someFutureField"),
            "forward-compat field preserved: {merged}"
        );
    }

    #[test]
    fn page_props_follow_the_newer_side() {
        let local = json!({
            "schema": "onote-page/1", "pageId": "p1",
            "page": {"background": "blank"},
            "blocks": [{"id": "a", "type": "text", "updatedAt": 1}],
        })
        .to_string();
        let remote = json!({
            "schema": "onote-page/1", "pageId": "p1",
            "page": {"background": "grid"},
            "blocks": [{"id": "a", "type": "text", "updatedAt": 100}],
        })
        .to_string();
        let merged = PageMirror::parse(&merge_json(&local, &remote).unwrap()).unwrap();
        assert_eq!(merged.page["background"], json!("grid"));
    }

    #[test]
    fn malformed_input_is_an_error_not_a_panic() {
        assert!(merge_json("{ not json", "{}").is_err());
    }
}
