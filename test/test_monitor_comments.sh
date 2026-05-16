#!/usr/bin/env bash

_MOCK_COUNTER_FILE=""

_mock_counter_next() {
  local val
  val=$(cat "$_MOCK_COUNTER_FILE")
  val=$((val + 1))
  echo "$val" > "$_MOCK_COUNTER_FILE"
  echo "$val"
}

_mock_call_should_timeout() {
  local call_num=$1 timeout_call
  for timeout_call in $_MOCK_TIMEOUT_CALLS; do
    if [ "$call_num" = "$timeout_call" ]; then
      return 0
    fi
  done
  return 1
}

setup_mocks() {
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) exit 1 ;;
    esac
  }
  gh() {
    echo "gh: unexpected call: $*" >&2
    exit 1
  }
  sleep() {
    :
  }
}

setup_mocks_monitor_comments_explicit_pr() {
  _MOCK_INITIAL_REVIEWS="$1"
  _MOCK_INITIAL_ISSUES="$2"
  _MOCK_CHANGED_REVIEWS="$3"
  _MOCK_CHANGED_ISSUES="$4"
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  setup_mocks
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "abc123def456abc123def456abc123def456abc1"
        ;;
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
        if [ "$call_num" -le 3 ]; then
          echo "$_MOCK_INITIAL_ISSUES"
        else
          echo "$_MOCK_CHANGED_ISSUES"
        fi
        ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_comments_auto_detect() {
  _MOCK_INITIAL_REVIEWS="$1"
  _MOCK_INITIAL_ISSUES="$2"
  _MOCK_CHANGED_REVIEWS="$3"
  _MOCK_CHANGED_ISSUES="$4"
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  setup_mocks
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls?head=acme:feature-branch"*"--paginate"*) echo '42' ;;
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "abc123def456abc123def456abc123def456abc1"
        ;;
      *"pulls/comments/"*"/replies"*)
        echo "ERROR: replies endpoint should not be called" >&2
        exit 1
        ;;
      *"pulls/42/comments"*"--paginate"*)
        if [ "$call_num" -le 3 ]; then
          echo "$_MOCK_INITIAL_REVIEWS"
        else
          echo "$_MOCK_CHANGED_REVIEWS"
        fi
        ;;
      *"issues/42/comments"*"--paginate"*)
        if [ "$call_num" -le 4 ]; then
          echo "$_MOCK_INITIAL_ISSUES"
        else
          echo "$_MOCK_CHANGED_ISSUES"
        fi
        ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_comments_no_change() {
  _MOCK_REVIEWS="$1"
  _MOCK_ISSUES="$2"
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
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "abc123def456abc123def456abc123def456abc1"
        ;;
      *"pulls/42/comments"*"--paginate"*)
        echo "$_MOCK_REVIEWS"
        ;;
      *"issues/42/comments"*"--paginate"*)
        echo "$_MOCK_ISSUES"
        ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_comments_no_pr() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls?head=acme:feature-branch"*"--paginate"*) echo "" ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_comments_api_failure() {
  _MOCK_INITIAL_REVIEWS="$1"
  _MOCK_INITIAL_ISSUES="$2"
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  setup_mocks
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "abc123def456abc123def456abc123def456abc1"
        ;;
      *"pulls/42/comments"*"--paginate"*)
        if [ "$call_num" -le 2 ]; then
          echo "$_MOCK_INITIAL_REVIEWS"
        else
          echo "$_MOCK_INITIAL_REVIEWS"
        fi
        ;;
      *"issues/42/comments"*"--paginate"*)
        if [ "$call_num" -le 3 ]; then
          echo "$_MOCK_INITIAL_ISSUES"
        else
          exit 1
        fi
        ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_comments_api_timeout() {
  _MOCK_INITIAL_REVIEWS="$1"
  _MOCK_INITIAL_ISSUES="$2"
  _MOCK_CHANGED_REVIEWS="$3"
  _MOCK_CHANGED_ISSUES="$4"
  _MOCK_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_COUNTER_FILE"
  setup_mocks
  _MOCK_TIMEOUT_CALLS="$5"
  gh() {
    local call_num
    call_num=$(_mock_counter_next)
    if _mock_call_should_timeout "$call_num"; then
      exit 124
    fi
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "abc123def456abc123def456abc123def456abc1"
        ;;
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
        if [ "$call_num" -le 3 ]; then
          echo "$_MOCK_INITIAL_ISSUES"
        else
          echo "$_MOCK_CHANGED_ISSUES"
        fi
        ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_comments_api_timeout_no_change() {
  _MOCK_INITIAL_REVIEWS="$1"
  _MOCK_INITIAL_ISSUES="$2"
  _MOCK_TIMEOUT_CALLS="$3"
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
    if _mock_call_should_timeout "$call_num"; then
      exit 124
    fi
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        echo "abc123def456abc123def456abc123def456abc1"
        ;;
      *"pulls/42/comments"*"--paginate"*)
        echo "$_MOCK_INITIAL_REVIEWS"
        ;;
      *"issues/42/comments"*"--paginate"*)
        echo "$_MOCK_INITIAL_ISSUES"
        ;;
      *) exit 1 ;;
    esac
  }
}

