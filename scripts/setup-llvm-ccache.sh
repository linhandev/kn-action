#!/usr/bin/env bash
# Source before running OH toolchain/llvm-project/llvm-build/build.sh when ccache is available.
# Uses only OH prebuilts Clang (env_prepare layout); no host gcc/clang fallback.
# Self-hosted layout: Linux Docker job should keep CCACHE_DIR inside CI_PROJECT_DIR (bind-mounted).
# macOS can use ~/runner/cache so caches survive workspace wipes unrelated to llvm/.
#
# Usage: source "$CI_PROJECT_DIR/scripts/setup-llvm-ccache.sh"
# Intentionally no "set -e" here — this file is sourced from CI steps.

if ! command -v ccache >/dev/null 2>&1; then
  echo "ccache not on PATH; skipping compiler cache (install ccache for faster rebuilds)." >&2
  return 0 2>/dev/null || exit 0
fi

# Prefer uname so GitLab (no RUNNER_OS) and GitHub Actions both behave.
SYS="$(uname -s)"
ARCH="${CI_RUNNER_ARCH:-$(uname -m)}"
: "${CI_PROJECT_DIR:=}"

if [ "$SYS" = "Linux" ] && [ -n "${CI_PROJECT_DIR}" ]; then
  export CCACHE_DIR="${CI_PROJECT_DIR}/.ccache"
else
  CR="${HOME}/runner/cache/llvm-ccache-${SYS}-${ARCH}"
  mkdir -p "$CR"
  export CCACHE_DIR="$CR"
fi

export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-50G}"
export CCACHE_COMPRESS="${CCACHE_COMPRESS:-1}"

# Real compiler paths + CMAKE_*_COMPILER_LAUNCHER only — never CC="ccache clang" (CMake may
# treat the compiler as a single token and break ASM).
#
# OH env_prepare.sh installs host Clang under prebuilts/clang/ohos/<host>-<cpu>/clang-<ver>/
# (see toolchain/llvm-project/llvm-build/env_prepare.sh).
llvm_ccache_prebuilt_clang() {
  local root="${LLVM_WORKSPACE:-}"
  if [ -z "$root" ] && [ -n "${CI_PROJECT_DIR:-}" ]; then
    root="${CI_PROJECT_DIR}/llvm"
  fi
  if [ -z "$root" ]; then
    echo "ccache: LLVM_WORKSPACE or CI_PROJECT_DIR must be set to find prebuilts." >&2
    return 1
  fi

  local hp hc
  case "$(uname -s)" in
    Linux) hp=linux ;;
    Darwin) hp=darwin ;;
    *)
      echo "ccache: unsupported host OS: $(uname -s)" >&2
      return 1
      ;;
  esac
  case "$(uname -m)" in
    arm64 | aarch64) hc=arm64 ;;
    x86_64 | amd64) hc=x86_64 ;;
    *)
      echo "ccache: unsupported host CPU: $(uname -m)" >&2
      return 1
      ;;
  esac

  local base="${root}/prebuilts/clang/ohos/${hp}-${hc}"
  if [ ! -d "$base" ]; then
    echo "ccache: missing OH prebuilts Clang dir: $base (run env_prepare.sh first)." >&2
    return 1
  fi

  local clang_root=""
  if [ -e "${base}/llvm" ]; then
    clang_root="$(cd "${base}/llvm" && pwd -P)" || return 1
  else
    local _d
    _d="$(ls -d "${base}"/clang-* 2>/dev/null | sort -V | tail -n 1)"
    if [ -z "$_d" ] || [ ! -d "$_d" ]; then
      echo "ccache: no clang-* under $base" >&2
      return 1
    fi
    clang_root="$_d"
  fi

  local cc cxx
  cc="${clang_root}/bin/clang"
  cxx="${clang_root}/bin/clang++"
  if [ ! -x "$cc" ] || [ ! -x "$cxx" ]; then
    echo "ccache: expected executables at $cc and $cxx" >&2
    return 1
  fi
  printf '%s\n' "$cc"
  printf '%s\n' "$cxx"
  return 0
}

# Host binaries link against libc++ from the OH prebuilt; prepend its lib dirs for the loader.
llvm_ccache_linux_prebuilt_ld_path() {
  local root="${1:?}"
  local acc="" d
  for d in "$root/lib/x86_64-unknown-linux-gnu" "$root/lib/x86_64-linux-gnu" "$root/lib64" "$root/lib"; do
    [ -d "$d" ] || continue
    case ":${acc}:" in
      *":$d:"*) ;;
      *) acc="${acc:+"$acc":}$d" ;;
    esac
  done
  if [ -z "$acc" ]; then
    return 0
  fi
  export LD_LIBRARY_PATH="${acc}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
  echo "ccache: Linux LD_LIBRARY_PATH for OH prebuilt libc++: $acc" >&2
}

if ! _pb="$(llvm_ccache_prebuilt_clang)"; then
  echo "ccache: could not resolve OH prebuilts Clang (see errors above)." >&2
  return 1 2>/dev/null || exit 1
fi

_CC="$(printf '%s\n' "$_pb" | sed -n '1p')"
_CXX="$(printf '%s\n' "$_pb" | sed -n '2p')"
if [ -z "${_CC:-}" ] || [ -z "${_CXX:-}" ]; then
  echo "ccache: internal error resolving prebuilt CC/CXX" >&2
  return 1 2>/dev/null || exit 1
fi

echo "ccache: OH prebuilt clang CC=$_CC" >&2

if [ "$SYS" = "Linux" ]; then
  _root="$(cd "$(dirname "$_CC")/.." && pwd -P)"
  llvm_ccache_linux_prebuilt_ld_path "$_root"
fi

export CC="$_CC"
export CXX="$_CXX"
export CMAKE_C_COMPILER_LAUNCHER=ccache
export CMAKE_CXX_COMPILER_LAUNCHER=ccache

echo "ccache: dir=$CCACHE_DIR maxsize=$CCACHE_MAXSIZE CC=${CC:-} CXX=${CXX:-} launchers=ccache" >&2

return 0 2>/dev/null || exit 0
