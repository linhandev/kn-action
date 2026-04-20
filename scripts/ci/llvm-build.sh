#!/usr/bin/env bash
# GitLab CI: matrix legs for LLVM build.
# Usage: llvm-build.sh linux | macos-arm64 | macos-x64
set -euo pipefail

: "${CI_PROJECT_DIR:?}"
: "${CI_PIPELINE_ID:?}"
source "$CI_PROJECT_DIR/scripts/ci/logging.sh"

PLATFORM="${1:?usage: llvm-build.sh linux|macos-arm64|macos-x64}"
log_info "start platform=$PLATFORM CI_JOB_NAME=${CI_JOB_NAME:-}"

_KN_ACTION_SKIP_LLVM_BUILD_SHA="disabled"
if [ "${CI_COMMIT_SHA:-}" = "$_KN_ACTION_SKIP_LLVM_BUILD_SHA" ]; then
  log_info "Internal debug: skipping LLVM build for commit $CI_COMMIT_SHA"
  echo "SKIP_BUILD=true" > "$CI_PROJECT_DIR/llvm-build-${PLATFORM}.env"
  exit 0
fi

case "$PLATFORM" in
  linux)
    export RUNNER_OS=Linux
    export RUNNER_ARCH=X64
    ;;
  macos-arm64)
    export RUNNER_OS=macOS
    export RUNNER_ARCH=ARM64
    ;;
  macos-x64)
    export RUNNER_OS=macOS
    export RUNNER_ARCH=X64
    ;;
  *)
    log_error "Unknown platform: $PLATFORM"
    exit 1
    ;;
esac

# macOS: install build deps via Homebrew
case "$PLATFORM" in
  macos-*)
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_ENV_HINTS=1
    export CI=1
    log_info "homebrew deps"
    command -v brew >/dev/null 2>&1 || { log_error "brew not on PATH"; exit 1; }
    for pkg in swig git-lfs java coreutils wget pigz python ccache ninja; do
      if brew list "$pkg" &>/dev/null; then
        log_info "brew already installed: $pkg"
      else
        log_info "brew install: $pkg"
        brew install "$pkg"
      fi
    done
    ;;
esac

export LLVM_WORKSPACE="${LLVM_WORKSPACE:-${CI_PROJECT_DIR}/llvm}"
LLVM_PROJECT_DIR="$LLVM_WORKSPACE/toolchain/llvm-project"
export REPO_DIR="${REPO_DIR:-${CI_PROJECT_DIR}/bin}"
export MANIFEST_URL="${MANIFEST_URL:-https://gitcode.com/linhandev/manifest.git}"
export MANIFEST_FILE="${MANIFEST_FILE:-llvm-toolchain.xml}"

if [ "${LLVM_CLEAN_BUILD:-false}" = "true" ]; then
  rm -rf "$LLVM_WORKSPACE"
fi
mkdir -p "$LLVM_WORKSPACE"

git config --global --add safe.directory '*' 2>/dev/null || true
git config --global user.email "ci@ci.ci" 2>/dev/null || true
git config --global user.name "ci" 2>/dev/null || true

log_info "setup-repo-tool"
bash "$CI_PROJECT_DIR/scripts/setup-repo-tool.sh"
export PATH="$REPO_DIR:$PATH"

if [ ! -d "$LLVM_WORKSPACE/.repo" ] || [ "${LLVM_CLEAN_BUILD:-false}" = "true" ]; then
  cd "$LLVM_WORKSPACE"
  REFERENCE_FLAG=""
  ref_dir="${LOCAL_REFERENCE_DIR:-$HOME/git/ci/llvm-project-kmp}"
  [ -d "$ref_dir" ] && REFERENCE_FLAG="--reference=$ref_dir"
  log_info "repo init"
  repo init -u "$MANIFEST_URL" -m "$MANIFEST_FILE" $REFERENCE_FLAG
else
  log_warn "repo init skipped (.repo present, LLVM_CLEAN_BUILD not set)"
fi