run_script() {
  export -f git gh sleep _mock_counter_next _mock_call_should_timeout
  export _MOCK_INITIAL_REVIEWS _MOCK_INITIAL_ISSUES _MOCK_CHANGED_REVIEWS _MOCK_CHANGED_ISSUES
  export _MOCK_REVIEWS _MOCK_ISSUES _MOCK_COUNTER_FILE _MOCK_TIMEOUT_CALLS
  timeout 15 bash "$script" "$@" </dev/null
}

run_script_with_real_sleep() {
  export -f git gh sleep _mock_counter_next _mock_call_should_timeout
  export _MOCK_INITIAL_REVIEWS _MOCK_INITIAL_ISSUES _MOCK_CHANGED_REVIEWS _MOCK_CHANGED_ISSUES
  export _MOCK_REVIEWS _MOCK_ISSUES _MOCK_COUNTER_FILE _MOCK_TIMEOUT_CALLS
  timeout 15 bash "$script" "$@" </dev/null
}

cleanup_mock_counter() {
  [ -n "$_MOCK_COUNTER_FILE" ] && [ -f "$_MOCK_COUNTER_FILE" ] && rm -f "$_MOCK_COUNTER_FILE"
}

test_names+=(
  test_monitor_comments_new_review_comment
  test_monitor_comments_new_issue_comment
  test_monitor_comments_multiple_new_comments
  test_monitor_comments_existing_not_reported
  test_monitor_comments_reply_not_counted
  test_monitor_comments_output_format
  test_monitor_comments_check_flag_rejected
  test_monitor_comments_timeout_exits_two
  test_monitor_comments_timeout_stderr_message
  test_monitor_comments_explicit_pr
  test_monitor_comments_auto_detect
  test_monitor_comments_no_pr_exits_nonzero
  test_monitor_comments_no_pr_stderr_message
  test_monitor_comments_api_failure_exits_nonzero
  test_monitor_comments_help_exits_zero
  test_monitor_comments_missing_pr_value_exits_nonzero
  test_monitor_comments_missing_interval_value_exits_nonzero
  test_monitor_comments_invalid_interval_exits_nonzero
  test_monitor_comments_zero_interval_exits_nonzero
  test_monitor_comments_negative_interval_exits_nonzero
  test_monitor_comments_missing_timeout_value_exits_nonzero
  test_monitor_comments_invalid_timeout_exits_nonzero
  test_monitor_comments_api_timeout_continues
  test_monitor_comments_overall_timeout_after_api_timeout
)

