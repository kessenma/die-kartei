#!/bin/bash
# Builds llama.cpp for the Android app: arm64 shared libraries plus the headers the CLlama module
# imports. Output (gitignored except the headers):
#   DieKarteiAndroid/Vendor/llama/arm64-v8a/*.so        packaged into the APK (see app/build.gradle.kts)
#   DieKarteiAndroid/Sources/CLlama/include/*.h         llama.h and the ggml headers it includes
#
# The CPU backend is built once per ARM feature level (GGML_CPU_ALL_VARIANTS) and loaded at
# runtime (GGML_BACKEND_DL), so each phone gets the fastest kernels it supports (dotprod, i8mm,
# SVE2, SME) from one APK. TutorEngine loads them from the app's native library directory.
#
#   scripts/build_llama_android.sh            # uses ~/ws/llama.cpp at the pinned commit
#   LLAMA_DIR=/path/to/llama.cpp scripts/build_llama_android.sh
set -euo pipefail

LLAMA_COMMIT=fa9f928
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_DIR="${LLAMA_DIR:-$HOME/ws/llama.cpp}"
OUT_LIB="$ROOT/DieKarteiAndroid/Vendor/llama/arm64-v8a"
OUT_INC="$ROOT/DieKarteiAndroid/Sources/CLlama/include"
: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME (source ~/.zprofile)}"

if [ ! -d "$LLAMA_DIR" ]; then
  git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
fi
git -C "$LLAMA_DIR" fetch --quiet origin "$LLAMA_COMMIT" 2>/dev/null || true
git -C "$LLAMA_DIR" checkout --quiet "$LLAMA_COMMIT"

BUILD="$LLAMA_DIR/build-android-so"
cmake -S "$LLAMA_DIR" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28 -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
  -DLLAMA_BUILD_COMMON=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_APP=OFF \
  -DLLAMA_OPENSSL=OFF -DLLAMA_CURL=OFF \
  -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON \
  -DGGML_LLAMAFILE=OFF -DGGML_OPENMP=OFF >/dev/null
cmake --build "$BUILD" -j --target llama >/dev/null

STRIP="$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-strip | head -1)"
rm -rf "$OUT_LIB" && mkdir -p "$OUT_LIB" "$OUT_INC"
for so in "$BUILD"/bin/*.so; do
  "$STRIP" --strip-unneeded "$so" -o "$OUT_LIB/$(basename "$so")"
done
for h in ggml.h ggml-alloc.h ggml-backend.h ggml-cpu.h ggml-opt.h gguf.h; do cp "$LLAMA_DIR/ggml/include/$h" "$OUT_INC/"; done
cp "$LLAMA_DIR/include/llama.h" "$OUT_INC/"
echo "llama.cpp $LLAMA_COMMIT → $OUT_LIB"
ls -la "$OUT_LIB"
