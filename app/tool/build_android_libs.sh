#!/usr/bin/env bash
# Build the two Rust libraries for Android and put them where the app looks.
#
#   bash app/tool/build_android_libs.sh            # arm64 (every current phone)
#   bash app/tool/build_android_libs.sh x86_64     # an emulator on a PC
#
# Needs: `rustup target add aarch64-linux-android` (or x86_64-linux-android) and
# the Android NDK (installed with the SDK). No other tools: both crates are pure
# Rust, so the NDK's clang is only the linker.
#
# Builds into its own target directory (`target-android`), so it never touches
# the Windows library the running app has loaded from `target/release`.
set -euo pipefail

ABI="${1:-arm64-v8a}"
case "$ABI" in
  arm64-v8a|arm64) TRIPLE=aarch64-linux-android; ABI=arm64-v8a; CLANG_PREFIX=aarch64-linux-android ;;
  x86_64)          TRIPLE=x86_64-linux-android;  ABI=x86_64;    CLANG_PREFIX=x86_64-linux-android ;;
  *) echo "unknown ABI $ABI (arm64-v8a or x86_64)"; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$LOCALAPPDATA/Android/Sdk}}"
NDK="$(ls -d "$SDK"/ndk/* | sort -V | tail -1)"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) HOST=windows-x86_64; EXT=.cmd ;;
  Darwin)               HOST=darwin-x86_64;  EXT= ;;
  *)                    HOST=linux-x86_64;   EXT= ;;
esac
BIN="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
API=24 # Android 7; the floor for the libraries' own needs
CLANG="$BIN/${CLANG_PREFIX}${API}-clang${EXT}"
[ -e "$CLANG" ] || { echo "NDK clang not found: $CLANG"; exit 1; }

UP="$(echo "$TRIPLE" | tr 'a-z-' 'A-Z_')"
export "CARGO_TARGET_${UP}_LINKER=$CLANG"
export "CC_${TRIPLE//-/_}=$CLANG"
export "AR_${TRIPLE//-/_}=$BIN/llvm-ar${EXT/.cmd/.exe}"
# Android 15+ devices may use 16 KB memory pages; a library built for 4 KB pages
# triggers the "not 16 KB-compatible" warning and, later, will not load at all.
export "CARGO_TARGET_${UP}_RUSTFLAGS=-C link-arg=-Wl,-z,max-page-size=16384"

OUT="$ROOT/app/android/app/src/main/jniLibs/$ABI"
mkdir -p "$OUT"
for crate in onote_core onote_text; do
  echo "== $crate ($TRIPLE)"
  (cd "$ROOT/rust/$crate" && CARGO_TARGET_DIR="$ROOT/rust/$crate/target-android" \
     cargo build --release --target "$TRIPLE")
  cp "$ROOT/rust/$crate/target-android/$TRIPLE/release/lib$crate.so" "$OUT/"
done
ls -la "$OUT"
