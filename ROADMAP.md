# Openote Roadmap

> **Status:** v0.2 · **Implementation phase** · Last updated 2026-07-27
> **2026-07-27 fix pass:** the imported-page **layout misalignment is fixed** — root-caused to four renderer constants (line pitch, box inset, indent per level, bullet gutter), each measured against OneNote's own PDF export; the parser's coordinates were already accurate to 0.017 mm. Also landed: flush-on-exit and honest save-failure reporting, atomic `workspace.json`, importer hardening (finite floats, zip-bomb budget, partial-folder recovery, panic guards), partial-import reporting, title-dedup no longer eating body text, ink tilt round-trip, backlinks for bare `[[Page]]`, the notebook manager (+ duplicate), underline, external links, font size, open-attachment, ink-outline caching, and 25 → 82 tests. Later the same day: OneNote **table import** including OneNote's own per-column widths, the **`OUTLINE_GROUP` content-loss fix** (+16 % content boxes), flow re-stacking with real text measurement, imported-image anchoring, the **ADR-0004 editor decision**, a **Unicode font-fallback chain + Alt+X**, and **[ADR-0006](docs/adr/ADR-0006-sync-transport-and-text-model.md)** proposing the sync storage layout. See §K–§O of the [exit review](docs/reviews/2026-07-code-review-phase1-exit.md).
>
> **Accuracy note:** the checkboxes below were reconciled against the code on 2026-07-27 by a full requirement-by-requirement audit of all 102 PRD requirement IDs (see the [Phase 1 exit review](docs/reviews/2026-07-code-review-phase1-exit.md)). Headline: **25 fully done · 47 partial · 6 missing · 24 deferred by design.** A `[~]` box below means "the headline behaviour works, but named sub-requirements don't" — the review names each one. Several previously-`[x]` items were downgraded; several unclaimed ones were credited.
> This roadmap is intentionally **milestone-based, not date-based** — it's a solo/community open-source effort in its earliest days, and sequencing matters more than calendar promises. Priorities trace to the [PRD](docs/02-product-requirements.md).

The guiding sequence: **de-risk the hardest technical unknowns first, ship a genuinely useful single-device MVP, then earn the harder features (sync, import, recognition, collaboration) on a proven foundation.**

---

## At a glance — done · started · next

A cross-cutting summary of *state*, where the phase sections below are organised
by *scope*. Anything marked started has code or a decision in the tree already.

### Decided and shipped
- **The MVP app** — canvas, ink, math, images, attachments, tables, code, export, themes, autosave. Phase 1 is substantially built; the `[~]` items below name what each one is still missing.
- **The OneNote importer** — structure, text, styling, lists, images, equations, ink, `.onepkg` whole-notebook import, and now **tables with real column widths**. Verified page-for-page against a real 324-page notebook.
- **Imported-page layout** — root-caused to four renderer constants, each measured against OneNote's own PDF export.
- **[ADR-0004](docs/adr/ADR-0004-editor-engine.md)** — keep the engine we own, behind the `OnoteTextEditor` seam. The bake-off was not run.
- **Notebook management** — one surface, not two menus; recycle bin with 30-day expiry; duplicate; import feedback.
- **Durability** — flush-on-exit, honest save-failure reporting, atomic `workspace.json` with `.bak` recovery, importer hardening.
- **Unicode legibility** — font-fallback chain verified against the shipped fonts' cmaps; **Alt+X** code-point conversion.

