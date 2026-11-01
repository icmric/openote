# Openote File Format Specification

> **Format version 1**, frozen since v0.2.0: a notebook written by any release
> opens in every later one (§11).
> **Licence: CC0-1.0** ([`LICENSE`](LICENSE)). Implement it freely, no
> attribution required.
> **Audience:** anyone writing a tool that reads or writes Openote notebooks.
> This document is the whole specification — you should not need to read
> Openote's source.
> **Normativity:** MUST, SHOULD and MAY are used in the RFC 2119 sense. Anything
> marked *(informative)* is guidance, not a conformance requirement.
> **Related:** [Data model](11-data-model-spec.md) · [Maths](12-math-input-spec.md) · [Ink](13-ink-data-spec.md) · [ADR-0006](../adr/ADR-0006-sync-transport-and-text-model.md)

---

## 1. Goals

1. **Openness in practice.** Every byte is either a well-known open format —
   SQLite, JSON, Markdown, LaTeX, PNG/JPEG — or a structure described here. A
   competent developer MUST be able to write a read-only implementation from this
   document alone.
2. **Crash-safety and partial recoverability.** A power cut mid-write MUST NOT
   corrupt a notebook, and damage to one page MUST NOT take down the rest.
3. **Mergeable by dumb file sync.** Google Drive, OneDrive, Dropbox and rsync
   replicate whole files and resolve conflicts by making a second copy. The
   durable unit is therefore shaped so **no two writers ever touch the same
   file** (§3).
4. **No artificial limits** on notebook, section, page or attachment size.
5. **Longevity.** Every layer was chosen for archival credibility.

**Non-goal:** human-readability of the SQLite container. That is what the
open-folder export in §7 is for.

## 2. A notebook is a directory

```
Physics.onotebook/
├── Open this notebook.onotelink   # what a person double-clicks
├── manifest.json                  # id, format version, sync scope, devices
├── ops/
│   └── <device-id>.oplog          # append-only. ONE writer, ever.
├── blobs/
│   └── <sha256>.blob              # content-addressed, immutable
└── media/
    └── <uuid>.<ext>               # video and audio: files, not blobs
```

**Copying this directory copies the whole notebook.** It is self-contained, it is
what a sync client replicates, and it is the unit of sharing.

Beside it there is usually a `Physics.onote` — a SQLite database (§4). **That
file is a cache**: a queryable projection of the log, rebuildable from it at any
time, and **each device makes its own**. A reader MAY use it as a fast path and
MUST NOT treat it as the source of truth.

> **⚠ Changed in v0.17.** Earlier versions of this specification said a notebook
> was the `.onote` file, and that copying one moved the notebook "attachments
> included". That stopped being true when blob bytes moved out of the container,
> so copying a `.onote` on its own loses every picture, PDF and ink stroke.
> **This cost real data**, including some of this project's own. If you have a
> tool that copies `.onote` files, copy the directory instead.

### 2.1 `.onotelink`

A small text pointer whose only job is to be double-clickable, so that opening a
notebook does not mean knowing which file inside a folder to pick. It is
**derived, not data**: deleting it loses nothing and the app rewrites it. A
reader MAY ignore it entirely.

## 3. The operation log

The log is the notebook. Everything else here is either a projection of it or a
place bytes live.

Each device appends to **its own file and no other**, named for its device id.
That one property is what makes conflicts structurally impossible rather than
resolved after the fact: two devices can never produce competing versions of one
file, so a sync client has nothing to disambiguate. Merging is reading —
concatenate the logs, order the operations, apply.

**Encoding is JSON Lines**: one complete JSON object per line, UTF-8, `\n`
separated. A torn or partially flushed tail costs the last line, not the file,
which matters because logs are appended to constantly and replicated by
processes nobody controls. A reader MUST tolerate a trailing partial line and
SHOULD decode leniently.

Operations are **never deleted or rewritten**, and the log is not compacted.

### 3.1 `manifest.json`

