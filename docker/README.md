# OpenHarmony build env container (run only, no Dockerfile)

Run the OpenHarmony JNLP build image with host user, HTTP proxy support, and systemd auto-start.

## Quick start

1. **Install the run script** so systemd can start it:
   ```bash
   sudo cp docker/run.sh /usr/local/bin/openharmony-build-run.sh
   sudo chmod +x /usr/local/bin/openharmony-build-run.sh
   ```
   Or symlink: `sudo ln -s "$(pwd)/docker/run.sh" /usr/local/bin/openharmony-build-run.sh`  
   Or edit the service file and set `ExecStart` to the full path of `docker/run.sh`.

2. **Optional: proxy and user** (if you use a proxy or run the service as root and want the container to match your user):
   ```bash
   sudo mkdir -p /etc/openharmony-build
   sudo cp docker/docker-openharmony-build.env.example /etc/openharmony-build/docker.env
   sudo edit /etc/openharmony-build/docker.env   # set HTTP_PROXY, HTTPS_PROXY, NO_PROXY, RUN_AS_UID, RUN_AS_GID
   ```

3. **Enable and start the service:**
   ```bash
   sudo cp docker/docker-openharmony-build.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable docker-openharmony-build.service
   sudo systemctl start docker-openharmony-build.service
   ```
   The container will start on boot after Docker.

## Run once (no systemd)

```bash
# Set proxy if needed
export HTTP_PROXY=... HTTPS_PROXY=... NO_PROXY=...
./docker/run.sh
```

When run as your user, UID/GID are taken from the current user. When run by the system service (as root), set `RUN_AS_UID` and `RUN_AS_GID` in `/etc/openharmony-build/docker.env` so the container runs as your host user.

## User systemd service (same user without env file)

To have the service run as your user (so `run.sh` gets your UID/GID automatically):

1. Enable lingering: `loginctl enable-linger $USER`
2. Copy the unit to the user dir: `mkdir -p ~/.config/systemd/user && cp docker/docker-openharmony-build.service ~/.config/systemd/user/`
3. Edit `ExecStart` to the full path of `docker/run.sh` and remove or adjust `EnvironmentFile` if needed.
4. `systemctl --user daemon-reload && systemctl --user enable docker-openharmony-build.service && systemctl --user start docker-openharmony-build.service`
