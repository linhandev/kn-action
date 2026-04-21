# Linux image for OpenHarmony / LLVM CI (repo sync + env_prepare + llvm-build).
# Used by: GitLab `build:llvm:linux:x64` (.gitlab/ci/llvm.yml), GitHub Actions (build-linux-image, llvm-linux-docker).
# Target: x86_64; align package set with toolchain/llvm-project/llvm-build expectations and scripts/ci/llvm-build.sh.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    git build-essential swig python3-dev libedit-dev libncurses5-dev \
    binutils-dev gcc-multilib abigail-tools elfutils pkg-config \
    autoconf autoconf-archive libxml2 \
    curl python3 python3-pip python3-requests git-lfs wget rsync ccache pigz \
    ninja-build openssh-client unzip file \
 && ln -sf "$(command -v python3)" /usr/bin/python \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
CMD ["/bin/bash"]
