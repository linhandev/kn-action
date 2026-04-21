# Agent guide — kn-action

This file is for humans and coding agents working on **kn-action**: **GitLab CI** on a LAN instance, shell scripts, and shared **prepare-repo** tooling for **Kotlin Multiplatform (KMP)** and **OpenHarmony (OH)**-related builds (Kotlin compiler, LLVM toolchain, local artifact plumbing). Upstream sources are mostly on **GitCode**.

---

## What this repo is for

- **Orchestration**: Pipelines clone upstream repos (mostly **GitCode**), run long builds, and publish results; primary CI entry is **`.gitlab-ci.yml`** (expand with **`include:`** as Kotlin/LLVM jobs land).
- **Kotlin / OH**: Building **Kotlin for OpenHarmony** via `scripts/build-ohos.sh` and repo prep through [`.github/actions/prepare-repo`](.github/actions/prepare-repo/README.md) (invoked from CI scripts; path is historical).
- **LLVM / OH**: Google **repo** with `--standalone-manifest` using manifest files in `manifest/` directory (e.g. `llvm-1914.xml`, `llvm-1914-bare.xml`, `llvm-1917.xml`) to sync an OH LLVM workspace; Linux LLVM builds typically use a **Docker** image built from [`infra/docker/Dockerfile`](infra/docker/Dockerfile).
- **Local artifacts**: Large outputs use **`~/runner/artifact`** and the LAN artifact server; **`upload-artifact-local` / `download-artifact-local`** composite actions implement the same contract for any CI that calls their shell scripts with the variables below.

---

## Host layout: `~/runner` and `~/gitlab-runner`

| Path | Role |
|------|------|
| **`~/gitlab-runner/kotlin`** | GitLab Runner **`builds_dir`** for **Kotlin**-tagged registrations (limit 1; all hosts). |
| **`~/gitlab-runner/llvm`** | GitLab Runner **`builds_dir`** for **LLVM**-tagged registrations (limit 1; all hosts). |
| **`~/gitlab-runner/chore`** | GitLab Runner **`builds_dir`** for **Chore**-tagged registrations (limit 2; lightweight merge/verify/test). |
| **`~/runner/artifact`** | Local artifact drop zone (aligned with composite action scripts). |
| **`~/gitlab-runner/cache`** | Persistent caches (Konan, Maven, OH sysroot tarballs, ccache, etc.). |
| **`~/runner/kotlin`**, **`~/runner/llvm`** | Optional extra dirs for disk organization or non-GitLab automation; **GitLab job checkouts** stay under **`~/gitlab-runner/…`**, not here. |

**Four machines** are typically used (SSH **`Host`** names: **`linux`**, **`win`**, **`mini`**, **studio**):

| Host | Spot-check |
|------|------------|
| **`win`**, **`linux`**, **`mini`** | `ls ~/runner` / `ls ~/gitlab-runner` as needed |
| **studio** | This Mac; confirm paths locally |

### Three-tier runner design (kotlin / llvm / chore)

**Policy:** **Three separate GitLab Runner registrations** per host — **`kotlin`**, **`llvm`**, and **`chore`**. Each registration advertises **exactly one** role tag. No registration may advertise more than one role.

| Role | Purpose | `limit` | `builds_dir` |
|------|---------|---------|--------------|
| **`kotlin`** | Heavy Kotlin/KMP builds | **1** | **`~/gitlab-runner/kotlin`** |
| **`llvm`** | Heavy LLVM compiles (`repo sync` + `build.py`) | **1** | **`~/gitlab-runner/llvm`** |
| **`chore`** | Lightweight merge/verify/test (cross-copy, artifact-refs, ohos-test, hdc-verify) | **2** | **`~/gitlab-runner/chore`** |

**Global `concurrent = 4`** on each host (1 kotlin + 1 llvm + 2 chore). Per-stanza **`limit`** caps each role.

**Why three tiers:**

- **LLVM** and **Kotlin** builds are long-running, resource-intensive, and manage large on-disk workspaces (`repo sync` tree, Gradle cache). They must not compete for CPU/RAM. **`limit = 1`** prevents overlapping heavy builds.
- **Chore** jobs (cross-copy, ohos-test, hdc-verify, artifact-refs) are lightweight (bash, curl, tar, small compiles). They were previously blocked behind heavy builds on the same runner. With **`limit = 2`** on a separate registration, two chore jobs can run concurrently without starving or being starved by builds.
- A **chore** job never needs Docker on Linux — all chore scripts use standard shell tools.

