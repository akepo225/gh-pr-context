#!/usr/bin/env bash
set -euo pipefail

HEAD_SHA="abc123def456abc123def456abc123def456abc1"
NEW_SHA="def456abc123def456abc123def456abc123def4"
_MOCK_SHA_COUNTER_FILE=""
_MOCK_CHECK_COUNTER_FILE=""
_MOCK_REVIEW_COUNTER_FILE=""
_MOCK_ISSUE_COUNTER_FILE=""

_mock_counter_next() {
  local file=$1 val
  val=$(cat "$file")
  val=$((val + 1))
  echo "$val" > "$file"
  echo "$val"
}

setup_counter_files() {
  _MOCK_SHA_COUNTER_FILE=$(mktemp)
  _MOCK_CHECK_COUNTER_FILE=$(mktemp)
  _MOCK_REVIEW_COUNTER_FILE=$(mktemp)
  _MOCK_ISSUE_COUNTER_FILE=$(mktemp)
  echo 0 > "$_MOCK_SHA_COUNTER_FILE"
  echo 0 > "$_MOCK_CHECK_COUNTER_FILE"
  echo 0 > "$_MOCK_REVIEW_COUNTER_FILE"
  echo 0 > "$_MOCK_ISSUE_COUNTER_FILE"
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
    exit 1
  }
  sleep() {
    :
  }
}

