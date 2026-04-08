#!/usr/bin/env bash
# Prepare a repo for CI: clone or reuse workspace (optional local reference), resolve
# branch/commit/PR, force to expected state. Outputs HEAD SHA to stdout.
#
# Reusable from any workflow/CI: set env and run; no repo-specific logic.
# Required: REPO_URL. For branch or branch+PR: BRANCH.
# Optional: WORKSPACE_DIR (default ci-workspace), LOCAL_REFERENCE_DIR (default $HOME/git/ci/),
#           COMMIT, PR_NUMBER, MR_REF_TEMPLATE (see below).
# Resolution: COMMIT set -> checkout + hard reset to commit; BRANCH+PR_NUMBER -> hard reset to origin/BRANCH then merge MR; else -> branch + hard reset.
# Local reference: reference path = LOCAL_REFERENCE_DIR / basename(REPO_URL without .git).
# MR ref: when PR_NUMBER is set, fetch uses MR_REF_TEMPLATE (default refs/merge-requests/%s/head for GitLab/GitCode).
#         For GitHub use MR_REF_TEMPLATE='refs/pull/%s/head'.

set -euo pipefail

# Remove stale lock files in an existing git worktree.
# Self-hosted runners reuse workspace directories; interrupted jobs can leave .lock files behind.
clear_stale_git_locks() {
  local repo_dir="${1:-.}" git_dir lock
  git_dir="$(git -C "$repo_dir" rev-parse --git-dir 2>/dev/null || true)"
  [[ -z "$git_dir" ]] && return 0

  for lock in \
    "$git_dir/index.lock" \
    "$git_dir/shallow.lock" \
    "$git_dir/packed-refs.lock" \
    "$git_dir/config.lock" \
    "$git_dir/HEAD.lock" \
    "$git_dir/FETCH_HEAD.lock" \
    "$git_dir/refs/heads/"*.lock \
    "$git_dir/refs/remotes/"*.lock; do
    [[ -e "$lock" ]] || continue
    echo "prepare-repo: removing stale lock: $lock" >&2
    rm -f "$lock"
  done
}

