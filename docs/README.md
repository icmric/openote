# Openote documentation

Openote is an open-source, cross-platform alternative to Microsoft OneNote. These
are its design documents and its format specification.

**Where a document and the code disagree, that is a bug in one of them.** Each
document says which it expects to be right.

## Start here

| | |
|---|---|
| [00 — Product vision](00-product-vision.md) | Why this exists, who it is for, and §9's non-goals — what it deliberately will not become |
| [02 — Requirements](02-product-requirements.md) | Every feature area as identified, prioritised requirements, plus the MVP definition. `CANVAS-3` and friends are named here and used everywhere else |
| [04 — Architecture](04-architecture-overview.md) | The layers, the document model, and the hard subsystems. The map; the specs are the detail |

Two more are background rather than current state. [01 — OneNote
teardown](01-onenote-teardown.md) is the evidence base behind the requirements,
and does not go stale because it describes a competitor. [03 — Technology
evaluation](03-technology-evaluation.md) is why Flutter and Rust, kept because the
reasoning is what makes the decision reviewable.

[05 — Style guide](05-style-guide.md) is how it looks and speaks. It has not been
read against the shipped theme value by value, so treat a disagreement there as an
open question.

## The format

Written for people outside this project, and licensed CC0 so that implementing it
needs no permission. Read them in this order.

| | |
|---|---|
| [10 — File format](specs/10-file-format-spec.md) | **The one to read first.** What a notebook is on disk: the directory, the operation log, blobs, and the SQLite cache beside them |
| [11 — Data model](specs/11-data-model-spec.md) | What a page holds: identity rules, every block type's fields, the text model, embeds |
| [12 — Maths](specs/12-math-input-spec.md) | The linear input grammar, how it builds into notation, and what gets stored |
| [13 — Ink](specs/13-ink-data-spec.md) | Stroke capture, storage and InkML interchange |
| [14 — MCP API](specs/14-external-api-mcp.md) | The contract with programs that read or write notes. §2's rule — the file format *is* the API — is what keeps it from drifting |

**There is no sync protocol specification, and there does not need to be one.**
[ADR-0006](adr/ADR-0006-sync-transport-and-text-model.md) replaced a CRDT relay
with an append-only log in files that any ordinary folder-sync service
replicates. There is no wire protocol until somebody wants a *server* transport.
The format spec §3 covers what exists.

## Decisions

[Architecture Decision Records](adr/README.md) — eight of them, each with the
context, the options weighed, the consequences, and the triggers that would reopen
it. The index says where each one stands, including the two that were not
implemented and the one whose shipped feature is a knowing compromise.

## Working documents

| | |
|---|---|
| [Roadmap](../ROADMAP.md) | The phased plan |
| [Planning](planning/README.md) | One document per release-sized piece of work, kept for the reasoning. [backlog.md](planning/backlog.md) is what to do next |
| [PLANNING.md](../PLANNING.md) | Eric's asks, in his own words, in priority order |
| [Releasing](RELEASING.md) | How a commit on `master` becomes a download, and the four steps that are manual on purpose |
| [Pre-release checklist](pre-release-checklist.md) | The fixed manual pass before every release, covering only what a headless suite cannot see |
| [TESTING.md](../TESTING.md) | The rolling frontier: built, covered by tests, never touched by a human |
| [Reviews](reviews/) | Three whole-tree audits. History rather than current assessment — the requirement scoreboard in the 2026-07 one is the part still worth reading |

## Conventions

- **Requirements are identified and prioritised** — `CANVAS-3`, Must / Should /
  Could / Won't-now. An id is never reused.
- **MUST, SHOULD and MAY** in the specs are RFC 2119. Anything marked
  *(informative)* is guidance, not a conformance requirement.
- **No document carries a revision number or a date.** Git has both, and a
  hand-maintained date is wrong more often than it is right. A document says
  instead whether it is normative, and what it knows it does not cover.
- **Figures are measured, not estimated.** Where a number is a single source it
  says so.