```json
{
  "format": {"major": 1, "minor": 0},
  "notebookId": "0198f3c2-7b1e-7cc3-9f10-3d2a8c41e977",
  "title": "Physics",
  "createdAt": 1753142400000,
  "scope": {"kind": "notebook", "id": "0198f3c2-…"},
  "devices": {
    "01a109af-…": {"firstSeen": 1753142400000, "label": "Windows computer"}
  }
}
```

`scope` is an explicit object rather than an implied "everything under this
directory", so sharing a subset of sections can later be a new scope value
instead of a new directory layout.

`devices` is **informational**: a log file's existence is the real registry, and
`label` is optional. A reader MUST tolerate a manifest it cannot parse, because
every field in it is either recoverable from the logs or cosmetic.

### 3.2 The operation envelope

```jsonc
{"v":1,"dev":"01a109af-…","seq":412,"lc":9183,"ts":1753142400000,
 "enc":"none","op":"block.set","d":{ /* per kind, §3.3 */ }}
```

| | |
|---|---|
| `v` | envelope version. Absent means `1` |
| `dev` | the writing device's id — always the log's own filename |
| `seq` | that device's own counter, strictly increasing and gapless |
| `lc` | Lamport clock, for the total order |
| `ts` | Unix epoch milliseconds, UTC. Informational — never used for ordering |
| `enc` | `"none"`. Reserved for per-node encryption |
| `op` | the kind, §3.3 |
| `d` | the payload |

**Ordering is by `(lc, dev, seq)`**, so it is total and identical on every device
regardless of arrival order. Two operations on the same key resolve
last-writer-wins under that order.

**A reader that meets an unknown `op` MUST preserve the line verbatim** and MAY
skip applying it. This is what lets a newer device's notebook round-trip through
an older one without losing work.

**A reader that meets a `v` higher than it understands MUST hold the notebook
read-only.** New op *kinds* are additive and do not bump `v`, provided skipping
one is harmless. A kind whose omission would silently produce the *wrong*
content, because it is a delta rather than a whole value, MUST ride a higher `v`,
so that a reader which cannot apply it goes read-only instead of quietly
diverging. `block.patch` is the first such kind, and `v: 2` means only that a log
may contain one.

### 3.3 Operation kinds

Payloads are the `d` object. Block JSON and page properties are the data model
spec's shapes, unchanged.

| `op` | `d` |
|---|---|
| `node.upsert` | `{id, kind, parentId, title, position, color, level, createdAt, updatedAt}` — the whole node. `kind` is `section_group`, `section` or `page` |
| `node.delete` | `{id, deletedAt}` — soft delete, to the recycle bin |
| `node.restore` | `{id}` |
| `node.purge` | `{id}` — permanent |
| `block.set` | `{pageId, block}`, where `block` is a complete block envelope |
| `block.remove` | `{pageId, blockId}` |
| `block.patch` | `{pageId, blockId, k, base, at, del, ins, updatedAt, rect?}` — §3.4 |
| `ink.strokes` | `{pageId, blockId, del: [strokeId…], put: [{i, s}…], updatedAt, rect?}` — §3.5 |
| `page.props` | `{pageId, props}` |
| `blob.put` | `{hash, mime, size}` — announces bytes in `blobs/`, §3.6 |
| `notebook.meta` | the `notebook_meta` keys that changed, as an object |

`rect`, where present, is `{x, y, w, h}`: the block's bounds after the edit, so a
reader can update layout without decoding the content.

Writers SHOULD emit `block.set` for a new or wholly changed block, and MAY use
the two narrower kinds below when they are smaller. **A reader MUST implement all
three**, because a log written by any Openote release contains all three.

### 3.4 `block.patch` — one splice of one string

Replaces `del` UTF-16 code units at offset `at` with `ins`, in the string at
`content[k]` of the named block. Offsets are snapped to whole runes, so a
boundary never falls between the halves of a surrogate pair.