**Hardware:** Prefer dedicated machines per role; if one host runs all three, use **three registrations** with different **`builds_dir`** values.

**Agent tip — before editing CI or shell that touches paths/tools:** SSH to the host and verify paths and binaries:

```bash
ssh win   'ls -la ~/runner ~/gitlab-runner 2>/dev/null; command -v git'
ssh linux 'ls -la ~/runner ~/gitlab-runner 2>/dev/null; command -v docker'
ssh mini  'ls -la ~/runner ~/gitlab-runner 2>/dev/null; xcode-select -p'
```

---

## Build LLVM — required runner environment

Checklist so **`llvm`**-tagged runners can **`repo` sync**, build, and drop **`llvm/packages`** into **`~/runner/artifact`**.

### Every `llvm` host (macOS / Linux / Windows)

| Item | Notes |
|------|------|
| **`~/runner/artifact`**, **`~/gitlab-runner/cache`** | Scripts expect artifact output and caches here; bind-mount or ensure paths inside Docker match this layout. |
| **Network** | **gitcode.com**, **gitee.com** (default **`repo.py`** fetch in **`setup-repo-tool.sh`**). HTTPS **`repo`** remotes are expected to be **public** (no CI PAT); use **SSH** on the runner for private upstreams. |
| **Optional `repo init --reference`** | **`LOCAL_REFERENCE_DIR`** defaults to **`~/git/ci/llvm-project-kmp`** when set on the host. |

### macOS (`llvm`)

| Item | Notes |
|------|------|
| **Build deps** | **`swig`**, **`git-lfs`**, **`java`**, **GNU coreutils**, **`wget`**, **`pigz`**, **Python 3** + **pip** (**repo**, **requests**). |
| **Xcode / CLT** | Must satisfy OH LLVM build scripts; full Xcode via **`xcode-select`** is the tested layout. |
| **Git LFS** | **`git lfs install`**; **`repo forall -c git lfs pull`** — use **three** words after **`-c`**, not one quoted token (Windows/Git Bash). |
| **`hdc` on `PATH`** | For device-verify steps: OpenHarmony **`hdc`** (e.g. DevEco toolchains). |

### Linux (`llvm`, Docker executor)

| Item | Notes |
|------|------|
| **Image** | **`ghcr.io/<repo-owner>/kn-action-linux-llvm-builder:<tag>`** — pin must match [`infra/docker/Dockerfile`](infra/docker/Dockerfile). |
| **Container user** | **root** (default for the image). `$HOME=/root` inside the container; `builds_dir` and volume mount targets use `/root/…` paths. |
| **Volumes** | Bind-mount host paths into container `/root/…`: **`~/gitlab-runner/llvm:/root/gitlab-runner/llvm`**, **`~/gitlab-runner/cache:/root/gitlab-runner/cache`**, **`~/runner/artifact:/root/runner/artifact`**. This keeps the `~/gitlab-runner/…` convention uniform — `~` is `/home/user` on the host and `/root` inside the container. |
| **Base tooling** | Image provides **bash**, **git**, **git-lfs**, **curl**, **Python 3**, **pip**, **ccache**, **ninja-build**. |

### Windows (`llvm`)

| Item | Notes |
|------|------|
| **Shell** | **Git Bash** (**`C:\PROGRA~1\Git\bin\bash.exe`**) with **`pipefail`** is the tested shell for repo/build scripts. |
| **Git LFS** | Install and **`git lfs install`**; **`repo forall -c git lfs pull`** (see macOS). |
| **Python 3.12+** | **`python -m pip`** for **`requests`**; ensure the **GitLab Runner** service user’s **`PATH`** includes Python (all-users install or user-aligned service account). |
| **Symlinks / Developer Mode** | **Developer Mode** (or equivalent) so **`.repo`** symlinks work. |
| **Stale `.repo`** | After policy changes, remove **`…/llvm/.repo`** once or run a clean job. |
| **LLVM prebuilts** | **`env_prepare.sh`** is Linux/Darwin-**`uname`** oriented; Windows uses [**`scripts/ohos-env-prepare-windows.sh`**](scripts/ohos-env-prepare-windows.sh) and [**`scripts/ohos-build-llvm-windows.sh`**](scripts/ohos-build-llvm-windows.sh). |