setup_mocks_monitor_all() {
  _MOCK_INITIAL_CHECKS="$1"
  _MOCK_CHANGED_CHECKS="$2"
  _MOCK_INITIAL_REVIEWS="$3"
  _MOCK_INITIAL_ISSUES="$4"
  _MOCK_CHANGED_REVIEWS="$5"
  _MOCK_CHANGED_ISSUES="$6"
  setup_counter_files
  setup_mocks
  gh() {
    case "$*" in
      *"pulls?head=acme:feature-branch"*"--paginate"*) echo "42" ;;
      *"pulls/42"*"--paginate"*"--jq"*)
        _mock_counter_next "$_MOCK_SHA_COUNTER_FILE" >/dev/null
        echo "$HEAD_SHA"
        ;;
      *"pulls/comments/"*"/replies"*)
        echo "ERROR: replies endpoint should not be called" >&2
        exit 1
        ;;
      *"check-runs"*"--paginate"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_CHECK_COUNTER_FILE")
        if [ "$call_num" -le 1 ]; then
          echo "$_MOCK_INITIAL_CHECKS"
        else
          echo "$_MOCK_CHANGED_CHECKS"
        fi
        ;;
      *"pulls/42/comments"*"--paginate"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_REVIEW_COUNTER_FILE")
        if [ "$call_num" -le 1 ]; then
          echo "$_MOCK_INITIAL_REVIEWS"
        else
          echo "$_MOCK_CHANGED_REVIEWS"
        fi
        ;;
      *"issues/42/comments"*"--paginate"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_ISSUE_COUNTER_FILE")
        if [ "$call_num" -le 1 ]; then
          echo "$_MOCK_INITIAL_ISSUES"
        else
          echo "$_MOCK_CHANGED_ISSUES"
        fi
        ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_all_new_commit() {
  _MOCK_INITIAL_CHECKS="$1"
  _MOCK_CHANGED_CHECKS="$1"
  _MOCK_INITIAL_REVIEWS="$2"
  _MOCK_INITIAL_ISSUES="$3"
  _MOCK_CHANGED_REVIEWS="$2"
  _MOCK_CHANGED_ISSUES="$3"
  setup_counter_files
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_SHA_COUNTER_FILE")
        if [ "$call_num" -le 1 ]; then
          echo "$HEAD_SHA"
        else
          echo "$NEW_SHA"
        fi
        ;;
      *"check-runs"*"--paginate"*) echo "$_MOCK_INITIAL_CHECKS" ;;
      *"pulls/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_REVIEWS" ;;
      *"issues/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_ISSUES" ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_all_no_change() {
  _MOCK_INITIAL_CHECKS="$1"
  _MOCK_CHANGED_CHECKS="$1"
  _MOCK_INITIAL_REVIEWS="$2"
  _MOCK_INITIAL_ISSUES="$3"
  _MOCK_CHANGED_REVIEWS="$2"
  _MOCK_CHANGED_ISSUES="$3"
  setup_counter_files
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
      *"check-runs"*"--paginate"*) echo "$_MOCK_INITIAL_CHECKS" ;;
      *"pulls/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_REVIEWS" ;;
      *"issues/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_ISSUES" ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_all_api_failure() {
  _MOCK_INITIAL_CHECKS="$1"
  _MOCK_CHANGED_CHECKS="$1"
  _MOCK_INITIAL_REVIEWS="$2"
  _MOCK_INITIAL_ISSUES="$3"
  _MOCK_CHANGED_REVIEWS="$2"
  _MOCK_CHANGED_ISSUES="$3"
  setup_counter_files
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*) echo "$HEAD_SHA" ;;
      *"check-runs"*"--paginate"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_CHECK_COUNTER_FILE")
        if [ "$call_num" -le 1 ]; then
          echo "$_MOCK_INITIAL_CHECKS"
        else
          exit 1
        fi
        ;;
      *"pulls/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_REVIEWS" ;;
      *"issues/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_ISSUES" ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_all_comment_api_timeout() {
  _MOCK_INITIAL_CHECKS="$1"
  _MOCK_CHANGED_CHECKS="$2"
  _MOCK_INITIAL_REVIEWS="$3"
  _MOCK_INITIAL_ISSUES="$4"
  _MOCK_CHANGED_REVIEWS="$5"
  _MOCK_CHANGED_ISSUES="$6"
  setup_counter_files
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*) echo "$HEAD_SHA" ;;
      *"check-runs"*"--paginate"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_CHECK_COUNTER_FILE")
        if [ "$call_num" -le 1 ]; then
          echo "$_MOCK_INITIAL_CHECKS"
        else
          echo "$_MOCK_CHANGED_CHECKS"
        fi
        ;;
      *"pulls/42/comments"*"--paginate"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_REVIEW_COUNTER_FILE")
        if [ "$call_num" -eq 2 ]; then
          exit 124
        elif [ "$call_num" -le 1 ]; then
          echo "$_MOCK_INITIAL_REVIEWS"
        else
          echo "$_MOCK_CHANGED_REVIEWS"
        fi
        ;;
      *"issues/42/comments"*"--paginate"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_ISSUE_COUNTER_FILE")
        if [ "$call_num" -le 1 ]; then
          echo "$_MOCK_INITIAL_ISSUES"
        else
          echo "$_MOCK_CHANGED_ISSUES"
        fi
        ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_all_sha_api_timeout() {
  _MOCK_INITIAL_CHECKS="$1"
  _MOCK_CHANGED_CHECKS="$2"
  _MOCK_INITIAL_REVIEWS="$3"
  _MOCK_INITIAL_ISSUES="$4"
  _MOCK_CHANGED_REVIEWS="$3"
  _MOCK_CHANGED_ISSUES="$4"
  setup_counter_files
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_SHA_COUNTER_FILE")
        if [ "$call_num" -eq 2 ]; then
          exit 124
        fi
        echo "$HEAD_SHA"
        ;;
      *"check-runs"*"--paginate"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_CHECK_COUNTER_FILE")
        if [ "$call_num" -le 1 ]; then
          echo "$_MOCK_INITIAL_CHECKS"
        else
          echo "$_MOCK_CHANGED_CHECKS"
        fi
        ;;
      *"pulls/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_REVIEWS" ;;
      *"issues/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_ISSUES" ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_all_check_api_timeout() {
  _MOCK_INITIAL_CHECKS="$1"
  _MOCK_CHANGED_CHECKS="$2"
  _MOCK_INITIAL_REVIEWS="$3"
  _MOCK_INITIAL_ISSUES="$4"
  _MOCK_CHANGED_REVIEWS="$3"
  _MOCK_CHANGED_ISSUES="$4"
  setup_counter_files
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42"*"--paginate"*"--jq"*) echo "$HEAD_SHA" ;;
      *"check-runs"*"--paginate"*)
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_CHECK_COUNTER_FILE")
        if [ "$call_num" -eq 2 ]; then
          exit 124
        elif [ "$call_num" -le 1 ]; then
          echo "$_MOCK_INITIAL_CHECKS"
        else
          echo "$_MOCK_CHANGED_CHECKS"
        fi
        ;;
      *"pulls/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_REVIEWS" ;;
      *"issues/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_ISSUES" ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_monitor_all_api_timeout_no_change() {
  _MOCK_INITIAL_CHECKS="$1"
  _MOCK_CHANGED_CHECKS="$1"
  _MOCK_INITIAL_REVIEWS="$2"
  _MOCK_INITIAL_ISSUES="$3"
  _MOCK_CHANGED_REVIEWS="$2"
  _MOCK_CHANGED_ISSUES="$3"
  setup_counter_files
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
        local call_num
        call_num=$(_mock_counter_next "$_MOCK_CHECK_COUNTER_FILE")
        if [ "$call_num" -eq 2 ]; then
          exit 124
        fi
        echo "$_MOCK_INITIAL_CHECKS"
        ;;
      *"pulls/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_REVIEWS" ;;
      *"issues/42/comments"*"--paginate"*) echo "$_MOCK_INITIAL_ISSUES" ;;
      *) exit 1 ;;
    esac
  }
}

