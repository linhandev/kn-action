#!/usr/bin/env bash
# GHA cross-copy job: merge llvm/packages outer tars and run platform_package RUN_FINAL_PACKAGE=1.
set -euo pipefail
: "${CI_PROJECT_DIR:?}"
: "${OUTER_LINUX_NAME:?}"
: "${OUTER_MAC_ARM_NAME:?}"
: "${OUTER_MAC_X64_NAME:?}"

WORK="${CI_PROJECT_DIR}/cross-copy-work"
rm -rf "$WORK"
mkdir -p "$WORK/downloads"
cd "$WORK"
DL="$(pwd)/downloads"

"$CI_PROJECT_DIR/scripts/ci/gitlab-download-artifact-local.sh" --name="$OUTER_LINUX_NAME" --dir="$DL"
"$CI_PROJECT_DIR/scripts/ci/gitlab-download-artifact-local.sh" --name="$OUTER_MAC_ARM_NAME" --dir="$DL"
"$CI_PROJECT_DIR/scripts/ci/gitlab-download-artifact-local.sh" --name="$OUTER_MAC_X64_NAME" --dir="$DL"

mkdir -p extract-linux extract-mac-arm64 extract-mac-x64 staging
tar -xf "$DL/$OUTER_LINUX_NAME" -C extract-linux
tar -xf "$DL/$OUTER_MAC_ARM_NAME" -C extract-mac-arm64
tar -xf "$DL/$OUTER_MAC_X64_NAME" -C extract-mac-x64
cp -f extract-linux/packages/*.tar.gz staging/
cp -f extract-mac-arm64/packages/clang-dev-darwin-arm64.tar.gz staging/
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
  export LLVM_MAJOR_FOR_PACKAGE="${LLVM_MAJOR_FOR_PACKAGE:-19}"
  export LLVM_ESSENTIALS_ID="${LLVM_ESSENTIALS_ID:-203}"
  export RUN_FINAL_PACKAGE=1
  export CLANG_RESOURCE_VERSION="${CLANG_RESOURCE_VERSION:-19}"
  export COPYFILE_DISABLE=1
  bash "$CI_PROJECT_DIR/scripts/platform_package.sh"
)

for p in clang_darwin-arm64 clang_darwin-x86_64 clang_windows-x86_64; do
  D="$(find staging -maxdepth 1 -type d -name "${p}-*" | head -1)"
  if [ -z "$D" ] || [ ! -d "$D" ]; then
    echo "Missing merged $p tree under staging"
    ls -la staging || true
    exit 1
  fi
  echo "Merged $p -> $D"
done

set -a
# shellcheck disable=SC1090
source "$DOTENV"
set +a

AP="${ARTIFACT_LOCAL_PATH:-$HOME/runner/artifact}"
AP="${AP/#\~/$HOME}"
UP_DOT="$(mktemp)"
export INPUT_SERVER_URL="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
export INPUT_CACHE_DIR="$AP"
export KNACTION_DOTENV_FILE="$UP_DOT"

for key in archive_linux archive_mac_arm64 archive_mac_x64 archive_windows; do
  fname="${!key:-}"
  if [ -z "$fname" ]; then
    echo "Missing $key in cross-copy.env"
    exit 1
  fi
  export INPUT_PATH="$WORK/staging/$fname"
  # shellcheck source=/dev/null
  source "$CI_PROJECT_DIR/.github/actions/upload-artifact-local/upload.sh"
done
rm -f "$UP_DOT"

echo "cross-copy.env (for downstream jobs):"
cat "$DOTENV"
