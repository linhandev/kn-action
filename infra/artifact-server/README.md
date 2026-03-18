# Artifact server

Simple HTTP server to store and serve build artifacts (tar/zip) on your LAN, so self-hosted runners can upload/download without using GitHub's artifact storage. Artifacts are stored in `artifacts/` next to `main.py` (i.e. `infra/artifact-server/artifacts`).

## Endpoints

- **POST /upload** — Upload a file. Body: multipart form with `file`. Stored under the uploaded filename.
- **GET /artifacts** — Directory listing (HTML with links) or JSON list when `Accept: application/json`.
- **GET /artifacts/latest?pattern={regex}** — Redirect (302) to the latest (by mtime) artifact whose name matches the regex.
- **GET /artifacts/{name}** — Download artifact by name.

## Setup (macOS)

1. Install the launchd service:

   ```bash
   cd infra/artifact-server
   sed -e "s|REPLACE_WITH_ABSOLUTE_PATH_TO_infra/artifact-server|$(pwd)|" \
       com.kn-action.artifact-server.plist > ~/Library/LaunchAgents/com.kn-action.artifact-server.plist
   launchctl load ~/Library/LaunchAgents/com.kn-action.artifact-server.plist
   ```

2. Server runs at `http://<this-machine-ip>:8765`. Use that URL as `ARTIFACT_SERVER_URL` in your workflows (or rely on the default `http://192.168.3.5:8765`).

## Run manually

```bash
cd infra/artifact-server
./run.sh
```

Port defaults to 8765; set `PORT` in the environment to override.

## Unload service

```bash
launchctl unload ~/Library/LaunchAgents/com.kn-action.artifact-server.plist
```
