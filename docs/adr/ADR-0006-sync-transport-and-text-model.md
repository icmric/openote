# ADR-0006: Sync transport and the text model it requires

> **Status:** Proposed — groundwork only; no sync code is being written yet · 2026-07-27
> **Related:** [ADR-0002](ADR-0002-crdt-library.md) (Loro) · [ADR-0003](ADR-0003-storage-container.md) (SQLite `.onote`) · [ADR-0004](ADR-0004-editor-engine.md) (editor seam) · [Data Model §5](../specs/11-data-model-spec.md)

## Why this exists now

Cloud sync is "very soon", the targets are Google Drive / OneDrive / self-hosted,
and the requirements are painless conflict resolution and live collaboration.
Those requirements constrain the **storage layout** far more than they constrain
the sync code, and the storage layout is what we would otherwise keep building
on. Deciding it late means migrating real notebooks; deciding it now costs a
document.

This ADR also answers a question that came up directly: *does Unicode support
require a substantial rebuild, and if so should the structured-`nodes` migration
be folded into it?* **No, and therefore no** — see §1. The `nodes` migration is
justified, but by *this* ADR's requirements, not by Unicode.

---

## 1. Unicode does not require a rebuild

Worth stating plainly because it changes the plan: there is no UTF-8/UTF-16
rebuild to do.

- Dart strings are already **UTF-16 code units**, and `String.runes` /
  `characters` give code points and grapheme clusters. Flutter's text stack
  renders any Unicode scalar for which *some* font has a glyph. Nothing in the
  storage path is byte- or ASCII-oriented: SQLite text is UTF-8, `dart:convert`
  round-trips it, and the Rust parser decodes OneNote's UTF-16LE properly
  (verified — see below).
