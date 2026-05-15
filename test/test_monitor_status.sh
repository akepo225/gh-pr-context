#!/usr/bin/env bash

HEAD_SHA="abc123def456abc123def456abc123def456abc1"
NEW_SHA="def456abc123def456abc123def456abc123def4"
_MOCK_COUNTER_FILE=""

# _mock_counter_next increments a file-based call counter and returns the new value,
# enabling stateful mocks that return different responses on successive gh invocations.
_mock_counter_next() {
  local val
  val=$(cat "$_MOCK_COUNTER_FILE")
  val=$((val + 1))
  echo "$val" > "$_MOCK_COUNTER_FILE"
  echo "$val"
}

# setup_mocks defines mocked `git` and `sleep` shell functions used by the test harness;
# `git` responds with fixed repo URL and branch values for known invocations and exits
# nonzero for others; `sleep` is a no-op so polling tests complete instantly.
setup_mocks() {
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) exit 1 ;;
    esac
  }
  sleep() {
    :
  }
}

# setup_mocks_monitor_explicit_pr configures git/gh mocks and defines a stateful gh()
# that returns HEAD_SHA for pulls/42 lookups, the first argument as the initial
# check-runs JSON, and the second argument as the changed check-runs JSON on the
# third gh invocation (simulating a state change between poll cycles).
setup_mocks_monitor_explicit_pr() {
  _MOCK_INITIAL="$1"
  _MOCK_CHANGED="$2"
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  setup_mocks
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "$HEAD_SHA"
        ;;
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
}

# setup_mocks_monitor_sha_change configures git/gh mocks where the first SHA lookup
# returns HEAD_SHA and subsequent lookups return NEW_SHA, simulating a new commit
# pushed to the PR between poll cycles.
setup_mocks_monitor_sha_change() {
  _MOCK_INITIAL="${1:-}"
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  setup_mocks
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        if [ "$call_num" -le 1 ]; then
          echo "$HEAD_SHA"
        else
          echo "$NEW_SHA"
        fi
        ;;
      *"check-runs"*"--paginate"*)
        echo "$_MOCK_INITIAL"
        ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_monitor_auto_detect configures git/gh mocks and defines gh to return
# '42' for a pull lookup by head (auto-detect PR), return the HEAD SHA for pulls/42,
# and return the first argument as initial check-runs and the second as changed
# check-runs after three gh calls (accounting for the extra PR auto-detect call).
setup_mocks_monitor_auto_detect() {
  _MOCK_INITIAL="$1"
  _MOCK_CHANGED="$2"
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  setup_mocks
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls?head=acme:feature-branch"*"--paginate"*) echo '42' ;;
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "$HEAD_SHA"
        ;;
      *"check-runs"*"--paginate"*)
        if [ "$call_num" -le 3 ]; then
          echo "$_MOCK_INITIAL"
        else
          echo "$_MOCK_CHANGED"
        fi
        ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_monitor_no_pr sets up mocked git/gh commands where a pull request
# lookup for the current head returns an empty result (simulating no open PR).
setup_mocks_monitor_no_pr() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls?head=acme:feature-branch"*"--paginate"*) echo "" ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_monitor_api_failure configures git/gh mocks where the first two
# check-runs calls succeed (returning the first argument) but the third call
# exits with failure, simulating an API error during a poll cycle.
setup_mocks_monitor_api_failure() {
  _MOCK_INITIAL="$1"
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  setup_mocks
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "$HEAD_SHA"
        ;;
      *"check-runs"*"--paginate"*)
        if [ "$call_num" -le 2 ]; then
          echo "$_MOCK_INITIAL"
        else
          exit 1
        fi
        ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_monitor_no_change configures git/gh mocks where data never changes,
# suitable for timeout tests. Defines a sleep() wrapper that calls the real system
# sleep so SECONDS advances correctly and no leaked mock from other tests interferes.
setup_mocks_monitor_no_change() {
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
      *"check-runs"*"--paginate"*)
        echo '{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
        ;;
      *) exit 1 ;;
    esac
  }
}

