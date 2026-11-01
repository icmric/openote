# Openote — the application

The Openote desktop app: a Flutter/Dart UI over a native **Rust core**
(`rust/onote_core`) linked with hand-written `dart:ffi`. It reads and writes real
notebooks per the [file format spec](../docs/specs/10-file-format-spec.md).

The Rust core is **optional at runtime** — without its library the app falls back
to the pure-Dart engine and behaves identically, minus OneNote import. It is not
optional at build time on Windows and Linux; see below.

This file describes the app as it is, not how it got here. Release history is in
[CHANGELOG.md](../CHANGELOG.md).

## Building and running

Prereqs: Flutter (latest stable) with desktop support for your OS. Rust
(`cargo`) is needed only to build the native core — the app runs without it.

```bash
cd app
flutter pub get
flutter test
flutter run -d windows      # or -d linux / -d macos
```

> **Do not run `flutter create` in this directory**, for any platform. The
> runner projects are tracked, and `windows/CMakeLists.txt` and
> `linux/CMakeLists.txt` carry the hook that builds and bundles the Rust core.
> `flutter create` overwrites them, which reintroduces the stale-library trap
> below. Adding a platform is worse than it looks: `--platforms=web` also
> dropped `pdfium_flutter` from all three desktop plugin registrants, trading a
> working desktop build for a `web/` folder. Write the platform files by hand.

Linux desktop needs the usual toolchain (`clang`, `cmake`, `ninja-build`,
`libgtk-3-dev`); `flutter doctor` names whatever is missing.

### The Rust core

**On Windows and Linux, `flutter build` builds the core for you.** The CMake
hook in each runner project invokes `cargo build --release` and copies the
library next to the executable, which is what closed the stale-DLL trap that
burned several sessions (fixes appearing to do nothing because an old library
was still being loaded). If `cargo` is not on `PATH` the hook prints a warning
and skips it, and the app runs on the Dart engine.

**macOS now has the same hook, written but never run.** Flutter drives macOS
through Xcode rather than our CMake, so the equivalent is a Run Script build
phase on the Runner target that calls
[`macos/build_onote_core.sh`](macos/build_onote_core.sh). It mirrors the CMake
hooks deliberately: always `cargo build --release`, no cargo means a warning
rather than a failure, a broken crate fails the build, and the phase is
declared last so nothing Flutter does can overwrite what it copied in.

It differs from the CMake hooks in one place, and it is the interesting one:
**architecture**. The script reads Xcode's `$ARCHS` and builds one Rust target
per entry — `aarch64-apple-darwin` for `arm64`, `x86_64-apple-darwin` for
`x86_64` — then `lipo`s them into one dylib. A Debug run builds only your own
machine's architecture (Debug sets `ONLY_ACTIVE_ARCH = YES`); a Release or
Profile build gets both, because `flutter build macos --release` produces a
universal app. This is not tidiness: a universal app carrying an arm64-only
dylib loses the Rust core on every Intel Mac, and loses it *silently*, since
the loader is built to fall back to the Dart engine when `dlopen` fails.

The release workflow still does the same work explicitly
(`.github/workflows/release.yml` builds both architectures, `lipo`s them, drops
the dylib into `Contents/MacOS/` and re-signs). That is now redundant on paper
and is staying until the build phase has been confirmed on real hardware — a
tag must not be the first thing to find out this script is wrong. See
[`rust/onote_core/INTEGRATION.md`](../rust/onote_core/INTEGRATION.md).

#### Verifying the macOS hook (nobody has yet)

The script and the Xcode phase were written on a Windows machine. What was
checked there: shell syntax under `bash -n` and `sh -n`, every branch driven
with stub `cargo`/`rustup`/`lipo`/`codesign` (including a checkout path with a
space in it), the target triples, the crate's output paths, and that
`Runner.xcodeproj/project.pbxproj` still parses with its object graph intact.
What was not checked: that any of it runs. On the first Mac to try it:

1. `rustup target add aarch64-apple-darwin x86_64-apple-darwin`.
2. `cd app && flutter build macos --release`. The build log should carry an
   `onote_core: libonote_core.dylib (…) -> …/openote.app/Contents/MacOS` line.
