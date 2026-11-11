#!/bin/bash
#
# Build the writing checker (rust/onote_text) and put its dylib inside the .app.
#
# The sibling of build_onote_core.sh, and run BY it (as its last act), so the
# Xcode project needs no second build phase. Everything that script explains
# applies here and is not repeated: $ARCHS decides the targets, a universal app
# needs a universal dylib, MACOSX_DEPLOYMENT_TARGET is dropped before cargo, a
# missing Rust target is a warning and a compile error is not, and the loader
# falls back (here, to the older word list with no grammar checking) when the
# library is absent — so a failure to bundle costs a feature, never a launch.
#
# ============================================================================
# UNVERIFIED ON REAL HARDWARE, like the script it follows. Written on Windows.
# The first build on a Mac compiles Harper, which takes about 13 minutes per
# architecture; after that cargo is incremental. When the core hook has been
# confirmed on a Mac, confirm this one with it and delete this banner.
# ============================================================================
set -euo pipefail

LIB_NAME=libonote_text.dylib

if [ -z "${SRCROOT:-}" ] || [ -z "${TARGET_BUILD_DIR:-}" ]; then
  echo "error: $(basename "$0") expects Xcode's build environment (SRCROOT," \
       "TARGET_BUILD_DIR, ARCHS)." >&2
  exit 1
fi

CRATE_DIR="$SRCROOT/../../rust/onote_text"
export PATH="$PATH:$HOME/.cargo/bin"

if ! command -v cargo >/dev/null 2>&1; then
  echo "warning: cargo not found — skipping the writing checker ($LIB_NAME). The" \
       "editor will use its older word list, with no grammar checking."
  exit 0
fi

triples=""
for arch in ${ARCHS:-$(uname -m)}; do
  case "$arch" in
    arm64) triples="$triples aarch64-apple-darwin" ;;
    x86_64) triples="$triples x86_64-apple-darwin" ;;
    *)
      echo "warning: no Rust target is mapped for architecture '$arch' — the" \
           "writing checker will be missing for it."
      ;;
  esac
done

unset MACOSX_DEPLOYMENT_TARGET
built=""
n_built=0
n_wanted=0
for triple in $triples; do
  n_wanted=$((n_wanted + 1))
  if command -v rustup >/dev/null 2>&1 &&
     ! rustup target list --installed | grep -qx "$triple"; then
    echo "warning: Rust target $triple is not installed, so the writing checker" \
         "will be missing for that architecture. Fix with: rustup target add $triple"
    continue
  fi
  cargo build --release --manifest-path "$CRATE_DIR/Cargo.toml" --target "$triple"
  built="$built $triple"
  n_built=$((n_built + 1))
done

if [ "$n_built" -eq 0 ]; then
  echo "warning: no architecture of the writing checker could be built — the" \
       "editor will use its older word list, with no grammar checking."
  exit 0
fi
if [ "$n_built" -lt "$n_wanted" ]; then
  echo "warning: the writing checker was built for $n_built of $n_wanted" \
       "architectures; the others fall back to the older word list."
fi

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

DEST="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH"
mkdir -p "$DEST"
cp -f "$STAGED" "$DEST/$LIB_NAME"

if ! codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DEST/$LIB_NAME"; then
  echo "warning: could not sign $LIB_NAME. If grammar checking is missing, this" \
       "is the first thing to check."
fi

echo "onote_text: $LIB_NAME ($(echo "$built" | tr -s ' ' | sed 's/^ //')) -> $DEST"
