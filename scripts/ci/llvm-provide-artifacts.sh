#!/usr/bin/env bash
set -euo pipefail
: "${CI_PROJECT_DIR:?}"
source "$CI_PROJECT_DIR/scripts/ci/logging.sh"

OUT="$CI_PROJECT_DIR/llvm-artifacts.env"

source "$CI_PROJECT_DIR/cross-copy.env"
{
  echo "archive_linux=$archive_linux"
  echo "archive_mac_arm64=$archive_mac_arm64"
  echo "archive_mac_x64=$archive_mac_x64"
  echo "archive_windows=$archive_windows"
} >"$OUT"
log_info "Wrote llvm-artifacts.env from cross-copy.env"

cat "$OUT"
