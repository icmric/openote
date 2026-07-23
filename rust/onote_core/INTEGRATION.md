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

## 2. Automatic build (optional, permanent) — edit `app\windows\CMakeLists.txt`

To have `flutter run` / `flutter build windows` compile the crate and copy the
DLL for you, add this near the **end** of `app/windows/CMakeLists.txt` (after
the `add_executable(${BINARY_NAME} ...)` / runner target is defined):

```cmake
# --- onote-core (Rust) : build the crate and place the DLL next to the exe ---
set(ONOTE_CORE_MANIFEST "${CMAKE_SOURCE_DIR}/../../rust/onote_core/Cargo.toml")
set(ONOTE_CORE_DLL      "${CMAKE_SOURCE_DIR}/../../rust/onote_core/target/release/onote_core.dll")
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND cargo build --release --manifest-path "${ONOTE_CORE_MANIFEST}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${ONOTE_CORE_DLL}" "$<TARGET_FILE_DIR:${BINARY_NAME}>"
  COMMENT "Building and bundling onote-core (Rust)"
  VERBATIM)
```

Requirements: `cargo` must be on PATH for the process that runs the Flutter
build (step 0). For a packaged/installer build, ensure `onote_core.dll` ships
in the same folder as `openote.exe` (the `copy_if_different` above puts it in
the runner output dir that Flutter bundles).

macOS/Linux use the same idea with `libonote_core.dylib` / `libonote_core.so`;
the Dart loader already knows those names.

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
