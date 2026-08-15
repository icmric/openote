#!/bin/bash
#
# Build the Rust core (rust/onote_core) and put its dylib inside the built .app.
#
# This is macOS's answer to the hook in app/windows/CMakeLists.txt and
# app/linux/CMakeLists.txt. Those two run `cargo build --release` on every
# `flutter build` / `flutter run` and bundle the library next to the
# executable, which is what closed the stale-library trap that
# rust/onote_core/INTEGRATION.md exists to warn about. macOS was the odd one
# out — Flutter drives it through Xcode, not our CMake — so
# `flutter build macos` produced an app with no core, and therefore no OneNote
# import, and nothing on screen said so.
#
# ============================================================================
# UNVERIFIED ON REAL HARDWARE. Written on a Windows machine against the Xcode
# and cargo documentation and the two CMake hooks it mirrors. What was checked
# statically: shell syntax (`bash -n`), the target triples, the crate's output
# paths, and that project.pbxproj still parses. What was NOT checked: that it
# runs. Nobody here has a Mac. The first person who does should work through
# the checklist in app/README.md ("Verifying the macOS hook") and delete this
# banner — leaving it in place is how the next reader knows the difference.
# ============================================================================
set -euo pipefail

LIB_NAME=libonote_core.dylib

# Xcode-only. Named explicitly rather than left to `set -u`'s "unbound
# variable", because someone WILL run this by hand while debugging it and
# deserves a sentence instead of a line number.
if [ -z "${SRCROOT:-}" ] || [ -z "${TARGET_BUILD_DIR:-}" ]; then
  echo "error: $(basename "$0") expects Xcode's build environment (SRCROOT," \
       "TARGET_BUILD_DIR, ARCHS). It runs as a Run Script build phase on the" \
       "Runner target; to build the core by hand instead, see" \
       "rust/onote_core/INTEGRATION.md." >&2
  exit 1
fi

# SRCROOT is app/macos, so this is rust/onote_core — the same relative hop the
# CMake hooks make with ${CMAKE_CURRENT_SOURCE_DIR}/../../rust/onote_core.
CRATE_DIR="$SRCROOT/../../rust/onote_core"

# Xcode does not run your login shell, so ~/.cargo/bin is missing from PATH
# when the build starts from the Xcode UI even though `cargo --version` works
# fine in Terminal. The CMake hooks solve the identical problem with
# find_program(... HINTS "$ENV{HOME}/.cargo/bin"). Appended, not prepended, so
# a cargo deliberately placed earlier on PATH still wins.
export PATH="$PATH:$HOME/.cargo/bin"

# Xcode turns a line beginning `warning:` or `error:` from a script phase into
# an entry in the issue navigator, which is the closest thing here to CMake's
# message(WARNING ...) — the point being that skipping the core has to be
# visible, not buried in a build log nobody opens.
if ! command -v cargo >/dev/null 2>&1; then
  echo "warning: cargo not found — skipping the Rust core ($LIB_NAME). The" \
       "app will run on the pure-Dart engine, minus OneNote import. Install" \
       "Rust from https://rustup.rs, reopen your terminal, and rebuild."
  exit 0
fi

# --- Which architectures -----------------------------------------------------
#
# $ARCHS is what Xcode is really building, after ONLY_ACTIVE_ARCH has been
# applied: one arch for a Debug run on this machine (Debug sets
# ONLY_ACTIVE_ARCH = YES), and both for Release and Profile, which leave ARCHS
# at $(ARCHS_STANDARD) — arm64 and x86_64. That is why `flutter build macos
# --release` produces a universal app, and it is the whole reason to read ARCHS
# rather than pick an architecture here: a universal app carrying an
# arm64-only dylib loses the Rust core on every Intel Mac, and loses it
# SILENTLY, because the loader is deliberately built to fall back to the Dart
# engine when dlopen fails (app/lib/core/onote_ffi.dart). Nobody would see a
# crash; OneNote import would just be missing on half the machines.
#
# Space-separated strings rather than bash arrays throughout: /bin/bash on
# macOS is still 3.2, where expanding an empty array under `set -u` is an
# "unbound variable" error.
triples=""
for arch in ${ARCHS:-$(uname -m)}; do
  case "$arch" in
    arm64) triples="$triples aarch64-apple-darwin" ;;
    x86_64) triples="$triples x86_64-apple-darwin" ;;
    *)
      echo "warning: no Rust target is mapped for architecture '$arch' — the" \
           "Rust core will be missing for it. Add the mapping in" \
           "$(basename "$0")."
      ;;
  esac
done

