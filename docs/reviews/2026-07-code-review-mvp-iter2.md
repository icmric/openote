# Code Review — MVP iteration 2 vs. specifications *(now the iteration log)*

> ⚠ **This document outgrew its title.** It began as the iteration-2 audit and has since accumulated one section per iteration (A–N, covering iterations 3–22, out of alphabetical order — `F` sits between `L` and `M`). Treat it as the project's **iteration log / engineering history**, not a current assessment: the reverse-engineering notes in §L and the performance analysis in §N are the most reusable parts.
>
> **For the current state of the project, read the [Phase 1 exit readiness review](2026-07-code-review-phase1-exit.md) (2026-07-27)** — a whole-tree audit whose scoreboard supersedes the status claims below. Several items marked ✅ here are only partially complete against their full requirement text.

> **Date:** 2026-07-22 · **Scope:** everything under `app/` (20 source files, 2 test files) audited against the [PRD](../02-product-requirements.md) (MVP cut, §9), the [File Format Spec](../specs/10-file-format-spec.md), [Data Model Spec](../specs/11-data-model-spec.md), [Math Input Spec](../specs/12-math-input-spec.md), [Ink Data Spec](../specs/13-ink-data-spec.md), and the [Style Guide](../05-style-guide.md).
> **Verdict:** the format/storage layer conforms well; the interaction layer had **two Must-level spec violations** (F-1, F-2), one **data-loss bug** (F-3), and a cluster of Must-level gaps (multi-select, culling, section groups, find, area-erase). Iteration 3 fixes everything marked ✅; items marked ⏳ are tracked with rationale.

## A. Requirement change ratified in this review

**CANVAS-1 refined (PRD v0.3):** the stakeholder clarified that "unbounded canvas" must *present* like OneNote — a visible **page surface** on a neutral backdrop that **grows automatically** as content approaches its edges, with content never placed above/left of the page origin. The underlying model stays unbounded; the surface is presentation. PRD and Data Model Spec updated (`PageProps.pageWidth`).

## B. Findings — bugs (spec violations in behavior)

| # | Severity | Finding | Spec | Status |
|---|----------|---------|------|--------|
| F-1 | **High** | **Click-anywhere-to-type was gated behind the Text tool / double-click.** CANVAS-3 (Must) requires: click empty canvas → text container → type immediately. | CANVAS-3 | ✅ Single click on empty page in Select mode now creates a text box (when nothing is selected; first click deselects). Empty boxes still evaporate, so stray clicks don't litter. |
| F-2 | **High** | **Canvas was a featureless infinite void** — no page metaphor at all. | CANVAS-1 (v0.3) | ✅ Page surface rendered (default width 900, grows right/down with content), neutral backdrop, pan clamped so the page can't be lost off-screen, initial view centers the page. Backgrounds (grid/ruled/dotted) now draw only on the page. |
| F-3 | **High** | **Data loss on edit exit:** committing math (and empty-box cleanup for text/code) ran in a FocusNode listener, but `select(null)` cleared `editingBlockId` *before* focus was lost, so the commit path never ran — math edits silently discarded; empty math blocks became invisible, unclickable husks ("can't edit boxes after exiting"). | MATH-2/6, PLAT-9 in spirit | ✅ Commit now triggers on the **state transition** (editing→not, detected in build, applied post-frame) — immune to focus-ordering. Empty math blocks also render a visible "empty equation" chip instead of nothing. |
| F-4 | Medium | Clicking a text block required select-then-double-click to edit — friction OneNote doesn't have. | Style guide §8.1 | ✅ Single tap on a text/code/math block now enters editing directly; drag still moves; Esc/click-away exits. |
| F-5 | Medium | Erase claimed "by area" but removed whole strokes near the pointer. | INK-6, Ink Spec §2 | ✅ True area-erase: strokes are **split** — points inside the eraser radius are removed and surviving runs become new strokes (fresh IDs per spec). |
| F-6 | Low | `duplicateBlock` built a throwaway `Block.fromJson` without an `id` (would throw). | — | ✅ (fixed during review, pre-release) |
| F-7 | Low | Status bar save-state didn't update on dirty (markDirty didn't notify). | — | ✅ |

## C. Findings — Must-level MVP gaps closed in iteration 3

| # | Requirement | Was | Now |
|---|-------------|-----|-----|
| G-1 | CANVAS-7 multi-select (Must-core) | single-select only | **Shift-click additive select + marquee** (drag on empty page), group move (incl. ink blocks), group delete; selected ink gets a dashed outline |
| G-2 | CANVAS-9 viewport culling (Must) | every block always built | Blocks outside the (padded) viewport are skipped, using measured render sizes; selected/editing blocks never culled; off-screen ink strokes not painted |
| G-3 | ORG-1 section groups (Must) | absent | Section groups: create, rename, delete, collapse, move sections into/out of groups *(single level for now — nesting tracked, see D-4)* |
| G-4 | ORG-2 reorder (Must) | absent | Move up / Move down for sections and pages via context menu *(drag-reorder tracked, D-5)* |
| G-5 | TEXT-7 find (Should-M) | absent | Find bar (Ctrl+F): live matches across the page's text/code/math, next/prev cycles, centers and selects each match |
| G-6 | TEXT-1a / MATH-1 inline math | `$…$` was plain text | Inline `$…$` and display `$$…$$` **render as real math inside text blocks** (view mode) |
| G-7 | MATH-4 symbol palette | absent | Insert-symbol strip in the math editor (n-ary templates, Greek, operators) — each chip teaches its linear form |
| G-8 | MEDIA-2 file attach (Should-M) | absent | File blocks: attach any file into the notebook's content-addressed blob store; "Save a copy…" extracts it back out |
| G-9 | OPEN-7 PDF export (MVP partial) | Markdown only | **Export page as PDF** (content fitted, rasterized at 2×, single-page PDF) alongside Markdown export *(adds the pure-Dart `pdf` package — run `flutter pub get` once)* |

## D. Tracked gaps (accepted for now, with rationale)

