//! Dependency-free content hashing.
//!
//! Sync wants a cheap "did this page actually change?" check so it can skip
//! re-sending unchanged pages. A stable content hash over the *canonical* form
//! of a page mirror answers that: two replicas holding the same logical page
//! produce the same hash even if their JSON key order or block order differs.
//!
//! We use FNV-1a (64-bit) — tiny, fast, and deterministic across platforms.
//! It is **not** cryptographic; it is a change detector, not a security
//! primitive. Content-addressed *blob* storage keeps using SHA-256 on the Dart
//! side (`repository.dart`); this is a different, cheaper job.

use crate::mirror::PageMirror;

const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

/// FNV-1a 64-bit hash of raw bytes, hex-encoded.
pub fn content_hash(bytes: &[u8]) -> String {
    let mut hash = FNV_OFFSET;
    for &b in bytes {
        hash ^= b as u64;
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    format!("{hash:016x}")
}

/// A stable hash of a page mirror that ignores incidental JSON formatting and
/// block ordering, so it only changes when the page's *content* changes.
///
/// Returns the parse error for malformed input. Canonicalization: parse →
/// merge with itself (which sorts blocks by `z` then `id` and normalizes the
/// serialization) → hash the resulting bytes.
pub fn page_content_hash(mirror_json: &str) -> Result<String, serde_json::Error> {
    let page = PageMirror::parse(mirror_json)?;
    let canonical = crate::mirror::merge(&page, &page).to_json();
    Ok(content_hash(canonical.as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn known_vector() {
        // FNV-1a/64 of "" is the offset basis; of "a" is a known constant.
        assert_eq!(content_hash(b""), "cbf29ce484222325");
        assert_eq!(content_hash(b"a"), "af63dc4c8601ec8c");
    }

    #[test]
    fn hash_is_order_independent_for_pages() {
        let a = json!({
            "schema": "onote-page/1", "pageId": "p",
            "page": {}, "blocks": [
                {"id": "a", "type": "text", "z": 0, "updatedAt": 1},
                {"id": "b", "type": "text", "z": 1, "updatedAt": 2},
            ],
        })
        .to_string();
        // Same content, blocks listed in the opposite order.
        let b = json!({
            "schema": "onote-page/1", "pageId": "p",
            "page": {}, "blocks": [
                {"id": "b", "type": "text", "z": 1, "updatedAt": 2},
                {"id": "a", "type": "text", "z": 0, "updatedAt": 1},
            ],
        })
        .to_string();
        assert_eq!(
            page_content_hash(&a).unwrap(),
            page_content_hash(&b).unwrap()
        );
    }

    #[test]
    fn hash_changes_when_content_changes() {
        let a = json!({"blocks": [{"id": "a", "type": "text", "updatedAt": 1}]}).to_string();
        let b = json!({"blocks": [{"id": "a", "type": "text", "updatedAt": 2}]}).to_string();
        assert_ne!(
            page_content_hash(&a).unwrap(),
            page_content_hash(&b).unwrap()
        );
    }
}
