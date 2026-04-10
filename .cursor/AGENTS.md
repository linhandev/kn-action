# Agent Guide

Project-scoped guidance for the AI agent working in kn-action.

**Keep it simple.** Don’t overdesign. Keep everything clean and readable.

## Commit messages

**Use this format:** `type(scope): what's done`, keep description short and concise

- **Type:** `feat`, `fix`, `chore`, etc.
- **Scope:** workflow or action name (e.g. `build-kotlin`, `prepare-repo`).
- **Example:** `fix(prepare-repo): use GITHUB_ACTION_PATH for script`

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
- **How to wait for a run to finish:** Use the poll script so the agent doesn’t have to guess when the run is done.
  - **If you have the run ID** (e.g. from `gh workflow run …` output URL, or from `gh run list --workflow=… --limit 1 -q '.[0].databaseId'` after a push, make sure you are polling for the workflow run triggered by ur edit): run `python3 scripts/poll-workflow-run.py RUN_ID`. It polls every 10s, exits 0 on success or 1 on failure, and on failure prints the last 64 lines of each failed step’s log.
  - Requires `gh` CLI (authenticated) and Python 3.9+.
- Fix and iterate if the run fails.