| # | Item | Spec | Why deferred | Lands |
|---|------|------|--------------|-------|
| D-1 | True rich text, span-level as-you-type Markdown, inline math *while editing* | TEXT-1/2/4 | Interim editor by design — awaiting the **ADR-0004 bake-off**; storage dialect already final so no data migration | Bake-off |
| D-2 | Syntax highlighting in code blocks | CODE-1 | `re_highlight` integration is a contained task; kept out to limit this iteration's dependency risk | Next iteration |
| D-3 | FTS index population + `refs` table population | Format Spec §3 | Tables exist but nothing writes them; page-local find (G-5) covers MVP search; workspace search & backlinks are the consumers and are P2 | With workspace search |
| D-4 | Nested section groups | ORG-1 | Single-level shipped; nesting is a sidebar-UI problem, not a model problem (model already supports it) | P2 polish |
| D-5 | Drag-to-reorder in sidebar; drag section between groups | ORG-2 | Move up/down + move-to-group menus cover the function; drag is polish | P2 polish |
| D-6 | Snap-invert modifier key; alignment guides; lasso; minimap | CANVAS-5/7/8/10 | Should/Could-P2 items | P2 |
| D-7 | InkML / JSON Canvas / open-folder export | OPEN-5/6/7 | Spec'd for P2; Markdown+PDF satisfy the MVP cut | P2 |
| D-8 | Stroke `splitFrom` lineage on area-erase | Ink Spec §2 | Survivors get fresh IDs (spec-compliant); lineage field omitted until lasso-history needs it | With lasso |
| D-9 | IME/CJK + screen-reader test pass | PLAT-5/6 | Requires manual testing on real OSes — flagged as the stakeholder-assisted task it always was | Ongoing |

## E. Format-layer audit (passes)

`.onote` schema matches the File Format Spec DDL (application_id `ONOT`, user_version 1, WAL, FK on); mirror-write mode correctly sets `dirty_mirror`; blocks round-trip byte-stable with unknown-field preservation (tested); eager UUIDv7 identity throughout (OPEN-12); strokes stored as parallel arrays with pressure/time, unsmoothed (Ink Spec §1–2); math stored as canonical LaTeX with the user's linear source preserved (`linearSource`) — an app-level convenience field the spec permits under the unknown-field rule; blobs content-addressed by SHA-256 with `blob_refs` maintained. **One deviation:** `page_mirror.mirror_rev` increments correctly but `fts_pages`/`refs` stay empty (D-3).

## E-bis. Iteration 4 (page feel & navigation)

Stakeholder refinements after iteration 3, all implemented:

- **Page reads like a page, canvas on demand.** The page is anchored top-left and grows to fill the window in normal zoom (no backdrop visible); zooming out below 85% reveals its bounds on the neutral backdrop — "a large page that can be a canvas." Panning is pinned to the page origin. Default page width 1100.
- **Intelligent text placement (OneNote-style).** Clicking doesn't land pixel-exact: `smartTextPosition` aligns the new box to the writing margin or a nearby block's edge, snaps vertically to neighbours, and drops the first box of an empty page at the standard top-left spot. (PRD CANVAS-3 note extended.)
- **In-page title.** The page title + date render at the top of the page itself (`PageTitleView`), editable in place — no menu. The old title bar became a slim notebook › section breadcrumb.
- **Drag-and-drop navigation (ORG-2/6/1).** Drag a page onto a section → move it there; drag a page onto another page → make it a subpage; drag a section onto a group → file it under the group. Live drop-target highlighting.

## G. MVP status (PRD §9) — assessment

| MVP area | State |
|----------|-------|
| Freeform canvas (pan/zoom both axes, click-to-create, drag/resize, free+snap, page surface) | ✅ met |
| Notebook hierarchy + navigator (notebook/section/**group**/page/**subpage**, create/rename/**reorder**/**drag-drop**, multiple notebooks) | ✅ met |
| Math (linear→2D, LaTeX storage, native render, complex notation, palette) | ✅ met (grammar is a growing subset) |
| Ink (pen/highlighter/eraser, pressure, smooth, lossless, undo, area-erase) | ✅ met; **partial:** stylus-vs-touch palm rejection needs real-device tuning |
| Images, file attach, code blocks | ✅ met; **code syntax highlighting deferred** (D-2) |
| Open format, local-first, no limits, crash-safe, inspectable, MD+PDF export | ✅ met |
| Light/dark themes, undo/redo, shortcuts, find | ✅ met |
| **Rich text + inline-rendered Markdown (TEXT-1/2/4)** | ⏳ **interim** — view-mode Markdown + inline math render, but true span-level as-you-type editing awaits the **ADR-0004 editor bake-off**. This is the one substantial MVP gap, and it is by design the next stage. |
| Page links by stable ID (EMBED-1) | ⏳ not yet surfaced in UI (eager UUIDs exist; link-insertion UX is small and can ride the editor work) |
| Accessibility pass (PLAT-5) | ⏳ untested — needs real-device screen-reader/IME verification |

**Verdict:** the MVP is **functionally met across every pillar except the real rich-text editor**, which was always gated behind ADR-0004 and is the logical next stage. Everything else deferred is either P2-scoped or a small follow-on (syntax highlighting, page-link UI, a11y verification).

## E-ter. Iteration 5 (MVP polish) — gaps closed

Stakeholder chose to round out the MVP before the editor bake-off. Closed:

