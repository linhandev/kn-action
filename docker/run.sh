#!/usr/bin/env bash
set -euo pipefail

IMAGE="swr.cn-north-4.myhuaweicloud.com/ci-service/openharmony-release-build-env-jnlp"
NAME="llvm-runner"

# Fixed local proxy (override by setting HTTP_PROXY/HTTPS_PROXY in env)
: "${HTTP_PROXY:=http://localhost:7897}"
: "${HTTPS_PROXY:=http://localhost:7897}"
: "${NO_PROXY:=localhost,127.0.0.1}"

# Use RUN_AS_UID/RUN_AS_GID when set (e.g. from systemd EnvironmentFile); otherwise current user
if [[ -n "${RUN_AS_UID:-}" && -n "${RUN_AS_GID:-}" ]]; then
  USER_SPEC="${RUN_AS_UID}:${RUN_AS_GID}"
else
  USER_SPEC="$(id -u):$(id -g)"
fi

# Start existing container or create a new one
if docker ps -a -q -f name="^${NAME}$" | grep -q .; then
  docker start "$NAME"
else
  run_args=(
    -d --name "$NAME"
    -u "$USER_SPEC"
  )
  run_args+=(-e HTTP_PROXY -e HTTPS_PROXY -e NO_PROXY)
  [[ -n "${HOME:-}" ]]        && run_args+=(-v "$HOME/runner/llvm:/llvm")
  docker run "${run_args[@]}" "$IMAGE" "$@"
fi
