#!/usr/bin/env bash
# Poll a GitHub Actions workflow run until it finishes.
# Exits 1 if run failed/cancelled/skipped/timed_out; 0 only on success.
# On failure, prints the last FAILED_JOB_LOG_LINES lines of log for each failed job.
#
# Usage: poll-workflow-run.sh RUN_ID [--repo OWNER/REPO]
#
# Testing: After editing this script, run the test that triggers a workflow
# and polls until completion:
#   ./scripts/test-poll-workflow-run.sh
#
# Requires: gh CLI (https://cli.github.com/) authenticated

set -e

POLL_INTERVAL=10
FAILED_JOB_LOG_LINES=64
RUN_ID=""
REPO_ARG=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0 RUN_ID [--repo OWNER/REPO]"
      echo "  RUN_ID  Workflow run ID (required)"
      echo "  --repo  OWNER/REPO (default: current git remote)"
      echo ""
      echo "Test: run ./scripts/test-poll-workflow-run.sh after editing this script"
      exit 0
      ;;
    --repo)
      REPO_ARG=(--repo "$2")
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$RUN_ID" ]]; then
        RUN_ID="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$RUN_ID" ]]; then
  echo "Usage: $0 RUN_ID [--repo OWNER/REPO]" >&2
  exit 1
fi

if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI is required. Install from https://cli.github.com/" >&2
  exit 1
fi

# Print workflow details once at start (one API call)
details=$(gh run view "$RUN_ID" "${REPO_ARG[@]}" --json displayTitle,workflowName,event -q '[.displayTitle, .workflowName, .event] | @tsv' 2>/dev/null) || true
if [[ -n "$details" ]]; then
  IFS=$'\t' read -r title wfname event <<< "$details"
  echo "Workflow: $wfname"
  echo "Title:    $title"
  echo "Trigger:  $event"
  echo ""
fi

last_status=""
last_conclusion=""
echo "Polling run $RUN_ID every ${POLL_INTERVAL}s..."
while true; do
  status=$(gh run view "$RUN_ID" "${REPO_ARG[@]}" --json status,conclusion -q '.status' 2>/dev/null) || true
  if [[ -z "$status" ]]; then
    echo "Run $RUN_ID not found or no access." >&2
    exit 1
  fi
  conclusion=$(gh run view "$RUN_ID" "${REPO_ARG[@]}" --json status,conclusion -q '.conclusion // "unknown"' 2>/dev/null) || true
  conclusion=${conclusion:-unknown}

  if [[ "$status" != "$last_status" || "$conclusion" != "$last_conclusion" ]]; then
    echo "$(date -u +%H:%M:%S)  status=$status  conclusion=$conclusion"
    last_status="$status"
    last_conclusion="$conclusion"
  fi

  if [[ "$status" == "completed" ]]; then
    case "$conclusion" in
      success) exit 0 ;;
      failure|cancelled|skipped|timed_out)
        # Output last N lines of log for failed step(s) only (no Post/Complete job steps)
        while read -r job_id; do
          [[ -z "$job_id" ]] && continue
          job_name=$(gh run view "$RUN_ID" "${REPO_ARG[@]}" --json jobs -q ".jobs[] | select(.databaseId == $job_id) | .name" 2>/dev/null) || true
          echo "" >&2
          echo "--- Last ${FAILED_JOB_LOG_LINES} lines of failed step log for job: $job_name (id: $job_id) ---" >&2
          gh run view "$RUN_ID" "${REPO_ARG[@]}" --job "$job_id" --log-failed 2>/dev/null | tail -n "$FAILED_JOB_LOG_LINES" >&2 || true
          echo "---" >&2
        done < <(gh run view "$RUN_ID" "${REPO_ARG[@]}" --json jobs -q '.jobs[] | select(.conclusion == "failure") | .databaseId' 2>/dev/null)
        exit 1
        ;;
      *)
        exit 1
        ;;
    esac
  fi
  sleep "$POLL_INTERVAL"
done
