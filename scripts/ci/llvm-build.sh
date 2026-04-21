#!/usr/bin/env bash
# GitLab CI: matrix legs for LLVM build.
# Usage: llvm-build.sh linux | macos-arm64 | macos-x64
set -euo pipefail

: "${CI_PROJECT_DIR:?}"
: "${CI_PIPELINE_ID:?}"
source "$CI_PROJECT_DIR/scripts/ci/logging.sh"

# GitLab / YAML / copy-paste can inject CR, LF, or spaces into MANIFEST_FILE. If unnormalized,
# ${MANIFEST_FILE%.xml} does NOT strip the suffix (e.g. "llvm-1914-bare.xml\r" → wrong LLVM_WORKSPACE).
_kn_action_normalize_manifest_name() {
  local raw="${1:-llvm-1914.xml}"
  raw="$(printf '%s' "$raw" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -n "$raw" ] || raw="llvm-1914.xml"
  case "$raw" in
    *.xml) ;;
    *)
      log_warn "MANIFEST_FILE had no .xml suffix (got '$raw'); appending .xml"
      raw="${raw}.xml"
      ;;
  esac
  printf '%s' "$raw"
}

export REPO_DIR="${REPO_DIR:-${CI_PROJECT_DIR}/bin}"
export REPO_URL="${REPO_URL:-https://mirrors.tuna.tsinghua.edu.cn/git/git-repo}"
MANIFEST_FILE="$(_kn_action_normalize_manifest_name "${MANIFEST_FILE:-llvm-1914.xml}")"
export MANIFEST_FILE
export LLVM_WORKSPACE="${LLVM_WORKSPACE:-${CI_PROJECT_DIR}/${MANIFEST_FILE%.xml}}"
export LOCAL_REFERENCE_DIR="${LOCAL_REFERENCE_DIR:-$HOME/git/ci/llvm-project-kmp}"

PLATFORM="${1:?usage: llvm-build.sh linux|macos-arm64|macos-x64}"
log_info "start platform=$PLATFORM CI_JOB_NAME=${CI_JOB_NAME:-}"

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

LLVM_PROJECT_DIR="$LLVM_WORKSPACE/toolchain/llvm-project"
log_info "LLVM_WORKSPACE=$LLVM_WORKSPACE (manifest=$MANIFEST_FILE)"

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

# Reuse the workspace whenever .repo exists; repo sync below repairs partial checkouts.
# If .repo is missing (stale / never inited), clear the workspace and run repo init.
if ! [ -d "$LLVM_WORKSPACE/.repo" ] || [ "${LLVM_CLEAN_BUILD:-false}" = "true" ]; then
  cd "$LLVM_WORKSPACE"
  if ! [ -d "$LLVM_WORKSPACE/.repo" ] && [ "${LLVM_CLEAN_BUILD:-false}" != "true" ]; then
    log_warn "LLVM workspace stale or incomplete; wiping .repo and partial project trees before init"
  fi
  # Only removing .repo leaves broken project dirs (e.g. build/) from a failed sync; repo sync then hits
  # fatal: bad revision 'HEAD'. Clear the workspace entirely before a fresh repo init.
  find "$LLVM_WORKSPACE" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  REFERENCE_FLAG=""
  [ -d "$LOCAL_REFERENCE_DIR" ] && REFERENCE_FLAG="--reference=$LOCAL_REFERENCE_DIR"
  MANIFEST_PATH="$CI_PROJECT_DIR/manifest/$MANIFEST_FILE"
  log_info "repo init --standalone-manifest (manifest=$MANIFEST_FILE)"
  repo init --standalone-manifest -u "file://$MANIFEST_PATH" $REFERENCE_FLAG
  printf '%s\n' "$MANIFEST_FILE" >"$LLVM_WORKSPACE/.repo/.manifest_file"
else
  log_info "repo init skipped (.repo valid for manifest=$MANIFEST_FILE)"
fi

export GIT_TERMINAL_PROMPT=0
cd "$LLVM_WORKSPACE"
log_info "repo sync"
repo forall -c 'git reset --hard && git clean -ffdx'
repo sync -c --force-sync -d --prune -j 16

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

# Omitting LLVM/OHOS stages is only via GitLab LLVM_SKIP_PIPELINE (see .gitlab-ci.yml), not by probing the artifact server.
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
fi

DOTENV="$CI_PROJECT_DIR/llvm-build-${PLATFORM}.env"
{
  echo "MANIFEST_MD5=$MANIFEST_MD5"
  echo "LLVM_SHA_SHORT=$LLVM_SHA_SHORT"
  echo "ACT_SHA_SHORT=$ACT_SHA_SHORT"
  echo "FINAL_ARTIFACT=$FINAL_ARTIFACT"
} > "$DOTENV"

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
  [ -d "$ws/prebuilts/cmake/${_CMAKE}/share" ] &&
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
  ccache -M 20G 2>/dev/null || true
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
    bash "$CI_PROJECT_DIR/.github/actions/upload-artifact-local/upload.sh"
  log_info "outer tar artifact: $SERVER/artifacts/$OUTER_NAME"
else
  log_warn "artifact server unreachable at $SERVER; skipping upload"
fi

echo "OUTER_NAME=$OUTER_NAME" >> "$DOTENV"
