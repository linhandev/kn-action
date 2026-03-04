# Agent Guide

Project-scoped guidance for the AI agent working in kn-action.

## GitHub Actions

### Prefer actions over bash

**Try to use an action if possible instead of bash.**

- Prefer official or well-maintained actions (e.g. [actions/checkout](https://github.com/marketplace/actions/checkout), `actions/setup-java`) over inline `run:` scripts when an action exists and fits the use case.
- Use workflow steps or actions to install and configure dependencies instead of host tools (`brew`, `apt`, etc.).

### Environment setup principle

**Use GitHub Actions to set up the environment; avoid relying on host tools when possible.**

- Use workflow steps or actions to install and configure dependencies.
- Example: use `actions/setup-java` to install Java instead of `brew install --cask`.
- Prefer standard Actions (e.g. `actions/setup-java`, `actions/checkout`) over host-specific commands (`brew`, `apt`, `/usr/libexec/java_home`).

### Test workflow edits

**Try to test your edits.** This repo is primarily GitHub Action workflows.

- After changing workflow or related code: **commit**, **push**, then **wait for the workflow run to finish** and **check the result** (e.g. via GitHub Actions MCP: `actions_list` / `actions_get` / `get_job_logs`).
- Fix and iterate if the run fails.

**Per-step time estimates:** For each workflow, document estimated duration per step for **first run** (cold cache) and **incremental run** (warm cache / same runner) so you can decide how long to sleep before polling for the result. Sleep up to **20 minutes** when waiting; if the workflow usually takes longer, poll at 20 min and interpret in_progress as “still running.”

#### build-kotlin-ohos.yml (Build Kotlin OpenHarmony)

| Step | First run | Incremental |
|------|-----------|-------------|
| Checkout kn-action | ~10 s | ~5 s |
| Set up Java 8 (Zulu) | ~1–2 min | ~10–30 s (cache) |
| Set up Java 21 (Temurin) | ~1–2 min | ~10–30 s (cache) |
| Clone Kotlin repo | ~1–3 min | ~1–3 min (fresh clone each run) |
| Build Kotlin (OpenHarmony) | ~20–45 min | ~20–45 min (full build each run) |
| **Total (approx)** | **~25–55 min** | **~25–50 min** |

Use a 20 min sleep before first poll; re-check run status and job logs if still in progress or failed.
