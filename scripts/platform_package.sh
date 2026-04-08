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
# Merge Linux x86_64 OHOS bits into Darwin and Windows clang installs.
# Expects *.tar.gz blobs in cwd (staging). CLANG_RESOURCE_VERSION must match lib/clang/<ver> (e.g. 19).

set -euo pipefail

: "${CLANG_RESOURCE_VERSION:=19}"

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
llvm_list=($clang_linux_x86_64 $clang_darwin_arm64 $clang_darwin_x86_64 $clang_windows_x86_64 $libcxx_ndk_linux_x86_64 $libcxx_ndk_darwin_x86_64 $libcxx_ndk_darwin_arm64 $libcxx_ndk_ohos_arm64 $libcxx_ndk_linux_aarch64 $libcxx_ndk_windows_x86_64)

V="${CLANG_RESOURCE_VERSION}"

# decompress file and rename
tar -xf ${clang_linux_x86_64_tar}
mv clang-dev ${clang_linux_x86_64}
tar -xf ${clang_darwin_arm64_tar}
mv clang-dev ${clang_darwin_arm64}
tar -xf ${clang_darwin_x86_64_tar}
mv clang-dev ${clang_darwin_x86_64}
tar -xf ${clang_windows_x86_64_tar}
mv clang-dev ${clang_windows_x86_64}
tar -xf ${libcxx_ndk_linux_x86_64_tar}
mv libcxx-ndk ${libcxx_ndk_linux_x86_64}
tar -xf ${libcxx_ndk_darwin_x86_64_tar}
mv libcxx-ndk ${libcxx_ndk_darwin_x86_64}
tar -xf ${libcxx_ndk_darwin_arm64_tar}
mv libcxx-ndk ${libcxx_ndk_darwin_arm64}
cp -a ${libcxx_ndk_linux_x86_64} ${libcxx_ndk_ohos_arm64}
tar -xf ${libcxx_ndk_linux_aarch64_tar}
mv libcxx-ndk ${libcxx_ndk_linux_aarch64}
cp -a ${libcxx_ndk_linux_x86_64} ${libcxx_ndk_windows_x86_64}

#clang-dev-darwin-arm64
cp -rf ${clang_linux_x86_64}/lib/aarch64-linux-ohos ${clang_darwin_arm64}/lib
cp -rf ${clang_linux_x86_64}/lib/arm-liteos-ohos ${clang_darwin_arm64}/lib
cp -rf ${clang_linux_x86_64}/include/libcxx-ohos ${clang_darwin_arm64}/include
cp -rf ${clang_linux_x86_64}/lib/arm-linux-ohos ${clang_darwin_arm64}/lib
if [ -d "${clang_linux_x86_64}/lib/loongarch64-linux-ohos" ]; then
	cp -rf ${clang_linux_x86_64}/lib/loongarch64-linux-ohos ${clang_darwin_arm64}/lib
