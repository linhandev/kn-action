#!/bin/bash
# Copyright (c) 2024 Huawei Device Co., Ltd.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Merge Linux x86_64 OHOS bits into Darwin and Windows clang installs,
# overlay libcxx-ndk, and produce distributable archives.
#
# Expects *.tar.gz blobs in cwd (staging).
# CLANG_RESOURCE_VERSION must match lib/clang/<ver> (e.g. 19).
# LLVM_MAJOR_FOR_PACKAGE and CLANG_RESOURCE_VERSION default here (override only for local/debug).
# Produces per-host archives named: llvm-<major>-<arch>-<os>-dev-oh-<OH_VERSION>.zip or .tar.gz

set -euo pipefail

: "${CLANG_RESOURCE_VERSION:=19}"
: "${LLVM_MAJOR_FOR_PACKAGE:=19}"
: "${OH_VERSION:=1}"

commit_id=""
date="$(date '+%Y-%m-%dT%H:%M:%S')"

clang_linux_x86_64_tar="clang-dev-linux-x86_64.tar.gz"
clang_darwin_arm64_tar="clang-dev-darwin-arm64.tar.gz"
clang_darwin_x86_64_tar="clang-dev-darwin-x86_64.tar.gz"
clang_windows_x86_64_tar="clang-dev-windows-x86_64.tar.gz"
libcxx_ndk_linux_x86_64_tar="libcxx-ndk-dev-linux-x86_64.tar.gz"
libcxx_ndk_darwin_x86_64_tar="libcxx-ndk-dev-darwin-x86_64.tar.gz"
libcxx_ndk_darwin_arm64_tar="libcxx-ndk-dev-darwin-arm64.tar.gz"
libcxx_ndk_linux_aarch64_tar="libcxx-ndk-dev-linux-aarch64.tar.gz"

clang_linux_x86_64="clang_linux-x86_64-${commit_id}-${date}"
clang_darwin_arm64="clang_darwin-arm64-${commit_id}-${date}"
clang_darwin_x86_64="clang_darwin-x86_64-${commit_id}-${date}"
clang_windows_x86_64="clang_windows-x86_64-${commit_id}-${date}"
libcxx_ndk_linux_x86_64="libcxx-ndk_linux-x86_64-${commit_id}-${date}"
libcxx_ndk_darwin_x86_64="libcxx-ndk_darwin-x86_64-${commit_id}-${date}"
libcxx_ndk_darwin_arm64="libcxx-ndk_darwin-arm64-${commit_id}-${date}"
libcxx_ndk_ohos_arm64="libcxx_ndk_ohos-arm64-${commit_id}-${date}"
libcxx_ndk_linux_aarch64="libcxx-ndk_linux-aarch64-${commit_id}-${date}"
libcxx_ndk_windows_x86_64="libcxx-ndk_windows-x86_64-${commit_id}-${date}"

V="${CLANG_RESOURCE_VERSION}"

_extract() {
  if command -v pigz >/dev/null 2>&1; then
    pigz -dc "$1" | tar -xf -
  else
    tar -xzf "$1"
  fi
}

# --- 1. Extract all tarballs ---

_extract ${clang_linux_x86_64_tar}
mv clang-dev ${clang_linux_x86_64}
_extract ${clang_darwin_arm64_tar}
mv clang-dev ${clang_darwin_arm64}
_extract ${clang_darwin_x86_64_tar}
mv clang-dev ${clang_darwin_x86_64}
_extract ${clang_windows_x86_64_tar}
mv clang-dev ${clang_windows_x86_64}
_extract ${libcxx_ndk_linux_x86_64_tar}
mv libcxx-ndk ${libcxx_ndk_linux_x86_64}
_extract ${libcxx_ndk_darwin_x86_64_tar}
mv libcxx-ndk ${libcxx_ndk_darwin_x86_64}
_extract ${libcxx_ndk_darwin_arm64_tar}
mv libcxx-ndk ${libcxx_ndk_darwin_arm64}
cp -a ${libcxx_ndk_linux_x86_64} ${libcxx_ndk_ohos_arm64}
_extract ${libcxx_ndk_linux_aarch64_tar}
mv libcxx-ndk ${libcxx_ndk_linux_aarch64}
cp -a ${libcxx_ndk_linux_x86_64} ${libcxx_ndk_windows_x86_64}

