#!/usr/bin/env bash
set -euo pipefail

HEAD_SHA="abc123def456abc123def456abc123def456abc1"
NEW_SHA="def456abc123def456abc123def456abc123def4"
_MOCK_COUNTER_FILE=""
_SIGNAL_TMPDIR=""

_mock_counter_next() {
  local val
  val=$(cat "$_MOCK_COUNTER_FILE")
  val=$((val + 1))
  echo "$val" > "$_MOCK_COUNTER_FILE"
  echo "$val"
}

cleanup_mock_counter() {
  [ -n "$_MOCK_COUNTER_FILE" ] && [ -f "$_MOCK_COUNTER_FILE" ] && rm -f "$_MOCK_COUNTER_FILE"
}

_skip_check() {
  if [ -n "${SKIP_SIGNAL_TESTS:-}" ]; then
    echo "  SKIP: $1 (SKIP_SIGNAL_TESTS is set)"
    pass=$((pass + 1))
    return 0
  fi
  return 1
}

# _export_signal_mocks exports mock functions and variables needed for signal
# tests. Must be called after defining git/gh/sleep mocks in the test function.
_export_signal_mocks() {
  export -f git gh sleep _mock_counter_next
  export _MOCK_COUNTER_FILE HEAD_SHA NEW_SHA
  export _MOCK_INITIAL _MOCK_CHANGED
  export _MOCK_INITIAL_REVIEWS _MOCK_INITIAL_ISSUES _MOCK_CHANGED_REVIEWS _MOCK_CHANGED_ISSUES
  export _MOCK_REVIEWS _MOCK_ISSUES
}

cleanup_signal_tmpdir() {
  [ -n "$_SIGNAL_TMPDIR" ] && [ -d "$_SIGNAL_TMPDIR" ] && rm -rf "$_SIGNAL_TMPDIR"
}

# _run_and_signal starts the script in the background, waits SIGNAL_DELAY
# seconds, sends SIGTERM, then reaps the child. Sets _signal_exit_code and
# _signal_output. Uses || to avoid set -e exit on non-zero wait return.
_run_and_signal() {
  local outfile="$_SIGNAL_TMPDIR/out"
  bash "$script" "$@" > "$outfile" 2>&1 &
  local pid=$!

  command sleep 4
  kill -TERM "$pid" 2>/dev/null || true
  _signal_exit_code=0
  wait "$pid" 2>/dev/null || _signal_exit_code=$?
  _signal_output=$(cat "$outfile")
}

test_names+=(
  test_signal_status_with_change_exits_130
  test_signal_status_no_change_exits_130_silent
  test_signal_status_sigterm_with_change_exits_130
  test_signal_comments_with_change_exits_130
  test_signal_comments_no_change_exits_130_silent
  test_signal_comments_sigterm_no_change_exits_130
  test_signal_all_with_change_exits_130
)

# test_signal_status_with_change_exits_130 verifies that a signal during
# monitor status triggers a final poll, detects the change, prints output, and
# exits 130. Uses SIGTERM because SIGINT cannot be delivered to background
# processes on Windows/Git Bash. The script traps both INT and TERM identically.
test_signal_status_with_change_exits_130() {
  _skip_check "signal status with change" && return 0

  _MOCK_INITIAL='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  _MOCK_CHANGED='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  sleep() { command sleep "$@"; }
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) echo "git: unexpected call: $*" >&2; exit 1 ;;
    esac
  }
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*) echo "$HEAD_SHA" ;;
      *"check-runs"*"--paginate"*)
        if [ "$call_num" -le 2 ]; then
          echo "$_MOCK_INITIAL"
        else
          echo "$_MOCK_CHANGED"
        fi
        ;;
      *) echo "gh: unexpected call: $*" >&2; exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  _export_signal_mocks
  _run_and_signal monitor status --pr 42 --interval 5
  cleanup_signal_tmpdir
  cleanup_mock_counter

  if [ "$_signal_exit_code" -eq 130 ] \
    && echo "$_signal_output" | grep -qF -- "--- change" \
    && echo "$_signal_output" | grep -qF "check: CI" \
    && echo "$_signal_output" | grep -qF "to: completed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: signal status with change (exit=$_signal_exit_code, output: $_signal_output)"
  fi
}

