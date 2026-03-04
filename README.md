# kn-action

GitHub Actions for KMP/Kotlin and related projects.

## Actions

### Build Kotlin (OpenHarmony)

**Workflow:** [`.github/workflows/build-kotlin-ohos.yml`](.github/workflows/build-kotlin-ohos.yml)

- Clones [CPF-KMP-CMP/kotlin](https://gitcode.com/CPF-KMP-CMP/kotlin) from GitCode
- Runs `bash scripts/build-ohos.sh` to build Kotlin for OpenHarmony

**Runner:** Mac ARM64 self-hosted. Labels: `self-hosted`, `macOS`, `ARM64`, `kotlin`.

**When it runs:** On push/PR to `develop` or `main`, or via **Actions → Build Kotlin (OpenHarmony) → Run workflow**.

**Requirement — GitCode SSH access:** The workflow clones `git@gitcode.com:CPF-KMP-CMP/kotlin.git`. The runner environment must already have SSH configured so that `git clone` to GitCode works without prompts (e.g. a self-hosted runner with an SSH key for GitCode in the agent’s `~/.ssh`, or an image/VM that has it preconfigured). The workflow does not inject or configure SSH keys; it assumes the environment is set up for GitCode access.
