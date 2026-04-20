#!/usr/bin/env bash
# Install Google's repo launcher into $REPO_DIR (default: $CI_PROJECT_DIR/bin).
# repo.py is cached at a fixed path so it survives Docker container recycling.
#
# Python strategy (per-host):
#   macOS:  /usr/bin/python3 (system); `requests` via pip --user (pre-installed on runners)
#   Linux Docker: python3 from image (requests pre-installed in Dockerfile)
#   Windows: python via Git Bash PATH (requests pre-installed via `python -m pip install requests`)
set -euo pipefail

: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set}"
REPO_DIR="${REPO_DIR:-${CI_PROJECT_DIR}/bin}"
REPO_SCRIPT="$REPO_DIR/repo.py"
REPO_WRAPPER="$REPO_DIR/repo"
REPO_DOWNLOAD_URL="${REPO_DOWNLOAD_URL:-https://gitee.com/oschina/repo/raw/fork_flow/repo-py3}"
REPO_CACHE="${HOME}/gitlab-runner/cache/repo.py"

mkdir -p "$REPO_DIR" "$(dirname "$REPO_CACHE")"

# Legacy: rename bare `repo` to `repo.py` if someone left a raw copy.
[ -f "$REPO_WRAPPER" ] && [ ! -f "$REPO_SCRIPT" ] && mv "$REPO_WRAPPER" "$REPO_SCRIPT"

# Pick a working Python 3. macOS/Linux: python3. Windows (Git Bash): python, then py -3.
pick_py() { command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1; }

PY=""
if pick_py python3; then PY=python3
elif pick_py python; then PY=python
elif command -v py >/dev/null 2>&1 && py -3 --version >/dev/null 2>&1; then PY="py -3"
fi
[ -n "$PY" ] || { echo "No usable Python 3 found"; exit 1; }

# Restore from persistent cache, or download once.
if [ ! -f "$REPO_SCRIPT" ]; then
  if [ -f "$REPO_CACHE" ]; then
    cp "$REPO_CACHE" "$REPO_SCRIPT"
  else
    curl -fSL -sS --connect-timeout 30 -o "$REPO_SCRIPT" "$REPO_DOWNLOAD_URL"
    cp "$REPO_SCRIPT" "$REPO_CACHE" 2>/dev/null || true
  fi
  head -c 2 "$REPO_SCRIPT" | grep -q '#!' || { echo "Invalid repo script (no shebang)"; exit 1; }
fi

# Ensure requests is available (repo.py imports it).
has_requests() {
  case "$PY" in
    "py -3") py -3 -c "import requests" >/dev/null 2>&1 ;;
    *) $PY -c "import requests" >/dev/null 2>&1 ;;
  esac
}
if ! has_requests; then
  case "$PY" in
    "py -3") py -3 -m pip install --user -q requests 2>/dev/null \
             || py -3 -m pip install --break-system-packages -q requests ;;
    *)       $PY -m pip install --user -q requests 2>/dev/null \
             || $PY -m pip install --break-system-packages -q requests ;;
  esac
fi

# Create a bash wrapper that invokes repo.py with the resolved Python.
cat > "$REPO_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
_dir="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec $PY "\$_dir/repo.py" "\$@"
EOF
chmod a+x "$REPO_WRAPPER" "$REPO_SCRIPT"

export PATH="$REPO_DIR:$PATH"
repo --version