# Agent guide — kn-action

This file is for humans and coding agents working on **kn-action**: **GitLab CI** on a LAN instance, shell scripts, and shared **prepare-repo** tooling for **Kotlin Multiplatform (KMP)** and **OpenHarmony (OH)**-related builds (Kotlin compiler, LLVM toolchain, local artifact plumbing). Upstream sources are mostly on **GitCode**.

---

## What this repo is for

- **Orchestration**: Pipelines clone upstream repos (mostly **GitCode**), run long builds, and publish results; primary CI entry is **`.gitlab-ci.yml`** (expand with **`include:`** as Kotlin/LLVM jobs land).
- **Kotlin / OH**: Building **Kotlin for OpenHarmony** via `scripts/build-ohos.sh` and repo prep through [`.github/actions/prepare-repo`](.github/actions/prepare-repo/README.md) (invoked from CI scripts; path is historical).
- **LLVM / OH**: Google **repo** + a manifest on GitCode to sync an OH LLVM workspace, then OH build scripts; Linux LLVM builds typically use a **Docker** image built from [`infra/docker/Dockerfile`](infra/docker/Dockerfile).
- **Local artifacts**: Large outputs use **`~/runner/artifact`** and the LAN artifact server; **`upload-artifact-local` / `download-artifact-local`** composite actions implement the same contract for any CI that calls their shell scripts with the variables below.

---

## Host layout: `~/runner` and `~/gitlab-runner`

| Path | Role |
|------|------|
| **`~/gitlab-runner/kotlin`** | GitLab Runner **`builds_dir`** for **Kotlin**-tagged registrations (spec; all hosts — see **Self-hosted GitLab**). |
| **`~/gitlab-runner/llvm`** | GitLab Runner **`builds_dir`** for **LLVM**-tagged registrations (spec; all hosts). |
| **`~/runner/artifact`** | Local artifact drop zone (aligned with composite action scripts). |
| **`~/gitlab-runner/cache`** | Persistent caches (Konan, Maven, OH sysroot tarballs, ccache, etc.). |
| **`~/runner/kotlin`**, **`~/runner/llvm`** | Optional extra dirs for disk organization or non-GitLab automation; **GitLab job checkouts** stay under **`~/gitlab-runner/…`**, not here. |

**Four machines** are typically used (SSH **`Host`** names: **`linux`**, **`win`**, **`mini`**, **studio**):

| Host | Spot-check |
|------|------------|
| **`win`**, **`linux`**, **`mini`** | `ls ~/runner` / `ls ~/gitlab-runner` as needed |
| **studio** | This Mac; confirm paths locally |

### Kotlin vs LLVM — separate runners (required)

**Policy:** **Separate GitLab Runner registrations** (separate **`[[runners]]`** stanzas / tokens) for **Kotlin** and **LLVM**. One registration must **not** advertise both **`kotlin`** and **`llvm`** tags.

**Why:**

- **LLVM**: **`repo`** (~many Git repos), large disk, **`clean_build`**-style wipes can remove the whole job work parent — incompatible with sharing a root with Kotlin’s single-repo tree.
- **Kotlin**: Long-lived **`~/gitlab-runner/cache`** and a separate workspace; mixing roles increases contention and confusing failures.

**Hardware:** Prefer dedicated machines per role; if one host runs both, still use **two registrations** and **different `builds_dir`** values (**`~/gitlab-runner/kotlin`** vs **`~/gitlab-runner/llvm`**).

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
| **Volume** | Mount host **`~/runner/artifact`** (or equivalent) into the container at the path expected by scripts (same artifact layout as other OSes). |
| **Base tooling** | Image provides **bash**, **git**, **git-lfs**, **curl**, **Python 3**, **pip**. |

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
- **Persistent LLVM workspace** under the job checkout when not cleaning; **`~/gitlab-runner/cache`** for sysroot/ccache, not the main monorepo tree.
- **ccache** via [**`scripts/setup-llvm-ccache.sh`**](scripts/setup-llvm-ccache.sh); Docker jobs should mount or place **`CCACHE_DIR`** on persistent storage (**`CI_PROJECT_DIR/.ccache`** or **`~/gitlab-runner/cache`**).
- **Conditional `env_prepare`** when the tree lacks bootstrap markers.
- **Repo** via [**`scripts/setup-repo-tool.sh`**](scripts/setup-repo-tool.sh) (Windows wrapper for **`python`**).
- **Artifacts** and **`platform_package.sh`** naming aligned with Konan dependency layout (flattened host trees in published tarballs/zip).
- **Multi-platform**: prefer **`fail-fast: false`** so one OS does not cancel others.

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
| **Web UI** | `http://192.168.3.6:8929` |
| **Git over SSH** | `git@192.168.3.6`, port **2222** (GitLab shell in Docker; host SSH stays **22**) |
| **Deployment** | Docker **`gitlab/gitlab-ce`**, data under **`~/gitlab/`** on **`linux`** |
| **Operator notes** | **`~/gitlab/SETUP.txt`** on **`linux`** — e.g. **`docker restart gitlab`**; initial root password via **`docker exec gitlab grep '^Password:' /etc/gitlab/initial_root_password`** |

