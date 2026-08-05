# ADR-0007 — Blob storage and garbage collection

> **Status:** Proposed · 2026-08-05
> **Supersedes nothing.** Refines [ADR-0006](ADR-0006-sync-transport-and-text-model.md) §3.
> **Related:** E1/E2 in [v0.4-and-beyond](../planning/v0.4-and-beyond.md)

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

**Three separate changes, in this order. Only the first two are safe today.**

### 1. Stop double-storing (blocked on E2 — see below)

Make `.onotebook/blobs/` the single home and have the container hold no bytes.
This is not a GC change at all: it halves the cost with no deletion logic and
no reachability question. It **is** the ADR-0006 §3 container demotion wearing
a different hat, and it inherits that work's blocker.

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
- Step 1 must not ship before the join path stops depending on the container
  being in the shared folder (below).

## Blocker, recorded here because it also blocks E2

`Repository.openExistingNotebook` joins a shared notebook by **copying the
`.onote` out of the shared folder**. That is the whole mechanism. Demoting the
container — removing it from the synced folder — therefore leaves a second
device with nothing to join: `rebuild-from-log` exists in shadow mode with a
test, but it has never been the user-facing join path and "rebuild-from-log on
real data" is still on the carried-verification list.

So the real order is:

1. Make **rebuild-from-log** a real, verified join path.
2. Then demote the container (E2), which also gives blob de-duplication (E1
   step 1) for free.
3. Then GC (E1 step 2/3), against a single blob store.

Attempting (2) before (1) produces a notebook a second device cannot open, and
the failure is silent at the moment of the move — it only surfaces later, on a
different machine. That is the worst possible shape for a data bug, and it is
why the demotion was reverted rather than shipped when this was discovered.

## Revisit triggers

- A user reports Openote filling a disk before step 2 lands — pull step 3
  forward against the container's `blobs` table alone.
- Audio notes (P7) get scheduled: they make the cost per lecture permanent and
  the grace period more expensive to be wrong about.
