#!/usr/bin/env bash
# Source before running OH toolchain/llvm-project/llvm-build/build.sh when ccache is available.
# Self-hosted layout: Linux Docker job should keep CCACHE_DIR inside CI_PROJECT_DIR (bind-mounted).
# macOS can use ~/runner/cache so caches survive workspace wipes unrelated to llvm/.
#
# Usage: source "$CI_PROJECT_DIR/scripts/setup-llvm-ccache.sh"
# Intentionally no "set -e" here — this file is sourced from CI steps.

if ! command -v ccache >/dev/null 2>&1; then
  echo "ccache not on PATH; skipping compiler cache (install ccache for faster rebuilds)."
  return 0 2>/dev/null || exit 0
fi

# Prefer uname so GitLab (no RUNNER_OS) and GitHub Actions both behave.
SYS="$(uname -s)"
ARCH="${CI_RUNNER_ARCH:-$(uname -m)}"
: "${CI_PROJECT_DIR:=}"

if [ "$SYS" = "Linux" ] && [ -n "${CI_PROJECT_DIR}" ]; then
  # Container job: only paths under CI_PROJECT_DIR are reliably persisted on the host mount.
  export CCACHE_DIR="${CI_PROJECT_DIR}/.ccache"
else
  CR="${HOME}/runner/cache/llvm-ccache-${SYS}-${ARCH}"
  mkdir -p "$CR"
  export CCACHE_DIR="$CR"
fi

export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-50G}"
export CCACHE_COMPRESS="${CCACHE_COMPRESS:-1}"

# Ubuntu/Debian: gcc/g++ picked up through ccache wrappers when those compilers are used.
if [ -d /usr/lib/ccache ]; then
  export PATH="/usr/lib/ccache:${PATH}"
fi

# CMake + clang/gcc: prefer explicit ccache prefix so clang-based OH LLVM builds benefit (not only gcc).
if command -v clang >/dev/null 2>&1 && command -v clang++ >/dev/null 2>&1; then
  export CC="ccache clang"
  export CXX="ccache clang++"
elif command -v gcc >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1; then
  export CC="ccache gcc"
  export CXX="ccache g++"
fi

# Newer LLVM CMake flows honor compiler launchers; harmless if unused.
export CMAKE_C_COMPILER_LAUNCHER=ccache
export CMAKE_CXX_COMPILER_LAUNCHER=ccache

echo "ccache: dir=$CCACHE_DIR maxsize=$CCACHE_MAXSIZE CC=${CC:-} CXX=${CXX:-}" >&2

return 0 2>/dev/null || exit 0
