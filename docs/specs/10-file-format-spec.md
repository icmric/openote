# Openote File Format Specification (`.onote`)

> **Document status:** Draft v0.2 (format version `1`) · Last updated 2026-07-27
> **Licence:** **CC0-1.0** ([`LICENSE`](LICENSE)) — ratified in [ADR-0005](../adr/ADR-0005-licensing.md). Implement it freely; no attribution required.
> **Audience:** Openote implementers and third-party tool authors. This document is publishable as the standalone public specification of the format.
> **Related:** [Architecture §5](../04-architecture-overview.md) · [Data Model Spec](11-data-model-spec.md) · [ADR-0003 (container)](../adr/ADR-0003-storage-container.md) · **[ADR-0006 (sync layout)](../adr/ADR-0006-sync-transport-and-text-model.md)**
> **Normativity:** the key words MUST, SHOULD, MAY are used in the RFC 2119 sense. Anything marked *(informative)* is guidance, not a conformance requirement.

> ### ⚠ v0.2 correction: there is no CRDT layer in the container
>
> v0.1 of this spec specified a CRDT layer (`page_docs`, `page_updates`) as the notebook's source of truth, with `page_mirror` as an open JSON *projection* of it — the "glass box". **That layer was never implemented, and it is no longer the plan.**
>
> - **What is actually stored:** `page_mirror` holds page content and is **authoritative**. It is the only copy. `page_docs` was created and written a zero-byte placeholder on every save; `page_updates` and `fts_pages` were created and never touched at all. As of 2026-07-27 none of the three is created or written.
> - **Why the plan changed:** [ADR-0006](../adr/ADR-0006-sync-transport-and-text-model.md) found that consumer file-sync services (Drive, OneDrive, rsync) replicate *whole files* and resolve conflicts by making a second copy — so a single large SQLite file that every edit rewrites is close to the worst possible sync unit. The operation log therefore moves **out of the container and into files**, inside a `.onotebook` directory, where one-writer-per-file makes conflicts structurally impossible.
> - **Where this is heading:** the container becomes a **local, never-synced, rebuildable cache** of that log (§9). The openness guarantee moves with it: the log and its documented materialisation become the durable open artifact, rather than a JSON mirror kept inside a binary container.
>
> §5 is retained below, marked superseded, because implementations of v0.1 may exist and readers deserve to know what those bytes were meant to be.

---

## 1. Design goals & non-goals

**Goals** (traceable to PRD OPEN-1…12):
1. **Openness in practice, not just on paper.** Every byte is either a well-known open format (SQLite, JSON, Markdown, LaTeX, PNG/JPEG/…) or a structure fully described in this document. A competent developer MUST be able to write a read-only implementation from this spec alone, without reading Openote's source.
2. **Crash-safety and partial recoverability.** A power cut mid-write MUST NOT corrupt the notebook. Damage to one page MUST NOT take down the rest.
3. **Local-first, and honest about sync.** These structures serve single-device use well. They are *not* the multi-device merge unit — that lives outside the container by design ([ADR-0006](../adr/ADR-0006-sync-transport-and-text-model.md), §11), because a format that every edit rewrites wholesale cannot be merged by the file-sync services people actually use.
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

-- ── Page content (§4) ─────────────────────────────────────────────
-- AUTHORITATIVE. One row per page holding the complete block tree as
-- JSON (Data Model Spec §8). This is the only copy of a page's content
-- in the container; it is not a projection of anything.
--
-- The name is historical: v0.1 of this spec placed a CRDT layer
-- (`page_docs`, `page_updates`) underneath and called this its open
-- "mirror". That layer was never implemented and has been superseded
-- (see the v0.2 correction at the top, and §5). The table keeps its
-- name so that every notebook ever written stays readable.
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

-- ── Full-text search (FTS5; OPTIONAL, rebuildable cache) ──────────
-- NOT created by default as of v0.2: Openote created this table on every
-- open and never wrote a row to it, which advertised a search index that
-- held nothing. A writer implementing notebook-wide search SHOULD create
-- and populate it, and MUST declare "fts_pages" in notebook_meta.features
-- so readers can tell a populated index from an absent one.
--
-- CREATE VIRTUAL TABLE fts_pages USING fts5(
--   title, body,                    -- extracted plain text per page
--   content='', tokenize='unicode61 remove_diacritics 2'
-- );
--
-- Implementations targeting CJK substring search SHOULD add a parallel
-- trigram-tokenized table. FTS content is derivable; corruption here is
-- repaired by rebuild, never data loss.

