# Linking the Rust core into the app

The app calls the Rust core (`onote_core`) through `dart:ffi` — see
`app/lib/core/onote_ffi.dart`. Loading is **optional**: if the native library
is present the app uses it (and the status bar shows a green
`Rust core v0.1.0 · <hash>` chip); if it's absent the app runs exactly as the
pure-Dart build did. So wiring this in can't break your build — worst case the
chip stays grey and says `Dart engine`.

## 0. Prerequisite: make `cargo` runnable

The "`cargo` is unrecognised" message means Cargo isn't on your PATH in that
terminal. Rust's installer adds `%USERPROFILE%\.cargo\bin`, but an
already-open terminal won't see it. Fix: **close and reopen the terminal**
(or sign out/in), then confirm:

```
cargo --version
```

## 1. Quick check (no CMake changes) — do this first

Build the library and drop it next to the app's executable.

```powershell
# from the repo root
cd rust\onote_core
cargo build --release
```

That produces `rust\onote_core\target\release\onote_core.dll`. Copy it next to
the built `openote.exe`:

- Debug run:   `app\build\windows\x64\runner\Debug\`
- Release build: `app\build\windows\x64\runner\Release\`

```powershell
copy target\release\onote_core.dll ..\..\app\build\windows\x64\runner\Debug\
```

Run the app. The status bar (bottom) should show a green **`Rust core v0.1.0`**
chip, and a short hash that changes as you edit and save a page — that hash is
computed in Rust from your live page data on every save, so it's a real
end-to-end round-trip, not a version string.

If the chip stays grey (`Dart engine`), the DLL wasn't found next to the exe —
double-check the folder, or use step 2 to have the build place it for you.

> ### ⚠ The stale-DLL trap — read this before debugging any import problem
>
> **The app does NOT rebuild the Rust core.** `flutter run` / `flutter build windows`
> only compiles Dart; the DLL next to the exe is whatever you last copied there.
> After **any** change to this crate you must `cargo build --release` **and**
> re-copy (step 1), or you will be testing old native code.
>
> This has bitten us repeatedly, and the symptoms look exactly like parser bugs —
> wrong page order, missing content, "the fix didn't work". Always verify:
>
> ```powershell
> # hashes MUST match, or you are running a stale core
> Get-FileHash target\release\onote_core.dll
> Get-FileHash ..\..\app\build\windows\x64\runner\Debug\onote_core.dll
> ```
>
> Mitigations in place: `OnoteCore._tryLoad` (Dart) prefers the **newest** candidate
> DLL by mtime, so a fresh `cargo build` is often picked up without the copy; and
> the status-bar chip shows the loaded core's version.
>
> **As of 2026-07-27 this trap is CLOSED on Windows and Linux** — see §2. The
> warning above is retained for anyone building macOS by hand, and as history.

## 2. Automatic build — **WIRED** on Windows and Linux (2026-07-27)

`app/windows/CMakeLists.txt` and `app/linux/CMakeLists.txt` build the crate on
every `flutter build` / `flutter run` and bundle the library next to the
executable. Verified end-to-end: after `flutter build windows --release`, the
bundled `onote_core.dll`'s hash equals `target/release/onote_core.dll`'s.

Three properties of the wiring worth knowing:

- **It is an `install(FILES … OPTIONAL)` rule declared LAST, not a POST_BUILD
  copy.** The snippet this section used to recommend
  (`add_custom_command(TARGET … POST_BUILD)`) is broken by design on Linux: the
  install sequence *starts* by `REMOVE_RECURSE`-ing the whole bundle directory,
  so a post-build copy is wiped before the user ever runs the app. Install
  rules execute in declaration order; last-declared lands after Flutter's own
  bundle steps.
- **No cargo → warning, not failure.** Contributors without Rust still get a
  working app on the pure-Dart engine (minus OneNote import). CMake warns at
  configure time and at build time; `OPTIONAL` lets the install proceed.
- **Cargo present but the crate broken → the app build fails.** Deliberate:
  failing loudly beats silently running a stale core, which is exactly the bug
  class this document exists to warn about.

**macOS is manual for now** (`app/macos` is Xcode, not CMake): `cargo build
--release`, copy `target/release/libonote_core.dylib` into
`openote.app/Contents/MacOS/`, then **re-sign ad-hoc**
(`codesign --force --deep --sign - <app>`) — inserting a dylib breaks the
bundle's signature seal and the app is killed on launch without it. The release
workflow does exactly this, universal via `lipo`. Proper wiring later: a Run
Script phase on the Runner target after Flutter's own, "based on dependency
analysis" unchecked.

`sync-core.bat` remains useful only as the fast path for Rust-only iteration
(`sync-core.bat rust`); its build-then-copy choreography is otherwise
superseded by the CMake wiring.

## What the app uses it for today

- **Status-bar engine indicator** — proves the library loaded and a call
  round-trips (a self-test merge runs at startup).
- **Page content hash on save** — the current page's mirror JSON is hashed in
  Rust each time it saves. This is the change-detection primitive sync will use
  (skip re-sending unchanged pages), exercised now over real data.

The merge function (`onote_core_merge`) is linked and unit-tested but not yet on
a user-facing path — it activates when the sync flow is built. Swapping the
whole `DocumentEngine` to a Rust-backed implementation, and later to the Loro
CRDT (ADR-0002), happens behind the existing interface without touching UI.
