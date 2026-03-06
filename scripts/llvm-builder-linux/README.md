# OpenHarmony build env container (run only, no Dockerfile)

Run the OpenHarmony JNLP build image with host user, HTTP proxy support, SSH keys, and systemd auto-start. When `HOME` is set, `~/runner/llvm` is mounted at `/llvm` and `~/.ssh` at `/llvm/.ssh` (read-only) for git over SSH.

## Quick start

1. **Install the run script** so systemd can start it:
   ```bash
   sudo ln -sf "$(pwd)/scripts/llvm-builder-linux/run.sh" /usr/local/bin/llvm-builder-run.sh
   ```

2. **Enable and start the service:**
   ```bash
   sudo cp scripts/llvm-builder-linux/llvm-builder.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable llvm-builder.service
   sudo systemctl start llvm-builder.service
   ```
   The container starts on boot after Docker. The service is configured to **auto-restart on failure** (`Restart=on-failure`, `RestartSec=10`).

## Run interactively (for setup)

To get a shell inside the same image (proxy, user, and `~/runner/llvm` → `/llvm` mounted) for one-off setup:

```bash
./scripts/llvm-builder-linux/run.sh -i
# or
./scripts/llvm-builder-linux/run.sh --interactive
```

Optional: pass a command instead of the default shell, e.g. `./scripts/llvm-builder-linux/run.sh -i /bin/bash -c "echo hello"`. The container is `--rm` so it is removed when you exit.

## Run once (no systemd)

```bash
# Default proxy: host.docker.internal:7897 (set HTTP_PROXY/HTTPS_PROXY to override)
./scripts/llvm-builder-linux/run.sh
```

The container runs as the current user (UID/GID from the host).

## User systemd service (run as your user)

1. Enable lingering: `loginctl enable-linger $USER`
2. Copy the unit: `mkdir -p ~/.config/systemd/user && cp scripts/llvm-builder-linux/llvm-builder.service ~/.config/systemd/user/`
3. Edit `ExecStart` to the full path of `scripts/llvm-builder-linux/run.sh`.
4. `systemctl --user daemon-reload && systemctl --user enable llvm-builder.service && systemctl --user start llvm-builder.service`
