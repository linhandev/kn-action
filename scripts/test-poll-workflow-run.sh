#!/usr/bin/env bash
# Test script for poll-workflow-run.sh: trigger test-prepare-repo workflow and poll until it finishes.
# Run this after editing scripts/poll-workflow-run.sh to verify trigger + poll + failure log output.
#
# Usage: test-poll-workflow-run.sh [--repo OWNER/REPO]
# Requires: gh CLI authenticated

set -e

SCRIPT_DIR="${BASH_SOURCE%/*}"
POLL_SCRIPT="${SCRIPT_DIR}/poll-workflow-run.sh"
WORKFLOW="test-prepare-repo.yml"
REPO_ARG=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_ARG=(--repo "$2")
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      echo "Unexpected argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI is required. Install from https://cli.github.com/" >&2
  exit 1
fi

echo "Triggering workflow: $WORKFLOW"
out=$(gh workflow run "$WORKFLOW" "${REPO_ARG[@]}" 2>&1) || true
RUN_ID=""
if [[ "$out" =~ /runs/([0-9]+) ]]; then
  RUN_ID="${BASH_REMATCH[1]}"
  echo "Run ID from trigger: $RUN_ID"
fi
if [[ -z "$RUN_ID" ]]; then
  echo "Waiting for run to appear in list..."
  sleep 3
  RUN_ID=$(gh run list --workflow="$WORKFLOW" "${REPO_ARG[@]}" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null) || true
fi
if [[ -z "$RUN_ID" ]]; then
  echo "Could not get run ID after triggering workflow." >&2
  exit 1
fi

echo "Polling until run $RUN_ID finishes..."
exec "$POLL_SCRIPT" "$RUN_ID" "${REPO_ARG[@]}"
