#!/usr/bin/env bash

PATH="$HOME/bin:$PATH"

HEAD_SHA="abc123def456abc123def456abc123def456abc1"

# setup_mocks sets up test mocks for `git` and `gh`: `git` returns a fixed repository URL or branch name for specific queries, and `gh` exits with status 1 by default.
setup_mocks() {
  git() {
    case "$*" in
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "branch --show-current") echo "feature-branch" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) exit 1 ;;
    esac
  }
  gh() {
    exit 1
  }
}

# setup_mocks_logs sets up git/gh mocks where `gh` returns `HEAD_SHA` for `pulls/42`, the first argument as the `check-runs` JSON, and the second argument as the logs content (args: 1 = check-runs JSON, 2 = log content).
setup_mocks_logs() {
  _MOCK_CHECK_RUNS="$1"
  _MOCK_LOG_CONTENT="$2"
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42"*) echo "$HEAD_SHA" ;;
      *"check-runs"*) echo "$_MOCK_CHECK_RUNS" ;;
      *"logs"*) printf '%s' "$_MOCK_LOG_CONTENT" ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_logs_multi sets up base mocks, exports _MOCK_LOG_<job_id> variables for each provided job-id/log-content pair, and defines a gh() mock that returns the PR head SHA for pulls/42, the supplied check-runs JSON for check-runs requests, or the corresponding per-job log content for logs requests.
setup_mocks_logs_multi() {
  _MOCK_CHECK_RUNS="$1"
  shift
  setup_mocks
  local idx=0
  while [ $# -gt 0 ]; do
    local job_id="$1"
    local log_content="$2"
    shift 2
    export "_MOCK_LOG_${job_id}=$log_content"
    idx=$((idx + 1))
  done
  gh() {
    case "$*" in
      *"pulls/42"*) echo "$HEAD_SHA" ;;
      *"check-runs"*) echo "$_MOCK_CHECK_RUNS" ;;
      *"logs"*)
        local jid
        jid=$(echo "$*" | sed -E 's/.*jobs\/([0-9]+)\/logs.*/\1/')
        local var="_MOCK_LOG_${jid}"
        printf '%s' "${!var}"
        ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_logs_auto configures git and gh mock functions to simulate auto-detection of the pull request for the current branch and to serve provided check-run JSON and log content.
# 
# _MOCK_CHECK_RUNS is the JSON string that will be returned for check-run queries; _MOCK_LOG_CONTENT is the text that will be returned for log requests.
setup_mocks_logs_auto() {
  _MOCK_CHECK_RUNS="$1"
  _MOCK_LOG_CONTENT="$2"
  setup_mocks
  gh() {
    case "$*" in
      *"pulls?head=acme:feature-branch"*) echo '42' ;;
      *"pulls/42"*) echo "$HEAD_SHA" ;;
      *"check-runs"*) echo "$_MOCK_CHECK_RUNS" ;;
      *"logs"*) printf '%s' "$_MOCK_LOG_CONTENT" ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_logs_no_pr sets up base mocks and overrides gh to return an empty response for the PR lookup query (simulating no matching pull request).
setup_mocks_logs_no_pr() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls?head=acme:feature-branch"*) echo "" ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_logs_sha_fails sets up mocked git/gh behavior where PR auto-detection returns `42` but the subsequent pull request SHA lookup fails.
setup_mocks_logs_sha_fails() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls?head=acme:feature-branch"*) echo '42' ;;
      *"pulls/42"*) exit 1 ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_logs_no_log sets up git/gh mocks where `gh` returns `HEAD_SHA` for pulls/42, returns the provided check-runs JSON for check-runs, and exits with status 1 when logs are requested.
setup_mocks_logs_no_log() {
  _MOCK_CHECK_RUNS="$1"
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42"*) echo "$HEAD_SHA" ;;
      *"check-runs"*) echo "$_MOCK_CHECK_RUNS" ;;
      *"logs"*) exit 1 ;;
      *) exit 1 ;;
    esac
  }
}

