# Agent guide — kn-action

This file is for humans and coding agents working on **kn-action**: reusable GitHub Actions workflows, composite actions, and scripts for **Kotlin Multiplatform (KMP)** and **OpenHarmony (OH)**-related CI (Kotlin compiler builds, LLVM toolchain builds, local artifact plumbing).

---

## What this repo is for

- **Orchestration**: Self-hosted GitHub Actions workflows that clone upstream repos (mostly **GitCode**), run long builds, and publish results.
- **Kotlin / OH**: Primary product path is building **Kotlin for OpenHarmony** from `CPF-KMP-CMP/kotlin` (`build-kotlin.yml`) using `scripts/build-ohos.sh` and shared prep via [`.github/actions/prepare-repo`](.github/actions/prepare-repo/README.md).
- **LLVM / OH**: **Build LLVM** (`build-llvm.yml`) uses Google **repo** + a manifest on GitCode to sync an OH LLVM workspace, then runs OH build scripts; matrix covers macOS (ARM64/X64), Linux (Docker image), Windows (X64).
- **Local artifacts**: Composite actions `upload-artifact-local` / `download-artifact-local` exchange large artifacts via **`~/runner/artifact`** on runners (not GitHub-hosted artifact storage), with a scheduled [**Cleanup artifact cache**](.github/workflows/cleanup-artifact-cache.yml) workflow.

---

## Self-hosted runners and `~/runner`

Workflows assume a **standard layout under `~/runner`** on each self-hosted machine:

| Path | Role |
|------|------|
| `~/runner/kotlin` | Runner `_work` (or equivalent) for jobs labeled **`kotlin`** |
| `~/runner/llvm` | Runner `_work` for jobs labeled **`llvm`** |
| `~/runner/cache` | Persistent caches (Konan, Maven, OH sysroot tarballs, etc., per workflow) |
| `~/runner/artifact` | Local artifact drop zone for upload/download composite actions |

**Four machines** are typically used (all reachable via SSH for debugging; exact mapping to GitHub runner names is in **Settings → Actions → Runners**):

| Host (SSH `Host` in dev config) | Verified `~/runner` (spot-check) |
|----------------------------------|----------------------------------|
| **`win`** | `artifact`, `cache`, `kotlin`, `llvm` |
| **`linux`** | same |
| **`mini`** | same |
| **This host** | The remaining macOS-class runner (e.g. Studio or your primary dev Mac). Confirm with `ls ~/runner` locally or `ssh <host> 'ls -la ~/runner'`. |

**Agent tip — before editing workflow or shell that touches paths/tools:** SSH to the relevant host and sanity-check paths and binaries, e.g.:

```bash
ssh win   'ls -la ~/runner && command -v git && ls /c/PROGRA~1/Git/bin/bash.exe'
ssh linux 'ls -la ~/runner && command -v docker'
ssh mini  'ls -la ~/runner && xcode-select -p'
```

This avoids slow “push → wait for Actions → read logs” cycles when the fix is purely environmental or path-related.

---

## Build LLVM — required runner environment

Checklist for self-hosted **`llvm`** runners so [`.github/workflows/build-llvm.yml`](.github/workflows/build-llvm.yml) can clone, `repo` sync, build, and drop **`llvm/packages`** into **`~/runner/artifact`**.

### GitHub repository configuration

| Item | Required |
|------|----------|
| **Environment** named **`env`** (workflow `environment: env`) | Yes |
| **Secret** **`GITCODE_TOKEN`** on that environment | Yes — GitCode PAT with read access; used for HTTPS `git` / `repo` against `gitcode.com` (workflow rewrites URLs in git config). |

### Every `llvm` host (macOS / Linux / Windows)

| Item | Notes |
|------|--------|
| **`~/runner/artifact`**, **`~/runner/cache`**, **`~/runner/llvm`** | Workflow assumes `ARTIFACT_LOCAL_PATH` `~/runner/artifact` and caches under `~/runner/cache`; persistent LLVM tree lives next to the job workspace under the llvm runner’s `_work`. |
| **Network** | **gitcode.com** (manifest + `repo` sync), **gitee.com** (default `repo.py` download in `setup-repo-tool.sh`), and **GitHub** ( **`actions/checkout`** fetches the action bundle from `api.github.com` — TLS/proxy issues show up as “Set up job” / checkout failures). |
| **Optional `repo init --reference`** | Workflow env **`LOCAL_REFERENCE_DIR`** defaults to **`~/git/ci/llvm-project-kmp`** (tilde expanded per job). If that directory exists on the runner, `repo init` uses **`--reference=`** to save bandwidth. |

### macOS (`llvm`)

| Item | Notes |
|------|--------|
| **Homebrew** | Workflow installs **`swig`**, **`git-lfs`**, **`java`**, **`coreutils`**, **`wget`**, **`pigz`**, **`python`** (Python 3 + pip for Google **`repo`** and **`requests`**). |
| **Xcode / CLT** | Must satisfy OH LLVM build scripts (same as local OH dev expectations). |
| **`git-lfs`** | Used after **`repo sync`** (`repo forall -c 'git lfs pull'`). |

