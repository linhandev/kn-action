#!/usr/bin/env bash
# Install Google's repo launcher under $REPO_DIR (default: $GITHUB_WORKSPACE/bin).
# Upstream repo-py3 uses `#!/usr/bin/env python`; Windows Git Bash often has no `python`
# on PATH — we keep the script as repo.py and write a small `repo` wrapper.
set -euo pipefail

REPO_DIR="${REPO_DIR:-${GITHUB_WORKSPACE:?GITHUB_WORKSPACE must be set}/bin}"
REPO_SCRIPT="$REPO_DIR/repo.py"
REPO_WRAPPER="$REPO_DIR/repo"
REPO_DOWNLOAD_URL="${REPO_DOWNLOAD_URL:-https://gitee.com/oschina/repo/raw/fork_flow/repo-py3}"

mkdir -p "$REPO_DIR"

if [ -f "$REPO_WRAPPER" ] && [ ! -f "$REPO_SCRIPT" ]; then
  mv "$REPO_WRAPPER" "$REPO_SCRIPT"
fi

if [ ! -f "$REPO_SCRIPT" ]; then
  curl -fSL -o "$REPO_SCRIPT" "$REPO_DOWNLOAD_URL"
  head -c 2 "$REPO_SCRIPT" | grep -q '#!' || {
    echo "::error::Downloaded repo script invalid (no shebang)"
    exit 1
  }
fi

PY_CMD=""
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then PY_CMD="$c"; break; fi
done
if [ -z "$PY_CMD" ]; then
  echo "::error::python3, python, or py (Windows) not found"
  exit 1
fi

if [ "$PY_CMD" = "py" ]; then
  py -3 -m pip install requests || py -3 -m pip install --user requests
else
  "$PY_CMD" -m pip install requests || "$PY_CMD" -m pip install --user requests
fi

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' \
  'if command -v python3 >/dev/null 2>&1; then exec python3 "$_dir/repo.py" "$@"; fi' \
  'if command -v python >/dev/null 2>&1; then exec python "$_dir/repo.py" "$@"; fi' \
  'if command -v py >/dev/null 2>&1; then exec py -3 "$_dir/repo.py" "$@"; fi' \
  'echo "::error::no python for repo"; exit 1' \
  > "$REPO_WRAPPER"

chmod a+x "$REPO_WRAPPER" "$REPO_SCRIPT"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$REPO_DIR" >> "$GITHUB_PATH"
fi

export PATH="$REPO_DIR:$PATH"
repo --version
