# Openote — MVP application

The walking-skeleton MVP of Openote: a runnable, **pure-Dart** slice of the full architecture. It creates real `.onote` files per the [File Format Spec](../docs/specs/10-file-format-spec.md), operating in the spec's documented **mirror-write mode** (§4) until the Rust core lands — so nothing about your notebooks changes when it does.

## What works in this cut (iteration 5 — MVP polish)

Iteration 5 closes the remaining MVP gaps: **code syntax highlighting** (dependency-free, ~15 languages), **clickable page links** (`[[Page|id]]` wiki-links — Insert ▸ Link to page, or type them; click to navigate, resolved by stable ID), **palm rejection** (with a pen/stylus the finger pans & pinch-zooms while only the pen draws — OneNote's default), and an **accessibility pass** (blocks, title, and controls expose labels to screen readers). No new dependencies — no `pub get` needed.

## What worked as of iteration 4

Iteration 4 = page feel & navigation: the page now **reads like a page** (anchored top-left, fills the window; zoom out to reveal its bounds — canvas on demand), **intelligent text placement** (clicks align to the margin/neighbours instead of landing pixel-exact; empty-page clicks go to the standard top-left spot), an **in-page editable title + date** (no menu), and **drag-and-drop navigation** (drag a page into a section, drag a page onto a page to make it a subpage, drag a section into a group). No new dependencies — no `pub get` needed since iteration 3.

## What worked as of iteration 3

Iteration 3 = the [code-review](../docs/reviews/2026-07-code-review-mvp-iter2.md) fixes: **page surface** (OneNote-like page on a backdrop that grows with content; pan clamped; view opens centered on the page), **click-anywhere-to-type** (single click on empty page — CANVAS-3 as specified), **tap-to-edit** blocks (no more double-click), **no more lost math edits** (commit on state transition), **multi-select** (shift-click + marquee, group move/delete, ink included), **viewport culling**, **section groups** + move up/down + move-to-group, **find on page** (Ctrl+F), **inline `$math$` and `$$math$$` rendered inside text blocks**, **math symbol palette**, **true area-erase** (stroke splitting), **file attachments**, and **PDF export**. ⚠️ `pubspec.yaml` gained the `pdf` package — run `flutter pub get` once.

## What worked as of iteration 2

New in iteration 2: **inline-rendered Markdown** in text blocks (headings, bold/italic/code/highlight/strike, bullets, numbered lists, clickable checkboxes, quotes, code fences — rendered in view mode, source revealed while editing), **undo/redo** (Ctrl+Z/Y, page-scoped), **keyboard shortcuts** (V/T/P/H/E tools, Del, Ctrl+D duplicate, Ctrl+±/0 zoom, Esc), **code blocks** (mono, language label, copy button), **page backgrounds** (blank/grid/dotted/ruled), **multiple notebooks** (switcher + create), **subpages** (indent/promote via right-click), **pen size slider + per-tool colors**, **zoom controls with % indicator and zoom-to-fit**, **duplicate block**, **Markdown export with image assets**, a **page title header**, **status bar** (save state + shortcut hints), and proper **empty states**.


- **Workspace & hierarchy:** notebooks → sections → pages (create, rename, select) with a navigator sidebar, persisted to `.onote` SQLite files in `~/Documents/Openote/`.
- **Infinite canvas:** pan (space-drag / middle-drag / two-finger), zoom (Ctrl+scroll, buttons), both axes, unbounded.
- **Click-anywhere text blocks:** click empty canvas with the Text tool → type. Drag to move, edge-handle to resize. **Free ↔ snap-to-grid** toggle with grid overlay.
- **Ink:** pen / highlighter / eraser with pressure-sensitive perfect-freehand strokes, stored losslessly per the [Ink Data Spec](../docs/specs/13-ink-data-spec.md).
- **Math blocks:** type linear input (`(x^2+4)/(x-3)`, `\sum_(n=1)^oo 1/n^2`) → renders as 2-D notation (subset of the [Math Input Spec](../docs/specs/12-math-input-spec.md) grammar; grows toward the full spec).
- **Images:** insert from file; stored content-addressed in the notebook's blob table.
- **Light/dark theme** from the style-guide tokens, following the OS.

**Not yet (by design, tracked in the roadmap):** the rich-text engine (awaiting the [ADR-0004](../docs/adr/ADR-0004-editor-engine.md) bake-off — text blocks currently use plain multiline editing behind the `TextBlockView` seam), inline Markdown rendering, CRDT/Rust core (stubbed behind `lib/core/engine.dart`), sync, embeds, export.

## Running it

Prereqs: Flutter (latest stable) with desktop support enabled for your OS.

```bash
cd app
# 1) Generate the platform runner directories (one-time; they are not committed):
flutter create --platforms=windows,macos,linux --project-name openote --org org.openote .
# 2) IMPORTANT: flutter create drops a boilerplate test referencing a class we
#    don't have — delete it or `flutter test` reports a bogus failure:
#      Windows:      del test\widget_test.dart
#      macOS/Linux:  rm test/widget_test.dart
# 3) Fetch packages:
flutter pub get
# 4) Verify (all tests should pass) and run:
flutter test
flutter run -d windows   # or -d linux / -d macos
```

Linux desktop needs the usual toolchain (`clang`, `cmake`, `ninja-build`, `libgtk-3-dev`); `flutter doctor` will tell you what's missing.

### Troubleshooting first run
- **Package version conflicts:** versions in `pubspec.yaml` are caret ranges chosen mid-2026; if `pub get` complains, run `flutter pub upgrade --major-versions` and sanity-check the two APIs we touch directly (`getStroke` from perfect_freehand, `Math.tex` from flutter_math_fork).
- **SQLite errors on launch:** `sqlite3_flutter_libs` bundles SQLite on desktop; if your distro build skips it, install `libsqlite3-dev` and it falls back to the system library.
- **Where's my data?** `~/Documents/Openote/*.onote` — open one with any SQLite browser and look at `page_mirror` to see the open format doing its job. If Documents isn't usable (e.g. OneDrive folder redirection on Windows), Openote falls back to the per-user app-data directory (on Windows: `%APPDATA%\org.openote\openote\Openote`, shown in the window title of a future build; check both if in doubt).
- **App starts but no window / crash at startup:** fixed builds show an in-window error report instead; paste its contents into an issue.

## Where the Rust core will slot in

`lib/core/engine.dart` defines the `DocumentEngine` interface (open/apply/snapshot/subscribe). Today `MirrorEngine` implements it in pure Dart (direct mirror writes + `dirty_mirror` flag per spec §4). The Loro-backed `onote-core` crate (via `flutter_rust_bridge`) will be a second implementation behind the same interface — [ADR-0002](../docs/adr/ADR-0002-crdt-library.md). Until then, **you don't need Rust installed to develop or run the app.**

## Code map

```
lib/
├── main.dart                  # entry, theme wiring
├── theme/onote_theme.dart     # style-guide tokens (Ink/Brass/Paper/Night) → ThemeData
├── core/
│   ├── ids.dart               # UUIDv7 (Data Model §2)
│   └── engine.dart            # DocumentEngine interface + MirrorEngine stub
├── model/models.dart          # TreeNode, Block (+envelope), Stroke, JSON ↔ objects
├── store/
│   ├── database.dart          # .onote SQLite: DDL per File Format Spec §3
│   └── repository.dart        # workspace/notebook/page CRUD, mirror read-write, blobs
├── state/app_state.dart       # app-wide state: selection, tool, page, debounced saves
├── math/linear_math.dart      # linear-input → LaTeX (Math Input Spec §3 subset)
├── canvas/
│   ├── canvas_controller.dart # pan/zoom matrix, screen↔page mapping, snap
│   ├── page_canvas.dart       # gestures, grid, ink capture, block layout
│   ├── block_view.dart        # selection chrome, move/resize, type dispatch
│   └── ink_painter.dart       # perfect-freehand outline painting
├── editor/
│   ├── text_block_view.dart   # interim text editing (swaps for bake-off winner)
│   ├── math_block_view.dart   # linear entry ↔ rendered 2-D math
│   └── image_block_view.dart
└── ui/
    ├── app_shell.dart         # layout: sidebar | toolbar / canvas
    ├── sidebar.dart           # notebook/section/page navigator
    └── toolbar.dart           # tools, grid toggle, zoom, insert menu
```