`base` is the first 16 hex characters of the SHA-256 of the string the patch was
computed against. **A reader MUST refuse to apply a patch whose `base` does not
match**, and MUST leave the value as it found it. That is what keeps two devices'
logs mergeable: a patch really can arrive to be applied on top of another
device's `block.set`, and applying it blind is silent corruption, where refusing
it lands exactly on last-writer-wins.

*(Informative)* It exists because `block.set` carries the entire block and an
autosave fires at every pause in a sentence — measured at 52.6% of a real
workspace's log.

### 3.5 `ink.strokes` — a per-stroke ink edit

`del` names strokes to remove, by id. `put` inserts strokes at positions, each
`{i: index, s: strokeJson}`, **applied after the removals**, so the exact stroke
order is reproduced. Positional rather than append-only because an area eraser
inserts split fragments mid-list.

*(Informative)* An imported page's ink is one block holding every stroke, several
megabytes serialised, so recording an erase gesture as a whole `block.set` was
50–1000× write amplification.

### 3.6 `blobs/`

Content-addressed, immutable, named for the lowercase hex SHA-256 of the
contents. A blob reference anywhere in a notebook is the string `sha256:<hash>`.

**Filenames carry a `.blob` suffix, and a reader MUST accept both spellings** —
look for `<hash>.blob` first, then bare `<hash>`, and write new blobs under the
former. The hash is still the whole of the identity, so two devices storing the
same image independently still produce the same filename with no merge logic.

> *(Informative)* The suffix exists because **Google Drive treats a file with no
> extension as one whose extension it should work out, and renames it.** A
> notebook on Drive accumulated copies numbered up to `(8)` of identical bytes:
> every launch found the canonical name missing, recovered the bytes from the
> renamed copy, wrote the canonical name back, and Drive renamed it again. With a
> suffix present Drive identifies the content and leaves the name alone. Verified
> on a real notebook — the first open under the new scheme migrated 3 blobs and
> removed 62 redundant copies of them.
>
> **Nothing migrates older notebooks**, deliberately: to a sync client a rename
> is a delete plus a create, so renaming every blob would re-upload the whole
> notebook, and a bare filename nothing has touched is not a problem.

**Nothing deletes a blob today.** A writer MUST assume bytes written here are
permanent and MUST NOT rely on any collection having happened.

### 3.7 `media/`

Video and audio, as ordinary files with random names and their original
extensions — not content-addressed, and not blobs. A block references media by
**bare filename**, in `content.media`.

*(Informative)* The reason is size. A 700 MB lecture in a content-addressed store
would be one enormous row that has to be decoded into memory in full before a
single frame plays, and it would be carried by every backup and every integrity
scan. Being a file is the point: a player wants a path. Names are random rather
than hashes because hashing a gigabyte at insert time is a visible stall on the
one operation where the user is already waiting, and deduplicating two copies of
the same lecture is worth very little.

## 4. The container (`.onote`)

A SQLite 3 database holding a queryable projection of the log, for the device
that made it. A reader that only wants to *read* a notebook can use it and skip
§3 entirely — which is the easiest way in, and the reason it is specified here
rather than left as an implementation detail.

- `application_id` MUST be `0x4F4E4F54` ("ONOT"). `user_version` is the format
  major version, **`1` for a notebook file**.
- **`user_version = 2` means Openote's own local working copy, not a notebook.**
  Its `blobs` table may be empty and its only guarantee is that it can be rebuilt
  from the log beside it. A reader that does not understand `2` MUST refuse the
  file rather than open it.
- WAL journal mode when writable. `foreign_keys` ON.
- UTF-8 throughout. All timestamps are Unix epoch milliseconds, UTC. All
  identifiers are **UUIDv7** in canonical lowercase form — time-ordered, so
  index-friendly, with rough creation-time forensics for free.

### 4.1 Schema (normative DDL)

