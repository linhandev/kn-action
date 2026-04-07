#!/usr/bin/env bash
# Install Google's repo launcher under $REPO_DIR (default: $GITHUB_WORKSPACE/bin).
# A tiny bash wrapper runs repo.py with a Python we verified here — avoids relying on
# repo.py's shebang under Git Bash and avoids Windows "python3" app-installer stubs
# (command -v succeeds but the binary is useless).
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

# Pick Python 3 with pip (repo.py needs `requests`). CI uses actions/setup-python (Unix) or PATH (Windows).
# Prefer `python` before `python3` so Linux skips /usr/bin/python without pip; avoid Windows Store stubs.
pick_py() {
  local c="$1"
  if command -v "$c" >/dev/null 2>&1 && "$c" --version >/dev/null 2>&1 && "$c" -m pip --version >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

PY_EXEC=""
if pick_py python; then
  PY_EXEC="python"
elif pick_py python3; then
  PY_EXEC="python3"
elif command -v py >/dev/null 2>&1 && py -3 --version >/dev/null 2>&1 && py -3 -m pip --version >/dev/null 2>&1; then
  PY_EXEC="py -3"
fi
if [ -z "$PY_EXEC" ]; then
  echo "::error::no usable Python 3 with pip (tried python, python3, py -3)"
  exit 1
fi

case "$PY_EXEC" in
  "py -3")
    py -3 -m pip install requests || py -3 -m pip install --user requests
    ;;
  *)
    "$PY_EXEC" -m pip install requests || "$PY_EXEC" -m pip install --user requests
    ;;
esac

cat > "$REPO_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
_dir="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec $PY_EXEC "\$_dir/repo.py" "\$@"
EOF

chmod a+x "$REPO_WRAPPER" "$REPO_SCRIPT"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$REPO_DIR" >> "$GITHUB_PATH"
fi

export PATH="$REPO_DIR:$PATH"
repo --version
