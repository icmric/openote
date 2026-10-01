<div align="center">

# Openote

**An open-source alternative to Microsoft OneNote.**

Freeform canvas, pen, maths and Markdown — in a documented format, on your own disk.

Windows · macOS · Linux

</div>

---

> **It works, and it's young.** Development happens on Windows. Linux gets
> tested occasionally, macOS barely at all. Updates can break things for a
> release. What they can't do is lose your notes: those are files on your disk
> in a [documented format](docs/specs/10-file-format-spec.md) that reads without
> Openote. [TESTING.md](TESTING.md) tracks what's actually been tried by a
> human, as opposed to by the test suite.

## Install

[openote.org](https://openote.org), or the
[Releases page](https://github.com/icmric/openote/releases).

| | Download | Then |
|---|---|---|
| **Windows** | `…-windows-x64-setup.exe` | Run it. Per-user, so no admin password. The `.zip` is the same build if you'd rather not install. |
| **macOS** | `…-macos-universal.dmg` | Drag Openote to Applications. |
| **Linux** | `…-linux-amd64.deb` or `…-linux-x86_64.rpm` | Double-click, or install from a terminal. The `.tar.gz` runs from anywhere. |

No account, no sign-in, nothing uploaded.

A notebook is a folder — `Physics.onotebook` — with a file called **Open this
notebook** inside it. Double-click that, or run
`openote path/to/Physics.onotebook`.

**Your OS will warn you.** Openote isn't code-signed; certificates cost a few
hundred a year per platform and buy nothing you'd notice yet. Every release is
built by [a public workflow](.github/workflows/release.yml) from its tagged
commit.

- **Windows** — *"Windows protected your PC"* → **More info** → **Run anyway**
- **macOS** — *"openote is damaged"* → `xattr -cr /Applications/openote.app`, once
- **Linux** — no warning

## What it does

- **Infinite freeform canvas.** Click anywhere, put anything there. Free
  placement or snap-to-grid.
- **Notebooks, section groups, sections, pages, subpages** — the hierarchy you
  already know.
- **Markdown that renders where you type it.** No preview pane, no raw
  asterisks left on screen.
- **Maths you type linearly and read in 2-D** — summations with limits,
  integrals, matrices, fractions. It solves them too.
- **Pressure-sensitive ink**, with shapes, lasso select and palm rejection.
- **Tables inside your sentences**, code blocks that run, images, video, and
  PDFs you annotate like a printout.
- **Live windows onto other pages** — a region of another page, rendered here,
  always current, click through to the source.
- **Flashcards from your own notes.** Tag a line Question or Definition and it
  becomes a card, with spaced repetition and Anki export.
- **OneNote import** — `.one` and `.onepkg`, from reverse-engineered
  MS-ONESTORE: text at true positions, styling, images, equations, ink,
  hyperlinks.
- **Sync with no server.** A notebook is append-only per-device logs plus
  content-addressed blobs; put it in any folder your cloud already keeps in
  step. One writer per file, so two devices can't produce conflicting logs.
- **A planner**, notebook-wide search, tags, spell check, and export to
  Markdown, PDF or a plain folder of files.

## Known issues

Being worked on for v1.0.2 — full write-ups, including what's been ruled out,
in [docs/planning/v1.0.2.md](docs/planning/v1.0.2.md).

| | What you'd notice |
|---|---|
| **Screen readers can't read the editor** | The Windows accessibility bridge rejects our semantics tree. Console errors, and no usable Narrator/NVDA support. |
| **Formatting buttons are grey in a table cell** | Type Markdown in the cell instead — that works. |
| **Opening a cloud notebook freezes the app** | Only when its folder is not set "Available offline". Set that on each device; the app reads synchronously and waits on the download. |
| **Text scaling is ignored** | Columns and auto-sized boxes are measured at 100%, so Windows' "Make text bigger" misreports widths. |
| **Images dropped on empty canvas can't be inlined** | Two code paths for one thing. Drop onto a text box and it inlines properly. |

Longer-standing defects are carried openly in the
[roadmap](ROADMAP.md#known-defects-carried-openly).

## What's next

v1.0.2 clears the list above. Beyond that: searchable vector PDF export
(today's is a raster capture), splitting `AppState`, and real use of the macOS
and Linux builds. The ranked backlog is
[here](docs/planning/v0.4-and-beyond.md#1-what-to-do-next); the phase plan is in
the [roadmap](ROADMAP.md).

## Documentation

**[docs/README.md](docs/README.md)** is the index. The ones worth knowing about:

- [File Format Spec](docs/specs/10-file-format-spec.md) — the `.onote`
  container. CC0, implement it freely.
- [Architecture Overview](docs/04-architecture-overview.md) — Flutter/Dart UI,
  Rust core over `dart:ffi`, SQLite container.
- [ADRs](docs/adr/README.md) — the decisions and why, including the ones that
  turned out wrong.
- [Product Vision](docs/00-product-vision.md) — what this is for, and what it
  deliberately isn't.

## Licence

Three tiers ([ADR-0005](docs/adr/ADR-0005-licensing.md), mapped in
[LICENSING.md](LICENSING.md)):

- **[AGPL-3.0-or-later](LICENSE)** — the app. Improvements stay open, hosted
  forks included.
- **[Apache-2.0](rust/onote_core/LICENSE)** — `onote_core`, the format
  reader/writer and importers. Build anything on it, commercial and closed
  included.
- **[CC0-1.0](docs/specs/LICENSE)** — the format spec. No attribution needed.

The asymmetry is deliberate: the app resists closed forks, while reading and
writing your own notes is legally frictionless.

Contributions are inbound = outbound, [DCO](https://developercertificate.org/)
sign-off (`git commit -s`), no CLA.

## Contributing

Issues and pull requests welcome. Ink on real touch and stylus hardware,
rich-text editing, CRDTs and maths input are where help goes furthest — see
[CONTRIBUTING.md](CONTRIBUTING.md). Build instructions are in
[`app/README.md`](app/README.md).

---

<div align="center">
<sub>Not affiliated with or endorsed by Microsoft. "OneNote" and "Microsoft" are trademarks of Microsoft Corporation, referenced for comparison and interoperability.</sub>
</div>