### Kotlin `kotlin` runners — GitCode SSH

Clone uses **SSH** to GitCode. Install **`~/.ssh`** (for the **user that runs the runner**): **`id_ed25519`**, **`known_hosts`** for **gitcode.com**, **`StrictHostKeyChecking`**, no **`accept-new`** in CI. Authorize the public key for **`CPF-KMP-CMP/kotlin`**.

On **Windows**, if the runner runs as a service account, place keys under **that account’s** home (e.g. **`…/ServiceProfiles/NetworkService/.ssh`** or the service user you configure) and lock down private key ACLs.

---

## Product goals (scripts + pipelines)

Keep these in mind when changing **`scripts/`** or CI:

**Kotlin**

- Multi-platform matrix (**macOS** arm64/x64, **Linux** x64, **Windows** x64) with consistent toolchains per OS.
- **Incremental** builds reuse **`~/gitlab-runner/cache`** (Gradle/Konan/Maven); **clean** builds use an ephemeral tree then may **promote** cache on success (see existing script/workflow logic you port).
- **GitCode via SSH** — host identity only for clones where designed.
- **prepare-repo** for commit/branch/MR selection (see action README).
- **Artifacts** under **`~/runner/artifact`** with names that encode revision, pipeline id, and platform.
- Optional LAN **Maven/Gradle** mirror and **proxy** mode when available.

**LLVM**

