#!/usr/bin/env bash
# Emit llvm-artifact-refs.env (GitLab dotenv) for llvm:cross-copy.
# Resolves latest outer tar names from the LAN artifact server.
# Build jobs upload directly to server; no GitLab artifacts passed.
set -euo pipefail
: "${CI_PROJECT_DIR:?}"
source "$CI_PROJECT_DIR/scripts/ci/logging.sh"

OUT="${CI_PROJECT_DIR}/llvm-artifact-refs.env"

log_info "resolving latest outer tar names from artifact server"
# shellcheck source=artifact-server-latest.sh
source "$CI_PROJECT_DIR/scripts/ci/artifact-server-latest.sh"
SERVER="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"

declare -A NAMES
for suffix in "Linux_X64" "macOS_ARM64" "macOS_X64"; do
  name="$(artifact_server_latest_basename "$SERVER" "llvm-packages-.*_${suffix}\\.tar$")"
  NAMES[$suffix]="$name"
  log_info "resolved $suffix -> $name"
done

{
  echo "OUTER_LINUX_NAME=${NAMES[Linux_X64]}"
  echo "OUTER_MAC_ARM_NAME=${NAMES[macOS_ARM64]}"
  echo "OUTER_MAC_X64_NAME=${NAMES[macOS_X64]}"
  echo "LLVM_ARTIFACT_SOURCE=server"
} >"$OUT"

log_info "wrote $OUT"
cat "$OUT"