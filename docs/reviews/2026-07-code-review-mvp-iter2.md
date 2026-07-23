# Code Review — MVP iteration 2 vs. specifications

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

## F. Process note

Iteration 2's two shipped bugs (F-6-class API drift, the startup-path crash) both stemmed from unverifiable-in-sandbox platform behavior. Mitigation now in place: every UI interaction path in iteration 3 was re-derived from event-dispatch order rather than assumed (F-3 was exactly an ordering assumption), and version-sensitive APIs are confined to two files (`ink_painter.dart`, `export/pdf_export.dart`) with fallbacks noted in the README.
