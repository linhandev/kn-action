#!/usr/bin/env bash
# Same as toolchain/llvm-project/llvm-build/build.sh but uses MingW Python from prebuilts (not linux-x86 + /usr/bin/python3).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR=$(pwd)
LLVM_DIR=${WORK_DIR}/toolchain/llvm-project

PATCH_MAP=(
  "${WORK_DIR}/toolchain/llvm-project/llvm-build/0001-adapt-build-for-llvm19.patch:${WORK_DIR}/build"
  "${WORK_DIR}/toolchain/llvm-project/llvm-build/0001-adapt-musl-for-llvm19.patch:${WORK_DIR}/third_party/musl"
)

apply_patch() {
  local patch_file="$1"
  local target_dir="$2"
  if [ ! -f "$patch_file" ]; then
    echo "error: $patch_file not exit!!!!" >&2
    return 1
  fi
  if [ ! -d "$target_dir" ]; then
    echo "error: $target_dir not exit!!!" >&2
    return 1
  fi
  if (cd "$target_dir" && git apply --check "$patch_file" &>/dev/null); then
    echo "$patch_file can be applied  $target_dir"
    echo "begin apply patch"
    if (cd "$target_dir" && git am "$patch_file"); then
      echo "$patch_file apply success"
      return 0
    else
      echo "error: $patch_file apply failed" >&2
      return 1
    fi
  else
    echo "skip: $patch_file may have already been applied or there may be conflicts"
    return 1
  fi
}

# Upstream build.py only sets CMAKE_BIN_DIR / prebuilts paths for Linux and Darwin; Windows OH layout uses
# windows-x86 for cmake, ninja, and Python. Apply a small patch idempotently (marker comment in build.py).
apply_windows_build_py_patch() {
  local patch="${SCRIPT_DIR}/patches/ohos-llvm-build-py-windows-host.patch"
  local d="${WORK_DIR}/toolchain/llvm-project/llvm-build"
  if [ ! -f "$patch" ]; then
    echo "::error::missing patch: $patch" >&2
    exit 1
  fi
  if grep -q "kn-action: matches OH Windows prebuilts layout" "$d/build.py" 2>/dev/null; then
    return 0
  fi
  if (cd "$d" && git apply --check "$patch"); then
    (cd "$d" && git apply "$patch")
    echo "::notice::Applied kn-action Windows build.py host patch"
  else
    echo "::error::git apply failed: $patch (rebase patch against toolchain/llvm-project/llvm-build/build.py)" >&2
    exit 1
  fi
}

# OH build.py expects swig on PATH; self-hosted Windows runners often omit it.
ensure_swig_on_path() {
  if command -v swig >/dev/null 2>&1; then
    return 0
  fi
  local ver=4.2.1
  local base="${WORK_DIR}/prebuilts/swig-win"
  local root="${base}/swigwin-${ver}"
  if [ ! -f "${root}/swig.exe" ]; then
    mkdir -p "$base"
    local zip="${base}/swigwin-${ver}.zip"
    if [ ! -f "$zip" ]; then
      curl -fSL --retry 3 --connect-timeout 20 -o "$zip" \
        "https://downloads.sourceforge.net/project/swig/swigwin/swigwin-${ver}/swigwin-${ver}.zip"
    fi
    unzip -qo "$zip" -d "$base"
  fi
  export PATH="${root}:$PATH"
}

build_llvm() {
  apply_windows_build_py_patch
  ensure_swig_on_path
  shopt -s nullglob
  local pybins=( "${WORK_DIR}/prebuilts/python3"/windows-x86/*/bin )
  if [ "${#pybins[@]}" -eq 0 ]; then
    pybins=( "${WORK_DIR}/prebuilts/python3"/python-mingw-x86*/bin )
  fi
  if [ "${#pybins[@]}" -eq 0 ]; then
    echo "::error::No MingW Python under prebuilts/python3 (run env prepare first)"
    exit 1
  fi
  export PATH="${pybins[0]}:$PATH"
  rm -rf "${WORK_DIR}/out"
  python "${WORK_DIR}/toolchain/llvm-project/llvm-build/build.py" --no-build-riscv64 --no-build-loongarch64 --no-build-mipsel --no-build lldb-server --compression-format gz
}

main() {
  for entry in "${PATCH_MAP[@]}"; do
    IFS=':' read -r patch_file target_dir <<< "$entry"
    echo "------------------------------"
    apply_patch "$patch_file" "$target_dir" || true
  done
  build_llvm
}
main
