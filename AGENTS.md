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
| **Build deps** | **`swig`**, **`git-lfs`**, **`java`**, **GNU coreutils**, **`wget`**, **`pigz`**, **Python 3** with **pip** (for Google **repo** and **requests**). Install with Homebrew or equivalent. **Tested:** Homebrew-installed set matching what the llvm macOS matrix expects. |
| **Xcode / CLT** | Must satisfy OH LLVM build scripts (same as local OH dev). **Tested:** full Xcode selected via **`xcode-select`** on the project’s macOS **`llvm`** runners (not a minimal CLT-only layout unless you have confirmed OH scripts accept it). |
| **Git LFS** | **`git-lfs`** installed and **`git lfs install`** run for the runner user. **Tested:** **`repo forall -c git lfs pull`** with **three words** after **`-c`** (`git`, `lfs`, `pull`) — on Windows/Git Bash, do not pass that as one quoted token (breaks under **cmd.exe** when repo shells out). |
| **`hdc` on `PATH`** | Needed only on hosts that run OH **device verify** / test-artifact steps: OpenHarmony **`hdc`** on **`PATH`** (e.g. symlink to DevEco’s **`…/openharmony/toolchains/hdc`**). |

#### Local environment dependencies (build-llvm — device verify)

For **`hdc-ohos-verify`** / **Execute test artifacts**: install or link **`hdc`** so `command -v hdc` succeeds for the runner user; connect at least one OH device when exercising that job.

### Linux (`llvm`, Docker job)

| Item | Notes |
|------|--------|
| **Image** | **`ghcr.io/<repo-owner>/kn-action-linux-llvm-builder:<tag>`** — pin in **`build-llvm.yml`** must match an image built from [`infra/docker/Dockerfile`](infra/docker/Dockerfile) (push under `infra/docker/**` runs [**Build Linux image**](.github/workflows/build-linux-image.yml)). |
| **Volume** | Host **`${{ github.workspace }}/../../../artifact`** mounted at **`/home/runner/runner/artifact`** so the container can write the same artifact layout as other OSes. |
| **Base tooling** | Image provides **bash**, **git**, **git-lfs**, **curl**, **Python 3**, and a **pip**-usable install (same contract as **`kn-action-linux-llvm-builder`** from [`infra/docker/Dockerfile`](infra/docker/Dockerfile)). |

### Windows (`llvm`)

| Item | Notes |
|------|--------|
| **Shell** | Workflow **`defaults.run.shell`**: **`C:\PROGRA~1\Git\bin\bash.exe`** with **`--noprofile --norc -e -o pipefail`**. **Git for Windows** must be installed there (or adjust the workflow path). |
| **Git LFS** | Install **Git LFS** (bundled with **Git for Windows** under **`mingw64/bin`** or **`usr/bin`**) and run **`git lfs install`**. The workflow prepends those dirs to **`PATH`**. Use **`repo forall -c git lfs pull`** without shell-quoting the command into one token (see macOS row). |
| **Python 3.12+** | Must be usable with **`python -m pip`** for **`requests`**. The workflow prepends the first match to **`GITHUB_PATH`**, in order: **`%LOCALAPPDATA%\Programs\Python\Python{314..310}`**, **`%ProgramFiles%\Python*`**, then each **`/c/Users/*/AppData/Local/Programs/Python/Python{314..310}`** (every user under **`C:\Users`**) so the service account can still find an interactive user’s install. Prefer an **all-users** install or run the listener as the user that owns Python. |
| **Service account vs interactive user** | The Actions listener often runs as **Network Service**; **`LOCALAPPDATA`** may **not** point at the user who installed Python — the **`Users/*`** scan above is the fallback. |
| **Symlinks / Developer Mode** | **`repo`** and **git** expect to create symlinks under **`.repo`**. Turn on **Settings → System → For developers → Developer Mode**. Confirm **`AllowDevelopmentWithoutDevLicense`** = **`1`** under **`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock`**, or verify **`New-Item -ItemType SymbolicLink`** works without elevation. Without this, **`repo init` / `repo sync`** fails with symlink errors. |
| **Stale `.repo` after policy changes** | If symlink mode or `repo` layout changed, remove **`…/llvm/.repo`** once on the runner or run **`workflow_dispatch`** with **`clean_build`**. |
| **LLVM prebuilts (first / clean run)** | **`toolchain/.../env_prepare.sh`** only supports **Linux/Darwin** **`uname`**. On Windows the workflow runs [**`scripts/ohos-env-prepare-windows.sh`**](scripts/ohos-env-prepare-windows.sh) and [**`scripts/ohos-build-llvm-windows.sh`**](scripts/ohos-build-llvm-windows.sh) (MingW Python / **`build.py`**) instead of **`build.sh`**’s hardcoded Linux paths. |

