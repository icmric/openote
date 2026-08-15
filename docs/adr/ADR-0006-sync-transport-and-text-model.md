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
<the synced folder>/           ← what Drive/OneDrive/Dropbox/Syncthing replicate
  MyNotebook.onotebook/        ← a directory, not a file
    manifest.json              ← notebook id, format version, device registry
    ops/
      <device-id>.oplog        ← append-only. ONE writer, ever.
      <device-id>.oplog
    blobs/
      <sha256>                 ← content-addressed, immutable

<this device's workspace>/     ← never synced, never shared
  MyNotebook.onote             ← local-only SQLite cache (+ -wal, -shm)
```

> **Amended 2026-08-15 (v0.17 plan, Step 4).** As first drawn, this diagram put
> `cache.onote` **inside** `MyNotebook.onotebook/`, and listed a `snapshots/`
> directory beside it. Both are withdrawn.
>
> §8 below — written six days after this section — made that same directory the
> git repository root and the thing every consumer sync client replicates. A
> live WAL SQLite database inside the replicated tree re-creates precisely the
> torn-database hazard §2 exists to prevent, and it was not hypothetical: the
> owner's Google Drive was replicating a 31,674,368-byte container, a
> 247,232-byte `-wal` and a 32,768-byte `-shm` for an open notebook. git
> tolerates it (`git_sync.dart` writes a `.gitignore` naming `*.onote`); **the
> four consumer providers have no per-file ignore at all.**
>
> The code always did the right thing — the container is a sibling, or lives in
> the local workspace — so this was the ADR being wrong, and leaving the diagram
> as drawn invited a future implementer to "finish the job" by moving a WAL
> database into a cloud folder. `Repository.moveNotebookTo` did exactly that for
> notebooks this device created, until Step 4.
>
> `snapshots/` goes for a different reason: the v0.17 investigation measured a
> full rebuild of the largest real notebook at 54 ms of CPU (329 pages, 2,780
> ops), so there is nothing for a snapshot to optimise — and superseding one
> would mean *deleting* a file inside the synced set, which is the one thing the
> one-writer-per-file property does not cover.
>
> The identical diagram in **spec §11** (`docs/specs/10-file-format-spec.md`)
> needs the same amendment and has not had it yet.

The load-bearing property is **one writer per file**. A device only ever appends
to its own log, so two devices can never produce conflicting versions of the same
file — the situation Drive resolves badly simply never arises. Sync degenerates
to "copy files you don't have", which every provider and every home server does
correctly. Deletes never happen, so nothing can be lost by a racing upload.

Merging is then *reading*: concatenate the logs, order the operations, apply. The
result is identical on every device regardless of arrival order, which is what
makes it conflict-free rather than conflict-resolved.

The container keeps the current SQLite database as a **local materialised view**
— it stays the fast path for queries and rendering, is rebuildable from the logs
at any time, and is explicitly excluded from sync by living **outside** the
replicated directory rather than by being ignored inside it. That is what
retires the WAL tearing risk: the synced set contains no SQLite files at all,
and no ignore rule has to be honoured by anything to keep it that way.

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

## 6. Stakeholder questions — two answered 2026-07-27

- **Sync granularity: per notebook, section later.** ✅ Ship one manifest and
  device registry per notebook, but shape the manifest so it can describe a
  *subset* of sections without a format migration. Concretely: the manifest
  carries an explicit scope object rather than implying "everything under this
  directory", so a future section-scoped share is a new scope value and not a
  new file layout. Sharing a single section today means splitting it into its
  own notebook.
- **`.onotebook` as a visible directory: accepted.** ✅ Windows and Linux will
  show a folder the user can open. macOS may present it as a bundle; that is a
  presentation detail and MUST NOT change the layout, or the two platforms would
  disagree about what a notebook is. The app is responsible for making a folder
  feel like one object — the file picker filters to `*.onotebook`, and the
  navigator never exposes the internal paths.
- **Eager vs lazy first sync — still open.** For the imported-notebook case
  (324 pages, 372 images, ~65k strokes) lazy blob fetch needs a placeholder
  state in the UI. This does **not** block step 1: blobs are content-addressed
  and independently fetchable either way, so the decision only changes when they
  are pulled, not how they are stored.

## 6a. Log-format decisions (2026-07-27)

Four decisions that get written into bytes on disk, so they are taken before any
log code rather than discovered during it. The three questions in §6 turned out
to be an incomplete list — none of these four was on it, and all four are more
expensive to change later than the ones that were.

### 6a.1 An operation is **block-level**, in a **versioned envelope**

An op says *"block X now has this content"*. Concurrent edits to **different
blocks of the same page merge cleanly**; concurrent edits to **the same text
block** resolve last-writer-wins and one side's edit is lost.

That limitation is accepted deliberately and is not permanent. The envelope
carries a format version and an op-type tag, so finer-grained text operations
become new op types rather than a format break — the migration path §4 describes
(Markdown → `nodes` → Loro sequence CRDT) lands as `text.splice` ops alongside
the existing `block.set`, and old logs stay replayable.

The reasoning: the case that actually happens to a single user with several
devices — laptop edits one page, desktop edits another — is *fully* solved by
block-level ops. Same-paragraph collision requires two people typing in one
paragraph at once, which is **live collaboration** (SYNC-6, Phase 3). Blocking
all sync on the CRDT would trade a solved common case for an unsolved rare one.

### 6a.2 Device identity: per-install UUID, **fork on conflict**

One-writer-per-file is the entire correctness argument of §3, so the identity
that names the writer is load-bearing.

- The id is a UUIDv7 generated at install and stored in **app config, not in the
  notebook**. Storing it in the notebook would mean copying a notebook folder
  clones the identity — instantly two writers on one log.
- Normal use cannot produce a collision. The dangerous cases are **cloned
  machines, restored backups, and copied installs**, where two running copies
  legitimately believe they are the same device.
- Therefore each device remembers, locally, the sequence number it last wrote to
  its own log. On open, if the log's tail is **ahead of what we remember
  writing**, someone else is using our identity: the device **forks to a fresh
  id** and continues there, rather than appending.

The failure this prevents is silent and unrecoverable — two interleaved writers
produce a log that looks valid and cannot be untangled — which is why it earns
the extra bookkeeping.

### 6a.3 Delete wins, **into the recycle bin**

When one device deletes a page and another concurrently edits it, the delete
wins and propagates. This is only a safe choice because **ORG-7's recycle bin
already exists**: "delete wins" means the page lands in the bin on every device
with its 30-day retention, not that work is destroyed. A wrong guess costs a
restore, not data.

This also replaces the current behaviour, which is worse than either option:
`mirror.rs` merges add-wins with **no delete propagation at all**, so a page
deleted on one device simply returns.

### 6a.4 An encryption envelope is **reserved, not implemented**

Op records carry a header with an algorithm field (`"none"` for now) and treat
the payload as opaque bytes. Nothing is encrypted yet.

Reserving costs a few bytes per record. Retrofitting would rewrite **every byte
of every log on every device** — the one change this design makes genuinely
painful, since logs are append-only and devices hold independent copies. SYNC-5
(E2E, blind-relay) is on the roadmap, so the space is worth holding.

### 6a.5 Deferred deliberately

- **Compaction never deletes log prefixes** in v1. Safe deletion requires knowing
  every device has consumed them, which needs a device registry with watermarks —
  a second distributed problem. Snapshots stay a pure read optimisation, as §3
  requires. Revisit when a log actually gets large; the ~65k-stroke imported
  notebook is the case to measure.
- **Migration is non-destructive.** Converting an existing `.onote` builds the
  `.onotebook` *beside* it and leaves the original in place until the user
  confirms. There is a real 324-page imported notebook to protect.
- **`workspace.json` stays local-only** — a registry of where notebooks are plus
  view state. It is never synced, and a notebook may live anywhere, including
  inside a provider's folder.
- **Eager vs lazy blob fetch** (§6) remains open and still does not block: blobs
  are content-addressed either way, so the decision changes *when* they are
  pulled, not how they are stored.

## 7. Status of the storage layer as of 2026-07-27

Step 1 groundwork has begun, ahead of any op-log code:

- The container's **dead CRDT layer has been removed** — `page_docs` took a
  zero-byte placeholder write on every save, and `page_updates` and `fts_pages`
  were created but never touched. None is created or written now. This matters
  to this ADR because those tables were the in-container form of exactly the
  design §3 replaces; leaving them would have meant two contradictory sync
  designs visible in one schema.
- The [File Format Spec](../specs/10-file-format-spec.md) is corrected to v0.2:
  `page_mirror` is documented as **authoritative, not a projection**, §5's CRDT
  encoding is marked superseded-and-never-implemented, and a new §11 states this
  ADR's direction in the published spec so third-party implementers can see
  where the format is going.
### Built 2026-07-27 (steps 1–2), in `app/lib/sync/`

| File | Role |
|---|---|
| `op.dart` | The envelope — version, device, per-device seq, Lamport counter, reserved `enc` field, op tag, payload. JSON Lines. Deterministic total order (`lamport`, then device id, then seq). |
| `op_log.dart` | `Foo.onotebook/{manifest.json, ops/<device>.oplog}` beside `Foo.onote`. Append-only writes; `readAll()` is the merge — concatenate every device's log and sort. |
| `device_identity.dart` | Per-install UUID in app settings, with the fork-on-conflict check. |
| `materializer.dart` | Replay → state. Pure function of the ordered op list. |
| `sync_recorder.dart` | Diffs a page save into block-level ops and appends them. |

**Running in shadow mode**: the `.onote` remains authoritative, and every
mutation through `AppState`'s facade also records ops. `sync_shadow_test.dart`
asserts the step-2 property directly — **rebuild a page from the log alone and
it equals the container**.

Three decisions were forced by writing it, all recorded in the code:

- **Ops are recorded *after* the container write succeeds.** The reverse would
  make rebuild-from-log differ on every failed save, and that divergence would
  read as a recording bug rather than the disk error it is.
- **A page save is diffed, not dumped.** Recording the whole page per autosave
  would grow the log without bound and would throw away the block granularity
  §6a.1 exists to provide. An unchanged save now appends nothing.
- **Recorders are keyed per notebook**, because imports write into a notebook
  that is not the open one — the single most likely place for the log to end up
  quietly incomplete.

Not yet built: the container is not yet demoted to `cache.onote`, the `nodes`
migration, Loro, and every transport.

### Amended 2026-08-06 — blob bytes are materialised on demand

Blob bytes *are* written into `blobs/`, but **only for notebooks that are
shared** — in a sync folder, or mirrored. The op is always recorded; the bytes
wait.

This was forced by measurement, not by taste. Shadow mode stores every image
twice, once in the container's `blobs` table and once as `blobs/<sha256>`, and a
synthetic imported notebook came to 17.39 MB for 7.81 MB of media — a 2.23×
overhead, paid by every notebook including the majority that never leave the
machine. Deferring the bytes for those took the same notebook to 9.57 MB.

Two things make it safe rather than a hole in §7's completeness property:

1. **The container is still authoritative and still holds every byte.**
   Deferred is not lost. `SyncRecorder.backfillBlobs` — which already existed,
   to migrate notebooks created before the log — materialises the whole set from
   the container the moment a notebook becomes shared. What used to be the
   migration path is now the normal one.
2. **The op stream is identical either way.** Turning sync on never has to
   synthesise history it did not record, because hash, mime and size were
   written all along.

What it costs: rebuild-from-log verification loses its shadow *content* for
local-only notebooks (structure still verifies; `sync_shadow_test.dart` covers
the shared case). A log that will never leave the machine verifies nothing an
enabled one wouldn't. Wave 2's demotion of the container supersedes this
entirely — at that point `blobs/` is the only home and single-copy falls out
structurally for shared notebooks too.

## 8. Cloud transports — decided 2026-08-03: folders, not APIs

Google Drive, OneDrive, iCloud Drive and Dropbox all ship a desktop client that
presents the cloud as an ordinary local folder. §3's design already syncs
correctly through any such folder, because one-writer-per-file means the
provider is never asked to merge anything — which is precisely the thing these
providers do badly.

**So Openote never talks to a cloud API.** The alternative was considered and
rejected on four grounds:

1. **Secrets that aren't secret.** OAuth requires registering with each vendor
   and shipping a client ID/secret inside an open-source binary, where anyone
   can extract them.
2. **Attack surface.** Holding refresh tokens with broad Drive scopes on disk
   is a far larger security liability than reading and writing files the user
   already syncs — and the vision's local-first promise gets harder to keep the
   moment the app can reach the network at all.
3. **Maintenance.** Four vendor APIs, four auth flows, four sets of breaking
   changes, and a token-refresh failure mode for every user.
4. **It buys nothing.** The provider's own client already does the transport,
   better and with the user's existing credentials.

**What this means for self-hosting:** it is the same feature. Syncthing,
Nextcloud's client, a NAS mount, or an rsync cron job all produce a folder, so
self-hosting needs no Openote-side support at all and exposes nothing to the
network. That is the strongest possible answer to "can I run this myself?"

### Implemented (`app/lib/sync/`)

| File | Role |
|---|---|
| `cloud_folders.dart` | Detects Drive/OneDrive/iCloud/Dropbox/Nextcloud/Syncthing folders by well-known path, and carries the per-provider caveat (all four big providers evict files by default, which looks exactly like data loss). |
| `folder_watch.dart` | Watches `ops/` and pulls when a **foreign** log changes — own-device writes are ignored, or every save would schedule a re-read of what it just wrote. Debounced, because a cloud client writes one edit as a burst. |
| `Repository.moveNotebookTo` | Copy → verify length → copy the `.onotebook` directory → only then delete the originals. Never a bare rename: the destination is usually a different volume, where rename is not atomic, and a half-moved notebook is the worst outcome. Never overwrites an existing file. |
| `ui/sync_dialog.dart` | The whole setup flow, one dialog: pick a detected folder or choose any folder. |

Re-entrancy: `AppState.syncPull` holds a lock, because the watcher can fire
again mid-pull and two overlapping pulls would both read the same pending ops,
both write them, and both advance the watermark — applying remote edits twice.

**Deliberately still open:** a notebook in a shared folder edited by two people
*at the same moment in the same paragraph* resolves last-writer-wins until the
structured text model and a sequence CRDT land (§4). Different pages, different
blocks, and different paragraphs of different blocks all merge correctly today.
