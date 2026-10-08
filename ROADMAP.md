# Openote Roadmap

The sequence, and where it has got to. **Milestone-based rather than date-based** —
this is a solo project with occasional contributors, and ordering matters more than
calendar promises.

The guiding shape: de-risk the hardest technical unknowns first, ship a genuinely
useful single-device notebook, then earn the harder features — sync, import,
recognition, collaboration — on a foundation that already works.

**This document does not track what is left to do.** That is
[backlog.md](docs/planning/backlog.md), ranked, and the current release's own
document beside it. Requirement ids and their priorities are in the
[PRD](docs/02-product-requirements.md). Keeping a third copy here is what made
every earlier version of this file wrong.

---

## Phase 0 — Foundations · **closed**

Documentation, prototypes, and the decisions that are expensive to reverse: the
framework, the CRDT, the storage container, the editor engine, licensing, and the
sync layout. All eight are [ADRs](docs/adr/README.md).

The gate was "nothing is being built on an undecided foundation", and it closed.

## Phase 1 — A single-device notebook · **shipped, with known gaps**

**The goal:** somebody switching from OneNote can install Openote on Windows,
macOS or Linux and do real work — locally, in an open format, with no account.

Built: the canvas, the notebook hierarchy, rich text with Markdown rendered where
it is typed, maths typed linearly and read in two dimensions, pressure-sensitive
ink, images and attachments, tables, code blocks, themes, autosave, and export to
Markdown, PDF, a plain folder, InkML and JSON Canvas. The OneNote importer handles
`.one` and `.onepkg`, verified page for page against a real 324-page notebook, and
there is a second route over Microsoft Graph that needs no export at all.

**The exit criterion is not met.** It asks for the MVP test to pass on all three
desktop operating systems, and only Windows has been used by a human. CI proves
the other two compile. That is the project's oldest open item and the first thing
on the backlog.

## Phase 2 — Notes that move between your own devices · **mostly shipped**

**The goal:** notes move between a person's own devices reliably, and the app gains
the polish that makes it a daily driver.

Sync works, through two transports: a **folder** that any cloud client already
replicates, and a **git remote with join-by-link** — paste a repository address and
the notebook rebuilds from its operation logs. One writer per file means a
conflicting pair of versions cannot arise;
[ADR-0006](docs/adr/ADR-0006-sync-transport-and-text-model.md) is why that is the
shape. The container has been demoted to a rebuildable cache, opt-in per notebook.

Also shipped in this phase: live page windows onto other pages, the full
open-folder export, Markdown and Obsidian import, tables with two-way GFM interop,
backlinks, a recycle bin, lasso ink selection, page templates, page backgrounds,
find and replace, flashcards from your own notes with spaced repetition, a planner
that subscribes to a timetable, local code cells, an MCP server, keyboard control,
and installers for all three platforms.

**What this phase still owes**, and each is on the backlog: a tablet pass — the
pen toolbar and gestures have never met real hardware — HTML and MathML export,
notebook-wide search, and the block, range and frame embed targets.

## Phase 3 — The switch, and the network

**The goal:** leaving OneNote costs nothing, and more than one person can work in
a notebook.

**Shipped already:** the whole importer, which was this phase's headline and
arrived early because it turned out to be the thing that decides whether anybody
can switch at all.

**Open:**

- **Real convergence for text.** Two devices editing different blocks merge
  cleanly today; two edits to the same paragraph resolve last-writer-wins. Fixing
  that needs the structured text model of [data model
  §5.1](docs/specs/11-data-model-spec.md) and then a sequence CRDT —
  [ADR-0002](docs/adr/ADR-0002-crdt-library.md), whose choice should be re-argued
  first because the op log took over most of what it was chosen for.
- **Live collaboration.** A transport swap over the same operations rather than a
  redesign, and deliberately not wanted yet: shared-folder and git group notebooks
  already cover the group-study case students actually have.
- **Handwriting recognition**, ink-to-text and ink-to-maths. The stroke model is
  recognition-ready and there is no mature fully-open cross-platform recogniser to
  build on, so this waits on evidence that people want it.
- **OCR on images**, which is additive — search already indexes a hidden text
  layer.

## Beyond

Longer-range ideas, each in [PLANNING.md](PLANNING.md) in the owner's own words:
a spreadsheet engine inside a table, audio pinned to notes, maps, flowcharts,
citations and an academic writing mode, and a presentation mode.

Two have been designed and not built, and both have documents:
[everything in one box](docs/planning/v0.19-everything-in-one-box.md) and
[outdoing OneNote at maths](docs/planning/v0.21-outdo-onenote-maths.md).

## Known defects, carried openly

Things that are wrong, that nobody is about to fix, and that are better said out
loud than discovered. The ones being worked on now are in
[v1.0.2](docs/planning/v1.0.2.md) instead.

- **Screen readers cannot read the editor.** The Windows accessibility bridge
  rejects the semantics tree this app produces. This is the worst defect in the
  project and it is being worked on.
- **A small fraction of imported ink strokes are undecodable and dropped.** The
  count is reported after an import, so it is no longer silent, but those strokes
  are not recoverable.
- **The two PDFs in the repository root are stale** and have no source in the
  tree. They predate the current navigator and style guide.
- **The pen's barrel button does not switch tools**, and palm rejection has only
  ever been tested by unit tests on the decision function, never on a real stylus.

---

## How priorities are decided

Every item is judged against one question: **does this help a student the week
before an exam?** Secondary, always: does it keep working for somebody who
switched from OneNote and judges us on whether their daily habits survived.

Where two things are close, the one that is harder to reverse goes first. A format
decision, a storage layout or anything that touches what is already on somebody's
disk is worth more care than a feature, because a feature can be replaced and a
migration cannot be unmade.
