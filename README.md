<div align="center">

# Openote

**An open-source, natively cross-platform alternative to Microsoft OneNote.**

*Your notes. Your format. Every platform.*

`Freeform canvas` · `Handwriting & math` · `Open file format` · `Local-first` · `Windows · macOS · Linux · tablets`

</div>

---

> 🚧 **Status: early, but real.** Openote is a working Flutter + Rust desktop
> app — freeform canvas, ink, math, Markdown, an open `.onote` format, sync
> through any folder you already have, a OneNote importer that handles real
> notebooks, flashcards from your own notes, and a planner. It is **not yet
> 1.0**: expect rough edges, and see [TESTING.md](TESTING.md) for what is
> currently unverified. Design and specification documents are in the
> [documentation index](docs/README.md); build instructions in
> [`app/README.md`](app/README.md).

## Install

Grab the latest build from **[openote.org](https://openote.org)** or the
[Releases page](https://github.com/icmric/openote/releases).

| | Download | Then |
|---|---|---|
| **Windows** | `openote-*-windows-x64-setup.exe` | Run it. Installs for your user only, so it never asks for an administrator password. *(Prefer no installer? The `.zip` is the same build — unzip anywhere and run `openote.exe`.)* |
| **macOS** | `openote-*-macos-universal.dmg` | Open it, drag Openote to Applications. |
| **Linux** | `openote-*-linux-amd64.deb` (Ubuntu/Debian/Mint) or `openote-*-linux-x86_64.rpm` (Fedora/RHEL/openSUSE) | Double-click it, or install from a terminal. Openote then appears in your applications menu. *(Neither fits? The `.tar.gz` extracts anywhere and runs with `./openote`.)* |

Your notes are written to your own machine in an open, documented format. There
is no account, and nothing is uploaded anywhere.

On Windows and Linux, the installer also teaches your file manager what a
notebook is: double-click any `.onote` and it opens, in the Openote you already
have running if there is one. From a terminal, `openote path/to/notebook.onote`
does the same thing.

### Your operating system will warn you. Here's why, honestly.

Openote isn't code-signed. Certificates cost a few hundred dollars a year per
platform, and while the project is this young that money buys nothing a user
would notice. The warnings don't mean the software is unsafe — only that we
haven't paid to tell your OS who we are. Every release is built by the
[public workflow](.github/workflows/release.yml) in this repository, from the
tagged commit; you can read both.

- **Windows** — *"Windows protected your PC"*: click **More info** ▸ **Run anyway**.
- **macOS** — *"openote is damaged and can't be opened"*: after copying to
  Applications, run `xattr -cr /Applications/openote.app` once.
- **Linux** — no warning; the `.deb` and `.rpm` install like any other package.

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

- **Now (2026-08):** a **working desktop app** for Windows, macOS and Linux — freeform canvas, notebook/section/page navigator, live-Markdown text, math blocks, pressure ink, images, tables, code, tags, notebook-wide search, spell check, the open `.onote` format with Markdown/PDF/folder export, and a **native Rust core** linked over `dart:ffi`. Stack decided: **Flutter/Dart UI + Rust core, SQLite `.onote` container** ([ADRs](docs/adr/README.md)).
- **Sync between your own devices** works, with no account and no sign-in: a notebook carries a `.onotebook` directory of append-only per-device op logs plus content-addressed blobs, and you put it in a folder your cloud already keeps in step ([ADR-0006](docs/adr/ADR-0006-sync-transport-and-text-model.md)). One writer per file, so two devices cannot produce conflicting logs. Mirrors and dated backups are configurable per notebook.
- **For students specifically:** the **OneNote `.one`/`.onepkg` importer** (reverse-engineered MS-ONESTORE — text boxes at true positions, styling, images, equations, ink, hyperlinks, whole-notebook packages), **PDF lecture slides** imported as an annotatable printout you write on with the pen, and **flashcards** generated from the lines you tagged Question or Definition, with spaced repetition and Anki export.
- **Next:** vector (searchable) PDF export and printing — export is a raster capture today; reclaiming space from deleted images; and demoting the `.onote` container to a purely local cache, which is the remaining half of ADR-0006 §3.
- See the [Roadmap](ROADMAP.md) for exactly what is and isn't done.

## License

Ratified ([ADR-0005](docs/adr/ADR-0005-licensing.md), 2026-07-27) — three tiers, mapped in full in [LICENSING.md](LICENSING.md):

- **[AGPL-3.0-or-later](LICENSE)** — the application. Fork it, self-host it, modify it; improvements stay open, including for hosted forks.
- **[Apache-2.0](rust/onote_core/LICENSE)** — `onote_core`, the `.onote` reader/writer, hashing and importers. **Build anything you like on it, including closed commercial software.**
- **[CC0-1.0](docs/specs/LICENSE)** — the file-format specification. Implement it freely, no attribution required.

The asymmetry is the point: the app resists closed forks, while reading and writing your notes is legally frictionless for everyone. Openness is a constraint we design under, not an afterthought. Contributions are inbound = outbound with a [DCO](https://developercertificate.org/) sign-off (`git commit -s`) and no CLA.

## Contributing

Openote is being planned in the open. Ideas, critiques, and expertise (especially on cross-platform ink, rich-text editing, CRDTs, and math input) are very welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

---

<div align="center">
<sub>Openote is not affiliated with or endorsed by Microsoft. "OneNote" and "Microsoft" are trademarks of Microsoft Corporation, referenced here for comparison and interoperability only.</sub>
</div>
