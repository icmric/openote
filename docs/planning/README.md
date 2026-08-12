# Planning documents

One document per release-sized piece of work. They are **not** a backlog —
[`ROADMAP.md`](../../ROADMAP.md) is the sequence, [`PLANNING.md`](../../PLANNING.md)
is Eric's raw asks in priority order, and
[`v0.4-and-beyond`](v0.4-and-beyond.md) is the standing product backlog. These
are the *reasoning*: what was reported, what was measured, which options were
weighed, what shipped, and what it cost.

They are kept after shipping. The changelog says what changed; these say why,
and every one of them has since been re-read to answer a question the code
alone could not.

**House style, for anything added here:** the report in the user's own words,
then a measurement, then the options with what each cannot do, then the
decision. Numbers in tables, not adjectives. Corrections appended rather than
edited over, so a wrong first diagnosis stays visible next to what replaced it.

---

## Open — work that is planned but not finished

Read these before starting anything; each one already contains the thinking.

| Document | State | What it covers |
|---|---|---|
| [v0.12 — make folder sync bomb-proof](v0.12-folder-sync-hardening.md) | **report captured, nothing investigated** | Marked in its own header as *"this before any more git work — folder sync is what most people will use."* Currently the highest-priority unstarted plan. |
| [v0.12 — making sync feel live](v0.12-sync-latency.md) | design note, nothing built | *"Its a bit slow but its working."* Where the latency actually goes, and what would make a two-device edit feel immediate rather than eventual. |
| [v0.11 — the size and speed overhaul](v0.11-size-and-speed-overhaul.md) | **partly built** | Phase 0 (7.3 MB off the install) and the ink-as-bytes conversion (63.09 MB → 3.22 MB of handwriting) shipped; the rest is planned. Pairs with the install-size findings below. |
| [v0.10 — responsiveness and storage](v0.10-responsiveness-and-storage.md) | **partly built** | Four reports, one thread. Images stored twice (fixed, 2.23× → 1.23×); the import writer isolate; the whole-notebook layout request that was itself a freeze; the op-log replay that ran on the UI thread at launch. Wave 1c (PDFs as PDFs) shipped since; waves 1b/1d/1e and the container demotion remain. |
| [Four asks that are features, not fixes](v0.5-boxes-pages-and-documents.md) | nothing built | Everything-in-one-box, and three siblings, sized honestly so they can be picked between rather than started in the order they were said. |
| [Where the install size actually goes](install-size-findings.md) | scoping only | Measured against v0.4.2. Feeds v0.11. |

## Rejected

| Document | State | What it covers |
|---|---|---|
| [Op-log compaction](v0.13-op-log-compaction-review.md) | **rejected as designed** | Designed twice, challenged, not built. 64.56 MB of `.oplog` on the measured notebook is a real problem; the proposed fix was not a safe one. Do not implement without answering every kill-shot in it. |

## Shipped — kept for the reasoning

| Document | What it covers |
|---|---|
| [v0.16 — full keyboard control](v0.16-keyboard-control.md) | Phases 1–2 built. Design-first, like the MCP work: ONE map with a consistency rule and `Ctrl+/` to render it, so every future surface ships keyboard-complete instead of keyboard-someday. |
| [v0.14 — local code](v0.14-local-code.md) | JS and SQL cells that run, sandboxed, output in the note. The sandbox rule is decided first because it is the one thing that cannot be retrofitted. |
| [v0.9 — the performance pass](v0.9-performance.md) | The import rework (background job, batched writes, the lost-popup bug) and why the study tab stopped decoding every page: a SQL tag prefilter and a shared decoded-page cache instead of a maintained index. |
| [v0.8 — events, alerts and the timetable](v0.8-events.md) | Why a subscribed timetable felt like an afterthought: events classified into kinds, per-kind alert lead times, a Join button, an "up next" strip, the in-app alert popup, and the retry ladder that fixed a university feed which would not load at all. |
| [v0.7 — packaging and installers](v0.7-packaging.md) | How a non-technical user actually installs this: Inno Setup and a per-user Windows install, the Linux AppImage and macOS dmg, and the honest cost of code signing. |
| [v0.6 — the UI revamp](v0.6-ui-revamp.md) | The answer to "the UI feels a bit off and unprofessional": a screenshot-driven review naming the causes (two design languages in one window, no token layer, 17 font sizes, an AA-failing text colour) and a five-stage plan. |
| [v0.5 — dates, reminders and the planner](v0.5-dates-and-reminders.md) | Why reminders cannot use the OS scheduler, where a due date lives versus a reminder time versus an exam date, why calendar integration is an ICS subscription rather than an OAuth client, and the brakes that keep a notebook from becoming a to-do app. |
| [v0.3 — the student release](v0.3-student-plan.md) | OneNote parity for students plus the differentiators: PDF slide annotation, flashcards from tags, free math evaluation, group notebooks. |
| [v0.2 — the first public release](v0.2-release-plan.md) | The tiered plan for the first public release: exit checklist, sizes, open decisions. |

## The backlog itself

| Document | What it covers |
|---|---|
| [The standing product backlog](v0.4-and-beyond.md) | Everything **not yet planned into a release document**, ranked by value ÷ effort. Read this to find what to do next; when an item grows a plan it moves to its own file here. |

---

**Two documents are numbered v0.12** — folder-sync hardening and sync latency.
They were written the same day about the same subsystem from different angles
(correctness and speed) and are kept apart on purpose: the first is a bug hunt,
the second a design note.
