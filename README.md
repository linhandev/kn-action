# kn-action

GitHub Actions for KMP/Kotlin and related projects.

## Actions

### Build Kotlin (OpenHarmony)

**Workflow:** [`.github/workflows/build-kotlin.yml`](.github/workflows/build-kotlin.yml)

- Clones [CPF-KMP-CMP/kotlin](https://gitcode.com/CPF-KMP-CMP/kotlin) from GitCode into `ci-workspace` (default); optional local reference at `LOCAL_REFERENCE_DIR` / repo name from URL (e.g. `~/git/ci/` + `kotlin` → `~/git/ci/kotlin`)
- Runs `bash scripts/build-ohos.sh` to build Kotlin for OpenHarmony
- Supports building a **branch**, a **commit**, or a **branch + PR** (merge GitCode merge-request into branch then build)

**Runner:** Mac ARM64 self-hosted. Labels: `self-hosted`, `macOS`, `ARM64`, `kotlin`.

**When it runs:** On push to `develop` or `main`, or via **Actions → Build Kotlin → Run workflow** (with optional inputs).

**Cache (incremental builds):** `RUNNER_TEMP` is removed when the job ends, so it must not be used for incremental build cache. For incremental builds the workflow uses a **different, persistent directory** (workflow input `cache_root` or default `$HOME/kn-action-ci`). That directory persists across jobs, host reboots, and runner restarts until you remove it manually.

**Workflow inputs (manual run):**

| Input | Description | Default |
|-------|-------------|---------|
| `branch` | Branch to build (required for branch or branch+PR; on push uses env `KOTLIN_BRANCH`) | — |
| `commit` | Commit SHA to build (if set, overrides branch/PR) | — |
| `pr_number` | Merge-request number to merge into branch (use with `branch`) | — |
| `incremental` | Use persistent cache for incremental build | `false` |
| `cache_root` | Persistent cache root for incremental | `$HOME/kn-action-ci` |
| `artifact_destination` | Save artifact `local` or `github` | `local` |
| `artifact_local_path` | Directory or path for local artifact | `$HOME/kn-action-artifacts` |

**Build modes (derived from inputs):** If `commit` is set → build that commit. Else if both `branch` and `pr_number` are set → clone branch, fetch GitCode merge-request (`refs/merge-requests/<id>/head` → local branch `pr_<id>`), merge into branch, then build. Else → build `branch`.

**Artifact:** After the build, `build/repo` is archived as `kotlin-<kotlin_sha>_act-<repo_sha>.tar.gz` (gzip -9). With `artifact_destination: local` the file is written to `artifact_local_path`. With `artifact_destination: github` the file is uploaded as a workflow artifact.

**Reference clone:** The workflow uses the reusable composite action [`.github/actions/prepare-repo`](.github/actions/prepare-repo) (any repo). Local reference base is `LOCAL_REFERENCE_DIR` (default `~/git/ci/`); the repo name from the remote URL is appended for the reference path. If that path exists and is a git repo, clone/fetch use `--reference`; otherwise a normal clone. If the workspace already exists, the action reuses it: fetch, checkout/merge, then `git clean -dfx` and `git reset --hard`. Use the same action from other workflows: `uses: ./.github/actions/prepare-repo` or `uses: owner/repo/.github/actions/prepare-repo@ref`.

**Requirement — GitCode SSH access:** The workflow clones `git@gitcode.com:CPF-KMP-CMP/kotlin.git`. The runner environment must already have SSH configured so that `git clone` to GitCode works without prompts (e.g. a self-hosted runner with an SSH key for GitCode in the agent’s `~/.ssh`, or an image/VM that has it preconfigured). The workflow does not inject or configure SSH keys; it assumes the environment is set up for GitCode access.
