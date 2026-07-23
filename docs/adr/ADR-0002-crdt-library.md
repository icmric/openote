# ADR-0002: CRDT library — Loro, behind our own Rust API

> **Status:** Accepted (provisional) · 2026-07-22
> **Related:** [File Format Spec §5](../specs/10-file-format-spec.md) · [Architecture §3.3](../04-architecture-overview.md)

## Context

The document model is CRDT-backed from day one (conflict-free multi-device merge now; real-time collaboration later; the CRDT doc is also the on-disk source of truth). Candidates: **Yjs/`yrs`** (largest ecosystem, AppFlowy precedent), **Loro** (Rust-native, movable tree + rich text + time travel), **Automerge** (git-like history). Research finding that reframes the choice: **no CRDT has a production Dart binding** — every option means writing and maintaining our own thin Rust crate exposed through `flutter_rust_bridge`. With integration cost equalized, the decision is about model fit.

## Decision

**Loro**, wrapped in a first-party Rust crate (`onote-core`) exposing a deliberately small, Loro-agnostic API (~20 functions: open/close doc, apply/export update, snapshot, subscribe, tree ops, text ops, value ops). **`yrs` is the documented fallback**, feasible precisely because the app only ever sees `onote-core`'s API.

## Rationale

- **Model fit is unusually good:** Loro's **movable tree** CRDT is exactly the notebook-structure problem (reorder/move sections and pages without conflict) and exactly the block-tree-per-page problem; its rich-text CRDT covers text blocks; snapshot + time-travel gives page version history (SYNC-8) nearly free.
- **Performance where notes hurt:** Loro's documented strength is parse/load of large documents (its benchmarks show order-of-magnitude faster doc-open than Yjs on big docs) — page-open latency is a startup-adjacent priority. Its known trade-off (larger encoded size) is acceptable inside a SQLite container with compaction.
- **Field evidence for our exact stack:** a production report of Loro in Dart/Flutter apps via `flutter_rust_bridge` exists; the Yjs-ecosystem advantage (web editor bindings, y-websocket servers) is worth little to a native Flutter app that isn't using web editors.
- **Automerge rejected** for now: its marquee git-like history is not a headline Openote feature, and it carries the largest wasm/binary footprint of the three.

## Consequences

- We own `onote-core` (small but permanent); Loro's own encoding version is recorded per snapshot/update (`snapshot_v`/`update_v`) so engine upgrades are managed.
- Sync protocol work (deferred spec) will target "opaque update relay" so the server never needs Loro knowledge.
- The **note-shaped benchmark** (long text + hundreds of ink strokes + math blocks; open/apply/export timings + file sizes vs `yrs`) remains a Phase-0 validation task — published CRDT numbers conflict and are workload-dependent.

## Revisit triggers

1. The note-shaped benchmark shows Loro ≥2× worse than `yrs` on page-open or memory for realistic pages.
2. Loro development stalls (no maintained release for 12 months) before Openote 1.0.
3. Yjs wire-protocol compatibility becomes a product requirement (e.g., interop with an external collaboration service).
