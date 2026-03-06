# OpenHarmony build env container (run only, no Dockerfile)

Run the OpenHarmony build image with host user, HTTP proxy support, SSH keys, and systemd auto-start. When `HOME` is set, `~/runner/llvm` is mounted at `/llvm` and `~/.ssh` at `/llvm/.ssh` (read-only) for git over SSH.

## Install (user scope)

User-scope install: no `sudo`. The service runs as your user; the container sees your `HOME`, so `~/runner/llvm` and `~/.ssh` mounts work. Starts when you log in (or at boot if lingering is enabled). Ensure Docker is running before starting the service.

1. **Enable lingering** (optional — so the service runs at boot without a login session):
   ```bash
   loginctl enable-linger $USER
   ```

2. **Install the user unit** and set `ExecStart` in `~/.config/systemd/user/llvm-builder.service`:
   Edit the unit and set `ExecStart` to the full path of `run.sh`, e.g. `ExecStart=/full/path/to/kn-action/scripts/llvm-builder-linux/run.sh /bin/bash /llvm/run.sh`
   ```bash
   mkdir -p ~/.config/systemd/user
   cp -f scripts/llvm-builder-linux/llvm-builder.service ~/.config/systemd/user/
   ```

3. **Enable and start** the service:
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable llvm-builder.service
   systemctl --user start llvm-builder.service
   ```
   Status: `systemctl --user status llvm-builder.service`

## Run interactively (for setup)

To get a shell inside the same image (proxy, user, and `~/runner/llvm` → `/llvm` mounted) for one-off setup:

```bash
./scripts/llvm-builder-linux/run.sh -i
```

Optional: pass a command instead of the default shell, e.g. `./scripts/llvm-builder-linux/run.sh -i /bin/bash -c "echo hello"`. The container is `--rm` so it is removed when you exit.

## Run once (no systemd)

```bash
# Default proxy: host.docker.internal:7897 (set HTTP_PROXY/HTTPS_PROXY to override)
./scripts/llvm-builder-linux/run.sh
```

The container runs as the current user (UID/GID from the host).
