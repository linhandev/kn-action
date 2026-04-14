#!/usr/bin/env bash
# Emit llvm-artifact-refs.env (GitLab dotenv) matching GHA llvm-artifact-refs job.
# Two modes (see .github/workflows/build-llvm.yml resolve-packages-skip-build):
# - Build matrix ran: use .llvm-ci-meta/*.env from build job artifacts (consistent LLVM/ACT short SHAs).
# - Skip build / no meta: resolve latest outer tar per host via artifact server regex (independent SHAs OK).
set -euo pipefail
: "${CI_PROJECT_DIR:?}"

OUT="${CI_PROJECT_DIR}/llvm-artifact-refs.env"

_REF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=artifact-server-latest.sh
source "$_REF_DIR/artifact-server-latest.sh"

# Same patterns as GHA download-artifact-local (latest by mtime on server).
PAT_LINUX='llvm-packages-.*_Linux_X64\.tar$'
PAT_MAC_ARM='llvm-packages-.*_macOS_ARM64\.tar$'
PAT_MAC_X64='llvm-packages-.*_macOS_X64\.tar$'

resolve_latest_basename() {
  local pattern="$1"
  local server_url="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
  server_url="${server_url%/}"
  artifact_server_latest_basename "$server_url" "$pattern"
}

emit_from_meta() {
  local META="$1"
  shopt -s nullglob
  local files=("$META"/*.env)
  if [ "${#files[@]}" -eq 0 ]; then
    return 1
  fi

  local L="" A="" first=1
  for f in "${files[@]}"; do
    # shellcheck disable=SC1090
    source "$f"
    if [ "$first" = 1 ]; then
      L="${LLVM_SHA_SHORT:-}"
      A="${ACT_SHA_SHORT:-}"
      first=0
    else
      [ "${LLVM_SHA_SHORT:-}" = "$L" ] || {
        echo "LLVM_SHA_SHORT mismatch in $f"
        exit 1
      }
      [ "${ACT_SHA_SHORT:-}" = "$A" ] || {
        echo "ACT_SHA_SHORT mismatch in $f"
        exit 1
      }
    fi
  done

  if [ -z "$L" ] || [ -z "$A" ]; then
    echo "Empty LLVM or ACT short sha from meta."
    exit 1
  fi

  {
    echo "OUTER_LINUX_NAME=llvm-packages-${L}_act-${A}_Linux_X64.tar"
    echo "OUTER_MAC_ARM_NAME=llvm-packages-${L}_act-${A}_macOS_ARM64.tar"
    echo "OUTER_MAC_X64_NAME=llvm-packages-${L}_act-${A}_macOS_X64.tar"
  } >"$OUT"
}

META="${CI_PROJECT_DIR}/.llvm-ci-meta"
use_meta="false"
if [ "${LLVM_USE_LATEST_SERVER_ARTIFACTS:-}" != "true" ] && [ -d "$META" ] && emit_from_meta "$META"; then
  use_meta="true"
fi

if [ "$use_meta" != "true" ]; then
  echo "Resolving outer tar names from artifact server (regex latest per OS)."
  LNX="$(resolve_latest_basename "$PAT_LINUX")"
  ARM="$(resolve_latest_basename "$PAT_MAC_ARM")"
  X64="$(resolve_latest_basename "$PAT_MAC_X64")"
  {
    echo "OUTER_LINUX_NAME=$LNX"
    echo "OUTER_MAC_ARM_NAME=$ARM"
    echo "OUTER_MAC_X64_NAME=$X64"
  } >"$OUT"
fi

echo "Wrote $OUT"
cat "$OUT"
