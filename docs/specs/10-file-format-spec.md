# Openote File Format Specification (`.onote`)

> **Document status:** Draft v0.1 (format version `1`) · Last updated 2026-07-22
> **Audience:** Openote implementers and third-party tool authors. This document is written to be publishable as the standalone, permissively-licensed public specification of the format ([ADR-0005](../adr/ADR-0005-licensing.md) proposes CC0/MIT for this spec).
> **Related:** [Architecture §5](../04-architecture-overview.md) · [Data Model Spec](11-data-model-spec.md) · [ADR-0002 (CRDT)](../adr/ADR-0002-crdt-library.md) · [ADR-0003 (container)](../adr/ADR-0003-storage-container.md)
> **Normativity:** the key words MUST, SHOULD, MAY are used in the RFC 2119 sense. Anything marked *(informative)* is guidance, not a conformance requirement.

---

## 1. Design goals & non-goals

**Goals** (traceable to PRD OPEN-1…12):
1. **Openness in practice, not just on paper.** Every byte is either a well-known open format (SQLite, JSON, Markdown, LaTeX, PNG/JPEG/…) or a structure fully described in this document. A competent developer MUST be able to write a read-only implementation from this spec alone, without reading Openote's source.
2. **Crash-safety and partial recoverability.** A power cut mid-write MUST NOT corrupt the notebook. Damage to one page MUST NOT take down the rest.
3. **Local-first & sync-ready.** The same structures serve single-device use and CRDT-based multi-device merge.
4. **No artificial limits** on notebook, section, page, or attachment size.
5. **Longevity.** All layers chosen for archival credibility (SQLite is a Library-of-Congress-recommended storage format; JSON/Markdown/LaTeX are ubiquitous).

**Non-goals:** human-readability of the *container* itself (that is what the open-folder export in §8 is for); wire-format stability of internal CRDT bytes across major versions (§5.4 defines the escape hatch).

## 2. Container overview

An Openote **notebook** is a single file with the `.onote` extension: a **SQLite 3 database** using the standard SQLite file format.

