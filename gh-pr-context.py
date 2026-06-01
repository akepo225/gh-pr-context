#!/usr/bin/env python3
import json
import os
import re
import shlex
import subprocess
import sys
from datetime import datetime, timezone

VERSION = "0.2.5"


def die(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def _git_cmd():
    override = os.environ.get("GH_PR_CONTEXT_GIT")
    if override:
        return shlex.split(override)
    return ["git"]


def _gh_cmd():
    override = os.environ.get("GH_PR_CONTEXT_GH")
    if override:
        return shlex.split(override)
    return ["gh"]


def run_cmd(args, timeout=None):
    result = subprocess.run(
        args, capture_output=True, text=True, timeout=timeout
    )
    return result.stdout.strip(), result.returncode


def run_git(*args):
    out, rc = run_cmd(_git_cmd() + list(args))
    if rc != 0:
        die(f"git {' '.join(args)} failed")
    return out


def run_git_ok(*args):
    return run_cmd(_git_cmd() + list(args))


def parse_paginated_json(raw):
    if not raw or not raw.strip():
        return []
    decoder = json.JSONDecoder()
    pos = 0
    items = []
    raw = raw.strip()
    while pos < len(raw):
        while pos < len(raw) and raw[pos] in " \t\n\r":
            pos += 1
        if pos >= len(raw):
            break
        try:
            obj, end = decoder.raw_decode(raw, pos)
            if isinstance(obj, list):
                items.extend(obj)
            else:
                items.append(obj)
            pos = end
        except json.JSONDecodeError:
            print("warning: incomplete paginated JSON response", file=sys.stderr)
            break
    return items


def gh_api_paginated(endpoint):
    args = _gh_cmd() + ["api", "--paginate", endpoint]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        return None, False
    return result.stdout, True


def gh_api_jq(endpoint, jq_filter):
    args = _gh_cmd() + ["api", endpoint, "--jq", jq_filter]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        return None, False
    return result.stdout.strip().replace("\r", ""), True


def check_deps():
    from shutil import which
    git_bin = _git_cmd()[0]
    gh_bin = _gh_cmd()[0]
    for label, binary in (("git", git_bin), ("gh", gh_bin)):
        if not which(binary):
            die(f"{label} is required but not found on PATH")
    out, rc = run_cmd(_git_cmd() + ["rev-parse", "--git-dir"])
    if rc != 0:
        die("not a git repository")


def resolve_owner_repo():
    remote_url = run_git("remote", "get-url", "origin")
    m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", remote_url)
    if not m:
        die("failed to parse owner/repo from remote url")
    return m.group(1)


def resolve_pr_number():
    branch = run_git("rev-parse", "--abbrev-ref", "HEAD")
    owner_repo = resolve_owner_repo()
    owner, repo = owner_repo.split("/", 1)
    endpoint = f"repos/{owner}/{repo}/pulls?head={owner}:{branch}"
    val, ok = gh_api_jq(endpoint, ".[0].number")
    if not ok:
        die(f"failed to look up PR for branch '{branch}'")
    if not val or val == "null":
        die(f"no open PR found for branch '{branch}'")
    return val


def validate_since_format(value):
    if not value:
        return
    if value == "last-commit":
        return
    if re.match(r"^[0-9a-fA-F]{7,40}$", value):
        return
    if re.match(r"^\d{4}-\d{2}-\d{2}$", value):
        ts = f"{value}T00:00:00Z"
        _validate_iso(ts, value)
        return
    if re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$", value):
        ts = f"{value}Z"
        _validate_iso(ts, value)
        return
    die(f"invalid --since value: {value} (expected: last-commit, <7-40 char SHA>, YYYY-MM-DD, or YYYY-MM-DDTHH:mm:ss)")


def _validate_iso(ts, original):
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        formatted = dt.strftime("%Y-%m-%dT%H:%M:%S+00:00")
        expected = ts.replace("Z", "+00:00")
        if formatted != expected:
            raise ValueError
    except (ValueError, OverflowError):
        die(f"invalid --since value: {original} (expected: last-commit, <7-40 char SHA>, YYYY-MM-DD, or YYYY-MM-DDTHH:mm:ss)")


def resolve_since_timestamp(since_input):
    if not since_input:
        return ""
    if since_input == "last-commit":
        out, rc = run_cmd(_git_cmd() + ["log", "-1", "--format=%ct", "HEAD"])
        if rc != 0:
            die("failed to resolve last-commit timestamp")
        try:
            epoch = int(out.strip())
            dt = datetime.fromtimestamp(epoch, tz=timezone.utc)
            return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        except (ValueError, OverflowError):
            die("failed to resolve last-commit timestamp")
    if re.match(r"^[0-9a-fA-F]{7,40}$", since_input):
        expanded = ""
        exp_out, exp_rc = run_git_ok("rev-parse", since_input)
        if exp_rc == 0:
            expanded = exp_out.strip()
        if expanded:
            epoch_out, log_rc = run_cmd(_git_cmd() + ["log", "-1", "--format=%ct", expanded])
            if log_rc == 0:
                try:
                    epoch = int(epoch_out.strip())
                    dt = datetime.fromtimestamp(epoch, tz=timezone.utc)
                    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
                except (ValueError, OverflowError):
                    pass
        sha_for_api = expanded or since_input
        owner_repo = resolve_owner_repo()
        api_date, ok = gh_api_jq(
            f"repos/{owner_repo}/commits/{sha_for_api}",
            ".commit.committer.date",
        )
        if not ok or not api_date:
            die(f"unknown commit: {since_input}")
        try:
            dt = datetime.fromisoformat(api_date.replace("Z", "+00:00"))
            return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        except (ValueError, OverflowError):
            die(f"unknown commit: {since_input}")
    if re.match(r"^\d{4}-\d{2}-\d{2}$", since_input):
        ts = f"{since_input}T00:00:00Z"
        _validate_iso(ts, since_input)
        return ts
    if re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$", since_input):
        ts = f"{since_input}Z"
        _validate_iso(ts, since_input)
        return ts
    die(f"invalid --since value: {since_input} (expected: last-commit, <7-40 char SHA>, YYYY-MM-DD, or YYYY-MM-DDTHH:mm:ss)")


def resolve_pr_head_sha(pr_number):
    owner_repo = resolve_owner_repo()
    val, ok = gh_api_jq(f"repos/{owner_repo}/pulls/{pr_number}", ".head.sha")
    if not ok or not val:
        return None
    return val


def cmd_status(argv):
    pr_number = ""
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--pr":
            if i + 1 >= len(argv):
                die("missing value for --pr")
            pr_number = argv[i + 1]
            if not pr_number:
                die("--pr value must not be empty")
            i += 2
        elif arg in ("-h", "--help"):
            usage()
            sys.exit(0)
        else:
            die(f"unknown option: {arg}")

    check_deps()

    if not pr_number:
        pr_number = resolve_pr_number()

    owner_repo = resolve_owner_repo()

    sha = resolve_pr_head_sha(pr_number)
    if not sha:
        die(f"failed to resolve head SHA for PR #{pr_number}")

    checks_raw, ok = gh_api_paginated(f"repos/{owner_repo}/commits/{sha}/check-runs")
    if not ok:
        die(f"failed to fetch check runs for SHA {sha}")

    checks_data = parse_paginated_json(checks_raw)

    all_runs = []
    for page in checks_data:
        if isinstance(page, dict) and "check_runs" in page:
            all_runs.extend(page["check_runs"])

    all_runs.sort(key=lambda x: x.get("name", ""))

    lines = []
    for run in all_runs:
        parts = [
            "--- check",
            f"name: {run['name']}",
            f"status: {run['status']}",
        ]
        if run.get("status") == "completed":
            parts.append(f"conclusion: {run['conclusion']}")
        lines.append("\n".join(parts))

    output = "\n".join(lines)
    if output:
        print(output)


def cmd_logs(argv):
    pr_number = ""
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--pr":
            if i + 1 >= len(argv):
                die("missing value for --pr")
            pr_number = argv[i + 1]
            if not pr_number:
                die("--pr value must not be empty")
            i += 2
        elif arg in ("-h", "--help"):
            usage()
            sys.exit(0)
        else:
            die(f"unknown option: {arg}")

    check_deps()

    if not pr_number:
        pr_number = resolve_pr_number()

    owner_repo = resolve_owner_repo()

    sha = resolve_pr_head_sha(pr_number)
    if not sha:
        die(f"failed to resolve head SHA for PR #{pr_number}")

    checks_raw, ok = gh_api_paginated(f"repos/{owner_repo}/commits/{sha}/check-runs")
    if not ok:
        die(f"failed to fetch check runs for SHA {sha}")

    checks_data = parse_paginated_json(checks_raw)

    all_runs = []
    for page in checks_data:
        if isinstance(page, dict) and "check_runs" in page:
            all_runs.extend(page["check_runs"])

    failed = sorted(
        [r for r in all_runs if r.get("status") == "completed" and r.get("conclusion") == "failure"],
        key=lambda x: x.get("name", ""),
    )

    if not failed:
        return

    for run in failed:
        check_run_id = run["id"]
        name = run["name"]

        # Resolve real job IDs from the check-run (check-run IDs ≠ job IDs)
        job_ids = []
        try:
            jobs_args = _gh_cmd() + ["api", f"repos/{owner_repo}/check-runs/{check_run_id}/jobs"]
            jobs_result = subprocess.run(jobs_args, capture_output=True, text=True)
            if jobs_result.returncode == 0:
                jobs_data = json.loads(jobs_result.stdout)
                for job in jobs_data.get("jobs", []):
                    if "id" in job:
                        job_ids.append(job["id"])
        except Exception:
            pass

        log_content = ""
        for job_id in job_ids:
            try:
                args = _gh_cmd() + ["api", f"repos/{owner_repo}/actions/jobs/{job_id}/logs"]
                result = subprocess.run(args, capture_output=True, text=True)
                if result.returncode == 0 and result.stdout:
                    if log_content:
                        log_content += "\n" + result.stdout
                    else:
                        log_content = result.stdout
            except Exception:
                pass

        print("--- log")
        print(f"name: {name}")

        if not log_content:
            print("[log not available]")
            continue

        log_lines = log_content.splitlines()
        if len(log_lines) > 500:
            for line in log_lines[:500]:
                print(line)
            omitted = len(log_lines) - 500
            print(f"[truncated: {omitted} lines omitted]")
        else:
            print(log_content, end="" if log_content.endswith("\n") else "\n")



def cmd_comments(argv):
    pr_number = ""
    since_input = ""
    force_all = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--pr":
            if i + 1 >= len(argv):
                die("missing value for --pr")
            pr_number = argv[i + 1]
            if not pr_number:
                die("--pr value must not be empty")
            i += 2
        elif arg == "--since":
            if i + 1 >= len(argv):
                die("missing value for --since")
            validate_since_format(argv[i + 1])
            since_input = argv[i + 1]
            i += 2
        elif arg == "--all":
            force_all = True
            i += 1
        elif arg in ("-h", "--help"):
            usage()
            sys.exit(0)
        else:
            die(f"unknown option: {arg}")

    if force_all:
        since_input = ""

    check_deps()

    since_ref = resolve_since_timestamp(since_input) if since_input else ""

    if not pr_number:
        pr_number = resolve_pr_number()

    owner_repo = resolve_owner_repo()

    review_raw, ok = gh_api_paginated(f"repos/{owner_repo}/pulls/{pr_number}/comments")
    if not ok:
        die(f"failed to fetch review comments for PR #{pr_number}")

    review_data = parse_paginated_json(review_raw)

    review_items = []
    for c in review_data:
        if c.get("in_reply_to_id") is not None:
            continue
        review_items.append({
            "source": "review-comment",
            "id": c["id"],
            "author": c["user"]["login"],
            "created": c["created_at"],
            "path": c.get("path", ""),
            "line": c.get("line") or 0,
            "body": c.get("body", ""),
        })

    review_ids = [str(item["id"]) for item in review_items]

    replies_map = {}
    for cid in review_ids:
        endpoint = f"repos/{owner_repo}/pulls/comments/{cid}/replies"
        replies_raw, ok = gh_api_paginated(endpoint)
        if not ok:
            print(f"warning: failed to fetch replies for comment {cid}", file=sys.stderr)
            replies_raw = "[]"
        replies_data = parse_paginated_json(replies_raw)

        if since_ref:
            replies_data = [r for r in replies_data if r.get("created_at", "") >= since_ref]

        reply_fields = sorted(
            [
                {
                    "author": r["user"]["login"],
                    "created": r["created_at"],
                    "body": r.get("body", ""),
                }
                for r in replies_data
            ],
            key=lambda x: x["created"],
        )
        if reply_fields:
            replies_map[cid] = reply_fields

    for item in review_items:
        cid = str(item["id"])
        item["replies"] = replies_map.get(cid, [])

    issue_raw, ok = gh_api_paginated(f"repos/{owner_repo}/issues/{pr_number}/comments")
    if not ok:
        die(f"failed to fetch issue comments for PR #{pr_number}")

    issue_data = parse_paginated_json(issue_raw)

    issue_items = []
    for c in issue_data:
        issue_items.append({
            "source": "issue-comment",
            "author": c["user"]["login"],
            "created": c["created_at"],
            "body": c.get("body", ""),
        })

    merged = review_items + issue_items
    merged.sort(key=lambda x: x["created"])

    if since_ref:
        merged = [c for c in merged if c["created"] >= since_ref or c.get("replies")]

    lines = []
    for item in merged:
        if item["source"] == "review-comment":
            parts = [
                "--- review-comment",
                f"author: {item['author']}",
                f"created: {item['created']}",
                f"path: {item['path']}",
                f"line: {item['line']}",
                f"body: {item['body']}",
            ]
            for reply in item["replies"]:
                parts.append(">>> reply")
                parts.append(f"author: {reply['author']}")
                parts.append(f"created: {reply['created']}")
                parts.append(f"body: {reply['body']}")
            lines.append("\n".join(parts))
        else:
            parts = [
                "--- issue-comment",
                f"author: {item['author']}",
                f"created: {item['created']}",
                f"body: {item['body']}",
            ]
            lines.append("\n".join(parts))

    output = "\n".join(lines)
    if output:
        print(output)


def usage():
    print("usage: gh-pr-context <command> [options]")
    print("")
    print("commands:")
    print("  comments   Fetch PR comments")
    print("  status     Fetch CI check status")
    print("  logs       Fetch logs for failed CI checks")
    print("")
    print("options:")
    print("  --pr <number>   PR number (auto-detected from branch if omitted)")
    print("  --since <ref>   Filter comments by time")
    print("  --all           Return all comments (default)")
    print("  --version       Show version")
    print("  -h, --help      Show this message")


def main(argv):
    if sys.version_info < (3, 11):
        return die("python 3.11+ is required")

    if not argv:
        usage()
        return 1

    command = argv[0]
    rest = argv[1:]

    if command == "--version":
        print(f"gh-pr-context {VERSION}")
        return 0
    if command in ("-h", "--help"):
        usage()
        return 0
    if command == "comments":
        cmd_comments(rest)
        return 0
    if command == "status":
        cmd_status(rest)
        return 0
    if command == "logs":
        cmd_logs(rest)
        return 0

    return die(f"unknown command: {command}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