### Four-host runner matrix

SSH hosts: **`linux`**, **`win`**, **`mini`**, **studio**. **Eight** registrations: **Kotlin + LLVM on each host**. **`.gitlab-ci.yml`** **`prepare-repo`** tests use **Kotlin** runners only.

**Naming (`--description`):** **`{kotlin|llvm}-{os}-{arch}`** only (e.g. **`kotlin-linux-x64`**, **`kotlin-macos-arm64`**, **`kotlin-macos-x64`**, **`kotlin-windows-x64`**). Do not embed SSH host names or executor type in the description.

**Tags:** exactly **three**: role (**`kotlin`** / **`llvm`**), OS (**`linux`**, **`windows`**, **`macos`**), arch (**`x64`** / **`arm64`**). No **`docker`** tag — LLVM on Linux uses **`executor = "docker"`** in **`config.toml`**; jobs with **`image:`** select that runner via tags + executor.

**Runner `builds_dir` (spec, all hosts):** **`~/gitlab-runner/kotlin`** and **`~/gitlab-runner/llvm`**. On Windows: **`%USERPROFILE%\gitlab-runner\kotlin`** and **`%USERPROFILE%\gitlab-runner\llvm`**. Set in **`config.toml`** or **`gitlab-runner register --builds-dir`**.

| SSH host | Runner name | Tags | Executor | `builds_dir` |
|----------|-------------|------|----------|--------------|
| **`linux`** | `kotlin-linux-x64` | `kotlin`, `linux`, `x64` | **shell** | **`~/gitlab-runner/kotlin`** |
| **`linux`** | `llvm-linux-x64` | `llvm`, `linux`, `x64` | **docker** | **`~/gitlab-runner/llvm`** (mount **`~/runner/artifact`** etc. per LLVM Docker layout) |
| **`win`** | `kotlin-windows-x64` | `kotlin`, `windows`, `x64` | **shell** (Git Bash) | **`%USERPROFILE%\gitlab-runner\kotlin`** |
| **`win`** | `llvm-windows-x64` | `llvm`, `windows`, `x64` | **shell** (Git Bash) | **`%USERPROFILE%\gitlab-runner\llvm`** |
| **`studio`** | `kotlin-macos-arm64` | `kotlin`, `macos`, `arm64` | **shell** | **`~/gitlab-runner/kotlin`** |
| **`studio`** | `llvm-macos-arm64` | `llvm`, `macos`, `arm64` | **shell** | **`~/gitlab-runner/llvm`** |
| **`mini`** | `kotlin-macos-x64` | `kotlin`, `macos`, `x64` | **shell** | **`~/gitlab-runner/kotlin`** |
| **`mini`** | `llvm-macos-x64` | `llvm`, `macos`, `x64` | **shell** | **`~/gitlab-runner/llvm`** |

**Windows:** Runner install under **`%USERPROFILE%\gitlab-runner\`**, config **`config.toml`**, service user matches **`%USERPROFILE%`**.

**Linux:** **`~/gitlab-runner/config.toml`** (same tree as **`builds_dir`** above). System packages may use **`/etc/gitlab-runner/config.toml`** instead.

**macOS:** **`~/gitlab-runner/config.toml`**; two stanzas per host (**`studio`**: arm64 names; **`mini`**: x64 names). **`name`** in **`config.toml`** should match the GitLab runner **description** above.

**Register example:**

```bash
gitlab-runner register \
  --url "http://192.168.3.6:8929" \
  --token "glrt-…" \
  --executor shell \
  --description "kotlin-macos-arm64" \
  --tag-list "kotlin,macos,arm64" \
  --builds-dir "$HOME/gitlab-runner/kotlin"
```

**LLVM Linux (Docker):** add **`--executor docker`**, **`--docker-image alpine:latest`**, **`--tag-list "llvm,linux,x64"`**.

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

**GitLab** checkouts: **`~/gitlab-runner/kotlin`** / **`llvm`** only. **`~/runner`** holds **artifacts**, **caches**, and optional non-GitLab layout — do not use it as GitLab **`builds_dir`**.

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

Exactly **three** tags: **`kotlin`** or **`llvm`**, OS, arch. Never both roles on one registration. No **`docker`**, **`shell`**, **`host-mini`**, **`host-studio`** tags.

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

Use **`include:`** (e.g. **`.gitlab/ci/kotlin.yml`**, **`.gitlab/ci/llvm.yml`**), **`workflow:rules:`**, per-job **`rules:`**, and optional child pipelines.

---

## Related docs

- [README.md](README.md) — overview and links.
- [`.github/actions/prepare-repo/README.md`](.github/actions/prepare-repo/README.md) — clone modes and outputs.
- [`.gitlab-ci.yml`](.gitlab-ci.yml) — current GitLab CI (**prepare-repo** tests).
