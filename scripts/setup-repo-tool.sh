#!/usr/bin/env bash
# Install Google's repo launcher under $REPO_DIR (default: $CI_PROJECT_DIR/bin).
# GitLab sets CI_PROJECT_DIR to the checked-out project root. Export it when running locally:
#   export CI_PROJECT_DIR="$(git rev-parse --show-toplevel)"
# A tiny bash wrapper runs repo.py with a Python we verified here — avoids relying on
# repo.py's shebang under Git Bash and avoids Windows "python3" app-installer stubs
# (command -v succeeds but the binary is useless).
#
# Docker jobs often start with an empty project bin/; repo.py is also copied from
# REPO_TOOL_CACHE (default ~/runner/cache/kn-action-repo) when set on the host so we
# avoid re-downloading from gitee every run.
set -euo pipefail

: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set (GitLab CI or export for local runs)}"
REPO_DIR="${REPO_DIR:-${CI_PROJECT_DIR}/bin}"
REPO_SCRIPT="$REPO_DIR/repo.py"
REPO_WRAPPER="$REPO_DIR/repo"
REPO_DOWNLOAD_URL="${REPO_DOWNLOAD_URL:-https://gitee.com/oschina/repo/raw/fork_flow/repo-py3}"
REPO_TOOL_CACHE="${REPO_TOOL_CACHE:-${HOME}/runner/cache/kn-action-repo}"
REPO_CACHE_SCRIPT="$REPO_TOOL_CACHE/repo.py"

mkdir -p "$REPO_DIR"
mkdir -p "$REPO_TOOL_CACHE"

if [ -f "$REPO_WRAPPER" ] && [ ! -f "$REPO_SCRIPT" ]; then
  mv "$REPO_WRAPPER" "$REPO_SCRIPT"
fi

# Restore repo.py from persistent runner cache (same layout as ~/runner/cache elsewhere).
if [ ! -f "$REPO_SCRIPT" ] && [ -f "$REPO_CACHE_SCRIPT" ]; then
  cp -a "$REPO_CACHE_SCRIPT" "$REPO_SCRIPT"
  head -c 2 "$REPO_SCRIPT" | grep -q '#!' || {
    echo "::error::Cached repo script invalid (no shebang); removing"
    rm -f "$REPO_SCRIPT"
  }
fi

# Skip download/pip when a working repo is already in this workspace.
if [ -f "$REPO_SCRIPT" ] && [ -f "$REPO_WRAPPER" ]; then
  export PATH="$REPO_DIR:$PATH"
  if repo --version >/dev/null 2>&1; then
    if [ -n "${KNACTION_DOTENV_FILE:-}" ]; then
      printf 'PATH=%s\n' "$REPO_DIR:${PATH}" >>"$KNACTION_DOTENV_FILE"
    fi
    echo "repo tool already present at $REPO_WRAPPER; skipping install"
    exit 0
  fi
fi

if [ ! -f "$REPO_SCRIPT" ]; then
  # -s silent (no progress meter); -S show errors when -s is used
  curl -fSL -sS --connect-timeout 30 -o "$REPO_SCRIPT" "$REPO_DOWNLOAD_URL"
  head -c 2 "$REPO_SCRIPT" | grep -q '#!' || {
    echo "::error::Downloaded repo script invalid (no shebang)"
    exit 1
  }
  cp -a "$REPO_SCRIPT" "$REPO_CACHE_SCRIPT" 2>/dev/null || true
fi

# Pick Python 3 with pip (repo.py needs `requests`). Prefer `python` before `python3` so Linux skips
# /usr/bin/python without pip; Windows job prepends a real install before Store stubs.
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

requests_ok() {
  case "$PY_EXEC" in
    "py -3") py -3 -c "import requests" >/dev/null 2>&1 ;;
    *) "$PY_EXEC" -c "import requests" >/dev/null 2>&1 ;;
  esac
}

if ! requests_ok; then
  # Homebrew / PEP 668 "externally managed" Python may reject plain pip install; last resort for CI.
  case "$PY_EXEC" in
    "py -3")
      py -3 -m pip install -q requests \
        || py -3 -m pip install --user -q requests \
        || py -3 -m pip install --break-system-packages -q requests
      ;;
    *)
      "$PY_EXEC" -m pip install -q requests \
        || "$PY_EXEC" -m pip install --user -q requests \
        || "$PY_EXEC" -m pip install --break-system-packages -q requests
      ;;
  esac
fi

cat > "$REPO_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
_dir="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec $PY_EXEC "\$_dir/repo.py" "\$@"
EOF

chmod a+x "$REPO_WRAPPER" "$REPO_SCRIPT"

# GitLab: optional dotenv file for later steps in the same job (artifacts:reports:dotenv).
if [ -n "${KNACTION_DOTENV_FILE:-}" ]; then
  printf 'PATH=%s\n' "$REPO_DIR:${PATH}" >>"$KNACTION_DOTENV_FILE"
fi

export PATH="$REPO_DIR:$PATH"
repo --version
