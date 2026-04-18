#!/usr/bin/env bash
# Cross-copy job: download per-OS llvm/packages outer tars from LAN artifact server,
# merge and run platform_package.sh (final archives).
set -euo pipefail
: "${CI_PROJECT_DIR:?}"
: "${OUTER_LINUX_NAME:?}"
: "${OUTER_MAC_ARM_NAME:?}"
: "${OUTER_MAC_X64_NAME:?}"
source "$CI_PROJECT_DIR/scripts/ci/logging.sh"

log_info "downloading outer tars from artifact server"
echo "  Linux:       $OUTER_LINUX_NAME"
echo "  macOS arm64: $OUTER_MAC_ARM_NAME"
echo "  macOS x64:   $OUTER_MAC_X64_NAME"

WORK="${CI_PROJECT_DIR}/cross-copy-work"
rm -rf "$WORK"
mkdir -p "$WORK/downloads"
cd "$WORK"
DL="$(pwd)/downloads"

SERVER="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
for name in "$OUTER_LINUX_NAME" "$OUTER_MAC_ARM_NAME" "$OUTER_MAC_X64_NAME"; do
  log_info "downloading $name"
  curl -fsSL -o "$DL/$name" "$SERVER/artifacts/$name"
done

mkdir -p extract-linux extract-mac-arm64 extract-mac-x64 staging
log_info "decompressing $OUTER_LINUX_NAME"
tar -xf "$DL/$OUTER_LINUX_NAME" -C extract-linux
cp -f extract-linux/packages/*.tar.gz staging/

log_info "decompressing $OUTER_MAC_ARM_NAME"
tar -xf "$DL/$OUTER_MAC_ARM_NAME" -C extract-mac-arm64
cp -f extract-mac-arm64/packages/clang-dev-darwin-arm64.tar.gz staging/

log_info "decompressing $OUTER_MAC_X64_NAME"
tar -xf "$DL/$OUTER_MAC_X64_NAME" -C extract-mac-x64
cp -f extract-mac-x64/packages/clang-dev-darwin-x86_64.tar.gz staging/

if [ ! -f staging/clang-dev-windows-x86_64.tar.gz ]; then
  echo "Linux packages must include clang-dev-windows-x86_64.tar.gz"
  ls -la extract-linux/packages || true
  exit 1
fi

DOTENV="${CI_PROJECT_DIR}/cross-copy.env"
: >"$DOTENV"
export KNACTION_DOTENV_FILE="$DOTENV"
export KNACTION_STEP_SUMMARY="${KNACTION_STEP_SUMMARY:-/dev/null}"
(
  cd staging
  export COPYFILE_DISABLE=1
  bash "$CI_PROJECT_DIR/scripts/platform_package.sh"
)

set -a
# shellcheck disable=SC1090
source "$DOTENV"
set +a

for key in archive_linux archive_mac_arm64 archive_mac_x64 archive_windows; do
  fname="${!key:-}"
  [ -n "$fname" ] || { echo "Missing $key in cross-copy.env"; exit 1; }
  [ -f "staging/$fname" ] || { echo "Archive $fname missing under staging/"; ls -la staging || true; exit 1; }
  echo "Verified $key -> $fname"
done

FINAL_DIR="${CI_PROJECT_DIR}/.llvm-final-packages"
mkdir -p "$FINAL_DIR"
_SERVER="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
for key in archive_linux archive_mac_arm64 archive_mac_x64 archive_windows; do
  cp "$WORK/staging/${!key}" "$FINAL_DIR/"
  INPUT_PATH="$FINAL_DIR/${!key}" INPUT_SERVER_URL="$_SERVER" INPUT_CACHE_DIR="${HOME}/runner/artifact" \
    bash "$CI_PROJECT_DIR/.github/actions/upload-artifact-local/upload.sh"
  log_info "final artifact: $_SERVER/artifacts/${!key}"
done

echo "cross-copy.env (for downstream jobs):"
cat "$DOTENV"