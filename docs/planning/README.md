# Planning documents

One document per release-sized piece of work. They are **not** a backlog —
[`ROADMAP.md`](../../ROADMAP.md) is the sequence and
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

| Document | State | What it covers |
|---|---|---|
| [v0.10 — responsiveness and storage](v0.10-responsiveness-and-storage.md) | **partly built** | Four reports, one thread. Images stored twice (fixed, 2.23× → 1.23×); the import writer isolate; the whole-notebook layout request that was itself a freeze; the op-log replay that ran on the UI thread at launch. Waves 1b–1e and the container demotion still planned. |
| [v0.9 — the performance pass](v0.9-performance.md) | built | The import rework (background job, batched writes, the lost-popup bug) and why the study tab stopped decoding every page: a SQL tag prefilter and a shared decoded-page cache instead of a maintained index. |
| [v0.8 — events, alerts and the timetable](v0.8-events.md) | built | Why a subscribed timetable felt like an afterthought: events classified into kinds, per-kind alert lead times, a Join button, an "up next" strip, the in-app alert popup, and the retry ladder that fixed a university feed which would not load at all. |
| [v0.7 — packaging and installers](v0.7-packaging.md) | built | How a non-technical user actually installs this: Inno Setup and a per-user Windows install, the Linux AppImage and macOS dmg, and the honest cost of code signing. |
| [v0.6 — the UI revamp](v0.6-ui-revamp.md) | built | The answer to "the UI feels a bit off and unprofessional": a screenshot-driven review naming the causes (two design languages in one window, no token layer, 17 font sizes, an AA-failing text colour) and a five-stage plan. |
| [v0.5 — dates, reminders and the planner](v0.5-dates-and-reminders.md) | built | Why reminders cannot use the OS scheduler, where a due date lives versus a reminder time versus an exam date, why calendar integration is an ICS subscription rather than an OAuth client, and the brakes that keep a notebook from becoming a to-do app. |
| [v0.4 and beyond](v0.4-and-beyond.md) | **standing backlog** | The product backlog proper, by theme. Read this to find what is *not* yet planned. |
| [v0.3 — the student release](v0.3-student-plan.md) | shipped | OneNote parity for students plus the differentiators: PDF slide annotation, flashcards from tags, free math evaluation, group notebooks. |
| [v0.2 — the first public release](v0.2-release-plan.md) | shipped | The tiered plan for the first public release: exit checklist, sizes, open decisions. |
