#!/usr/bin/env python3
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone

VERSION = "0.2.6"

_active_subprocess = None


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


def _timed_gh_api_jq(endpoint, jq_filter, timeout_secs=None):
    """Like gh_api_jq but with a subprocess timeout.

    Uses Popen + _active_subprocess so the monitor signal handler can
    kill the in-flight gh process.  Returns (value, status) where
    status is "ok", "timeout", or "error".
    """
    global _active_subprocess
    args = _gh_cmd() + ["api", endpoint, "--jq", jq_filter]
    proc = subprocess.Popen(
        args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    _active_subprocess = proc
    try:
        stdout, _ = proc.communicate(timeout=timeout_secs)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        return None, "timeout"
    finally:
        _active_subprocess = None
    if proc.returncode != 0:
        return None, "error"
    return stdout.strip().replace("\r", ""), "ok"


def _setup_git_env():
    """Resolve worktree gitdir when git rev-parse --git-dir fails.

    Handles three cases:
    1. Normal repo: git works, nothing to do.
    2. Worktree with Windows absolute path (C:/...): convert to /mnt/c/...
    3. Worktree with relative gitdir: resolve relative to worktree root.
    """
    _out, rc = run_cmd(_git_cmd() + ["rev-parse", "--git-dir"])
    if rc == 0:
        return  # git works, nothing to do

    # Walk up to find the worktree root where .git is a file
    work_tree = os.getcwd()
    while work_tree != os.path.dirname(work_tree):
        git_file = os.path.join(work_tree, ".git")
        if os.path.isfile(git_file):
            break
        work_tree = os.path.dirname(work_tree)
    else:
        return  # no .git file found

    git_file = os.path.join(work_tree, ".git")
    try:
        with open(git_file, "r") as f:
            content = f.read().strip()
    except OSError:
        return

    # Parse "gitdir: <path>"
    m = re.match(r"^gitdir:\s+(.+)$", content)
    if not m:
        return
    gitdir_path = m.group(1).strip()

    # Case 1: Windows absolute path (C:/...) → WSL /mnt/c/...
    win_match = re.match(r"^([A-Za-z]):(/.*)$", gitdir_path)
    if win_match:
        drive = win_match.group(1).lower()
        rest = win_match.group(2)
        resolved = f"/mnt/{drive}{rest}"
        if os.path.isdir(resolved):
            os.environ["GIT_DIR"] = resolved
            os.environ["GIT_WORK_TREE"] = work_tree
            _out, rc = run_cmd(_git_cmd() + ["rev-parse", "--git-dir"])
            if rc == 0:
                return
            os.environ.pop("GIT_DIR", None)
            os.environ.pop("GIT_WORK_TREE", None)

    # Case 2: Non-absolute path → resolve relative to worktree root
    if not os.path.isabs(gitdir_path):
        abs_path = os.path.normpath(os.path.join(work_tree, gitdir_path))
        if os.path.isdir(abs_path):
            os.environ["GIT_DIR"] = abs_path
            os.environ["GIT_WORK_TREE"] = work_tree
            _out, rc = run_cmd(_git_cmd() + ["rev-parse", "--git-dir"])
            if rc == 0:
                return
            os.environ.pop("GIT_DIR", None)
            os.environ.pop("GIT_WORK_TREE", None)


def check_deps():
    from shutil import which
    git_bin = _git_cmd()[0]
    gh_bin = _gh_cmd()[0]
    for label, binary in (("git", git_bin), ("gh", gh_bin)):
        if not which(binary):
            die(f"{label} is required but not found on PATH")
    _setup_git_env()
    out, rc = run_cmd(_git_cmd() + ["rev-parse", "--git-dir"])
    if rc != 0:
        die("not a git repository (or worktree path could not be resolved)")


def resolve_owner_repo():
    remote_url = run_git("remote", "get-url", "origin")
    m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", remote_url)
    if not m:
        die("failed to parse owner/repo from remote url")
    return m.group(1)


_resolved_owner_repo = None


def resolve_pr_number(call_timeout=None):
    global _resolved_owner_repo
    branch = run_git("rev-parse", "--abbrev-ref", "HEAD")
    owner_repo = resolve_owner_repo()
    head_owner, _ = owner_repo.split("/", 1)

    if call_timeout is not None:
        endpoint_owner_repo, det_status = _detect_fork_parent(owner_repo, call_timeout)
        if det_status == "timeout":
            return None, "timeout"
    else:
        endpoint_owner_repo = _detect_fork_parent(owner_repo)

    endpoint_owner, endpoint_repo = endpoint_owner_repo.split("/", 1)
    endpoint = f"repos/{endpoint_owner}/{endpoint_repo}/pulls?head={head_owner}:{branch}"

    if call_timeout is not None:
        val, status = _timed_gh_api_jq(endpoint, ".[0].number", call_timeout)
        if status == "timeout":
            return None, "timeout"
        if status != "ok":
            return None, "error"
    else:
        val, ok = gh_api_jq(endpoint, ".[0].number")
        if not ok:
            die(f"failed to look up PR for branch '{branch}'")
    if not val or val == "null":
        if call_timeout is not None:
            return None, "error"
        die(f"no open PR found for branch '{branch}'")
    if call_timeout is not None:
        return val, "ok"
    return val


def _detect_fork_parent(owner_repo, call_timeout=None):
    """Detect if owner_repo is a fork and return the parent repo, or the
    original if not a fork. Caches the result in _resolved_owner_repo.

    When call_timeout is provided, uses _timed_gh_api_jq and returns
    (result, status) where status is "ok" or "timeout".
    When call_timeout is None, returns a plain string (backward compat).
    """
    global _resolved_owner_repo
    if call_timeout is not None:
        is_fork_val, status = _timed_gh_api_jq(f"repos/{owner_repo}", ".fork", call_timeout)
        if status == "timeout":
            return owner_repo, "timeout"
        if status == "error":
            return owner_repo, "error"
        if is_fork_val == "true":
            parent_val, pstatus = _timed_gh_api_jq(f"repos/{owner_repo}", ".parent.full_name", call_timeout)
            if pstatus == "timeout":
                return owner_repo, "timeout"
            if pstatus == "error":
                return owner_repo, "error"
            if parent_val and parent_val != "null":
                _resolved_owner_repo = parent_val
                return parent_val, "ok"
        _resolved_owner_repo = owner_repo
        return owner_repo, "ok"
    try:
        is_fork_val, ok = gh_api_jq(f"repos/{owner_repo}", ".fork")
        if ok and is_fork_val == "true":
            parent_val, pok = gh_api_jq(f"repos/{owner_repo}", ".parent.full_name")
            if pok and parent_val and parent_val != "null":
                _resolved_owner_repo = parent_val
                return parent_val
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"warning: fork detection failed for {owner_repo}: {exc}", file=sys.stderr)
    _resolved_owner_repo = owner_repo
    return owner_repo


