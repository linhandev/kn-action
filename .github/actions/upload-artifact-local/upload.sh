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
echo "path=$cache_path" >> "$GITHUB_OUTPUT"
echo "Cached to $cache_path"

echo "Uploading to $server_url/upload ..."
code=$(curl -sS -w '%{http_code}' -o /tmp/upload-artifact-local.out \
  -X POST \
  -F "file=@$path" \
  "$server_url/upload")
if [ "$code" != "200" ]; then
  msg="$(cat /tmp/upload-artifact-local.out 2>/dev/null)"
  if [ "$code" = "409" ]; then
    echo "::error::Re-upload forbidden: artifact already exists. $msg"
  else
    echo "::error::Upload failed (HTTP $code): $msg"
  fi
  exit 1
fi
download_url="${server_url}/artifacts/${name}"
echo "download_url=$download_url" >> "$GITHUB_OUTPUT"
echo "Uploaded artifact: $name"
echo "Download: $download_url"
