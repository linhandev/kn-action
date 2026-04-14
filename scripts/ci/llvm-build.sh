#!/usr/bin/env bash
# GitLab CI: matrix legs for .github/workflows/build-llvm.yml "build" job.
# Usage: llvm-build.sh linux | macos-arm64 | macos-x64
set -euo pipefail

: "${CI_PROJECT_DIR:?}"
mkdir -p "${CI_PROJECT_DIR}/.llvm-ci-meta"
source "$CI_PROJECT_DIR/scripts/ci/logging.sh"

: "${CI_PIPELINE_ID:?}"

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
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_ENV_HINTS=1
    export CI=1
    log_info "homebrew deps"
    command -v brew >/dev/null 2>&1 || {
      log_error "brew not on PATH"
      exit 1
    }
    echo "Installing LLVM build deps via Homebrew (swig, git-lfs, java, coreutils, wget, pigz, python, ccache, ninja)…"
    for pkg in swig git-lfs java coreutils wget pigz python ccache ninja; do
      if brew list "$pkg" &>/dev/null; then
        log_info "brew already installed: $pkg"
      else
        log_info "brew install: $pkg"
        brew install "$pkg"
      fi
    done
    ;;
  macos-x64)
    export RUNNER_OS=macOS
    export RUNNER_ARCH=X64
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_ENV_HINTS=1
    export CI=1
    log_info "homebrew deps"
    command -v brew >/dev/null 2>&1 || {
      log_error "brew not on PATH"
      exit 1
    }
    echo "Installing LLVM build deps via Homebrew (swig, git-lfs, java, coreutils, wget, pigz, python, ccache, ninja)…"
    for pkg in swig git-lfs java coreutils wget pigz python ccache ninja; do
      if brew list "$pkg" &>/dev/null; then
        log_info "brew already installed: $pkg"
      else
        log_info "brew install: $pkg"
        brew install "$pkg"
      fi
    done
    ;;
  *)
    log_error "Unknown platform: $PLATFORM"
    exit 1
    ;;
esac

# Keep one uniform workspace convention across runners/hosts:
# host path ~/gitlab-runner/llvm/... must be mounted into Docker at the same path.
export LLVM_WORKSPACE="${LLVM_WORKSPACE:-${CI_PROJECT_DIR}/llvm}"
export REPO_DIR="${REPO_DIR:-${CI_PROJECT_DIR}/bin}"
export ARTIFACT_LOCAL_PATH="${ARTIFACT_LOCAL_PATH:-${HOME}/runner/artifact}"
export MANIFEST_URL="${MANIFEST_URL:-https://gitcode.com/linhandev/manifest.git}"
export MANIFEST_FILE="${MANIFEST_FILE:-llvm-toolchain.xml}"

if [ "${LLVM_CLEAN_BUILD:-false}" = "true" ] || [ "${LLVM_CLEAN_BUILD:-false}" = "1" ]; then
  rm -rf "$LLVM_WORKSPACE"
fi
mkdir -p "$LLVM_WORKSPACE"

LLVM_PROJECT_BUILD="$LLVM_WORKSPACE/build"
LLVM_MUSL="$LLVM_WORKSPACE/third_party/musl"
git config --global --add safe.directory "$LLVM_PROJECT_BUILD" 2>/dev/null || true
git config --global --add safe.directory "$LLVM_MUSL" 2>/dev/null || true
git config --global user.email &>/dev/null || git config --global user.email "ci@ci.ci"
git config --global user.name &>/dev/null || git config --global user.name "ci"

log_info "setup-repo-tool"
bash "$CI_PROJECT_DIR/scripts/setup-repo-tool.sh"
export PATH="$REPO_DIR:$PATH"

