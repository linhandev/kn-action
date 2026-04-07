#!/usr/bin/env bash
# Set HTTP/HTTPS proxy on the active Wi‑Fi profile (NetworkManager), similar to Windows
# "Use a proxy server" for this network. No iptables, no extra daemons.
#
#   sudo CONN='HUAWEI-X1E71U' PROXY='http://192.168.3.5:7897' bash scripts/linux-nm-wifi-proxy.sh
#
# Omit CONN to use the first active 802-11-wireless connection. Reactivate Wi‑Fi if needed:
#   sudo nmcli connection up "$CONN"
set -euo pipefail

PROXY="${PROXY:-http://192.168.3.5:7897}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

# CLEAR=1 sudo -E bash …  → turn off proxy for this profile
if [[ "${CLEAR:-}" == 1 ]]; then
  if [[ -z "${CONN:-}" ]]; then
    CONN="$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | awk -F: '$2 == "802-11-wireless" && $3 != "" { print $1; exit }')"
  fi
  [[ -n "${CONN}" ]] || { echo "Set CONN=… or connect to Wi‑Fi first." >&2; exit 1; }
  nmcli connection modify "$CONN" proxy.method none
  nmcli connection up "$CONN"
  echo "Cleared proxy on: $CONN"
  exit 0
fi

if ! command -v nmcli >/dev/null 2>&1; then
  echo "nmcli not found; install/use NetworkManager." >&2
  exit 1
fi

if [[ -z "${CONN:-}" ]]; then
  CONN="$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | awk -F: '$2 == "802-11-wireless" && $3 != "" { print $1; exit }')"
fi

if [[ -z "${CONN}" ]]; then
  echo "No active Wi‑Fi connection. Set CONN to the profile name from: nmcli connection show" >&2
  exit 1
fi

nmcli connection modify "$CONN" proxy.method manual proxy.http "$PROXY" proxy.https "$PROXY"
nmcli connection up "$CONN"
echo "Updated NetworkManager profile: $CONN -> $PROXY"