```sql
-- ── Identity and metadata ─────────────────────────────────────────
CREATE TABLE notebook_meta (
  key   TEXT PRIMARY KEY,          -- see §4.2
  value TEXT NOT NULL              -- JSON-encoded
);

-- ── Structure: section groups / sections / pages ──────────────────
CREATE TABLE nodes (
  id         TEXT PRIMARY KEY,     -- UUIDv7
  kind       TEXT NOT NULL CHECK (kind IN ('section_group','section','page')),
  parent_id  TEXT REFERENCES nodes(id) ON DELETE CASCADE,  -- NULL = root
  title      TEXT NOT NULL DEFAULT '',
  position   TEXT NOT NULL,        -- fractional index; sorts lexicographically
  color      TEXT,                 -- section tab colour token, optional
  level      INTEGER NOT NULL DEFAULT 0,  -- pages: subpage indent 0..2
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER               -- soft delete → recycle bin
);
CREATE INDEX idx_nodes_parent ON nodes(parent_id, position);

-- ── Page content ──────────────────────────────────────────────────
-- One row per page holding the complete block tree as JSON. Within the
-- container this is the only copy of a page's content.
--
-- The name is historical: v0.1 of this spec put a CRDT layer underneath
-- and called this its open "mirror". That layer was never implemented
-- (appendix A). The name is kept so every notebook ever written stays
-- readable.
CREATE TABLE page_mirror (
  page_id    TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
  json       TEXT NOT NULL,        -- Page JSON, data model spec §8
  mirror_rev INTEGER NOT NULL,     -- increases per page on each write
  updated_at INTEGER NOT NULL
);

-- ── Blobs ─────────────────────────────────────────────────────────
-- LEGACY, and empty in any notebook written since v0.17: blob bytes live
-- in `blobs/` (§3.6). The table remains so a notebook written before that
-- still renders, and so a single `.onote` can be made genuinely
-- self-contained on purpose, by refilling it.
CREATE TABLE blobs (
  hash       TEXT PRIMARY KEY,     -- lowercase hex SHA-256
  bytes      BLOB NOT NULL,
  mime       TEXT NOT NULL,
  size       INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

-- Which pages reach which blobs: the garbage-collection root set.
--
-- **No foreign key onto `blobs`.** It had one, which made this table mean
-- "blobs this page reaches THAT THIS CONTAINER HOLDS" — and since the
-- container holds none, every page carrying a picture failed its INSERT,
-- inside the savepoint that writes the page, and so failed the whole save.
CREATE TABLE blob_refs (
  page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  hash    TEXT NOT NULL,
  PRIMARY KEY (page_id, hash)
);

-- ── Links and embeds index ────────────────────────────────────────
CREATE TABLE refs (
  src_page_id  TEXT NOT NULL,
  src_block_id TEXT NOT NULL,
  kind         TEXT NOT NULL CHECK (kind IN ('link','embed')),
  dst_page_id  TEXT NOT NULL,      -- may point into another notebook (§6)
  dst_notebook TEXT,               -- NULL = this notebook
  dst_target   TEXT,               -- JSON EmbedTarget, data model spec §7
  PRIMARY KEY (src_page_id, src_block_id, kind)
);
CREATE INDEX idx_refs_dst ON refs(dst_page_id);

-- ── Attribution and recent deletions ──────────────────────────────
-- Both DERIVED from the log and never synced: dropping them costs a
-- rebuild, never a note. One row per block that currently exists, which
-- bounds them by the size of the notebook rather than by how long it has
-- been edited.
CREATE TABLE block_authors (
  page_id    TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  block_id   TEXT NOT NULL,
  device     TEXT NOT NULL,
  lamport    INTEGER NOT NULL,
  seq        INTEGER NOT NULL,
  changed_at INTEGER NOT NULL,
  block_kind TEXT NOT NULL,
  chars      INTEGER NOT NULL,
  pins       TEXT NOT NULL,
  PRIMARY KEY (page_id, block_id)
);

-- Deliberately NOT keyed on `nodes`: a purged page has no `nodes` row, and
-- that is precisely the entry someone most needs back. Capped at ten.
CREATE TABLE recent_deletions (
  device     TEXT NOT NULL,
  seq        INTEGER NOT NULL,
  lamport    INTEGER NOT NULL,
  deleted_at INTEGER NOT NULL,
  kind       TEXT NOT NULL,
  target_id  TEXT NOT NULL,
  page_id    TEXT,
  what       TEXT NOT NULL,
  pins       TEXT NOT NULL,
  PRIMARY KEY (device, seq)
);
```

