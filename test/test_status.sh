#!/usr/bin/env bash

HEAD_SHA="abc123def456abc123def456abc123def456abc1"

# setup_mocks defines mocked `git` and `gh` shell functions used by the test harness; `git` responds with fixed repo URL and branch values for known invocations and exits nonzero for others, while `gh` always exits nonzero.
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

# setup_mocks_status sets up git and gh mock functions and configures `gh` to return `HEAD_SHA` for "pulls/42" requests and the provided check-runs JSON when "check-runs" is requested (first argument is the mock check-runs payload).
setup_mocks_status() {
  _MOCK_CHECK_RUNS="$1"
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42"*) echo "$HEAD_SHA" ;;
      *"check-runs"*) echo "$_MOCK_CHECK_RUNS" ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_status_auto configures git/gh mocks and defines gh to: return '42' for a pull lookup by head (auto-detect PR), return the HEAD SHA for pulls/42, and echo the first argument as the check-runs JSON; any other gh invocation exits with status 1.
setup_mocks_status_auto() {
  _MOCK_CHECK_RUNS="$1"
  setup_mocks
  gh() {
    case "$*" in
      *"pulls?head=acme:feature-branch"*) echo '42' ;;
      *"pulls/42"*) echo "$HEAD_SHA" ;;
      *"check-runs"*) echo "$_MOCK_CHECK_RUNS" ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_status_no_pr sets up mocked git and gh commands where a pull request lookup for the current head returns an empty result (simulating no open PR), and all other gh invocations fail.
setup_mocks_status_no_pr() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls?head=acme:feature-branch"*) echo "" ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_status_paginated configures mock git/gh behavior and defines a gh() that returns the head SHA for `pulls/42` and prints the two paginated `check-runs` responses provided as its first and second arguments.
setup_mocks_status_paginated() {
  _MOCK_PAGE1="$1"
  _MOCK_PAGE2="$2"
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42"*) echo "$HEAD_SHA" ;;
      *"check-runs"*) printf '%s\n' "$_MOCK_PAGE1" "$_MOCK_PAGE2" ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_status_sha_fails sets up git and gh mocks where a PR number is found but the pull details lookup fails, simulating a HEAD SHA resolution error.
setup_mocks_status_sha_fails() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls?head=acme:feature-branch"*) echo '42' ;;
      *"pulls/42"*) exit 1 ;;
      *) exit 1 ;;
    esac
  }
}

# run_script runs the target script in a subshell with the mocked `git` and `gh` functions and mock variables exported so the script sees the test-provided behavior.
run_script() {
  export -f git gh
  export _MOCK_CHECK_RUNS _MOCK_PAGE1 _MOCK_PAGE2 HEAD_SHA
  bash "$script" "$@"
}

test_names+=(
  test_status_completed_check
  test_status_in_progress_omits_conclusion
  test_status_queued_omits_conclusion
  test_status_sorted_by_name
  test_status_explicit_pr
  test_status_auto_detect
  test_status_exits_zero
  test_status_no_pr_found_exits_nonzero
  test_status_no_pr_found_stderr_message
  test_status_empty_checks
  test_status_multiple_conclusions
  test_status_unknown_option_exits_nonzero
  test_status_missing_pr_value_exits_nonzero
  test_status_missing_pr_value_stderr_message
  test_status_help_exits_zero
  test_status_paginated_merges_all_checks
  test_status_sha_lookup_failure_stderr_message
)

# test_status_completed_check verifies that `status --pr 42` prints a completed check run with its name, status, and conclusion.
test_status_completed_check() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  if echo "$output" | grep -qF -- "--- check" \
    && echo "$output" | grep -qF "name: CI" \
    && echo "$output" | grep -qF "status: completed" \
    && echo "$output" | grep -qF "conclusion: success"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: completed check missing expected fields (output: $output)"
  fi
}

# test_status_in_progress_omits_conclusion verifies that a check run with status in_progress is printed without a `conclusion:` line and increments the `pass` or `fail` counters accordingly.
test_status_in_progress_omits_conclusion() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  if echo "$output" | grep -qF "status: in_progress" \
    && ! echo "$output" | grep -qF "conclusion:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: in_progress check should omit conclusion (output: $output)"
  fi
}

# test_status_queued_omits_conclusion checks that when a check run has status 'queued' the script's status output includes 'status: queued' and does not include any 'conclusion:' line.
test_status_queued_omits_conclusion() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"Lint","status":"queued","conclusion":null}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  if echo "$output" | grep -qF "status: queued" \
    && ! echo "$output" | grep -qF "conclusion:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: queued check should omit conclusion (output: $output)"
  fi
}

