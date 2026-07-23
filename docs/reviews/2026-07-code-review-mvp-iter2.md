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

## F. Process note

Iteration 2's two shipped bugs (F-6-class API drift, the startup-path crash) both stemmed from unverifiable-in-sandbox platform behavior. Mitigation now in place: every UI interaction path in iteration 3 was re-derived from event-dispatch order rather than assumed (F-3 was exactly an ordering assumption), and version-sensitive APIs are confined to two files (`ink_painter.dart`, `export/pdf_export.dart`) with fallbacks noted in the README.
