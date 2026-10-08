# ADR-0002: CRDT library — Loro, behind our own Rust API

> **Status:** Accepted, **not implemented**. Loro has never been a dependency.
> **Related:** [ADR-0006](ADR-0006-sync-transport-and-text-model.md) · [Data Model §5.1](../specs/11-data-model-spec.md)
>
> **What changed under it.** This was decided when the CRDT document was going
> to be the on-disk source of truth. [ADR-0006](ADR-0006-sync-transport-and-text-model.md)
> replaced that with an append-only op log, which took over two of the four
> reasons Loro was chosen: the **movable tree** that was going to order sections
> and pages is now `node.*` ops over fractional indices, and the **snapshot and
> time-travel** that was going to give version history is now a replay of the
> log. The container stores no CRDT at all.
>
> So the decision stands but its **scope has narrowed to one thing: the text
> sequence.** Two text edits to one paragraph still resolve last-writer-wins,
> which is the one problem nothing else has solved, and `block.patch` narrows
> the cost of a keystroke without converging. The open question this leaves is
> worth stating rather than inheriting: **Loro was chosen largely on
> movable-tree model fit, and that is no longer what it would be for.** A
> choice made for text alone should be re-argued, against `yrs` and Automerge
> on rich-text merge quality and binding cost, before anyone integrates
> anything. The one assumption already known to be wrong is the integration
> path — this assumed `flutter_rust_bridge`, and `onote_core` is reached by
> hand-written `dart:ffi`.

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

1. **Anyone starting the text-sequence work.** The narrowed scope above means
   the original comparison no longer decides this; redo it for text.
2. The note-shaped benchmark shows Loro ≥2× worse than `yrs` on page-open or memory for realistic pages.
3. Loro development stalls (no maintained release for 12 months).
4. Yjs wire-protocol compatibility becomes a product requirement — interop with an external collaboration service, say.
