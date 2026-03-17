# Linux build environment for kn-action (LLVM/Kotlin CI).
# Matches deps installed in .github/workflows/build-llvm.yml for Linux.
# CI runs on linux X64; gcc-multilib is amd64-only so we install it only when available.
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
# Part 1: packages from .github/workflows/build-llvm.yml (doc)
 && apt-get install -y --no-install-recommends \
    git build-essential swig python3-dev libedit-dev libncurses5-dev \
    binutils-dev abigail-tools elfutils pkg-config \
    autoconf autoconf-archive libxml2 \
 && (apt-get install -y --no-install-recommends gcc-multilib 2>/dev/null || true) \
 \
# Part 2: added for this image
 && apt-get install -y --no-install-recommends \
    curl python3-requests git-lfs wget rsync ccache pigz \
 && ln -sf "$(command -v python3)" /usr/bin/python \
 && rm -rf /var/lib/apt/lists/*

# Default: run shell so "docker run -it <image>" works
CMD ["/bin/bash"]