test_monitor_comments_new_review_comment() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  local changed_issues='[]'
  setup_mocks_monitor_comments_explicit_pr "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues"
  local output
  output=$(run_script monitor comments --pr 42 --interval 1 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "type: new-comment" \
    && echo "$output" | grep -qF "count: 1"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: new review comment (output: $output)"
  fi
}

test_monitor_comments_new_issue_comment() {
  local initial_reviews='[]'
  local initial_issues='[{"id":201}]'
  local changed_reviews='[]'
  local changed_issues='[{"id":201},{"id":202}]'
  setup_mocks_monitor_comments_explicit_pr "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues"
  local output
  output=$(run_script monitor comments --pr 42 --interval 1 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "type: new-comment" \
    && echo "$output" | grep -qF "count: 1"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: new issue comment (output: $output)"
  fi
}

test_monitor_comments_multiple_new_comments() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[{"id":201}]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null},{"id":103,"in_reply_to_id":null}]'
  local changed_issues='[{"id":201},{"id":202}]'
  setup_mocks_monitor_comments_explicit_pr "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues"
  local output
  output=$(run_script monitor comments --pr 42 --interval 1 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "type: new-comment" \
    && echo "$output" | grep -qF "count: 3"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: multiple new comments (output: $output)"
  fi
}

test_monitor_comments_existing_not_reported() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[{"id":201}]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null}]'
  local changed_issues='[{"id":201}]'
  setup_mocks_monitor_comments_no_change "$initial_reviews" "$initial_issues"
  local output
  output=$(run_script_with_real_sleep monitor comments --pr 42 --interval 1 --timeout 2s 2>&1) || true
  if echo "$output" | grep -qF "timed out" \
    && ! echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: existing comments should not be reported (output: $output)"
  fi
}

test_monitor_comments_reply_not_counted() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":101}]'
  local changed_issues='[]'
  setup_mocks_monitor_comments_explicit_pr "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues"
  local output
  output=$(run_script_with_real_sleep monitor comments --pr 42 --interval 1 --timeout 2s 2>&1) || true
  if ! echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply should not be counted as new comment (output: $output)"
  fi
}

test_monitor_comments_output_format() {
  local initial_reviews='[]'
  local initial_issues='[]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null}]'
  local changed_issues='[]'
  setup_mocks_monitor_comments_explicit_pr "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues"
  local output
  output=$(run_script monitor comments --pr 42 --interval 1 2>&1)
  cleanup_mock_counter
  local line1 line2 line3
  line1=$(echo "$output" | head -1 | tr -d '\r')
  line2=$(echo "$output" | sed -n '2p' | tr -d '\r')
  line3=$(echo "$output" | sed -n '3p' | tr -d '\r')
  if [ "$line1" = "--- change" ] \
    && [ "$line2" = "type: new-comment" ] \
    && [ "$line3" = "count: 1" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: output format (line1=$line1, line2=$line2, line3=$line3, output: $output)"
  fi
}

test_monitor_comments_check_flag_rejected() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor comments --check ci.yml 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF -- "unknown option: --check (only valid with monitor status)"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check should be rejected for monitor comments (exit=$exit_code, output: $output)"
  fi
}

test_monitor_comments_timeout_exits_two() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[]'
  setup_mocks_monitor_comments_no_change "$initial_reviews" "$initial_issues"
  local exit_code=0
  run_script_with_real_sleep monitor comments --pr 42 --interval 1 --timeout 2s >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: timeout should exit 2 (exit: $exit_code)"
  fi
}

test_monitor_comments_timeout_stderr_message() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[]'
  setup_mocks_monitor_comments_no_change "$initial_reviews" "$initial_issues"
  local output
  output=$(run_script_with_real_sleep monitor comments --pr 42 --interval 1 --timeout 2s 2>&1) || true
  if echo "$output" | grep -qF "monitor timed out after 2s"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: timeout stderr message (output: $output)"
  fi
}

