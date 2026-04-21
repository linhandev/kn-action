# LLVM Manifest Repository

This repository contains manifest files for LLVM builds for OpenHarmony (OH).

## Available Manifests

| Manifest | LLVM Source | Branch | Description |
|----------|-------------|--------|-------------|
| `llvm-1914.xml` | `linhandev/mpcore-llvm-kmp` | `kmp-llvm-19.1.4` | KMP-customized LLVM 19.1.4 |
| `llvm-1914-bare.xml` | `linhandev/mpcore-llvm-kmp` | `kmp-llvm-19.1.4` | Same LLVM as 1914; alternate remotes / minimal layout variant |
| `llvm-1917.xml` | `openharmony/third_party_llvm-project` | `llvm-19.1.7` | Official OH LLVM 19.1.7 |

## Usage

```bash
repo init -u http://192.168.3.6:8929/linhandev/manifest.git -m llvm-1914.xml
repo sync -c --force-sync -j 16
```

## Repository Layout

All manifests define the same workspace structure:

```
toolchain/llvm-project/  - LLVM source tree
prebuilts/lite/sysroot/  - Sysroot for cross-compilation
kernel/liteos_a/         - LiteOS kernel
kernel/linux/patches/    - Linux kernel patches
third_party/...          - Dependencies (musl, zlib, ncurses, etc.)
build/                   - OH build scripts
```