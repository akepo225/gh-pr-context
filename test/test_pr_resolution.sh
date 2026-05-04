#!/usr/bin/env bash

PATH="$HOME/bin:$PATH"

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

setup_mocks_no_pr() {
  setup_mocks_base
  gh() {
    case "$*" in
      *"pulls?head=acme:my-feature"*) echo "" ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_api_fail() {
  setup_mocks_base
  gh() {
    exit 1
  }
}

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
