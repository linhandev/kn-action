# Upload artifact (local)

Uploads a single tar/zip file to your LAN artifact server and to the runner's local cache (`~/runner/artifact` by default). Use with the artifact server in `infra/artifact-server`.

## Inputs

| Input       | Required | Description |
|------------|----------|-------------|
| `path`     | yes      | Path to the tar or zip file (filename is used as artifact name). |
| `server_url` | no     | Base URL of the artifact server (default `http://192.168.3.5:8765`). |
| `cache_dir` | no      | Local cache directory (default `~/runner/artifact`). |

## Outputs

| Output | Description |
|--------|-------------|
| `path` | Path where the artifact was written in the local cache. |

## Example

```yaml
- uses: ./.github/actions/upload-artifact-local
  with:
    path: ${{ steps.archive.outputs.path }}
    server_url: ${{ vars.ARTIFACT_SERVER_URL }}
```

Optional: set `ARTIFACT_SERVER_URL` in repo/org variables to override the default (`http://192.168.3.5:8765`).
