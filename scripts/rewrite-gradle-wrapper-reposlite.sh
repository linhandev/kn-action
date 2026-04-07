#!/usr/bin/env bash
# Point Gradle wrapper at LAN mirror with the same /distributions/… layout as services.gradle.org.
# Args: <kotlin-repo-root> <mirror-base>   e.g. http://192.168.3.5:8080/distributions
# Uses sed only (no Python): Windows kotlin jobs often have no python on PATH.
set -euo pipefail
ROOT="${1:?kotlin repo root}"
BASE="${2:?mirror base URL (…/distributions, no trailing slash)}"
BASE="${BASE%/}"
PROP="$ROOT/gradle/wrapper/gradle-wrapper.properties"
if [[ ! -f "$PROP" ]]; then
  echo "ERROR: missing $PROP" >&2
  exit 1
fi

ZIP=$(sed -nE 's/^distributionUrl=.*\/(gradle-[a-zA-Z0-9_.-]+\.zip).*/\1/p' "$PROP" | tr -d '\r\n')
if [[ ! "$ZIP" =~ ^gradle-.*\.zip$ ]]; then
  echo "ERROR: could not parse gradle zip from distributionUrl in $PROP" >&2
  exit 1
fi

NEW="distributionUrl=${BASE}/${ZIP}"
tmp="${PROP}.kn-action.tmp"
sed -E "s#^distributionUrl=.*#${NEW}#" "$PROP" > "$tmp"
if grep -qE '^validateDistributionUrl=' "$tmp"; then
  sed -E 's/^validateDistributionUrl=.*/validateDistributionUrl=false/' "$tmp" > "${tmp}.2"
  mv "${tmp}.2" "$tmp"
else
  echo 'validateDistributionUrl=false' >> "$tmp"
fi
mv "$tmp" "$PROP"
echo "gradle-wrapper: distributionUrl -> ${BASE}/${ZIP}"