**Two tables a reader may meet and MUST treat as optional.** `fts_pages` (FTS5)
is not created by default — Openote created it on every open and never wrote a
row, which advertised a search index holding nothing. A writer implementing
notebook-wide search SHOULD create and populate it, and MUST declare
`"fts_pages"` in `notebook_meta.features` so readers can tell a populated index
from an absent one. And `page_versions`, which kept up to thirty complete copies
of every page, was **withdrawn in v0.17**: it was bounded by how long a notebook
had been edited, i.e. by nothing — measured at 9,840 snapshots in a 322 MB
container — and it pinned media from collection by accident and permanently.

### 4.2 `notebook_meta` keys

Required: `format` (`{"major":1,"minor":0}`) · `notebook_id` · `title` ·
`created_at` · `app` (creator and version, informational) · `features` (a JSON
array of optional capabilities the writer used) · `content` (where page content
authoritatively lives; `"page_mirror"` for this version — **a reader that does
not recognise the value MUST NOT write**).

Readers MUST ignore unknown keys and MUST NOT destroy data belonging to features
they do not implement.

### 4.3 What is recoverable

| | Tables | On corruption |
|---|---|---|
| **Projection of the log** | `nodes`, `page_mirror`, `refs`, `blob_refs` | rebuild from `ops/` |
| **Derived, never synced** | `block_authors`, `recent_deletions`, `fts_pages` | rebuild; the feature degrades |
| **Legacy** | `blobs` | the bytes are in `blobs/` |

Damage is naturally page-scoped: one unparseable `page_mirror.json` costs that
page, not the notebook.

*(Informative)* Note the honest trade. A whole page's JSON is rewritten on every
save, so the smallest edit the container can represent is "the page is now this".
That is affordable for one device, and it is exactly why the container cannot be
the sync unit.

## 5. Page content

`page_mirror` holds one row per page: the complete block tree in the **Page JSON
schema** (data model spec §8) — positions, text as Markdown-with-extensions,
maths as LaTeX, ink as a blob reference, embeds as refs.

- A writer MUST regenerate the row on every page save, in the same transaction as
  the `refs` and `blob_refs` rows it implies, so a reader never sees content and
  index disagree.
- `mirror_rev` MUST increase per page on each write. Readers MAY use it to detect
  change, and MUST NOT assume it counts edits.
- **A reader MUST preserve fields it does not understand** when rewriting a
  block. This is the mechanism by which a third-party tool can safely edit a
  notebook written by a newer Openote, and it is the whole forward-compatibility
  contract.

## 6. Links, embeds and cross-notebook references

`refs` indexes every outgoing link and embed, for backlinks and delete-time
warnings. It is a projection; the truth is in the blocks.

A cross-notebook ref carries `dst_notebook`, the target's notebook id, resolved
through the workspace registry (§8). A missing notebook renders as a dangling
reference, never an error that blocks the page.

## 7. Open-folder export

Every implementation MUST offer a lossless-where-possible export of a notebook to
a plain folder:

```
Physics/
├── notebook.json                 # structure tree, ids, titles, order
├── pages/<section>/<page-title>.<id8>/
│   ├── page.json                 # the Page JSON, verbatim — the fidelity path
│   ├── page.md                   # Markdown projection (layout flattened)
│   ├── canvas.json               # JSON Canvas projection (§9)
│   └── page.inkml                # when the page has ink
└── assets/<hash>.<ext>           # blobs, content-addressed filenames
```