- The characters that failed were **three unrelated problems**, none of them an
  encoding rebuild:
  1. **Glyph coverage.** We bundle no fonts (style guide §4.1), so a maths note
     full of `∃ ∀ ∧ ∨ ⊆ ⊘ ¬ ℝ` fell back to whatever the OS had. *Fixed* — an
     explicit `fontFamilyFallback` chain (`onoteFontFallback`) now names
     wide-coverage families per platform, and imported boxes get it too (they
     name their own family, which bypassed the theme's list).
  2. **Private Use Area characters.** The sample notebook contains 17 × `U+F0AC`
     — Office's way of storing a *Symbol-font* character. It decodes correctly
     and then renders as a blank box because no normal font claims the PUA. The
     fix is a Symbol/Wingdings→Unicode mapping table in the importer. **Not yet
     done**, tracked separately; it is a lookup table, not a rebuild.
  3. **Replacement characters already in the source.** 37 × `U+FFFD` exist in
     the `.one` file itself. Measured: our UTF-16 decoder never produces one
     (instrumented, zero unpaired surrogates across the whole notebook), so
     these were lost before Openote ever saw the file. Nothing to fix.
- **Alt+X** (type a code point, press Alt+X, get the character; press again to
  get the code back) is `lib/editor/unicode_input.dart` — a pure
  string-and-selection transform with 16 tests. It needed no changes anywhere
  else, which is the clearest evidence that text handling was never the problem.

So the two pieces of work are independent, and bundling them would have bought
nothing. What follows is the case for the `nodes` model on its own merits.

---

## 2. The constraint everyone gets wrong: Drive and OneDrive sync *files*

Google Drive, OneDrive, Dropbox and a home server over rsync/WebDAV all share
one property: **they replicate whole files and resolve conflicts by making a
second copy.** They have no idea what is inside. This has hard consequences:

- **One SQLite file per notebook is close to the worst possible layout for them.**
  It is a single large binary that every edit rewrites. Two devices editing
  different pages of the same notebook produce two whole-file versions, and the
  provider's only move is `notebook (1).onote`. Nothing can merge those
  afterwards — the edits are already indistinguishable from each other.
- **WAL makes it worse.** `.onote-wal` / `.onote-shm` are separate files whose
  contents are only meaningful *paired* with the database at the same instant. A
  file syncer that uploads them independently, or at a slightly different time,
  can produce a torn database. This is a live risk today, not a future one.
- **Last-writer-wins on a whole notebook silently destroys work.** Not "produces
  a conflict to resolve" — destroys, because the losing version's edits were
  never separable.

Any design that ends in "and then Drive syncs the `.onote`" fails the stated
requirement of painless conflict resolution. So the unit the cloud sees has to
change.

## 3. Decision: an append-only per-device op log, with the container as a cache

The layout that satisfies dumb file sync, real merging, and live collaboration
at once:

```
MyNotebook.onotebook/          ← a directory, not a file
  manifest.json                ← notebook id, format version, device registry
  ops/
    <device-id>.oplog          ← append-only. ONE writer, ever.
    <device-id>.oplog
  blobs/
    <sha256>                   ← content-addressed, immutable
  snapshots/
    <device-id>-<seq>.snap     ← optional compaction, never authoritative
  cache.onote                  ← local-only SQLite; never synced
```

The load-bearing property is **one writer per file**. A device only ever appends
to its own log, so two devices can never produce conflicting versions of the same
file — the situation Drive resolves badly simply never arises. Sync degenerates
to "copy files you don't have", which every provider and every home server does
correctly. Deletes never happen, so nothing can be lost by a racing upload.

Merging is then *reading*: concatenate the logs, order the operations, apply. The
result is identical on every device regardless of arrival order, which is what
makes it conflict-free rather than conflict-resolved.

`cache.onote` keeps the current SQLite container as a **local materialised view**
— it stays the fast path for queries and rendering, is rebuildable from the logs
at any time, and is explicitly excluded from sync. That also retires the WAL
tearing risk, because the synced set contains no SQLite files at all.

### Consequences

- Blobs are already content-addressed, so they need no merge logic and can be
  fetched lazily — the design that makes a 300-page imported notebook usable
  before every image has downloaded.
- Compaction has to be a pure optimisation. A snapshot is a cache of a log
  prefix; if two devices compact differently, both remain correct. The moment a
  snapshot becomes authoritative, one-writer-per-file is broken.
- A self-hosted target needs nothing but file storage — no server logic. That
  answers "unless that's going to be far too difficult": with this layout it is
  the *easiest* of the three, not the hardest.
- Live collaboration is a **transport swap, not a redesign**: the same operations
  that append to a log can stream over a socket. File sync and live sync stop
  being different features.

## 4. What this requires of the text model — and this is the real reason for `nodes`

An operation log is only as good as the granularity of its operations. Today a
text block stores an opaque Markdown string (`content['text']`), so the smallest
representable edit is *"the whole block is now this"*. Two people editing
different sentences of one paragraph produce two whole-block writes, and one must
lose. That is not a merge failure — it is a modelling failure, and no amount of
sync cleverness fixes it.

Per-character convergence needs the paragraph to be a **sequence CRDT** with
stable identity per element, which is exactly the structured `{nodes: […]}` model
of Data Model §5.1, and exactly what Loro (ADR-0002) provides. This is also
[ADR-0004](ADR-0004-editor-engine.md)'s recorded revisit trigger #2, reached
sooner than expected because sync arrived first.

The migration has one place to land, by design: `OnoteTextEditor.serialize` /
`deserialize` / `textStorageKey`. A structured engine declares `'nodes'` and
implements the conversion; nothing above the seam changes. That seam existing is
why this is a contained piece of work rather than an editor rewrite.

### Sequencing (nothing here is built yet)

1. **Stable identity everywhere.** Blocks already have stable ids; pages and
   nodes need the same guarantee across import and restore. Cheap, and every
   later step depends on it.
2. **Model the op log and write it alongside today's saves.** Log first, derive
   the container from it, and keep the current save path as the check: if a
   rebuild-from-log doesn't reproduce the container byte-for-byte, the log is
   incomplete. This is testable before any network code exists.
3. **Markdown → `nodes`.** Behind the editor seam, with the byte-stable
   round-trip ADR-0004 criterion 4 asks for.
4. **Loro for the text sequence**, replacing the hand-rolled ordering. ADR-0002
   assumed `flutter_rust_bridge`; we hand-wrote `dart:ffi` instead, so that
   integration assumption needs re-testing at this point.
5. **Transports last** — local folder, then a provider, then live.

Steps 1–3 are useful on their own even if sync slipped indefinitely, which is the
main reason to sequence it this way.

## 5. Alternatives rejected

- **Sync the `.onote` file directly.** Simplest to build, and fails the actual
  requirement — see §2. Worth writing down because it is the obvious default.
- **Per-page files, no op log** (an extension of the existing "materialise as a
  folder" export). Scopes conflicts to a page instead of a notebook, which is a
  real improvement, and still cannot merge two edits to the *same* page. A
  reasonable interim if sync is needed before the CRDT lands; not the end state.
- **Server-authoritative sync** (our own backend, clients push/pull). Merges
  well and rules out the self-hosted-on-anything goal, since every user then
  needs to run a service rather than point at a folder.
- **Operational Transform instead of CRDT.** Needs a central sequencer to order
  operations, which contradicts dumb file transports.

## 6. Open questions for the stakeholder

- Is **per-notebook** the right sync granularity, or should a section be
  independently shareable? This changes whether the manifest is per notebook or
  per section, and is much cheaper to decide now.
- Should the imported-notebook case (324 pages, 372 images, ~65k strokes) sync
  eagerly or lazily on first open? Lazy needs a placeholder state in the UI.
- `.onotebook` as a directory changes what "open a notebook" means on each
  platform. macOS can present a directory as a bundle; Windows and Linux cannot,
  so a notebook becomes a folder the user can see inside. Acceptable?
