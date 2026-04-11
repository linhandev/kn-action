#!/usr/bin/env bash
# Shared CI logger with ANSI colors.

set -euo pipefail

_ci_log_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_ci_log_emit() {
  local level="$1"
  local color="$2"
  shift 2
  local message="$*"
  local line
  line="$(_ci_log_now_utc) [${level}] ${message}"

  printf "%b%s%b\n" "$color" "$line" $'\033[0m' >&2
}

log_info() {
  _ci_log_emit "INFO" $'\033[0;32m' "$@"
}

log_warn() {
  _ci_log_emit "WARN" $'\033[0;33m' "$@"
}

log_error() {
  _ci_log_emit "ERROR" $'\033[0;31m' "$@"
}