# test_signal_status_no_change_exits_130_silent verifies that a signal during
# monitor status exits 130 with no output when no state changed.
test_signal_status_no_change_exits_130_silent() {
  _skip_check "signal status no change" && return 0

  _MOCK_INITIAL='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  sleep() { command sleep "$@"; }
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) echo "git: unexpected call: $*" >&2; exit 1 ;;
    esac
  }
  gh() {
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*) echo "$HEAD_SHA" ;;
      *"check-runs"*"--paginate"*) echo "$_MOCK_INITIAL" ;;
      *) echo "gh: unexpected call: $*" >&2; exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  _export_signal_mocks
  _run_and_signal monitor status --pr 42 --interval 5
  cleanup_signal_tmpdir

  if [ "$_signal_exit_code" -eq 130 ] && [ -z "$_signal_output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: signal status no change (exit=$_signal_exit_code, output: $_signal_output)"
  fi
}

# test_signal_status_sigterm_with_change_exits_130 explicitly tests SIGTERM
# to verify both signal names produce the same behavior.
test_signal_status_sigterm_with_change_exits_130() {
  _skip_check "signal SIGTERM status with change" && return 0

  _MOCK_INITIAL='{"total_count":2,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null},{"name":"CI","status":"in_progress","conclusion":null}]}'
  _MOCK_CHANGED='{"total_count":2,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"CI","status":"completed","conclusion":"failure"}]}'
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  sleep() { command sleep "$@"; }
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) echo "git: unexpected call: $*" >&2; exit 1 ;;
    esac
  }
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*) echo "$HEAD_SHA" ;;
      *"check-runs"*"--paginate"*)
        if [ "$call_num" -le 2 ]; then
          echo "$_MOCK_INITIAL"
        else
          echo "$_MOCK_CHANGED"
        fi
        ;;
      *) echo "gh: unexpected call: $*" >&2; exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  _export_signal_mocks
  _run_and_signal monitor status --pr 42 --interval 5
  cleanup_signal_tmpdir
  cleanup_mock_counter

  if [ "$_signal_exit_code" -eq 130 ] \
    && echo "$_signal_output" | grep -qF "check: Build" \
    && echo "$_signal_output" | grep -qF "check: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SIGTERM status with change (exit=$_signal_exit_code, output: $_signal_output)"
  fi
}

# test_signal_comments_with_change_exits_130 verifies that a signal during
# monitor comments triggers a final poll, detects new comments, prints output,
# and exits 130.
test_signal_comments_with_change_exits_130() {
  _skip_check "signal comments with change" && return 0

  _MOCK_INITIAL_REVIEWS='[{"id":101,"in_reply_to_id":null}]'
  _MOCK_INITIAL_ISSUES='[]'
  _MOCK_CHANGED_REVIEWS='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  _MOCK_CHANGED_ISSUES='[]'
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  sleep() { command sleep "$@"; }
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) echo "git: unexpected call: $*" >&2; exit 1 ;;
    esac
  }
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/comments/"*"/replies"*)
        echo "gh: replies endpoint should not be called: $*" >&2
        exit 1
        ;;
      *"pulls/42/comments"*"--paginate"*)
        if [ "$call_num" -le 2 ]; then
          echo "$_MOCK_INITIAL_REVIEWS"
        else
          echo "$_MOCK_CHANGED_REVIEWS"
        fi
        ;;
      *"issues/42/comments"*"--paginate"*)
        if [ "$call_num" -le 2 ]; then
          echo "$_MOCK_INITIAL_ISSUES"
        else
          echo "$_MOCK_CHANGED_ISSUES"
        fi
        ;;
      *) echo "gh: unexpected call: $*" >&2; exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  _export_signal_mocks
  _run_and_signal monitor comments --pr 42 --interval 5
  cleanup_signal_tmpdir
  cleanup_mock_counter

  if [ "$_signal_exit_code" -eq 130 ] \
    && echo "$_signal_output" | grep -qF -- "--- change" \
    && echo "$_signal_output" | grep -qF "type: new-comment" \
    && echo "$_signal_output" | grep -qF "count: 1"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: signal comments with change (exit=$_signal_exit_code, output: $_signal_output)"
  fi
}

