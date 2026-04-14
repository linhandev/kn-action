#!/usr/bin/env bash
# GHA ohos-test-build matrix leg. Requires dotenv from llvm:cross-copy (archive_*).
set -euo pipefail

PLATFORM="${1:?usage: ohos-test-build.sh linux-x64|windows-x64|macos-arm64|macos-x64}"
: "${CI_PROJECT_DIR:?}"
: "${CI_PIPELINE_ID:?}"

case "$PLATFORM" in
  linux-x64) n="${archive_linux:?}" ;;
  windows-x64) n="${archive_windows:?}" ;;
  macos-arm64) n="${archive_mac_arm64:?}" ;;
  macos-x64) n="${archive_mac_x64:?}" ;;
  *)
    echo "unexpected platform $PLATFORM"
    exit 1
    ;;
esac

case "$PLATFORM" in
  linux-x64) SUF="Linux_X64" ;;
  windows-x64) SUF="Windows_X64" ;;
  macos-arm64) SUF="macOS_ARM64" ;;
  macos-x64) SUF="macOS_X64" ;;
esac

W="${CI_PROJECT_DIR}/ohos-test-work"
rm -rf "$W"
mkdir -p "$W/dl"
cd "$W"

"$CI_PROJECT_DIR/scripts/ci/download-artifact-local.sh" --name="$n" --dir="$W/dl"

LLVM_TAR="$W/dl/$n"
W_U="$W"
if [ "${RUNNER_OS:-}" = "Windows" ] && command -v cygpath >/dev/null 2>&1; then
  LLVM_TAR="$(cygpath -u "$LLVM_TAR")"
  W_U="$(cygpath -u "$W")"
fi

if [ ! -f "$LLVM_TAR" ] && [ -f "$W/dl/$n" ]; then
  LLVM_TAR="$W/dl/$n"
fi
if [ ! -f "$LLVM_TAR" ]; then
  echo "Downloaded archive not found for $n"
  ls -la "$W/dl" || true
  exit 1
fi

if [[ "$LLVM_TAR" = *.zip ]]; then
  unzip -q "$LLVM_TAR" -d "$W_U"
else
  tar -xzf "$LLVM_TAR" -C "$W_U"
fi

ROOT="$(find "$W_U" -maxdepth 1 -type d -name 'llvm-*-dev-*' | head -1)"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "Expected llvm-*-dev-* directory after extract"
  ls -la "$W_U" || true
  exit 1
fi

OHOS_SYSROOT="${OHOS_SYSROOT:-sysroot-ohos-aarch64-6.0.2.640-02}"
OHOS_SYSROOT_URL="${OHOS_SYSROOT_URL:-https://maven.eazytec-cloud.com/nexus/repository/file-storage/sysroot-ohos-aarch64-6.0.2.640-02.tar.gz}"
CACHE_BASE="${OHOS_SYSROOT_CACHE_DIR:-$HOME/gitlab-runner/cache}"
CACHE_BASE="${CACHE_BASE/#\~/$HOME}"
if [ "${RUNNER_OS:-}" = "Windows" ] && command -v cygpath >/dev/null 2>&1; then
  CACHE_BASE="$(cygpath -u "$CACHE_BASE")"
fi
mkdir -p "$CACHE_BASE"
ARCHIVE="$CACHE_BASE/${OHOS_SYSROOT}.tar.gz"
if [ ! -f "$ARCHIVE" ]; then curl -fsSL -o "$ARCHIVE" "$OHOS_SYSROOT_URL"; fi
if [ ! -d "$CACHE_BASE/${OHOS_SYSROOT}" ]; then tar -xzf "$ARCHIVE" -C "$CACHE_BASE"; fi
SYSROOT="$CACHE_BASE/${OHOS_SYSROOT}"
if [ ! -d "$SYSROOT" ]; then
  echo "Missing sysroot $SYSROOT"
  exit 1
fi

mkdir -p src
cat >src/test.c <<EOF
#include <stdio.h>
int main(void) {
  printf("ok_ohos_c_${SUF}\\n");
  return 0;
}
EOF
cat >src/test.cpp <<EOF
#include <iostream>
int main() {
  std::cout << "ok_ohos_cpp_${SUF}\\n";
  return 0;
}
EOF

BIN="$ROOT/bin"
[ -d "$BIN" ] || {
  echo "No $ROOT/bin"
  exit 1
}

