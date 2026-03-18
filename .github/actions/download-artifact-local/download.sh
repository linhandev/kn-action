#!/usr/bin/env bash
set -e
name="$INPUT_NAME"
server_url="${INPUT_SERVER_URL%/}"
cache_dir="${INPUT_CACHE_DIR/#\~/$HOME}"
out_dir="${INPUT_PATH/#\~/$HOME}"

mkdir -p "$cache_dir"
[ -n "$out_dir" ] || out_dir="$cache_dir"
mkdir -p "$out_dir"
cache_path="$cache_dir/$name"
dest_path="$out_dir/$name"

if [ -f "$cache_path" ]; then
  echo "Using cached artifact: $cache_path"
  if [ "$cache_path" != "$dest_path" ]; then
    cp -f "$cache_path" "$dest_path"
  fi
  echo "path=$dest_path" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "Downloading $name from $server_url ..."
code=$(curl -sS -w '%{http_code}' -o "$dest_path" \
  "$server_url/artifacts/$name")
if [ "$code" != "200" ]; then
  rm -f "$dest_path"
  echo "::error::Download failed (HTTP $code) for $name"
  exit 1
fi
# Cache it for next time (same runner)
cp -f "$dest_path" "$cache_path"
echo "path=$dest_path" >> "$GITHUB_OUTPUT"
echo "Downloaded and cached: $dest_path"
