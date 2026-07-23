# Openote Documentation

This is the planning and design documentation for **Openote**, an open-source, natively cross-platform alternative to Microsoft OneNote. The project is in the **planning & design phase** — these documents define what we're building and why, before any application code is written.

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
The "how it looks and feels." Brand and voice, a full color system (light/dark), typography, spacing, iconography, component patterns, canvas interaction guidelines, motion, and accessibility.

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
Framework ([0001](adr/ADR-0001-application-framework.md)) · CRDT ([0002](adr/ADR-0002-crdt-library.md)) · storage container ([0003](adr/ADR-0003-storage-container.md)) · editor-engine bake-off ([0004](adr/ADR-0004-editor-engine.md)) · licensing proposal ([0005](adr/ADR-0005-licensing.md)). Each records context, rationale, consequences, and revisit triggers.

## Reviews

- [2026-07 — MVP iteration-2 code review](reviews/2026-07-code-review-mvp-iter2.md): full audit of `app/` against the PRD/specs; findings F-1…F-7 (bugs), G-1…G-9 (gaps closed in iteration 3), D-1…D-9 (tracked deferrals). Also ratified the CANVAS-1 v0.3 page-surface refinement.

## Supporting documents

- [Roadmap](../ROADMAP.md) — phased plan from MVP to collaboration.
- [Contributing](../CONTRIBUTING.md) — how to get involved.
- [README](../README.md) — project overview.

## What remains for a later pass

- **Sync Protocol Specification** — deliberately deferred until the CRDT integration is validated in code (the File Format Spec already fixes the constraint that the server is an opaque-update relay).
- The **editor-engine decision** (ADR-0004) and **license ratification** (ADR-0005) — both process-gated, not writing-gated.

## Document conventions

- Each document carries a status header (all currently **Draft v0.1**).
- Requirements are identified (e.g. `CANVAS-3`) and prioritized (Must / Should / Could / Won't-now).
- Claims are grounded in research; figures flagged as single-source should be primary-source-confirmed before any public use.
- These are **living documents** — expected to evolve as decisions and prototypes firm them up. The core commitments (open format, local-first, freeform canvas, cross-platform parity) are the fixed points.