### Linux (`llvm`, Docker job)

| Item | Notes |
|------|--------|
| **Image** | **`ghcr.io/<repo-owner>/kn-action-linux-llvm-builder:<tag>`** — pin in **`build-llvm.yml`** must match an image built from [`infra/docker/Dockerfile`](infra/docker/Dockerfile) (push under `infra/docker/**` runs [**Build Linux image**](.github/workflows/build-linux-image.yml)). |
| **Volume** | Host **`${{ github.workspace }}/../../../artifact`** mounted at **`/home/runner/runner/artifact`** so the container can write the same artifact layout as other OSes. |
| **Tools in image** | **bash**, **git**, **git-lfs**, **curl**; **Python 3** and **`python3-pip`** (required for **`scripts/setup-repo-tool.sh`**). |

### Windows (`llvm`)

| Item | Notes |
|------|--------|
| **Shell** | Workflow **`defaults.run.shell`**: **`C:\PROGRA~1\Git\bin\bash.exe`** with **`--noprofile --norc -e -o pipefail`**. **Git for Windows** must be installed there (or adjust the workflow path). |
| **Git LFS** | Not installed by the workflow on Windows. Install **Git LFS** (bundled under **Git for Windows** in **`Program Files/Git/usr/bin/git-lfs.exe`**) and run **`git lfs install`**. The workflow prepends **`…/Git/usr/bin`** to **`PATH`** and runs **`repo forall`** LFS pulls via **`bash -lc`** because **`repo`** invokes **`-c`** through **cmd.exe**, which breaks **`git lfs pull`** quoting. |
| **Python 3.12+** | Must be usable with **`python -m pip`** for **`requests`**. The workflow prepends the first match to **`GITHUB_PATH`**, in order: **`%LOCALAPPDATA%\Programs\Python\Python{314..310}`**, **`%ProgramFiles%\Python*`**, then each **`/c/Users/*/AppData/Local/Programs/Python/Python{314..310}`** (every user under **`C:\Users`**) so the service account can still find an interactive user’s install. Prefer an **all-users** install or run the listener as the user that owns Python. |
| **Service account vs interactive user** | The Actions listener often runs as **Network Service**; **`LOCALAPPDATA`** may **not** point at the user who installed Python — the **`Users/*`** scan above is the fallback. |
| **Symlinks / Developer Mode** | **`repo`** and **git** expect to create symlinks under **`.repo`**. Turn on **Settings → System → For developers → Developer Mode**. Confirm **`AllowDevelopmentWithoutDevLicense`** = **`1`** under **`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock`**, or verify **`New-Item -ItemType SymbolicLink`** works without elevation. Without this, **`repo init` / `repo sync`** fails with symlink errors. |
| **Stale `.repo` after policy changes** | If symlink mode or `repo` layout changed, remove **`…/llvm/.repo`** once on the runner or run **`workflow_dispatch`** with **`clean_build`**. |

### Kotlin `kotlin` runners (short pointer)

**Build Kotlin** does **not** use **`GITCODE_TOKEN`** in the workflow file; runners need **SSH keys** on the host for **GitCode** as documented in **`build-kotlin.yml`** / design specs below.

---

## Key workflows (overview)

| Workflow | File | Purpose |
|----------|------|---------|
| **Build Kotlin** | [`.github/workflows/build-kotlin.yml`](.github/workflows/build-kotlin.yml) | Matrix: macOS ARM64/X64, Linux X64, Windows X64 — all with label **`kotlin`**. Clones Kotlin from GitCode (SSH), optional Maven proxy, Gradle/Konan caches, archives `build/repo` to `~/runner/artifact`. |
| **Build LLVM** | [`.github/workflows/build-llvm.yml`](.github/workflows/build-llvm.yml) | Matrix: macOS ARM64/X64, Linux (Docker **`kn-action-linux-llvm-builder`**), Windows X64 — label **`llvm`**. Repo sync from GitCode (HTTPS + **`GITCODE_TOKEN`** in environment **`env`**). |
| **Cleanup artifact cache** | [`.github/workflows/cleanup-artifact-cache.yml`](.github/workflows/cleanup-artifact-cache.yml) | Hourly: delete files under `~/runner/artifact` older than 1 hour (Kotlin matrix runners). |
| **Build Linux image** | [`.github/workflows/build-linux-image.yml`](.github/workflows/build-linux-image.yml) | Builds/publishes the Linux LLVM builder image used by Build LLVM. |
| **Cancel pending runs** | [`.github/workflows/cancel-pending-runs.yml`](.github/workflows/cancel-pending-runs.yml) | Housekeeping for queued runs. |
| **Test prepare repo** | [`.github/workflows/test-prepare-repo.yml`](.github/workflows/test-prepare-repo.yml) | Exercises `prepare-repo` / polling tests. |

**Polling CI from CLI:** [`scripts/poll-workflow-run.py`](scripts/poll-workflow-run.py) — requires `gh` authenticated.

---

## Design specs — Build Kotlin (`build-kotlin.yml`)

Abstract goals the workflow should keep satisfying:

1. **Multi-platform matrix** — Same logical build (OH Kotlin) on **macOS ARM64, macOS X64, Linux X64, Windows X64**, with runner labels **`self-hosted`, `kotlin`**, plus arch/OS dimensions as today.
2. **Correct Java layout per OS** — macOS ARM64/Linux use Java 17 (and Linux also 21 where needed); macOS X64 uses 8 + 11; Windows uses setup-java as defined in the workflow — agents must not collapse these without testing all matrix legs.
3. **Incremental vs clean build** — **Clean**: ephemeral Gradle/Konan/Maven roots under `RUNNER_TEMP` (or equivalent clean root), then optional **promotion** of that cache into **`~/runner/cache`** after success. **Incremental**: persist caches under **`PERSISTED_CACHE_ROOT`** (`~/runner/cache` by default). Scheduled runs force clean behavior as documented in the workflow.
4. **Optional Maven proxy** — Reachability check against `DEFAULT_MAVEN_PROXY_URL`; if unreachable, degrade gracefully (no proxy). Init script from `scripts/maven-proxy.init.gradle` and Maven `settings.xml` mirror **`external:*`** only (do not mirror `file:` repos).
5. **GitCode source of truth** — Clone via **SSH** (`REPO_URL`); runner must already have SSH keys/config for GitCode (workflow does not inject SSH secrets).
6. **Branch / commit / MR modes** — Support building a **commit**, a **branch**, or **branch + merge-request** via `prepare-repo` inputs (see action README).
7. **Artifacts** — Pack `build/repo` into a gzip archive named with Kotlin SHA + action SHA + OS/arch; deliver to **`~/runner/artifact`** via `upload-artifact-local`.
8. **macOS toolchain check** — On macOS, verify **bitcode-build-tool** via `xcrun` early (`DEVELOPER_DIR` points at expected Xcode).

---

## Design specs — Build LLVM (`build-llvm.yml`)

Abstract goals the workflow should keep satisfying:

1. **Multi-platform LLVM builds** — Produce OH-oriented LLVM/packages on **macOS ARM64, macOS X64, Linux X64 (inside fixed Docker image), Windows X64**, labels **`llvm`**.
2. **Linux isolation** — Linux job runs in **`container.image`** from `ghcr.io/<owner>/kn-action-linux-llvm-builder:…` with a **volume** into the host artifact area (`…/artifact` → `/home/runner/runner/artifact`) so Linux matches the same local-artifact contract as other OSes.
3. **Incremental by default** — **`LLVM_WORKSPACE`** under the job workspace persists across runs; **`clean_build`** workflow input wipes it when a full rebuild is required.
4. **Conditional env prepare** — Run `env_prepare.sh` only when **`prebuilts/cmake`** (or equivalent marker) is missing — skip when incremental tree is already bootstrapped.
5. **Repo / GitCode** — **`scripts/setup-repo-tool.sh`** installs **repo** with a **wrapper** so Windows Git Bash does not rely on `#!/usr/bin/env python` alone. Sync uses **`GITCODE_TOKEN`** (repository environment **`env`**); URL rewrites in git config for GitCode HTTPS.
6. **Windows shell** — Use a Git Bash invocation that survives self-hosted Windows (e.g. **`C:\PROGRA~1\Git\bin\bash.exe`** with `pipefail`) — avoid quoted `Program Files` paths that break runner/OpenSSH command parsing. **Windows** also needs **Developer Mode** (or equivalent) so **`repo`/git symlinks** work; see **Build LLVM — required runner environment** above.
7. **OH sysroot** — Download/cache sysroot tarball under **`~/runner/cache`**; symlink into build layout as the workflow defines.
8. **Artifacts** — Archive **`llvm/packages`** (and naming/metadata) consistent with downstream **cross-copy** / **ohos-test-build** jobs in the same file; upload via local server action where configured.
9. **Fail-soft matrix** — **`fail-fast: false`** so one OS failure does not cancel others; fix and iterate per OS.

---

## Secrets and environments

- **Build LLVM** uses GitHub **environment `env`** with secret **`GITCODE_TOKEN`** (GitCode PAT for HTTPS clone/sync). Agents should not log token values.
- **Build Kotlin** relies on **host SSH** to GitCode, not that PAT in the workflow file.

---

## Conventions for agents

1. **Prefer SSH verification** on `win` / `linux` / `mini` / this host before large workflow rewrites touching paths, shells, or Docker.
2. **Keep design specs** in this file aligned when you change **`build-kotlin.yml`** or **`build-llvm.yml`** in ways that affect goals above.
3. **Push path filters** — Build LLVM triggers on `build-llvm.yml` and `scripts/setup-repo-tool.sh`; Build Kotlin on its workflow, `prepare-repo`, and `maven-proxy.init.gradle`. If you add new shared scripts, extend `paths` when appropriate.
4. **End-to-end** — After substantive workflow changes, push to **`develop`** and poll the relevant run until green or a clear external failure (TLS, runner offline, etc.).

---

## Related docs

- [README.md](README.md) — Kotlin workflow summary, poll script, Maven proxy URLs.
- [`.github/actions/prepare-repo/README.md`](.github/actions/prepare-repo/README.md) — Clone modes and outputs.