run_script() {
  export -f git gh sleep _mock_counter_next
  export HEAD_SHA NEW_SHA
  export _MOCK_INITIAL_CHECKS _MOCK_CHANGED_CHECKS
  export _MOCK_INITIAL_REVIEWS _MOCK_INITIAL_ISSUES _MOCK_CHANGED_REVIEWS _MOCK_CHANGED_ISSUES
  export _MOCK_SHA_COUNTER_FILE _MOCK_CHECK_COUNTER_FILE _MOCK_REVIEW_COUNTER_FILE _MOCK_ISSUE_COUNTER_FILE
  timeout 15 bash "$script" "$@" </dev/null
}

run_script_with_real_sleep() {
  run_script "$@"
}

cleanup_mock_counters() {
  for file in "$_MOCK_SHA_COUNTER_FILE" "$_MOCK_CHECK_COUNTER_FILE" "$_MOCK_REVIEW_COUNTER_FILE" "$_MOCK_ISSUE_COUNTER_FILE"; do
    [ -n "$file" ] && [ -f "$file" ] && rm -f "$file"
  done
}

test_names+=(
  test_monitor_all_status_only
  test_monitor_all_comments_only
  test_monitor_all_mixed_changes_status_first
  test_monitor_all_new_commit
  test_monitor_all_check_flag_rejected
  test_monitor_all_missing_pr_value_exits_nonzero
  test_monitor_all_unknown_option_exits_nonzero
  test_monitor_all_missing_interval_value_exits_nonzero
  test_monitor_all_invalid_interval_exits_nonzero
  test_monitor_all_zero_interval_exits_nonzero
  test_monitor_all_negative_interval_exits_nonzero
  test_monitor_all_missing_timeout_value_exits_nonzero
  test_monitor_all_invalid_timeout_exits_nonzero
  test_monitor_all_timeout_exits_two
  test_monitor_all_explicit_pr
  test_monitor_all_auto_detect
  test_monitor_all_accepts_timeout
  test_monitor_all_api_failure_exits_nonzero
  test_monitor_all_sha_api_timeout_continues
  test_monitor_all_check_api_timeout_continues
  test_monitor_all_comment_api_timeout_continues
  test_monitor_all_overall_timeout_after_api_timeout
  test_monitor_all_help_exits_zero
  test_monitor_help_lists_all
)

test_monitor_all_status_only() {
  local initial_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  local initial_reviews='[]'
  local initial_issues='[{"id":201}]'
  setup_mocks_monitor_all "$initial_checks" "$changed_checks" "$initial_reviews" "$initial_issues" "$initial_reviews" "$initial_issues"
  local output
  output=$(run_script monitor --all --pr 42 --interval 1 2>&1)
  cleanup_mock_counters
  if echo "$output" | grep -qF "type: status" \
    && echo "$output" | grep -qF "check: CI" \
    && echo "$output" | grep -qF "to: completed" \
    && ! echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all status-only change (output: $output)"
  fi
}

test_monitor_all_comments_only() {
  local checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local initial_issues='[]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  local changed_issues='[]'
  setup_mocks_monitor_all "$checks" "$checks" "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues"
  local output
  output=$(run_script monitor --all --pr 42 --interval 1 2>&1)
  cleanup_mock_counters
  if echo "$output" | grep -qF "type: new-comment" \
    && echo "$output" | grep -qF "count: 1" \
    && ! echo "$output" | grep -qF "type: status"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all comment-only change (output: $output)"
  fi
}

