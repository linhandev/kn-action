#!/usr/bin/env bash
# GitLab CI: matrix legs for .github/workflows/build-llvm.yml "build" job.
# Usage: gitlab-llvm-build.sh linux | macos-arm64 | macos-amd64
set -euo pipefail

: "${CI_PROJECT_DIR:?}"
mkdir -p "${CI_PROJECT_DIR}/.llvm-ci-meta"
LLVM_TRACE="${CI_PROJECT_DIR}/.llvm-ci-meta/trace.log"
: >"$LLVM_TRACE"
trace() {
  local line
  line="$(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"
  echo "$line" >>"$LLVM_TRACE"
  echo "$line" >&2
}

if [ -z "${GITCODE_TOKEN:-}" ]; then
  echo "GITCODE_TOKEN is empty in this job."
  echo "GitLab omits Protected variables on unprotected branches. Fix one of:"
  echo "  • Settings → Repository → Protected branches: protect ${CI_COMMIT_REF_NAME:-this branch}; or"
  echo "  • Settings → CI/CD → Variables → GITCODE_TOKEN: uncheck \"Protect variable\" (still use Masked)."
  exit 1
fi
: "${CI_PIPELINE_ID:?}"

PLATFORM="${1:?usage: gitlab-llvm-build.sh linux|macos-arm64|macos-amd64}"
trace "start platform=$PLATFORM CI_JOB_NAME=${CI_JOB_NAME:-}"

case "$PLATFORM" in
  linux)
    export RUNNER_OS=Linux
    export RUNNER_ARCH=X64
    ;;
  macos-arm64)
    export RUNNER_OS=macOS
    export RUNNER_ARCH=ARM64
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_ENV_HINTS=1
    export CI=1
    trace "homebrew deps"
    command -v brew >/dev/null 2>&1 || {
      echo "brew not on PATH"
      exit 1
    }
    echo "Installing LLVM build deps via Homebrew (swig, git-lfs, java, coreutils, wget, pigz, python, ccache)…"
    for pkg in swig git-lfs java coreutils wget pigz python ccache; do
      if brew list "$pkg" &>/dev/null; then
        trace "brew already installed: $pkg"
      else
        trace "brew install: $pkg"
        brew install "$pkg"
      fi
    done
    ;;
  macos-amd64)
    export RUNNER_OS=macOS
    export RUNNER_ARCH=X64
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_ENV_HINTS=1
    export CI=1
    trace "homebrew deps"
    command -v brew >/dev/null 2>&1 || {
      echo "brew not on PATH"
      exit 1
    }
    echo "Installing LLVM build deps via Homebrew (swig, git-lfs, java, coreutils, wget, pigz, python, ccache)…"
    for pkg in swig git-lfs java coreutils wget pigz python ccache; do
      if brew list "$pkg" &>/dev/null; then
        trace "brew already installed: $pkg"
      else
        trace "brew install: $pkg"
        brew install "$pkg"
      fi
    done
    ;;
  *)
    echo "Unknown platform: $PLATFORM"
    exit 1
    ;;
esac

export LLVM_WORKSPACE="${LLVM_WORKSPACE:-${CI_PROJECT_DIR}/llvm}"
export REPO_DIR="${REPO_DIR:-${CI_PROJECT_DIR}/bin}"
export ARTIFACT_LOCAL_PATH="${ARTIFACT_LOCAL_PATH:-${HOME}/runner/artifact}"
export MANIFEST_URL="${MANIFEST_URL:-https://gitcode.com/linhandev/manifest.git}"
export MANIFEST_FILE="${MANIFEST_FILE:-llvm-toolchain.xml}"

if [ "${LLVM_CLEAN_BUILD:-false}" = "true" ] || [ "${LLVM_CLEAN_BUILD:-false}" = "1" ]; then
  rm -rf "$LLVM_WORKSPACE"
fi
mkdir -p "$LLVM_WORKSPACE"

NEED_ENV_PREPARE="false"
if [ ! -d "$LLVM_WORKSPACE/prebuilts/cmake" ]; then
  NEED_ENV_PREPARE="true"
fi

LLVM_PROJECT_BUILD="$LLVM_WORKSPACE/build"
LLVM_MUSL="$LLVM_WORKSPACE/third_party/musl"
git config --global --add safe.directory "$LLVM_PROJECT_BUILD" 2>/dev/null || true
git config --global --add safe.directory "$LLVM_MUSL" 2>/dev/null || true
git config --global user.email &>/dev/null || git config --global user.email "ci@ci.ci"
git config --global user.name &>/dev/null || git config --global user.name "ci"

git config --global credential.helper ''
git config --global --unset-all url."https://linhandev:${GITCODE_TOKEN}@gitcode.com/".insteadOf 2>/dev/null || true
git config --global url."https://linhandev:${GITCODE_TOKEN}@gitcode.com/".insteadOf "https://gitcode.com/"
git config --global --add url."https://linhandev:${GITCODE_TOKEN}@gitcode.com/".insteadOf "git@gitcode.com:"

