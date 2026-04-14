#!/usr/bin/env bash
# Source before OH LLVM build.sh when ccache is available.
# Usage: source "$CI_PROJECT_DIR/scripts/setup-llvm-ccache.sh"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/ci" && pwd)/logging.sh"

if ! command -v ccache >/dev/null 2>&1; then
  log_warn "ccache not found, skipping"
  return 0 2>/dev/null || exit 0
fi

# Linux Docker must bind-mount ~/gitlab-runner/cache into the container at the same path.
export CCACHE_DIR="${HOME}/gitlab-runner/cache/llvm-ccache-$(uname -s)-$(uname -m)"
mkdir -p "$CCACHE_DIR"

export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-50G}"
export CCACHE_COMPRESS="${CCACHE_COMPRESS:-1}"
export CMAKE_C_COMPILER_LAUNCHER=ccache
export CMAKE_CXX_COMPILER_LAUNCHER=ccache

# --- Resolve OH prebuilt Clang for CC/CXX ---
_root="${LLVM_WORKSPACE:-${CI_PROJECT_DIR:+${CI_PROJECT_DIR}/llvm}}"
if [ -z "$_root" ]; then
  log_error "set LLVM_WORKSPACE or CI_PROJECT_DIR to find prebuilt clang"
  return 1 2>/dev/null || exit 1
fi

case "$(uname -s)" in Linux) _os=linux ;; Darwin) _os=darwin ;;
  *) log_error "unsupported OS: $(uname -s)"; return 1 2>/dev/null || exit 1 ;; esac
case "$(uname -m)" in arm64|aarch64) _cpu=arm64 ;; x86_64|amd64) _cpu=x86_64 ;;
  *) log_error "unsupported arch: $(uname -m)"; return 1 2>/dev/null || exit 1 ;; esac

_base="${_root}/prebuilts/clang/ohos/${_os}-${_cpu}"

# Prefer llvm/ symlink, then newest clang-* dir.
if [ -d "${_base}/llvm/bin" ]; then
  _bin="${_base}/llvm/bin"
elif _bin="$(ls -d "${_base}"/clang-*/bin 2>/dev/null | sort -V | tail -1)" && [ -d "$_bin" ]; then
  :
else
  log_error "no clang under ${_base} (run env_prepare.sh first)"
  return 1 2>/dev/null || exit 1
fi

export CC="${_bin}/clang"
export CXX="${_bin}/clang++"

# Linux: OH prebuilt clang links against its bundled libc++.
if [ "$(uname -s)" = "Linux" ]; then
  _cr="$(cd "${_bin}/.." && pwd -P)"
  for _d in "$_cr/lib/x86_64-unknown-linux-gnu" "$_cr/lib/x86_64-linux-gnu" "$_cr/lib64" "$_cr/lib"; do
    [ -d "$_d" ] && LD_LIBRARY_PATH="${_d}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  done
  export LD_LIBRARY_PATH
fi

log_info "ccache: CC=$CC  CCACHE_DIR=$CCACHE_DIR  maxsize=$CCACHE_MAXSIZE"
return 0 2>/dev/null || exit 0
