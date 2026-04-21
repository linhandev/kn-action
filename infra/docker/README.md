# Linux LLVM builder image (`linux-llvm-builder`)

Ubuntu 22.04 image with dependencies for OpenHarmony LLVM builds (`scripts/ci/llvm-build.sh linux`), matching GitLab’s `build:llvm:linux:x64` Docker job.

## CI: GitHub Container Registry

The [Build Linux image](../../.github/workflows/build-linux-image.yml) workflow builds [`linux-llvm-builder/Dockerfile`](linux-llvm-builder/Dockerfile) and pushes **`ghcr.io/<owner>/kn-action-linux-llvm-builder:latest`**.

Consumers:

- [Build LLVM](../../.github/workflows/build-llvm.yml) — Linux matrix job uses this image as `container.image`.
- [LLVM Linux (Docker)](../../.github/workflows/llvm-linux-docker.yml) — runs the same `llvm-build.sh linux` script inside a container on GitHub-hosted runners (`workflow_dispatch`).
- GitLab [`.gitlab/ci/llvm.yml`](../../.gitlab/ci/llvm.yml) — `build:llvm:linux:x64` uses the same image name.

If a runner cannot pull the image (private package), make the package public or `docker login ghcr.io` with `read:packages`.

The image is rebuilt when you push changes under `infra/docker/` or edit `build-linux-image.yml`, or when you run **Build Linux image** manually.

## Local build

From the repository root:

```bash
docker build -f infra/docker/linux-llvm-builder/Dockerfile -t kn-action-linux-llvm-builder:local .
```

For self-hosted Actions, point `container_image` / `builder_image` at your tag if needed.
