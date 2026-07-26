# Openote Roadmap

> **Status:** Draft v0.1 · Planning phase · Last updated 2026-07-22
> This roadmap is intentionally **milestone-based, not date-based** — it's a solo/community open-source effort in its earliest days, and sequencing matters more than calendar promises. Priorities trace to the [PRD](docs/02-product-requirements.md).

The guiding sequence: **de-risk the hardest technical unknowns first, ship a genuinely useful single-device MVP, then earn the harder features (sync, import, recognition, collaboration) on a proven foundation.**

---

## Phase 0 — Foundations (documentation & prototypes) ← *we are here*

**Goal:** know what we're building and prove the riskiest parts are feasible before committing to a stack.

- [x] Product vision, OneNote teardown, PRD, technology evaluation, architecture overview, style guide
- [x] **Deep specs:** [File Format](docs/specs/10-file-format-spec.md), [Data Model](docs/specs/11-data-model-spec.md) (incl. live embeds), [Math Input](docs/specs/12-math-input-spec.md), [Ink Data](docs/specs/13-ink-data-spec.md) *(Sync Protocol spec deliberately deferred until CRDT integration is validated in code)*
- [x] **Framework decision:** Flutter/Dart UI + Rust core — [ADR-0001](docs/adr/ADR-0001-application-framework.md) *(provisional, revisit triggers documented)*
- [x] Provisional ADRs: CRDT ([0002](docs/adr/ADR-0002-crdt-library.md) — Loro), storage container ([0003](docs/adr/ADR-0003-storage-container.md) — SQLite `.onote`), licensing proposal ([0005](docs/adr/ADR-0005-licensing.md) — needs stakeholder ratification)
- [ ] **Editor-engine bake-off** ([ADR-0004](docs/adr/ADR-0004-editor-engine.md)): 1–2-week spikes on super_editor and appflowy_editor — "math inline widget + live Markdown + read-only canvas box" — then decide
- [ ] **Validation spikes (not decision gates):** first-party canvas core (pan/zoom/cull) ✅ *(shipped in `app/`)*; Saber-style ink pipeline feel-check on a tablet; Loro-via-FRB round-trip + note-shaped CRDT benchmark — *Rust core crate `rust/onote_core` now exists and its build/test toolchain is verified (13 passing tests); the FRB round-trip and Loro benchmark are the remaining pieces of this spike.*
- [ ] Ratify the license ([ADR-0005](docs/adr/ADR-0005-licensing.md)) and apply it; publish the format spec as the repo's public contract

**Exit criteria:** editor engine chosen with spike evidence; license ratified; canvas/ink/CRDT spikes green; a repo ready for application code.

---

## Phase 1 — MVP: the single-device notebook ← *started (walking skeleton in `app/`)*

