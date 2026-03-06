#!/usr/bin/env bash
set -euo pipefail

IMAGE="swr.cn-north-4.myhuaweicloud.com/ci-service/openharmony-release-build-env-jnlp:1.0.3"
NAME="llvm-builder"

# Proxy reachable from inside the container (host:7897). Override via HTTP_PROXY/HTTPS_PROXY.
: "${HTTP_PROXY:=http://host.docker.internal:7897}"
: "${HTTPS_PROXY:=http://host.docker.internal:7897}"
: "${NO_PROXY:=localhost,127.0.0.1}"

# Run as current user
USER_SPEC="$(id -u):$(id -g)"

# Common run options: user, proxy host, env, mounts (shared by interactive and detached)
run_args=(
  -u "$USER_SPEC"
  --add-host=host.docker.internal:host-gateway
  -e HTTP_PROXY -e HTTPS_PROXY -e NO_PROXY
)
[[ -n "${HOME:-}" ]]                  && run_args+=(-v "$HOME/runner/llvm:/llvm")
[[ -n "${HOME:-}" && -d "$HOME/.ssh" ]] && run_args+=(-v "$HOME/.ssh:/llvm/.ssh:ro")

INTERACTIVE=
if [[ "${1:-}" == "-i" ]]; then
  INTERACTIVE=1
  shift
fi

if [[ -n "${INTERACTIVE:-}" ]]; then
  exec docker run -it --rm "${run_args[@]}" "$IMAGE" "${@:-/bin/bash}"
else
  if docker ps -a -q -f name="^${NAME}$" | grep -q .; then
    docker start "$NAME"
  else
    docker run -d --name "$NAME" "${run_args[@]}" "$IMAGE" "$@"
  fi
fi