def get_owner_repo(call_timeout=None):
    """Return the resolved owner/repo for API endpoints.

    After resolve_pr_number sets _resolved_owner_repo (e.g. to the parent
    repo on forks), this returns that value. Otherwise detects fork and
    caches the parent repo. Falls back to origin if not a fork.

    When call_timeout is provided, returns (result, status) where status
    is "ok" or "timeout". Otherwise returns a plain string.
    """
    if _resolved_owner_repo is not None:
        if call_timeout is not None:
            return _resolved_owner_repo, "ok"
        return _resolved_owner_repo
    result = _detect_fork_parent(resolve_owner_repo(), call_timeout)
    if call_timeout is not None:
        return result
    return result


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


def resolve_pr_head_sha(pr_number, timeout_secs=None):
    owner_repo = get_owner_repo()
    val, status = _timed_gh_api_jq(
        f"repos/{owner_repo}/pulls/{pr_number}", ".head.sha", timeout_secs
    )
    if status == "timeout":
        return None, "timeout"
    if status == "error" or not val:
        return None, "error"
    return val, "ok"


def parse_duration(input_str):
    if not input_str:
        die("invalid duration: (empty)")
    m = re.match(r"^(\d+)(s|m|h)$", input_str)
    if not m:
        die(f"invalid duration: {input_str} (expected <number><s|m|h>)")
    num = int(m.group(1))
    suffix = m.group(2)
    if suffix == "s":
        return num
    if suffix == "m":
        return num * 60
    return num * 3600