Page directories nest to mirror the section hierarchy. `page.md` and
`canvas.json` are convenience projections; `page.json` round-trips. **Export MUST
be available on every platform** — it is the anti-lock-in guarantee, and a
platform that cannot get your notes out is the problem this project exists for.

## 8. The workspace

`workspace.json`, in the workspace directory root:

```json
{
  "format": {"major": 1, "minor": 0},
  "workspace_id": "0198f3c2-…",
  "notebooks": [
    {"id": "0198f3c2-…", "file": "Physics.onote", "color": "ink-500"}
  ],
  "settings": {}
}
```

`file` is relative to the workspace directory when the notebook lives inside it,
and absolute otherwise.

`format.major` is **2** once the workspace holds a notebook whose container has
been demoted to a working copy, and **1** otherwise. **A reader meeting a higher
`format.major` than it understands MUST load the entries and MUST NOT write the
file back** — `file` paths it cannot represent would be rewritten as something
else, and any entry whose file it cannot find would be dropped, which is how a
build predating the demotion would silently prune every migrated notebook from
someone's list.

Notebooks are discoverable without the registry, by scanning the directory. The
registry adds ordering, colours, and id-to-file resolution for cross-notebook
refs.

Two further files may appear, both **runtime state, not data**. A reader MUST
ignore them, and deleting them while Openote is closed loses nothing:
`.instance-lock`, held open and exclusively locked by the one running Openote for
this workspace; and `.open-request`, present for a moment while a second launch
hands a double-clicked notebook to the instance holding the lock.

*(Informative)* Why single-instance at all: `workspace.json` is rewritten
wholesale, so two processes over one workspace lose notebooks to a
last-writer-wins registry. Associating `.onote` with the app made a second
process one double-click away, so the lock arrived with the association.

## 9. Interoperability projections

- **JSON Canvas:** `canvas.json` maps blocks to JSON Canvas 1.0 nodes.
  Openote-specific data — ink, maths, embeds — exports as rendered assets plus an
  `x-onote` extension key that conformant readers ignore.
- **Maths:** LaTeX in place, MathML on demand (maths spec §6).
- **Ink:** InkML (ink spec §6).
- **Markdown:** CommonMark + GFM tables and tasks, plus the extensions in data
  model spec §5.2.

## 10. Conformance

A minimal **reader**, in order of how much work each step is:

1. Open the `.onote`, check `application_id` and `user_version`, read `nodes` for
   the tree and `page_mirror.json` per page. No log parsing, no Openote code.
2. **Resolve blob references from `blobs/<hash>.blob`** in the `.onotebook`
   directory, falling back to bare `<hash>`, and then to the container's `blobs`
   table for an old notebook. A reader that looks only in the container finds no
   images at all.
3. Media by bare filename, in `media/`.

A reader that wants to be correct without a container reads the log instead:
every `.oplog` in `ops/`, ordered by `(lc, dev, seq)`, applied in order.

A minimal **writer** writes `page_mirror.json` and the `nodes` row in one
transaction, preserving fields it does not understand — **and appends to its own
log file in `ops/`, never to another device's.** Picking a device id nobody else
is using is the whole of the coordination required.

## 11. Compatibility promise

**From v0.2.0 onward, format v1 is frozen.** Notebooks created by any Openote
release open in every later release. A change that cannot be made compatibly
bumps the format major version and migrates one-way-forward, documented here.

| Surface | Frozen | Notes |
|---|---|---|
| `page_mirror.json` shape | ✅ | Unknown fields MUST round-trip |
| `nodes`, `blobs`, `blob_refs`, `refs` columns | ✅ | Columns may be ADDED; existing ones keep their meaning |
| `application_id` / `user_version` | ✅ | `0x4F4E4F54` / `1` for a notebook, `2` for a working copy |
| `notebook_meta` required keys | ✅ | Readers MUST ignore unknown keys |
| The op envelope and its total order | ✅ | New kinds are additive, per §3.2 |
| `.onotebook` layout — `manifest.json`, `ops/`, `blobs/`, `media/` | ✅ | |
| `blobs/` filenames | ✅ | Both spellings read; `.blob` written |
| `fts_pages`, `page_versions` | ❌ optional | Neither is created |