# --- 2. Merge Linux-built OHOS cross-compiled libs into each host tree ---

merge_ohos_into_host() {
  local dst="$1"
  cp -rf ${clang_linux_x86_64}/lib/aarch64-linux-ohos "$dst"/lib
  cp -rf ${clang_linux_x86_64}/lib/arm-liteos-ohos "$dst"/lib
  cp -rf ${clang_linux_x86_64}/lib/arm-linux-ohos "$dst"/lib
  cp -rf ${clang_linux_x86_64}/lib/x86_64-linux-ohos "$dst"/lib
  if [ -d "${clang_linux_x86_64}/lib/loongarch64-linux-ohos" ]; then
    cp -rf ${clang_linux_x86_64}/lib/loongarch64-linux-ohos "$dst"/lib
  fi
  cp -rf ${clang_linux_x86_64}/lib/clang/${V}/bin "$dst"/lib/clang/${V}
  cp -rf ${clang_linux_x86_64}/lib/clang/${V}/share "$dst"/lib/clang/${V}
  cp -rf ${clang_linux_x86_64}/lib/clang/${V}/lib "$dst"/lib/clang/${V}
  cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/profile "$dst"/lib/clang/${V}/include
  cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/fuzzer "$dst"/lib/clang/${V}/include
  cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/sanitizer "$dst"/lib/clang/${V}/include
  cp -rf ${clang_linux_x86_64}/include/libcxx-ohos "$dst"/include
}

merge_ohos_into_host "$clang_darwin_arm64"
merge_ohos_into_host "$clang_darwin_x86_64"
merge_ohos_into_host "$clang_windows_x86_64"

# --- 3. Overlay libcxx-ndk and fix libc++.so linker scripts ---
# The clang-dev build ships a real libc++.so with __h ABI namespace, but
# libcxx-ndk headers and libc++_shared.so use __n1.  The overlay adds the
# correct libraries (libc++_shared.so, libc++.a) but does not replace the
# stale libc++.so (different filename).  We replace it with a linker script
# INPUT(-lc++_shared) matching the DevEco SDK layout.

overlay_dir() {
  local src="$1" target="$2"
  [ -d "$src" ] || { echo "::error::Missing overlay dir $src"; exit 1; }
  [ -d "$target" ] || { echo "::error::Missing target dir $target"; exit 1; }
  cp -a "$src"/. "$target"/
}

overlay_dir "$libcxx_ndk_darwin_arm64" "$clang_darwin_arm64"
overlay_dir "$libcxx_ndk_darwin_x86_64" "$clang_darwin_x86_64"
overlay_dir "$libcxx_ndk_linux_aarch64" "$clang_linux_x86_64"
overlay_dir "$libcxx_ndk_linux_x86_64" "$clang_linux_x86_64"
overlay_dir "$libcxx_ndk_windows_x86_64" "$clang_windows_x86_64"

