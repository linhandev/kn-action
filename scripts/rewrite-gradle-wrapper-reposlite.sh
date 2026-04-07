#!/usr/bin/env bash
# Point Gradle wrapper at Reposilite maven repo "gradle-distributions" (same host as /releases).
# Args: <kotlin-repo-root> <gradle-distributions-base-url>
# Example: ./rewrite-gradle-wrapper-reposlite.sh ../ci-workspace http://192.168.3.5:8080/gradle-distributions
#
# Pure bash (no Python): Windows kotlin jobs run as Network Service and often have no python on PATH.
set -euo pipefail
ROOT="${1:?kotlin repo root}"
BASE="${2:?gradle-distributions base URL}"
BASE="${BASE%/}"
PROP="$ROOT/gradle/wrapper/gradle-wrapper.properties"
if [[ ! -f "$PROP" ]]; then
  echo "ERROR: missing $PROP" >&2
  exit 1
fi

tmp="${PROP}.kn-action.tmp"
rm -f "$tmp"
found_dist=0
found_validate=0
new_url=""
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  if [[ "$line" =~ ^distributionUrl=(.+)$ ]]; then
    raw_val="${BASH_REMATCH[1]}"
    logical="${raw_val//\\/}"
    if [[ "$logical" != *"/"* ]] || [[ "$logical" != *".zip"* ]]; then
      echo "ERROR: unexpected distributionUrl value: ${raw_val}" >&2
      rm -f "$tmp"
      exit 1
    fi
    zip_name="${logical##*/}"
    if [[ ! "$zip_name" =~ ^gradle-[a-zA-Z0-9_.-]+\.zip$ ]]; then
      echo "ERROR: unexpected distribution zip name: ${zip_name}" >&2
      rm -f "$tmp"
      exit 1
    fi
    new_url="${BASE}/${zip_name}"
    escaped="${new_url//:/\\:}"
    printf '%s\n' "distributionUrl=${escaped}" >> "$tmp"
    found_dist=1
  elif [[ "$line" =~ ^validateDistributionUrl= ]]; then
    printf '%s\n' "validateDistributionUrl=false" >> "$tmp"
    found_validate=1
  else
    printf '%s\n' "$line" >> "$tmp"
  fi
done < "$PROP"

if [[ "$found_dist" -eq 0 ]]; then
  echo "ERROR: no distributionUrl= line in gradle-wrapper.properties" >&2
  rm -f "$tmp"
  exit 1
fi

if [[ "$found_validate" -eq 0 ]]; then
  printf '%s\n' "validateDistributionUrl=false" >> "$tmp"
fi

mv "$tmp" "$PROP"
echo "gradle-wrapper: distributionUrl -> $new_url"
