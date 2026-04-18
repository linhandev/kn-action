#!/usr/bin/env bash
# Resolve latest artifact basename on the LAN artifact server (infra/artifact-server/main.py).
# The server returns HTTP 302 with a Location header; curl's write-out %{redirect_url} is often
# empty when combined with -o /dev/null, so we parse Location from -D headers.
# Usage: artifact_server_latest_basename SERVER_URL PATTERN
# Prints basename only (e.g. llvm-packages-abc_act-def_Linux_X64.tar); exits non-zero on failure.
# Intended to be sourced (do not enable set -u/-e at file scope).

artifact_server_latest_basename() {
  local server_url="${1%/}"
  local pattern="$2"
  local hdr http loc redirect_url bn

  hdr="$(mktemp)"

  echo "artifact-server: GET $server_url/artifacts/latest pattern=$pattern" >&2
  if ! http="$(curl -sS --connect-timeout 10 --max-time 120 -o /dev/null -D "$hdr" -w '%{http_code}' -G \
    --data-urlencode "pattern=$pattern" "$server_url/artifacts/latest")"; then
    echo "curl failed for pattern=$pattern (check ARTIFACT_SERVER_URL and network)." >&2
    rm -f "$hdr"
    return 1
  fi

  case "$http" in
    301 | 302 | 303 | 307 | 308) ;;
    404)
      echo "No artifact matching pattern: $pattern (HTTP 404). Upload outer tars or run build:llvm with SKIP_LLVM_BUILD=false." >&2
      echo "Hint: curl -sS -H 'Accept: application/json' ${server_url}/artifacts/ | head" >&2
      rm -f "$hdr"
      return 1
      ;;
    *)
      echo "Unexpected HTTP $http from ${server_url}/artifacts/latest (expected 302)." >&2
      sed -n '1,20p' "$hdr" >&2 || true
      rm -f "$hdr"
      return 1
      ;;
  esac

  loc="$(grep -i '^location:' "$hdr" | tail -1 | sed 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//' | tr -d '\r')"
  if [ -z "$loc" ]; then
    echo "Empty Location header on HTTP $http for pattern=$pattern" >&2
    rm -f "$hdr"
    return 1
  fi
  rm -f "$hdr"

  case "$loc" in
    http://* | https://*) redirect_url="$loc" ;;
    /*) redirect_url="${server_url}${loc}" ;;
    *) redirect_url="${server_url}/${loc}" ;;
  esac

  bn="$(basename "${redirect_url%%\?*}")"
  printf '%s\n' "$bn"
}
