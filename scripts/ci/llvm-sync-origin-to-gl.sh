#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${LLVM_SYNC_REPO_DIR:-$HOME/git/ci/llvm-project-kmp}"
BRANCH="${LLVM_SYNC_BRANCH:-kmp-llvm-19.1.4}"
ORIGIN_REMOTE="${LLVM_SYNC_ORIGIN_REMOTE:-origin}"
GL_REMOTE="${LLVM_SYNC_GL_REMOTE:-gl}"

export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"

echo "Sync start: repo=${REPO_DIR} branch=${BRANCH}"
cd "${REPO_DIR}"

git fetch "${ORIGIN_REMOTE}" "${BRANCH}"
git checkout -B "${BRANCH}" "${ORIGIN_REMOTE}/${BRANCH}"
git reset --hard "${ORIGIN_REMOTE}/${BRANCH}"

if ! git push "${GL_REMOTE}" "${BRANCH}" --force; then
  origin_sha="$(git rev-parse "${ORIGIN_REMOTE}/${BRANCH}")"
  gl_sha="$(git ls-remote "${GL_REMOTE}" "refs/heads/${BRANCH}" | cut -f1 || true)"
  if [[ -n "${gl_sha}" && "${origin_sha}" == "${gl_sha}" ]]; then
    echo "Push returned non-zero but refs already aligned: ${origin_sha}"
  else
    echo "Push failed and refs differ: origin=${origin_sha} gl=${gl_sha}" >&2
    exit 1
  fi
fi

origin_sha="$(git rev-parse "${ORIGIN_REMOTE}/${BRANCH}")"
gl_sha="$(git ls-remote "${GL_REMOTE}" "refs/heads/${BRANCH}" | cut -f1)"
if [[ "${origin_sha}" != "${gl_sha}" ]]; then
  echo "Post-push verification failed: origin=${origin_sha} gl=${gl_sha}" >&2
  exit 1
fi

echo "Sync OK: ${origin_sha}"