### Changelog

**v1.0.2** — a `substitute` block's typed values move from `content.value`, one
string, to `content.values`, a map keyed by variable name. The block could hold
one value because the evaluator could bind one name; it can now hold a formula of
several, and one string cannot say which number belongs to which name.

Both spellings are read, and **reading one never rewrites the other** — the same
rule `.blob` follows, for the same reason: a notebook is shared between releases,
and a migration that fired on *reading* would make an older build lose a number
it can still display perfectly well. Take `values` when present and non-empty;
otherwise treat `value` as the first variable the formula asks for, which is the
only name it could have been.

On writing, `values` is authoritative. **While the formula has exactly one
variable, `value` is written alongside it**, so a release that knows only the old
spelling still shows the number. With several variables `value` is left
untouched, because it never recorded *which* variable it held, and a reader that
only understands it cannot evaluate such a formula anyway — a number there would
sit under the wrong label.

Nothing is bumped, because nothing here is a new op kind or a new column:
`content` is a block's own JSON, whose unknown fields every release has been
required to round-trip since v0.2.0.

**v1.0.0** (op envelope `v: 2`; container still `1`) — adds `block.patch` (§3.4).
Written at `v: 2` because skipping it is not harmless: a skipped delta is
silently stale content, where a skipped whole value is merely an older one. A
reader that understands only `v: 1` therefore holds such a notebook read-only.
The container is untouched, so a notebook never written by 1.0 opens everywhere
it always did.

**v0.17** (container `user_version` 2 for working copies; `workspace.json` format
2) — the container becomes a local, rebuildable working copy at
`<workspace>/.cache/<notebook-id>/cache.onote`. A notebook file is still v1 and
still opens everywhere; **v2 is only ever a working copy.** The migration is
opt-in per notebook and reversible, except that `page_versions` is dropped and
cannot be restored. Blob bytes left the container (§3.6), and `blobs/`
materialises for every notebook rather than only shared ones.

`workspace.json` is stamped `format.major = 2` only once a workspace actually
contains a demoted notebook, so an older build keeps full use of a registry it
can still write safely.

**v0.2.0** (format v1, spec v0.2) — first frozen release. Corrected from v0.1:
the CRDT layer is not part of the format and was never implemented (appendix A);
`page_mirror` is authoritative; `fts_pages` optional. Added the `.onotebook`
operation log, with the `node.*`, `block.*`, `ink.strokes`, `page.props`,
`blob.put` and `notebook.meta` kinds.

---

## Appendix A — the CRDT layer that was never built *(informative)*

v0.1 of this specification described a CRDT layer inside the container —
`page_docs` and `page_updates`, holding Loro documents — with `page_mirror` as an
open JSON projection of it. **No release ever wrote those structures.**
`page_docs` received a zero-byte placeholder on every save and `page_updates` was
never written at all. Neither is created now.

Two things make this worth recording rather than deleting. A v0.1 notebook has
the tables present and empty of meaning, and a reader should know they are safe to
ignore. And the reason the plan changed is the reason the format is shaped the way
it is: consumer file-sync services replicate whole files, so a single large SQLite
database that every edit rewrites is close to the worst possible sync unit, and no
CRDT inside it can fix that. The operation log therefore moved out of the
container and into files, where one-writer-per-file makes conflicts structurally
impossible.

The openness guarantee moved with it, and got stronger rather than weaker: the
open representation stopped being a copy kept alongside an opaque one, and became
the thing itself.

[ADR-0002](../adr/ADR-0002-crdt-library.md) records where a CRDT would still earn
its place — merging two edits to one *paragraph*, which nothing in this format
does today.
