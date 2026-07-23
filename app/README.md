# Openote — MVP application

The walking-skeleton MVP of Openote: a runnable, **pure-Dart** slice of the full architecture. It creates real `.onote` files per the [File Format Spec](../docs/specs/10-file-format-spec.md), operating in the spec's documented **mirror-write mode** (§4) until the Rust core lands — so nothing about your notebooks changes when it does.

## What works in this cut (iteration 10)

- **App icon, reliably:** copy `build/app_icon.ico` → `windows/runner/resources/app_icon.ico`, `flutter clean`, rebuild (see note below).
- **Auto-width fixed** — boxes now widen *before* text reaches the edge (no clipping), still locking on manual resize.
- **Full colour picker** — split button: click applies current colour, arrow opens the picker (palette grid, your recent/custom colours persisted, hue + saturation/value field, RGBA sliders incl. alpha, hex entry). Ctrl+Shift+C stays as a shortcut only.
- **System fonts** — the font button now lists your *installed* fonts (parsed from the OS font folders), searchable, each previewed in its own face.
- **Remembers your place** — per-page scroll & zoom survive flicking between pages, and the app reopens exactly where you closed it (notebook, page, view).
- **Version history** — automatic snapshots (~10 min apart, 30 kept) per page; right-click a page ▸ Version history to restore.
- **Page templates** — right-click a page ▸ Save as template; Insert ▸ Template applies one.
- **Faster** — ink strokes are no longer JSON-decoded every frame (cached + isolated repaint layer); UI latency budgets are now in the style guide (§7a.6).

No new runtime dependencies (`flutter_launcher_icons` in dev-deps is optional now) — but run **`flutter pub get`** anyway after replacing pubspec.

## What worked as of iteration 9

> **App icon (reliable method):** copy **`build/app_icon.ico`** over **`windows/runner/resources/app_icon.ico`** (the file `flutter create` generated), then run **`flutter clean`** and rebuild. That resource IS the window/taskbar/exe icon on Windows, so this cannot miss. (`dart run flutter_launcher_icons` does the same thing via tooling; the manual copy works even when the tool's config doesn't take. Windows Explorer aggressively caches icons — if the *old* icon lingers on the .exe in Explorer, that's the icon cache, not the build.)

- **App icon** — the design-doc logo (ink "O" + brass nib) is now the app icon, via `flutter_launcher_icons`.
- **Formatting buttons fixed** — the Home-tab formatting no longer greys out when you click back into a box.
- **Text boxes auto-size** — a new box grows in width with your text up to a comfortable max, then wraps; drag the right-edge handle (now grabbable while editing) to lock a custom width.
- **Text colour + font** — colour a selection from the Home tab (or long-press the swatch to pick); **Ctrl+Shift+C** flicks the selection between your last colour and default. Box-level font (sans/serif/mono).
- **Insert into the current box** — Insert ▸ Page link drops the link at your cursor when you're editing a box (instead of making a new one).
- **Code Tab indent** — Tab in a code block inserts spaces instead of moving focus.
- **Table navigation** — Tab/Shift+Tab between cells, arrow keys move (caret-aware left/right), Enter adds/moves to the next row, Ctrl+Enter is a line break.
- **Seamless page + zoom-out placement** — the page is one continuous surface at every zoom; zoom out and you can drop a box anywhere in the margin (it extends the page; unused space snaps back). Horizontal scroll stays constrained to your content.
- **Title-first flow** — a new page puts the cursor in the title; press Enter to jump straight into the first text box. Background lines no longer run over the title.

## What worked as of iteration 8 (Phase 2 features)

- **Horizontal scroll:** hold **Shift** and use the wheel to scroll the page sideways (OneNote parity).
- **Tables** (Insert ▸ Table, or right-click canvas): editable cells with add/remove row & column; exports as a GitHub-flavored Markdown table.
- **Recycle bin** (trash icon at the bottom of the sidebar): deleting a section/page now soft-deletes it and its subtree; restore brings it (and its parents) back, or delete permanently.
- **Backlinks panel** (the tree icon in the command bar): shows pages that link *to* the current page and the pages it links *out* to, both clickable. Links are indexed on save.

No new dependencies — no `pub get` needed.

## What worked as of iteration 7 (Phase 2 UI overhaul)

The clunky single-row toolbar is gone, replaced by a **tabbed command bar** — OneNote's few-clicks accessibility in Openote's calm style:

- **Home** — undo/redo + live formatting that acts on your selection: bold (Ctrl+B), italic (Ctrl+I), strike, inline code, highlight, H1/H2/H3, bullet/numbered/checkbox lists, quote. Buttons enable when you're in a text or code box.
- **Insert** — text box, equation, code, image, file, page link.
- **Draw** — tools, per-tool colors, pen size (with a "Done" chip on the tab row to hop back to Select from anywhere).
- **View** — page backgrounds, snap toggle, zoom controls with %, zoom-to-fit, and a **theme switcher** (Auto/Light/Dark).
- **Right-click menus everywhere**: on a block — edit, copy/cut, duplicate, bring-to-front/send-to-back, delete; on empty canvas — new text/equation here, paste, backgrounds.
- **Block clipboard**: Ctrl+C/X/V copies, cuts, and pastes whole blocks (with fresh IDs per the data-model spec); works from the context menus too.
- Review fixes: blocks now **paint in z-order** (so front/back actually works), and repeated drag-to-subpage drops no longer collide.

No new dependencies — no `pub get` needed.

## What worked as of iteration 6

The big one: **live-Markdown editing.** While you type, Markdown now formats in real time — finish `**bold**` and the text goes bold with the `*` markers collapsing away; move the caret back in and they reveal so you can edit them (Obsidian-style). Built as a custom `LiveMarkdownController` with a coverage-verification safety net, so a parse slip can never corrupt text. Also this cut:

- **Fixed the missing-keys bug.** Letter keys (V/T/P/H/E and others) were being swallowed by global shortcuts — a known Flutter desktop issue where bare-letter `Shortcuts` shadow text fields. Keyboard handling was rewritten to detect a focused field and only ever grab Escape then; every other key flows to your text.
- **VS Code-style wrap:** select text and press `(` `[` `{` `"` `'` `` ` `` `*` `_` `~` `=` `<` to wrap the selection instead of replacing it.
- **Images:** no more hover flicker (cached provider + gapless playback), and drag the right-edge handle to resize proportionally.
- **Collapsible hierarchy:** collapse section groups, sections, *and* pages-with-subpages (chevrons in the sidebar) — fold your notebook down to just what you need.
- **Seamless page:** at normal zoom the page fills the window as one continuous surface; zoom out below ~85% and it becomes a bounded sheet on the backdrop (canvas on demand).
- **Snap-to-grid on by default**, but the grid is invisible until you start dragging a block, then a faint alignment grid appears. Dropping a box near the left tucks it to the writing margin.

No new dependencies — no `pub get` needed.

## What worked as of iteration 5 (MVP polish)

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