-- ── Page version history (SYNC-8) — WITHDRAWN in v0.17 ────────────
--
-- `page_versions` kept up to thirty complete copies of every page. It was
-- bounded by how long a notebook had been edited, i.e. by nothing (measured:
-- 9,840 snapshots in a 322 MB container), it declared no foreign key onto
-- `nodes` so a purged page's snapshots outlived it for good, and it pinned
-- media from garbage collection by accident and permanently. It is no longer
-- created; Openote's opt-in storage migration drops it from containers that
-- have it. A reader MAY still meet the table in an older notebook and MUST
-- treat it as optional.
--
-- CREATE TABLE page_versions (
--   page_id    TEXT NOT NULL,
--   version_at INTEGER NOT NULL,
--   snapshot   BLOB NOT NULL,
--   label      TEXT,
--   PRIMARY KEY (page_id, version_at)
-- );
```

### 3.1 `notebook_meta` required keys
`format` (`{"major":1,"minor":0}`) · `notebook_id` (UUIDv7) · `title` · `created_at` · `app` (creator app + version string, informative) · `features` (JSON array of optional-capability strings a writer used, e.g. `["page_versions","fts_pages"]`; readers MUST ignore unknown feature names but MUST NOT destroy data belonging to features they don't implement) · `content` (where page content authoritatively lives; `"page_mirror"` for this version — a reader that does not recognise the value MUST NOT write).

*(Informative)* v0.1 also specified `dirty_mirror`, a flag a third-party writer set to ask Openote to reconcile its JSON edits back into the CRDT. With no CRDT there is nothing to reconcile, so it is no longer written; readers should ignore it if present.

### 3.2 Layer classification *(informative but important)*
| Layer | Tables | On corruption |
|---|---|---|
| **Source of truth** | `page_mirror`, `nodes`, `blobs`, `blob_refs` | data loss possible — protected by WAL + backups |
| **Projection** (rebuildable from truth) | `refs`, `fts_pages` (if present) | rebuild, no loss |
| **Optional** | `page_versions` *(withdrawn v0.17 — see §3; no longer created)*, `block_authors`, `recent_deletions` *(both derived from the op log, rebuildable, never synced)* | feature degrades |

This delivers OPEN-11 (partial recoverability) more directly than v0.1 did: a reader that understands *only* SQLite + JSON has everything, because there is no second, opaque representation to be the "real" one. Damage is also naturally page-scoped — one unparseable `page_mirror.json` costs that page, not the notebook.

*(Informative)* Note the honest trade this makes. A whole page's JSON is rewritten on every save, so the smallest representable edit is "the page is now this". That is affordable for a single device — and it is precisely why it cannot be the sync unit. See §11.

## 4. Page content and the openness guarantee

`page_mirror` holds one row per page: the complete block tree in the **Page JSON schema** (Data Model Spec §8) — positions, text as Markdown-with-extensions, math as LaTeX, ink as stroke arrays, embeds as refs + snapshot pointers.

- A writer MUST regenerate the row on every page save, and MUST write it inside the same transaction as the `refs` and `blob_refs` projections it implies, so a reader never sees content and index disagree.
- `mirror_rev` MUST increase monotonically per page on each write. Readers MAY use it to detect change; they MUST NOT assume it counts edits.
- **Third-party writers need nothing but SQLite and JSON.** There is no second representation to keep in step, no CRDT library to link, and no reconciliation flag to set. This is a straightforward improvement on v0.1, which asked third-party writers either to link a Loro-compatible library or to accept a documented lossy "mirror-write mode".
- A reader MUST preserve fields it does not understand when rewriting a block (Data Model Spec forward-compatibility rule). This is the mechanism by which a third-party tool can safely edit a notebook written by a newer Openote.

## 5. CRDT encoding — ⚠ SUPERSEDED, never implemented

> **This section describes v0.1's intended design and is retained for the historical record only.** No Openote release ever wrote these structures: `page_docs` received a zero-byte placeholder and `page_updates` was never written. [ADR-0006](../adr/ADR-0006-sync-transport-and-text-model.md) moved the operation log out of the container entirely — see §11. A reader encountering a v0.1 notebook will find these tables present, empty of meaning, and safe to ignore.

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
`file` is a path **relative to the workspace directory** when the notebook lives inside it, and absolute otherwise. For a notebook in the classic layout that relative path is exactly the basename, which is what every registry written before v0.17 holds.

`format.major` is **2** once the workspace holds a notebook whose container has been demoted to a working copy (§11), and **1** otherwise. A reader that meets a higher `format.major` than it understands MUST load the entries and MUST NOT write the file back: `file` paths it cannot represent would be rewritten as something else, and any entry whose file it cannot find would be dropped — which is how a build that predates the demotion would silently prune every migrated notebook from a user's list.

Notebooks are discoverable without the registry (directory scan); the registry adds ordering, colors, and id→file resolution for cross-notebook refs.

Two further files may appear in the workspace root, both **runtime state, not data**. A third-party reader MUST ignore them, and deleting them while Openote is closed loses nothing:

| File | What it is |
|---|---|
| `.instance-lock` | Held open, and exclusively locked, by the one running Openote for this workspace. Its contents are that process's id, for diagnosis only — the lock, not the number, is the claim, so a crashed process releases it automatically. |
| `.open-request` | Present for a moment only: a second launch writes `{"path": …, "at": …}` here to hand a double-clicked notebook to the instance that holds the lock, and the holder deletes it as its acknowledgement. |

Why the workspace is single-instance at all: this container is a WAL SQLite database rewritten on every save, and `workspace.json` above is rewritten wholesale. Two processes over one workspace lose notebooks (last writer wins the registry) and risk the container corruption §11 and ADR-0006 §3 describe. Associating `.onote` with the app made a second process one double-click away, so the lock arrived with the association.

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

A minimal third-party **writer**: write `page_mirror.json` and the `nodes` row, in one transaction, preserving any fields you don't understand (§4). Nothing else is required — no flag to set, no second representation to keep in step.

## 11. Where this format is going *(informative)*

Stated plainly, because a spec that hides its own direction is not open in any useful sense.

This container is an excellent **single-device** format and a poor **sync unit**. Both facts have the same cause: it is one large binary that every edit rewrites. Consumer file-sync services (Google Drive, OneDrive, Dropbox, rsync/WebDAV) replicate whole files and resolve conflicts by making a second copy, so two devices editing *different pages* of one notebook produce two whole-file versions whose edits are, by then, indistinguishable. Nothing downstream can merge them. WAL compounds it: `-wal`/`-shm` are only meaningful paired with the database at the same instant.

[ADR-0006](../adr/ADR-0006-sync-transport-and-text-model.md) therefore moves the durable unit **out of SQLite and into files**:

```
MyNotebook.onotebook/            ← what a sync client replicates
  manifest.json     ← notebook id, format version, device registry
  ops/<device>.oplog  ← append-only. ONE writer, ever.
  blobs/<sha256>    ← content-addressed, immutable

