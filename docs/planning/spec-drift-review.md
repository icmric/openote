# Spec drift — findings to date

> **Status:** findings only, nothing fixed · opened 2026-10-08
> **Why:** several drifts surfaced one at a time while building the web demo
> and chasing a "corrupted" page (v1.0.2 §17–§23). Enough of them, found by
> accident, to justify looking on purpose.
> **Scope of this file:** what is *known* to have drifted. It is **not an
> audit** — nobody has yet read the specs against the code deliberately. That
> is the job this file exists to start.

The pattern in every case is the same: **v0.17 moved where bytes live, and the
documents that describe where bytes live were not all moved with it.** The
code is right and the documents are stale, so none of this is a bug in the
app — it is a bug in what the project tells people, including its own author.

---

## A. The published specification

The highest-priority group, because
[10-file-format-spec.md](../specs/10-file-format-spec.md) describes itself as
*"publishable as the standalone public specification of the format"* and is
what a third-party tool would be written against.

### A1. §2 — "self-contained, attachments included" is false

> *"Notebooks are **self-contained**: moving/copying a `.onote` file moves the
> whole notebook, **attachments included**."*

v0.17 Step 6 stopped the container holding blob bytes.
`Repository.putBlob` says so in its own doc comment — *"The container is not
touched"* — and writes to `<name>.onotebook/blobs/<sha256>` instead. So
copying a `.onote` leaves every picture, PDF and ink stroke behind.

**This is the drift that cost real data.** It is how the demo notebook ended
up with eight ink blocks whose blobs were nowhere (v1.0.2 §17, §18c), because
`assets/demo/README.md` told its reader to do exactly what §2 says is safe.

### A2. §3.1 — the schema shows a foreign key the code drops

The published `CREATE TABLE` has:

```sql
CREATE TABLE blob_refs (
  hash TEXT NOT NULL REFERENCES blobs(hash),
```

`database.dart` has `_dropBlobRefsBlobsFk`, which rewrites the table **without**
that key, and explains why: *"Step 6 stops the container storing blob bytes, so
from that release on there is no `blobs` row for any new picture"* — with the
key present the insert raises a constraint violation inside `writePage`'s
savepoint and fails the whole page save.

So the spec publishes a constraint that, if a third-party writer honoured it,
would break saving.

### A3. §3.2 — `blobs` is listed as "source of truth"

The layer table puts `blobs` under **Source of truth**. For anything written
since Step 6 that table is empty; the bytes are files on disk. The truth moved
and the table did not.

(Credit where due: the same table *was* updated for `page_versions`, which it
correctly marks *"withdrawn v0.17 … no longer created"*. So this file has been
maintained — just not completely.)

### A4. §10 — the conformance checklist would produce a broken reader

> *"A minimal third-party **reader**: … resolve `blobs` by hash."*

Someone following this to the letter writes a reader that finds no images at
all. Of everything here this is the one with the furthest reach, because it is
addressed to people outside the project who have no way of knowing better.

---

## B. The ADRs

### B1. ADR-0007's amendment — the split is universal now

> *"storage wave 1a made `.onotebook/blobs/` materialise **only for notebooks
> that are in a sync folder or mirrored**, taking a measured 2.23× overhead to
> 1.23× for everything else."*

Step 6 superseded this: every notebook's blobs go to `blobs/` now, synced or
not. Anyone reading ADR-0007 today is told the opposite of what ships, and it
is the document you would reach for first.

### B2. ADR-0007's body — "stored **twice**"

The opening table (`blobs` table *and* `.onotebook/blobs/`, written by
`putBlob` and `SyncRecorder` respectively) describes the pre-Step-6 world.

### B3. ADR-0007 §"reachability" point 2 — version history

> *"**Version history** — `SYNC-8` keeps 30 snapshots per page."*

`page_versions` was removed in v0.17 Step 8a; `database.dart` says it is
*"deliberately NOT created"*. `media_gc.dart` already records the correction
from the GC side, so the knowledge exists in the codebase — it just never got
back into the ADR.

**This one actively misled the work in v1.0.2 §22**, where a whole argument was
built on snapshots pinning media. They do not. The op log does. Corrected in
§22c, and a good illustration of what stale docs cost.

### B4. ADR-0006 §3 — authority is stated two ways

Not stale so much as **unresolved**, and worth settling explicitly rather than
leaving both sentences true:

- ADR-0006 §3's title: *"an append-only per-device op log, **with the container
  as a cache**"*
- `app_state.dart` `_backfillTree`: *"**the container is authoritative** and a
  log we cannot write is a degraded check"*

Both are accurate today, because the log was built as a shadow and the
container has not yet been demoted (*"Not yet built: the container is not yet
demoted to `cache.onote`"*). The end state is written down; the transition's
current position is not, and that ambiguity confused the project's own author
(v1.0.2 §19, and the conversation on 2026-10-08).

---

## C. Doc-versus-code inside `lib/`

Same failure mode, smaller radius. Both of these were **fixed** in v1.0.2 and
are listed so the review can look for more of the shape, not so it redoes them.

### C1. `InkStorage.toWorking` — fixed 2026-10-07

Its doc comment promised *"an ink block that draws nothing rather than a page
that fails to open."* The code returned the content untouched, which left no
`strokes` key, which the canvas cast unchecked — a grey page. **The comment
was right and the code was wrong**, which is the rarer and more dangerous
direction.

### C2. `assets/demo/README.md` — fixed 2026-10-07

Told its reader to copy the container, which loses handwriting (A1). Written in
this repo, by this project, after Step 6.

---

## D. Interface-versus-reality

Not specification drift, but the same class — what the product asserts is not
what is true. Collected here because a review pass should probably cover them
together.

| | says | is | ref |
|---|---|---|---|
| Backup target with `keep: 0` | "backup" | a mirror, which **skips the container** | §18a |
| Sync chip | *N* devices | every `.oplog` that ever existed | §20e |
| AI dialog | "Connected" | "a config file mentions us" | §20g |
| Demo notebook | "solving single variable equations" | multi-variable since §6a | §21f |

---

## E. Checked and found correct

Recorded so the review does not spend time re-deriving them:

- **Alt+=** to insert an equation — real, documented in `app_shell.dart`.
- **18 code languages** — matches `code_languages.dart`.
- **Format spec §3.2 on `page_versions`** — correctly marked withdrawn.
- **Ink data spec §43 on `strokeStart`** — consistent with `ink_codec.dart`.
- **`.onotelink`'s own wording** — *"The notebook is this whole folder, not any
  one file in it"* — is the most accurate description of the storage model
  anywhere in the project, including the spec.

---

## F. How these were found, and how to find the rest

Every one above came from the same two moves, neither of which needs tooling:

1. **Follow a byte.** Pick something the spec says is stored somewhere, and
   grep for the code that writes it. A1–A4 and B1–B3 are all one question —
   *where do blob bytes actually go* — asked of six documents.
2. **Read the doc comment next to the code.** C1 and B3 were both caught
   because a comment in `lib/` already stated the correction. The project
   documents itself unusually well, which means **the answer to "has this
   drifted" is often already written a few lines away** from the code that
   drifted from it.

A deliberate pass should probably start with v0.17's steps, since every
confirmed drift traces to one of them, and check each claim the specs make
about *where* something lives rather than *what shape* it has. Shape claims
have held up; location claims have not.