# --- Build each one ----------------------------------------------------------
#
# Always --release, whatever Xcode is building. Same choice as the CMake
# hooks, and it is not arbitrary: the crate's release profile is where lto and
# codegen-units = 1 live (Cargo.toml), import parses tens of MB per notebook,
# and a debug core would make import look broken rather than slow.
#
# A cargo compile error fails the app build, exactly as on Windows and Linux —
# failing loudly beats shipping a stale core. A MISSING TARGET is different:
# that is a machine-setup gap, not a code fault, so it warns and carries on,
# which keeps a Debug run working while the developer sorts out rustup.
#
# MACOSX_DEPLOYMENT_TARGET is dropped first, and it matters. Xcode exports it
# into every script phase (this project sets 10.15) and rustc reads it from the
# environment — but 10.15 predates Apple Silicon, so it is not a legal
# deployment target for aarch64-apple-darwin at all. Left in place, the arm64
# build can fail or warn inside Xcode while the identical `cargo build` from
# Terminal succeeds, which is exactly the kind of only-here failure nobody can
# reproduce. Unset, each target uses rustc's own floor (10.12 for x86_64, 11.0
# for arm64) — both at or below the app's, so the dylib loads everywhere the
# app runs — and cargo sees the same environment it sees in release.yml, which
# is the one that has actually been exercised.
unset MACOSX_DEPLOYMENT_TARGET
built=""
n_built=0
n_wanted=0
for triple in $triples; do
  n_wanted=$((n_wanted + 1))
  if command -v rustup >/dev/null 2>&1 &&
     ! rustup target list --installed | grep -qx "$triple"; then
    echo "warning: Rust target $triple is not installed, so the core will be" \
         "missing for that architecture. Fix with: rustup target add $triple"
    continue
  fi
  cargo build --release --manifest-path "$CRATE_DIR/Cargo.toml" --target "$triple"
  built="$built $triple"
  n_built=$((n_built + 1))
done

if [ "$n_built" -eq 0 ]; then
  echo "warning: no architecture of the Rust core could be built — the app" \
       "will run on the pure-Dart engine, minus OneNote import."
  exit 0
fi
if [ "$n_built" -lt "$n_wanted" ]; then
  echo "warning: the Rust core was built for $n_built of $n_wanted" \
       "architectures. This app bundle will lose OneNote import on the" \
       "architectures listed above — it will not crash, it will quietly run" \
       "the Dart engine there instead."
fi

# --- Combine -----------------------------------------------------------------
#
# Positional parameters, not a variable holding a list of paths: a checkout
# under a directory with a space in its name ("~/My Projects/openote") would
# split a plain string into wrong arguments, and lipo would fail on a path
# fragment.
set --
for triple in $built; do
  set -- "$@" "$CRATE_DIR/target/$triple/release/$LIB_NAME"
done

STAGE_DIR="${DERIVED_FILE_DIR:-${TARGET_TEMP_DIR:-$CRATE_DIR/target}}"
mkdir -p "$STAGE_DIR"
STAGED="$STAGE_DIR/$LIB_NAME"
if [ "$#" -gt 1 ]; then
  lipo -create -output "$STAGED" "$@"
else
  cp -f "$1" "$STAGED"
fi

# --- Into the bundle ---------------------------------------------------------
#
# EXECUTABLE_FOLDER_PATH is openote.app/Contents/MacOS, which is where the
# loader looks first: its first candidate is the directory of
# Platform.resolvedExecutable (app/lib/core/onote_ffi.dart), and for a .app
# that resolves to Contents/MacOS. Same contract release.yml already states
# for the release dmg.
DEST="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH"
mkdir -p "$DEST"
cp -f "$STAGED" "$DEST/$LIB_NAME"

# Insert first, then let Xcode sign: Xcode's CodeSign step runs after every
# build phase, so a dylib copied in here is present when the bundle's seal is
# computed. That is the one structural difference from release.yml, which
# copies the dylib in AFTER `flutter build macos` has already signed and so
# has to re-sign the bundle by hand — insert a file into a signed bundle and
# the app is killed on launch.
#
# The dylib still needs a signature of its own: `codesign` on an .app does not
# sign other Mach-O files sitting in Contents/MacOS, and on Apple Silicon an
# unsigned binary will not load at all. ${EXPANDED_CODE_SIGN_IDENTITY:--}
# reads "the identity Xcode resolved, or ad-hoc" — the macOS configs here all
# set CODE_SIGN_IDENTITY = "-" already.
#
# Non-fatal deliberately, and this is the one place that differs from the
# "fail loudly" rule above: the linker has already ad-hoc signed arm64 output,
# so this is belt-and-braces, and a signing edge case should not stop an
# app from building when the worst case is a fallback the app is designed for.
if ! codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DEST/$LIB_NAME"; then
  echo "warning: could not sign $LIB_NAME. If the status bar shows 'Dart" \
       "engine' rather than 'Rust core', this is the first thing to check."
fi

echo "onote_core: $LIB_NAME ($(echo "$built" | tr -s ' ' | sed 's/^ //')) -> $DEST"