test_monitor_all_mixed_changes_status_first() {
  local initial_checks='{"total_count":2,"check_runs":[{"name":"Test","status":"queued","conclusion":null},{"name":"Build","status":"in_progress","conclusion":null}]}'
  local changed_checks='{"total_count":2,"check_runs":[{"name":"Test","status":"completed","conclusion":"failure"},{"name":"Build","status":"completed","conclusion":"success"}]}'
  local initial_reviews='[]'
  local initial_issues='[{"id":201}]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null}]'
  local changed_issues='[{"id":201},{"id":202}]'
  setup_mocks_monitor_all "$initial_checks" "$changed_checks" "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues"
  local output first_type last_type first_check second_check comment_count
  output=$(run_script monitor --all --pr 42 --interval 1 2>&1)
  cleanup_mock_counters
  first_type=$(echo "$output" | grep "^type:" | head -1 | tr -d '\r')
  last_type=$(echo "$output" | grep "^type:" | tail -1 | tr -d '\r')
  first_check=$(echo "$output" | grep "^check:" | head -1 | sed 's/check: //' | tr -d '\r')
  second_check=$(echo "$output" | grep "^check:" | tail -1 | sed 's/check: //' | tr -d '\r')
  comment_count=$(echo "$output" | grep "type: new-comment" | wc -l | tr -d '[:space:]')
  if [ "$first_type" = "type: status" ] \
    && [ "$last_type" = "type: new-comment" ] \
    && [ "$first_check" = "Build" ] \
    && [ "$second_check" = "Test" ] \
    && [ "$comment_count" = "1" ] \
    && echo "$output" | grep -qF "count: 2"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all mixed output ordering (output: $output)"
  fi
}

test_monitor_all_new_commit() {
  local checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local reviews='[]'
  local issues='[]'
  setup_mocks_monitor_all_new_commit "$checks" "$reviews" "$issues"
  local output
  output=$(run_script monitor --all --pr 42 --interval 1 2>&1)
  cleanup_mock_counters
  if echo "$output" | grep -qF "type: new-commit" \
    && echo "$output" | grep -qF "sha: $NEW_SHA" \
    && ! echo "$output" | grep -qF "type: status" \
    && ! echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all new commit (output: $output)"
  fi
}

test_monitor_all_check_flag_rejected() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor --all --check ci.yml 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "unknown option: --check (only valid with monitor status)"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all --check should be rejected (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_missing_pr_value_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor --all --pr 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "missing value for --pr"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all --pr should exit 1 with missing value message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_unknown_option_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor --all --bogus 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "unknown option: --bogus"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all --bogus should exit 1 with unknown option message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_missing_interval_value_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor --all --interval 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "missing value for --interval"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all --interval should exit 1 with missing value message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_invalid_interval_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor --all --interval abc 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "invalid --interval value: abc"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all --interval abc should exit 1 with invalid interval message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_zero_interval_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor --all --interval 0 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "invalid --interval value: 0"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all --interval 0 should exit 1 with invalid interval message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_negative_interval_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor --all --interval -1 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "invalid --interval value: -1"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all --interval -1 should exit 1 with invalid interval message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_missing_timeout_value_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor --all --timeout 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "missing value for --timeout"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all --timeout should exit 1 with missing value message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_invalid_timeout_exits_nonzero() {
  local output exit_code=0
  setup_mocks
  output=$(run_script monitor --all --timeout abc 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -qF "invalid duration"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all --timeout abc should exit 1 with invalid duration message (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_timeout_exits_two() {
  local checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local reviews='[{"id":101,"in_reply_to_id":null}]'
  local issues='[]'
  setup_mocks_monitor_all_no_change "$checks" "$reviews" "$issues"
  local exit_code=0
  run_script_with_real_sleep monitor --all --pr 42 --interval 1 --timeout 2s >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counters
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all timeout should exit 2 (exit: $exit_code)"
  fi
}

test_monitor_all_explicit_pr() {
  local initial_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"queued","conclusion":null}]}'
  local changed_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  setup_mocks_monitor_all "$initial_checks" "$changed_checks" "[]" "[]" "[]" "[]"
  local exit_code=0
  run_script monitor --all --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counters
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all explicit --pr should succeed (exit: $exit_code)"
  fi
}

test_monitor_all_auto_detect() {
  local checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed_reviews='[{"id":101,"in_reply_to_id":null}]'
  setup_mocks_monitor_all "$checks" "$checks" "[]" "[]" "$changed_reviews" "[]"
  local output
  output=$(run_script monitor --all --interval 1 2>&1)
  cleanup_mock_counters
  if echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all auto-detect should work (output: $output)"
  fi
}

test_monitor_all_accepts_timeout() {
  local initial_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"queued","conclusion":null}]}'
  local changed_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  setup_mocks_monitor_all "$initial_checks" "$changed_checks" "[]" "[]" "[]" "[]"
  local exit_code=0
  run_script monitor --all --pr 42 --interval 1 --timeout 5m >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counters
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all should accept --timeout 5m (exit: $exit_code)"
  fi
}

