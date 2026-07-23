# ADR-0003: Storage container — SQLite `.onote` package with an open-folder export

> **Status:** Accepted (provisional) · 2026-07-22
> **Related:** [File Format Spec](../specs/10-file-format-spec.md) · [Architecture §5](../04-architecture-overview.md)

## Context

Three container strategies were mapped in Architecture §5.2: (A) folder of plain files (Obsidian model — maximal portability, weak transactions), (B) SQLite as the application file format (Trilium model — ACID, single-file, but "not plain files"), (C) CRDT-native bundle (AFFiNE model — merge-for-free, but opaque). OneNote's one-`.one`-file-per-section design — the seam of its notorious corruption — is the anti-pattern to avoid. The Logseq Markdown→DB migration saga shows what happens when this choice is made casually and reversed later.

## Decision

**One SQLite database per notebook (`.onote`)** containing the CRDT source of truth, a **JSON mirror** of every page (the in-container openness guarantee), content-addressed blobs, and rebuildable projections (tree, refs, FTS) — plus a mandated **lossless open-folder export** ("materialize") available on every platform. Access from Dart via `drift` over the bundled `sqlite3` (FTS5 included; SQLCipher drop-in for future at-rest encryption).

## Rationale

- **Crash-safety is a headline requirement** (PLAT-9, OPEN-11) and SQLite's ACID/WAL semantics are the strongest crash story available in an embeddable store — directly attacking OneNote's #1 complaint class (sync/corruption).
- **Single file per notebook** keeps the document metaphor (move/email/back-up one file, attachments included) while eliminating per-section fragility.
- **The openness objection to B is answered structurally, twice:** the `page_mirror` JSON inside the container lets any SQLite+JSON reader recover everything without CRDT knowledge; the open-folder export materializes plain Markdown/JSON/assets on demand. Openness is provided by *specification + mirror + export*, not by making the working format inefficient.
- **B+C hybrid:** storing CRDT snapshots/updates *in* SQLite gets C's merge properties without C's opacity, and incremental row writes beat rewriting a ZIP bundle on every save.
- Strategy A was rejected as the *working* format: no transactions (crash mid-multi-file-write corrupts), thousands-of-small-files performance, and CRDT history has no clean home — but A *is* the export target, so its portability benefits are retained where they matter (leaving, archiving, grepping).

## Consequences

- "Your notes are just files" purists get the materialize export, not the working directory; docs must communicate this honestly.
- Whole-file cloud-drive sync of a live `.onote` is a documented anti-pattern (like syncing any live database); Openote sync (P2) exchanges CRDT updates instead, and a "synced-folder" transport ships with explicit safe-usage semantics.
- Blob GC, mirror-rebuild, and FTS-rebuild maintenance routines are part of the storage layer's contract from day one.

## Revisit triggers

1. MVP dogfooding shows unacceptable notebook-open times at realistic sizes (>500 pages) that schema tuning can't fix.
2. The mirror-write third-party path (File Format Spec §4) proves unusable for real integrations, undermining the openness claim.