trace "setup-repo-tool"
bash "$CI_PROJECT_DIR/scripts/setup-repo-tool.sh"
export PATH="$REPO_DIR:$PATH"

if [ ! -d "$LLVM_WORKSPACE/.repo" ] || [ "${LLVM_CLEAN_BUILD:-false}" = "true" ] || [ "${LLVM_CLEAN_BUILD:-false}" = "1" ]; then
  cd "$LLVM_WORKSPACE"
  REFERENCE_FLAG=""
  ref_dir="${LOCAL_REFERENCE_DIR:-$HOME/git/ci/llvm-project-kmp}"
  if [ -d "$ref_dir" ]; then
    REFERENCE_FLAG="--reference=$ref_dir"
  fi
  trace "repo init"
  repo init -u "$MANIFEST_URL" -m "$MANIFEST_FILE" $REFERENCE_FLAG
fi

export GIT_TERMINAL_PROMPT=0
cd "$LLVM_WORKSPACE"
trace "repo sync"
repo sync -c -v -j 16
trace "git lfs"
repo forall -c git lfs pull

if [ -n "${GITCODE_TOKEN:-}" ]; then
  git config --global --unset-all url."https://linhandev:${GITCODE_TOKEN}@gitcode.com/".insteadOf 2>/dev/null || true
fi
git config --global --unset credential.helper 2>/dev/null || true

if [ "$NEED_ENV_PREPARE" = "true" ]; then
  cd "$LLVM_WORKSPACE"
  trace "env_prepare"
  bash -x toolchain/llvm-project/llvm-build/env_prepare.sh
fi

trace "ccache setup"
source "$CI_PROJECT_DIR/scripts/setup-llvm-ccache.sh"
cd "$LLVM_WORKSPACE"
trace "llvm build.sh"
bash toolchain/llvm-project/llvm-build/build.sh
if command -v ccache >/dev/null 2>&1; then
  ccache -s || true
fi

AP="${ARTIFACT_LOCAL_PATH/#\~/$HOME}"
mkdir -p "$AP"

LLVM_PROJECT_DIR="$LLVM_WORKSPACE/toolchain/llvm-project"
LLVM_SHA="$(git -C "$LLVM_PROJECT_DIR" rev-parse HEAD)"
LLVM_SHA_SHORT="${LLVM_SHA:0:7}"
COMMIT_SHORT="${CI_COMMIT_SHA:0:7}"
if [ -z "${COMMIT_SHORT// }" ]; then
  COMMIT_SHORT="$(git -C "$CI_PROJECT_DIR" rev-parse --short=7 HEAD 2>/dev/null || true)"
fi
if [ -z "${COMMIT_SHORT// }" ]; then
  echo "Could not determine commit short SHA (CI_COMMIT_SHA / git rev-parse)."
  exit 1
fi

META_DIR="${CI_PROJECT_DIR}/.llvm-ci-meta"
SAFE_JOB="$(echo "${CI_JOB_NAME:-llvm-build}" | tr ':/' '__')"
{
  echo "LLVM_SHA_SHORT=${LLVM_SHA_SHORT}"
  echo "ACT_SHA_SHORT=${COMMIT_SHORT}"
} >"${META_DIR}/${SAFE_JOB}.env"

PACKAGES_DIR="$LLVM_WORKSPACE/packages"
if [ ! -d "$PACKAGES_DIR" ] || [ -z "$(ls -A "$PACKAGES_DIR" 2>/dev/null)" ]; then
  echo "Expected non-empty directory at $PACKAGES_DIR"
  exit 1
fi

ARCHIVE_NAME="llvm-packages-${LLVM_SHA_SHORT}_act-${COMMIT_SHORT}_${RUNNER_OS}_${RUNNER_ARCH}.tar"
OUT_PATH="$AP/$ARCHIVE_NAME"
trace "tar packages -> $OUT_PATH"
tar -cf "$OUT_PATH" -C "$LLVM_WORKSPACE" packages

export INPUT_PATH="$OUT_PATH"
export INPUT_SERVER_URL="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
export INPUT_CACHE_DIR="$AP"
KNACTION_DOTENV_FILE="$(mktemp)"
export KNACTION_DOTENV_FILE
trace "upload artifact server ${INPUT_SERVER_URL:-}"
# shellcheck source=/dev/null
if ! source "$CI_PROJECT_DIR/.github/actions/upload-artifact-local/upload.sh"; then
  echo "Artifact upload failed (retry once after 5s). Check Docker runner LAN reachability to ARTIFACT_SERVER_URL (${INPUT_SERVER_URL:-})."
  sleep 5
  trace "upload retry"
  # shellcheck source=/dev/null
  source "$CI_PROJECT_DIR/.github/actions/upload-artifact-local/upload.sh"
fi
rm -f "$KNACTION_DOTENV_FILE"

echo "LLVM packages archive: $OUT_PATH"
