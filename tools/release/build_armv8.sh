#!/usr/bin/env bash
# Builds the ARMv8 (arm64-v8a) version of PrismLive on Linux/macOS
# Usage: ./tools/release/build_armv8.sh [release|debug] [outDir]

set -euo pipefail

MODE="${1:-release}"
MODE_LOWER=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${2:-$ROOT_DIR/build/release}"

echo "=== Building PrismLive ARMv8 (arm64-v8a) [$MODE_LOWER] ==="

# 1. Compile purelive_core_rs if NDK available
RUST_CORE_DIR="$ROOT_DIR/rust/purelive_core_rs"
JNI_LIBS_ARM64="$ROOT_DIR/apps/pure_live/android/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$JNI_LIBS_ARM64"

if [ -n "${ANDROID_NDK_HOME:-}" ] || [ -n "${ANDROID_NDK_ROOT:-}" ]; then
    NDK_DIR="${ANDROID_NDK_HOME:-$ANDROID_NDK_ROOT}"
    echo "[1/3] Compiling purelive_core_rs for aarch64-linux-android with NDK: $NDK_DIR..."
    pushd "$RUST_CORE_DIR" > /dev/null
    cargo build --release --target aarch64-linux-android
    if [ -f "$RUST_CORE_DIR/target/aarch64-linux-android/release/libpurelive_core_rs.so" ]; then
        cp "$RUST_CORE_DIR/target/aarch64-linux-android/release/libpurelive_core_rs.so" "$JNI_LIBS_ARM64/"
    fi
    popd > /dev/null
else
    echo "[1/3] NDK not set, using existing binaries in jniLibs if present..."
fi

# 2. Build Flutter APK
echo "[2/3] Building Flutter APK ($MODE_LOWER, android-arm64)..."
pushd "$ROOT_DIR/apps/pure_live" > /dev/null
flutter build apk "--$MODE_LOWER" --target-platform android-arm64 --split-per-abi
popd > /dev/null

# 3. Verify and copy
APK_PATH="$ROOT_DIR/apps/pure_live/build/app/outputs/flutter-apk/app-arm64-v8a-$MODE_LOWER.apk"
if [ ! -f "$APK_PATH" ]; then
    echo "Error: Expected APK not found: $APK_PATH"
    exit 1
fi

mkdir -p "$OUT_DIR"
DEST_PATH="$OUT_DIR/PrismLive-arm64-v8a-$MODE_LOWER.apk"
cp "$APK_PATH" "$DEST_PATH"

SIZE_BYTES=$(wc -c < "$DEST_PATH")
SIZE_MB=$(awk "BEGIN {printf \"%.2f\", $SIZE_BYTES / 1048576}")
echo "Success! Generated ARMv8 APK: $DEST_PATH ($SIZE_MB MB)"