**Goal:** a OneNote user can install Openote on Windows/macOS/**Linux** and do real work — locally, in an open format, with no account. This is the "core essentials" cut from the [PRD §9](docs/02-product-requirements.md#9-mvp-definition-the-core-essentials-cut).

> **Walking skeleton shipped:** `.onote` SQLite storage (mirror-write mode), notebook/section/page navigator, infinite canvas (pan/zoom both axes, click-anywhere text, drag/resize, free ↔ snap-to-grid), pressure-sensitive ink (pen/highlighter/stroke-eraser via perfect-freehand), math blocks (linear-input subset → LaTeX → native render), images (content-addressed blobs), light/dark themes from the style-guide tokens, debounced autosave, and unit tests for the math grammar + block round-trip. **Interim seams:** plain-text editing behind the `TextBlockView` seam until the ADR-0004 bake-off; Rust/Loro core stubbed behind `DocumentEngine`.

- [ ] **Freeform canvas:** pan/zoom (both axes), click-to-create text, drag/resize/move, free + snap-to-grid placement, viewport-culled performance *(CANVAS-1–7, 9)*
- [ ] **Notebook hierarchy:** notebook/section/page/subpage, create/rename/reorder, navigator sidebar, multiple notebooks *(ORG-1–6)*
- [ ] **Rich text + inline-rendered Markdown** with reveal-on-edit; lists, headings, links, checkboxes; find *(TEXT-1–4, 6, 7)*
- [ ] **Math blocks:** linear-builds-to-2D input, LaTeX canonical storage, native rendering, complex notation, basic symbol palette *(MATH-1–6)*
- [ ] **Ink:** pen/highlighter/eraser, pressure, palm rejection, smooth low-latency strokes, lossless storage, undo *(INK-1–6, 11)*
- [ ] **Images** inline; **file attach** *(MEDIA-1–2)*
- [ ] **Code blocks** with syntax highlighting *(CODE-1)*
- [ ] **The open file format v1:** local-first, no size limits, crash-safe, inspectable; **Markdown + PDF export** *(OPEN-1–5, 10, 11; partial OPEN-7)*
- [ ] **Light/dark themes**, core design system, baseline accessibility *(PLAT-1, 4, 7, 9)*

**Exit criteria:** the [MVP success test](docs/02-product-requirements.md#9-mvp-definition-the-core-essentials-cut) passes on all three desktop OSes.

---

## Phase 2 — Own your notes everywhere: sync & polish

**Goal:** notes move between a user's own devices reliably, and the app gains the everyday polish that makes it a daily driver.

- [ ] **Cross-device sync** with **conflict-free CRDT merge** *(SYNC-1, 2)* — the direct answer to OneNote's #1 complaint. *Seeded (iteration 11):* the Rust core (`rust/onote_core`) now implements and unit-tests a deterministic page-mirror merge + content hash — the merge semantics of sync, buildable and toolchain-verified today. Remaining: wire `flutter_rust_bridge`, replace `MirrorEngine` with the Rust-backed engine, and move from snapshot-exchange to the Loro CRDT (ADR-0002) for full delete/offline-edit convergence.
- [ ] **Bring-your-own sync target** (WebDAV/Nextcloud, S3-compatible, synced folder) *(SYNC-3)*
- [ ] **Tablet experience** hardened: pen toolbar, gestures, latency tuning across iPad/Android/Surface *(PLAT-2)*
- [x] **Full open export** — lossless **"materialize as a folder of open files"** (per-page `page.json` mirror + `page.md` + JSON Canvas + InkML + content-addressed assets + manifest), plus single-page **JSON Canvas** and **InkML** exporters *(OPEN-6, 7)* — iteration 11. *(HTML/MathML export still to add.)*
- [x] **Import** from Markdown / Obsidian (folder → section, files → pages, nested folders → subpages; front-matter stripped; wiki-links preserved) *(OPEN-9)* — iteration 11. *(JSON Canvas import still to add.)*
- [ ] **Live embeds / transclusion** *(EMBED-2…8)*: render a block, range, or frame of another page inside this one — read-only, live-updating, cycle-safe, with snapshot fallback (built on the MVP's stable block IDs)
- [x] **Tables** *(MEDIA-3)*, **backlinks** *(TEXT-8, incoming + outgoing panel)*, **recycle bin** *(ORG-7)* — iteration 8
- [x] **lasso-select ink** *(INK-7)* — iteration 11 (loop-to-gather strokes into one selection); **page templates** *(ORG-9)* — iteration 10; **version history** *(SYNC-8)* — iteration 10
- [ ] **find-and-replace** across notebook *(TEXT-7)* — on-page find shipped; notebook-wide replace still to add
- [ ] Page backgrounds, minimap, alignment guides, auto-sort *(CANVAS-10–11, ORG-8)*

**Exit criteria:** a user works across two of their own devices offline and online with no data loss and no conflict dialogs.

---

## Phase 3 — The switch & the network: import, recognition, collaboration

**Goal:** make leaving OneNote painless, make ink smarter, and let people work together.

- [~] **OneNote importer** (`.one`/`.onepkg`) preserving structure, text, images, and — as far as feasible — ink and tags *(OPEN-8)* — the headline migration wedge. **Shipped:** the reverse-engineered MS-ONESTORE/MS-ONE parser imports pages (one per object space, current revision resolved per object) with their **separate text boxes at true positions/widths, rendered at OneNote's font size/metrics** so siblings line up; styled text (**bold/italic/strikethrough, highlight, font, colour** via the 0x1E12/0x1E13 run arrays); bulleted/indented lists; **in-flow images kept inside their text box at display size** (the `![alt](sha256:… =WxH)` dialect, Data Model §5.2) plus floating images at offset-chain positions; **equations** (Office linear-math → LaTeX) as math blocks; **ink** — MS-ISF multi-byte delta paths with pressure, calibrated pen width, colour/alpha — as page-absolute stroke blocks; and **`.onepkg` whole-notebook import** (pure-Rust LZX-CAB extraction) creating a **new notebook** with one section per packaged `.one` (folders → section groups). Pages import in **correct tab order with subpage hierarchy** (SectionNode→PageSeries→PageMetadata, level 0x1DFF) and **ink decodes cleanly** (channel-count inferred by compactness — no more page-crossing scribbles), verified page-for-page against a real 195-page notebook. Remaining: per-run font-size, tags/checkboxes, hyperlink URLs, and rare undecodable ink strokes (dropped, ~0.02%).
- [ ] **In-flow images edit as images** *(stakeholder, TEXT-1a)*: while a text box is being edited, an inline `![alt](sha256:… =WxH)` reference should still render as the image (not raw markdown) and be resizable in place — arrives with the structured rich-text editor, whose `{"t":"image"}` inline atom this dialect maps onto 1:1.
- [ ] **Imported-page layout gap** *(stakeholder)*: a small vertical gap can remain between an imported text box and its absolutely-positioned neighbours because Openote's text engine wraps/spaces slightly differently than OneNote's. The asymptotic fix is measuring each imported box with the real text layouter at import time and nudging sibling positions; revisit with the structured editor.
- [ ] **Ink recognition (optional):** ink-to-text, ink-to-shape, ink-to-math via on-device (ML Kit) or commercial (MyScript) engines *(INK-8, 9, 10; MATH-7)*
- [ ] **Real-time collaboration:** live multi-user editing, presence/cursors on the shared CRDT channel *(SYNC-6)*
- [ ] **Sharing & permissions** (notebook and section/page granularity) *(SYNC-7)*
- [ ] **Optional first-party sync service** and **E2E encryption** (blind-relay design, locally-searchable) *(SYNC-4, 5)*
- [ ] **OCR of images** *(MEDIA-4)*, **audio-linked notes** *(MEDIA-5)*, **web clipper** *(MEDIA-6)*, **graph view** *(TEXT-9)*
- [ ] **Phone & web builds** *(PLAT-3)*

**Exit criteria:** a OneNote user can import an existing notebook without losing their work, and two people can co-edit a shared notebook live.

---

## Beyond — "everything app" vision (stakeholder-flagged, future)

- **Math evaluation / CAS.** The editor stores canonical LaTeX; a compute layer (e.g. a Rust CAS crate, or an embedded engine) could evaluate expressions — from basic arithmetic up to matrix multiplication and symbolic algebra. Feasible incrementally: start with numeric evaluation of simple expressions, grow toward CAS. Was a v1 non-goal; re-opened as a future differentiator.
- **Point-and-click math UI.** A structure palette that builds matrices/fractions/integrals visually (OneNote-style) so users needn't learn LaTeX, layered over the existing linear-input engine.
- **Sandboxed code execution.** Run code blocks in a sandbox (WASM runtimes like Wasmtime, or language-specific sandboxes) so scripts execute in-app. Lofty; a security-sensitive, later-stage goal.
- Plugin/extension API (the documented format is the first extension surface)
- Community importers/exporters and format tooling around the published spec
- Advanced handwriting features; richer shapes/diagramming
- Self-hostable sync/collaboration server for teams and institutions

---

## How priorities are decided

When something new is proposed, it's weighed against the [design principles](docs/00-product-vision.md#5-design-principles) and the [non-goals](docs/00-product-vision.md#9-non-goals). Two questions gate everything: *does it protect the canvas and the open format?* and *is it something our core personas (the switcher, the open-source native, the pen-and-math thinker) actually need?* Features that fail either question wait, no matter how interesting.

*This roadmap will be revised as prototypes and real usage teach us where the effort truly is. Sequencing is a hypothesis; the principles are not.*