test_monitor_comments_explicit_pr() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  local changed_issues='[]'
  setup_mocks_monitor_comments_explicit_pr "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues"
  local exit_code=0
  run_script monitor comments --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: explicit --pr 42 should succeed (exit: $exit_code)"
  fi
}

test_monitor_comments_auto_detect() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  local changed_issues='[]'
  setup_mocks_monitor_comments_auto_detect "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues"
  local output
  output=$(run_script monitor comments --interval 1 2>&1)
  cleanup_mock_counter
  if echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect PR should work (output: $output)"
  fi
}

test_monitor_comments_no_pr_exits_nonzero() {
  setup_mocks_monitor_comments_no_pr
  local exit_code=0
  run_script monitor comments --interval 1 >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR should exit non-zero"
  fi
}

test_monitor_comments_no_pr_stderr_message() {
  setup_mocks_monitor_comments_no_pr
  local output
  output=$(run_script monitor comments --interval 1 2>&1) || true
  if echo "$output" | grep -qF "no open PR found for branch 'feature-branch'"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR stderr should contain no-open-PR message (output: $output)"
  fi
}

test_monitor_comments_api_failure_exits_nonzero() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[]'
  setup_mocks_monitor_comments_api_failure "$initial_reviews" "$initial_issues"
  local exit_code=0
  run_script monitor comments --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: API failure should exit non-zero"
  fi
}

test_monitor_comments_help_exits_zero() {
  setup_mocks
  assert_exit 0 "monitor comments --help exits 0" run_script monitor comments --help
  setup_mocks
  assert_exit 0 "monitor comments -h exits 0" run_script monitor comments -h
}

test_monitor_comments_missing_pr_value_exits_nonzero() {
  setup_mocks
  assert_exit 1 "monitor comments --pr without value exits 1" run_script monitor comments --pr
}

test_monitor_comments_missing_interval_value_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor comments --interval 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "missing value for --interval"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor comments --interval should exit 1 with missing value message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_comments_invalid_interval_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor comments --interval abc 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "invalid --interval value: abc"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor comments --interval abc should exit 1 with invalid interval message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_comments_zero_interval_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor comments --interval 0 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "invalid --interval value: 0"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor comments --interval 0 should exit 1 with invalid interval message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_comments_negative_interval_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor comments --interval -1 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "invalid --interval value: -1"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor comments --interval -1 should exit 1 with invalid interval message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_comments_missing_timeout_value_exits_nonzero() {
  setup_mocks
  assert_exit 1 "monitor comments --timeout without value exits 1" run_script monitor comments --timeout
}

test_monitor_comments_invalid_timeout_exits_nonzero() {
  setup_mocks
  assert_exit 1 "monitor comments --timeout invalid exits 1" run_script monitor comments --timeout abc
}

test_monitor_comments_api_timeout_continues() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  local changed_issues='[]'
  setup_mocks_monitor_comments_api_timeout "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues" "4"
  local output exit_code=0
  output=$(run_script monitor comments --pr 42 --interval 1 --timeout 5m 2>&1) || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -eq 0 ] \
    && echo "$output" | grep -qF "gh api call timed out; retrying next poll" \
    && echo "$output" | grep -qF "type: new-comment" \
    && echo "$output" | grep -qF "count: 1"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: API timeout should warn, retry, and detect change (exit=$exit_code, output: $output)"
  fi
}

test_monitor_comments_overall_timeout_after_api_timeout() {
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[]'
  setup_mocks_monitor_comments_api_timeout_no_change "$initial_reviews" "$initial_issues" "3"
  local output exit_code=0
  output=$(run_script_with_real_sleep monitor comments --pr 42 --interval 1 --timeout 2s 2>&1) || exit_code=$?
  cleanup_mock_counter
  if [ "$exit_code" -eq 2 ] \
    && echo "$output" | grep -qF "gh api call timed out; retrying next poll" \
    && echo "$output" | grep -qF "monitor timed out after 2s"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: overall timeout should still fire after API timeout (exit=$exit_code, output: $output)"
  fi
}
