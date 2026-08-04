# Openote — the application

The Openote desktop app: a Flutter/Dart UI over a native **Rust core**
(`rust/onote_core`) linked with hand-written `dart:ffi`. It reads and writes
real `.onote` files per the [File Format Spec](../docs/specs/10-file-format-spec.md),
in the spec's documented **mirror-write mode** (§4).

The Rust core is **optional at runtime**: without its library the app falls back
to the pure-Dart engine and behaves identically, minus OneNote import. It is not
optional at build time on Windows and Linux — see below.

> **This file describes the app as it is now.** It is not a changelog: the
> release history is in [CHANGELOG.md](../CHANGELOG.md), and the blow-by-blow
> iteration log lives in [docs/reviews](../docs/reviews/) — the
> [MVP iteration-2 review](../docs/reviews/2026-07-code-review-mvp-iter2.md) is
> explicitly the project's append-only record of what each pass changed.

## Building and running

Prereqs: Flutter (latest stable) with desktop support for your OS. Rust
(`cargo`) is needed only to build the native core — the app runs without it.

```bash
cd app
flutter pub get
flutter test
flutter run -d windows      # or -d linux / -d macos
```

> **Do NOT run `flutter create` in this directory.** An older version of this
> file told you to, on the claim that the runner projects "are not committed".
> They are: `windows/`, `linux/` and `macos/` are tracked, and `windows/CMakeLists.txt`
> and `linux/CMakeLists.txt` carry the hook that builds and bundles the Rust
> core. `flutter create` would overwrite them and quietly reintroduce the
> stale-library trap described below. The same advice told you to delete
> `test/widget_test.dart`, which today holds real tests.

Linux desktop needs the usual toolchain (`clang`, `cmake`, `ninja-build`,
`libgtk-3-dev`); `flutter doctor` names whatever is missing.

### The Rust core

**On Windows and Linux, `flutter build` builds the core for you.** The CMake
hook in each runner project invokes `cargo build --release` and copies the
library next to the executable, which is what closed the stale-DLL trap that
burned several sessions (fixes appearing to do nothing because an old library
was still being loaded). If `cargo` is not on `PATH` the hook prints a warning
and skips it, and the app runs on the Dart engine.

**macOS has no equivalent hook** — Flutter drives it through Xcode rather than
our CMake — so a local `flutter build macos` produces an app without the core,
and therefore without OneNote import. The release workflow does it explicitly
(`.github/workflows/release.yml` builds both architectures, `lipo`s them, drops
the dylib into `Contents/MacOS/` and re-signs), so **release** builds are fine;
only local mac development needs the manual step. See
[`rust/onote_core/INTEGRATION.md`](../rust/onote_core/INTEGRATION.md).

`sync-core.bat` in the repo root remains for Windows, and still works: it builds
Rust, then Flutter, then copies the DLL, in that order.

Two things that have each produced a "my fix didn't work" false alarm:

- **`openote.exe`'s timestamp tells you nothing about Dart.** It is the runner
  shell and is not relinked for a Dart-only change. Your Dart code lives in
  `build/windows/x64/runner/Debug/data/flutter_assets/kernel_blob.bin` (debug)
  or `data/app.so` (release).
- **Importer changes only affect *new* imports.** Anything the parser writes
  into a notebook — table column widths, flow positions, recovered content — is
  baked in at import time, so an already-imported notebook keeps the old values
  however new the binary is. Renderer changes (fonts, metrics) apply on restart.

### Troubleshooting a first run

- **Package version conflicts:** the versions in `pubspec.yaml` are caret ranges
  chosen mid-2026. If `pub get` complains, run
  `flutter pub upgrade --major-versions` and sanity-check the APIs we touch
  directly (`getStroke` from perfect_freehand, `Math.tex` from
  flutter_math_fork, and the `pdfrx` document API).
- **SQLite errors on launch:** `sqlite3_flutter_libs` bundles SQLite on desktop.
  If your distro build skips it, install `libsqlite3-dev` and it falls back to
  the system library. The test suite needs the same library present — see
  `test/support/sqlite.dart`, which skips locally and fails loudly under CI
  rather than letting the storage tests silently pass without running.
- **Where's my data?** `~/Documents/Openote/*.onote`. Open one in any SQLite
  browser and look at `page_mirror` to watch the open format doing its job. If
  Documents isn't usable (OneDrive folder redirection on Windows), Openote falls
  back to the per-user app-data directory (`%APPDATA%\org.openote\openote\Openote`).
- **PDF import fails on a fresh checkout:** `pdfrx` needs
  `pdfrxFlutterInitialize()` on the root isolate before the document API is
  touched; `main.dart` does this. If you refactor startup, keep it there.

## How the Rust core slots in

`lib/core/engine.dart` defines the `DocumentEngine` seam, and one of two
implementations is chosen once at startup by `AppState._selectEngine`:

- `MirrorEngine` — pure Dart, always available (direct mirror writes +
  `dirty_mirror` per spec §4).
- `RustEngine` — used whenever the native library loads
  (`lib/core/onote_ffi.dart`). Page saves are content-hashed in Rust and a save
  whose hash is unchanged is skipped. The status bar shows which engine is live.

The core also powers **OneNote import** and the imported-hyperlink repair pass,
neither of which has a Dart fallback; those menus report that the core is
required when the library is absent. The Loro CRDT
([ADR-0002](../docs/adr/ADR-0002-crdt-library.md)) is intended to replace the
snapshot merge behind this same seam and is **not wired**.