### Kotlin `kotlin` runners

**Build Kotlin** does **not** use **`GITCODE_TOKEN`**; clone uses **SSH** to **GitCode** (`REPO_URL` in **`build-kotlin.yml`**). Non-Windows runners: install **`~/.ssh`** for the user that runs the job.

#### Windows `kotlin` — GitCode SSH (one-time host setup)

The listener usually runs as **`NT AUTHORITY\NETWORK SERVICE`**, so job **`$HOME`** is **`C:\Windows\ServiceProfiles\NetworkService`**. **Setup environment** only verifies **`$HOME/.ssh/id_ed25519`** and **`$HOME/.ssh/known_hosts`** exist and exports **`GIT_SSH_COMMAND`** (explicit **`-i`**, **`IdentitiesOnly=yes`**, **`UserKnownHostsFile`**, **`StrictHostKeyChecking=yes`**). No copying, **`ssh-keyscan`**, or **`accept-new`** in CI.

| Requirement | What to do |
|-------------|------------|
| **Key pair** | **`id_ed25519`** + **`id_ed25519.pub`** in **`C:\Windows\ServiceProfiles\NetworkService\.ssh\`** (e.g. `scp … win:C:/Windows/ServiceProfiles/NetworkService/.ssh/`). |
| **Private key ACL** | `icacls "C:\Windows\ServiceProfiles\NetworkService\.ssh\id_ed25519" /inheritance:r /grant:r "NT AUTHORITY\NETWORK SERVICE:(R)" /grant:r "NT AUTHORITY\SYSTEM:(F)"` |
| **`known_hosts`** | Include **gitcode.com** (e.g. `ssh-keyscan -t rsa gitcode.com >> "C:\Windows\ServiceProfiles\NetworkService\.ssh\known_hosts"`). |
| **GitCode** | Authorize the **public** key for **`CPF-KMP-CMP/kotlin`**. **`Permission denied (publickey)`** → key not registered on GitCode. |
| **Optional** | Same key under **`C:\Users\<admin>\.ssh\`** for interactive **`ssh win 'git ls-remote …'`** checks. |

---

## Key workflows (overview)

| Workflow | File | Purpose |
|----------|------|---------|
| **Build Kotlin** | [`.github/workflows/build-kotlin.yml`](.github/workflows/build-kotlin.yml) | Matrix: macOS ARM64/X64, Linux X64, Windows X64 — all with label **`kotlin`**. Clones Kotlin from GitCode (SSH), optional Maven proxy, Gradle/Konan caches, archives `build/repo` to `~/runner/artifact`. |
| **Build LLVM** | [`.github/workflows/build-llvm.yml`](.github/workflows/build-llvm.yml) | Matrix: macOS ARM64/X64, Linux (Docker **`kn-action-linux-llvm-builder`**) — label **`llvm`**; Windows host Clang ships in Linux **`packages/`** and is tested on a Windows **`llvm`** runner after cross-copy. Repo sync from GitCode (HTTPS + **`GITCODE_TOKEN`** in environment **`env`**). |
| **Cleanup artifact cache** | [`.github/workflows/cleanup-artifact-cache.yml`](.github/workflows/cleanup-artifact-cache.yml) | Hourly: delete files under `~/runner/artifact` older than 1 hour (Kotlin matrix runners). |
| **Build Linux image** | [`.github/workflows/build-linux-image.yml`](.github/workflows/build-linux-image.yml) | Builds/publishes the Linux LLVM builder image used by Build LLVM. |
| **Cancel pending runs** | [`.github/workflows/cancel-pending-runs.yml`](.github/workflows/cancel-pending-runs.yml) | Housekeeping for queued runs. |
| **Test prepare repo** | [`.github/workflows/test-prepare-repo.yml`](.github/workflows/test-prepare-repo.yml) | Exercises `prepare-repo` / polling tests. |

**Polling CI from CLI:** [`scripts/poll-workflow-run.py`](scripts/poll-workflow-run.py) — requires `gh` authenticated. For matrix workflows, `--job-substring Windows` waits only until `build (Windows-X64)` (or any job whose name contains that substring) finishes and ignores other legs.

---

## Design targets — Build Kotlin (`build-kotlin.yml`)

Goals the workflow should keep satisfying (details live in the workflow and scripts):

1. **Multi-platform matrix** — Same logical OH Kotlin build on **macOS ARM64, macOS X64, Linux X64, Windows X64** with **`self-hosted`** + **`kotlin`** labels and the usual OS/arch split.
2. **Per-leg toolchain** — Keep Java versions and Windows job shell behavior aligned with what each matrix leg needs; treat any consolidation across legs as a full-matrix change.
3. **Incremental vs clean** — **Incremental** uses **`~/runner/cache`** as the Gradle/Konan/Maven root for the whole job (**Setup environment** in [`build-kotlin.yml`](.github/workflows/build-kotlin.yml)). **Clean** (workflow input or **schedule**) uses a tree under **`RUNNER_TEMP`** for the build; on **success**, **Promote clean build cache to persisted Gradle home** **replaces** **`~/runner/cache`** with it (`rm -rf` on the persisted root, then `mv` from the clean tree). That promotion is part of the clean path, not an optional knob—the step only no-ops if the ephemeral cache directory is missing.
4. **Maven / Gradle mirroring** — When a LAN Maven mirror is available, use it; when not, continue without it. Never break `file:` or other local repos. When mirroring is on, keep Gradle distribution fetches consistent with that mirror story.
5. **GitCode via SSH** — Clone from GitCode using host SSH identity only (no SSH secrets in the workflow). Windows **`kotlin`** runners follow the **NetworkService** **`~/.ssh`** layout described above.
6. **Source selection** — Build a specific **commit**, **branch**, or **branch + merge request** via `prepare-repo` (see the action README).
7. **Artifacts** — Ship **`build/repo`** as compressed archives into **`~/runner/artifact`**, with names that identify Kotlin revision, workflow/action revision, and platform.
8. **macOS toolchain** — On macOS, detect a bad or missing Xcode toolchain early (e.g. **bitcode-build-tool**), before expensive work.
9. **Local proxy mode** — When enabled, route dependency and plugin downloads through the LAN proxy and avoid hitting upstreams directly where the design allows.

---

## Design targets — Build LLVM (`build-llvm.yml`)

Goals the workflow should keep satisfying (details live in the workflow and scripts):

1. **Multi-platform LLVM builds** — Produce OH-oriented **`llvm/packages`** on **macOS ARM64, macOS X64, Linux X64 (Docker)**; the **Windows** host Clang package (**`clang-dev-windows-x86_64.tar.gz`**) is expected **inside the Linux** `packages/` tarball and is merged in **cross-copy** (native Windows LLVM compile in the build matrix stays optional).
2. **Linux isolation** — Linux job runs in **`container.image`** from `ghcr.io/<owner>/kn-action-linux-llvm-builder:…` with a **volume** into the host artifact area (`…/artifact` → `/home/runner/runner/artifact`) so Linux matches the same local-artifact contract as other OSes.
3. **Incremental vs clean** — **`LLVM_WORKSPACE`** is the **`llvm`** directory alongside the checked-out **`kn-action`** job workspace (see **`LLVM_WORKSPACE`** in [`build-llvm.yml`](.github/workflows/build-llvm.yml)). On self-hosted runners it is reused across runs because the Actions work directory persists. There is **no** Kotlin-style promotion of the LLVM tree into **`~/runner/cache`**; **`~/runner/cache`** is for things like the OH sysroot tarball, not the main LLVM checkout. **`clean_build`** **`rm -rf`s the parent of `GITHUB_WORKSPACE`** (entire job work root), rechecks out **`kn-action`**, and **`repo init`** runs when **`.repo`** is missing or clean is set—see **Setup environment**, **Re-checkout kn-action after clean workspace wipe**, and **Init repo manifest**. Expect much faster runs when the tree is unchanged and clean is off. **`repo sync`** can still touch many files each run, so Ninja may rebuild heavily; **[`scripts/setup-llvm-ccache.sh`](scripts/setup-llvm-ccache.sh)** enables **ccache** ( **`CC`/`CXX`** wrappers, **`CMAKE_*_COMPILER_LAUNCHER`**, Linux **`/usr/lib/ccache`** on **`PATH`**). **Linux (Docker)** keeps **`CCACHE_DIR`** under **`GITHUB_WORKSPACE/.ccache`** so the cache sits on the mounted work tree; **macOS** uses **`~/runner/cache/llvm-ccache-<os>-<arch>`**. The **Build LLVM** step appends **`ccache -s`** to the job summary for hit-rate verification.
4. **Conditional env prepare** — Run **`env_prepare`** only when the workspace lacks the usual bootstrap marker (e.g. **`prebuilts/cmake`**); skip when the tree is already prepared.
5. **Repo / GitCode** — **`scripts/setup-repo-tool.sh`** installs **repo** with a **wrapper** so Windows Git Bash does not rely on `#!/usr/bin/env python` alone. Sync uses **`GITCODE_TOKEN`** (repository environment **`env`**); URL rewrites in git config for GitCode HTTPS.
6. **Windows shell** — Use a Git Bash invocation that survives self-hosted Windows (e.g. **`C:\PROGRA~1\Git\bin\bash.exe`** with `pipefail`) — avoid quoted `Program Files` paths that break runner/OpenSSH command parsing. **Windows** also needs **Developer Mode** (or equivalent) so **`repo`/git symlinks** work; see **Build LLVM — required runner environment** above.
7. **OH sysroot** — Download/cache sysroot tarball under **`~/runner/cache`**; symlink into build layout as the workflow defines.
8. **Artifacts** — Archive **`llvm/packages`** (and naming/metadata) consistent with downstream **cross-copy** / **ohos-test-build** jobs in the same file; upload via local server action where configured. **cross-copy** runs **`platform_package.sh`** with **`clang-dev-windows-x86_64.tar.gz`** from the Linux `packages/` tree (alongside Darwin tars) and publishes **gzip-compressed** **`llvm-<major>-<konan_triple>-essentials-<id>-run<github_run_id>.tar.gz`** on the LAN server (unique basename per run; **`GZIP=-9 tar -czf`**, not a dependency on **pigz** in the cross-copy job). **Inside** the archive, the first member is exactly one top-level directory **`llvm-<major>-<konan_triple>-essentials-<id>/`** (Konan **`~/.konan/dependencies`** layout; no **`-run…`** in the folder name). **Darwin** and **Windows** essentials flatten the merged host clang tree: **`bin/`**, **`lib/`**, etc. live **directly** under that directory (not under **`clang_*-*-<timestamp>/`**). **Linux** keeps **`clang-dev/`** or **`clang/`** as produced by the upstream tarball. Workflow inputs **`final_llvm_artifact_version`** (essentials id, default **200**) and **`llvm_major_version`** (default **19**) control that stem; not **`llvm-merged-ohos-*`** / not raw outer **`llvm-packages-*.tar`** in **ohos-test-build**.
9. **Fail-soft matrix** — **`fail-fast: false`** so one OS failure does not cancel others; fix and iterate per OS.

---

## Secrets and environments

- **Build LLVM** uses GitHub **environment `env`** with secret **`GITCODE_TOKEN`** (GitCode PAT for HTTPS clone/sync). Agents should not log token values.
- **Build Kotlin** relies on **host SSH** to GitCode, not that PAT in the workflow file.

---

## Conventions for agents

1. **Prefer SSH verification** on `win` / `linux` / `mini` / this host before large workflow rewrites touching paths, shells, or Docker.
2. **Keep design targets** in this file aligned when you change **`build-kotlin.yml`** or **`build-llvm.yml`** in ways that affect goals above or adds new goals.
3. **Push path filters** — Build LLVM triggers on `build-llvm.yml` and `scripts/setup-repo-tool.sh`; Build Kotlin on its workflow, `prepare-repo`, and `proxy.init.gradle`. If you add new shared scripts, extend `paths` when appropriate.
4. **End-to-end** — After substantive workflow changes, push to **`develop`** and poll the relevant run until green or a enviromental issue you can't resolve, like runner offline.

---

## Related docs

- [README.md](README.md) — Kotlin workflow summary, poll script, Maven proxy URLs.
- [`.github/actions/prepare-repo/README.md`](.github/actions/prepare-repo/README.md) — Clone modes and outputs.