<workspace>/.cache/<notebook-id>/
  cache.onote       ← THIS container, demoted: local-only, never synced,
                      rebuildable from the logs at any time
```

> **Corrected 2026-08-16 (v0.17 Step 8, landed).** This diagram used to draw
> `cache.onote` **inside** `MyNotebook.onotebook/`, matching ADR-0006 §3 as first
> written. That is wrong and the ADR is amended: the `.onotebook` is the
> directory Drive, OneDrive, Dropbox and Syncthing replicate file by file, so a
> live WAL SQLite database inside it re-creates the torn-database hazard the
> whole design exists to avoid — measured on the owner's own Drive at
> 31,954,368 bytes of `.onote` + `-wal` + `-shm` being replicated. The working
> copy lives under the local workspace, keyed by notebook id, and is stamped
> `user_version = 2` so that any build meeting one knows it is not a notebook.

The load-bearing property is **one writer per file**, which makes the conflicting-versions case structurally impossible rather than resolved-after-the-fact. Merging becomes reading: concatenate the logs, order the operations, apply.

Two consequences matter to third-party implementers:

1. **The openness guarantee moves to the log.** The op log and its documented materialisation become the artifact you read to recover a notebook without Openote. This container stops being a compatibility surface at all, because it can always be regenerated. That is a *stronger* openness position than v0.1's, not a weaker one — the open representation stops being a copy kept alongside an opaque one, and becomes the thing itself.
2. **Sync granularity is per notebook**, with the manifest deliberately shaped so a section subset can be described later without a format migration (decided 2026-07-27).

Until that lands, `.onote` as specified above is the format, and notebooks written today remain readable: the migration path is "rebuild the cache from a log seeded by the existing container", which loses nothing.

**One caveat for anyone reading a `.onotebook` today.** Until the demotion lands, the container is authoritative and `blobs/` is a shadow copy — so it is written **only for notebooks that are shared** (in a sync folder, or mirrored). A local-only notebook has a complete `ops/` and an absent or sparse `blobs/`: the `blob.put` ops name every image, the bytes live in the container's `blobs` table, and Openote copies them out the moment the notebook starts syncing. Concretely: *a `.onotebook` you were given by another device is complete; a `.onotebook` sitting beside its `.onote` on the machine that made it may not be, and the `.onote` beside it is why that is not data loss.* This is a property of shadow mode, not of the format — after the demotion, `blobs/` is the only home and is always complete.

## 12. Compatibility promise and changelog

**From v0.2.0 onward, format v1 is frozen.** Notebooks created by any Openote release open in every later release. A future change that cannot be made compatibly bumps the format major version and migrates one-way-forward, with the migration documented here.

What "frozen" binds:

| Surface | Frozen | Notes |
|---|---|---|
| `page_mirror.json` shape (`schema`, `pageId`, `page`, `blocks`) | ✅ | The block envelope's known fields; unknown fields MUST round-trip (Data Model Spec §2). |
| `nodes`, `blobs`, `blob_refs`, `refs` columns | ✅ | Columns may be ADDED; existing ones keep their meaning. `page_versions` was on this list until v0.17 withdrew the table (§3). |
| `application_id` / `user_version` | ✅ | `0x4F4E4F54` / **`1` for a notebook file**. **`2` means Openote's own local working copy**, not a notebook: its `blobs` table may be empty and its only guarantee is that it can be rebuilt from the log beside it. A reader that does not understand `2` MUST refuse the file rather than open it — which every release before v0.17 already does, since its gate is `user_version > 1`. |
| `notebook_meta` required keys | ✅ | Readers MUST ignore unknown keys. |
| Op-log envelope (`v`, `dev`, `seq`, `lc`, `ts`, `enc`, `op`, `d`) and the total order | ✅ | New **op kinds** are additive and do not bump `v`; a reader that meets an unknown kind MUST preserve it verbatim and MAY skip applying it. |
| `.onotebook` directory layout (`manifest.json`, `ops/`, `blobs/`) | ✅ | |
| `fts_pages` | ❌ optional | Not created by default; declare it in `notebook_meta.features` if populated. |

### Changelog

- **v0.17 (container `user_version` 2 for working copies; `workspace.json` format 2)** — the container is demoted to a local, rebuildable working copy at `<workspace>/.cache/<notebook-id>/cache.onote` (§11). A notebook file is still v1 and still opens everywhere; **v2 is only ever a working copy**, and the migration that produces one is opt-in per notebook and reversible from inside the app, except that `page_versions` is dropped and cannot be restored (§3). `workspace.json` is stamped `format.major = 2` only once a workspace actually contains a demoted notebook, so an older build keeps full use of a registry it can still write safely; when it meets a 2 it loads the list read-only rather than rewriting it. The registry's `file` field is now a path **relative to the workspace**, which for every notebook in the classic layout is byte-identical to the basename it has always been.
- **v0.2.0 (format v1, spec v0.2)** — first frozen release. Corrected from spec v0.1: the CRDT layer (`page_docs`, `page_updates`) is not part of the format and never was implemented; `page_mirror` is authoritative; `dirty_mirror` retired; `fts_pages` optional. Added: the `.onotebook` operation log (§11) with the `ink.strokes`, `node.*`, `block.*`, `page.props`, `blob.put` and `notebook.meta` op kinds.

---

*Superseded: "Format version 1 is frozen only when the MVP ships." It ships with v0.2.0, and the promise above replaces that note.*
