#!/usr/bin/env bash
# Wrapper for .github/actions/download-artifact-local/download.sh (GitLab / shell).
set -euo pipefail
: "${CI_PROJECT_DIR:?}"

usage() {
  echo "usage: $0 (--name=ARTIFACT|--pattern=REGEX) [--dir=OUTPUT_DIR]"
  exit 1
}

NAME=""
PATTERN=""
OUT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name=*) NAME="${1#*=}" ;;
    --pattern=*) PATTERN="${1#*=}" ;;
    --dir=*) OUT_DIR="${1#*=}" ;;
    *) usage ;;
  esac
  shift
done

if [ -z "$NAME" ] && [ -z "$PATTERN" ]; then
  usage
fi
if [ -n "$NAME" ] && [ -n "$PATTERN" ]; then
  echo "Set only one of --name or --pattern"
  exit 1
fi

export INPUT_SERVER_URL="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
CACHE="${ARTIFACT_LOCAL_PATH:-$HOME/runner/artifact}"
export INPUT_CACHE_DIR="${CACHE/#\~/$HOME}"
export INPUT_NAME="$NAME"
export INPUT_PATTERN="$PATTERN"
export INPUT_PATH="${OUT_DIR:-$INPUT_CACHE_DIR}"
# shellcheck source=/dev/null
source "$CI_PROJECT_DIR/.github/actions/download-artifact-local/download.sh"
