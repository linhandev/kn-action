#!/usr/bin/env bash
# Run the artifact server. Use from launchd or manually.
# Set ARTIFACTS_DIR and PORT in environment if needed.
cd "$(dirname "$0")"
if [ -d .venv ]; then
  source .venv/bin/activate
fi
pip install -q -r requirements.txt
exec python3 -m uvicorn main:app --host 0.0.0.0 --port "${PORT:-8765}"
