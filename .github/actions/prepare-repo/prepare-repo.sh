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
      if ! git -C "$WORKSPACE_DIR" clean -dfx; then
        echo "prepare-repo: git clean failed in reused workspace; recloning: $WORKSPACE_DIR" >&2
        rm -rf "$WORKSPACE_DIR"
      fi
      ;;
  esac
fi

if [[ -d "$WORKSPACE_DIR/.git" ]]; then
  # Reuse existing clone: fetch and force to desired ref
  cd "$WORKSPACE_DIR"
  git remote set-url origin "$REPO_URL"
  git fetch origin
else
  # Fresh clone (optionally with --reference-if-able / --reference)
  rm -rf "$WORKSPACE_DIR"
  if [[ -d "$REFERENCE_REPO/.git" ]]; then
    if GIT_PAGER=cat git clone -h 2>&1 | grep -qF -- '--reference-if-able'; then
      git clone --reference-if-able "$REFERENCE_REPO" "$REPO_URL" "$WORKSPACE_DIR"
    else
      git clone --reference "$REFERENCE_REPO" "$REPO_URL" "$WORKSPACE_DIR"
    fi
  else
    git clone "$REPO_URL" "$WORKSPACE_DIR"
  fi
  cd "$WORKSPACE_DIR"
fi

# Drop stale merge/rebase state from a previous failed run (self-hosted reuse).
git merge --abort 2>/dev/null || true
git rebase --abort 2>/dev/null || true
git cherry-pick --abort 2>/dev/null || true

# Reused workspaces often accumulate gitignored untracked trees (.idea/, local tooling). Plain
# `git clean -df` skips ignored files, so `git checkout` / `checkout -B` can fail with
# "untracked working tree files would be overwritten by checkout" (seen on Windows kotlin runners).
git clean -ffdx

if [[ -n "$COMMIT" ]]; then
  git fetch origin "$COMMIT"
  git checkout "$COMMIT"
  git reset --hard "$COMMIT"
  git clean -dfx
elif [[ -n "$PR_NUMBER" && -n "$BRANCH" ]]; then
  MR_REF=$(printf "$MR_REF_TEMPLATE" "$PR_NUMBER")
  git fetch origin "$BRANCH"
  git checkout -B _ci_branch "origin/$BRANCH"
  # checkout -B can leave local edits when HEAD already matches the remote; merge then conflicts.
  git reset --hard "origin/$BRANCH"
  git clean -dfx
  git fetch origin "+${MR_REF}:pr_${PR_NUMBER}"
  git config user.email "ci@localhost"
  git config user.name "CI"
  git merge "pr_${PR_NUMBER}" --no-edit
else
  [[ -z "$BRANCH" ]] && { echo "BRANCH required for branch build" >&2; exit 1; }
  git fetch origin "$BRANCH"
  git checkout -B _ci_branch "origin/$BRANCH"
  git reset --hard "origin/$BRANCH"
  git clean -dfx
fi

# Force working tree to match HEAD (runner does not clean workspace between runs)
git clean -dfx
git reset --hard HEAD

# Output for workflow
git rev-parse HEAD
