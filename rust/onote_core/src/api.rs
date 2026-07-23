//! The Flutter-facing surface.
//!
//! Every function here is a plain Rust function so `cargo test` exercises it
//! directly. When the crate is built with `--features bridge`, the `#[frb]`
//! attributes tell `flutter_rust_bridge_codegen` how to generate the Dart
//! bindings (see `rust/onote_core/README.md`). With the feature off, the
//! attributes vanish and the functions are ordinary Rust — so the default
//! build never depends on the bridge machinery.
//!
//! These are marked `sync`: they are pure, fast, CPU-only transforms, so there
//! is no benefit to the async worker-isolate path — the app can call them
//! straight through.

#[cfg(feature = "bridge")]
use flutter_rust_bridge::frb;

use crate::{ids, mirror};

/// Which core the app linked (smoke test + diagnostics/about screen).
#[cfg_attr(feature = "bridge", frb(sync))]
pub fn core_version() -> String {
    crate::core_version().to_string()
}

/// Merge two page mirrors (local + a copy that arrived from another device)
/// into a single converged mirror. On malformed input, returns the local
/// mirror unchanged and never throws across the bridge — a sync round should
/// degrade gracefully, not crash the editor.
#[cfg_attr(feature = "bridge", frb(sync))]
pub fn merge_page_mirrors(local_json: String, remote_json: String) -> String {
    mirror::merge_json(&local_json, &remote_json).unwrap_or(local_json)
}

/// A stable content hash of a page mirror — cheap "did this page change?"
/// gating for sync. Empty string on malformed input.
#[cfg_attr(feature = "bridge", frb(sync))]
pub fn page_content_hash(mirror_json: String) -> String {
    ids::page_content_hash(&mirror_json).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn merge_bridge_fn_degrades_on_bad_remote() {
        let local = json!({"blocks": [{"id": "a", "type": "text", "updatedAt": 1}]}).to_string();
        // Bad remote → returns local unchanged rather than erroring.
        let out = merge_page_mirrors(local.clone(), "not json".into());
        assert_eq!(out, local);
    }

    #[test]
    fn hash_bridge_fn_is_stable() {
        let m = json!({"blocks": [{"id": "a", "type": "text", "updatedAt": 1}]}).to_string();
        assert_eq!(page_content_hash(m.clone()), page_content_hash(m.clone()));
        assert!(!page_content_hash(m).is_empty());
    }

    #[test]
    fn version_bridge_fn() {
        assert_eq!(core_version(), "0.1.0");
    }
}