# run_script_with_real_sleep runs the script with mocked git/gh but real sleep,
# so SECONDS-based timeout tests work correctly.
run_script_with_real_sleep() {
  export -f git gh sleep _mock_counter_next
  export _MOCK_INITIAL _MOCK_CHANGED HEAD_SHA NEW_SHA _MOCK_COUNTER_FILE
  timeout 15 bash "$script" "$@" </dev/null
}

# run_script runs the target script in a subshell with the mocked git, gh, sleep,
# and _mock_counter_next functions exported so the script sees the test-provided behavior.
run_script() {
  export -f git gh sleep _mock_counter_next
  export _MOCK_INITIAL _MOCK_CHANGED HEAD_SHA NEW_SHA _MOCK_COUNTER_FILE
  timeout 15 bash "$script" "$@" </dev/null
}

# cleanup_mock_counter removes the temporary file-based counter used by stateful mocks.
cleanup_mock_counter() {
  [ -n "$_MOCK_COUNTER_FILE" ] && [ -f "$_MOCK_COUNTER_FILE" ] && rm -f "$_MOCK_COUNTER_FILE"
}

test_names+=(
  test_monitor_status_single_check_change
  test_monitor_status_multiple_changes_sorted
  test_monitor_status_new_check_appearing
  test_monitor_status_check_disappearing
  test_monitor_status_sha_change
  test_monitor_status_explicit_pr
  test_monitor_status_auto_detect
  test_monitor_status_no_pr_exits_nonzero
  test_monitor_status_no_pr_stderr_message
  test_monitor_status_api_failure_exits_nonzero
  test_monitor_no_subcommand_exits_nonzero
  test_monitor_help_exits_zero
  test_monitor_status_help_exits_zero
  test_monitor_status_unknown_option_exits_nonzero
  test_monitor_status_missing_pr_value_exits_nonzero
  test_monitor_status_missing_interval_value_exits_nonzero
  test_monitor_status_invalid_interval_exits_nonzero
  test_monitor_status_zero_interval_exits_nonzero
  test_usage_lists_monitor
  test_monitor_status_timeout_exits_two
  test_monitor_status_timeout_stderr_message
  test_monitor_status_timeout_minutes
  test_monitor_status_timeout_hours
  test_monitor_status_no_timeout_preserves_behavior
  test_monitor_status_missing_timeout_value_exits_nonzero
  test_monitor_status_invalid_timeout_exits_nonzero
  test_monitor_status_help_shows_timeout
  test_monitor_status_check_missing_value_flag
  test_monitor_status_check_missing_value_last
  test_monitor_status_check_empty_value_rejected
  test_monitor_status_check_filters_to_named_check
  test_monitor_status_check_ignores_other_changes
  test_monitor_status_check_appears_after_delay
  test_monitor_status_check_timeout_missing_check
  test_monitor_status_check_case_sensitive
  test_monitor_status_help_shows_check
)

