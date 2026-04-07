#!/usr/bin/env bash
# OpenHarmony LLVM prebuilts bootstrap for Windows (Git Bash).
# Upstream env_prepare.sh only handles Linux/Darwin (uname); Git Bash reports MINGW64_NT-*.
set -euo pipefail

host_platform=windows
host_cpu=x86_64
download_url=https://mirrors.huaweicloud.com
code_dir=$(pwd)
bin_dir=${code_dir}/download_packages
mkdir -p "${bin_dir}"

if command -v wget >/dev/null 2>&1; then
  download_one() { wget -t3 -T10 -O "$1" "$2"; }
else
  download_one() { curl -fSL --retry 3 --connect-timeout 10 -o "$1" "$2"; }
fi

function download_and_archive() {
  archive_dir=$1
  download_source_url=$2
  bin_file=$(basename "${download_source_url}")
  download_one "${bin_dir}/${bin_file}" "${download_source_url}"
  if [ ! -d "${code_dir}/${archive_dir}" ]; then
    mkdir -p "${code_dir}/${archive_dir}"
  fi
  if [ "X${bin_file:0-3}" = "Xzip" ]; then
    unzip -o "${bin_dir}/${bin_file}" -d "${code_dir}/${archive_dir}/"
  elif [ "X${bin_file:0-6}" = "Xtar.gz" ]; then
    tar -xvzf "${bin_dir}/${bin_file}" -C "${code_dir}/${archive_dir}"
  else
    tar -xvf "${bin_dir}/${bin_file}" -C "${code_dir}/${archive_dir}"
  fi
}

copy_config="""
prebuilts/cmake,cmake-windows-x86
prebuilts/clang/ohos/windows-x86_64,windows/clang_windows-x86_64
prebuilts/python3,python-mingw-x86
prebuilts/build-tools/windows-x86/bin,ninja-windows-x86
prebuilts/clang/ohos/windows-x86_64,libcxx-ndk_windows
"""

for i in $(echo "${copy_config}"); do
  unzip_dir=$(echo "$i" | awk -F ',' '{print $1}')
  keyword=$(echo "$i" | awk -F ',' '{print $2}')
  url_part=$(cat ./build/prebuilts_config.json | sort | uniq | grep "$keyword" | grep -oE '"/[^"]+"' | sed 's/^"//;s/"$//' | head -1)
  if [ -n "$url_part" ]; then
    full_url="${download_url}${url_part}"
  else
    echo "URL not found for keyword: $keyword"
    exit 1
  fi
  download_and_archive "${unzip_dir}" "${full_url}"
done

windows_clang_filename=$(cat ./build/prebuilts_config.json | sort | uniq | grep "windows/clang_windows-x86_64" | grep -oE '"/[^"]+"' | sed 's/^"//;s/"$//' | head -1)
CLANG_WINDOWS_BUILD=$(basename "$windows_clang_filename" .tar.gz)

if [ -d "${code_dir}/prebuilts/clang/ohos/windows-x86_64/${CLANG_WINDOWS_BUILD}" ]; then
  SET_CLANG_VERSION='15.0.4'
  mv "${code_dir}/prebuilts/clang/ohos/windows-x86_64/${CLANG_WINDOWS_BUILD}" "${code_dir}/prebuilts/clang/ohos/windows-x86_64/clang-${SET_CLANG_VERSION}"
  ln -sfn "${code_dir}/prebuilts/clang/ohos/windows-x86_64/clang-${SET_CLANG_VERSION}" "${code_dir}/prebuilts/clang/ohos/windows-x86_64/llvm"
fi

BASE_CLANG_DIR="${code_dir}/prebuilts/clang/ohos/${host_platform}-${host_cpu}"
CLANG_FOUND_VERSION=$(cd "${BASE_CLANG_DIR}" && basename "$(ls -d clang*/ | head -1)" | sed 's/clang-//')
if [ -z "${CLANG_FOUND_VERSION}" ]; then
  echo "env_prepare (windows): could not detect clang version" >&2
  exit 1
fi

VER_PY="${code_dir}/toolchain/llvm-project/llvm-build/prebuilts_clang_version.py"
# Git on Windows may checkout prebuilts_clang_version.py with CRLF; pipe+diff sees a false mismatch vs LF-only echo.
want="prebuilts_clang_version='${CLANG_FOUND_VERSION}'"
got=$(tr -d '\r\n' < "${VER_PY}")
if [ "${got}" != "${want}" ]; then
  echo "Clang versions mismatch (expected '${want}', got '${got}')" >&2
  exit 1
fi
exit 0
