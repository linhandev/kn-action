# Download artifact (local)

Downloads an artifact by exact name or by regex pattern (latest match by mtime). If the file exists in the local cache (`~/runner/artifact`), uses it; otherwise downloads from the artifact server and caches it.

## Inputs

| Input       | Required | Description |
|------------|----------|-------------|
| `name`     | no*      | Exact artifact name. *Required if `pattern` is not set. |
| `pattern`  | no*      | Regex to match artifact names; downloads the latest (by mtime) match. *Required if `name` is not set. |
| `server_url` | no     | Base URL of the artifact server (default `http://192.168.3.5:8765`). |
| `cache_dir` | no      | Local cache directory (default `~/runner/artifact`). |
| `path`     | no       | Directory to place the file (default: cache_dir). |

## Outputs

| Output | Description |
|--------|-------------|
| `path` | Absolute path to the downloaded artifact file. |

## Examples

By exact name:

```yaml
- uses: ./.github/actions/download-artifact-local
  id: dl
  with:
    name: llvm-abc123_act-def456_Linux_X64.tar.gz

- run: tar -xzf "${{ steps.dl.outputs.path }}" -C linux_llvm
```

By regex (latest matching artifact):

```yaml
- uses: ./.github/actions/download-artifact-local
  id: dl
  with:
    pattern: 'llvm-.*_Linux_X64\.tar\.gz'

- run: tar -xzf "${{ steps.dl.outputs.path }}" -C linux_llvm
```

For multiple artifacts, call the action once per artifact or use a matrix.