test_monitor_all_api_failure_exits_nonzero() {
  local checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  setup_mocks_monitor_all_api_failure "$checks" "[]" "[]"
  local exit_code=0
  run_script monitor --all --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_counters
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all API failure should exit non-zero"
  fi
}

test_monitor_all_sha_api_timeout_continues() {
  local initial_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_monitor_all_sha_api_timeout "$initial_checks" "$changed_checks" "[]" "[]"
  local output exit_code=0
  output=$(run_script monitor --all --pr 42 --interval 1 --timeout 5m 2>&1) || exit_code=$?
  cleanup_mock_counters
  if [ "$exit_code" -eq 0 ] \
    && echo "$output" | grep -qF "gh api call timed out; retrying next poll" \
    && echo "$output" | grep -qF "type: status" \
    && echo "$output" | grep -qF "check: CI" \
    && echo "$output" | grep -qF "to: completed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all SHA API timeout should warn, retry, and detect change (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_check_api_timeout_continues() {
  local initial_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_monitor_all_check_api_timeout "$initial_checks" "$changed_checks" "[]" "[]"
  local output exit_code=0
  output=$(run_script monitor --all --pr 42 --interval 1 --timeout 5m 2>&1) || exit_code=$?
  cleanup_mock_counters
  if [ "$exit_code" -eq 0 ] \
    && echo "$output" | grep -qF "gh api call timed out; retrying next poll" \
    && echo "$output" | grep -qF "type: status" \
    && echo "$output" | grep -qF "check: CI" \
    && echo "$output" | grep -qF "to: completed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all check-runs API timeout should warn, retry, and detect change (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_comment_api_timeout_continues() {
  local initial_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed_checks='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_monitor_all_comment_api_timeout "$initial_checks" "$changed_checks" "[]" "[]" "[]" "[]"
  local output exit_code=0
  output=$(run_script monitor --all --pr 42 --interval 1 --timeout 5m 2>&1) || exit_code=$?
  cleanup_mock_counters
  if [ "$exit_code" -eq 0 ] \
    && echo "$output" | grep -qF "gh api call timed out; retrying next poll" \
    && echo "$output" | grep -qF "type: status" \
    && echo "$output" | grep -qF "check: CI" \
    && echo "$output" | grep -qF "to: completed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all comment API timeout should warn, retry, and detect change (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_overall_timeout_after_api_timeout() {
  local checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  setup_mocks_monitor_all_api_timeout_no_change "$checks" "[]" "[]"
  local output exit_code=0
  output=$(run_script_with_real_sleep monitor --all --pr 42 --interval 1 --timeout 2s 2>&1) || exit_code=$?
  cleanup_mock_counters
  if [ "$exit_code" -eq 2 ] \
    && echo "$output" | grep -qF "gh api call timed out; retrying next poll" \
    && echo "$output" | grep -qF "monitor timed out after 2s"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all overall timeout should still fire after API timeout (exit=$exit_code, output: $output)"
  fi
}

test_monitor_all_help_exits_zero() {
  assert_exit 0 "monitor --all --help exits 0" bash "$script" monitor --all --help
  assert_exit 0 "monitor --all -h exits 0" bash "$script" monitor --all -h
}

test_monitor_help_lists_all() {
  local output
  output=$(bash "$script" monitor --help 2>&1)
  if echo "$output" | grep -qF -- "--all"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --help should list --all (output: $output)"
  fi
}
