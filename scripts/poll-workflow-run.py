#!/usr/bin/env python3
"""Poll a GitHub Actions workflow run until it finishes. Exit 0 on success, 1 on failure.
Usage: python poll-workflow-run.py RUN_ID [--repo OWNER/REPO] [--fail-fast] [--job-substring SUBSTR]
  --fail-fast: exit as soon as any job fails (print that job's log). Default: wait for all jobs to finish.
  --job-substring: only track jobs whose name contains SUBSTR (case-insensitive); exit when those jobs
    complete — ignores other matrix legs (e.g. --job-substring Windows for build (Windows-X64))."""

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from zoneinfo import ZoneInfo

POLL_INTERVAL = 10
LOG_TAIL = 64
TZ = ZoneInfo("Asia/Shanghai")
BAD = frozenset({"failure", "cancelled", "skipped", "timed_out"})


def gh(run_id: str, repo: str | None, *args: str) -> dict | None:
    cmd = ["gh", "run", "view", run_id, "--json", "jobs,displayTitle,workflowName,event,url"] + list(args)
    if repo:
        cmd.extend(["--repo", repo])
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(r.stdout) if r.stdout else None
    except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError):
        return None


def _job_matches(job: dict, substr: str | None) -> bool:
    if not substr:
        return True
    name = (job.get("name") or "").lower()
    return substr.lower() in name


def _print_failed_and_exit(
    data: dict, failed: list, run_id: str, repo: str | None, *, label: str = "Failed jobs"
) -> int:
    if not failed:
        return 0
    print(f"\n{label}:", file=sys.stderr)
    for j in failed:
        print(f"  {j.get('name')} ({j.get('databaseId')})", file=sys.stderr)
    fid = failed[0].get("databaseId")
    cmd = ["gh", "run", "view", run_id, "--job", str(fid), "--log-failed"]
    if repo:
        cmd.extend(["--repo", repo])
    try:
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.stdout:
            for line in r.stdout.rstrip().split("\n")[-LOG_TAIL:]:
                print(line, file=sys.stderr)
    except (FileNotFoundError, subprocess.SubprocessError):
        pass
    if data.get("url"):
        print(f"\nRun: {data['url']}", file=sys.stderr)
    return 1


def main() -> int:
    p = argparse.ArgumentParser(description="Poll workflow run until done.")
    p.add_argument("run_id", help="Workflow run ID")
    p.add_argument("--repo", metavar="OWNER/REPO", help="Repository")
    p.add_argument("--fail-fast", action="store_true", help="Exit as soon as any job fails")
    p.add_argument(
        "--job-substring",
        metavar="SUBSTR",
        help="Only poll jobs whose name contains this substring (e.g. Windows); exit when they finish",
    )
    args = p.parse_args()
    run_id, repo, fail_fast, job_substr = args.run_id, args.repo, args.fail_fast, args.job_substring

    data = gh(run_id, repo)
    if not data:
        print(f"Run {run_id} not found or no access.", file=sys.stderr)
        return 1
    jobs = data.get("jobs") or []
    if not jobs:
        print(f"Run {run_id} has no jobs.", file=sys.stderr)
        return 1

    for k in ("workflowName", "displayTitle", "event"):
        if data.get(k):
            print(f"{k}: {data[k]}")
    mode = ""
    if fail_fast:
        mode += " (fail-fast)"
    if job_substr:
        mode += f" (jobs matching {job_substr!r} only)"
    print(f"Polling run {run_id} every {POLL_INTERVAL}s{mode}\n")

    seen = {}
    while True:
        data = gh(run_id, repo)
        if not data:
            print(f"Run {run_id} not found.", file=sys.stderr)
            return 1
        jobs = data.get("jobs") or []
        now = datetime.now(TZ).strftime("%H:%M:%S")

        if job_substr:
            track = [j for j in jobs if _job_matches(j, job_substr)]
            if jobs and not track:
                names = [j.get("name") for j in jobs]
                print(f"No job name contains {job_substr!r}. Jobs: {names}", file=sys.stderr)
                return 1
        else:
            track = jobs

        for j in track:
            jid = j.get("databaseId")
            status = j.get("status") or "unknown"
            conc = j.get("conclusion") or "unknown"
            step = ""
            for s in j.get("steps") or []:
                if s.get("status") == "in_progress":
                    step = s.get("name") or ""
                    break
            name = j.get("name") or f"job_{jid}"
            key = (status, conc, step)
            if seen.get(jid) != key:
                line = f"{now}  status={status}  conclusion={conc}"
                if step:
                    line += f"  step={step}"
                line += f"  job_name={name}"
                print(line)
                seen[jid] = key

        if job_substr:
            if not track:
                time.sleep(POLL_INTERVAL)
                continue
            failed_track = [j for j in track if (j.get("conclusion") or "") in BAD]
            if failed_track:
                return _print_failed_and_exit(data, failed_track, run_id, repo)
            if all(j.get("status") == "completed" for j in track):
                return 0
            time.sleep(POLL_INTERVAL)
            continue

        # Fail-fast: exit as soon as any job has a bad conclusion
        failed = [j for j in jobs if (j.get("conclusion") or "") in BAD]
        if failed:
            return _print_failed_and_exit(data, failed, run_id, repo)

        if not all(j.get("status") == "completed" for j in jobs):
            time.sleep(POLL_INTERVAL)
            continue

        return 0


if __name__ == "__main__":
    sys.exit(main())