if [ ! -d "$LLVM_WORKSPACE/.repo" ] || [ "${LLVM_CLEAN_BUILD:-false}" = "true" ] || [ "${LLVM_CLEAN_BUILD:-false}" = "1" ]; then
  cd "$LLVM_WORKSPACE"
  REFERENCE_FLAG=""
  ref_dir="${LOCAL_REFERENCE_DIR:-$HOME/git/ci/llvm-project-kmp}"
  if [ -d "$ref_dir" ]; then
    REFERENCE_FLAG="--reference=$ref_dir"
  fi
  log_info "repo init"
  repo init -u "$MANIFEST_URL" -m "$MANIFEST_FILE" $REFERENCE_FLAG
else
  log_info "repo init skipped (.repo present, LLVM_CLEAN_BUILD not set)"
fi

export GIT_TERMINAL_PROMPT=0
cd "$LLVM_WORKSPACE"
log_info "repo sync"
# --force-sync: overwrite work trees when .repo/project-objects vs checkout disagree (hooks/remap); required on reused runners.
# Omit -v (noisy/slow logs).
repo sync -c --force-sync -j 16
log_info "git lfs"
repo forall -c git lfs pull

# env_prepare.sh downloads CMake, Ninja under prebuilts/, etc. Run it when the tree is
# incomplete — not only when prebuilts/cmake is missing (e.g. incremental sync can leave
# prebuilts/cmake but drop build-tools/ninja; CMake then fails running ninja --version).
prebuilt_ninja_ok() {
  case "$PLATFORM" in
    linux)
      [ -x "${LLVM_WORKSPACE}/prebuilts/build-tools/linux-x64/bin/ninja" ]
      ;;
    macos-arm64)
      [ -x "${LLVM_WORKSPACE}/prebuilts/build-tools/darwin-arm64/bin/ninja" ]
      ;;
    macos-x64)
      [ -x "${LLVM_WORKSPACE}/prebuilts/build-tools/darwin-x64/bin/ninja" ] ||
        [ -x "${LLVM_WORKSPACE}/prebuilts/build-tools/darwin-x86_64/bin/ninja" ]
      ;;
    *)
      return 1
      ;;
  esac
}

NEED_ENV_PREPARE="false"
if [ ! -d "$LLVM_WORKSPACE/prebuilts/cmake" ]; then
  NEED_ENV_PREPARE="true"
fi
if ! prebuilt_ninja_ok; then
  log_warn "prebuilts incomplete (cmake dir or prebuilt ninja); will run env_prepare.sh"
  NEED_ENV_PREPARE="true"
fi

if [ "$NEED_ENV_PREPARE" = "true" ]; then
  cd "$LLVM_WORKSPACE"
  log_info "running env_prepare"
  bash -x toolchain/llvm-project/llvm-build/env_prepare.sh
fi

# Linux: OH CMake invokes prebuilts/build-tools/linux-x64/bin/ninja. Incremental repo sync can
# leave a broken or missing prebuilt ninja; prefer distro ninja-build (Dockerfile) or Homebrew
# ninja on Linux hosts that use linuxbrew — symlink into the tree CMake expects.
if [ "$PLATFORM" = "linux" ]; then
  log_info "Linux: ensure ninja for prebuilts path (apt ninja-build or Homebrew)"
  if command -v apt-get >/dev/null 2>&1; then
    if ! command -v ninja >/dev/null 2>&1; then
      log_info "apt-get install ninja-build"
      apt-get update
      apt-get install -y --no-install-recommends ninja-build
    fi
  elif command -v brew >/dev/null 2>&1; then
    brew list ninja &>/dev/null || brew install ninja
  fi
  if command -v ninja >/dev/null 2>&1; then
    sys_ninja="$(command -v ninja)"
    mkdir -p "${LLVM_WORKSPACE}/prebuilts/build-tools/linux-x64/bin"
    ln -sf "$sys_ninja" "${LLVM_WORKSPACE}/prebuilts/build-tools/linux-x64/bin/ninja"
    log_info "Linux: linked ninja -> $sys_ninja"
  else
    log_error "Linux: ninja not available after install attempts"
    exit 1
  fi