# run_script exports the mocked `git`/`gh` functions and mock variables, then invokes the target script with the provided arguments.
run_script() {
  export -f git gh
  export _MOCK_CHECK_RUNS _MOCK_LOG_CONTENT HEAD_SHA
  bash "$script" "$@"
}

test_names+=(
  test_logs_failed_check_shows_log
  test_logs_all_passing_no_output
  test_logs_multiple_failures
  test_logs_explicit_pr
  test_logs_auto_detect
  test_logs_truncation_at_500_lines
  test_logs_truncation_notice_format
  test_logs_under_500_no_truncation
  test_logs_no_pr_found_exits_nonzero
  test_logs_sha_lookup_failure
  test_logs_missing_pr_value_exits_nonzero
  test_logs_missing_pr_value_stderr_message
  test_logs_empty_pr_value_exits_nonzero
  test_logs_unknown_option_exits_nonzero
  test_logs_help_exits_zero
  test_logs_log_fetch_fails_shows_placeholder
)

# test_logs_failed_check_shows_log verifies that a failed check's log block, including the check name and its log content, appears in the command output.
test_logs_failed_check_shows_log() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content="Running tests...\nTest failed: expected 200 got 500"
  setup_mocks_logs "$check_runs" "$log_content"
  local output
  output=$(run_script logs --pr 42 2>&1)
  if echo "$output" | grep -qF -- "--- log" \
    && echo "$output" | grep -qF "name: CI" \
    && echo "$output" | grep -qF "Running tests..." \
    && echo "$output" | grep -qF "Test failed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: failed check should show log block with name and content (output: $output)"
  fi
}

# test_logs_all_passing_no_output verifies that when all check runs conclude with "success", running the `logs` command produces no output.
test_logs_all_passing_no_output() {
  local check_runs='{"total_count":2,"check_runs":[{"id":111,"name":"Build","status":"completed","conclusion":"success"},{"id":222,"name":"Test","status":"completed","conclusion":"success"}]}'
  setup_mocks_logs "$check_runs" "should not appear"
  local output
  output=$(run_script logs --pr 42 2>&1)
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: all passing checks should produce no output (got: $output)"
  fi
}

# test_logs_multiple_failures verifies that `logs --pr` outputs two log blocks (one per failed check) and includes each check's `name`.
test_logs_multiple_failures() {
  local check_runs='{"total_count":2,"check_runs":[{"id":222,"name":"Test","status":"completed","conclusion":"failure"},{"id":111,"name":"Build","status":"completed","conclusion":"failure"}]}'
  setup_mocks_logs_multi "$check_runs" 111 "build error at line 5" 222 "test assertion failed"
  local output
  output=$(run_script logs --pr 42 2>&1)
  local log_count
  log_count=$(echo "$output" | grep -c -- "--- log")
  if [ "$log_count" -eq 2 ] \
    && echo "$output" | grep -qF "name: Build" \
    && echo "$output" | grep -qF "name: Test"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected 2 log blocks for Build and Test (output: $output)"
  fi
}

# test_logs_explicit_pr verifies that when an explicit PR number is provided, failing check run logs (including the check name) are printed.
test_logs_explicit_pr() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content="error in CI"
  setup_mocks_logs "$check_runs" "$log_content"
  local output
  output=$(run_script logs --pr 42 2>&1)
  if echo "$output" | grep -qF "name: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --pr 42 should return failed check logs (output: $output)"
  fi
}

# test_logs_auto_detect verifies that running `logs` without `--pr` auto-detects the PR and prints the failing check's logs.
test_logs_auto_detect() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content="error in CI"
  setup_mocks_logs_auto "$check_runs" "$log_content"
  local output
  output=$(run_script logs 2>&1)
  if echo "$output" | grep -qF "name: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect should resolve PR and return logs (output: $output)"
  fi
}

