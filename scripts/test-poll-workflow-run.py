#!/usr/bin/env python3
"""Test poll-workflow-run: poll a run (or trigger test-prepare-repo then poll).
Usage: python test-poll-workflow-run.py [RUN_ID] [--repo OWNER/REPO] [--fail-fast]
  If RUN_ID is given, poll that run. Else trigger test-prepare-repo and poll the new run."""

import argparse
import json
import os
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
POLL_SCRIPT = os.path.join(SCRIPT_DIR, "poll-workflow-run.py")
WORKFLOW = "test-prepare-repo.yml"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("run_id", nargs="?", help="Workflow run ID (optional; if omitted, trigger workflow and poll)")
    p.add_argument("--repo", metavar="OWNER/REPO", help="Repository")
    p.add_argument("--fail-fast", action="store_true", help="Exit as soon as any job fails")
    args = p.parse_args()
    repo_args = ["--repo", args.repo] if args.repo else []
    if args.fail_fast:
        repo_args.append("--fail-fast")

    if args.run_id:
        run_id = args.run_id
        print(f"Polling run {run_id} until done...")
    else:
        print(f"Triggering workflow: {WORKFLOW}")
        subprocess.run(
            ["gh", "workflow", "run", WORKFLOW] + repo_args,
            capture_output=True,
        )
        time.sleep(3)
        r = subprocess.run(
            ["gh", "run", "list", "--workflow", WORKFLOW, "--limit", "1", "--json", "databaseId"] + repo_args,
            capture_output=True,
            text=True,
        )
        if r.returncode or not r.stdout:
            print("Could not get run ID after trigger.", file=sys.stderr)
            return 1
        run_id = str(json.loads(r.stdout)[0]["databaseId"])
        print(f"Run ID: {run_id}. Polling...")

    r = subprocess.run([sys.executable, POLL_SCRIPT, run_id] + repo_args)
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
