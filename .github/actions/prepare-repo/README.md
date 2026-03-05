# Prepare repo

Reusable composite action: setup a local repo to match branch/commit/PR then force a clean state. Outputs HEAD SHA and `workspace_dir` for downstream steps.

## Purpose

- Clone into a workspace directory, or reuse an existing clone.
- Resolve to a **commit**, a **branch**, or **branch + PR** (fetch merge-request ref and merge into branch).
- Run `git clean -dfx` and `git reset --hard` so the working tree matches HEAD.
- Output `sha` (HEAD commit) and `workspace_dir` for later steps.

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `repo_url` | Git clone ssh/https URL (required) | — |
| `branch` | Branch to build (required for branch or branch+PR mode) | — |
| `pr_number` | Merge/pull request number to merge into branch | — |
| `commit` | Commit SHA to build (overrides branch/PR when set) | — |
| `workspace_dir` | Directory to clone into | `ci-workspace` |
| `local_reference_dir` | Base dir for local reference repo (path = this dir + repo name from URL) | `$HOME/git/ci/` |
| `mr_ref_template` | Ref template for merge request fetch (`%s` = PR number). GitLab/GitCode default; use `refs/pull/%s/head` for GitHub | `refs/merge-requests/%s/head` |

## Outputs

| Output | Description |
|--------|-------------|
| `sha` | HEAD commit SHA of the prepared repo |
| `workspace_dir` | Directory where the repo was cloned (for `cd` in next steps) |

## Resolution rules

1. **If `commit` is set** → Fetch that commit and checkout it (branch/PR ignored).
2. **Else if both `branch` and `pr_number` are set** → Checkout `branch`, fetch the MR ref using `mr_ref_template`, merge into branch, then clean/reset.
3. **Else** → Checkout `branch` (branch required). Then clean/reset.

## Local reference

Reference path = `local_reference_dir` + repo name from URL (e.g. `~/git/ci/test-prepare-repo`). If that path exists and is a git repo, clone and fetch use `--reference` for faster operations.

## Reuse

If `workspace_dir` already contains `.git`, the action reuses it: sets origin URL, fetches, then resolves commit/branch/PR as above, then `git clean -dfx` and `git reset --hard`.

## How to test

**Locally:** Run from the repo root (tests both SSH and HTTPS remotes; requires GitCode access):

```bash
bash .github/actions/prepare-repo/test.sh
```

**CI:** The workflow [Test prepare-repo](.github/workflows/test-prepare-repo.yml) runs the test on `ubuntu-latest`, `macos-latest`, and `windows-latest` when files under `.github/actions/prepare-repo/` change. For full tests (SSH + HTTPS), add repository secret `GITCODE_SSH_PRIVATE_KEY` (deploy key for `linhandev/test-prepare-repo` with read access).