### Started — decided or built, but not finished
- **Sync ([ADR-0006](docs/adr/ADR-0006-sync-transport-and-text-model.md))** — **working between your own devices as of 2026-07-29** (steps 1–3): put a `.onotebook` in any synced folder and pull the other device's changes; one-writer-per-file means conflicts cannot arise, delete wins into the recycle bin, and four two-device tests pin it. Remaining: automatic (rather than click-to-pull) sync, demoting the container to `cache.onote`, the structured `nodes` model, Loro, live collaboration. *Historic note: steps 1–2 were built (2026-07-27): `app/lib/sync/` holds the op envelope, the append-only per-device log in a `.onotebook` directory beside each `.onote`, device identity with fork-on-conflict, the replay materializer with delete-wins, and a recorder that diffs page saves into block-level ops. Blob bytes are written to `blobs/` content-addressed (with a background backfill for notebooks predating the log), and notebook renames are recorded, so a rebuild recovers content and not merely structure. It runs in **shadow mode** — the container stays authoritative and a test asserts that rebuilding a page from the log alone reproduces it. 24 tests. **Remaining:** demote the container to `cache.onote`, the structured `nodes` migration, Loro, and any transport.
- **The structured `{nodes:[…]}` text model** (Data Model §5.1) — the seam it lands behind exists; the model itself does not. Now driven by sync rather than by the editor.
- **CRDT** — the Rust core implements and tests a deterministic merge, but it is **not a CRDT** (add-wins, no delete propagation) and is never called on the save path. Loro is unwired.
- **Image import geometry** — width/height verified to 0.03 mm; **`y` has never been independently validated** because the check was circular. Needs one OneNote PDF export to close.
- **Layering cleanup** — the `export/` write path is **closed** (2026-07-27): `AppState.repo` is private behind a storage facade, and both importers write through it, so there is now exactly one funnel for persistent mutation — the precondition for the op log observing every change. Still to do: the `AppState`/`sidebar.dart` file splits and the `onenote.rs` module split.

> **Detailed next-release plans:**
> - [docs/planning/v0.3-student-plan.md](docs/planning/v0.3-student-plan.md) — **v0.3, the student release** (current): the parity sprint, PDF slide annotation as flagship, flashcards from tags, free math evaluation, group notebooks over shared folders.
> - [docs/planning/v0.2-release-plan.md](docs/planning/v0.2-release-plan.md) — the tiered plan for **v0.2, the first public release** (verification & packaging → data-safety fixes → switcher parity → tags → two-device sync → format freeze), with sizes, the exit checklist, and the open decisions.

