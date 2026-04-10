# Linux build environment for kn-action (LLVM/Kotlin CI). X64 only.
# Matches deps installed in .github/workflows/build-llvm.yml for Linux.
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    git build-essential swig python3-dev libedit-dev libncurses5-dev \
    binutils-dev gcc-multilib abigail-tools elfutils pkg-config \
    autoconf autoconf-archive libxml2 \
    curl python3 python3-pip python3-requests git-lfs wget rsync ccache pigz \
 && ln -sf "$(command -v python3)" /usr/bin/python \
 && rm -rf /var/lib/apt/lists/*

# Default: run shell so "docker run -it <image>" works
CMD ["/bin/bash"]