- Produce OH-oriented **`llvm/packages`** on **macOS**, **Linux** (Docker), and validate **Windows** packages as needed.
- **Manifest selection**: CI input `llvm_manifest` selects manifest file from `manifest/` directory. Options: `llvm-1914.xml` and `llvm-1914-bare.xml` (KMP LLVM 19.1.4 from `linhandev/mpcore-llvm-kmp`), `llvm-1917.xml` (OH LLVM 19.1.7 from `openharmony/third_party_llvm-project`). Uses `repo init --standalone-manifest` with `file://` path; no separate manifest git repo needed.
- **Persistent LLVM workspace** under the job checkout when not cleaning; **`~/gitlab-runner/cache`** for sysroot/ccache, not the main monorepo tree.
- **ccache** is configured inline in [**`scripts/ci/llvm-build.sh`**](scripts/ci/llvm-build.sh): exports `CMAKE_{C,CXX}_COMPILER_LAUNCHER=ccache` (CMake 3.21+ reads these from env; OH `build.py` never sets them via `-D`). Default `CCACHE_DIR=${CCACHE_DIR:-~/gitlab-runner/cache/llvm-ccache}`, `max_size=10G`. CI jobs or `config.toml` can pre-set `CCACHE_DIR` when `$HOME` inside the container differs from the host (Docker root → `/root/…`). Docker runners must bind-mount **`~/gitlab-runner/cache`** into the container at the path matching the container's `$HOME`.
- **Conditional `env_prepare`** when the tree lacks bootstrap markers.
- **Repo** via [**`scripts/setup-repo-tool.sh`**](scripts/setup-repo-tool.sh) (Windows wrapper for **`python`**).
- **Artifacts** and **`platform_package.sh`** naming aligned with Konan dependency layout (flattened host trees in published tarballs/zip).
- **Multi-platform**: prefer **`fail-fast: false`** so one OS does not cancel others.
- **GitLab merge (`llvm:cross-copy`)**: run on **`chore-macos-arm64`** (Apple Silicon **chore** runner, e.g. **studio`). Cross-copy is **merge + `platform_package.sh` packaging** over tarballs; it does **not** require executing the produced LLVM on the merge host—downstream **`ohos:build-test:*`** jobs validate per OS.
- **Artifacts**: Build jobs upload outer tars directly to **LAN artifact server** (no GitLab artifacts). `llvm:artifact-refs` waits for build jobs (optional) then queries server for latest names. `llvm:cross-copy` downloads from server and produces final archives. Dependency: `artifact-refs` → `build:llvm:*` (optional) → `cross-copy` → `artifact-refs` only.

### LLVM build performance checklist

1. **On-demand downloads / env setup**: `env_prepare.sh`, `setup-repo-tool.sh`, and `repo init` run only when their outputs are missing. The script checks one representative binary from each prebuilt tarball (cmake, ninja, clang bootstrap, python3) before deciding to run `env_prepare`.
2. **ccache**: Must produce cache hits on repeat builds. `CCACHE_DIR` is on a persistent volume (`~/gitlab-runner/cache/llvm-ccache`). Docker mounts must map it to the container's `$HOME`. Verify with `ccache -s` after build (printed by the script).
3. **Skip build when source unchanged**: When `repo sync` leaves the LLVM source tree at the same commit as the last successful build AND `packages/` already exists from that build, the compile step can be skipped. *(Not yet implemented — planned.)*

---

## Conventions for agents

1. **Prefer SSH verification** on **`win`**, **`linux`**, **`mini`**, **studio** before large path or shell changes.
2. **Align** this file when CI or **`scripts/`** change behavior that operators rely on.
3. **GitLab branch** **`gitlab`**: push to remote **`gl`** (LAN); **`origin`** is optional for that branch.
4. **End-to-end**: after CI changes, push and watch the pipeline on GitLab until green or an environment issue blocks you.

---

## Self-hosted GitLab (LAN)

GitLab and runners are **LAN-only**. URLs use the GitLab host’s **static LAN IP**.

### GitLab server (host: `linux`)

| Item | Value |
|------|--------|
| **Web UI (LAN)** | `http://192.168.3.6:8929` |
| **Web UI (public)** | `http://139.159.236.211:11000` — same instance, different route |
| **`glab` CLI** | **Do NOT configure `GITLAB_HOST` or use `--hostname` flag** — the self-hosted GitLab serves HTTP, not HTTPS. Let `glab` use its default remote detection from the repo's `gl` remote URL (SSH `git@192.168.3.6:2222`). Commands like `glab ci status -R linhandev/kn-action` work without host overrides. |
| **Git over SSH** | `git@192.168.3.6`, port **2222** (GitLab shell in Docker; host SSH stays **22**) |
| **Deployment** | Docker **`gitlab/gitlab-ce`**, data under **`~/gitlab/`** on **`linux`** |
| **Operator notes** | **`~/gitlab/SETUP.txt`** on **`linux`** — e.g. **`docker restart gitlab`**; initial root password via **`docker exec gitlab grep '^Password:' /etc/gitlab/initial_root_password`** |

### Four-host runner matrix

SSH hosts: **`linux`**, **`win`**, **`mini`**, **studio**. **Twelve** registrations: **Kotlin + LLVM + Chore on each host**. **`.gitlab-ci.yml`** **`prepare-repo`** tests use **Kotlin** runners only.

**Naming (`--description`):** **`{kotlin|llvm|chore}-{os}-{arch}`** only (e.g. **`kotlin-linux-x64`**, **`chore-macos-arm64`**). Do not embed SSH host names or executor type in the description.

**Tags:** exactly **three**: role (**`kotlin`** / **`llvm`** / **`chore`**), OS (**`linux`**, **`windows`**, **`macos`**), arch (**`x64`** / **`arm64`**). No **`docker`** tag — LLVM on Linux uses **`executor = "docker"`** in **`config.toml`**; jobs with **`image:`** select that runner via tags + executor.

**Runner `builds_dir` (spec, all hosts):** **`~/gitlab-runner/{kotlin,llvm,chore}`**. On Windows: **`/c/Users/<user>/gitlab-runner/{kotlin,llvm,chore}`** (Git Bash paths).

| SSH host | Runner name | Tags | Executor | `limit` | `builds_dir` |
|----------|-------------|------|----------|---------|--------------|
| **`linux`** | `kotlin-linux-x64` | `kotlin`, `linux`, `x64` | **shell** | 1 | **`~/gitlab-runner/kotlin`** |
| **`linux`** | `llvm-linux-x64` | `llvm`, `linux`, `x64` | **docker** | 1 | **`/root/gitlab-runner/llvm`** (container) |
| **`linux`** | `chore-linux-x64` | `chore`, `linux`, `x64` | **shell** | 2 | **`~/gitlab-runner/chore`** |
| **`win`** | `kotlin-windows-x64` | `kotlin`, `windows`, `x64` | **shell** (Git Bash) | 1 | **`/c/Users/lin/gitlab-runner/kotlin`** |
| **`win`** | `llvm-windows-x64` | `llvm`, `windows`, `x64` | **shell** (PowerShell) | 1 | **`C:/Users/lin/gitlab-runner/llvm`** |
| **`win`** | `chore-windows-x64` | `chore`, `windows`, `x64` | **shell** (Git Bash) | 2 | **`/c/Users/lin/gitlab-runner/chore`** |
| **`studio`** | `kotlin-macos-arm64` | `kotlin`, `macos`, `arm64` | **shell** | 1 | **`~/gitlab-runner/kotlin`** |
| **`studio`** | `llvm-macos-arm64` | `llvm`, `macos`, `arm64` | **shell** | 1 | **`~/gitlab-runner/llvm`** |
| **`studio`** | `chore-macos-arm64` | `chore`, `macos`, `arm64` | **shell** | 2 | **`~/gitlab-runner/chore`** |
| **`mini`** | `kotlin-macos-x64` | `kotlin`, `macos`, `x64` | **shell** | 1 | **`~/gitlab-runner/kotlin`** |
| **`mini`** | `llvm-macos-x64` | `llvm`, `macos`, `x64` | **shell** | 1 | **`~/gitlab-runner/llvm`** |
| **`mini`** | `chore-macos-x64` | `chore`, `macos`, `x64` | **shell** | 2 | **`~/gitlab-runner/chore`** |

**Windows:** Runner install under **`%USERPROFILE%\gitlab-runner\`**, config **`config.toml`**, service user matches **`%USERPROFILE%`**.

**Linux:** **`~/gitlab-runner/config.toml`**. System packages may use **`/etc/gitlab-runner/config.toml`** instead.

**macOS:** **`~/gitlab-runner/config.toml`** (**`studio`**: arm64 names; **`mini`**: x64 names). Three stanzas per host. **`name`** in **`config.toml`** should match the GitLab runner **description** above.

**`config.toml` template (each host):**

```toml
concurrent = 4

[[runners]]  # kotlin
  limit = 1
  ...

[[runners]]  # llvm
  limit = 1
  ...

[[runners]]  # chore
  limit = 2
  ...
```

**API automation:** Short-lived root PATs for **`POST /api/v4/user/runners`** — revoke immediately; do not commit tokens.

### Test `prepare-repo` (`.gitlab-ci.yml`)

**Four** jobs — **Kotlin** runners, **three tags** each. Runs [`.github/actions/prepare-repo/test.sh`](.github/actions/prepare-repo/test.sh) (SSH + HTTPS to **`linhandev/test-prepare-repo`** on GitCode). **macOS** **`arm64`** targets **`studio`** (Apple Silicon); **`macos-x64`** targets **`mini`** (Intel).

| Item | Notes |
|------|--------|
| **Trigger** | **`workflow:rules`**: `schedule`, **`web`**, **`push`/`merge_request_event`** when **`.github/actions/prepare-repo/**`**, **`.gitlab-ci.yml`**, or related paths change. |
| **Tags** | **`test:prepare-repo:kotlin:linux`** → `kotlin`, `linux`, `x64`. **`…:windows`** → `kotlin`, `windows`, `x64`. **`…:macos`** → `kotlin`, `macos`, `arm64`. **`…:macos-x64`** → `kotlin`, `macos`, `x64`. |
| **`GITCODE_SSH_PRIVATE_KEY`** | CI/CD variable (masked). |
| **Work dirs** | Ephemeral under **`$CI_PROJECT_DIR/.ci-tmp/`**. |

### `~/runner` vs `~/gitlab-runner`

**GitLab** checkouts: **`~/gitlab-runner/kotlin`** / **`llvm`** / **`chore`** only. **`~/runner`** holds **artifacts**, **caches**, and optional non-GitLab layout — do not use it as GitLab **`builds_dir`**.

### CI variable contract (shell scripts)

Scripts under **`scripts/`** and **`upload.sh` / `download.sh`** expect:

| Variable | Meaning |
|----------|---------|
| **`CI_PROJECT_DIR`** | Repo root (GitLab sets this). Local: `export CI_PROJECT_DIR="$(git rev-parse --show-toplevel)"`. |
| **`CI_PIPELINE_ID`** | Pipeline id for archive suffixes (e.g. **`platform_package.sh`**). |
| **`KNACTION_DOTENV_FILE`** | Optional **`key=value`** file (**`artifacts:reports:dotenv`** or equivalent). |
| **`KNACTION_STEP_SUMMARY`** | Optional path for human-readable notes. |
| **`KNACTION_PIPELINE_ID`** | Optional override if **`CI_PIPELINE_ID`** is unset. |

### Runner tags (summary)

Exactly **three** tags: **`kotlin`**, **`llvm`**, or **`chore`** (one role only), plus OS and arch. Never multiple roles on one registration. No **`docker`**, **`shell`**, **`host-mini`**, **`host-studio`** tags.

### Incremental builds (GitLab Runner)

| Mechanism | Effect |
|-----------|--------|
| **`GIT_STRATEGY`** | **`fetch`**: reuse checkout, update refs. **`clone`**: clean each job. **`none`**: you manage **`git`**. |
| **`GIT_CLEAN_FLAGS`** | Controls pre-job **`git clean`**. |
| **Shell + stable `builds_dir`** | Same project path often reused — incremental if not wiped. |
| **Docker** | Ephemeral unless volumes mounted; persist **ccache** / large trees on the host. |
| **`cache:` in `.gitlab-ci.yml`** | Keyed caches for Gradle/Maven, etc. |

**Kotlin** incremental layout should still use **`~/gitlab-runner/cache`** (or clean trees under **`CI_PROJECT_DIR`**) as scripts expect.

### Multiple pipelines in one GitLab project

Use **`include:`** (e.g. **`.gitlab/ci/kotlin.yml`**, **`.gitlab/ci/llvm.yml`**), **`workflow:rules:``, per-job **`rules:`**, and optional child pipelines.

### Build efficiency troubleshooting

When build times are unexpectedly long or inconsistent across platforms, check these areas:

#### ccache configuration

LLVM builds use **ccache** for compiler output caching. Key points:

| Platform | CCACHE_DIR | Cache Size | Notes |
|----------|------------|------------|-------|
| **Linux (Docker)** | `/root/gitlab-runner/cache/llvm-ccache` | ~4-5GB | Hardcoded path; Docker HOME=/home/user but volumes mount to /root/... |
| **macOS (studio)** | `$HOME/gitlab-runner/cache/llvm-ccache` | ~1GB | Normal expansion |
| **macOS (mini)** | `$HOME/gitlab-runner/cache/llvm-ccache` | ~1GB | Normal expansion |

**Docker ccache gotcha:** Container HOME differs from volume mount paths. If CCACHE_DIR uses `$HOME`, ccache falls back to `~/.ccache` (ephemeral, lost between builds). Always verify with `ccache -s` inside the container.

**ccache internal errors:** `compile failed` and `preprocessor error` in ccache stats are normal for LLVM builds (config probes, try-compiles). They don't affect build success.

#### Checking ccache effectiveness

During or after LLVM builds, check hit rate:

```bash
# Linux: inside Docker container
docker exec <container> ccache -s

# macOS: on runner host
ssh <host> 'ccache -s'
```

Target: **>50% hit rate** after first build on unchanged source. Low hit rate (<20%) indicates:
- CCACHE_DIR not persisted (Docker volume misconfiguration)
- Source changed significantly (expected)
- ccache size limit too small

#### Diagnosing slow builds

1. **Check job duration** via GitLab API:
   ```bash
   glab api "projects/1/pipelines/<id>/jobs" | jq '.[] | select(.name | contains("llvm")) | {name, status, duration}'
   ```

2. **Compare across platforms** — Linux Docker vs macOS shell. Large disparities often indicate cache issues.

3. **Verify volume mounts** on Linux runner:
   ```bash
   ssh linux 'cat ~/gitlab-runner/config/config.toml | grep -A5 "runners.docker"'
   # Expected: volumes includes "/home/user/gitlab-runner/cache:/root/gitlab-runner/cache"
   ```

4. **Check ccache directory size**:
   ```bash
   ssh linux 'du -sh ~/gitlab-runner/cache/llvm-ccache/'
   # Target: 3-5GB after several builds
   ```

#### Efficiency optimization checklist

- [ ] ccache hit rate >50% on repeat builds
- [ ] CCACHE_DIR persisted across jobs (Docker volumes, host directories)
- [ ] ccache max_size >= 5G (configured in llvm-build.sh)
- [ ] No "dubious ownership" git errors slowing repo sync

When efficiency issues are found, update this section with the root cause and fix.

---

## Related docs

- [README.md](README.md) — overview and links.
- [`.github/actions/prepare-repo/README.md`](.github/actions/prepare-repo/README.md) — clone modes and outputs.
- [`.gitlab-ci.yml`](.gitlab-ci.yml) — current GitLab CI (**prepare-repo** tests).