OHOS_CC=""
for cand in \
  "$BIN/aarch64-unknown-linux-ohos-clang" "$BIN/aarch64-unknown-linux-ohos-clang.exe" \
  "$BIN/aarch64-linux-ohos-clang" "$BIN/aarch64-linux-ohos-clang.exe"; do
  if [ -x "$cand" ] || [ -f "$cand" ]; then OHOS_CC="$cand"; break; fi
done
[ -n "$OHOS_CC" ] || {
  echo "No aarch64 OHOS clang in $BIN"
  ls -la "$BIN"
  exit 1
}

OHOS_CXX=""
for cand in \
  "$BIN/aarch64-unknown-linux-ohos-clang++" "$BIN/aarch64-unknown-linux-ohos-clang++.exe" \
  "$BIN/aarch64-linux-ohos-clang++" "$BIN/aarch64-linux-ohos-clang++.exe"; do
  if [ -x "$cand" ] || [ -f "$cand" ]; then OHOS_CXX="$cand"; break; fi
done
[ -n "$OHOS_CXX" ] || {
  echo "No aarch64 OHOS clang++ in $BIN"
  exit 1
}
chmod +x "$OHOS_CC" "$OHOS_CXX" 2>/dev/null || true

OHOS_FLAGS=(--sysroot="$SYSROOT")
[ -d "$SYSROOT/usr/include" ] && OHOS_FLAGS+=(-I"$SYSROOT/usr/include")
[ -d "$SYSROOT/usr/lib" ] && OHOS_FLAGS+=(-L"$SYSROOT/usr/lib")
for triple in aarch64-unknown-linux-ohos aarch64-linux-ohos; do
  [ -d "$SYSROOT/usr/include/$triple" ] && OHOS_FLAGS+=(-I"$SYSROOT/usr/include/$triple")
  [ -d "$SYSROOT/usr/lib/$triple" ] && OHOS_FLAGS+=(-L"$SYSROOT/usr/lib/$triple")
done

set +e
CLOG="$("$OHOS_CC" "${OHOS_FLAGS[@]}" -O2 -o src/hello_ohos_c src/test.c 2>&1)"
CRC=$?
set -e
if [ "$CRC" -ne 0 ]; then echo "C compile failed: $CLOG"; exit 1; fi

set +e
CXXLOG="$("$OHOS_CXX" "${OHOS_FLAGS[@]}" -std=c++17 -O2 -o src/hello_ohos_cpp src/test.cpp 2>&1)"
CXXRC=$?
set -e
if [ "$CXXRC" -ne 0 ]; then echo "C++ compile failed: $CXXLOG"; exit 1; fi

if [ "$PLATFORM" = "linux-x64" ] || [ "$PLATFORM" = "windows-x64" ]; then
  ls -la src/hello_ohos_c src/hello_ohos_cpp 2>/dev/null || ls -la src/hello_ohos_c.exe src/hello_ohos_cpp.exe 2>/dev/null || ls -la src
elif command -v file >/dev/null 2>&1; then
  file src/hello_ohos_c src/hello_ohos_cpp 2>/dev/null || true
else
  ls -la src/hello_ohos_c src/hello_ohos_cpp 2>/dev/null || ls -la src
fi

NAME="test-binaries-ohos-${SUF}-${CI_PIPELINE_ID}.tar.gz"
members=()
for f in hello_ohos_c hello_ohos_cpp hello_ohos_c.exe hello_ohos_cpp.exe; do
  [ -f "src/$f" ] && members+=("$f")
done
[ "${#members[@]}" -ge 2 ] || {
  echo "Expected C and C++ binaries in src/"
  ls -la src
  exit 1
}
tar -czf "$W/$NAME" -C src "${members[@]}"

export INPUT_PATH="$W/$NAME"
export INPUT_SERVER_URL="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
AP="${ARTIFACT_LOCAL_PATH:-$HOME/runner/artifact}"
export INPUT_CACHE_DIR="${AP/#\~/$HOME}"
KND="$(mktemp)"
export KNACTION_DOTENV_FILE="$KND"
# shellcheck source=/dev/null
source "$CI_PROJECT_DIR/.github/actions/upload-artifact-local/upload.sh"
rm -f "$KND"

echo "Uploaded $NAME"