export GIT_TERMINAL_PROMPT=0
cd "$LLVM_WORKSPACE"
log_info "repo sync"
# --force-sync: overwrite work trees when .repo/project-objects vs checkout disagree; required on reused runners.
repo sync -c --force-sync -j 16
log_info "toolchain/llvm-project last 5 commits (full id, title)"
git -C "$LLVM_PROJECT_DIR" log -n 5 --format='%H %s' >&2 || log_warn "could not read git log for toolchain/llvm-project"
log_info "git lfs pull (per sub-repo)"
set +e
repo forall -c git lfs pull
_lfs_rc=$?
set -e
log_info "git lfs pull done (rc=$_lfs_rc)"
if [ "$_lfs_rc" -ne 0 ]; then
  log_warn "repo forall git lfs pull exited $_lfs_rc; continuing without LFS objects"
fi

log_info "generating revision-locked manifest for signature"
MANIFEST_LOCKED="$LLVM_WORKSPACE/.repo-manifest-locked.xml"
repo manifest -r -o "$MANIFEST_LOCKED"
MANIFEST_MD5="$(md5sum "$MANIFEST_LOCKED" | awk '{print $1}' | cut -c1-16)"

LLVM_SHA="$(git -C "$LLVM_PROJECT_DIR" rev-parse HEAD)"
LLVM_SHA_SHORT="${LLVM_SHA:0:7}"

ACT_SHA="${CI_COMMIT_SHA:-$(git -C "$CI_PROJECT_DIR" rev-parse HEAD)}"
ACT_SHA_SHORT="${ACT_SHA:0:7}"

log_info "three IDs: manifest=${MANIFEST_MD5} llvm=${LLVM_SHA_SHORT} act=${ACT_SHA_SHORT}"

SKIP_BUILD="false"
FINAL_ARTIFACT=""

if [ "${LLVM_CLEAN_BUILD:-false}" != "true" ]; then
  LLVM_MAJOR="${LLVM_MAJOR_FOR_PACKAGE:-19}"
  OH_VER="${OH_VERSION:-1}"
  
  case "$PLATFORM" in
    linux)       FINAL_ARCH="x86_64"; FINAL_OS="linux" ;;
    macos-arm64) FINAL_ARCH="aarch64"; FINAL_OS="macos" ;;
    macos-x64)   FINAL_ARCH="x86_64"; FINAL_OS="macos" ;;
  esac
  
  FINAL_ARTIFACT="llvm-${LLVM_MAJOR}-${FINAL_ARCH}-${FINAL_OS}-dev-oh-${OH_VER}_llvm-${LLVM_SHA_SHORT}_act-${ACT_SHA_SHORT}_manifest-${MANIFEST_MD5}.tar.gz"
  
  SERVER="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
  HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' "$SERVER/artifacts/$FINAL_ARTIFACT" 2>/dev/null || echo "000")"
  
  if [ "$HTTP_CODE" = "200" ]; then
    log_info "Final artifact cached: $FINAL_ARTIFACT"
    SKIP_BUILD="true"
  else
    log_info "Final artifact not cached (HTTP $HTTP_CODE); will build"
  fi
fi

DOTENV="$CI_PROJECT_DIR/llvm-build-${PLATFORM}.env"
{
  echo "SKIP_BUILD=$SKIP_BUILD"
  echo "MANIFEST_MD5=$MANIFEST_MD5"
  echo "LLVM_SHA_SHORT=$LLVM_SHA_SHORT"
  echo "ACT_SHA_SHORT=$ACT_SHA_SHORT"
  echo "FINAL_ARTIFACT=$FINAL_ARTIFACT"
} > "$DOTENV"

if [ "$SKIP_BUILD" = "true" ]; then
  log_info "Skipping build (cached artifact found)"
  echo "Build skipped. Final artifact: $SERVER/artifacts/$FINAL_ARTIFACT"
  exit 0
fi

log_info "Proceeding with build..."

# env_prepare.sh downloads CMake, Ninja, Clang bootstrap, Python3 under prebuilts/.
# Platform→subpath map matches env_prepare.sh layout and build.py platform_prefix().
case "$PLATFORM" in
  linux)      _CMAKE=linux-x86;        _NINJA=linux-x86;   _CLANG=linux-x86_64;  _PY3=linux-x86 ;;
  macos-arm64) _CMAKE=darwin-universal; _NINJA=darwin-arm64; _CLANG=darwin-arm64;  _PY3=darwin-arm64 ;;
  macos-x64)  _CMAKE=darwin-universal;  _NINJA=darwin-x86;   _CLANG=darwin-x86_64; _PY3=darwin-x86 ;;