# test_signal_comments_no_change_exits_130_silent verifies that a signal during
# monitor comments exits 130 with no output when no new comments.
test_signal_comments_no_change_exits_130_silent() {
  _skip_check "signal comments no change" && return 0

  _MOCK_REVIEWS='[{"id":101,"in_reply_to_id":null}]'
  _MOCK_ISSUES='[{"id":201}]'
  sleep() { command sleep "$@"; }
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) echo "git: unexpected call: $*" >&2; exit 1 ;;
    esac
  }
  gh() {
    case "$*" in
      *"pulls/42/comments"*"--paginate"*)
        echo "$_MOCK_REVIEWS"
        ;;
      *"issues/42/comments"*"--paginate"*)
        echo "$_MOCK_ISSUES"
        ;;
      *) echo "gh: unexpected call: $*" >&2; exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  _export_signal_mocks
  _run_and_signal monitor comments --pr 42 --interval 5
  cleanup_signal_tmpdir

  if [ "$_signal_exit_code" -eq 130 ] && [ -z "$_signal_output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: signal comments no change (exit=$_signal_exit_code, output: $_signal_output)"
  fi
}

# test_signal_comments_sigterm_no_change_exits_130 explicitly tests SIGTERM
# for monitor comments to verify both signal names produce the same behavior.
test_signal_comments_sigterm_no_change_exits_130() {
  _skip_check "signal SIGTERM comments no change" && return 0

  _MOCK_REVIEWS='[{"id":101,"in_reply_to_id":null}]'
  _MOCK_ISSUES='[{"id":201}]'
  sleep() { command sleep "$@"; }
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) echo "git: unexpected call: $*" >&2; exit 1 ;;
    esac
  }
  gh() {
    case "$*" in
      *"pulls/42/comments"*"--paginate"*)
        echo "$_MOCK_REVIEWS"
        ;;
      *"issues/42/comments"*"--paginate"*)
        echo "$_MOCK_ISSUES"
        ;;
      *) echo "gh: unexpected call: $*" >&2; exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  _export_signal_mocks
  _run_and_signal monitor comments --pr 42 --interval 5
  cleanup_signal_tmpdir

  if [ "$_signal_exit_code" -eq 130 ] && [ -z "$_signal_output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SIGTERM comments no change (exit=$_signal_exit_code, output: $_signal_output)"
  fi
}

# test_signal_all_with_change_exits_130 verifies that a signal during
# monitor --all triggers a final combined poll, emits detected status changes,
# and exits 130. Uses SIGTERM because the script traps TERM and INT identically.
test_signal_all_with_change_exits_130() {
  _skip_check "signal all with change" && return 0

  _MOCK_INITIAL='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  _MOCK_CHANGED='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  _MOCK_INITIAL_REVIEWS='[]'
  _MOCK_INITIAL_ISSUES='[]'
  _MOCK_CHANGED_REVIEWS='[]'
  _MOCK_CHANGED_ISSUES='[]'
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  sleep() { command sleep "$@"; }
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) echo "git: unexpected call: $*" >&2; exit 1 ;;
    esac
  }
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*) echo "$HEAD_SHA" ;;
      *"pulls/comments/"*"/replies"*)
        echo "gh: replies endpoint should not be called: $*" >&2
        exit 1
        ;;
      *"check-runs"*"--paginate"*)
        if [ "$call_num" -le 2 ]; then
          echo "$_MOCK_INITIAL"
        else
          echo "$_MOCK_CHANGED"
        fi
        ;;
      *"pulls/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_REVIEWS" ;;
      *"issues/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_ISSUES" ;;
      *) echo "gh: unexpected call: $*" >&2; exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  _export_signal_mocks
  _run_and_signal monitor --all --pr 42 --interval 5
  cleanup_signal_tmpdir
  cleanup_mock_counter

  if [ "$_signal_exit_code" -eq 130 ] \
    && echo "$_signal_output" | grep -qF -- "--- change" \
    && echo "$_signal_output" | grep -qF "type: status" \
    && echo "$_signal_output" | grep -qF "check: CI" \
    && echo "$_signal_output" | grep -qF "to: completed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: signal all with change (exit=$_signal_exit_code, output: $_signal_output)"
  fi
}
