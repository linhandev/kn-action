#!/usr/bin/env bash
# Same as toolchain/llvm-project/llvm-build/build.sh but uses MingW Python from prebuilts (not linux-x86 + /usr/bin/python3).
set -euo pipefail

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

build_llvm() {
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
