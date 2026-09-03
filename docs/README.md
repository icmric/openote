# Openote Documentation

This is the design and specification documentation for **Openote**, an open-source, natively cross-platform alternative to Microsoft OneNote.

> **Status (2026-08-11, v0.7.1):** the project is well past planning. A working Flutter + Rust application lives in [`app/`](../app/README.md) and [`rust/onote_core/`](../rust/onote_core/README.md), with **1,071 Dart + 53 Rust tests green**. Phase 1's MVP and most of Phase 2 are implemented; the Phase 3 headline feature (the reverse-engineered **OneNote `.one`/`.onepkg` importer**) works on real notebooks. Since v0.6 the surface has grown fast — git sync with join-by-link, password-protected pages, an MCP server for AI tools, local code cells, keyboard control — and the [standing backlog](planning/v0.4-and-beyond.md) is the ranked list of what has not. These documents are therefore **living specs describing intent**, not a pre-code plan: where a document and the code disagree, the disagreement is a bug in one of them — see the [reviews](#reviews) for the last full reconciliation.

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
The "how it looks and feels." Brand and voice, a full color system (light/dark), typography, spacing, iconography, component patterns, canvas interaction guidelines, motion, and accessibility. **v0.5 (2026-08-05)** adds the alert/interruption rules (§7f-2), the flush-to-edge rule for the shell's fixed regions (§7d), and two strengthened button rules (§7a.2 — a command row never changes shape; a label does not change a command's colour). **v0.4** folded in the operative values decided by the UI review — the chrome type ramp (§4.2a), surface roles (§3.7), the radius/icon sets, the side-panel pattern (§7c) — and rewrote §7b to match the shipped two-column navigator.

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
Framework ([0001](adr/ADR-0001-application-framework.md)) · CRDT ([0002](adr/ADR-0002-crdt-library.md)) · storage container ([0003](adr/ADR-0003-storage-container.md)) · editor engine ([0004](adr/ADR-0004-editor-engine.md) — keep the engine we own, behind a seam) · licensing ([0005](adr/ADR-0005-licensing.md), ratified) · sync transport + text model ([0006](adr/ADR-0006-sync-transport-and-text-model.md)) · blob lifecycle ([0007](adr/ADR-0007-blob-lifecycle.md)) · page protection ([0008](adr/ADR-0008-page-protection.md)). Each records context, rationale, consequences, and revisit triggers.

## Reviews

- **[2026-08-04 — v0.2-merge & student-release review](reviews/2026-08-code-review-v02-merge.md) ← current.** Independent verification of the v0.2/v0.3 work (294 Dart + 41 Rust tests confirmed green), a read of the new sync/study/PDF subsystems, new findings (a sync liveness gap, the `AppState` god-object risk, blob duplication numbers), the reconciled what's-next order, and the product review for the student audience.
- **[2026-07-27 — Phase 1 exit readiness review](reviews/2026-07-code-review-phase1-exit.md).** Whole-tree audit (Dart + Rust + vendored code + docs) against all 102 PRD requirements. Carries the authoritative **requirement scoreboard** (25 done · 47 partial · 6 missing · 24 deferred), the prioritised findings list, the test-coverage gaps, a OneNote feature comparison, and the recommended order of work. **Read this one first** — the roadmap and PRD were corrected against it.
- [2026-07-22 — MVP iteration-2 code review](reviews/2026-07-code-review-mvp-iter2.md): began as an audit of `app/` (findings F-1…F-7 bugs, G-1…G-9 gaps, D-1…D-9 deferrals; ratified the CANVAS-1 v0.3 page-surface refinement) and has since become the project's **append-only iteration log** — sections A–N covering iterations 3–22, including the OneNote-importer reverse-engineering notes (§L) and the performance pass (§N). Valuable as history; superseded as an assessment.

## Supporting documents

- [Roadmap](../ROADMAP.md) — phased plan from MVP to collaboration.
- [Planning documents](planning/README.md) — one per release-sized piece of work, kept after shipping: what was reported, what was measured, which options were weighed, and what it cost. The index separates **open** plans from shipped reasoning and from the one plan that was **rejected**. Currently v0.2 → v0.16, plus the ranked standing backlog in [v0.4-and-beyond](planning/v0.4-and-beyond.md).
- [Releasing](RELEASING.md) — how a commit on `master` becomes a download: the three commands, the four manual steps (publishing the draft, the two Cloudflare secrets, pointing the domain, and the signing decision), what each platform artifact is, why the site is a Worker rather than static hosting, and what to do when a job fails.
- [The pre-release checklist](pre-release-checklist.md) — the manual pass run on the
  packaged build before every release. Action and expected result, about 35
  minutes, deliberately covering only what a headless test suite cannot see:
  real frames, real file dialogs, the installer, the stylus, the update path.
  Complements [TESTING](../TESTING.md), which is the rolling frontier rather
  than the fixed floor.
- [Contributing](../CONTRIBUTING.md) — how to get involved.
- [README](../README.md) — project overview.

## What remains for a later pass

- **Sync Protocol Specification** — still deferred, but the reason has changed. [ADR-0006](adr/ADR-0006-sync-transport-and-text-model.md) replaced the planned CRDT relay with an append-only per-device op log synced through any ordinary folder, so there is no protocol to specify until a *server* transport is wanted. What exists is documented in the ADR and in [File Format Spec §11](specs/10-file-format-spec.md).
- **License ratification** (ADR-0005) — process-gated, not writing-gated.
- **The container demotion** — ADR-0006's own endgame, planned as format 1.1 in the [v0.10 plan](planning/v0.10-responsiveness-and-storage.md#14-wave-2--the-overhaul-demote-the-container-adr-0006s-own-endgame). Gated on the two-machine sync testing in [TESTING](../TESTING.md).

## Document conventions

- Each document carries a status header with its own revision and date — they no longer move in lockstep.
- Requirements are identified (e.g. `CANVAS-3`) and prioritized (Must / Should / Could / Won't-now).
- Claims are grounded in research; figures flagged as single-source should be primary-source-confirmed before any public use.
- These are **living documents** — expected to evolve as decisions and prototypes firm them up. The core commitments (open format, local-first, freeform canvas, cross-platform parity) are the fixed points.
