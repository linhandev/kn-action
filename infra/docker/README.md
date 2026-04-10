# Linux build Docker image (`linux-llvm-builder`)

Ubuntu 20.04 image with dependencies used by the [Build LLVM](../../.github/workflows/build-llvm.yml) workflow on Linux.

## CI: GitHub Container Registry

The [Build Linux image](../../.github/workflows/build-linux-image.yml) workflow builds this image and pushes it to **GitHub Container Registry** as `ghcr.io/<owner>/kn-action-linux-llvm-builder:latest`. The Build LLVM workflow uses that image for the Linux job; the runner pulls it automatically.

If the Linux runner cannot pull the image (private package), either make the package public (Package page → Package settings) or log in to GHCR on the runner (e.g. `docker login ghcr.io -u <user> -p <PAT>` with `read:packages`).

The image is rebuilt when:
- You push changes under `infra/docker/` or the build-linux-image workflow
- You run the "Build Linux image" workflow manually

## Local build (optional)

From this directory:

```bash
cd infra/docker
docker build -t linux-llvm-builder:latest .
```

For local runs or if you need to test image changes before pushing, you can temporarily change the Linux job's `container_image` in `build-llvm.yml` back to `linux-llvm-builder:latest` and ensure the image exists on the runner.
