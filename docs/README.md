# Openote Documentation

This is the design and specification documentation for **Openote**, an open-source, natively cross-platform alternative to Microsoft OneNote.

> **Status (2026-07-27):** the project is well past planning. A working Flutter + Rust application lives in [`app/`](../app/README.md) and [`rust/onote_core/`](../rust/onote_core/README.md) — ~11k lines of Dart and ~3.6k of Rust, 82 Dart + 26 Rust tests green. Most of the Phase 1 MVP and much of Phase 2 is implemented, and the Phase 3 headline feature (the reverse-engineered **OneNote `.one`/`.onepkg` importer**) works on real notebooks. These documents are therefore **living specs describing intent**, not a pre-code plan: where a document and the code disagree, the disagreement is a bug in one of them — see the [reviews](#reviews) for the current reconciliation.

## Reading order

The documents build on each other; read them in order for the full picture.

### [00 — Product Vision](00-product-vision.md)
The "why." The problem with OneNote, our vision and mission, the six design principles, who it's for, how we're positioned against OneNote / Obsidian / AFFiNE / others, what success looks like, and our explicit non-goals. **Start here.**

### [01 — OneNote Teardown & Gap Analysis](01-onenote-teardown.md)
A structured teardown of OneNote: its complete feature set, the things it does better than anyone (its "moat"), its most-complained-about weaknesses (ranked), the central file-format lock-in problem, and a survey of the competitive landscape. This is the evidence base for the requirements.

### [02 — Product Requirements (PRD)](02-product-requirements.md)
The "what." Every feature area — canvas, notebooks, text/Markdown, math, ink, media, the open format, sync, and platform/craft — specified with identified, prioritized (MoSCoW) requirements, plus the concrete **MVP definition** and the open questions to resolve.

### [03 — Technology & Framework Evaluation](03-technology-evaluation.md)
The "with what." The evaluation of Flutter, Compose Multiplatform, Tauri, Electron, .NET (Avalonia/MAUI), and Qt against Openote's specific needs — the content-vs-canvas tension, how the stakeholder's priority order (startup speed, consistency, features above pen latency) resolved it in Flutter's favor, and the concrete package-level stack that follows. *(Decision recorded in [ADR-0001](adr/ADR-0001-application-framework.md); the v0.1 balanced analysis is preserved inside.)*

### [04 — Architecture Overview](04-architecture-overview.md)
The "how." Layered architecture (written against the decided Flutter + Rust stack, with a framework-independent domain model), the CRDT-backed document model, the open file-format strategy, and the hard subsystems — canvas, text, math, ink, **live embeds (§4a)** — plus sync. Links down into the technical specs below.

### [05 — Style Guide & Design System](05-style-guide.md)
The "how it looks and feels." Brand and voice, a full color system (light/dark), typography, spacing, iconography, component patterns, canvas interaction guidelines, motion, and accessibility. **v0.4 (2026-08-05)** folds in the operative values decided by the UI review — the chrome type ramp (§4.2a), surface roles (§3.7), the radius/icon sets, the side-panel pattern (§7c) — and rewrites §7b to match the shipped two-column navigator.

## Technical specifications (build-ready layer)

Written against the provisionally-decided stack (Flutter/Dart + Rust core, Loro CRDT, SQLite container — see the ADRs). These are concrete enough to code from.

### [10 — File Format Specification](specs/10-file-format-spec.md)
The `.onote` container: SQLite schema (normative DDL), the CRDT encoding and the JSON "mirror" that keeps the container open in practice, blobs, refs, FTS, versioning, the open-folder export, and interoperability projections (JSON Canvas, MathML, InkML). Written to be publishable as the standalone public format spec.

### [11 — Data Model Specification](specs/11-data-model-spec.md)
The concrete document model: identity rules (eager UUIDv7 everywhere, split/merge semantics), the block envelope and every block type's fields, the text model and its Markdown mapping, frames, and the full **live-embed (transclusion) reference model** — targets, snapshots, tombstones, cycle safety.

### [12 — Math Input & Storage Specification](specs/12-math-input-spec.md)
The OneNote-style linear input grammar (build-as-you-type: fractions, scripts, n-ary operators with proper limits, matrices), normalization to canonical LaTeX, the palette, editing model, and MathML export.

### [13 — Ink Data Model Specification](specs/13-ink-data-spec.md)
Stroke capture and storage (parallel arrays with pressure/tilt/time), rendering via the perfect-freehand pipeline, tools, InkML interchange, and recognition hooks.

### [Architecture Decision Records](adr/README.md)
Framework ([0001](adr/ADR-0001-application-framework.md)) · CRDT ([0002](adr/ADR-0002-crdt-library.md)) · storage container ([0003](adr/ADR-0003-storage-container.md)) · editor engine ([0004](adr/ADR-0004-editor-engine.md) — keep the engine we own, behind a seam) · licensing proposal ([0005](adr/ADR-0005-licensing.md)) · sync transport + text model ([0006](adr/ADR-0006-sync-transport-and-text-model.md), proposed). Each records context, rationale, consequences, and revisit triggers.

## Reviews

- **[2026-08-04 — v0.2-merge & student-release review](reviews/2026-08-code-review-v02-merge.md) ← current.** Independent verification of the v0.2/v0.3 work (294 Dart + 41 Rust tests confirmed green), a read of the new sync/study/PDF subsystems, new findings (a sync liveness gap, the `AppState` god-object risk, blob duplication numbers), the reconciled what's-next order, and the product review for the student audience.
- **[2026-07-27 — Phase 1 exit readiness review](reviews/2026-07-code-review-phase1-exit.md).** Whole-tree audit (Dart + Rust + vendored code + docs) against all 102 PRD requirements. Carries the authoritative **requirement scoreboard** (25 done · 47 partial · 6 missing · 24 deferred), the prioritised findings list, the test-coverage gaps, a OneNote feature comparison, and the recommended order of work. **Read this one first** — the roadmap and PRD were corrected against it.
- [2026-07-22 — MVP iteration-2 code review](reviews/2026-07-code-review-mvp-iter2.md): began as an audit of `app/` (findings F-1…F-7 bugs, G-1…G-9 gaps, D-1…D-9 deferrals; ratified the CANVAS-1 v0.3 page-surface refinement) and has since become the project's **append-only iteration log** — sections A–N covering iterations 3–22, including the OneNote-importer reverse-engineering notes (§L) and the performance pass (§N). Valuable as history; superseded as an assessment.

## Supporting documents

- [Roadmap](../ROADMAP.md) — phased plan from MVP to collaboration.
- [v0.6 UI revamp](planning/v0.6-ui-revamp.md) — the answer to "the UI feels a bit off and unprofessional": a screenshot-driven review that names the causes (two design languages in one window, no token layer, 17 font sizes, an AA-failing default text colour), and a five-stage plan — tokens → component themes → migration → chrome architecture → defect burn-down.
- [v0.5 dates, reminders and the planner](planning/v0.5-dates-and-reminders.md) — **built.** Why reminders cannot use the OS scheduler and what Openote does instead, where a due date lives versus a reminder time versus an exam date, why the calendar integration is an ICS subscription rather than an OAuth client, and the brakes that keep a notebook from becoming a to-do app.
- [v0.3 student plan](planning/v0.3-student-plan.md) — the current plan: OneNote parity for students, plus the differentiators (PDF slide annotation, flashcards from tags, free math evaluation, group notebooks).
- [v0.2 release plan](planning/v0.2-release-plan.md) — the tiered plan for the first public release: exit checklist, sizes, and open decisions (carries the outstanding verification checklist).
- [Contributing](../CONTRIBUTING.md) — how to get involved.
- [README](../README.md) — project overview.

## What remains for a later pass

- **Sync Protocol Specification** — deliberately deferred until the CRDT integration is validated in code (the File Format Spec already fixes the constraint that the server is an opaque-update relay).
- The **editor-engine decision** (ADR-0004) and **license ratification** (ADR-0005) — both process-gated, not writing-gated.

## Document conventions

- Each document carries a status header with its own revision and date — they no longer move in lockstep.
- Requirements are identified (e.g. `CANVAS-3`) and prioritized (Must / Should / Could / Won't-now).
- Claims are grounded in research; figures flagged as single-source should be primary-source-confirmed before any public use.
- These are **living documents** — expected to evolve as decisions and prototypes firm them up. The core commitments (open format, local-first, freeform canvas, cross-platform parity) are the fixed points.