- Implementations MUST set `application_id = 0x4F4E4F54` ("ONOT") and use `user_version` for the **format major version** (this spec: `1`). A reader encountering a higher major version than it understands MUST refuse to write and SHOULD open read-only if it can.
- Databases MUST use WAL journal mode when writable (crash-safety, concurrent readers). `foreign_keys` MUST be ON.
- Text encoding is UTF-8 throughout. All timestamps are **Unix epoch milliseconds, UTC** (`INTEGER`). All identifiers are **UUIDv7** in canonical lowercase string form (§3 of the Data Model Spec explains why v7: time-ordered, index-friendly).
- A **workspace** (the user's whole world) is a directory of `.onote` files plus a small `workspace.json` (§7). Notebooks are self-contained: moving/copying a `.onote` file moves the whole notebook, attachments included.

*(Informative)* Why one file per notebook: it fixes OneNote's fragile one-file-per-section model (the seam of most corruption reports), keeps the "email me the notebook" document metaphor, and gives ACID transactions over every page in the notebook. SQLite-as-application-file-format trade-offs are discussed in Architecture §5.2.

## 3. Schema (normative DDL, format version 1)

```sql
-- ── Identity & metadata ────────────────────────────────────────────
CREATE TABLE notebook_meta (
  key   TEXT PRIMARY KEY,          -- see §3.1
  value TEXT NOT NULL              -- JSON-encoded
);

-- ── Structure: section groups / sections / pages ──────────────────
-- The org tree lives in ONE CRDT document ("structure doc", §5.2).
-- These tables are a QUERYABLE PROJECTION of it, rebuilt from the CRDT
-- on write; readers MAY treat them as authoritative for read-only use.
CREATE TABLE nodes (
  id         TEXT PRIMARY KEY,     -- UUIDv7
  kind       TEXT NOT NULL CHECK (kind IN ('section_group','section','page')),
  parent_id  TEXT REFERENCES nodes(id) ON DELETE CASCADE,  -- NULL = root
  title      TEXT NOT NULL DEFAULT '',
  position   TEXT NOT NULL,        -- fractional-index string; sorts lexicographically
  color      TEXT,                 -- section tab color token, optional
  level      INTEGER NOT NULL DEFAULT 0,  -- pages: subpage indent 0..2
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER               -- soft delete → recycle bin (ORG-7)
);
CREATE INDEX idx_nodes_parent ON nodes(parent_id, position);

-- ── Page content: one CRDT document per page ──────────────────────
CREATE TABLE page_docs (
  page_id     TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
  snapshot    BLOB NOT NULL,       -- CRDT snapshot (Loro export; §5)
  snapshot_v  INTEGER NOT NULL,    -- CRDT-encoding version tag (§5.4)
  updated_at  INTEGER NOT NULL
);
CREATE TABLE page_updates (        -- incremental CRDT updates since snapshot
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  page_id   TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  update_v  INTEGER NOT NULL,
  bytes     BLOB NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_updates_page ON page_updates(page_id, id);

-- ── Open-format mirror (the "glass box"; §4) ──────────────────────
-- A per-page JSON projection of the block tree, regenerated on save.
-- Third-party READERS should start here: no CRDT knowledge required.
CREATE TABLE page_mirror (
  page_id    TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
  json       TEXT NOT NULL,        -- Page JSON, schema in Data Model Spec §8
  mirror_rev INTEGER NOT NULL,     -- monotonically increasing per page
  updated_at INTEGER NOT NULL
);

-- ── Blobs: images, attachments, snapshot caches ───────────────────
CREATE TABLE blobs (
  hash       TEXT PRIMARY KEY,     -- lowercase hex SHA-256 of content
  bytes      BLOB NOT NULL,
  mime       TEXT NOT NULL,
  size       INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);                                  -- content-addressed, deduplicated
CREATE TABLE blob_refs (            -- which pages use which blobs (GC roots)
  page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  hash    TEXT NOT NULL REFERENCES blobs(hash),
  PRIMARY KEY (page_id, hash)
);

-- ── Links & embeds index (backlinks, delete-warnings; §6) ─────────
CREATE TABLE refs (
  src_page_id  TEXT NOT NULL,      -- page containing the link/embed
  src_block_id TEXT NOT NULL,
  kind         TEXT NOT NULL CHECK (kind IN ('link','embed')),
  dst_page_id  TEXT NOT NULL,      -- may point into another notebook (§6.1)
  dst_notebook TEXT,               -- NULL = this notebook
  dst_target   TEXT,               -- JSON EmbedTarget (Data Model Spec §7)
  PRIMARY KEY (src_page_id, src_block_id, kind)
);
CREATE INDEX idx_refs_dst ON refs(dst_page_id);

-- ── Full-text search (FTS5; rebuildable cache) ────────────────────
CREATE VIRTUAL TABLE fts_pages USING fts5(
  title, body,                      -- extracted plain text per page
  content='', tokenize='unicode61 remove_diacritics 2'
);
-- Implementations targeting CJK substring search SHOULD add a parallel
-- trigram-tokenized table. FTS content is derivable; corruption here is
-- repaired by rebuild, never data loss.

-- ── Page version history (SYNC-8; optional table, MAY be absent) ──
CREATE TABLE page_versions (
  page_id    TEXT NOT NULL,
  version_at INTEGER NOT NULL,
  snapshot   BLOB NOT NULL,
  label      TEXT,
  PRIMARY KEY (page_id, version_at)
);
```

### 3.1 `notebook_meta` required keys
`format` (`{"major":1,"minor":0}`) · `notebook_id` (UUIDv7) · `title` · `created_at` · `app` (creator app + version string, informative) · `features` (JSON array of optional-capability strings a writer used, e.g. `["page_versions","trigram_fts"]`; readers MUST ignore unknown feature names but MUST NOT destroy data belonging to features they don't implement).

### 3.2 Layer classification *(informative but important)*
| Layer | Tables | On corruption |
|---|---|---|
| **Source of truth** | `page_docs`, `page_updates`, structure CRDT (in `notebook_meta`/§5.2), `blobs`, `blob_refs` | data loss possible — protected by WAL + backups |
| **Projection** (rebuildable from truth) | `nodes`, `page_mirror`, `refs`, `fts_pages` | rebuild, no loss |
| **Optional** | `page_versions` | feature degrades |

This layering is what delivers OPEN-11 (partial recoverability): a reader that understands *only* SQLite + JSON can recover all content from `page_mirror` + `blobs` even if every CRDT byte were unreadable.

## 4. The open-format mirror (the "glass box")

The CRDT bytes are efficient but opaque; the **mirror** is the openness guarantee *inside* the container:

- On every page save, the writer MUST regenerate `page_mirror.json` — the complete block tree of the page in the **Page JSON schema** (Data Model Spec §8): positions, text as Markdown-with-extensions, math as LaTeX, ink as stroke arrays, embeds as refs + snapshot pointers.
- The mirror MUST be byte-for-byte derivable from the CRDT state (it is a pure projection; no information exists only in the mirror).
- Third-party tools SHOULD read the mirror and MUST NOT need to parse CRDT bytes for read-only access. Third-party *writers* have two conformant options: (a) full fidelity — apply CRDT updates via a Loro-compatible library; (b) **mirror-write mode** — modify `page_mirror` and set `notebook_meta.dirty_mirror=true`; Openote reconciles the mirror into the CRDT on next open (documented, lossy-for-concurrent-edits, but it keeps the format writable with nothing but SQLite + JSON).

## 5. CRDT encoding

### 5.1 Engine
Format v1 uses **Loro** ([ADR-0002](../adr/ADR-0002-crdt-library.md)); `snapshot` and `page_updates.bytes` contain Loro's documented export formats (`snapshot_v`/`update_v` carry Loro's own encoding version).

### 5.2 Document layout
- **Structure doc** (one per notebook, stored under `notebook_meta` key `structure_doc` as base64, with incremental updates in `page_updates` under the reserved page id `00000000-0000-0000-0000-000000000000`): a Loro **movable tree** of section-groups/sections/pages + a map of node attributes. The `nodes` table is its projection.
- **Page docs** (one per page): a Loro tree of **blocks**; each block a map (`type`, transform, type-specific fields); text content as Loro rich text; ink stroke arrays and other bulk values as Loro values or blob-refs. Full mapping in Data Model Spec §8.3.

### 5.3 Compaction
Writers SHOULD fold `page_updates` into a fresh `snapshot` when updates exceed a threshold (RECOMMENDED: 512 updates or 4 MiB) and MUST do so such that a crash mid-compaction leaves either the old or the new state intact (single transaction).

### 5.4 Version escape hatch
If a future major version changes CRDT engine or encoding, migration MUST be one-way-forward with the mirror as the bridge: old-format readers keep the mirror; the migrator rebuilds fresh CRDT docs from mirrors. This bounds the blast radius of the one deliberately non-eternal layer in the format.

## 6. Links, embeds & cross-notebook references

- The `refs` table indexes every outgoing link/embed for backlinks (TEXT-8) and delete-time warnings (EMBED-6). It is a projection; the truth lives in the blocks.
- **6.1 Cross-notebook refs** carry `dst_notebook` = target notebook UUID. Resolution is via the workspace registry (§7); a missing notebook renders as a dangling ref with snapshot fallback (never an error state that blocks the page).
- Embed snapshot caches are stored as `blobs` entries (mime `application/x-onote-snapshot+json`) referenced from the embed block — so tombstone rendering and offline embeds survive source deletion, per Data Model Spec §7.

## 7. The workspace

`workspace.json` (in the workspace directory root):
```json
{
  "format": {"major": 1, "minor": 0},
  "workspace_id": "0198f3c2-…",
  "notebooks": [
    {"id": "0198f3c2-…", "file": "Research.onote", "color": "ink-500"}
  ],
  "settings": {}
}
```
Notebooks are discoverable without the registry (directory scan); the registry adds ordering, colors, and id→file resolution for cross-notebook refs.

## 8. Open-folder export ("materialize")

Every implementation MUST offer a lossless-where-possible export of a notebook to a plain folder:

```
Research/
├── notebook.json                  # structure tree, ids, titles, order
├── pages/<page-title>.<id8>/      # one directory per page
│   ├── page.json                  # the Page JSON mirror, verbatim
│   ├── page.md                    # Markdown projection (lossy: layout flattened)
│   └── canvas.json                # JSON-Canvas-compatible projection (§9)
└── assets/<hash>.<ext>            # blobs, content-addressed filenames
```

`page.json` is the fidelity path (everything round-trips); `page.md` and `canvas.json` are convenience projections. Export MUST be available on every platform (OPEN-7; the anti-OneNote guarantee).

## 9. Interoperability projections

- **JSON Canvas:** `canvas.json` maps blocks → JSON Canvas 1.0 nodes (`text`, `file`, `link`, `group`); Openote-specific data (ink, math, embeds) exports as rendered assets + an `x-onote` extension key that conformant JSON Canvas readers ignore. Frames map to `group` nodes.
- **Math:** LaTeX in place; MathML on demand (Math Input Spec §6).
- **Ink:** InkML export per Ink Data Spec §6.
- **Markdown:** CommonMark + GFM tables/tasks + documented extensions (Data Model Spec §5.2).

## 10. Conformance checklist *(informative)*

A minimal third-party **reader**: open SQLite → check `application_id`/`user_version` → read `nodes` for the tree → read `page_mirror.json` per page → resolve `blobs` by hash. No CRDT, no Rust, no Openote code.

A minimal third-party **writer**: mirror-write mode (§4) + `dirty_mirror` flag.

A full peer: implements §5 (Loro encodings) and the reconciliation rules in the Data Model Spec.

---

*Format version 1 is frozen only when the MVP ships; until then this spec tracks the implementation. Changes are recorded in a changelog section from the first frozen release onward.*