# test_monitor_status_single_check_change verifies that a single check transitioning
# from in_progress to completed produces a --- change block with correct type, check,
# from, to, and conclusion fields.
test_monitor_status_single_check_change() {
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_monitor_explicit_pr "$initial" "$changed"
  local output
  output=$(run_script monitor status --pr 42 --interval 1 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "type: status" \
    && echo "$output" | grep -qF "check: CI" \
    && echo "$output" | grep -qF "from: in_progress" \
    && echo "$output" | grep -qF "to: completed" \
    && echo "$output" | grep -qF "conclusion: success"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: single check change (output: $output)"
  fi
}

# test_monitor_status_multiple_changes_sorted verifies that when multiple checks
# change state in one poll cycle, the output lists them sorted alphabetically by
# check name (Build before Test).
test_monitor_status_multiple_changes_sorted() {
  local initial='{"total_count":2,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null},{"name":"Test","status":"queued","conclusion":null}]}'
  local changed='{"total_count":2,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"Test","status":"completed","conclusion":"failure"}]}'
  setup_mocks_monitor_explicit_pr "$initial" "$changed"
  local output
  output=$(run_script monitor status --pr 42 --interval 1 2>&1)
  cleanup_mock_counter
  local first_check
  first_check=$(echo "$output" | grep -m1 "check:" | sed 's/check: //' | tr -d '\r')
  local second_check
  second_check=$(echo "$output" | grep "check:" | sed 's/check: //' | tail -1 | tr -d '\r')
  if [ "$first_check" = "Build" ] && [ "$second_check" = "Test" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: multiple changes not sorted (first=$first_check, second=$second_check, output: $output)"
  fi
}

# test_monitor_status_new_check_appearing verifies that a check appearing between
# polls (not in initial snapshot) reports from: absent with the new status.
test_monitor_status_new_check_appearing() {
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  local changed='{"total_count":2,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"},{"name":"Lint","status":"in_progress","conclusion":null}]}'
  setup_mocks_monitor_explicit_pr "$initial" "$changed"
  local output
  output=$(run_script monitor status --pr 42 --interval 1 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF "check: Lint" \
    && echo "$output" | grep -qF "from: absent" \
    && echo "$output" | grep -qF "to: in_progress"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: new check appearing (output: $output)"
  fi
}

# test_monitor_status_check_disappearing verifies that a check present in the initial
# snapshot but missing in the next poll reports to: absent with the previous status.
test_monitor_status_check_disappearing() {
  local initial='{"total_count":2,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"},{"name":"Lint","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_monitor_explicit_pr "$initial" "$changed"
  local output
  output=$(run_script monitor status --pr 42 --interval 1 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF "check: Lint" \
    && echo "$output" | grep -qF "from: in_progress" \
    && echo "$output" | grep -qF "to: absent"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: check disappearing (output: $output)"
  fi
}

# test_monitor_status_sha_change verifies that when the PR head SHA changes between
# polls, the output reports type: new-commit with the new SHA value.
test_monitor_status_sha_change() {
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  setup_mocks_monitor_sha_change "$initial"
  local output
  output=$(run_script monitor status --pr 42 --interval 1 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "type: new-commit" \
    && echo "$output" | grep -qF "sha: $NEW_SHA"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SHA change detection (output: $output)"
  fi
}

# test_monitor_status_explicit_pr verifies that monitor status --pr 42 successfully
# detects a change and exits 0 when targeting a specific PR number.
test_monitor_status_explicit_pr() {
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_monitor_explicit_pr "$initial" "$changed"
  local exit_code=0
  run_script monitor status --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: explicit --pr 42 should succeed (exit: $exit_code)"
  fi
}

# test_monitor_status_auto_detect verifies that omitting --pr triggers auto-detection
# of the PR from the current branch and that the monitor still detects check changes.
test_monitor_status_auto_detect() {
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_monitor_auto_detect "$initial" "$changed"
  local output
  output=$(run_script monitor status --interval 1 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF "check: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect PR should work (output: $output)"
  fi
}

# test_monitor_status_no_pr_exits_nonzero verifies that running monitor status when
# no open PR exists for the current branch exits with a non-zero status.
test_monitor_status_no_pr_exits_nonzero() {
  setup_mocks_monitor_no_pr
  local exit_code=0
  run_script monitor status --interval 1 >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR should exit non-zero"
  fi
}

# test_monitor_status_no_pr_stderr_message verifies that the stderr output contains
# "no open PR found" when no open PR is detected.
test_monitor_status_no_pr_stderr_message() {
  setup_mocks_monitor_no_pr
  local output
  output=$(run_script monitor status --interval 1 2>&1) || true
  if echo "$output" | grep -qF "no open PR found"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR should mention 'no open PR found' (output: $output)"
  fi
}

# test_monitor_status_api_failure_exits_nonzero verifies that an API failure during
# a poll cycle causes the monitor to exit non-zero.
test_monitor_status_api_failure_exits_nonzero() {
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  setup_mocks_monitor_api_failure "$initial"
  local exit_code=0
  run_script monitor status --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: API failure should exit non-zero"
  fi
}

# test_monitor_no_subcommand_exits_nonzero verifies that running monitor with no
# sub-command exits 1 with a usage message.
test_monitor_no_subcommand_exits_nonzero() {
  assert_exit 1 "monitor with no subcommand exits 1" bash "$script" monitor
}

# test_monitor_help_exits_zero verifies that monitor --help and monitor -h exit 0.
test_monitor_help_exits_zero() {
  assert_exit 0 "monitor --help exits 0" bash "$script" monitor --help
  assert_exit 0 "monitor -h exits 0" bash "$script" monitor -h
}

# test_monitor_status_help_exits_zero verifies that monitor status --help and -h exit 0.
test_monitor_status_help_exits_zero() {
  assert_exit 0 "monitor status --help exits 0" bash "$script" monitor status --help
  assert_exit 0 "monitor status -h exits 0" bash "$script" monitor status -h
}

# test_monitor_status_unknown_option_exits_nonzero verifies that passing an unknown
# flag to monitor status exits 1.
test_monitor_status_unknown_option_exits_nonzero() {
  assert_exit 1 "monitor status unknown option exits 1" bash "$script" monitor status --bogus
}

# test_monitor_status_missing_pr_value_exits_nonzero verifies that --pr without a
# value exits 1 with a clear error message.
test_monitor_status_missing_pr_value_exits_nonzero() {
  assert_exit 1 "monitor status --pr without value exits 1" bash "$script" monitor status --pr
}

# test_monitor_status_missing_interval_value_exits_nonzero verifies that --interval
# without a value exits 1 with a clear error message.
test_monitor_status_missing_interval_value_exits_nonzero() {
  assert_exit 1 "monitor status --interval without value exits 1" bash "$script" monitor status --interval
}

# test_monitor_status_invalid_interval_exits_nonzero verifies that --interval with
# a non-numeric value exits 1.
test_monitor_status_invalid_interval_exits_nonzero() {
  assert_exit 1 "monitor status --interval abc exits 1" bash "$script" monitor status --interval abc
}

# test_monitor_status_zero_interval_exits_nonzero verifies that --interval 0 is
# rejected (zero is not a positive integer).
test_monitor_status_zero_interval_exits_nonzero() {
  assert_exit 1 "monitor status --interval 0 exits 1" bash "$script" monitor status --interval 0
}

# test_usage_lists_monitor verifies that the main --help output includes the monitor
# command in the command listing.
test_usage_lists_monitor() {
  local output
  output=$(bash "$script" --help 2>&1)
  if echo "$output" | grep -qF "monitor"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: usage should list monitor command"
  fi
}

# test_monitor_status_timeout_exits_two verifies that --timeout 2s with --interval 1
# exits code 2 when no state change occurs within 2 seconds.
test_monitor_status_timeout_exits_two() {
  setup_mocks_monitor_no_change
  local exit_code=0
  run_script_with_real_sleep monitor status --pr 42 --interval 1 --timeout 2s >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: timeout should exit 2 (got $exit_code)"
  fi
}

# test_monitor_status_timeout_stderr_message verifies that the timeout stderr message
# includes the duration string (e.g. "monitor timed out after 2s").
test_monitor_status_timeout_stderr_message() {
  setup_mocks_monitor_no_change
  local stderr_output
  stderr_output=$(run_script_with_real_sleep monitor status --pr 42 --interval 1 --timeout 2s 2>&1 >/dev/null) || true
  if echo "$stderr_output" | grep -qF "monitor timed out after 2s"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: timeout stderr should contain 'monitor timed out after 2s' (got: $stderr_output)"
  fi
}

# test_monitor_status_timeout_minutes verifies that --timeout 5m is accepted and
# the duration is parsed correctly by proving the monitor starts successfully.
test_monitor_status_timeout_minutes() {
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_monitor_explicit_pr "$initial" "$changed"
  local exit_code=0
  run_script monitor status --pr 42 --interval 1 --timeout 5m >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --timeout 5m should be accepted (got exit $exit_code)"
  fi
}

# test_monitor_status_timeout_hours verifies that --timeout 1h is accepted and
# the duration is parsed correctly by proving the monitor starts successfully.
test_monitor_status_timeout_hours() {
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_monitor_explicit_pr "$initial" "$changed"
  local exit_code=0
  run_script monitor status --pr 42 --interval 1 --timeout 1h >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --timeout 1h should be accepted (got exit $exit_code)"
  fi
}

# test_monitor_status_no_timeout_preserves_behavior verifies that omitting --timeout
# preserves existing behavior (monitor runs until change is detected, exits 0).
test_monitor_status_no_timeout_preserves_behavior() {
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_monitor_explicit_pr "$initial" "$changed"
  local exit_code=0
  run_script monitor status --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no timeout should detect change and exit 0 (got exit $exit_code)"
  fi
}

# test_monitor_status_missing_timeout_value_exits_nonzero verifies that --timeout
# without a value exits 1 with a clear error message.
test_monitor_status_missing_timeout_value_exits_nonzero() {
  local output exit_code=0
  output=$(bash "$script" monitor status --timeout 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "missing value for --timeout"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected exit 1 and 'missing value for --timeout' (exit=$exit_code, output: $output)"
  fi
}

# test_monitor_status_invalid_timeout_exits_nonzero verifies that --timeout with
# an invalid value exits 1 with an "invalid duration" error message.
test_monitor_status_invalid_timeout_exits_nonzero() {
  local output exit_code=0
  output=$(bash "$script" monitor status --timeout abc 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "invalid duration"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected exit 1 and 'invalid duration' (exit=$exit_code, output: $output)"
  fi
}

# test_monitor_status_help_shows_timeout verifies that monitor status --help
# includes the --timeout option in the usage output.
test_monitor_status_help_shows_timeout() {
  local output
  output=$(bash "$script" monitor status --help 2>&1)
  if echo "$output" | grep -qF -- "--timeout"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor status --help should list --timeout (output: $output)"
  fi
}

# setup_mocks_monitor_check_appearing configures git/gh mocks where the filtered
# check is absent in the first N check-runs calls and appears on a later call,
# simulating a CI check that hasn't been created yet.
setup_mocks_monitor_check_appearing() {
  _MOCK_INITIAL="$1"
  _MOCK_CHANGED="$2"
  _MOCK_APPEAR_AT="${3:-3}"
  _MOCK_CHECK_RUNS_CALLS=0
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  setup_mocks
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "$HEAD_SHA"
        ;;
      *"check-runs"*"--paginate"*)
        _MOCK_CHECK_RUNS_CALLS=$((_MOCK_CHECK_RUNS_CALLS + 1))
        if [ "$_MOCK_CHECK_RUNS_CALLS" -le "$_MOCK_APPEAR_AT" ]; then
          echo "$_MOCK_INITIAL"
        else
          echo "$_MOCK_CHANGED"
        fi
        ;;
      *) exit 1 ;;
    esac
  }
}

# test_monitor_status_check_missing_value_flag verifies that --check followed
# by another flag (no value) exits 1 with "missing value for --check".
test_monitor_status_check_missing_value_flag() {
  local output exit_code=0
  output=$(bash "$script" monitor status --check --timeout 30s 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "missing value for --check"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check followed by flag should exit 1 (exit=$exit_code, output: $output)"
  fi
}

# test_monitor_status_check_missing_value_last verifies that --check as the
# last argument (no value) exits 1 with "missing value for --check".
test_monitor_status_check_missing_value_last() {
  local output exit_code=0
  output=$(bash "$script" monitor status --check 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "missing value for --check"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check as last arg should exit 1 (exit=$exit_code, output: $output)"
  fi
}

# test_monitor_status_check_empty_value_rejected verifies that --check "" is
# rejected as a missing value.
test_monitor_status_check_empty_value_rejected() {
  local output exit_code=0
  output=$(bash "$script" monitor status --check "" 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "missing value for --check"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check \"\" should exit 1 (exit=$exit_code, output: $output)"
  fi
}

# test_monitor_status_check_filters_to_named_check verifies that --check CI only
# reports changes for the CI check, ignoring other checks that also change.
test_monitor_status_check_filters_to_named_check() {
  local initial='{"total_count":2,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null},{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":2,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"CI","status":"completed","conclusion":"failure"}]}'
  setup_mocks_monitor_explicit_pr "$initial" "$changed"
  local output
  output=$(run_script monitor status --pr 42 --interval 1 --check CI 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF "check: CI" \
    && echo "$output" | grep -qF "from: in_progress" \
    && echo "$output" | grep -qF "to: completed" \
    && echo "$output" | grep -qF "conclusion: failure" \
    && ! echo "$output" | grep -qF "check: Build"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check should filter to named check only (output: $output)"
  fi
}

# test_monitor_status_check_ignores_other_changes verifies that when non-filtered
# checks change but the filtered check does not, no change output is produced.
# Uses --timeout with real sleep to avoid infinite polling.
test_monitor_status_check_ignores_other_changes() {
  _MOCK_INITIAL='{"total_count":2,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null},{"name":"CI","status":"in_progress","conclusion":null}]}'
  _MOCK_CHANGED='{"total_count":2,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"CI","status":"in_progress","conclusion":null}]}'
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) exit 1 ;;
    esac
  }
  sleep() { command sleep "$@"; }
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "$HEAD_SHA"
        ;;
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
  local exit_code=0
  run_script_with_real_sleep monitor status --pr 42 --interval 1 --check CI --timeout 2s >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check CI should not detect Build change, should timeout exit 2 (got $exit_code)"
  fi
}

# test_monitor_status_check_appears_after_delay verifies permissive behavior:
# when the named check is absent in the initial snapshot but appears in a later
# poll, the output shows from: absent.
test_monitor_status_check_appears_after_delay() {
  local initial='{"total_count":1,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":2,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null},{"name":"CI","status":"in_progress","conclusion":null}]}'
  setup_mocks_monitor_check_appearing "$initial" "$changed" 2
  local output
  output=$(run_script monitor status --pr 42 --interval 1 --check CI 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF "check: CI" \
    && echo "$output" | grep -qF "from: absent" \
    && echo "$output" | grep -qF "to: in_progress" \
    && ! echo "$output" | grep -qF "check: Build"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check should show from: absent for delayed check (output: $output)"
  fi
}

# test_monitor_status_check_timeout_missing_check verifies that when --check
# names a check that never appears and --timeout is set, the monitor exits 2.
test_monitor_status_check_timeout_missing_check() {
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
      *"check-runs"*"--paginate"*)
        echo '{"total_count":1,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null}]}'
        ;;
      *) exit 1 ;;
    esac
  }
  local exit_code=0
  run_script_with_real_sleep monitor status --pr 42 --interval 1 --check CI --timeout 2s >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check with missing check and --timeout should exit 2 (got $exit_code)"
  fi
}

# test_monitor_status_check_case_sensitive verifies that --check CI does not
# match a check named "ci" (case-sensitive exact match). Uses --timeout since
# the filtered check never matches and the loop would run indefinitely.
test_monitor_status_check_case_sensitive() {
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) exit 1 ;;
    esac
  }
  sleep() { command sleep "$@"; }
  gh() {
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*) echo "$HEAD_SHA" ;;
      *"check-runs"*"--paginate"*)
        echo '{"total_count":1,"check_runs":[{"name":"ci","status":"in_progress","conclusion":null}]}'
        ;;
      *) exit 1 ;;
    esac
  }
  local exit_code=0
  run_script_with_real_sleep monitor status --pr 42 --interval 1 --check CI --timeout 2s >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check CI should not match ci, should timeout exit 2 (got $exit_code)"
  fi
}

# test_monitor_status_help_shows_check verifies that monitor status --help
# includes the --check option in the usage output.
test_monitor_status_help_shows_check() {
  local output
  output=$(bash "$script" monitor status --help 2>&1)
  if echo "$output" | grep -qF -- "--check"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor status --help should list --check (output: $output)"
  fi
}