fi

# Last resort on macOS: Homebrew ninja at the path OH build.py passes to CMake.
if ! prebuilt_ninja_ok; then
  case "$PLATFORM" in
    macos-arm64 | macos-x64)
      log_warn "prebuilt ninja still missing after env_prepare; linking Homebrew ninja into prebuilts/build-tools"
      command -v brew >/dev/null 2>&1 || {
        log_error "brew not on PATH"
        exit 1
      }
      brew list ninja &>/dev/null || brew install ninja
      sys_ninja="$(command -v ninja)"
      mkdir -p "${LLVM_WORKSPACE}/prebuilts/build-tools/darwin-arm64/bin"
      ln -sf "$sys_ninja" "${LLVM_WORKSPACE}/prebuilts/build-tools/darwin-arm64/bin/ninja"
      if [ "$PLATFORM" = "macos-x64" ]; then
        mkdir -p "${LLVM_WORKSPACE}/prebuilts/build-tools/darwin-x64/bin" \
          "${LLVM_WORKSPACE}/prebuilts/build-tools/darwin-x86_64/bin"
        ln -sf "$sys_ninja" "${LLVM_WORKSPACE}/prebuilts/build-tools/darwin-x64/bin/ninja"
        ln -sf "$sys_ninja" "${LLVM_WORKSPACE}/prebuilts/build-tools/darwin-x86_64/bin/ninja"
      fi
      ;;
    *)
      log_error "prebuilt ninja missing after env_prepare (fix prebuilts or install ninja for $PLATFORM)"
      exit 1
      ;;
  esac
fi
if ! prebuilt_ninja_ok; then
  log_error "prebuilt ninja still not usable under prebuilts/build-tools"
  exit 1
fi

# log_info "ccache setup"
# if ! source "$CI_PROJECT_DIR/scripts/setup-llvm-ccache.sh"; then
#   log_warn "ccache setup failed; running env_prepare on demand and retrying"
#   cd "$LLVM_WORKSPACE"
#   log_info "running env_prepare (ccache/toolchain bootstrap)"
#   bash -x toolchain/llvm-project/llvm-build/env_prepare.sh
#   log_info "ccache setup retry"
#   source "$CI_PROJECT_DIR/scripts/setup-llvm-ccache.sh"
# fi

log_info "running build.sh"
cd "$LLVM_WORKSPACE"
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
  log_error "Could not determine commit short SHA (CI_COMMIT_SHA / git rev-parse)."
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
  log_error "Expected non-empty directory at $PACKAGES_DIR"
  exit 1
fi

ARCHIVE_NAME="llvm-packages-${LLVM_SHA_SHORT}_act-${COMMIT_SHORT}_${RUNNER_OS}_${RUNNER_ARCH}.tar"
OUT_PATH="$AP/$ARCHIVE_NAME"
log_info "tar packages -> $OUT_PATH"
tar -cf "$OUT_PATH" -C "$LLVM_WORKSPACE" packages

export INPUT_PATH="$OUT_PATH"
export INPUT_SERVER_URL="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
export INPUT_CACHE_DIR="$AP"
KNACTION_DOTENV_FILE="$(mktemp)"
export KNACTION_DOTENV_FILE
log_info "upload artifact server ${INPUT_SERVER_URL:-}"
# shellcheck source=/dev/null
if ! source "$CI_PROJECT_DIR/.github/actions/upload-artifact-local/upload.sh"; then
  log_warn "Artifact upload failed (retry once after 5s)."
  log_warn "Check Docker runner LAN reachability to ARTIFACT_SERVER_URL (${INPUT_SERVER_URL:-})."
  sleep 5
  log_info "upload retry"
  # shellcheck source=/dev/null
  source "$CI_PROJECT_DIR/.github/actions/upload-artifact-local/upload.sh"
fi
rm -f "$KNACTION_DOTENV_FILE"

echo "LLVM packages archive: $OUT_PATH"
