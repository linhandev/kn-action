#!/usr/bin/env bash
# Apply system-wide HTTP(S) proxy on Arch (or similar). Run as root:
#   sudo bash scripts/linux-global-proxy-install.sh
# Override: PROXY_URL=http://host:port/ NO_PROXY_VALUE=... sudo -E bash ...
set -euo pipefail

PROXY_URL="${PROXY_URL:-http://192.168.3.5:7897/}"
# Loopback + Docker bridge nets stay direct (daemon and local registry traffic).
NO_PROXY_VALUE="${NO_PROXY_VALUE:-localhost,127.0.0.1,::1,172.17.0.0/16,172.18.0.0/16}"
MARK="# kn-action global proxy"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

# Normalize: exactly one trailing slash
PROXY_URL="${PROXY_URL%/}/"

if [[ -f /etc/environment ]] && grep -qF "${MARK}" /etc/environment; then
  sed -i "/^${MARK}/,/^NO_PROXY=/d" /etc/environment
fi

{
  echo "${MARK}"
  echo "http_proxy=${PROXY_URL}"
  echo "https_proxy=${PROXY_URL}"
  echo "HTTP_PROXY=${PROXY_URL}"
  echo "HTTPS_PROXY=${PROXY_URL}"
  echo "ftp_proxy=${PROXY_URL}"
  echo "FTP_PROXY=${PROXY_URL}"
  echo "all_proxy=${PROXY_URL}"
  echo "ALL_PROXY=${PROXY_URL}"
  echo "no_proxy=${NO_PROXY_VALUE}"
  echo "NO_PROXY=${NO_PROXY_VALUE}"
} >> /etc/environment

install -d /etc/profile.d
cat > /etc/profile.d/kn-action-proxy.sh <<EOF
${MARK}
export http_proxy='${PROXY_URL}'
export https_proxy='${PROXY_URL}'
export HTTP_PROXY='${PROXY_URL}'
export HTTPS_PROXY='${PROXY_URL}'
export ftp_proxy='${PROXY_URL}'
export FTP_PROXY='${PROXY_URL}'
export all_proxy='${PROXY_URL}'
export ALL_PROXY='${PROXY_URL}'
export no_proxy='${NO_PROXY_VALUE}'
export NO_PROXY='${NO_PROXY_VALUE}'
EOF
chmod 644 /etc/profile.d/kn-action-proxy.sh

install -d /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/99-kn-action-proxy.conf <<EOF
${MARK}
[Manager]
DefaultEnvironment="http_proxy=${PROXY_URL}" "https_proxy=${PROXY_URL}" "HTTP_PROXY=${PROXY_URL}" "HTTPS_PROXY=${PROXY_URL}" "ftp_proxy=${PROXY_URL}" "FTP_PROXY=${PROXY_URL}" "all_proxy=${PROXY_URL}" "ALL_PROXY=${PROXY_URL}" "no_proxy=${NO_PROXY_VALUE}" "NO_PROXY=${NO_PROXY_VALUE}"
EOF

install -d /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
${MARK}
[Service]
Environment="HTTP_PROXY=${PROXY_URL}"
Environment="HTTPS_PROXY=${PROXY_URL}"
Environment="NO_PROXY=${NO_PROXY_VALUE}"
Environment="http_proxy=${PROXY_URL}"
Environment="https_proxy=${PROXY_URL}"
Environment="no_proxy=${NO_PROXY_VALUE}"
EOF

install -d /etc/sudoers.d
umask 077
cat > /etc/sudoers.d/kn-action-proxy <<EOF
${MARK}
Defaults env_keep += "http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ftp_proxy FTP_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY"
EOF
chmod 440 /etc/sudoers.d/kn-action-proxy
umask 022

visudo -c -f /etc/sudoers.d/kn-action-proxy

# GitHub runner user (this host uses User=user)
for u in user; do
  if id "${u}" &>/dev/null && sudo -u "${u}" bash -c 'command -v git' &>/dev/null; then
    sudo -u "${u}" git config --global http.proxy "${PROXY_URL}"
    sudo -u "${u}" git config --global https.proxy "${PROXY_URL}"
  fi
done

systemctl daemon-reload

if systemctl is-active --quiet docker 2>/dev/null; then
  systemctl restart docker
fi

for svc in actions.runner.linhandev-kn-action.linux-kotlin.service actions.runner.linhandev-kn-action.linux-llvm.service; do
  if [[ -f "/etc/systemd/system/${svc}" ]] && systemctl is-active --quiet "${svc}" 2>/dev/null; then
    systemctl restart "${svc}" || true
  fi
done

echo "Done. Log out and back in (or reboot) so desktop sessions pick up /etc/environment."
echo "Optional: stop local Clash: sudo systemctl stop clash-verge-service && sudo systemctl disable clash-verge-service"
