#!/usr/bin/env bash
# Test script for prepare-repo.sh against test-prepare-repo (SSH and HTTPS).
# Run from repo root: bash .github/actions/prepare-repo/test-prepare-repo.sh
# Requires: git; SSH or HTTPS access to GitCode (linhandev/test-prepare-repo).
# Phases: wo_reference (clean clone, no ref), with_reference (clean clone with ref), action_sequence (reuse workspace).

set -xeuo pipefail

REPO_URL_SSH="git@gitcode.com:linhandev/test-prepare-repo.git"
REPO_URL_HTTPS="https://gitcode.com/linhandev/test-prepare-repo.git"
REPO_URL=""   # set in loop
WORKSPACE_DIR="/tmp/test-script-workspace"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_REFERENCE_DIR="${HOME}/git/ci"
COMMIT_REF="41f89c0a66ecb5fb375f15076aba557ddcf2f702"
README_FILE="README.md"

run_prepare_repo() {
  local commit="" branch="" pr_number=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --commit) commit="$2"; shift 2 ;;
      --branch) branch="$2"; shift 2 ;;
      --pr) pr_number="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done
  export REPO_URL WORKSPACE_DIR LOCAL_REFERENCE_DIR
  unset COMMIT BRANCH PR_NUMBER
  [[ -n "$commit" ]] && export COMMIT="$commit"
  [[ -n "$branch" ]] && export BRANCH="$branch"
  [[ -n "$pr_number" ]] && export PR_NUMBER="$pr_number"
  bash "$SCRIPT_DIR/prepare-repo.sh" >/dev/null 2>&1
}

assert_readme_lines() {
  local want="$1"
  local got
  got=$(wc -l < "$WORKSPACE_DIR/$README_FILE")
  if [[ "$got" -ne "$want" ]]; then
    echo "FAIL: $README_FILE has $got lines, expected $want"
    return 1
  fi
  echo "  OK: $README_FILE has $want lines"
}

assert_readme_contains() {
  local str="$1"
  if ! grep -q "$str" "$WORKSPACE_DIR/$README_FILE"; then
    echo "FAIL: $README_FILE does not contain '$str'"
    return 1
  fi
  echo "  OK: $README_FILE contains '$str'"
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$WORKSPACE_DIR/$path" ]]; then
    echo "FAIL: $path does not exist"
    return 1
  fi
  echo "  OK: $path exists"
}

# --- wo_reference: clean clone without local reference ---
wo_reference() {
  echo "=== wo_reference: clean clone (no ref) ==="
  mkdir -p "$HOME/git/ci"
  rm -rf "$HOME/git/ci/test-prepare-repo"

  echo "Test 1: commit $COMMIT_REF (README 2 lines)"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --commit "$COMMIT_REF"
  assert_readme_lines 2

  echo "Test 2: branch main (README contains 'an edit since pr')"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --branch main
  assert_readme_contains "an edit since pr"

  echo "Test 3: main + PR 1 (README contains 'an edit since pr', pr_edit.md exists)"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --branch main --pr 1
  assert_readme_contains "an edit since pr"
  assert_file_exists "pr_edit.md"
}

# --- with_reference: clean clone with local reference ---
with_reference() {
  echo "=== with_reference: clean clone (with ref) ==="
  mkdir -p "$HOME/git/ci"
  if [[ ! -d "$HOME/git/ci/test-prepare-repo/.git" ]]; then
    git clone "$REPO_URL" "$HOME/git/ci/test-prepare-repo"
  fi

  echo "Test 1: commit (with ref)"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --commit "$COMMIT_REF"
  assert_readme_lines 2

  echo "Test 2: branch main (with ref)"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --branch main
  assert_readme_contains "an edit since pr"

  echo "Test 3: main + PR 1 (with ref)"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --branch main --pr 1
  assert_readme_contains "an edit since pr"
  assert_file_exists "pr_edit.md"
}

# --- action_sequence: reuse workspace (first then second in same workspace) ---
action_sequence() {
  echo "=== action_sequence: reuse workspace ==="
  # Ref already exists from with_reference; reuse workspace across each pair

  echo "Sequence 1 then 2"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --commit "$COMMIT_REF"
  assert_readme_lines 2
  run_prepare_repo --branch main
  assert_readme_contains "an edit since pr"

  echo "Sequence 1 then 3"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --commit "$COMMIT_REF"
  assert_readme_lines 2
  run_prepare_repo --branch main --pr 1
  assert_readme_contains "an edit since pr"
  assert_file_exists "pr_edit.md"

  echo "Sequence 2 then 1"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --branch main
  assert_readme_contains "an edit since pr"
  run_prepare_repo --commit "$COMMIT_REF"
  assert_readme_lines 2

  echo "Sequence 2 then 3"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --branch main
  assert_readme_contains "an edit since pr"
  run_prepare_repo --branch main --pr 1
  assert_readme_contains "an edit since pr"
  assert_file_exists "pr_edit.md"

  echo "Sequence 3 then 1"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --branch main --pr 1
  assert_readme_contains "an edit since pr"
  assert_file_exists "pr_edit.md"
  run_prepare_repo --commit "$COMMIT_REF"
  assert_readme_lines 2

  echo "Sequence 3 then 2"
  rm -rf "$WORKSPACE_DIR"
  run_prepare_repo --branch main --pr 1
  assert_readme_contains "an edit since pr"
  assert_file_exists "pr_edit.md"
  run_prepare_repo --branch main
  assert_readme_contains "an edit since pr"
}

for REPO_URL in "$REPO_URL_SSH" "$REPO_URL_HTTPS"; do
  echo "========== Remote: $REPO_URL =========="
  wo_reference
  with_reference
  action_sequence
done
echo "All tests passed."