### Next, in rough priority order
1. ~~Ratify the licence~~ — **done 2026-07-27.** The repo is legally open source; outside contributions can now be accepted.
2. **Continue the op log — steps 1–2 shipped 2026-07-27, in shadow mode.** ADR-0006 is fully specified: a notebook becomes a **`.onotebook` directory**; sync is **per notebook** (manifest shaped so a section subset can follow without a migration); ops are **block-level in a versioned envelope** (finer text ops become new op types, not a format break); device identity is a **per-install UUID that forks if another install writes to its log**; **delete wins, into the existing 30-day recycle bin**; and an **encryption envelope is reserved but not implemented**. Deferred on purpose: compaction never deletes log prefixes in v1, migration is non-destructive (build beside the `.onote`, don't replace it), and eager-vs-lazy blob fetch waits for a UI to hang a placeholder on.
3. ~~Tags (TEXT-5)~~ — **shipped app-side 2026-07-29**: nine built-in kinds, per-line markers in the gutter, Home-tab picker, click-to-complete to-dos, and a find-tags rollup. **OneNote tag IMPORT is still open** and deliberately so — the property IDs need verifying against a real tagged `.one`, and the same code path has a latent walker bug (type `0x10` mis-sized) that would corrupt working imports if guessed at.
4. **The atom-like inline-math caret (TEXT-1b)** — ADR-0004 criterion 3, explicitly not met.
5. **A CJK/IME pass on Linux + Windows** — ADR-0004 criterion 5, never done.
6. Canvas parity: group/ungroup + alignment guides (CANVAS-7), height/corner resize + ink scaling (CANVAS-4), drag-to-reorder (ORG-2), image paste/drag-drop (MEDIA-1).
7. ~~Bundle Inter + JetBrains Mono~~ — **done 2026-07-29** (OFL, licences beside the assets); the fallback chain now sits behind them and still resolves symbol/PUA glyphs.
8. ~~CI~~ — **added and GREEN on all three OSes, 2026-07-29.** The cross-platform claim (PLAT-1) is verified for the first time: the app analyzes, builds and tests on Windows, macOS and Linux, and the Rust core builds and lints on each. Still unverified: that anyone has *used* the macOS or Linux build.

### Known defects, carried openly
- The markdown emitter sometimes encodes fewer indent levels than the source, leaving a residual horizontal offset on those rows.
- Symbol/Wingdings PUA characters are drawn by those fonts rather than mapped to real Unicode.
- ~~A finger cannot draw at all (INK-1/4)~~ — **fixed 2026-07-27.** Palm rejection is now stylus-*conditional*: a finger draws until a stylus is used, then touch reverts to pan for 2 s so a resting palm can't mark the page. Two fingers always pan. A **Draw ▸ touch-drawing** control offers Auto / Always / Never. *(Verified by unit tests on the extracted decision function; **not yet tried on real touch hardware**.)*
- The two root PDFs (`Openote-Brand-and-Style-Guide.pdf`, `Openote-Product-and-Design-Overview.pdf`) are **stale** and have no source in the repo; they predate the navigator rework and the current style guide.
- ~0.02 % of ink strokes are undecodable and dropped **silently**.

---

## Phase 0 — Foundations (documentation & prototypes) — *gates closed*

> **Note:** implementation ran ahead of this phase's exit criteria, but both decision gates are now closed: ADR-0004 is **decided** (keep the engine we own, behind a seam) and ADR-0005 is **ratified and applied** (2026-07-27) — the repo is legally open source and can accept outside contributions. What remains from this phase is two validation spikes that were never gates: the tablet ink feel-check and the Loro round-trip benchmark.

**Goal:** know what we're building and prove the riskiest parts are feasible before committing to a stack.

- [x] Product vision, OneNote teardown, PRD, technology evaluation, architecture overview, style guide
- [x] **Deep specs:** [File Format](docs/specs/10-file-format-spec.md), [Data Model](docs/specs/11-data-model-spec.md) (incl. live embeds), [Math Input](docs/specs/12-math-input-spec.md), [Ink Data](docs/specs/13-ink-data-spec.md) *(Sync Protocol spec deliberately deferred until CRDT integration is validated in code)*
- [x] **Framework decision:** Flutter/Dart UI + Rust core — [ADR-0001](docs/adr/ADR-0001-application-framework.md) *(provisional, revisit triggers documented)*
- [x] Provisional ADRs: CRDT ([0002](docs/adr/ADR-0002-crdt-library.md) — Loro), storage container ([0003](docs/adr/ADR-0003-storage-container.md) — SQLite `.onote`), licensing proposal ([0005](docs/adr/ADR-0005-licensing.md) — needs stakeholder ratification)
- [x] **Editor-engine decision** ([ADR-0004](docs/adr/ADR-0004-editor-engine.md)) — **Accepted: keep the engine we own, behind the `OnoteTextEditor` seam.** The bake-off was not run: the incumbent already meets criteria 1–2 in shipped code, and both candidates own their own document layout, which fights absolutely-positioned canvas boxes whose geometry must match the importer to fractions of a millimetre. The seam ADR-0004 required of any winner is built and the swap is pinned by a test that installs a substitute engine. *Criteria 3–5 explicitly not met and tracked: atom-like inline-math caret (TEXT-1b), the §5.1 structured-`nodes` migration, and a CJK IME pass on Linux + Windows.*
- [~] **Validation spikes (not decision gates):** first-party canvas core (pan/zoom/cull) ✅ *shipped*; Rust core built, linked over **`dart:ffi`** and toolchain-verified (**26 passing tests**) ✅. Remaining: **ink feel-check on real tablet hardware** (never done — and note a finger currently cannot draw at all, INK-1), and the **Loro round-trip + note-shaped CRDT benchmark** (untouched; `flutter_rust_bridge` was bypassed in favour of hand-written `dart:ffi`, so ADR-0002's integration assumption should be revisited).
- [x] **Ratify the license** ([ADR-0005](docs/adr/ADR-0005-licensing.md)) — **Accepted 2026-07-27, as proposed.** Applied in the tree: `LICENSE` (AGPL-3.0-or-later, the app), `rust/onote_core/LICENSE` + `NOTICE` (Apache-2.0, the core library), `docs/specs/LICENSE` (CC0-1.0, the format spec as the repo's public contract), and [LICENSING.md](LICENSING.md) mapping all three plus the vendored MIT `cab`. `Cargo.toml`'s provisional `AGPL-3.0-or-later` was corrected to `Apache-2.0` — it had contradicted the very ADR it cited. All 15 direct dependencies were audited from their own `LICENSE` files and are permissive (MIT / BSD-3-Clause / Apache-2.0); the recorded invariant is that **`onote_core` must never gain a copyleft dependency**. Contributor terms are inbound = outbound with a DCO sign-off, no CLA. *New revisit trigger recorded: GPL-family licences are widely held incompatible with the Apple App Store's terms, so a first-party iOS/iPadOS build (PLAT-3) must revisit this ADR before that work starts.*

**Exit criteria:** editor engine chosen with spike evidence; license ratified; canvas/ink/CRDT spikes green; a repo ready for application code. **Status: substantially met** — the engine decision (ADR-0004) and the licence are both settled; the app was built ahead of the phase regardless. The residue is the two unrun validation spikes (tablet ink feel-check; Loro round-trip benchmark), which were never decision gates.

---

## Phase 1 — MVP: the single-device notebook ← *we are here (substantially built; polish + gaps remain)*

**Goal:** a OneNote user can install Openote on Windows/macOS/**Linux** and do real work — locally, in an open format, with no account. This is the "core essentials" cut from the [PRD §9](docs/02-product-requirements.md#9-mvp-definition-the-core-essentials-cut).

> **Shipped:** `.onote` SQLite storage (mirror-write mode), stacked notebook/section/page navigator with notebook management + recycle bin, page-surface canvas (pan/zoom both axes, click-anywhere text, drag/width-resize, free ↔ snap-to-grid, viewport culling), pressure-sensitive ink (pen/highlighter/**area eraser that splits strokes**, perfect-freehand rendering), math blocks (linear-input subset → LaTeX → native render), images + file attachments (content-addressed blobs), tables, syntax-highlighted code, light/dark themes from the style-guide tokens, debounced autosave, Markdown/PDF/open-folder/InkML/JSON-Canvas export, Markdown + **OneNote** import, and a **native Rust core over `dart:ffi`**. 82 Dart + 26 Rust tests.
>
> **Interim seams:** text editing is a `TextField` + rendered-Markdown pair with a real as-you-type marker-collapsing controller, now behind the `OnoteTextEditor` engine seam (ADR-0004, decided) — still **not** a structured rich-text model; storage remains the interim Markdown string, and the §5.1 `nodes` migration has one place to land (`serialize`/`deserialize`). `RustEngine` is live for hashing/import; **Loro CRDT is not wired** and the Rust merge is never called on the save path.

- [~] **Freeform canvas:** pan/zoom (both axes), click-to-create text, drag/move, free + snap-to-grid placement, viewport-culled performance *(CANVAS-1–7, 9)* — **gaps:** no **group/ungroup** and no **alignment guides** (both named in CANVAS-7); resize is **width-only** (no height, no corner handles, and ink strokes never scale — CANVAS-4); no level-of-detail rendering (CANVAS-9); snap-to-grid is a global unpersisted flag, not per-page/notebook (CANVAS-5)
- [~] **Notebook hierarchy:** notebook/section/page/subpage, create/rename, navigator sidebar, multiple notebooks *(ORG-1–6)* — **gaps:** **reorder is menu-only, no drag-to-reorder among siblings** (ORG-2); section groups can't actually nest (ORG-1); only one notebook is *open* at a time (ORG-3); no page tags/colour (ORG-5)
- [~] **Rich text + inline-rendered Markdown** with reveal-on-edit; lists, headings, checkboxes; on-page find *(TEXT-1–4, 6, 7)* — **underline** (`++u++`, Ctrl+U), **font size** (points dropdown) and **external `[text](url)` links** (opened via the OS, scheme allow-listed) shipped 2026-07-27. **Alt+X code-point conversion** (type `2200` or `U+2200`, press Alt+X, get `∀`; press again to get the code back — selection-aware, greedy-longest scan, refuses surrogate halves) shipped 2026-07-27. **Remaining gaps:** no **text alignment** (TEXT-1); ` ``` ` doesn't open a fence while typing (TEXT-2); find has **no replace** and is page-only + block-granular (TEXT-7)
- [~] **Math blocks:** linear input, LaTeX canonical storage, native rendering, complex notation, symbol palette *(MATH-1–6)* — **gaps:** the 2-D form renders in a **preview pane below the field**, not built up in place (MATH-2); **no MathML export** (MATH-3/OPEN-4); decorated operators (`\overline`, `\vec`, …) have no linear syntax or palette chip (MATH-5)
- [~] **Ink:** pen/highlighter/area-eraser, pressure, **stylus-conditional palm rejection**, smooth low-latency strokes, undo *(INK-1–6, 11)* — finger drawing shipped 2026-07-27 (INK-1/4: a finger draws until a pen is used; two fingers always pan; Auto/Always/Never control on the Draw tab) and **tilt round-trips** (INK-11). **Remaining gaps:** no whole-stroke eraser mode (INK-6); the touch path has unit coverage but **has never been exercised on real touch hardware**
- [~] **Images** inline; **file attach** *(MEDIA-1–2)* — attachments now **open with the system default app** (MEDIA-2, shipped 2026-07-27). **Remaining gap:** no **paste** and no **drag-and-drop** of images (MEDIA-1 — needs a platform package)
- [x] **Code blocks** with syntax highlighting *(CODE-1)* — dependency-free tokenizer, 16 languages. *(CODE-2: no auto-detect / line numbers.)*
- [~] **The open file format v1:** local-first, no size limits, crash-safe, inspectable; **Markdown + PDF export** *(OPEN-1–5, 10, 11; partial OPEN-7)* — **gaps:** PDF export is **raster, not vector**; no HTML or MathML export (OPEN-7). *(OPEN-1/PLAT-10's licensing requirement is now met — the format spec is CC0-1.0 and the reader/writer is Apache-2.0, so implementing `.onote` carries no licensing friction.)*
- [~] **Light/dark themes**, core design system, baseline accessibility *(PLAT-1, 4, 7, 9)* — **gaps:** **no fonts bundled** so type differs per OS, contradicting style guide §4.1 — mitigated 2026-07-27 by an explicit `onoteFontFallback` chain so maths and symbol characters resolve to *some* installed font (including `Symbol`/`Wingdings` for the PUA characters Office writes) instead of rendering as blank boxes, but bundling a known-coverage font is still the durable fix; `workspace.json` (the notebook registry) is written **non-atomically** — a crash mid-write can leave the app showing zero notebooks (PLAT-9); no adjustable text sizing, no reduced-motion support, no keyboard traversal of canvas blocks (PLAT-5); **no measured performance budgets** despite PLAT-4 specifying them

**Exit criteria:** the [MVP success test](docs/02-product-requirements.md#9-mvp-definition-the-core-essentials-cut) passes on all three desktop OSes. **Currently unverified** — the app is developed and tested on Windows only; macOS and Linux have runner projects but no build/run evidence.

---

## Phase 2 — Own your notes everywhere: sync & polish

**Goal:** notes move between a user's own devices reliably, and the app gains the everyday polish that makes it a daily driver.

- [ ] **Cross-device sync** with **conflict-free CRDT merge** *(SYNC-1, 2)* — the direct answer to OneNote's #1 complaint. *Seeded:* the Rust core implements and unit-tests a deterministic page-mirror merge + content hash, exposed over the C ABI. **Two honest caveats:** the merge is **never called by the app** (deliberately off the local save path — a single-device save is authoritative and add-wins merging would resurrect just-deleted blocks), and it is **not yet a CRDT** — add-wins with **no delete propagation**, so it cannot converge offline deletes. Remaining: the Loro CRDT (ADR-0002) for real convergence, plus a transport. The `RustEngine` *is* live for content hashing and import.
- [ ] **Bring-your-own sync target** (Google Drive/OneDrive, WebDAV/Nextcloud, S3-compatible, synced folder) *(SYNC-3)*
  > **Storage layout decided first — [ADR-0006](docs/adr/ADR-0006-sync-transport-and-text-model.md) (Proposed).** Consumer file-sync services replicate *whole files* and resolve conflicts by making a second copy, so today's one-SQLite-file-per-notebook is close to the worst possible layout for them: two devices editing different pages produce two whole-file versions whose only resolution is `notebook (1).onote`, and the edits are already unmergeable. Proposed instead: a `.onotebook` **directory** with an append-only **per-device op log** (one writer per file ⇒ conflicts cannot arise), content-addressed blobs, and SQLite demoted to a local never-synced cache. This is also what forces the structured-`nodes` text model — an opaque Markdown string makes the smallest edit "the whole block is now this". **Three open stakeholder questions** in the ADR before step 1.
- [ ] **Tablet experience** hardened: pen toolbar, gestures, latency tuning across iPad/Android/Surface *(PLAT-2)*
- [x] **Full open export** — lossless **"materialize as a folder of open files"** (per-page `page.json` mirror + `page.md` + JSON Canvas + InkML + content-addressed assets + manifest), plus single-page **JSON Canvas** and **InkML** exporters *(OPEN-6, 7)*. *(Still to add: **HTML** and **MathML** export; and note **PDF export is a 2× raster capture, not vector** — text isn't selectable or searchable in the output, which undercuts OPEN-7's spirit.)*
- [x] **Import** from Markdown / Obsidian (folder → section, files → pages, nested folders → subpages; front-matter stripped; wiki-links preserved) *(OPEN-9)* — iteration 11. *(JSON Canvas import still to add.)*
- [ ] **Live embeds / transclusion** *(EMBED-2…8)*: render a block, range, or frame of another page inside this one — read-only, live-updating, cycle-safe, with snapshot fallback (built on the MVP's stable block IDs)
- [~] **Tables** *(MEDIA-3)* — full editing, GFM **export**, and **OneNote import** with OneNote's own per-column widths (0x1D66) ✅. **Markdown-table interop is now two-way** (2026-07-27): `markdown/md_table.dart` parses GFM pipe tables — escaped `\|`, `:---:` alignment, ragged rows padded to the header — and the renderer draws them as real tables, horizontally scrollable so a wide pasted table doesn't push the page sideways. Pinned by a round-trip test against `tableToMarkdown`'s own output
- [~] **Backlinks** *(TEXT-8)* — incoming + outgoing panel works, but **a bare `[[Page]]` link produces no backlink** (the refs index skips links without an explicit id, `repository.dart:470`) even though navigation resolves it by title. **Bug, not a gap.**
- [~] **Recycle bin** *(ORG-7)* — soft-delete/restore/purge for notebooks *and* nodes, with 30-day auto-purge; retention is **hard-coded**, PRD asks for configurable
- [~] **lasso-select ink** *(INK-7)* — loop-to-gather, move and delete; PRD's **resize and recolor are missing**
- [~] **page templates** *(ORG-9)* — user-saved templates work; **no built-in templates**, so a fresh install shows an empty list
- [x] **version history** *(SYNC-8)* — throttled snapshots, 30-per-page retention, restore
- [x] **Page backgrounds** *(CANVAS-11)* — blank/grid/dotted/ruled, on the View tab *(was listed as to-do; it is done)*
- [ ] **find-and-replace** across notebook *(TEXT-7)* — on-page find shipped (block-granular, no in-text highlighting); notebook-wide search **and replace entirely** still to add
- [ ] Minimap / off-screen-content hints *(CANVAS-10, 12 — zoom-to-fit and reset-view are done)*, **alignment guides** *(CANVAS-7)*, section/page auto-sort *(ORG-8)*, favourites & recents *(ORG-10)*

**Exit criteria:** a user works across two of their own devices offline and online with no data loss and no conflict dialogs.

---

## Phase 3 — The switch & the network: import, recognition, collaboration

**Goal:** make leaving OneNote painless, make ink smarter, and let people work together.

- [~] **OneNote importer** (`.one`/`.onepkg`) preserving structure, text, images, and — as far as feasible — ink and tags *(OPEN-8)* — the headline migration wedge. **Shipped:** the reverse-engineered MS-ONESTORE/MS-ONE parser imports pages (one per object space, current revision resolved per object) with their **separate text boxes at true positions/widths, rendered at OneNote's font size/metrics** so siblings line up; styled text (**bold/italic/strikethrough, highlight, font, colour** via the 0x1E12/0x1E13 run arrays); bulleted/indented lists; **in-flow images kept inside their text box at display size** (the `![alt](sha256:… =WxH)` dialect, Data Model §5.2) plus floating images at offset-chain positions; **equations** (Office linear-math → LaTeX) as math blocks; **ink** — MS-ISF multi-byte delta paths with pressure, calibrated pen width, colour/alpha — as page-absolute stroke blocks; and **`.onepkg` whole-notebook import** (pure-Rust LZX-CAB extraction) creating a **new notebook** with one section per packaged `.one` (folders → section groups). Pages import in **correct tab order with subpage hierarchy** (SectionNode→PageSeries→PageMetadata, level 0x1DFF) and **ink decodes cleanly** (channel-count inferred by compactness — no more page-crossing scribbles), verified page-for-page against a real 195-page notebook, and later **page-for-page against a real 324-page / 48 MB `.onepkg`** including three levels of subpage nesting.
  **Performance (2026-07-27):** whole-notebook import went **~53 s → ~14 s** — single-pass LZX folder extraction (a vendored two-method `cab` patch; upstream re-decompresses the folder prefix per file, which is quadratic over a one-folder package), **parallel per-section parsing**, `opt-level = 3`, and batched SQLite transactions.
  **Fidelity fixed since:** prose inside math zones no longer runs together — classification is now **per run**, so a sentence containing a symbol is no longer promoted to a whole display equation, and **no path drops a run**; imported images are visible on open (pages now fit-to-width, since images sit at their true OneNote offsets — often right of the text); **`OUTLINE_GROUP` (0x00060019) is now treated as a container**, which alone took one section from 54,713 → 60,643 characters and the full notebook from 985 → 1133 content boxes with pages, images and ink unchanged; **tables** (`TABLE`/`TABLE_ROW`/`TABLE_CELL`, 0x00060022–24) import with **OneNote's own per-column widths (0x1D66)** — cells get the full Markdown dialect, ragged grids are rectangularised, and tables the outline walk never reaches are recovered rather than lost; and boxes from one container now share a **flow id** so the app **re-stacks them using real `TextPainter` measurement**, since the parser can only count *source* lines at a fixed pitch and so undercounted every wrapping paragraph.
  **Remaining:** per-run font size (one font per box today); **tags/checkboxes**; hyperlink URLs; the markdown emitter sometimes encodes fewer indent levels than the source (leaving a residual horizontal offset on those rows); non-PNG images (JPEG/EMF) are never recovered; exact image *positioning* still uses aspect-ratio matching rather than the structural `PictureContainer` (0x1C3F) link; **file attachments** unparsed; **Symbol/Wingdings PUA characters** (`U+F000+n`) are not mapped to real Unicode — currently mitigated by letting those fonts draw them, because Symbol's `0xAC` is `←` while a user typing `¬` means `U+00AC` and the two are indistinguishable after the fact; ~0.02 % of ink strokes undecodable (dropped **silently** — no warning surfaced to the user).

  **Open measurement:** imported image **`y` has never been *independently* validated** — the page offset used to check it was itself derived from an image, so the check was circular. Width and height are confirmed to 0.03 mm and the four in-flow images in the sample carry no position of their own, so this is narrow; closing it needs a fresh OneNote PDF export of a page where the offset is visible.

  > **Import-time vs render-time.** Parser fixes only affect **new** imports: column widths, flow re-stacking and the `OUTLINE_GROUP` recovery are written into the notebook at import, so an existing notebook must be re-imported to gain them. Renderer fixes (font fallback, the healed line-height) apply on restart.

  **Tables now import** — `TABLE`/`TABLE_ROW`/`TABLE_CELL` (0x00060022–24) are parsed, cells get the full Markdown dialect (inline maths, bold, lists), ragged grids are rectangularised, and tables the outline walk never reaches are recovered rather than lost. *Measured: 8 tables in one section, from 0.*
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