esac

prebuilts_complete() {
  local ws="$LLVM_WORKSPACE"
  [ -x "$ws/prebuilts/cmake/${_CMAKE}/bin/cmake" ] &&
  [ -x "$ws/prebuilts/build-tools/${_NINJA}/bin/ninja" ] &&
  [ -d "$ws/prebuilts/clang/ohos/${_CLANG}" ] &&
  [ -d "$ws/prebuilts/python3/${_PY3}" ]
}

if ! prebuilts_complete; then
  log_info "prebuilts incomplete; running env_prepare"
  cd "$LLVM_WORKSPACE"
  for _attempt in 1 2; do
    bash -x toolchain/llvm-project/llvm-build/env_prepare.sh || true
    if prebuilts_complete; then break; fi
    log_warn "env_prepare attempt $_attempt incomplete; cleaning download_packages and retrying"
    rm -rf "$LLVM_WORKSPACE/download_packages"
  done
  prebuilts_complete || { log_error "prebuilts still incomplete after env_prepare"; exit 1; }
fi
log_info "prebuilts OK"

if command -v ccache >/dev/null 2>&1; then
  if [ "$PLATFORM" = "linux" ]; then
    export CCACHE_DIR="/root/gitlab-runner/cache/llvm-ccache"
  else
    export CCACHE_DIR="${HOME}/gitlab-runner/cache/llvm-ccache"
  fi
  mkdir -p "$CCACHE_DIR"
  ccache -M 5G 2>/dev/null || true
  export CMAKE_C_COMPILER_LAUNCHER=ccache
  export CMAKE_CXX_COMPILER_LAUNCHER=ccache
  ccache --zero-stats 2>/dev/null || true
  log_info "ccache enabled: CCACHE_DIR=$CCACHE_DIR  max_size=$(ccache -p 2>/dev/null | grep max_size | head -1)"
fi

log_info "running build.sh"
cd "$LLVM_WORKSPACE"
bash toolchain/llvm-project/llvm-build/build.sh
if command -v ccache >/dev/null 2>&1; then
  log_info "ccache stats after build:"
  ccache -s || true
fi

log_info "llvm-project HEAD: $LLVM_SHA_SHORT"

PACKAGES_DIR="$LLVM_WORKSPACE/packages"
if [ ! -d "$PACKAGES_DIR" ] || [ -z "$(ls -A "$PACKAGES_DIR" 2>/dev/null)" ]; then
  log_error "Expected non-empty directory at $PACKAGES_DIR"
  exit 1
fi

OUTER_NAME="llvm-packages_llvm-${LLVM_SHA_SHORT}_act-${ACT_SHA_SHORT}_manifest-${MANIFEST_MD5}_${RUNNER_OS}_${RUNNER_ARCH}.tar"
GL_PKG_DIR="${CI_PROJECT_DIR}/.llvm-packages"
mkdir -p "$GL_PKG_DIR"
OUT_PATH="$GL_PKG_DIR/$OUTER_NAME"
log_info "tar packages -> $OUT_PATH"
tar -cf "$OUT_PATH" -C "$LLVM_WORKSPACE" packages

echo "LLVM packages archive: $OUT_PATH"

SERVER="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
if curl -sS --connect-timeout 5 -o /dev/null "$SERVER/" 2>/dev/null; then
  log_info "uploading outer tar to artifact server (retain_days=2)"
  INPUT_PATH="$OUT_PATH" INPUT_SERVER_URL="$SERVER" INPUT_CACHE_DIR="${HOME}/runner/artifact" \
    INPUT_RETAIN_DAYS=2 \
    bash "$CI_PROJECT_DIR/.github/actions/upload-artifact-local/upload.sh" \
    || log_warn "artifact server upload failed (non-fatal)"
  log_info "outer tar artifact: $SERVER/artifacts/$OUTER_NAME"
else
  log_warn "artifact server unreachable at $SERVER; skipping upload"
fi

echo "OUTER_NAME=$OUTER_NAME" >> "$DOTENV"
