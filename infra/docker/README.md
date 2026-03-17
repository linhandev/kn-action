# Linux build Docker image (`linux-llvm-builder`)

Ubuntu 20.04 image with dependencies used by the [Build LLVM](../../.github/workflows/build-llvm.yml) workflow on Linux.

## How to build

From the repo root:

```bash
docker build -t linux-llvm-builder:latest infra/docker
```

Or from this directory:

```bash
cd infra/docker
docker build -t linux-llvm-builder:latest .
```

The workflow expects the image name **`linux-llvm-builder:latest`** on the Linux runner. If the Build LLVM job fails on Linux with "image not found", build the image on that runner (or a machine that can push to the runner’s Docker), then re-run the workflow.

To publish for a registry (e.g. for multiple runners), tag and push:

```bash
docker tag linux-llvm-builder:latest ghcr.io/your-org/linux-llvm-builder:1.0
docker push ghcr.io/your-org/linux-llvm-builder:1.0
```

Then set the workflow’s Linux job `container_image` to that URL.
