<div align="center">

# Openote

**An open-source, natively cross-platform alternative to Microsoft OneNote.**

*Your notes. Your format. Every platform.*

`Freeform canvas` · `Handwriting & math` · `Open file format` · `Local-first` · `Windows · macOS · Linux · tablets`

</div>

---

> 🚧 **Status: MVP in progress.** The planning/design docs are complete (see the [documentation index](docs/README.md)) and the **walking-skeleton MVP lives in [`app/`](app/README.md)** — a runnable pure-Dart Flutter app writing real `.onote` files (mirror-write mode; the Rust/Loro core slots in behind a stubbed interface later). See [`app/README.md`](app/README.md) for build/run instructions.

## What is Openote?

Microsoft OneNote is, for many people, the best freeform note-taking tool ever made — an infinite canvas where you click anywhere, drop a text box, draw with a pen, and write complex equations, all inside a familiar notebook/section/page structure. Nothing open has matched it.

But OneNote traps your notes in a proprietary format, defaults to a mandatory cloud, has **no native Linux client**, gates core features (like solving math) behind subscriptions, and has ignored years of requests for Markdown, an open format, and backlinks.

**Openote aims to match OneNote's experience with open technology, and fix its structural failings by construction:**

- 🎨 **A genuine freeform infinite canvas** — click anywhere, place anything, pan and zoom in every direction, with free-form *or* snap-to-grid placement.
- 🗂️ **The notebook hierarchy you know** — notebooks, section groups, sections, pages, subpages.
- ✍️ **Rich text with inline-rendered Markdown** — formatting appears where you type it.
- 🪟 **Live page embeds (transclusion)** — render a block, range, or region of another page inside the current one, always up to date, read-only, click-through to the source. OneNote's links only navigate; ours show you the content.
- ➗ **Beautiful math entry** — type linearly and watch it build into 2-D notation (summations with limits, integrals, matrices, fractions), OneNote-style.
- 🖊️ **First-class pen & handwriting** — low-latency, pressure-sensitive ink you can write and draw with anywhere.
- 📦 **An open, documented file format** — local-first, no lock-in, no size limits, readable without us.
- ☁️ **Cloud-optional sync** — work across your devices; bring your own backend; real-time collaboration on the roadmap.
- 🐧 **Truly cross-platform** — desktop-first (Windows, macOS, **Linux**), tablets close behind.

Read the full argument in the [Product Vision](docs/00-product-vision.md).

## Why "Openote"?

**Open** + **note.** It's open, and it's for notes. It's also an invitation.

## Documentation

Start here → **[docs/README.md](docs/README.md)** (the index). In reading order:

| # | Document | What it covers |
|---|----------|----------------|
| 00 | [Product Vision](docs/00-product-vision.md) | Why we're building this, principles, positioning, non-goals |
| 01 | [OneNote Teardown & Gap Analysis](docs/01-onenote-teardown.md) | What OneNote does well, its weaknesses, and the competitive landscape |
| 02 | [Product Requirements (PRD)](docs/02-product-requirements.md) | The full feature spec, prioritized, with the MVP definition |
| 03 | [Technology & Framework Evaluation](docs/03-technology-evaluation.md) | Balanced Flutter-vs-alternatives analysis; the core decision |
| 04 | [Architecture Overview](docs/04-architecture-overview.md) | Layers, document model, open file format, canvas/math/ink/sync |
| 05 | [Style Guide & Design System](docs/05-style-guide.md) | Brand, color, type, components, canvas UX, accessibility, voice |
| 10 | [File Format Spec](docs/specs/10-file-format-spec.md) | The `.onote` container — schema, encodings, versioning, open export |
| 11 | [Data Model Spec](docs/specs/11-data-model-spec.md) | Concrete block structures, identity rules, live-embed references |
| 12 | [Math Input Spec](docs/specs/12-math-input-spec.md) | The linear math grammar and LaTeX/MathML canonicalization |
| 13 | [Ink Data Spec](docs/specs/13-ink-data-spec.md) | Stroke encoding, brushes, InkML interchange |
| — | [ADRs](docs/adr/README.md) | Framework, CRDT, storage, editor-engine, licensing decisions |
| — | [Roadmap](ROADMAP.md) | Phased plan from MVP to real-time collaboration |
| — | [Contributing](CONTRIBUTING.md) | How to get involved (once code begins) |

## Guiding principles

1. **Your data is yours** — open format, documented and versioned from day one.
2. **Local-first, cloud-optional** — fully usable offline, no account required.
3. **The canvas is sacred** — freeform placement, fast startup, and responsive ink are first-class (and we don't trade startup or consistency for micro-latency).
4. **Interpret, don't interrupt** — formatting happens where you type it.
5. **Native feel on every platform** — cross-platform, not lowest-common-denominator.
6. **Open by construction** — an open license, a published format spec, an extensible core.

## Project status & roadmap at a glance

- **Now (2026-07):** a **working desktop app** — freeform canvas, notebook/section/page navigator, live-Markdown text, math blocks, pressure ink, images, tables, code, the open `.onote` format with Markdown/PDF/folder export, and a **native Rust core** linked over `dart:ffi`. Stack decided: **Flutter/Dart UI + Rust core, SQLite `.onote` container** ([ADRs](docs/adr/README.md)); Loro CRDT is specified but not yet wired.
- **Already landed from later phases:** the **OneNote `.one`/`.onepkg` importer** (reverse-engineered MS-ONESTORE — text boxes at true positions, styling, images, equations, ink, whole-notebook packages), plus tables, backlinks, templates, version history, recycle bin, and lossless open-folder export.
- **Next:** the editor-engine bake-off ([ADR-0004](docs/adr/ADR-0004-editor-engine.md)) — now the critical path, since structured rich text gates several stakeholder asks — **license ratification** ([ADR-0005](docs/adr/ADR-0005-licensing.md), still unratified and the repo has no `LICENSE` file yet), and cross-device **sync** on the CRDT core.
- **MVP definition:** desktop, single-device, local-only. See the [MVP definition](docs/02-product-requirements.md#9-mvp-definition-the-core-essentials-cut) and the [Roadmap](ROADMAP.md) for exactly what is and isn't done.

## License

Proposed (pending ratification, [ADR-0005](docs/adr/ADR-0005-licensing.md)): **AGPL-3.0** for the application, **Apache-2.0** for the reference libraries, and **CC0/MIT** for the file-format specification — so the app resists closed forks while the format invites the widest possible ecosystem. Openness is a core requirement, not an afterthought.

## Contributing

Openote is being planned in the open. Ideas, critiques, and expertise (especially on cross-platform ink, rich-text editing, CRDTs, and math input) are very welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

---

<div align="center">
<sub>Openote is not affiliated with or endorsed by Microsoft. "OneNote" and "Microsoft" are trademarks of Microsoft Corporation, referenced here for comparison and interoperability only.</sub>
</div>