## What isn't built yet

Tracked in the [roadmap](../ROADMAP.md) and the
[v0.4 backlog](../docs/planning/v0.4-and-beyond.md); the ones that shape the
code you are about to read:

- **The structured rich-text model.** [ADR-0004](../docs/adr/ADR-0004-editor-engine.md)
  is decided (keep the engine we own, behind the `OnoteTextEditor` seam), but a
  block's text is still an interim Markdown **string** rather than the Data
  Model §5.1 `{nodes:[…]}` model. The migration is driven by sync
  ([ADR-0006](../docs/adr/ADR-0006-sync-transport-and-text-model.md)) rather
  than by the editor: an opaque string makes the smallest representable edit
  "the whole block is now this", which cannot merge per-character. Per-run
  styling, paragraph collapse and in-flow-images-editable-as-images all wait on
  it.
- **Sync is real but half-migrated.** Two devices sharing a folder works
  (`sync/`, ADR-0006 steps 1–3). The container has **not** been demoted to
  `cache.onote`, blobs are stored twice and never garbage-collected, and Loro
  and any network transport are absent.
- **`AppState` is a god object** — ~3,200 lines across 27 sections, because
  there is nowhere else for state to land. Splitting out `SyncCoordinator`,
  `StudyState` and `TagOps` is item E3 of the v0.4 backlog and is meant to
  happen before more features land in it.

## Code map

```
lib/
├── main.dart                     entry, theme wiring, pdfrx init
├── theme/onote_theme.dart        style-guide tokens + the font-fallback chain
├── core/
│   ├── ids.dart                  UUIDv7 (Data Model §2)
│   ├── engine.dart               DocumentEngine seam + MirrorEngine
│   ├── onote_ffi.dart            dart:ffi bindings to onote_core
│   ├── platform_open.dart        open a file/URL with the OS, scheme-allowlisted
│   └── system_fonts.dart         installed-font enumeration for the picker
├── model/
│   ├── models.dart               TreeNode, Block (+envelope), Stroke, JSON
│   └── tags.dart                 per-line tags (TEXT-5) and their rebasing
├── store/
│   ├── database.dart             .onote SQLite DDL (File Format Spec §3)
│   └── repository.dart           workspace/notebook/page CRUD, mirrors, blobs
├── state/
│   ├── app_state.dart            app-wide state + the storage facade — the one
│   │                             funnel every persistent mutation passes through
│   └── builtin_templates.dart    the six shipped page templates
├── sync/                         ADR-0006 operation log (shadow mode)
│   ├── op.dart                   envelope + deterministic total order
│   ├── op_log.dart               Foo.onotebook/ops/<device>.oplog, append-only
│   ├── device_identity.dart      per-install id, forks on conflict
│   ├── materializer.dart         replay → state (delete-wins)
│   ├── sync_recorder.dart        diffs a page save into block-level ops
│   ├── cloud_folders.dart        detects Drive/OneDrive/… (and why no OAuth)
│   ├── folder_watch.dart         auto-pull when another device writes
│   └── mirrors.dart              per-notebook mirrors and dated backups
├── canvas/
│   ├── canvas_controller.dart    pan/zoom matrix, screen↔page mapping, snap
│   ├── page_canvas.dart          gestures, grid, ink capture, block layout
│   ├── ink_ops.dart              pure ink logic (touch-vs-pen routing)
│   ├── ink_painter.dart          perfect-freehand outline painting
│   ├── align_guides.dart         snap lines against sibling edges
│   ├── media_drop.dart           paste and drag-drop into the page or a box
│   ├── block_view.dart           selection chrome, move bar, resize, dispatch
│   └── page_title_view.dart      the in-page title band
├── editor/
│   ├── onote_text_editor.dart    ADR-0004 engine seam (the swap point)
│   ├── live_markdown_engine.dart the engine we ship, behind that seam
│   ├── live_markdown_controller.dart  as-you-type marker collapsing
│   ├── unicode_input.dart        Alt+X code-point conversion
│   ├── text_block_view.dart      host for a text container (not an editor)
│   ├── math_block_view.dart      linear entry ↔ rendered 2-D maths
│   ├── table_block_view.dart, code_block_view.dart, code_highlight.dart
│   └── image_block_view.dart, file_block_view.dart
├── math/
│   ├── linear_math.dart          linear input → LaTeX (Math Input Spec §3)
│   └── evaluate.dart             numeric evaluation — a calculator, not a CAS
├── markdown/                     rendering + GFM pipe tables (two-way)
├── spell/spell_checker.dart      English spell check + learned words
├── study/
│   ├── flashcards.dart           cards from tagged lines, SM-2 scheduling
│   └── study_stats.dart          streak, activity and exam-countdown maths
├── export/                       Markdown, PDF (vector + raster), open folder,
│                                 OneNote/.onepkg import, Markdown import,
│                                 PDF-as-annotatable-pages import
└── ui/
    ├── app_shell.dart            layout: navigator | command bar / canvas / panels
    ├── sidebar.dart              the stacked navigator (style guide §7b)
    ├── command_bar.dart          the tabbed command bar
    ├── study_panel.dart          review, progress and the exam countdown
    ├── notebook_manager.dart, sync_dialog.dart, onboarding.dart
    ├── color_picker.dart, font_picker.dart, exam_date.dart
    └── context_menus.dart
```
