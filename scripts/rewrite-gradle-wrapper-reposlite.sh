#!/usr/bin/env bash
# Point Gradle wrapper at Reposilite maven repo "gradle-distributions" (same host as /releases).
# Args: <kotlin-repo-root> <gradle-distributions-base-url>
# Example: ./rewrite-gradle-wrapper-reposlite.sh ../ci-workspace http://192.168.3.5:8080/gradle-distributions
set -euo pipefail
ROOT="${1:?kotlin repo root}"
BASE="${2:?gradle-distributions base URL}"
PROP="$ROOT/gradle/wrapper/gradle-wrapper.properties"
if [[ ! -f "$PROP" ]]; then
  echo "ERROR: missing $PROP" >&2
  exit 1
fi

BASE="${BASE%/}"
export ROOT BASE PROP
python3 <<'PY'
import os, pathlib, re

prop = pathlib.Path(os.environ["PROP"])
base = os.environ["BASE"]
text = prop.read_text(encoding="utf-8")
m = re.search(r"^distributionUrl=(.+)$", text, re.MULTILINE)
if not m:
    raise SystemExit("no distributionUrl= line in gradle-wrapper.properties")
raw_val = m.group(1).strip()
# Gradle escapes ':' in properties; normalize for parsing
logical = raw_val.replace("\\", "")
if "/" not in logical or ".zip" not in logical:
    raise SystemExit(f"unexpected distributionUrl value: {raw_val!r}")
zip_name = logical.rsplit("/", 1)[-1]
if not re.fullmatch(r"gradle-[\w.-]+\.zip", zip_name):
    raise SystemExit(f"unexpected distribution zip name: {zip_name!r}")
new_url = f"{base}/{zip_name}"
# Properties file: escape every ':' (https\:// and host\:port)
escaped = new_url.replace(":", "\\:")
text, n = re.subn(r"^distributionUrl=.*$", f"distributionUrl={escaped}", text, count=1, flags=re.MULTILINE)
if n != 1:
    raise SystemExit("failed to replace distributionUrl")
if re.search(r"^validateDistributionUrl=.*$", text, re.MULTILINE):
    text = re.sub(
        r"^validateDistributionUrl=.*$",
        "validateDistributionUrl=false",
        text,
        count=1,
        flags=re.MULTILINE,
    )
else:
    if not text.endswith("\n"):
        text += "\n"
    text += "validateDistributionUrl=false\n"
prop.write_text(text, encoding="utf-8")
print(f"gradle-wrapper: distributionUrl -> {new_url}")
PY
