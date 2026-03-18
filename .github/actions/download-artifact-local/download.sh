#!/usr/bin/env bash
set -e
name="$INPUT_NAME"
pattern="$INPUT_PATTERN"
server_url="${INPUT_SERVER_URL%/}"
cache_dir="${INPUT_CACHE_DIR/#\~/$HOME}"
out_dir="${INPUT_PATH/#\~/$HOME}"

if [ -z "$name" ] && [ -z "$pattern" ]; then
  echo "::error::One of name or pattern must be set"
  exit 1
fi
if [ -n "$name" ] && [ -n "$pattern" ]; then
  echo "::error::Set only one of name or pattern"
  exit 1
fi

# If pattern is set, resolve to latest matching artifact name via server redirect
if [ -n "$pattern" ]; then
  redirect_url=$(curl -sS -w '%{redirect_url}' -o /dev/null -G \
    --data-urlencode "pattern=$pattern" "$server_url/artifacts/latest")
  if [ -z "$redirect_url" ]; then
    echo "::error::No artifact matching pattern: $pattern"
    exit 1
  fi
  name=$(basename "${redirect_url%%\?*}")
fi

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
