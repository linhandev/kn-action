# Agent Guide

Project-scoped guidance for the AI agent working in kn-action.

## GitHub Actions

### Prefer actions over bash

**Try to use an action if possible instead of bash.**

- Prefer official or well-maintained actions (e.g. `actions/checkout`, `actions/setup-java`) over inline `run:` scripts when an action exists and fits the use case.

### Environment setup principle

**Use GitHub Actions to set up the environment; avoid relying on host tools when possible.**

- Use workflow steps or actions to install and configure dependencies.
- Example: use `actions/setup-java` to install Java instead of `brew install --cask`.
- Prefer standard Actions (e.g. `actions/setup-java`, `actions/checkout`) over host-specific commands (`brew`, `apt`, `/usr/libexec/java_home`).

### Test workflow edits

**Try to test your edits.** 

- This repo is primarily GitHub Action workflows.
- After changing workflow or related code: **commit**, **push**, then **wait for the workflow run to finish** and **check the result** (e.g. via GitHub Actions MCP: `actions_list` / `actions_get` / `get_job_logs`).
- Fix and iterate if the run fails.

**Per-step time estimates:** For each workflow, document estimated duration for **first run** (cold cache) and **incremental run** (warm cache / same runner) so you can decide how long to sleep before polling for the result. Sleep maximum **20 minutes** when waiting, interpret in_progress as “still running.”

#### build-kotlin.yml

