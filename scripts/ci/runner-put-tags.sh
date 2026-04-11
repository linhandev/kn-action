#!/usr/bin/env bash
# Update GitLab runner tags via API (e.g. fix amd64 → x64 so CI jobs with tags llvm/kotlin, windows, x64 match).
# Run on a host that can reach GitLab (LAN). Needs a token with api scope and permission to edit the runner.
#
# Usage:
#   export GITLAB_URL=http://192.168.3.6:8929
#   export GITLAB_TOKEN=glpat-...
#   bash scripts/ci/runner-put-tags.sh RUNNER_ID tag1,tag2,tag3 [RUNNER_ID tag1,tag2,tag3 ...]
#
# Example (Windows runners from config.toml id fields):
#   bash scripts/ci/runner-put-tags.sh 7 kotlin,windows,x64 8 llvm,windows,x64
set -euo pipefail

GITLAB_URL="${GITLAB_URL:-${CI_SERVER_URL:-}}"
TOKEN="${GITLAB_TOKEN:-${GITLAB_ACCESS_TOKEN:-}}"
if [[ -z "${GITLAB_URL}" || -z "${TOKEN}" ]]; then
  echo "Set GITLAB_URL and GITLAB_TOKEN (or GITLAB_ACCESS_TOKEN)." >&2
  exit 1
fi

if [[ "$#" -lt 2 ]] || [[ $(("$#" % 2)) -ne 0 ]]; then
  echo "usage: $0 RUNNER_ID tags_csv [RUNNER_ID tags_csv ...]" >&2
  exit 1
fi

while [[ "$#" -gt 0 ]]; do
  rid="${1:?}"
  tags_csv="${2:?}"
  shift 2
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tag_list": sys.argv[1].split(",")}))' "$tags_csv")"
  code="$(curl -sS -o /tmp/gitlab-runner-put-tags.body -w "%{http_code}" \
    -X PUT \
    -H "PRIVATE-TOKEN: ${TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "${GITLAB_URL%/}/api/v4/runners/${rid}")"
  if [[ "$code" != "200" && "$code" != "204" ]]; then
    echo "PUT runners/${rid} failed HTTP ${code}" >&2
    cat /tmp/gitlab-runner-put-tags.body >&2 || true
    exit 1
  fi
  echo "OK runners/${rid} tag_list=${tags_csv}"
done
rm -f /tmp/gitlab-runner-put-tags.body
