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

# If pattern is set, resolve to latest matching artifact name via server 302 Location
# (curl %{redirect_url} is often empty with -o /dev/null; parse headers — see scripts/ci/artifact-server-latest.sh).
if [ -n "$pattern" ]; then
  _dl_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _repo_root="$(cd "$_dl_here/../../.." && pwd)"
  # shellcheck source=/dev/null
  source "$_repo_root/scripts/ci/artifact-server-latest.sh"
  name="$(artifact_server_latest_basename "$server_url" "$pattern")" || {
    echo "::error::No artifact matching pattern: $pattern"
    exit 1
  }
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
  if [ -n "${KNACTION_DOTENV_FILE:-}" ]; then
    echo "path=$dest_path" >>"$KNACTION_DOTENV_FILE"
  fi
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
if [ -n "${KNACTION_DOTENV_FILE:-}" ]; then
  echo "path=$dest_path" >>"$KNACTION_DOTENV_FILE"
fi
echo "Downloaded and cached: $dest_path"
