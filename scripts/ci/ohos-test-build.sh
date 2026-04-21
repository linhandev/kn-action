#!/usr/bin/env bash
# GHA ohos-test-build matrix leg. Requires dotenv from llvm:cross-copy (archive_*).
set -euo pipefail

PLATFORM="${1:?usage: ohos-test-build.sh linux-x64|windows-x64|macos-arm64|macos-x64}"
: "${CI_PROJECT_DIR:?}"
: "${CI_PIPELINE_ID:?}"
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCRIPT_DIR/logging.sh"

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

_SERVER="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
log_info "downloading final package: $_SERVER/artifacts/$n"
curl -fsSL -o "$W/dl/$n" "$_SERVER/artifacts/$n"

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

# shellcheck source=junit-helpers.sh
source "$_SCRIPT_DIR/junit-helpers.sh"

JUNIT_FILE="${CI_PROJECT_DIR}/.junit/ohos-test-build-${PLATFORM}.xml"
CLASS="ohos-cross-compile.${PLATFORM}"

compile_test() {
  local name="$1" compiler="$2" src="$3" out="$4"; shift 4
  local t0 t1 dur log rc
  t0="$(junit_ts)"
  set +e; log="$("$compiler" "$@" -o "$out" "$src" 2>&1)"; rc=$?; set -e
  t1="$(junit_ts)"
  dur="$(junit_duration "$t0" "$t1")"
  if [ "$rc" -eq 0 ]; then
    junit_pass "$CLASS" "$name" "$dur"
    echo "$name: OK"
  else
    junit_fail "$CLASS" "$name" "$dur" "exit code $rc" "$log"
    echo "$name: FAILED (rc=$rc)"
    echo "$log"
  fi
}

compile_test "c-compile" "$OHOS_CC" src/test.c src/hello_ohos_c "${OHOS_FLAGS[@]}" -O2
compile_test "cpp-compile" "$OHOS_CXX" src/test.cpp src/hello_ohos_cpp "${OHOS_FLAGS[@]}" -std=c++17 -O2

junit_write "ohos-cross-compile-${PLATFORM}" "$JUNIT_FILE" || exit 1

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
# Git Bash GNU tar treats "C:/..." archive paths as host:file remote specs; write via cwd + basename.
( cd "$W" && tar -czf "$NAME" -C src "${members[@]}" )

TEST_OUT="${CI_PROJECT_DIR}/.ohos-test-binaries"
mkdir -p "$TEST_OUT"
cp "$W/$NAME" "$TEST_OUT/"
echo "Saved test binary: $TEST_OUT/$NAME"
