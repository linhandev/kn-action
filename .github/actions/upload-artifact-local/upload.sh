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
cp -f "$path" "$cache_path"
echo "path=$cache_path" >> "$GITHUB_OUTPUT"
echo "Cached to $cache_path"

echo "Uploading to $server_url/upload ..."
code=$(curl -sS -w '%{http_code}' -o /tmp/upload-artifact-local.out \
  -X POST \
  -F "file=@$path" \
  "$server_url/upload")
if [ "$code" != "200" ]; then
  echo "::error::Upload failed (HTTP $code): $(cat /tmp/upload-artifact-local.out)"
  exit 1
fi
echo "Uploaded artifact: $name"
