#!/usr/bin/env bash
# Prepare a repo for CI: clone or reuse workspace (optional local reference), resolve
# branch/commit/PR, force to expected state. Outputs HEAD SHA to stdout.
#
# Reusable from any workflow/CI: set env and run; no repo-specific logic.
# Required: REPO_URL. For branch or branch+PR: BRANCH.
# Optional: WORKSPACE_DIR (default ci-workspace), LOCAL_REFERENCE_DIR (default $HOME/git/ci/),
#           COMMIT, PR_NUMBER, MR_REF_TEMPLATE (see below).
# Resolution: COMMIT set -> checkout commit; BRANCH+PR_NUMBER set -> fetch MR ref, merge into branch; else -> checkout BRANCH.
# Local reference: reference path = LOCAL_REFERENCE_DIR / basename(REPO_URL without .git).
# MR ref: when PR_NUMBER is set, fetch uses MR_REF_TEMPLATE (default refs/merge-requests/%s/head for GitLab/GitCode).
#         For GitHub use MR_REF_TEMPLATE='refs/pull/%s/head'.

set -euo pipefail
set -x

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

# optional --reference for clone/fetch when local repo exists to speed up clone/fetch
[[ -n "$LOCAL_REFERENCE_DIR" ]] && LOCAL_REFERENCE_DIR="${LOCAL_REFERENCE_DIR/#\~/$HOME}"
if command -v realpath &>/dev/null; then
  LOCAL_REFERENCE_DIR="$(realpath "$LOCAL_REFERENCE_DIR")"
fi
REFERENCE_REPO="${LOCAL_REFERENCE_DIR}/${REPO_NAME}"
REF_ARGS=()
[[ -d "$REFERENCE_REPO/.git" ]] && REF_ARGS=(--reference "$REFERENCE_REPO")

if [[ -d "$WORKSPACE_DIR/.git" ]]; then
  # Reuse existing clone: fetch and force to desired ref
  cd "$WORKSPACE_DIR"
  git remote set-url origin "$REPO_URL"
  git fetch "${REF_ARGS[@]}" origin
else
  # Fresh clone
  rm -rf "$WORKSPACE_DIR"
  git clone "${REF_ARGS[@]}" "$REPO_URL" "$WORKSPACE_DIR"
  cd "$WORKSPACE_DIR"
fi

if [[ -n "$COMMIT" ]]; then
  git fetch "${REF_ARGS[@]}" origin "$COMMIT"
  git checkout "$COMMIT"
elif [[ -n "$PR_NUMBER" && -n "$BRANCH" ]]; then
  MR_REF=$(printf "$MR_REF_TEMPLATE" "$PR_NUMBER")
  git fetch "${REF_ARGS[@]}" origin "$BRANCH"
  git checkout -B _ci_branch "origin/$BRANCH"
  git fetch "${REF_ARGS[@]}" origin "+${MR_REF}:pr_${PR_NUMBER}"
  git merge "pr_${PR_NUMBER}" --no-edit
else
  [[ -z "$BRANCH" ]] && { echo "BRANCH required for branch build" >&2; exit 1; }
  git fetch "${REF_ARGS[@]}" origin "$BRANCH"
  git checkout -B _ci_branch "origin/$BRANCH"
fi

# Force working tree to match HEAD (runner does not clean workspace between runs)
git clean -dfx
git reset --hard HEAD

# Output for workflow
git rev-parse HEAD
