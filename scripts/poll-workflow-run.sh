#!/usr/bin/env bash
# Poll a GitHub Actions workflow run until it finishes.
# Exits 1 if run failed/cancelled/skipped/timed_out; 0 only on success.
# If the run has multiple jobs, lists job names and asks the user to select one;
# only that job's status and (on failure) logs are shown.
# On failure, prints the last FAILED_JOB_LOG_LINES lines of log for the selected job.
#
# Usage: poll-workflow-run.sh RUN_ID [--repo OWNER/REPO]
#
# Testing: After editing this script, run the test that triggers a workflow
# and polls until completion:
#   ./scripts/test-poll-workflow-run.sh
#
# Requires: gh CLI (https://cli.github.com/) authenticated, jq (for job listing)

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
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required for job listing. Install jq (e.g. brew install jq)." >&2
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

# Get jobs and optionally ask user to select one when there are multiple
jobs_json=$(gh run view "$RUN_ID" "${REPO_ARG[@]}" --json jobs -q '.jobs' 2>/dev/null) || true
if [[ -z "$jobs_json" || "$jobs_json" == "null" ]]; then
  echo "Run $RUN_ID not found or no access." >&2
  exit 1
fi
job_count=$(echo "$jobs_json" | jq -r 'length')
if [[ "$job_count" -eq 0 ]]; then
  echo "Run $RUN_ID has no jobs." >&2
  exit 1
fi

SELECTED_JOB_ID=""
if [[ "$job_count" -eq 1 ]]; then
  SELECTED_JOB_ID=$(echo "$jobs_json" | jq -r '.[0].databaseId')
  echo "Job: $(echo "$jobs_json" | jq -r '.[0].name')"
else
  echo "Run has $job_count jobs. Select one to poll:"
  for i in $(seq 1 "$job_count"); do
    name=$(echo "$jobs_json" | jq -r ".[$((i-1))].name")
    echo "  $i) $name"
  done
  while true; do
    read -r -p "Job (1-$job_count): " sel
    if [[ "$sel" =~ ^[0-9]+$ && "$sel" -ge 1 && "$sel" -le "$job_count" ]]; then
      SELECTED_JOB_ID=$(echo "$jobs_json" | jq -r ".[$((sel-1))].databaseId")
      echo "Watching: $(echo "$jobs_json" | jq -r ".[$((sel-1))].name")"
      break
    fi
    echo "Enter a number from 1 to $job_count."
  done
fi
echo ""

POLL_TZ="Asia/Shanghai"
last_status=""
last_conclusion=""
last_step=""
echo "Polling run $RUN_ID (job $SELECTED_JOB_ID) every ${POLL_INTERVAL}s (time UTC+8)..."
while true; do
  run_json=$(gh run view "$RUN_ID" "${REPO_ARG[@]}" --json jobs 2>/dev/null) || true
  if [[ -z "$run_json" ]]; then
    echo "Run $RUN_ID not found or no access." >&2
    exit 1
  fi
  job_status=$(echo "$run_json" | jq -r --argjson jid "$SELECTED_JOB_ID" '.jobs[] | select(.databaseId == $jid) | "\(.status)\t\(.conclusion // "unknown")"' 2>/dev/null) || true
  if [[ -z "$job_status" ]]; then
    echo "Job $SELECTED_JOB_ID not found in run $RUN_ID." >&2
    exit 1
  fi
  IFS=$'\t' read -r status conclusion <<< "$job_status"
  conclusion=${conclusion:-unknown}
  current_step=$(echo "$run_json" | jq -r --argjson jid "$SELECTED_JOB_ID" '[.jobs[] | select(.databaseId == $jid) | .steps[]? | select(.status == "in_progress") | .name][0] // empty' 2>/dev/null) || true

  if [[ "$status" != "$last_status" || "$conclusion" != "$last_conclusion" || "$current_step" != "$last_step" ]]; then
    line="$(TZ="$POLL_TZ" date +%H:%M:%S)  status=$status  conclusion=$conclusion"
    [[ -n "$current_step" ]] && line="$line  step=$current_step"
    echo "$line"
    last_status="$status"
    last_conclusion="$conclusion"
    last_step="$current_step"
  fi

  if [[ "$status" == "completed" ]]; then
    case "$conclusion" in
      success) exit 0 ;;
      failure|cancelled|skipped|timed_out)
        run_url=$(gh run view "$RUN_ID" "${REPO_ARG[@]}" --json url -q '.url' 2>/dev/null) || true
        job_name=$(echo "$run_json" | jq -r --argjson jid "$SELECTED_JOB_ID" '.jobs[] | select(.databaseId == $jid) | .name' 2>/dev/null) || true
        step_names=$(echo "$run_json" | jq -r --argjson jid "$SELECTED_JOB_ID" '.jobs[] | select(.databaseId == $jid) | [.steps[] | select(.conclusion == "failure") | .name] | join(", ")' 2>/dev/null) || true
        echo "" >&2
        gh run view "$RUN_ID" "${REPO_ARG[@]}" --job "$SELECTED_JOB_ID" --log-failed 2>/dev/null | tail -n "$FAILED_JOB_LOG_LINES" >&2 || true
        echo "---" >&2
        header="--- Last ${FAILED_JOB_LOG_LINES} lines of failed step log (run_id: $RUN_ID, job: $job_name, job_id: $SELECTED_JOB_ID"
        [[ -n "$step_names" ]] && header="$header, step: $step_names"
        echo "$header) ---" >&2
        if [[ -n "$run_url" ]]; then
          echo "Run detail: ${run_url}/job/${SELECTED_JOB_ID}" >&2
        fi
        exit 1
        ;;
      *)
        exit 1
        ;;
    esac
  fi
  sleep "$POLL_INTERVAL"
done
