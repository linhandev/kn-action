#!/usr/bin/env bash
# Emit llvm-artifact-refs.env (GitLab dotenv) for llvm:cross-copy.
# Derives OUTER_*_NAME variables from build job artifacts under .llvm-packages/ —
# filenames are llvm-packages-${L}_act-${A}_${RUNNER_OS}_${RUNNER_ARCH}.tar
# (see scripts/ci/llvm-build.sh).
#
# When build:llvm:* jobs were skipped (KNACTION_LLVM_RUN_BUILD=false), .llvm-packages/ is empty.
# In that case, resolve the latest outer tar names from the LAN artifact server so downstream
# cross-copy can download and merge them.
set -euo pipefail
: "${CI_PROJECT_DIR:?}"
source "$CI_PROJECT_DIR/scripts/ci/logging.sh"

OUT="${CI_PROJECT_DIR}/llvm-artifact-refs.env"
PKG="${CI_PROJECT_DIR}/.llvm-packages"

mkdir -p "$PKG"
shopt -s nullglob
tars=("$PKG"/llvm-packages-*.tar)

if [ "${#tars[@]}" -eq 0 ]; then
  log_info "no build artifacts in $PKG — resolving latest names from artifact server"
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

  log_info "wrote $OUT (from artifact server)"
  cat "$OUT"
  exit 0
fi

# Build artifacts present — map each tar to its platform suffix.
LINUX="" MAC_ARM="" MAC_X64=""
LLVM_SHA=""
for t in "${tars[@]}"; do
  base="${t##*/}"
  if [[ "$base" =~ ^llvm-packages-([^_]+)_act-([^_]+)_(.+)\.tar$ ]]; then
    t_llvm="${BASH_REMATCH[1]}"
    t_suffix="${BASH_REMATCH[3]}"
  else
    log_error "could not parse filename: $base"
    exit 1
  fi
  if [ -z "$LLVM_SHA" ]; then
    LLVM_SHA="$t_llvm"
  elif [ "$t_llvm" != "$LLVM_SHA" ]; then
    log_error "LLVM_SHA mismatch across tars: $t_llvm vs $LLVM_SHA ($base)"
    exit 1
  fi
  case "$t_suffix" in
    Linux_X64)   LINUX="$base" ;;
    macOS_ARM64) MAC_ARM="$base" ;;
    macOS_X64)   MAC_X64="$base" ;;
    *) log_warn "ignoring unexpected suffix: $t_suffix ($base)" ;;
  esac
done

for var_name in LINUX MAC_ARM MAC_X64; do
  val="${!var_name}"
  [ -n "$val" ] || { log_error "missing outer tar for $var_name (have ${#tars[@]} tar(s))"; exit 1; }
done

{
  echo "OUTER_LINUX_NAME=$LINUX"
  echo "OUTER_MAC_ARM_NAME=$MAC_ARM"
  echo "OUTER_MAC_X64_NAME=$MAC_X64"
  echo "LLVM_ARTIFACT_SOURCE=build"
} >"$OUT"

log_info "wrote $OUT (from ${#tars[@]} build artifact(s), LLVM_SHA=$LLVM_SHA)"
cat "$OUT"
