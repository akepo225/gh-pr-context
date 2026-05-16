#!/usr/bin/env bash

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

test_names+=(
  test_signal_status_with_change_exits_130
  test_signal_status_no_change_exits_130_silent
  test_signal_status_sigterm_with_change_exits_130
  test_signal_comments_with_change_exits_130
  test_signal_comments_no_change_exits_130_silent
  test_signal_comments_sigterm_no_change_exits_130
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
      *) exit 1 ;;
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
      *) exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  local outfile="$_SIGNAL_TMPDIR/out"

  _export_signal_mocks
  bash "$script" monitor status --pr 42 --interval 5 > "$outfile" 2>&1 &
  local pid=$!

  command sleep 3
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null
  local exit_code=$?

  local output
  output=$(cat "$outfile")
  cleanup_signal_tmpdir
  cleanup_mock_counter

  if [ "$exit_code" -eq 130 ] \
    && echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "check: CI" \
    && echo "$output" | grep -qF "to: completed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: signal status with change (exit=$exit_code, output: $output)"
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
      *) exit 1 ;;
    esac
  }
  gh() {
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*) echo "$HEAD_SHA" ;;
      *"check-runs"*"--paginate"*) echo "$_MOCK_INITIAL" ;;
      *) exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  local outfile="$_SIGNAL_TMPDIR/out"

  _export_signal_mocks
  bash "$script" monitor status --pr 42 --interval 5 > "$outfile" 2>&1 &
  local pid=$!

  command sleep 3
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null
  local exit_code=$?

  local output
  output=$(cat "$outfile")
  cleanup_signal_tmpdir

  if [ "$exit_code" -eq 130 ] && [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: signal status no change (exit=$exit_code, output: $output)"
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
      *) exit 1 ;;
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
      *) exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  local outfile="$_SIGNAL_TMPDIR/out"

  _export_signal_mocks
  bash "$script" monitor status --pr 42 --interval 5 > "$outfile" 2>&1 &
  local pid=$!

  command sleep 3
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null
  local exit_code=$?

  local output
  output=$(cat "$outfile")
  cleanup_signal_tmpdir
  cleanup_mock_counter

  if [ "$exit_code" -eq 130 ] \
    && echo "$output" | grep -qF "check: Build" \
    && echo "$output" | grep -qF "check: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SIGTERM status with change (exit=$exit_code, output: $output)"
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
      *) exit 1 ;;
    esac
  }
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/comments/"*"/replies"*)
        echo "ERROR: replies endpoint should not be called" >&2
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
      *) exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  local outfile="$_SIGNAL_TMPDIR/out"

  _export_signal_mocks
  bash "$script" monitor comments --pr 42 --interval 5 > "$outfile" 2>&1 &
  local pid=$!

  command sleep 3
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null
  local exit_code=$?

  local output
  output=$(cat "$outfile")
  cleanup_signal_tmpdir
  cleanup_mock_counter

  if [ "$exit_code" -eq 130 ] \
    && echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "type: new-comment" \
    && echo "$output" | grep -qF "count: 1"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: signal comments with change (exit=$exit_code, output: $output)"
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
      *) exit 1 ;;
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
      *) exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  local outfile="$_SIGNAL_TMPDIR/out"

  _export_signal_mocks
  bash "$script" monitor comments --pr 42 --interval 5 > "$outfile" 2>&1 &
  local pid=$!

  command sleep 3
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null
  local exit_code=$?

  local output
  output=$(cat "$outfile")
  cleanup_signal_tmpdir

  if [ "$exit_code" -eq 130 ] && [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: signal comments no change (exit=$exit_code, output: $output)"
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
      *) exit 1 ;;
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
      *) exit 1 ;;
    esac
  }

  _SIGNAL_TMPDIR=$(mktemp -d)
  local outfile="$_SIGNAL_TMPDIR/out"

  _export_signal_mocks
  bash "$script" monitor comments --pr 42 --interval 5 > "$outfile" 2>&1 &
  local pid=$!

  command sleep 3
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null
  local exit_code=$?

  local output
  output=$(cat "$outfile")
  cleanup_signal_tmpdir

  if [ "$exit_code" -eq 130 ] && [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SIGTERM comments no change (exit=$exit_code, output: $output)"
  fi
}