# test_logs_truncation_at_500_lines verifies that when a job log exceeds 500 lines, the reported output contains at most 500 content lines (excluding headers) and includes a "[truncated:" notice.
test_logs_truncation_at_500_lines() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content
  log_content=$(seq 1 600 | paste -sd '\n' -)
  setup_mocks_logs "$check_runs" "$log_content"
  local output
  output=$(run_script logs --pr 42 2>&1)
  local content_lines
  content_lines=$(echo "$output" | grep -v -e "--- log" -e "name:" -e "truncated" | grep -c .)
  if [ "$content_lines" -le 500 ] && echo "$output" | grep -qF "[truncated:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected at most 500 content lines with truncation notice (content_lines: $content_lines, output: $output)"
  fi
}

# test_logs_truncation_notice_format verifies that the logs command includes the "[truncated: 100 lines omitted]" notice when a job's log exceeds 500 lines.
test_logs_truncation_notice_format() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content
  log_content=$(seq 1 600 | paste -sd '\n' -)
  setup_mocks_logs "$check_runs" "$log_content"
  local output
  output=$(run_script logs --pr 42 2>&1)
  if echo "$output" | grep -qF "[truncated: 100 lines omitted]"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected '[truncated: 100 lines omitted]' (output: $output)"
  fi
}

test_logs_under_500_no_truncation() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content
  log_content=$(seq 1 10 | paste -sd '\n' -)
  setup_mocks_logs "$check_runs" "$log_content"
  local output
  output=$(run_script logs --pr 42 2>&1)
  if ! echo "$output" | grep -q "truncated"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: under 500 lines should not show truncation notice (output: $output)"
  fi
}

# test_logs_no_pr_found_exits_nonzero adds a test that verifies `logs` exits with a non-zero status when no pull request is found.
test_logs_no_pr_found_exits_nonzero() {
  setup_mocks_logs_no_pr
  local exit_code=0
  run_script logs >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR found should exit non-zero"
  fi
}

test_logs_sha_lookup_failure() {
  setup_mocks_logs_sha_fails
  local output
  output=$(run_script logs 2>&1) || true
  if echo "$output" | grep -qF "failed to resolve head SHA"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SHA lookup failure should mention 'failed to resolve head SHA' (output: $output)"
  fi
}

test_logs_missing_pr_value_exits_nonzero() {
  assert_exit 1 "logs --pr without value exits non-zero" bash "$script" logs --pr
}

test_logs_missing_pr_value_stderr_message() {
  assert_stderr_contains "logs --pr without value gives clear message" "missing value for --pr" bash "$script" logs --pr
}

# test_logs_empty_pr_value_exits_nonzero asserts that invoking `logs --pr ""` exits with a nonzero status.
test_logs_empty_pr_value_exits_nonzero() {
  assert_exit 1 "logs --pr empty exits non-zero" bash "$script" logs --pr ""
}

test_logs_unknown_option_exits_nonzero() {
  local check_runs='{"total_count":0,"check_runs":[]}'
  setup_mocks_logs "$check_runs" ""
  local exit_code=0
  run_script logs --pr 42 --bogus >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: unknown option should exit non-zero"
  fi
}

test_logs_help_exits_zero() {
  assert_exit 0 "logs --help exits 0" bash "$script" logs --help
  assert_exit 0 "logs -h exits 0" bash "$script" logs -h
}

# test_logs_log_fetch_fails_shows_placeholder verifies that when fetching a job's logs fails the `logs` command prints a log placeholder and includes the job name.
test_logs_log_fetch_fails_shows_placeholder() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  setup_mocks_logs_no_log "$check_runs"
  local output
  output=$(run_script logs --pr 42 2>&1)
  if echo "$output" | grep -qF -- "--- log" \
    && echo "$output" | grep -qF "name: CI" \
    && echo "$output" | grep -qF "[log not available]"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: log fetch failure should show placeholder (output: $output)"
  fi
}