fi
cp -rf ${clang_linux_x86_64}/lib/x86_64-linux-ohos ${clang_darwin_arm64}/lib
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/bin ${clang_darwin_arm64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/profile ${clang_darwin_arm64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/fuzzer ${clang_darwin_arm64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/share ${clang_darwin_arm64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/sanitizer ${clang_darwin_arm64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/lib ${clang_darwin_arm64}/lib/clang/${V}

#clang-dev-darwin-x86_64
cp -rf ${clang_linux_x86_64}/lib/aarch64-linux-ohos ${clang_darwin_x86_64}/lib
cp -rf ${clang_linux_x86_64}/lib/arm-liteos-ohos ${clang_darwin_x86_64}/lib
cp -rf ${clang_linux_x86_64}/lib/arm-linux-ohos ${clang_darwin_x86_64}/lib
cp -rf ${clang_linux_x86_64}/lib/x86_64-linux-ohos ${clang_darwin_x86_64}/lib
if [ -d "${clang_linux_x86_64}/lib/loongarch64-linux-ohos" ]; then
	cp -rf ${clang_linux_x86_64}/lib/loongarch64-linux-ohos ${clang_darwin_x86_64}/lib
fi
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/bin ${clang_darwin_x86_64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/share ${clang_darwin_x86_64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/lib ${clang_darwin_x86_64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/profile ${clang_darwin_x86_64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/fuzzer ${clang_darwin_x86_64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/sanitizer ${clang_darwin_x86_64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/include/libcxx-ohos ${clang_darwin_x86_64}/include

#clang-dev-windows-x86_64 (same OHOS payload merge as Darwin x86_64 host)
cp -rf ${clang_linux_x86_64}/lib/aarch64-linux-ohos ${clang_windows_x86_64}/lib
cp -rf ${clang_linux_x86_64}/lib/arm-liteos-ohos ${clang_windows_x86_64}/lib
cp -rf ${clang_linux_x86_64}/lib/arm-linux-ohos ${clang_windows_x86_64}/lib
cp -rf ${clang_linux_x86_64}/lib/x86_64-linux-ohos ${clang_windows_x86_64}/lib
if [ -d "${clang_linux_x86_64}/lib/loongarch64-linux-ohos" ]; then
	cp -rf ${clang_linux_x86_64}/lib/loongarch64-linux-ohos ${clang_windows_x86_64}/lib
fi
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/bin ${clang_windows_x86_64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/share ${clang_windows_x86_64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/lib ${clang_windows_x86_64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/profile ${clang_windows_x86_64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/fuzzer ${clang_windows_x86_64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/sanitizer ${clang_windows_x86_64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/include/libcxx-ohos ${clang_windows_x86_64}/include

#archive
mkdir target_location
function package_llvm(){
for i in ${llvm_list[@]}
do
	if command -v pigz >/dev/null 2>&1; then
		tar -cf - "${i}" | pigz -9 > "target_location/${i}.tar.gz"
	else
		tar zcf "target_location/${i}.tar.gz" "${i}"
	fi
	sha256sum target_location/${i}.tar.gz |awk '{print $1}' > target_location/${i}.tar.gz.sha256
done
}

package_llvm

# Optional cross-copy final packaging mode used by build-llvm.yml.
# Expects:
# - LLVM_MAJOR_FOR_PACKAGE, LLVM_ESSENTIALS_ID, GITHUB_RUN_ID
# - GITHUB_OUTPUT (optional; archives are still created without it)
# Produces archives in cwd and (if GITHUB_OUTPUT exists) exports:
#   archive_linux, archive_mac_arm64, archive_mac_x64, archive_windows
if [ "${RUN_FINAL_PACKAGE:-0}" = "1" ]; then
  overlay_dir() {
    local src="$1"
    local target="$2"
    [ -d "$src" ] || { echo "::error::Missing overlay dir $src"; exit 1; }
    [ -d "$target" ] || { echo "::error::Missing target dir $target"; exit 1; }
    cp -a "$src"/. "$target"/
  }

  pack_host_tree() {
    local source_dir="$1"
    local stem="$2"
    local ext="$3"
    local archive
    rm -rf "$stem"
    mkdir -p "$stem"
    cp -a "$source_dir"/. "$stem/"
    [ -d "$stem/bin" ] || { echo "::error::Expected $stem/bin after flattening from $source_dir"; ls -la "$stem"; exit 1; }
    if [ "$ext" = "zip" ]; then
      archive="${stem}-run${GITHUB_RUN_ID}.zip"
      zip -qry "$archive" "$stem"
      first="$(unzip -Z1 "$archive" | head -1)"
      [ "$first" = "${stem}/" ] || { echo "::error::Expected first member ${stem}/, got $first"; exit 1; }
    else
      archive="${stem}-run${GITHUB_RUN_ID}.tar.gz"
      GZIP=-9 tar -czf "$archive" "$stem"
      first="$(tar -tzf "$archive" | head -1)"
      [ "$first" = "${stem}/" ] || { echo "::error::Expected first member ${stem}/, got $first"; exit 1; }
    fi
    printf '%s' "$archive"
  }

  [ -n "${LLVM_MAJOR_FOR_PACKAGE:-}" ] || { echo "::error::LLVM_MAJOR_FOR_PACKAGE is required when RUN_FINAL_PACKAGE=1"; exit 1; }
  [ -n "${LLVM_ESSENTIALS_ID:-}" ] || { echo "::error::LLVM_ESSENTIALS_ID is required when RUN_FINAL_PACKAGE=1"; exit 1; }
  [ -n "${GITHUB_RUN_ID:-}" ] || { echo "::error::GITHUB_RUN_ID is required when RUN_FINAL_PACKAGE=1"; exit 1; }

  if [ ! -d "$clang_linux_x86_64" ]; then
    echo "::error::Missing linux clang tree $clang_linux_x86_64"
    exit 1
  fi

  # Overlay libcxx-ndk payloads directly from already-extracted dirs.
  overlay_dir "$libcxx_ndk_darwin_arm64" "$clang_darwin_arm64"
  overlay_dir "$libcxx_ndk_darwin_x86_64" "$clang_darwin_x86_64"
  overlay_dir "$libcxx_ndk_linux_aarch64" "$clang_linux_x86_64"
  overlay_dir "$libcxx_ndk_linux_x86_64" "$clang_linux_x86_64"
  overlay_dir "$libcxx_ndk_windows_x86_64" "$clang_windows_x86_64"

  STEM_LINUX="llvm-${LLVM_MAJOR_FOR_PACKAGE}-x86_64-linux-dev-${LLVM_ESSENTIALS_ID}"
  STEM_MAC_ARM64="llvm-${LLVM_MAJOR_FOR_PACKAGE}-aarch64-macos-dev-${LLVM_ESSENTIALS_ID}"
  STEM_MAC_X64="llvm-${LLVM_MAJOR_FOR_PACKAGE}-x86_64-macos-dev-${LLVM_ESSENTIALS_ID}"
  STEM_WINDOWS="llvm-${LLVM_MAJOR_FOR_PACKAGE}-x86_64-windows-dev-${LLVM_ESSENTIALS_ID}"

  ARCHIVE_LINUX="$(pack_host_tree "$clang_linux_x86_64" "$STEM_LINUX" "tar.gz")"
  ARCHIVE_MAC_ARM64="$(pack_host_tree "$clang_darwin_arm64" "$STEM_MAC_ARM64" "tar.gz")"
  ARCHIVE_MAC_X64="$(pack_host_tree "$clang_darwin_x86_64" "$STEM_MAC_X64" "tar.gz")"
  ARCHIVE_WINDOWS="$(pack_host_tree "$clang_windows_x86_64" "$STEM_WINDOWS" "zip")"

  {
    echo "Packed $ARCHIVE_LINUX (top-level dir $STEM_LINUX)"
    echo "Packed $ARCHIVE_MAC_ARM64 (top-level dir $STEM_MAC_ARM64)"
    echo "Packed $ARCHIVE_MAC_X64 (top-level dir $STEM_MAC_X64)"
    echo "Packed $ARCHIVE_WINDOWS (top-level dir $STEM_WINDOWS)"
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "archive_linux=$ARCHIVE_LINUX"
      echo "archive_mac_arm64=$ARCHIVE_MAC_ARM64"
      echo "archive_mac_x64=$ARCHIVE_MAC_X64"
      echo "archive_windows=$ARCHIVE_WINDOWS"
    } >> "$GITHUB_OUTPUT"
  fi
fi