def _timed_gh_api_paginated(endpoint, timeout_secs=None):
    global _active_subprocess
    args = _gh_cmd() + ["api", "--paginate", endpoint]
    proc = subprocess.Popen(
        args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    _active_subprocess = proc
    try:
        stdout, _ = proc.communicate(timeout=timeout_secs)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        return None, "timeout"
    finally:
        _active_subprocess = None
    if proc.returncode != 0:
        return None, "error"
    return stdout, "ok"


def _capture_check_snapshot(owner_repo, sha, timeout_secs=None):
    checks_raw, status = _timed_gh_api_paginated(
        f"repos/{owner_repo}/commits/{sha}/check-runs", timeout_secs
    )
    if status == "timeout":
        return None, "timeout"
    if status != "ok":
        return None, "error"
    checks_data = parse_paginated_json(checks_raw)
    all_runs = []
    for page in checks_data:
        if isinstance(page, dict) and "check_runs" in page:
            all_runs.extend(page["check_runs"])
    snapshot = sorted(
        [
            {
                "name": r.get("name", ""),
                "status": r.get("status", ""),
                "conclusion": r.get("conclusion"),
            }
            for r in all_runs
        ],
        key=lambda x: x["name"],
    )
    return snapshot, "ok"


def _capture_comment_id_snapshot(owner_repo, pr_number, timeout_secs=None):
    snap_start = time.monotonic()
    review_raw, review_status = _timed_gh_api_paginated(
        f"repos/{owner_repo}/pulls/{pr_number}/comments", timeout_secs
    )
    if review_status == "timeout":
        return None, "timeout"
    if review_status != "ok":
        return None, "error"
    remaining = None
    if timeout_secs is not None:
        remaining = max(timeout_secs - (time.monotonic() - snap_start), 0)
    issue_raw, issue_status = _timed_gh_api_paginated(
        f"repos/{owner_repo}/issues/{pr_number}/comments", remaining
    )
    if issue_status == "timeout":
        return None, "timeout"
    if issue_status != "ok":
        return None, "error"
    review_data = parse_paginated_json(review_raw)
    issue_data = parse_paginated_json(issue_raw)
    ids = set()
    for c in review_data:
        if c.get("in_reply_to_id") is None:
            ids.add(c["id"])
    for c in issue_data:
        ids.add(c["id"])
    return ids, "ok"


def _compute_status_diff(prev_snapshot, cur_snapshot):
    prev_by_name = {}
    for c in prev_snapshot:
        prev_by_name.setdefault(c["name"], c)
    cur_by_name = {}
    for c in cur_snapshot:
        cur_by_name.setdefault(c["name"], c)
    all_names = sorted(set(prev_by_name.keys()) | set(cur_by_name.keys()))
    changes = []
    for name in all_names:
        old = prev_by_name.get(name)
        new = cur_by_name.get(name)
        if old is None:
            changes.append(
                {
                    "check": name,
                    "from": "absent",
                    "to": new["status"],
                    "conclusion": new["conclusion"],
                }
            )
        elif new is None:
            changes.append(
                {
                    "check": name,
                    "from": old["status"],
                    "to": "absent",
                    "conclusion": None,
                }
            )
        elif (
            old["status"] != new["status"]
            or (old.get("conclusion") or "") != (new.get("conclusion") or "")
        ):
            changes.append(
                {
                    "check": name,
                    "from": old["status"],
                    "to": new["status"],
                    "conclusion": new["conclusion"],
                }
            )
    return changes


def _format_status_changes(changes):
    parts = []
    for c in changes:
        block = [
            "--- change",
            "type: status",
            f"check: {c['check']}",
            f"from: {c['from']}",
            f"to: {c['to']}",
        ]
        if c.get("conclusion") is not None and c["to"] != "absent":
            block.append(f"conclusion: {c['conclusion']}")
        parts.append("\n".join(block))
    return "\n".join(parts)


def _monitor_call_timeout(timeout_secs, start_mono):
    if timeout_secs is None:
        return None
    remaining = timeout_secs - (time.monotonic() - start_mono)
    if remaining <= 0:
        return "expired"
    return remaining


_INTERRUPTIBLE_SLEEP_CHUNK = 0.1


def _interruptible_sleep(total, is_interrupted):
    end = time.monotonic() + total
    while True:
        if is_interrupted():
            return
        remaining = end - time.monotonic()
        if remaining <= 0:
            return
        time.sleep(min(remaining, _INTERRUPTIBLE_SLEEP_CHUNK))


def cmd_monitor_status(argv):
    pr_number = ""
    interval = 30
    timeout_input = ""
    timeout_secs = None
    check_filter = ""
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--pr":
            if i + 1 >= len(argv):
                die("missing value for --pr")
            pr_number = argv[i + 1]
            i += 2
        elif arg == "--interval":
            if i + 1 >= len(argv):
                die("missing value for --interval")
            interval = argv[i + 1]
            i += 2
            if not re.match(r"^[1-9][0-9]*$", interval):
                die(
                    f"invalid --interval value: {interval} (expected a positive integer)"
                )
            interval = int(interval)
        elif arg == "--timeout":
            if i + 1 >= len(argv):
                die("missing value for --timeout")
            timeout_input = argv[i + 1]
            i += 2
            timeout_secs = parse_duration(timeout_input)
        elif arg == "--check":
            if i + 1 >= len(argv):
                die("missing value for --check")
            val = argv[i + 1]
            if not val:
                die("missing value for --check")
            if val.startswith("-"):
                die("missing value for --check")
            check_filter = val
            i += 2
        elif arg in ("-h", "--help"):
            usage_monitor_status()
            sys.exit(0)
        else:
            die(f"unknown option: {arg}")

    check_deps()

    if not pr_number:
        pr_number = resolve_pr_number()

    owner_repo = get_owner_repo()

    prev_sha, sha_status = resolve_pr_head_sha(pr_number)
    if sha_status != "ok":
        die(f"failed to resolve head SHA for PR #{pr_number}")

    prev_snapshot, snap_status = _capture_check_snapshot(owner_repo, prev_sha)
    if snap_status != "ok":
        die(f"failed to fetch check runs for SHA {prev_sha}")
    if check_filter:
        prev_snapshot = [c for c in prev_snapshot if c["name"] == check_filter]

    interrupted = False

    def _handle_signal(signum, frame):
        nonlocal interrupted
        interrupted = True

    original_sigint = signal.signal(signal.SIGINT, _handle_signal)
    original_sigterm = signal.signal(signal.SIGTERM, _handle_signal)

    start_mono = time.monotonic()

    try:
        while True:
            if timeout_secs is not None:
                elapsed = time.monotonic() - start_mono
                if elapsed >= timeout_secs:
                    print(
                        f"monitor timed out after {timeout_input}", file=sys.stderr
                    )
                    sys.exit(2)

            sleep_for = interval
            if timeout_secs is not None:
                remaining = timeout_secs - (time.monotonic() - start_mono)
                if remaining < sleep_for:
                    sleep_for = max(remaining, 0)
            try:
                _interruptible_sleep(sleep_for, lambda: interrupted)
            except OSError:
                pass

            if interrupted:
                pass
            elif timeout_secs is not None:
                elapsed = time.monotonic() - start_mono
                if elapsed >= timeout_secs:
                    print(
                        f"monitor timed out after {timeout_input}", file=sys.stderr
                    )
                    sys.exit(2)

            call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
            if call_timeout == "expired":
                print(f"monitor timed out after {timeout_input}", file=sys.stderr)
                sys.exit(2)

            cur_sha, sha_status = resolve_pr_head_sha(pr_number, call_timeout)
            if sha_status == "timeout":
                print(
                    "gh api call timed out; retrying next poll", file=sys.stderr
                )
                if interrupted:
                    sys.exit(130)
                continue
            if sha_status != "ok":
                die(f"failed to re-resolve head SHA for PR #{pr_number}")

            if cur_sha != prev_sha:
                print("--- change")
                print("type: new-commit")
                print(f"sha: {cur_sha}")
                if interrupted:
                    sys.exit(130)
                sys.exit(0)

            call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
            if call_timeout == "expired":
                print(f"monitor timed out after {timeout_input}", file=sys.stderr)
                sys.exit(2)

            cur_snapshot, snap_status = _capture_check_snapshot(
                owner_repo, cur_sha, call_timeout
            )
            if snap_status == "timeout":
                print(
                    "gh api call timed out; retrying next poll", file=sys.stderr
                )
                if interrupted:
                    sys.exit(130)
                continue
            if snap_status != "ok":
                die("failed to fetch check runs during poll")
            if check_filter:
                cur_snapshot = [
                    c for c in cur_snapshot if c["name"] == check_filter
                ]

            changes = _compute_status_diff(prev_snapshot, cur_snapshot)

            if changes:
                print(_format_status_changes(changes))
                if interrupted:
                    sys.exit(130)
                sys.exit(0)

            if interrupted:
                sys.exit(130)

            prev_sha = cur_sha
            prev_snapshot = cur_snapshot
    finally:
        signal.signal(signal.SIGINT, original_sigint)
        signal.signal(signal.SIGTERM, original_sigterm)


def cmd_monitor(argv):
    if not argv:
        die("missing monitor sub-command (see 'gh-pr-context monitor --help')")

    sub_command = argv[0]
    rest = argv[1:]

    if sub_command == "status":
        cmd_monitor_status(rest)
    elif sub_command == "comments":
        cmd_monitor_comments(rest)
    elif sub_command == "--all":
        cmd_monitor_all(rest)
    elif sub_command in ("-h", "--help"):
        usage_monitor()
        sys.exit(0)
    else:
        die(f"unknown monitor sub-command: {sub_command}")


def cmd_monitor_comments(argv):
    pr_number = ""
    interval = 30
    timeout_input = ""
    timeout_secs = None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--pr":
            if i + 1 >= len(argv):
                die("missing value for --pr")
            pr_number = argv[i + 1]
            i += 2
        elif arg == "--interval":
            if i + 1 >= len(argv):
                die("missing value for --interval")
            interval = argv[i + 1]
            i += 2
            if not re.match(r"^[1-9][0-9]*$", interval):
                die(
                    f"invalid --interval value: {interval} (expected a positive integer)"
                )
            interval = int(interval)
        elif arg == "--timeout":
            if i + 1 >= len(argv):
                die("missing value for --timeout")
            timeout_input = argv[i + 1]
            i += 2
            timeout_secs = parse_duration(timeout_input)
        elif arg == "--check":
            die("unknown option: --check (only valid with monitor status)")
        elif arg in ("-h", "--help"):
            usage_monitor_comments()
            sys.exit(0)
        else:
            die(f"unknown option: {arg}")

    check_deps()

    if not pr_number:
        pr_number = resolve_pr_number()

    owner_repo = get_owner_repo()

    interrupted = False

    def _handle_signal(signum, frame):
        nonlocal interrupted
        interrupted = True
        if _active_subprocess is not None:
            _active_subprocess.kill()

    original_sigint = signal.signal(signal.SIGINT, _handle_signal)
    original_sigterm = signal.signal(signal.SIGTERM, _handle_signal)

    try:
        start_mono = time.monotonic()

        call_timeout = timeout_secs
        initial_snapshot, snap_status = _capture_comment_id_snapshot(
            owner_repo, pr_number, call_timeout
        )
        if interrupted:
            sys.exit(130)
        if snap_status == "timeout":
            print(
                f"monitor timed out after {timeout_input}", file=sys.stderr
            )
            sys.exit(2)
        if snap_status != "ok":
            die(f"failed to fetch comments for PR #{pr_number}")

        while True:
            if timeout_secs is not None:
                elapsed = time.monotonic() - start_mono
                if elapsed >= timeout_secs:
                    print(
                        f"monitor timed out after {timeout_input}", file=sys.stderr
                    )
                    sys.exit(2)

            sleep_for = interval
            if timeout_secs is not None:
                remaining = timeout_secs - (time.monotonic() - start_mono)
                if remaining < sleep_for:
                    sleep_for = max(remaining, 0)
            try:
                _interruptible_sleep(sleep_for, lambda: interrupted)
            except OSError:
                pass

            if interrupted:
                pass
            elif timeout_secs is not None:
                elapsed = time.monotonic() - start_mono
                if elapsed >= timeout_secs:
                    print(
                        f"monitor timed out after {timeout_input}", file=sys.stderr
                    )
                    sys.exit(2)

            call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
            if call_timeout == "expired":
                print(f"monitor timed out after {timeout_input}", file=sys.stderr)
                sys.exit(2)

            cur_snapshot, snap_status = _capture_comment_id_snapshot(
                owner_repo, pr_number, call_timeout
            )
            if snap_status == "timeout":
                print(
                    "gh api call timed out; retrying next poll", file=sys.stderr
                )
                if interrupted:
                    sys.exit(130)
                continue
            if snap_status != "ok":
                if interrupted:
                    sys.exit(130)
                die("failed to fetch comments during poll")

            new_ids = cur_snapshot - initial_snapshot
            if new_ids:
                print("--- change")
                print("type: new-comment")
                print(f"count: {len(new_ids)}")
                if interrupted:
                    sys.exit(130)
                sys.exit(0)

            if interrupted:
                sys.exit(130)
    finally:
        signal.signal(signal.SIGINT, original_sigint)
        signal.signal(signal.SIGTERM, original_sigterm)


def cmd_monitor_all(argv):
    pr_number = ""
    interval = 30
    timeout_input = ""
    timeout_secs = None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--pr":
            if i + 1 >= len(argv):
                die("missing value for --pr")
            pr_number = argv[i + 1]
            i += 2
        elif arg == "--interval":
            if i + 1 >= len(argv):
                die("missing value for --interval")
            interval = argv[i + 1]
            i += 2
            if not re.match(r"^[1-9][0-9]*$", interval):
                die(
                    f"invalid --interval value: {interval} (expected a positive integer)"
                )
            interval = int(interval)
        elif arg == "--timeout":
            if i + 1 >= len(argv):
                die("missing value for --timeout")
            timeout_input = argv[i + 1]
            i += 2
            timeout_secs = parse_duration(timeout_input)
        elif arg == "--check":
            die("unknown option: --check (only valid with monitor status)")
        elif arg in ("-h", "--help"):
            usage_monitor_all()
            sys.exit(0)
        else:
            die(f"unknown option: {arg}")

    check_deps()

    interrupted = False

    def _handle_signal(signum, frame):
        nonlocal interrupted
        interrupted = True
        if _active_subprocess is not None:
            _active_subprocess.kill()

    original_sigint = signal.signal(signal.SIGINT, _handle_signal)
    original_sigterm = signal.signal(signal.SIGTERM, _handle_signal)

    start_mono = time.monotonic()

    if not pr_number:
        call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
        if call_timeout == "expired":
            print(f"monitor timed out after {timeout_input}", file=sys.stderr)
            sys.exit(2)
        pr_number_result = resolve_pr_number(call_timeout)
        if call_timeout is not None:
            pr_number, pr_status = pr_number_result
            if pr_status == "timeout":
                print(f"monitor timed out after {timeout_input}", file=sys.stderr)
                sys.exit(2)
            if pr_status != "ok":
                if interrupted:
                    sys.exit(130)
                die("failed to resolve PR number")
        else:
            pr_number = pr_number_result

    call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
    if call_timeout == "expired":
        print(f"monitor timed out after {timeout_input}", file=sys.stderr)
        sys.exit(2)
    if call_timeout is not None:
        owner_repo, repo_status = get_owner_repo(call_timeout)
        if repo_status == "timeout":
            print(f"monitor timed out after {timeout_input}", file=sys.stderr)
            sys.exit(2)
    else:
        owner_repo = get_owner_repo()

    try:
        call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
        if call_timeout == "expired":
            print(f"monitor timed out after {timeout_input}", file=sys.stderr)
            sys.exit(2)

        prev_sha, sha_status = resolve_pr_head_sha(pr_number, call_timeout)
        if sha_status == "timeout":
            print(f"monitor timed out after {timeout_input}", file=sys.stderr)
            sys.exit(2)
        if sha_status != "ok":
            if interrupted:
                sys.exit(130)
            die(f"failed to resolve head SHA for PR #{pr_number}")

        call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
        if call_timeout == "expired":
            print(f"monitor timed out after {timeout_input}", file=sys.stderr)
            sys.exit(2)

        prev_status_snapshot, snap_status = _capture_check_snapshot(owner_repo, prev_sha, call_timeout)
        if snap_status == "timeout":
            print(f"monitor timed out after {timeout_input}", file=sys.stderr)
            sys.exit(2)
        if snap_status != "ok":
            if interrupted:
                sys.exit(130)
            die(f"failed to fetch check runs for commit {prev_sha}")

        call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
        if call_timeout == "expired":
            print(f"monitor timed out after {timeout_input}", file=sys.stderr)
            sys.exit(2)

        initial_comment_snapshot, snap_status = _capture_comment_id_snapshot(
            owner_repo, pr_number, call_timeout
        )
        if snap_status == "timeout":
            print(f"monitor timed out after {timeout_input}", file=sys.stderr)
            sys.exit(2)
        if snap_status != "ok":
            if interrupted:
                sys.exit(130)
            die(f"failed to fetch comments for PR #{pr_number}")

        while True:
            if timeout_secs is not None:
                elapsed = time.monotonic() - start_mono
                if elapsed >= timeout_secs:
                    print(
                        f"monitor timed out after {timeout_input}", file=sys.stderr
                    )
                    sys.exit(2)

            sleep_for = interval
            if timeout_secs is not None:
                remaining = timeout_secs - (time.monotonic() - start_mono)
                if remaining < sleep_for:
                    sleep_for = max(remaining, 0)
            try:
                _interruptible_sleep(sleep_for, lambda: interrupted)
            except OSError:
                pass

            if interrupted:
                pass
            elif timeout_secs is not None:
                elapsed = time.monotonic() - start_mono
                if elapsed >= timeout_secs:
                    print(
                        f"monitor timed out after {timeout_input}", file=sys.stderr
                    )
                    sys.exit(2)

            call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
            if call_timeout == "expired":
                print(f"monitor timed out after {timeout_input}", file=sys.stderr)
                sys.exit(2)

            cur_sha, sha_status = resolve_pr_head_sha(pr_number, call_timeout)
            if sha_status == "timeout":
                print(
                    "gh api call timed out; retrying next poll", file=sys.stderr
                )
                if interrupted:
                    sys.exit(130)
                continue
            if sha_status != "ok":
                die(f"failed to re-resolve head SHA for PR #{pr_number}")

            if cur_sha != prev_sha:
                print("--- change")
                print("type: new-commit")
                print(f"sha: {cur_sha}")
                if interrupted:
                    sys.exit(130)
                sys.exit(0)

            call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
            if call_timeout == "expired":
                print(f"monitor timed out after {timeout_input}", file=sys.stderr)
                sys.exit(2)

            cur_status_snapshot, snap_status = _capture_check_snapshot(
                owner_repo, cur_sha, call_timeout
            )
            if snap_status == "timeout":
                print(
                    "gh api call timed out; retrying next poll", file=sys.stderr
                )
                if interrupted:
                    sys.exit(130)
                continue
            if snap_status != "ok":
                die("failed to fetch check runs during poll")

            call_timeout = _monitor_call_timeout(timeout_secs, start_mono)
            if call_timeout == "expired":
                print(f"monitor timed out after {timeout_input}", file=sys.stderr)
                sys.exit(2)

            cur_comment_snapshot, snap_status = _capture_comment_id_snapshot(
                owner_repo, pr_number, call_timeout
            )
            if snap_status == "timeout":
                print(
                    "gh api call timed out; retrying next poll", file=sys.stderr
                )
                if interrupted:
                    sys.exit(130)
                continue
            if snap_status != "ok":
                die("failed to fetch comments during poll")

            status_changes = _compute_status_diff(
                prev_status_snapshot, cur_status_snapshot
            )
            new_comment_ids = cur_comment_snapshot - initial_comment_snapshot

            if status_changes:
                print(_format_status_changes(status_changes))
            if new_comment_ids:
                print("--- change")
                print("type: new-comment")
                print(f"count: {len(new_comment_ids)}")
            if status_changes or new_comment_ids:
                if interrupted:
                    sys.exit(130)
                sys.exit(0)

            if interrupted:
                sys.exit(130)

            prev_sha = cur_sha
            prev_status_snapshot = cur_status_snapshot
    finally:
        signal.signal(signal.SIGINT, original_sigint)
        signal.signal(signal.SIGTERM, original_sigterm)


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

    owner_repo = get_owner_repo()

    sha, sha_status = resolve_pr_head_sha(pr_number)
    if sha_status != "ok":
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

    owner_repo = get_owner_repo()

    sha, sha_status = resolve_pr_head_sha(pr_number)
    if sha_status != "ok":
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

    owner_repo = get_owner_repo()

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

    # The review comments endpoint already includes replies (they have
    # in_reply_to_id set). Group replies client-side instead of N+1 API calls.
    replies_map = {}
    for c in review_data:
        parent_id = c.get("in_reply_to_id")
        if parent_id is None:
            continue
        if since_ref and c.get("created_at", "") < since_ref:
            continue
        parent_key = str(parent_id)
        replies_map.setdefault(parent_key, []).append({
            "author": c["user"]["login"],
            "created": c["created_at"],
            "body": c.get("body", ""),
        })

    # Sort each reply group by created_at
    for cid in replies_map:
        replies_map[cid].sort(key=lambda x: x["created"])

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
    print("  monitor    Poll for CI/comment changes")
    print("")
    print("options:")
    print("  --pr <number>   PR number (auto-detected from branch if omitted)")
    print("  --since <ref>   Filter comments by time")
    print("  --all           Return all comments (default)")
    print("  --version       Show version")
    print("  -h, --help      Show this message")


def usage_monitor():
    print("usage: gh-pr-context monitor <sub-command|--all> [options]")
    print("")
    print("sub-commands:")
    print("  status    Poll for check status changes")
    print("  comments  Poll for new comments")
    print("  --all     Poll for both status and comment changes")
    print("")
    print("options:")
    print("  -h, --help   Show this message")


def usage_monitor_status():
    print("usage: gh-pr-context monitor status [options]")
    print("")
    print("Poll for check status/conclusion changes and new commits.")
    print("Exits 0 on change, 1 on error, 2 on timeout, 130 on signal.")
    print("")
    print("options:")
    print("  --pr <number>       PR number (auto-detected from branch if omitted)")
    print("  --interval <secs>   Poll interval in seconds (default: 30)")
    print("  --timeout <dur>     Maximum time to poll (e.g. 30s, 5m, 1h)")
    print("  --check <name>      Only watch the named check (case-sensitive)")
    print("  -h, --help          Show this message")


def usage_monitor_comments():
    print("usage: gh-pr-context monitor comments [options]")
    print("")
    print("Poll for new top-level review and issue comments.")
    print("Exits 0 on change, 1 on error, 2 on timeout, 130 on signal.")
    print("")
    print("options:")
    print("  --pr <number>       PR number (auto-detected from branch if omitted)")
    print("  --interval <secs>   Poll interval in seconds (default: 30)")
    print("  --timeout <dur>     Maximum time to poll (e.g. 30s, 5m, 1h)")
    print("  -h, --help          Show this message")


def usage_monitor_all():
    print("usage: gh-pr-context monitor --all [options]")
    print("")
    print("Poll for both check status changes and new comments.")
    print("Exits 0 on change, 1 on error, 2 on timeout, 130 on signal.")
    print("")
    print("options:")
    print("  --pr <number>       PR number (auto-detected from branch if omitted)")
    print("  --interval <secs>   Poll interval in seconds (default: 30)")
    print("  --timeout <dur>     Maximum time to poll (e.g. 30s, 5m, 1h)")
    print("  -h, --help          Show this message")


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
    if command == "monitor":
        cmd_monitor(rest)
        return 0

    return die(f"unknown command: {command}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
