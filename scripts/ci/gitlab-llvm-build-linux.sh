#!/usr/bin/env bash
# Thin wrapper: Linux X64 leg (Docker image provides deps; see gitlab-llvm-build.sh).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/gitlab-llvm-build.sh" linux
