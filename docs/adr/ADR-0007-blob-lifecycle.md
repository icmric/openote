# ADR-0007 — Blob storage and garbage collection

> **Status:** Accepted, **not built**. Nothing has ever deleted a blob.
> **Refines** [ADR-0006](ADR-0006-sync-transport-and-text-model.md) §3.
> **Related:** [backlog §1.3](../planning/backlog.md) · [v1.0.2](../planning/v1.0.2.md)
>
> **Two things below have been overtaken, and the decision is better for both.**
>
> Step 1 shipped: blob bytes left the container entirely in v0.17 Step 6, and
> `.onotebook/blobs/` is now the only home for every notebook, synced or not. So
> the double-store the Context describes is gone, there is one store to sweep
> rather than two, and the Blocker at the foot of this document is spent —
> rebuild-from-log became the real join path, which is what it was waiting for.
>
> **The reachability list in "The problem GC actually has to solve" is wrong in
> three places**, and this is the part to read before writing any sweep:
>
> * **Version history is not a root.** `page_versions` was withdrawn in v0.17
>   Step 8a and is no longer created. Point 2 below can go.
> * **The op log is a root, and it is the hard one.** It is append-only and
>   never compacted, so it permanently names every blob ever written. A sweep
>   that treats a `blob.put` as a reference can therefore collect *nothing*.
>   This is the real obstacle, and it is why the forget op in
>   [v1.0.2](../planning/v1.0.2.md) exists as a sketch — a blob has to be
>   positively retired, not merely unreferenced.
> * **The clipboard and the undo stack are roots too.** A blob whose only
>   reference was just cut is reachable from the cut. Both are session-scoped,
>   which bounds the problem, but neither is in the list below.

## Context

Every image, PDF-slide render and attachment is stored **twice**:

| Store | Written by | Read by | Purpose |
|---|---|---|---|
| `blobs` table in the `.onote` container | `Repository.putBlob` | the app, every render | the fast local path |
| `.onotebook/blobs/<sha256>` | `SyncRecorder` | other devices | the replicated artefact |

**Nothing ever deletes from either.** Delete a page, empty the recycle bin,
delete the notebook's every reference to an image — the bytes stay in both
places for ever.

The numbers make this urgent rather than tidy. A 60-slide lecture deck rendered
at 2× is ~120 MB, so a single PDF import costs **~240 MB**, before per-notebook
mirrors and dated backups copy it again. Audio notes (P7), which are the next
large feature on the backlog, are ~30 MB per lecture and permanent. A student
who imports a semester of decks fills a small SSD, and nothing in the app can
currently give the space back.

## The problem GC actually has to solve

A blob is reachable from **four** places, and three of them are easy to forget:

1. **Live pages** — `![](sha256:…)` inside a text block, or an image/file
   block's `content['blob']`.
2. **Version history** — `SYNC-8` keeps 30 snapshots per page. A snapshot that
   still references a deleted image is a restore path; collecting that blob
   turns "restore" into "restore, with holes".
3. **The recycle bin** — a soft-deleted page keeps its content for 30 days by
   design.
4. **Other devices' op logs that have not synced yet.** This is the one with
   teeth. Device B writes an image, appends the op to *its* log, and the file
   has not arrived on device A. If A garbage-collects on the basis of what it
   can see, it deletes a blob that is about to be referenced. There is no
   handshake in the design — deliberately, because one-writer-per-file is what
   makes the transport work — so A cannot ask B what it holds.

Point 4 is why "mark and sweep over the current page set" is wrong, and why
this needs a decision rather than a patch.

## Decision

**Three changes, in this order.** The first has shipped.

### 1. Stop double-storing — shipped

`.onotebook/blobs/` is the single home and the container holds no bytes. Not a
GC change at all: it halved the cost with no deletion logic and no reachability
question, which is why it was worth doing first.

It had one prerequisite, and the reason is worth keeping: joining a shared
notebook used to mean copying the `.onote` out of the shared folder, so removing
the container from that folder would have left a second device with nothing to
join — and the failure would have been silent at the moment of the move,
surfacing later on a different machine. Rebuild-from-log had to become a real,
verified join path first. It did, and it is now the only one.

### 2. Collect only what this device can prove is unreferenced, and only
      inside a grace period

The rule, stated so it can be checked:

> A blob may be deleted when it is referenced by no live page, no version
> snapshot and no recycle-bin entry, **and** its file is older than the
> longest plausible sync delay, **and** no foreign log has been ingested in
> that window that mentions it.

The age test is what handles point 4 without a handshake. A blob written by
another device arrives *with* its op; a blob nothing references and that has
sat untouched for longer than any sync round-trip is genuinely orphaned. The
window should be conservative — **30 days, matching the recycle bin**, so a
single retention number governs everything the user can get back.

This is deliberately incomplete: it will never collect a blob that a
never-syncing second device still references. That is the correct trade. The
cost of over-retention is disk; the cost of over-collection is a hole in
someone's notes.

### 3. Report before deleting

GC runs **on request**, from Notebooks ▸ Repair (which already walks every
page), and says what it will reclaim before it does anything: *"142 unused
images · 310 MB. Delete?"* No automatic background collection in v1. The first
version of a delete-user-data feature should be one the user chose to run.

## Why not the obvious alternatives

- **Reference-count on write.** Requires every mutation path to maintain the
  count exactly, for ever, including import, undo, sync ingestion and version
  restore. One missed path silently deletes user content — and this codebase
  has already found several mutation paths that forgot to record themselves.
  Recompute-by-scanning is O(pages) on an operation that runs rarely.
- **Collect on page delete.** The blob may be referenced by another page, a
  snapshot, or a log not yet ingested. This is the naive version of the bug.
- **Never collect; ask the user to re-import.** What we have now, and it is
  why three ~90 MB containers and hundreds of megabytes of orphaned logs were
  measured in one user's Drive.

## Consequences

- Reclaim is **best-effort and conservative by construction**. Documented as
  such, so nobody later "fixes" it into aggressiveness.
- The 30-day grace period ties GC to the recycle-bin retention, which is
  currently hard-coded and which the PRD wants configurable (ORG-7). Making
  retention configurable now has a second consumer.
- A blob store with one home has no "which copy is right" question, which is
  the quiet dividend of step 1 and the reason the sweep below is simpler than
  the one this ADR was first written against.

## Revisit triggers

- A user reports Openote filling a disk. The report-only half (step 3) is
  worth shipping on its own: telling somebody what is reclaimable costs none of
  the risk of reclaiming it.
- Audio notes (P7) get scheduled: they make the cost per lecture permanent and
  the grace period more expensive to be wrong about.
