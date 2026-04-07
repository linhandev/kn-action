# Artifact server

Simple HTTP server to store and serve build artifacts (tar/zip) on your LAN, so self-hosted runners can upload/download without using GitHub's artifact storage. Artifacts are stored in `artifacts/` next to `main.py` (i.e. `infra/artifact-server/artifacts`).

## Endpoints

- **POST /upload** — Upload a file. Body: multipart form with `file`. Stored under the uploaded filename. After a successful upload, the server writes **`{name}.md5`** next to it (single line: 32-char hex MD5 digest). Re-upload of the same name is rejected unless the upload client skips via MD5 match (see below).
- **GET /artifacts** — Directory listing (HTML with links) or JSON list when `Accept: application/json`.
- **GET /artifacts/latest?pattern={regex}** — Redirect (302) to the latest (by mtime) artifact whose name matches the regex (`.md5` sidecar files are ignored for matching).
- **GET /artifacts/{name}** — Download artifact by name.
- **GET /artifacts/{name}.md5** — Download the MD5 digest for an artifact (used by CI to skip upload when the server already has the same bytes).

### Skipping upload when the file already exists

The **`upload-artifact-local`** composite action fetches **`/artifacts/<basename>.md5`** before **POST /upload**. If the digest matches the local file, upload is skipped. If the artifact exists but the digest differs, the job fails with an MD5 mismatch error. Legacy trees without a `.md5` sidecar still return **409** on re-upload; generate sidecars once (e.g. `md5sum file | awk '{print $1}' > file.md5` in `artifacts/`) or remove the remote artifact and upload again.

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