# test_status_sorted_by_name verifies that check runs are listed sorted by name so the first `name:` line is `Alpha`.
test_status_sorted_by_name() {
  local check_runs='{"total_count":2,"check_runs":[{"name":"Zebra","status":"completed","conclusion":"success"},{"name":"Alpha","status":"completed","conclusion":"success"}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  local first_name
  first_name=$(echo "$output" | grep -m1 "name:" | sed 's/name: //')
  if [ "$first_name" = "Alpha" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected Alpha first, got: $first_name (output: $output)"
  fi
}

# test_status_explicit_pr verifies that running `status --pr 42` prints the check run details for the specified PR (expects a `CI` check with `status: completed` and `conclusion: success`).
test_status_explicit_pr() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  if echo "$output" | grep -qF "name: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --pr 42 should return check status (output: $output)"
  fi
}

# test_status_auto_detect verifies that the status command auto-detects the pull request from the current branch and outputs the check run status.
test_status_auto_detect() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_status_auto "$check_runs"
  local output
  output=$(run_script status 2>&1)
  if echo "$output" | grep -qF "name: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect should resolve PR and return check status (output: $output)"
  fi
}

# test_status_exits_zero ensures the status command exits with 0 when all check runs conclude successfully.
test_status_exits_zero() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_status "$check_runs"
  assert_exit 0 "status exits 0 on success" run_script status --pr 42
}

# test_status_no_pr_found_exits_nonzero verifies that invoking the script's `status` command when no open PR exists exits with a non-zero status.
test_status_no_pr_found_exits_nonzero() {
  setup_mocks_status_no_pr
  local exit_code=0
  run_script status >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR found should exit non-zero"
  fi
}

# test_status_no_pr_found_stderr_message verifies that running `status` when no open PR is found writes "no open PR found" to stderr (and counts the test as pass/fail accordingly).
test_status_no_pr_found_stderr_message() {
  setup_mocks_status_no_pr
  local output
  output=$(run_script status 2>&1) || true
  if echo "$output" | grep -qF "no open PR found"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR found should mention 'no open PR found' (output: $output)"
  fi
}

test_status_empty_checks() {
  local check_runs='{"total_count":0,"check_runs":[]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: empty check_runs should produce no output (got: $output)"
  fi
}

# test_status_multiple_conclusions verifies the status command outputs each conclusion value when multiple completed check runs have differing conclusions.
test_status_multiple_conclusions() {
  local check_runs='{"total_count":3,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"Test","status":"completed","conclusion":"failure"},{"name":"Deploy","status":"completed","conclusion":"cancelled"}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  if echo "$output" | grep -qF "conclusion: success" \
    && echo "$output" | grep -qF "conclusion: failure" \
    && echo "$output" | grep -qF "conclusion: cancelled"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: mixed conclusions not all present (output: $output)"
  fi
}

# test_status_unknown_option_exits_nonzero verifies that running the `status` command with an unrecognized option causes the script to exit with a non-zero status.
test_status_unknown_option_exits_nonzero() {
  local check_runs='{"total_count":0,"check_runs":[]}'
  setup_mocks_status "$check_runs"
  local exit_code=0
  run_script status --pr 42 --bogus >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: unknown option should exit non-zero"
  fi
}

# test_status_missing_pr_value_exits_nonzero asserts that invoking the script's `status` command with `--pr` but no value exits with status 1.
test_status_missing_pr_value_exits_nonzero() {
  assert_exit 1 "status --pr without value exits non-zero" bash "$script" status --pr
}

test_status_missing_pr_value_stderr_message() {
  assert_stderr_contains "status --pr without value gives clear message" "missing value for --pr" bash "$script" status --pr
}

test_status_help_exits_zero() {
  assert_exit 0 "status --help exits 0" bash "$script" status --help
  assert_exit 0 "status -h exits 0" bash "$script" status -h
}

# test_status_paginated_merges_all_checks verifies that the status command merges paginated check-run responses and includes check runs from all returned pages.
test_status_paginated_merges_all_checks() {
  local page1='{"total_count":3,"check_runs":[{"name":"Zebra","status":"completed","conclusion":"success"}]}'
  local page2='{"total_count":3,"check_runs":[{"name":"Alpha","status":"completed","conclusion":"failure"}]}'
  setup_mocks_status_paginated "$page1" "$page2"
  local output
  output=$(run_script status --pr 42 2>&1)
  if echo "$output" | grep -qF "name: Alpha" \
    && echo "$output" | grep -qF "name: Zebra"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: paginated response should merge all pages (output: $output)"
  fi
}

# test_status_sha_lookup_failure_stderr_message verifies that a failed head SHA lookup causes the status command to emit "failed to resolve head SHA" and that the test harness records the failure or pass accordingly.
test_status_sha_lookup_failure_stderr_message() {
  setup_mocks_status_sha_fails
  local output
  output=$(run_script status 2>&1) || true
  if echo "$output" | grep -qF "failed to resolve head SHA"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SHA lookup failure should mention 'failed to resolve head SHA' (output: $output)"
  fi
}
