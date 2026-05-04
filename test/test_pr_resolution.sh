#!/usr/bin/env bash

# setup_mocks_base sets up base mock implementations of `git` and `gh` for tests, where `git` returns a fixed origin URL or branch name and `gh` exits with failure.
setup_mocks_base() {
  git() {
    case "$*" in
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "my-feature" ;;
      *) exit 1 ;;
    esac
  }
  gh() {
    exit 1
  }
}

# setup_mocks_auto_detect sets up base git/gh mocks, sets _MOCK_HEAD_SHA to a fixed SHA, and overrides gh() to simulate auto-detection of PR 99 by returning the PR number, empty comments, the PR head SHA, and an empty check-runs response.
setup_mocks_auto_detect() {
  setup_mocks_base
  _MOCK_HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  gh() {
    case "$*" in
      *"pulls?head=acme:my-feature"*) echo '99' ;;
      *"pulls/99/comments"*) echo '[]' ;;
      *"issues/99/comments"*) echo '[]' ;;
      *"pulls/99"*) echo "$_MOCK_HEAD_SHA" ;;
      *"check-runs"*) echo '{"total_count":0,"check_runs":[]}' ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_explicit_pr sets up mocked git and gh functions for tests that use an explicit PR number (55), providing a fixed head SHA, returning empty comment lists and check-run metadata, and failing if auto-detect (`pulls?head=`) is invoked.
setup_mocks_explicit_pr() {
  setup_mocks_base
  _MOCK_HEAD_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  gh() {
    case "$*" in
      *"pulls?head="*) echo "SHOULD NOT BE CALLED" >&2; exit 1 ;;
      *"pulls/55/comments"*) echo '[]' ;;
      *"issues/55/comments"*) echo '[]' ;;
      *"pulls/55"*) echo "$_MOCK_HEAD_SHA" ;;
      *"check-runs"*) echo '{"total_count":0,"check_runs":[]}' ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_no_pr sets up base mocks and overrides gh to simulate "no open PR" by returning an empty string for pull requests queried by head and exiting non-zero for any other gh calls.
setup_mocks_no_pr() {
  setup_mocks_base
  gh() {
    case "$*" in
      *"pulls?head=acme:my-feature"*) echo "" ;;
      *) exit 1 ;;
    esac
  }
}

# setup_mocks_api_fail configures base mocks and overrides `gh` to always fail, simulating a GitHub CLI/API failure.
setup_mocks_api_fail() {
  setup_mocks_base
  gh() {
    exit 1
  }
}

# run_script exports mocked git and gh functions and _MOCK_HEAD_SHA into the environment and invokes the target script with the provided arguments.
run_script() {
  export -f git gh
  export _MOCK_HEAD_SHA
  bash "$script" "$@"
}

test_names+=(
  test_pr_resolution_auto_detect_comments
  test_pr_resolution_auto_detect_status
  test_pr_resolution_auto_detect_logs
  test_pr_resolution_explicit_pr_skips_autodetect_comments
  test_pr_resolution_explicit_pr_skips_autodetect_status
  test_pr_resolution_explicit_pr_skips_autodetect_logs
  test_pr_resolution_no_pr_found_exits_nonzero
  test_pr_resolution_no_pr_found_stderr_message
  test_pr_resolution_api_fail_exits_nonzero
  test_pr_resolution_api_fail_stderr_message
)

# test_pr_resolution_auto_detect_comments verifies that auto-detect resolves PR 99 and that running `comments` succeeds; it updates the global `pass`/`fail` counters and prints a failure message with the exit code when it fails.
test_pr_resolution_auto_detect_comments() {
  setup_mocks_auto_detect
  local exit_code=0
  run_script comments >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect should resolve PR 99 and succeed for comments (exit: $exit_code)"
  fi
}

# test_pr_resolution_auto_detect_status runs the `status` command with auto-detect mocks, expects the PR to be resolved to 99, and updates the global `pass`/`fail` counters (prints a failure message if the command exits non-zero).
test_pr_resolution_auto_detect_status() {
  setup_mocks_auto_detect
  local exit_code=0
  run_script status >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect should resolve PR 99 and succeed for status (exit: $exit_code)"
  fi
}

# test_pr_resolution_auto_detect_logs verifies that auto-detect resolves PR 99 for the logs command and increments the global pass or fail counter based on the command's exit status.
test_pr_resolution_auto_detect_logs() {
  setup_mocks_auto_detect
  local exit_code=0
  run_script logs >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect should resolve PR 99 and succeed for logs (exit: $exit_code)"
  fi
}

# test_pr_resolution_explicit_pr_skips_autodetect_comments verifies that providing --pr 55 prevents auto-detection when running the comments command and updates the global pass/fail counters, printing a diagnostic on failure.
test_pr_resolution_explicit_pr_skips_autodetect_comments() {
  setup_mocks_explicit_pr
  local output exit_code=0
  output=$(run_script comments --pr 55 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ] && ! echo "$output" | grep -qF "SHOULD NOT BE CALLED"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: explicit --pr should not trigger auto-detect for comments (exit: $exit_code, output: $output)"
  fi
}

# test_pr_resolution_explicit_pr_skips_autodetect_status verifies that providing `--pr 55` prevents auto-detection and succeeds when running the `status` command.
test_pr_resolution_explicit_pr_skips_autodetect_status() {
  setup_mocks_explicit_pr
  local output exit_code=0
  output=$(run_script status --pr 55 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ] && ! echo "$output" | grep -qF "SHOULD NOT BE CALLED"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: explicit --pr should not trigger auto-detect for status (exit: $exit_code, output: $output)"
  fi
}

# test_pr_resolution_explicit_pr_skips_autodetect_logs ensures an explicit --pr argument prevents auto-detection when invoking the logs command and updates global pass/fail counters, printing a diagnostic message on failure.
test_pr_resolution_explicit_pr_skips_autodetect_logs() {
  setup_mocks_explicit_pr
  local output exit_code=0
  output=$(run_script logs --pr 55 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ] && ! echo "$output" | grep -qF "SHOULD NOT BE CALLED"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: explicit --pr should not trigger auto-detect for logs (exit: $exit_code, output: $output)"
  fi
}

# test_pr_resolution_no_pr_found_exits_nonzero verifies that the script exits with a non-zero status when no open PR is found.
test_pr_resolution_no_pr_found_exits_nonzero() {
  setup_mocks_no_pr
  local exit_code=0
  run_script comments >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR found should exit non-zero"
  fi
}

# test_pr_resolution_no_pr_found_stderr_message checks that the comments command emits the literal "no open PR found" when no open PR is found.
test_pr_resolution_no_pr_found_stderr_message() {
  setup_mocks_no_pr
  local output
  output=$(run_script comments 2>&1) || true
  if echo "$output" | grep -qF "no open PR found"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR found should mention 'no open PR found' (output: $output)"
  fi
}

# test_pr_resolution_api_fail_exits_nonzero verifies that when the GitHub API fails, running `comments` exits with a non-zero status and the test harness updates the pass/fail counters accordingly.
test_pr_resolution_api_fail_exits_nonzero() {
  setup_mocks_api_fail
  local exit_code=0
  run_script comments >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: API failure should exit non-zero"
  fi
}

# test_pr_resolution_api_fail_stderr_message checks that invoking comments when the GitHub API fails prints a message containing "failed" and updates the pass/fail counters.
test_pr_resolution_api_fail_stderr_message() {
  setup_mocks_api_fail
  local output
  output=$(run_script comments 2>&1) || true
  if echo "$output" | grep -qiF "failed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: API failure should emit a failure message (output: $output)"
  fi
}
