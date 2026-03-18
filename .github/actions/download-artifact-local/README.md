# Download artifact (local)

Downloads an artifact by name: if it exists in the local cache (`~/runner/artifact`), uses it; otherwise downloads from the artifact server and caches it.

## Inputs

| Input       | Required | Description |
|------------|----------|-------------|
| `name`     | yes      | Artifact name (e.g. `llvm-abc123_act-def456_macOS_ARM64.tar.gz`). |
| `server_url` | no     | Base URL of the artifact server (default `http://192.168.3.5:8765`). |
| `cache_dir` | no      | Local cache directory (default `~/runner/artifact`). |
| `path`     | no       | Directory to place the file (default: cache_dir). |

## Outputs

| Output | Description |
|--------|-------------|
| `path` | Absolute path to the downloaded artifact file. |

## Example

```yaml
- uses: ./.github/actions/download-artifact-local
  id: dl
  with:
    name: llvm-abc123_act-def456_Linux_X64.tar.gz
    server_url: ${{ vars.ARTIFACT_SERVER_URL }}

- run: tar -xzf "${{ steps.dl.outputs.path }}" -C linux_llvm
```

For multiple artifacts, call the action once per artifact or use a matrix.
