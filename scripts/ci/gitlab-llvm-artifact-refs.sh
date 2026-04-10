#!/usr/bin/env bash
# Emit llvm-artifact-refs.env (GitLab dotenv) matching GHA llvm-artifact-refs job.
set -euo pipefail
: "${CI_PROJECT_DIR:?}"

META="${CI_PROJECT_DIR}/.llvm-ci-meta"
if [ ! -d "$META" ]; then
  echo "Missing .llvm-ci-meta (build job artifacts)."
  exit 1
fi

shopt -s nullglob
files=("$META"/*.env)
if [ "${#files[@]}" -eq 0 ]; then
  echo "No *.env under $META"
  exit 1
fi

L=""
A=""
first=1
for f in "${files[@]}"; do
  # shellcheck disable=SC1090
  source "$f"
  if [ "$first" = 1 ]; then
    L="${LLVM_SHA_SHORT:-}"
    A="${ACT_SHA_SHORT:-}"
    first=0
  else
    [ "${LLVM_SHA_SHORT:-}" = "$L" ] || {
      echo "LLVM_SHA_SHORT mismatch in $f"
      exit 1
    }
    [ "${ACT_SHA_SHORT:-}" = "$A" ] || {
      echo "ACT_SHA_SHORT mismatch in $f"
      exit 1
    }
  fi
done

if [ -z "$L" ] || [ -z "$A" ]; then
  echo "Empty LLVM or ACT short sha from meta."
  exit 1
fi

OUT="${CI_PROJECT_DIR}/llvm-artifact-refs.env"
{
  echo "OUTER_LINUX_NAME=llvm-packages-${L}_act-${A}_Linux_X64.tar"
  echo "OUTER_MAC_ARM_NAME=llvm-packages-${L}_act-${A}_macOS_ARM64.tar"
  echo "OUTER_MAC_X64_NAME=llvm-packages-${L}_act-${A}_macOS_X64.tar"
} >"$OUT"

echo "Wrote $OUT"
cat "$OUT"
