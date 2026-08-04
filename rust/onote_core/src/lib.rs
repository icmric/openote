//! # onote-core
//!
//! The Rust core for Openote. Today it owns the parts of the document model
//! that benefit most from a fast, portable, well-tested implementation shared
//! across every platform:
//!
//! * [`mirror`] — the page **mirror** model (the open "glass-box" JSON that the
//!   File Format Spec §4 defines) plus a deterministic, conflict-free
//!   **merge** of two page snapshots. This is the seed of cross-device sync
//!   (SYNC-1/2): exchange page mirrors, merge, converge — no server, no
//!   conflict dialogs. It is intentionally CRDT-*shaped* (commutative,
//!   associative, idempotent over the snapshot exchange) so it can be replaced
//!   by the Loro-backed engine (ADR-0002) behind the same API without changing
//!   call sites.
//! * [`ids`] — a small, dependency-free content hash used to tell whether a
//!   page actually changed (cheap sync gating) and, later, for content-address
//!   dedup.
//! * [`api`] — the thin surface that [`flutter_rust_bridge`] exposes to the
//!   Dart app. Building the bindings is opt-in via the `bridge` feature so the
//!   default `cargo test` needs nothing but a Rust toolchain.
//!
//! ## Why merge lives here, not in Dart
//!
//! The Dart app's `DocumentEngine` seam (see `app/lib/core/engine.dart`) is
//! currently the pure-Dart `MirrorEngine`. Merge is the first piece of that
//! engine to move to Rust because it is (a) hot on the sync path, (b) identical
//! on every OS, and (c) exactly the logic we do *not* want two divergent
//! implementations of. Keeping the Dart fallback intact means shipping never
//! depends on the Rust build being wired up yet — end users still get a plain
//! executable with no Rust runtime requirement.

pub mod api;
pub mod ffi;
pub mod ids;
pub mod mirror;
pub mod onenote;
pub mod onepkg;

/// The crate version, surfaced to the app so a build can report which core it
/// linked. Also the simplest possible end-to-end bridge smoke test.
pub fn core_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// When this library was built, and from which commit: `"<epoch-secs> <sha>"`.
///
/// The answer to "is the library I am running actually the source I am
/// looking at?" — a question git cannot answer, because git describes the
/// source tree and the app loads a compiled artefact. Surfaced in the status
/// bar so a stale build is visible rather than mysterious.
pub fn core_build_id() -> &'static str {
    env!("ONOTE_CORE_BUILD")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_reported() {
        assert_eq!(core_version(), "0.1.0");
    }
}