3. `lipo -info build/macos/Build/Products/Release/openote.app/Contents/MacOS/libonote_core.dylib`
   → must list **both** `x86_64` and `arm64`.
4. `codesign --verify --strict --verbose=2` on the `.app` → must pass. This is
   the assumption most worth testing: the script copies the dylib in *during*
   the build on the belief that Xcode's own code-signing step runs after all
   build phases, so no manual re-sign is needed. If that is wrong, the app will
   be killed on launch and the script needs to re-sign the bundle itself.
5. Open the app. The status bar should show the green **`Rust core v0.1.0`**
   chip, not `Dart engine`.
6. `flutter run -d macos` (Debug) — same chip, and step 3 lists one
   architecture, your own.
7. If the phase never runs at all, check the exec bit: the phase invokes
   `/bin/bash "$SRCROOT/build_onote_core.sh"` precisely so the script does not
   need one, because the file was authored on Windows where git records mode
   `100644`.

Then delete the "UNVERIFIED" banner at the top of the script, and this
paragraph.

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

Three gaps shape the code you are about to read. The rest of the open work is
in the [backlog](../docs/planning/backlog.md).

- **Text is a Markdown string, not a structured model.** A text block keeps its
  content in `content['text']`; the `{nodes: […]}` model of
  [Data Model §5.1](../docs/specs/11-data-model-spec.md) is specified and not
  built. Everything that wants to address a *run* of text rather than the whole
  block waits on it: per-run styling, paragraph collapse, and editing an
  in-flow image as an image. The migration has one landing site by design —
  `OnoteTextEditor.serialize` / `deserialize` / `textStorageKey`.
- **Two text edits to one block cannot both win.** Folder and git sync both
  work, and ops are block-level, so two devices editing different blocks merge
  cleanly. `block.patch` narrows the cost of a keystroke to a splice but still
  falls back to last-writer-wins when two splices collide. Real convergence
  needs a sequence CRDT ([ADR-0002](../docs/adr/ADR-0002-crdt-library.md)),
  which is chosen and not integrated. There is no network transport either —
  sync is files in a folder somebody else replicates.
- **`AppState` holds most of the app's state**, and `notifyListeners` offers a
  rebuild of everything to every listener. That is why per-keystroke caches and
  `ui/memo.dart` exist. Splitting it is the standing second item on the backlog;
  `StudyState` and `PlannerState` came out first.

## Code map

By directory, because a file-by-file map of 220-odd files goes stale faster
than it helps. Each directory is one subject; `grep` finds the file.

```
lib/
├── main.dart      entry point, theme wiring, pdfrx init
├── model/         TreeNode, Block and its envelope, Stroke, JSON round-trip
├── store/         the SQLite container, the workspace registry, blobs, media
├── sync/          the op log, folder and git transports, device identity
├── state/         AppState and the three states split out of it so far
├── canvas/        the page surface: placement, selection, ink input, portals
├── editor/        text, code, tables, flashcards, boards — one view per block
├── markdown/      one grammar, shared by the live editor and the renderer
├── math/          the editing tree, the linear grammar, evaluation, graphs
├── ink/           stroke storage and the binary codec
├── media/         images, video, recordings
├── export/        PDF, Markdown, the open folder, and every importer
├── onenote/       Microsoft Graph: sign-in, page fetch, MathML conversion
├── code/          JS and SQL cells and the engines behind them
├── planner/       dates, reminders, the ICS timetable, the agenda
├── study/         flashcard scheduling and Anki export
├── api/           the MCP server and the one-click client connections
├── ui/            the shell, the command bar, the navigator, every dialog
├── core/          cross-cutting: ids, FFI, platform seams, single instance
├── theme/         tokens and the component themes built from them
├── spell/         the dictionary and the checker
├── update/        the in-app update check
└── l10n/          `.arb` message files; `gen/` is generated, do not edit
```

A file named `x_native.dart` / `x_web.dart` beside an `x.dart` is a platform
seam: `x.dart` is a conditional export and nothing else imports the halves
directly. `core/capabilities.dart` is where a feature asks whether its
platform dependency is present.