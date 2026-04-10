#!/usr/bin/env bash
set -e
path="$INPUT_PATH"
name="$(basename "$path")"
server_url="${INPUT_SERVER_URL%/}"
cache_dir="${INPUT_CACHE_DIR/#\~/$HOME}"

if [ ! -f "$path" ]; then
  echo "::error::File not found: $path"
  exit 1
fi

mkdir -p "$cache_dir"
cache_path="$cache_dir/$name"
if ! [ "$path" -ef "$cache_path" ]; then
  cp -f "$path" "$cache_path"
fi
if [ -n "${KNACTION_DOTENV_FILE:-}" ]; then
  echo "path=$cache_path" >>"$KNACTION_DOTENV_FILE"
fi
echo "Cached to $cache_path"

local_md5_artifact() {
  local f="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum -- "$f" | awk '{ print $1 }'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q -- "$f"
  else
    echo "::error::Need md5sum (Linux/Git Bash) or md5 (macOS) to verify artifact server state." >&2
    return 1
  fi
}

local_md5="$(local_md5_artifact "$path")" || exit 1
md5_url="${server_url}/artifacts/${name}.md5"
tmp_sidecar="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/upload-artifact-local-md5-$$"
if ! code=$(curl -sS -o "$tmp_sidecar" -w '%{http_code}' "$md5_url"); then
  rm -f "$tmp_sidecar"
  echo "::error::Could not reach artifact server for MD5 check: $md5_url"
  exit 1
fi
case "$code" in
  200)
    server_md5="$(awk 'NR==1 { print $1 }' "$tmp_sidecar" | tr -d '\r\n')"
    rm -f "$tmp_sidecar"
    if [ "$server_md5" = "$local_md5" ]; then
      download_url="${server_url}/artifacts/${name}"
      if [ -n "${KNACTION_DOTENV_FILE:-}" ]; then
        echo "download_url=$download_url" >>"$KNACTION_DOTENV_FILE"
      fi
      echo "Server already has identical artifact (MD5 match), skipping upload."
      echo "Download: $download_url"
      exit 0
    fi
    echo "::error::Artifact already exists on server with different content (MD5 mismatch). Local=$local_md5 server=$server_md5"
    exit 1
    ;;
  404)
    rm -f "$tmp_sidecar"
    ;;
  *)
    rm -f "$tmp_sidecar"
    echo "::error::MD5 sidecar check failed (HTTP $code): $md5_url"
    exit 1
    ;;
esac

echo "Uploading to $server_url/upload ..."
code=$(curl -sS -w '%{http_code}' -o /tmp/upload-artifact-local.out \
  -X POST \
  -F "file=@$path" \
  "$server_url/upload")
if [ "$code" != "200" ]; then
  msg="$(cat /tmp/upload-artifact-local.out 2>/dev/null)"
  if [ "$code" = "409" ]; then
    echo "::error::Re-upload forbidden: artifact already exists (no or stale .md5 sidecar). Remove the remote file or backfill ${name}.md5 on the server. $msg"
  else
    echo "::error::Upload failed (HTTP $code): $msg"
  fi
  exit 1
fi
download_url="${server_url}/artifacts/${name}"
if [ -n "${KNACTION_DOTENV_FILE:-}" ]; then
  echo "download_url=$download_url" >>"$KNACTION_DOTENV_FILE"
fi
echo "Uploaded artifact: $name"
echo "Download: $download_url"