fixup_libcxx_linker_script() {
  local tree="$1"
  for ohos_lib in "$tree"/lib/*-ohos; do
    [ -d "$ohos_lib" ] || continue
    if [ -f "$ohos_lib/libc++_shared.so" ] && [ -f "$ohos_lib/libc++.so" ]; then
      rm -f "$ohos_lib/libc++.so"
      printf 'INPUT(-lc++_shared)\n' > "$ohos_lib/libc++.so"
    fi
  done
}
fixup_libcxx_linker_script "$clang_linux_x86_64"
fixup_libcxx_linker_script "$clang_darwin_arm64"
fixup_libcxx_linker_script "$clang_darwin_x86_64"
fixup_libcxx_linker_script "$clang_windows_x86_64"

# --- 4. Archive (versioned per-host artifacts) ---

pack_host_tree() {
  local source_dir="$1" stem="$2" ext="$3"
  local archive
  [ -d "$source_dir/bin" ] || { echo "::error::Expected $source_dir/bin"; ls -la "$source_dir"; exit 1; }
  mv "$source_dir" "$stem"
  _rid="${CI_PIPELINE_ID:-${KNACTION_PIPELINE_ID:-}}"
  if [ "$ext" = "zip" ]; then
    archive="${stem}-run${_rid}.${ext}"
    zip -qry "$archive" "$stem"
    first="$(unzip -Z1 "$archive" | head -1)"
    [ "$first" = "${stem}/" ] || { echo "::error::Expected first member ${stem}/, got $first"; exit 1; }
  else
    archive="${stem}-run${_rid}.${ext}"
    if command -v pigz >/dev/null 2>&1; then
      tar -cf - "$stem" | pigz -9 > "$archive"
    else
      GZIP=-9 tar -czf "$archive" "$stem"
    fi
    first="$(tar -tzf "$archive" | head -1)"
    [ "$first" = "${stem}/" ] || { echo "::error::Expected first member ${stem}/, got $first"; exit 1; }
  fi
  printf '%s' "$archive"
}

[ -n "${CI_PIPELINE_ID:-${KNACTION_PIPELINE_ID:-}}" ] || { echo "::error::CI_PIPELINE_ID or KNACTION_PIPELINE_ID is required"; exit 1; }
[ -d "$clang_linux_x86_64" ] || { echo "::error::Missing linux clang tree $clang_linux_x86_64"; exit 1; }

STEM_LINUX="llvm-${LLVM_MAJOR_FOR_PACKAGE}-x86_64-linux-dev-oh-${OH_VERSION}"
STEM_MAC_ARM64="llvm-${LLVM_MAJOR_FOR_PACKAGE}-aarch64-macos-dev-oh-${OH_VERSION}"
STEM_MAC_X64="llvm-${LLVM_MAJOR_FOR_PACKAGE}-x86_64-macos-dev-oh-${OH_VERSION}"
STEM_WINDOWS="llvm-${LLVM_MAJOR_FOR_PACKAGE}-x86_64-windows-dev-oh-${OH_VERSION}"

ARCHIVE_LINUX="$(pack_host_tree "$clang_linux_x86_64" "$STEM_LINUX" "tar.gz")"
ARCHIVE_MAC_ARM64="$(pack_host_tree "$clang_darwin_arm64" "$STEM_MAC_ARM64" "tar.gz")"
ARCHIVE_MAC_X64="$(pack_host_tree "$clang_darwin_x86_64" "$STEM_MAC_X64" "tar.gz")"
ARCHIVE_WINDOWS="$(pack_host_tree "$clang_windows_x86_64" "$STEM_WINDOWS" "zip")"

{
  echo "Packed $ARCHIVE_LINUX (top-level dir $STEM_LINUX)"
  echo "Packed $ARCHIVE_MAC_ARM64 (top-level dir $STEM_MAC_ARM64)"
  echo "Packed $ARCHIVE_MAC_X64 (top-level dir $STEM_MAC_X64)"
  echo "Packed $ARCHIVE_WINDOWS (top-level dir $STEM_WINDOWS)"
} >> "${KNACTION_STEP_SUMMARY:-/dev/null}"

if [ -n "${KNACTION_DOTENV_FILE:-}" ]; then
  {
    echo "archive_linux=$ARCHIVE_LINUX"
    echo "archive_mac_arm64=$ARCHIVE_MAC_ARM64"
    echo "archive_mac_x64=$ARCHIVE_MAC_X64"
    echo "archive_windows=$ARCHIVE_WINDOWS"
  } >> "$KNACTION_DOTENV_FILE"
fi
