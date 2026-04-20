#!/usr/bin/env bash
set -euo pipefail
: "${CI_PROJECT_DIR:?}"
source "$CI_PROJECT_DIR/scripts/ci/logging.sh"

SKIP_ALL="true"
for platform in linux macos-arm64 macos-x64; do
  env_file="$CI_PROJECT_DIR/llvm-build-${platform}.env"
  [ -f "$env_file" ] || continue
  grep -q "SKIP_BUILD=false" "$env_file" && SKIP_ALL="false" && break
done

OUT="$CI_PROJECT_DIR/llvm-artifacts.env"

if [ "$SKIP_ALL" = "true" ]; then
  source "$CI_PROJECT_DIR/llvm-build-linux.env"
  
  LLVM_MAJOR="${LLVM_MAJOR_FOR_PACKAGE:-19}"
  OH_VER="${OH_VERSION:-1}"
  ID="_llvm-${LLVM_SHA_SHORT}_act-${ACT_SHA_SHORT}_manifest-${MANIFEST_MD5}"
  
  {
    echo "archive_linux=llvm-${LLVM_MAJOR}-x86_64-linux-dev-oh-${OH_VER}${ID}.tar.gz"
    echo "archive_mac_arm64=llvm-${LLVM_MAJOR}-aarch64-macos-dev-oh-${OH_VER}${ID}.tar.gz"
    echo "archive_mac_x64=llvm-${LLVM_MAJOR}-x86_64-macos-dev-oh-${OH_VER}${ID}.tar.gz"
    echo "archive_windows=llvm-${LLVM_MAJOR}-x86_64-windows-dev-oh-${OH_VER}${ID}.zip"
    echo "SKIP_BUILD_ALL=true"
  } > "$OUT"
  log_info "All builds skipped; computed final artifact names"
else
  source "$CI_PROJECT_DIR/cross-copy.env"
  {
    echo "archive_linux=$archive_linux"
    echo "archive_mac_arm64=$archive_mac_arm64"
    echo "archive_mac_x64=$archive_mac_x64"
    echo "archive_windows=$archive_windows"
    echo "SKIP_BUILD_ALL=false"
  } > "$OUT"
  log_info "Builds ran; using cross-copy artifact names"
fi

cat "$OUT"