# GitCode SSH clones occasionally drop mid-transfer on long fetches; retry a few times.
git_with_retry() {
  local max="${GIT_RETRY_MAX:-4}" delay="${GIT_RETRY_DELAY_SEC:-45}" n=1
  local errf repo_dir
  errf="$(mktemp)"

  repo_dir="."
  if [[ "$1" == "-C" && $# -ge 2 ]]; then
    repo_dir="$2"
  fi

  # Pre-clean stale locks in reused worktrees before the first attempt.
  clear_stale_git_locks "$repo_dir"

  while true; do
    if "$@" 2>"$errf"; then
      rm -f "$errf"
      return 0
    fi
    if grep -E -q 'Another git process seems to be running|Unable to create .*\.lock|cannot lock ref' "$errf"; then
      clear_stale_git_locks "$repo_dir"
    fi
    if [ "$n" -ge "$max" ]; then
      cat "$errf" >&2
      rm -f "$errf"
      return 1
    fi
    cat "$errf" >&2
    echo "prepare-repo: git failed (${n}/$((max - 1))), retry in ${delay}s: $*" >&2
    sleep "$delay"
    n=$((n + 1))
  done
}

# Short retries for local git ops (clean/checkout/reset/merge) that are not covered by git_with_retry.
# Reused self-hosted trees can still hit stale index.lock on these commands.
git_lock_retry() {
  local repo_dir="${1:?}" errf n=1 max=4 delay="${GIT_LOCK_RETRY_DELAY_SEC:-5}"
  shift
  errf="$(mktemp)"
  while true; do
    clear_stale_git_locks "$repo_dir"
    if git -C "$repo_dir" "$@" 2>"$errf"; then
      rm -f "$errf"
      return 0
    fi
    if grep -E -q 'Another git process seems to be running|Unable to create .*\.lock|cannot lock ref' "$errf"; then
      cat "$errf" >&2
      rm -f "$errf"
      if [[ "$n" -ge "$max" ]]; then
        return 1
      fi
      echo "prepare-repo: git lock retry (${n}/$((max - 1))): git -C \"$repo_dir\" $*" >&2
      sleep "$delay"
      n=$((n + 1))
      continue
    fi
    cat "$errf" >&2
    rm -f "$errf"
    return 1
  done
}

# Git for Windows: Kotlin contains paths >260 chars; without this, clone/clean/checkout errors with
# "Filename too long" and leaves a dirty tree ("untracked files would be overwritten by checkout").
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) git config --global core.longpaths true ;;
esac

REPO_URL="${REPO_URL:?}"
BRANCH="${BRANCH:-}"
COMMIT="${COMMIT:-}"
PR_NUMBER="${PR_NUMBER:-}"

WORKSPACE_DIR="${WORKSPACE_DIR:-ci-workspace}"
LOCAL_REFERENCE_DIR="${LOCAL_REFERENCE_DIR:-$HOME/git/ci/}"
MR_REF_TEMPLATE="${MR_REF_TEMPLATE:-refs/merge-requests/%s/head}"

# Repo name from URL for local reference path
REPO_NAME="${REPO_URL##*/}"
REPO_NAME="${REPO_NAME%.git}"

# optional --reference for speeding up cloning when local repo exists
[[ -n "$LOCAL_REFERENCE_DIR" ]] && LOCAL_REFERENCE_DIR="${LOCAL_REFERENCE_DIR/#\~/$HOME}"
# Only resolve realpath when the directory exists (e.g. CI may pass a path that is created later)
if [[ -d "$LOCAL_REFERENCE_DIR" ]] && command -v realpath &>/dev/null; then
  LOCAL_REFERENCE_DIR="$(realpath "$LOCAL_REFERENCE_DIR")"
fi
REFERENCE_REPO="${LOCAL_REFERENCE_DIR}/${REPO_NAME}"

# Windows: failed runs can leave paths git clean cannot fix; drop the tree and use fresh clone below.
if [[ -d "$WORKSPACE_DIR/.git" ]]; then
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
      if ! git_lock_retry "$WORKSPACE_DIR" clean -ffdx; then
        echo "prepare-repo: git clean failed in reused workspace; recloning: $WORKSPACE_DIR" >&2
        rm -rf "$WORKSPACE_DIR"
      fi
      ;;
  esac
fi

if [[ -d "$WORKSPACE_DIR/.git" ]]; then
  # Reuse existing clone: fetch and force to desired ref
  cd "$WORKSPACE_DIR"
  git_lock_retry . remote set-url origin "$REPO_URL"
  git_with_retry git fetch origin
else
  # Fresh clone (optionally with --reference-if-able / --reference)
  attempt=1
  max_attempts=4
  clone_delay=45
  while [[ "$attempt" -le "$max_attempts" ]]; do
    rm -rf "$WORKSPACE_DIR"
    clone_ok=0
    if [[ -d "$REFERENCE_REPO/.git" ]]; then
      if GIT_PAGER=cat git clone -h 2>&1 | grep -qF -- '--reference-if-able'; then
        if git clone --reference-if-able "$REFERENCE_REPO" "$REPO_URL" "$WORKSPACE_DIR"; then
          clone_ok=1
        fi
      else
        if git clone --reference "$REFERENCE_REPO" "$REPO_URL" "$WORKSPACE_DIR"; then
          clone_ok=1
        fi
      fi
    else
      if git clone "$REPO_URL" "$WORKSPACE_DIR"; then
        clone_ok=1
      fi
    fi
    if [[ "$clone_ok" -eq 1 ]]; then
      break
    fi
    if [[ "$attempt" -eq "$max_attempts" ]]; then
      echo "prepare-repo: git clone failed after ${max_attempts} attempts" >&2
      exit 1
    fi
    echo "prepare-repo: clone failed (${attempt}/$((max_attempts - 1))), retry in ${clone_delay}s" >&2
    sleep "$clone_delay"
    attempt=$((attempt + 1))
  done
  cd "$WORKSPACE_DIR"
fi

# Drop stale merge/rebase state from a previous failed run (self-hosted reuse).
git merge --abort 2>/dev/null || true
git rebase --abort 2>/dev/null || true
git cherry-pick --abort 2>/dev/null || true

# Gitignored untracked paths (.idea/, etc.) block checkout unless removed (-x).
git_lock_retry . clean -ffdx

if [[ -n "$COMMIT" ]]; then
  git_with_retry git fetch origin "$COMMIT"
  git_lock_retry . checkout "$COMMIT"
  git_lock_retry . reset --hard "$COMMIT"
  git_lock_retry . clean -ffdx
elif [[ -n "$PR_NUMBER" && -n "$BRANCH" ]]; then
  MR_REF=$(printf "$MR_REF_TEMPLATE" "$PR_NUMBER")
  git_with_retry git fetch origin "$BRANCH"
  git_lock_retry . checkout -B _ci_branch "origin/$BRANCH"
  # checkout -B can leave local edits when HEAD already matches the remote; merge then conflicts.
  git_lock_retry . reset --hard "origin/$BRANCH"
  git_lock_retry . clean -ffdx
  git_with_retry git fetch origin "+${MR_REF}:pr_${PR_NUMBER}"
  git config user.email "ci@localhost"
  git config user.name "CI"
  git_lock_retry . merge "pr_${PR_NUMBER}" --no-edit
else
  [[ -z "$BRANCH" ]] && { echo "BRANCH required for branch build" >&2; exit 1; }
  git_with_retry git fetch origin "$BRANCH"
  git_lock_retry . checkout -B _ci_branch "origin/$BRANCH"
  git_lock_retry . reset --hard "origin/$BRANCH"
  git_lock_retry . clean -ffdx
fi

# Force working tree to match HEAD (runner does not clean workspace between runs)
git_lock_retry . clean -ffdx
git_lock_retry . reset --hard HEAD

# Output for workflow
git rev-parse HEAD