- **Code syntax highlighting (CODE-1 complete).** A dependency-free single-pass tokenizer (`editor/code_highlight.dart`) covering ~15 languages (comments, strings, numbers, keywords, types). Chosen over an external grammar package to guarantee compilation; swappable for `re_highlight` later without touching call sites. *(Closes D-2.)*
- **Page links (EMBED-1 complete).** `[[Page|id]]` wiki-links render as clickable chips that navigate by **stable id** (title fallback); inserted via Insert ▸ Link to page or typed directly. *(Closes the EMBED-1 gap in §G.)*
- **Palm rejection (INK-4 hardened).** In ink tools, stylus/mouse draw while touch pans/pinch-zooms — a resting palm never marks the page (OneNote's default).
- **Accessibility (PLAT-5 light pass).** Blocks expose their type + content, the page title and controls carry semantic labels. Full screen-reader/IME verification on real hardware remains the tracked device-side task.

With these, the only MVP item still open is the **real rich-text editor (ADR-0004 bake-off)** — the agreed next stage.

## E-quater. Iteration 6 (live editor + feel)

- **Live-Markdown editing (TEXT-2/4 substantially delivered).** A custom `LiveMarkdownController` renders Markdown as you type — markers collapse when a construct completes and reveal when the caret re-enters — with a span-coverage safety net that falls back to plain text if parsing ever diverges (so editing can't corrupt). This realizes the "interpret as you go" requirement without an external editor package; the [ADR-0004](../adr/ADR-0004-editor-engine.md) block-editor bake-off remains an option for full block semantics but is no longer on the MVP critical path.
- **Keyboard bug fixed (was blocking usage).** Bare-letter `Shortcuts` shadow text fields on Flutter desktop (EditableText inserts printable chars via the text-input channel, so ancestor shortcuts win the raw key). Rewrote to a global `HardwareKeyboard` handler that detects a focused editable and only intercepts Escape then. *This is why several letters were untypeable.*
- **VS Code-style selection wrap** (`WrapSelectionFormatter`).
- **Image** hover-flicker fixed (cached provider + `gaplessPlayback`) and **proportional resize** via recorded intrinsic aspect.
- **Collapsible hierarchy** for section groups, sections, and pages-with-subpages.
- **Seamless page** at normal zoom (fills the window) → bounded sheet when zoomed out; **snap-to-grid default on** with the grid shown only during a drag; **ongoing left-margin snap** on drop.

## H. Post-MVP review (iterations 4–6 audit) & Phase 2 kickoff (iteration 7)

**Audit result:** the iteration-4–6 code held up well against the specs; three defects found and fixed in iteration 7 — (1) blocks stored `z` but painted in insertion order, so z-order was decorative (now sorted at paint); (2) repeated drag-to-subpage drops onto the same target produced colliding position keys (now time-suffixed); (3) Data Model Spec had drifted from code on `pageWidth`/`gridSize` defaults and the seamless-page presentation (docs updated to PRD v0.4). The style guide's "no fixed toolbar tabs" stance was formally revised: the stakeholder explicitly values OneNote's few-clicks accessibility, so §7 now specifies the **tabbed command bar** (Home/Insert/Draw/View + context menus, ≤2 clicks to most actions).

**Phase 2 UI workstream (iteration 7) delivered:** the tabbed command bar; right-click context menus on blocks and canvas; selection-aware formatting commands (wrap + line-prefix toggles, Ctrl+B/I) acting on the live editor via an active-editor registration seam; an internal block clipboard (copy/cut/paste with fresh IDs); z-order commands; and a user-facing theme mode (Auto/Light/Dark). Remaining Phase 2 backlog, in rough order: tables, lasso-select ink, backlinks panel, recycle bin, page templates, version history, full open export (open-folder materialize, InkML, JSON Canvas), Obsidian/Markdown import, tablet/pen hardening, then sync (Rust core).

## I. Iteration 10 review — UI standards, performance, session state

**Docs first (stakeholder-requested):** Style Guide gained **§7a Interaction & component behaviour standards** — normative specs for menus, buttons/clicks, split-buttons, dialogs/pickers (incl. the colour-picker and searchable-font-picker standards), shortcuts-as-accelerators-only, state persistence, and UI latency budgets (page switch <100ms, keystroke <16ms, no hot-path JSON decoding).

**Fixes:** app icon now ships as a real multi-size `.ico` replacing the runner resource (tool-independent); auto-width grows *ahead of need* with slack (no more edge clipping); colour is now the §7a split-button + full picker (palette grid, recent/custom persisted, hue+SV field, RGBA sliders, hex — supports alpha `{{#RRGGBBAA}}`); fonts enumerate the **actual system fonts** (TTF/TTC/OTF name-table parser over platform font dirs, searchable picker, per-face preview); the colour hotkey is shortcut-only (removed from menus).

**Performance review findings & fixes:** (1) **ink strokes were JSON-decoded every frame** — now cached per `block.id#updatedAt` and the ink layer sits in its own `RepaintBoundary` with cheap repaint checks; (2) auto-width measurement is single-TextPainter per edit, acceptable; (3) page switch is one SQLite read + JSON parse (fast); notebooks open lazily and stay open. Budgets now documented in §7a.6.

**Session state (§7a.5) implemented:** per-page scroll+zoom memory (in-memory, persisted to `workspace.json` settings), last notebook + page restored on launch, custom colours persisted.

**Also landed:** **version history** (SYNC-8 — throttled snapshots into `page_versions` on save, 30 kept, restore dialog via page right-click; idempotent migration adds the table to existing notebooks) and **page templates** (ORG-9 — save current page as template, apply from Insert tab).

**Remaining Phase 2 (non-Rust):** lasso-select ink (INK-7), the full open-export suite (open-folder materialize, InkML, JSON Canvas), and Markdown/Obsidian import (OPEN-9). Next batch.

## J. Iteration 11 — Phase 2 rounded off + the Rust core lands

Stakeholder confirmed Rust is installed and asked to finish Phase 2 (remaining components + a real Rust core) and do a consistency pass. Delivered:

**Two reported nitpicks fixed.** (1) *Colour re-set no longer nests.* `applyTextColor` now detects when the selection is already the inner content of a `{{#hex …}}` wrapper (or spans a whole wrapper) and rewrites the hex in place instead of wrapping again — three explicit cases (inner-content, whole-wrapper, fresh) with a `dotAll` whole-wrapper regex. (2) *Auto-width no longer lags into a wrap.* Measurement moved out of the child's build (which ran a frame after the parent had already sized the container) into the **parent** `BlockView` build, so an auto-width text box grows in the *same* frame its text changes. To keep pan/zoom cheap, only the block being *edited* is measured live; others reuse their stored width. The measured width is written back to the model so persistence/export/hit-testing agree with the screen.

**Pop-out page menu + inline rename (§7a.1).** The section/group/page right-click menu is now a pointer-anchored `showMenu` (was a centred `SimpleDialog`), focused on menu-only actions — move up/down, move-to-group, make-subpage/promote, version history, save-as-template, delete. Rename left the menu and became **double-click inline rename** on the tile itself (autofocus, select-all, commit on Enter/blur, cancel on Esc), which also meant the three navigator tiles became `StatefulWidget`s.

**Lasso-select ink (INK-7).** A new Draw-tab **lasso** tool: draw a freeform loop; on release, every stroke whose points are ≥60% inside the polygon (ray-cast point-in-polygon) is spliced out of its source blocks and re-homed into one new selected ink block, so the existing move/delete/copy machinery works on a freeform ink selection regardless of original block grouping. Emptied source blocks are dropped; undo snapshots the true pre-lasso state.

**Full open-export suite (OPEN-6/7).** New `export/open_export.dart`: **materialize the whole notebook to a folder** (section/page hierarchy as nested folders, each page carried by a fidelity `page.json` mirror + convenience `page.md` + `page.canvas` + `page.inkml` when it has ink + content-addressed `assets/`, plus a `manifest.json`); single-page **JSON Canvas** (`.canvas`, Obsidian-compatible) and **InkML** exporters, wired into the export menu. Freeform layout flattens to reading order for Markdown; JSON keeps exact coordinates (File Format Spec §8).

**Markdown / Obsidian import (OPEN-9).** New `export/md_import.dart`: pick a folder, its tree maps to a section with files→pages and nested folders→folder-pages/subpages (depth clamped 0–2); YAML front matter and a duplicate leading H1 are stripped; body lands as one live-Markdown block so `[[wiki-links]]`, tables, lists render immediately. Wired into the notebook menu.

**The Rust core is real and toolchain-verified (`rust/onote_core`).** Rather than blind-write the whole Loro CRDT stack untested, the first slice is the piece the sync design needs most and can be proven now: a deterministic, conflict-free **page-mirror merge** (block-level last-writer-wins over the snapshot-exchange model, canonical output, forward-compatible field round-trip) plus an FNV-1a **content hash** for cheap change-detection, exposed to Flutter through an opt-in `flutter_rust_bridge` `api` module. It builds and **`cargo test` passes 13/13** (newer-wins, union, idempotence, commutativity, unknown-field survival, hash vectors) with only `serde`/`serde_json` on the default path — so a contributor verifies their toolchain with one command. The Dart app is untouched at runtime: `MirrorEngine` stays the `DocumentEngine`, so shipping never blocks on the bridge being wired (guide + steps in `rust/onote_core/README.md`; the Loro-backed engine replaces `merge` behind the same API later, ADR-0002).

**Consistency pass.** Balanced-bracket tokenizer over every edited/new Dart file (clean); a cross-file compile-correctness review caught one real blocker before it shipped — the auto-width statics were placed on the private `_TextBlockViewState` where the canvas layer couldn't reach them, now relocated to the `TextBlockView` widget class. `cargo test` green.

**Still open for Phase 2:** live embeds/transclusion (EMBED-2…8), cross-device sync itself (SYNC-1/2/3 — needs the Loro engine behind `merge` and a sync transport), tablet/pen hardening, find-and-replace across a notebook, and the minor canvas polish (minimap, alignment guides).

## K. Iteration 12 — Rust core linked into the app (dart:ffi)

Stakeholder asked whether the Rust core was actually used (it wasn't — the app ran 100% on the Dart `MirrorEngine`) and to integrate it. Done, via **`dart:ffi` with a graceful fallback** rather than flutter_rust_bridge: FRB needs a codegen step that can't run in the build sandbox (so the Dart glue would be hand-written blind), whereas a small C-ABI shim is fully authored *and* compile-tested here.

- **Rust:** new `src/ffi.rs` exposes `onote_core_version` / `onote_core_merge` / `onote_core_page_hash` / `onote_core_string_free` as `extern "C"` (CString ownership handed to the caller, freed back through the shim). No new deps. `cargo test` now **16/16**, and `cargo build --release` produces the real cdylib.
- **Dart:** `core/onote_ffi.dart` loads the library from several candidate locations (next to the exe, the crate's release dir, bare name), verifies a call round-trips before trusting it, and marshals strings via `package:ffi`. `OnoteCore.instance` is null when the library is absent, so **linking Rust cannot break the app** — with it present the app uses it; without it, behaviour is byte-identical to the Dart-only build.
- **Live use:** startup runs a merge self-test to set the engine label; every save hashes the current page's mirror through Rust (a real Dart→Rust→Dart round-trip over live content — the change-detection primitive sync will use). Both surface in the status bar as a green `Rust core vX · <hash>` chip (grey `Dart engine` on the pure-Dart path).
- **Build wiring:** the desktop platform folders aren't in this repo copy, so integration ships as `rust/onote_core/INTEGRATION.md` — a zero-CMake "build the DLL, drop it next to the exe, see the green chip" quick path (verifiable immediately) plus an optional `windows/CMakeLists.txt` POST_BUILD snippet to compile+bundle it automatically. Prereq noted: `cargo` on PATH (the "unrecognised" terminal issue).

The FFI `merge` is linked and tested but still off the user-facing path — it activates when the sync flow is built. Next: a `RustEngine` implementing `DocumentEngine`, then Loro behind `merge` (ADR-0002) and a sync transport.

**RustEngine (same iteration).** `DocumentEngine` gained a real Rust-backed implementation, selected automatically when the core is linked (else `MirrorEngine`). It routes all persistence through Rust: every page is content-hashed, and a save whose hash matches the last persisted state is **skipped entirely** (no mirror write, no version-history snapshot) — killing the redundant writes that a debounced autosave fires when nothing actually changed, while deletions still persist (removing a block changes the hash). Deliberately, `merge` is *not* on the local save path: a single-device save is authoritative, and add-wins merge against the stored copy would resurrect just-deleted blocks. Version-snapshot + write moved out of `AppState.flushSave` into the engine, centralising persistence behind the seam.

## L. Iteration 13 — OneNote `.one` import (reverse-engineered)

Stakeholder supplied a real `.one` section (Office-365 OneNote, Win 11) and a `.onepkg`. The `.one`/MS-ONESTORE format is barely documented in practice, so the parser was reverse-engineered empirically in Rust against the actual bytes (`rust/onote_core/src/onenote.rs`):

- **Container** — validated the ONESTORE header (`guidFileType` = .one section; `cbExpectedFileLength` matched the file exactly), then walked from `fcrFileNodeListRoot` through `FileNodeListFragment`s (header/footer magics, `nextFragment` chains, `BaseType==2` sub-list refs) collecting `BaseType==1` object declarations and their `FileNodeChunkReference` blob refs.
- **Objects** — parsed each `ObjectSpaceObjectPropSet` (OID/OSID/context streams → `PropertySet` → `PropertyID` type/size walk). Property IDs were identified empirically by decoding and matching to the notebook: **`0x001C22`** = `RichEditTextUnicode` (body text), **`0x001CF3`** = page title, **`0x001DD7`** = image name. The JCID histogram matched known MS-ONE node types (rich-text, image ×5, outline), confirming the walk.
- **Content out** — for the sample: title "Lecture", 3 text blocks (real networking-lecture content), and 4 inline PNGs (recovered by signature→IEND scan; dimensions read from IHDR), all validated (321×254 etc.). A specially-encoded run (an embedded **math equation**) is filtered by a readability check rather than imported as garbage.
- **Wiring** — new FFI `onote_core_import_one(ptr,len)→JSON`; Dart `OnoteCore.importOne`; `export/onenote_import.dart` turns the JSON into a section → page(s) with text blocks + content-addressed image blobs, stacked in reading order; menu item "Import OneNote (.one)…". 18/18 crate tests pass.

**Scope & limits (v1):** brings **text + images** across from `.one` files. Not yet: `.onepkg` (an LZX-compressed CAB — needs a pure-Rust LZX decompressor), exact canvas layout/positions, multi-page-per-section segmentation, math equations, and ink. Requires the linked Rust core (the binary parse can't be done in pure Dart).

### L.2 — Full text + hierarchy (iteration 14)

The v1 extraction only recovered a handful of runs and misdecoded some. Testing against a PDF export of the same page showed the whole outline was missing. Two root causes, found and fixed against the real bytes:

- **Wrong text property + encoding.** The body outline text is property **`0x003498`** stored **UTF-8** (not the UTF-16 `0x001C22` v1 keyed on — that one only holds diagram-label text). Confirmed by searching the raw file: "Internet", "Packet Switches" exist as ASCII, not UTF-16.
- **No reading order / hierarchy.** Objects are stored in dependency order, not document order. Fixed by reconstructing the object graph: each object declaration's own CompactID indexes a map; property **`0x001C20`** and the OID stream give ordered child references; a DFS from each Outline/Title node (Page → Outline → OutlineElement → RichText → runs) yields text in true reading order, and nesting under paragraph nodes reproduces the **indent levels**. Outlines are deduped across revisions (first-line key, longest wins) and ordered by vertical offset (`0x001C02`).

Result on the sample: the page's ~90-line hierarchical outline imports **line-for-line and indent-for-indent identical to the OneNote PDF**, plus the original title/date-time block ("Tuesday, 29 July 2025 · 8:05 AM") and all 4 images. Emitted as indented Markdown bullets (one text block per outline); Dart lays notes down the left and images in a right-hand column. Math runs are still skipped; per-run bold and exact pixel positions remain future polish.

### L.3 — Fidelity pass + a canvas hit-test bug (iteration 15)

Testing against the PDF surfaced several issues, all fixed:

- **Canvas bug (not import-specific): tall boxes ignored clicks below a point.** The page-space `Stack` was sized to the viewport (`Positioned.fill`), and Flutter won't hit-test children positioned beyond a render box's own size — so clicks on the lower half of a long text box fell through and spawned a new box. Fixed by giving that layer loose constraints (`Positioned(left:0, top:0)`) and sizing the Stack to the **full page** (`SizedBox(pageSize)`), so every block is hit-testable at any length.
- **Everything imported as a bulleted list.** OneNote marks list items with a `NumberListNode` child (167 of 235 paragraphs here; the other 68 are headings) and stores the bullet in prop `0x001C1A` (a literal "-"). The importer now bullets only real list items and leaves headings flush-left, with the original bullet, indented by depth for the renderer.
- **Title/date duplicated.** The title/date lines were also glued onto the end of the main outline; they're now collected from the Title node and filtered out of content outlines. The original created date is parsed from that text and set as the page's `createdAt`, so the in-page date band shows the original date, not today's.
- **Layout + overlap.** Images are correlated to their objects by natural pixel size and placed at their real page coordinates (units calibrated at ≈60 px/unit); imported text boxes are pinned to a fixed width (`autoWidth:false`) so a long line never grows the box over an adjacent image. Also revealed: the images' vertical offsets (13 cm, 48 cm, 62 cm) show the section spans **multiple OneNote pages** merged into one Openote page — proper page-splitting, per-run bold, and math remain the next steps.

### L.4 — Object spaces, unified boxes, in-flow images, ink (iterations 16–17)

Testing against two real files (a lecture section + a second page with pen annotations) drove four structural fixes and one new subsystem:

- **Object spaces & revisions (the merge bug).** CompactID OIDs are only unique per ONESTORE object space, and objects repeat across appended revisions. The parser now tags every object with its space (FileNode id 0x008 crosses a boundary), resolves OIDs per space, and takes each OID's **highest-file-offset occurrence** as current — the old first-wins rule read a stale page root that dropped two boxes and two images. Each content space imports as its own page; the page root's 0x1C20 children are the page's boxes, each with real offsets (0x1C14/15) and width (0x1C1B). OneNote coordinates are used verbatim (their origin includes the title area ≈ our page origin).
- **In-flow images / unified boxes (Data Model §5.1 made real).** `MarkdownView` now renders `![alt](sha256:<hash>)` lines as images resolved from the blob store (cached; `blob_refs` maintained from text refs), so a text box is a true mixed-content container. The importer keeps an image-as-list-item **inside its box's markdown** instead of splitting the box or floating the image — OneNote's container behaviour, and the fix for the "mystery gap" (flow-height estimates are gone; the real renderer lays it out). Spec §5.2 documents the dialect.
- **Equations** import as their own math boxes beside the text (matching OneNote's separate equation object).
- **Trackpad panning.** Block drag/resize gestures exclude `PointerDeviceKind.trackpad`, so two-finger scrolls over a block pan the canvas (trackpad click-drags arrive as mouse events and still move blocks).
- **Ink import (OPEN-8).** Decoded OneNote's ink model empirically + via the open-source `onenote.rs` parser's property tables: InkContainer (0x00060014, scaling 0x1C46/47) → InkDataNode (0x0002003B) → InkStrokeNode (0x00020047) with the packed path in 0x340B — an MS-ISF multi-byte stream (7-bit varints, LSB sign, length-prefixed) of **per-dimension delta blocks** (absolute first value, cumulative sum). Dimension GUIDs from the stroke-properties node (0x0012004D-sibling 0x00120048) select X/Y/pressure; pressure normalises by its limits into Openote's `p[]`; pen size (HIMETRIC → px at 120 dpi), colour (COLORREF) and alpha map onto the stroke brush. Default unit calibrated at 1270/half-inch. A page's strokes land as one ink block with page-absolute coordinates (Ink Spec §3). Verified on a 184-stroke page: bounds within the page, smooth paths, sensible pressure.

### L.5 — Layout fidelity, visible ink, `.onepkg` notebooks (iteration 18)

Stakeholder testing of L.4 surfaced three issues, all root-caused:

- **The "mystery gaps."** Two causes, both height-estimation: (1) imported boxes rendered at Openote's default 15px/1.5 text metrics while their absolutely-positioned siblings sat at OneNote-height positions — boxes now import with `fontSize`/`lineHeight` content overrides (dominant run size in pt → px at the page's 120 dpi, line spacing 1.32) so heights track the source; (2) in-flow images rendered at natural pixel size instead of OneNote's display size — the dialect gained an optional ` =WxH` suffix (`![alt](sha256:… =266x232)`), emitted by the importer and honoured by `MarkdownView`.
- **"Invisible" ink.** The strokes were stored and rendered — as sub-pixel hairlines. A 0.25 mm OneNote pen mapped to 1.18 px, then the painter's pressure thinning (×0.3–0.6) cut it below a pixel. OneNote draws pens ~2× nominal tip width; the importer now applies that factor with a 1.8 px floor. (Diagnosis included a headless data-path check, `app/tool/check_ink.dart`, which verified 184 strokes/7301 points survive the exact JSON round-trip into `Stroke.fromJson`.)
- **Highlight** (0x1C0D, previously misread as a second colour property) now imports as `==highlight==`.

**`.onepkg` whole-notebook import shipped.** A `.onepkg` is a Microsoft Cabinet (LZX-compressed) of `.one` section files; the pure-Rust `cab` crate provides extraction (`rust/onote_core/src/onepkg.rs`, 256 MB/section zip-bomb cap, panic-guarded FFI `onote_core_import_onepkg`). The Dart importer creates a **new notebook** named after the package, one section per `.one` (package folders → section groups), reusing the same per-page import path as single-section import, and removes the seeded starter section once real content lands. Menu: notebook menu ▸ "Import OneNote notebook (.onepkg)…".

Known gaps (tracked in ROADMAP): per-run font size, OneNote tags/checkboxes, hyperlink URLs (the dialect renders no standard links yet), and in-flow images rendering as images *while editing* (Phase 3, with the structured editor).

### L.6 — Notebook-import correctness + canvas fixes (iteration 19)

Stakeholder testing of the first whole-notebook import surfaced seven issues:

- **Only the first group's sections had content** — `firstPageId ??= _importPagesIntoSection(…)`: `??=` short-circuits its right-hand side once non-null, so the import call itself was skipped for every section after the first. (Lesson: never put a side-effecting call on the RHS of `??=`.)
- **Ink rendered grey / wrong for the theme.** Imported strokes now carry `"auto"` colour when OneNote stored none; `InkPainter` resolves `auto` from the theme (dark ink on light pages, light on dark) — the same contract as default text colour, which was already theme-correct. Explicit pen colours always pass through.
- **Page order + subpage levels.** `0x1DFF` is the page's 1-based **subpage level** (not a page number, as previously assumed); display order lives in the directory-space section node's ordered page-oid array (JCID `0x00060008`, property `0x3442`) — a user can reorder pages without rewriting object spaces, so file order alone is wrong. Content spaces pair with page nodes by creation ordinal, then sort by the display array; levels flow into `TreeNode.level` (ORG-6). Empty content spaces still consume their ordinal (skipping shifted every later page's title by one).
- **No feedback during long imports.** The Rust parse (LZX + binary + base64) now runs in an isolate via `compute`, with a non-dismissible busy dialog; the UI thread never freezes.
- **"Blank page until scroll."** The CANVAS-9 culling rect was computed in `build()` but the transform changes without a rebuild (viewport assignment, per-page view restore) — first paint culled everything against a stale viewport and nothing invalidated the list. Culling now computes inside the transform's `AnimatedBuilder`, so it always matches the frame being painted.
- **Math pixel overflow.** Wide imported equations overflowed their block; `Math.tex` is now wrapped in `FittedBox(scaleDown)` in the math block (view + editor preview) and the markdown `$$…$$` renderer.
- Residual layout gap: imported line-height nudged 1.32 → 1.35.

### L.7 — The gosid correlation (iteration 20): pages finally match their content

Testing against the stakeholder's real 41 MB notebook (195 pages, 12 sections, 3 groups, ~68k ink strokes) exposed that L.6's "pair content spaces with page metadata by creation ordinal" heuristic was simply wrong — titles/levels attached to the wrong content, order didn't survive, and unmatched pages went missing. The definitive linkage, now implemented, is OneNote's own:

- The section node's page list holds **parallel arrays**: `0x3442` (page-metadata OIDs: title, subpage level) and **`0x1D63` (each page's ObjectSpaceID)**.
- An ObjectSpaceID is a compact ID (guidIndex high 24 bits, n low 8) resolved through the space's **global-id table** (FileNode `0x024` entries, captured per space during the walk) to an ExtendedGUID.
- That ExtendedGUID matches the **gosid** in each space's ObjectSpaceManifestListReferenceFND body (also captured during the walk) — giving an exact space→(title, level, display order) map. Requires consuming the propset's **OSID stream** (types 0x0A/0x0B), previously skipped.
- Pages listed in the section but yielding no parseable content now import as empty titled pages (visible) instead of vanishing; unmatched content spaces fall back to their on-page title text.

Also in this iteration: ink strokes with a channel count that doesn't match the shared dimension table (pen without pressure sharing a 3-dim properties node) now fall back to a divisor-based channel guess instead of being silently dropped (the "missing ink" report); math blocks self-size to the rendered equation (a stored width scaled complex equations illegibly small — `displayW = null` + measured write-back); the notebook-import busy dialog narrates per-section progress during the write phase.

### L.8 — Page order/hierarchy rebuilt + ink giant-scribble fixed (iteration 21)

Cross-checked the importer against the stakeholder's real notebook opened read-only in OneNote-web, page-for-page. Four fixes:

- **Section→page structure was modelled wrong.** L.7 assumed one section node with parallel page arrays; MS-ONE actually nests **SectionNode (JCID 0x00060007) → ElementChildNodes (0x1C20) → PageSeriesNodes (0x00060008)**, each with parallel **0x1D63 (page object-spaces)** and **0x3442 (PageMetadata)**. A section has *many* series; the old code read a single series, so order was wrong and only that series' pages got correct subpage levels. Now the series are walked in section order, pages concatenated — verified identical to the web notebook (e.g. Discrete Maths: Symbols, then Week 1/2/3… each a top-level page with its lecture subpages; Programming 1: six flat pages in exact order).
- **Subpage level was off by one.** `PageLevel` (0x1DFF) is 1-based (1 = top-level); Openote's indent is 0-based, so subtract 1. (The browser shows top-level pages flush-left; mine were indented once.)
- **Ink "giant scribbles."** ~25% of strokes on some pages spanned the whole page. Root cause: strokes sharing a StrokeProperties node with an **empty dimension table** were decoded as 2-channel when they're 3-channel (X,Y,Pressure) — reading 3ch data as 2ch bleeds the X block into Y and the cumulative sum runs away. Fix: infer the channel count by **compactness** (the correct split keeps X/Y bounded; the wrong one is ~10× larger), apply it even when a valid table yields an absurd span, and drop any stroke still spanning > ~3200px (scale-aware). Verified: runaways across the 68,605-stroke notebook went from thousands to zero page-crossers, dropping only 10 genuinely-undecodable strokes (0.015%).
- **Tiny equations** now expand their box: math blocks size to the rendered equation (`displayW = null` + measured write-back) instead of scaling a complex equation illegibly small inside a fixed 320px box.

Progress feedback for `.onepkg` import now narrates per-section, and the parse runs in an isolate (no UI freeze).

### L.8 — Verifying the notebook correlation + the stale-DLL trap (iteration 21)

The stakeholder reported a full-notebook import as "super messy": wrong page order, subpages only in the first group then flat, bodies as titles, missing pages. Investigation:

- **The parser was already correct.** Cross-checking the authoritative open-source `onenote.rs` parser confirmed the structure (SectionNode 0x00060007 → `ElementChildNodes` → PageSeriesNodes 0x00060008; each PageSeries has parallel `ChildGraphSpaceElementNodes`/0x1D63 page-space OSIDs ‖ `MetaDataObjectsAboveGraphSpace`/0x3442 metadata OIDs; PageMetadata carries `CachedTitleString`/0x1CF3 + `PageLevel`/0x1DFF). A new `dump_sections` diagnostic showed titles, levels, order and content fingerprints all lining up for the real 41 MB notebook — Programming 1 matched the live OneNote page-for-page, Discrete's 55 pages nested Week→subpages correctly, and a scan across all 12 sections found **zero orphans and zero flattening**.
- **The bug was a stale DLL.** Inspecting the user's actual imported `.onote` (SQLite) showed the *old* ordinal-pairing output (44 flat pages), while the current source produced 55 correct ones. `sha256` of the deployed `onote_core.dll` didn't match a fresh `cargo build --release` — the app had been loading a pre-fix binary. This had recurred several times.
- **Root-cause fixes:** (1) `OnoteCore._tryLoad` now loads the **newest** candidate library by mtime, so a `cargo build` is picked up without a manual copy (no-op in a shipped build with one library); (2) a real **end-to-end test** (`test/onenote_import_e2e_test.dart`) drives the native DLL + the actual import/persistence into a temp SQLite and asserts the reconstructed tree — Programming 1 exact match, Discrete nesting, and no orphaned subpages in any section. The onepkg-apply logic was extracted to `buildNotebookFromPackage` and `Repository.openAt` added so the pipeline is testable headlessly.

Remaining (unchanged): the residual imported-layout gap (Phase 3), tables/attachments (unparsed), in-flow images editing as images (Phase 3).

### L.9 — Per-revision resolution & aspect image matching (iteration 22)

Verifying a fresh 1:1 `.onepkg` (48 MB, 324 pages) against the live OneNote web notebook — Programming 1 matched page-for-page, and "Intro to Information Systems" nested **three levels** exactly (Module → Lecture week → sub-note) — surfaced two real content bugs on the way, both now fixed and covered by the end-to-end test:

- **Lost text on heavily-revised pages (the big one).** OneNote's global-id table (guidIndex→GUID) is declared **per revision**, so the same CompactID names different objects in different revisions. The parser resolved references globally, mixing revisions — a page edited many times (e.g. every section's "Misc") resolved to a title-only stub and imported with **zero text boxes**. Fixed by giving every object its revision's table, canonicalising each reference to its ExGuid (revision-resolved GUID + n) via the referencing object's revision, and keying the object graph by ExGuid (`Resolver` in [onenote.rs]). The page's content root is now the PageNode declaration that actually has `0x1C20` children (not merely the latest, which can be a stub). Result on the sample: text recovered across the notebook (boxes 858→985), and cross-revision **duplicate ink de-duplicated** (strokes 73.8k→64.6k, one copy per stroke). The walk now tracks GlobalIdTable Start/Entry/Entry2/Entry3 (0x021/0x024/0x025/0x026) to build per-revision tables with inheritance.
- **Images piling onto page 1.** The natural-size→pixel factor isn't constant (paste ≈ 60 px/unit, insert ≈ 96), so absolute-size PNG matching failed and unclaimed PNGs dumped onto each section's first page (a "Misc" page showed 24 images). Matching now keys on **aspect ratio** (scale-invariant) gated by a plausible pixel-factor (40–130), with the old exact-size match as a fallback. Result: that Misc page went 24→4 images and the section's other pages regained theirs; totals unchanged (no image lost); the previously-correct pages (Lecture) stayed correct.

New diagnostics: `dump_sections` (section→page correlation + content fingerprints), `dump_revisions` (per-space revision/ExGuid resolution), and `--json`/`--sections`/`--revs` modes on the `dump_one` example. The e2e test (`test/onenote_import_e2e_test.dart`) now also asserts the revised-page text recovery and 3-level nesting.

Still not addressed (documented follow-ups): exact image *positioning* and dedup need the structural `PictureContainer` (0x1C3F) → file-data-store link rather than PNG-signature scanning; tables and file attachments remain unparsed; the residual imported-layout gap (Phase 3).

## F. Process note

Iteration 2's two shipped bugs (F-6-class API drift, the startup-path crash) both stemmed from unverifiable-in-sandbox platform behavior. Mitigation now in place: every UI interaction path in iteration 3 was re-derived from event-dispatch order rather than assumed (F-3 was exactly an ordering assumption), and version-sensitive APIs are confined to two files (`ink_painter.dart`, `export/pdf_export.dart`) with fallbacks noted in the README.

## M. Navigator rework (two-layout prototype)

The single-pane tree navigator worked but lacked focus (every section could expand at once into one long, hard-to-scan list) and had no notebook management at all — no rename, no delete (the reported "can't delete a notebook" gap: the notebook dropdown only *switched*). Rather than copy OneNote's three-column "double fold-out" (48px rail + sections column + pages column ≈ 480px of chrome — the space cost the stakeholder disliked), we take its *clarity* — see one section's pages at a time — and keep a single ~250px pane. Both candidate presentations ship behind a live toggle so the stakeholder can decide:

- **Stacked** (`NavLayout.stacked`, default): two zones — a sections list above, the **active** section's pages below — split by a drag-to-resize divider (ratio persisted as `navSplit`). OneNote's focus without the second column.
- **Focused tree** (`NavLayout.tree`): the familiar single tree, but opening a section makes it the active one and expands its pages inline while the others collapse (accordion). Smallest change, most space-frugal.

Both share one concept — the **active section** (`AppState.activeSectionId`) — kept in sync with the open page (`selectPage`) and set by tapping a section (`activateSection`; a second tap collapses in tree mode). Toggle lives next to a new search/quick-jump box; the layout choice persists as `navLayout`.

Notebook management is now first-class. The notebook menu (and a right-click on the header) offers rename, delete, new, imports, and the recycle bin. **Delete → confirm dialog → recycle bin** (the chosen safety model): `Repository.trashNotebook` moves the notebook to a persisted `trashed` list in `workspace.json` and closes its handle but **keeps the `.onote` file**, so `restoreNotebook` is lossless; `purgeNotebook` removes the file for good (extra confirm). Deleting the current notebook switches to another first; the only notebook can't be deleted. The recycle bin dialog now lists trashed notebooks alongside deleted sections/pages, and the delete snackbar offers Undo.

Coverage: `test/notebook_lifecycle_test.dart` exercises trash → restore → rename → purge (file removed) plus workspace-reopen persistence and the last-notebook guard. Analyzer clean on all changed files; existing unit + import e2e tests unaffected.

Stakeholder picked **stacked** ("absolutely the way to go"). Follow-up cleanup: drop the `tree` branch + the layout toggle. Possible extras: notebook duplicate (copy the `.onote` + blobs), remembering the last page per section, and horizontal pane resize.

### M.1 — Notebook context menus + recycle-bin retention

Second pass on the notebook UX:

- **Right-click acts in place.** `_NotebookHeader` is now stateful and owns the `MenuController`; a right-click on the header *or* on any notebook row in the dropdown (`Listener` on `kSecondaryMouseButton`) closes the dropdown and pops that notebook's actions at the pointer — rename/delete/open — acting on **that** notebook without switching to it first (`showNotebookMenu` already took a `NotebookRef`; `deleteNotebook` only switches when deleting the current one). The earlier fragile trailing "more" `IconButton` inside `MenuItemButton` was dropped for this.
- **30-day retention.** Trashed notebooks and nodes are auto-purged after `Repository.recycleRetentionDays` (30). Swept at startup (`AppState.init`) and whenever the recycle bin opens (`purgeExpiredNotebooks` / `purgeExpiredNodes`); the bin shows a per-item "Deletes in N days" countdown and a header note. Covered by a retention test (backdated trash is purged, fresh is kept).

### M.2 — "Images don't load" was images off-screen, not broken

Reported: imported images (standalone and in-text) don't appear, though ink on the same pages does. A deep end-to-end trace against the real 324-page notebook found **nothing broken**: all 254 image blocks persist with valid, decodable PNG blobs (`blobOk=254`), and images *do* render — proven three ways: an isolated `ImageBlockView` render test (3/3, `naturalW` set), live instrumentation in the running app (`branch=image`, valid provider, no exceptions), and a window screenshot showing the graph diagrams once zoomed out. All 91 in-text image refs are on their own line, so `md_render`'s image regex matches them too.

Root cause: the importer places images at their **faithful OneNote offsets**, which for many pages is to the *right* of the text (x ≈ 980–1200+) or well below it (≈80% of images sit below the first screenful). At 100% zoom on a normal window they're simply off-screen — the text/ink on the left is visible, so the images read as "not loaded."

Fix (chosen: "fit page on open"): `CanvasController.fitWidth(contentWidth)` scales a page down so its full content width fits the viewport, anchored top-left — only ever zooming *out* (never past 100%), so narrow pages keep natural size while wide imported pages reveal their right-hand images immediately. `PageCanvas.initState` applies it unless the page has a genuinely user-adjusted saved view (a stored default of 100%/top-left counts as unadjusted and gets the fit). Verified in the live app: the previously-blank right side now shows the diagrams on open. Regression: `test/canvas_view_test.dart`.

Noted-not-fixed: imported math still renders run-together (missing inter-token spaces), a separate LaTeX-spacing issue.

### M.3 — Math prose spacing + stacked-only navigator

- **Run-together math fixed at the source.** OneNote math zones freely mix prose with symbols; the importer converted whole paragraphs to LaTeX, and math mode swallows spaces ("Apathisasequence…"). `latexify_prose` (in `office_math_to_latex`) now wraps prose words (≥2 letters, grouping runs incl. single-letter prose words like "a") in `\text{…}` with boundary spaces folded inside, while single-letter variables and `\commands` stay math. Verified on the real Lecture.one: `\frac{L (\text{bits})}{R (\text{bits}/\text{sec})}`. Unit-tested (`prose_in_math_keeps_spaces`). Applies to **new imports** — already-imported pages keep their stored latex (re-import to pick it up).
- **Tree layout removed.** The stakeholder confirmed stacked; the `NavLayout` enum, toggle, accordion branch and section chevrons are gone. `activateSection` lost `allowCollapse`.

## N. Performance pass (startup / import / in-page)

Measured on the real 48MB, 324-page `.onepkg` (release DLL, debug Flutter):

**Import: ~53s → ~14s end-to-end.** Segment timings before: parse 41.6s | JSON decode 1.3s | blob store 1.8s | page writes 8.9s. The parse breakdown (new `--timing` mode on `dump_one`) showed cabinet **extraction** at 34.6s vs actual parsing 3.9s — the `cab` crate's `read_file` re-decompresses the LZX folder prefix for every file, and a OneNote package is ONE 85.7MB folder holding all 27 sections → quadratic (~1.2GB of LZX work). Fixes:
- **Vendored `cab` 0.6 with a 2-method patch** (`vendor/cab`, `[patch.crates-io]`): `FileEntry::uncompressed_offset()` + `Cabinet::read_folder_data(index, limit)` — decompress each folder ONCE, slice sections out at their offsets (extent-capped zip-bomb guard preserved).
- **Parallel section parsing**: `.one` payloads parse independently → `std::thread::scope` fan-out across cores, per-section `catch_unwind` (a damaged section is now skipped instead of failing the whole package).
- **`opt-level = 3`** (was `"z"`, size-optimized — measurably slowed LZX + parsing; DLL 648KB, fine).
- Result: parse 41.6s → **4.4s**. Page writes: `PRAGMA synchronous=NORMAL` (WAL-recommended durability; import ran ~700 fsync'd commits), `writePage` converted to savepoints + `Repository.runInTransaction` batches each section into one commit. Remaining ~8s of build time is real work (mirror JSON encoding of ink-heavy pages) — a deeper mirror-format change, deliberately not attempted.

**Startup.** `Repository.open()` + `AppState.init()` (SQLite opens, node load, restored-page JSON decode) ran BEFORE `runApp` — the window stayed invisible until everything loaded. `OpenoteBoot` now paints a splash immediately and swaps the app in when ready (startup errors still render in-window). Note: debug builds JIT — `flutter build windows --release` is the representative startup.

**In-page sluggishness.** Two structural fixes:
- `MarkdownView` (stateless, re-parsed every text block's Markdown on EVERY app notify — drag frames, ink commits, typing) is now stateful with a parse cache keyed on (text, style, theme); unchanged content returns the identical subtree, which short-circuits Flutter's rebuild. Also fixed the never-retry `_imgCache` (a null resolve was cached forever) — misses now retry.
- **Wet ink no longer rebuilds the canvas per point.** `_inkMove` did `setState` at stylus rate (rebuilding every visible block per point); the stroke now grows in place and nudges a `ValueNotifier` wired to `InkPainter(repaint:)` — repaint-only, zero widget rebuilds until stroke commit.
- The root `MaterialApp` also rebuilt on every notify (its `ListenableBuilder` watched the whole AppState); it now caches and rebuilds only when `themeMode` changes — content updates ride `AppShell`'s own listener.

Fidelity re-verified after all of the above: full Dart suite (23) + Rust suite (26) green, including the e2e import of the real notebook (order/nesting/orphans/text recovery). The e2e's wall time dropped 48s → 15s, confirming the import speedup in-pipeline.
