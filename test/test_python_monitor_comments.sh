#!/usr/bin/env bash

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
python_script="$repo_root/gh-pr-context.py"
if command -v py >/dev/null 2>&1; then
  python_cmd="py -3"
else
  python_cmd="python3"
fi

pass=${pass:-0}
fail=${fail:-0}
_MOCK_DIR=""

assert_exit() {
  local expected_exit=$1 desc=$2; shift 2
  local actual_exit=0
  "$@" >/dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
  fi
}

assert_stderr_contains() {
  local desc=$1 needle=$2; shift 2
  local output
  output=$("$@" 2>&1 >/dev/null) || true
  if echo "$output" | grep -qF "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $desc (stderr did not contain: $needle)"
  fi
}

setup_mock_dir() {
  _MOCK_DIR=$(mktemp -d)
}

cleanup_mock_dir() {
  if [ -n "${_MOCK_DIR:-}" ] && [ -d "$_MOCK_DIR" ]; then
    rm -rf "$_MOCK_DIR"
  fi
}

write_git_mock() {
  cat > "$_MOCK_DIR/git" << 'GIT_EOF'
#!/usr/bin/env bash
case "$*" in
  "rev-parse --git-dir") echo ".git" ;;
  "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
  "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
  *) exit 1 ;;
esac
GIT_EOF
  chmod +x "$_MOCK_DIR/git"
}

write_gh_stateful_mock() {
  local initial_reviews="$1"
  local initial_issues="$2"
  local changed_reviews="$3"
  local changed_issues="$4"
  local review_threshold="${5:-2}"
  local issue_threshold="${6:-3}"
  echo 0 > "$_MOCK_DIR/counter"
  cat > "$_MOCK_DIR/gh" << GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
esac
call_num=\$(cat $_MOCK_DIR/counter)
call_num=\$((call_num + 1))
echo "\$call_num" > "$_MOCK_DIR/counter"
case "\$*" in
  *"repos/acme/widgets/pulls/42/comments"*)
    if [ "\$call_num" -le $review_threshold ]; then
      printf '%s' '$initial_reviews'
    else
      printf '%s' '$changed_reviews'
    fi
    ;;
  *"repos/acme/widgets/issues/42/comments"*)
    if [ "\$call_num" -le $issue_threshold ]; then
      printf '%s' '$initial_issues'
    else
      printf '%s' '$changed_issues'
    fi
    ;;
  *) echo "UNMATCHED: \$*" >&2; exit 1 ;;
esac
GHEOF
  chmod +x "$_MOCK_DIR/gh"
}

write_gh_auto_detect_mock() {
  local initial_reviews="$1"
  local initial_issues="$2"
  local changed_reviews="$3"
  local changed_issues="$4"
  echo 0 > "$_MOCK_DIR/counter"
  cat > "$_MOCK_DIR/gh" << GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
  *"pulls?head=acme:feature-branch"*"--jq"*) echo '42'; exit 0 ;;
esac
call_num=\$(cat $_MOCK_DIR/counter)
call_num=\$((call_num + 1))
echo "\$call_num" > "$_MOCK_DIR/counter"
case "\$*" in
  *"repos/acme/widgets/pulls/42/comments"*)
    if [ "\$call_num" -le 3 ]; then
      printf '%s' '$initial_reviews'
    else
      printf '%s' '$changed_reviews'
    fi
    ;;
  *"repos/acme/widgets/issues/42/comments"*)
    if [ "\$call_num" -le 4 ]; then
      printf '%s' '$initial_issues'
    else
      printf '%s' '$changed_issues'
    fi
    ;;
  *) echo "UNMATCHED: \$*" >&2; exit 1 ;;
esac
GHEOF
  chmod +x "$_MOCK_DIR/gh"
}

write_gh_no_pr_mock() {
  cat > "$_MOCK_DIR/gh" << 'GH_EOF'
#!/usr/bin/env bash
case "$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
  *"pulls?head=acme:feature-branch"*"--jq"*) echo ''; exit 0 ;;
  *) exit 1 ;;
esac
GH_EOF
  chmod +x "$_MOCK_DIR/gh"
}

write_gh_api_failure_mock() {
  local initial_reviews="$1"
  local initial_issues="$2"
  echo 0 > "$_MOCK_DIR/counter"
  cat > "$_MOCK_DIR/gh" << GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
esac
call_num=\$(cat $_MOCK_DIR/counter)
call_num=\$((call_num + 1))
echo "\$call_num" > "$_MOCK_DIR/counter"
case "\$*" in
  *"repos/acme/widgets/pulls/42/comments"*)
    printf '%s' '$initial_reviews'
    ;;
  *"repos/acme/widgets/issues/42/comments"*)
    if [ "\$call_num" -le 3 ]; then
      printf '%s' '$initial_issues'
    else
      exit 1
    fi
    ;;
  *) exit 1 ;;
esac
GHEOF
  chmod +x "$_MOCK_DIR/gh"
}

write_gh_no_change_mock() {
  local reviews="$1"
  local issues="$2"
  cat > "$_MOCK_DIR/gh" << GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
esac
case "\$*" in
  *"repos/acme/widgets/pulls/42/comments"*)
    printf '%s' '$reviews'
    ;;
  *"repos/acme/widgets/issues/42/comments"*)
    printf '%s' '$issues'
    ;;
  *) exit 1 ;;
esac
GHEOF
  chmod +x "$_MOCK_DIR/gh"
}

run_python() {
  if command -v cygpath >/dev/null 2>&1; then
    local git_bash='"C:/Program Files/Git/usr/bin/bash.exe"'
    local git_mock="$git_bash $(cygpath -m "$_MOCK_DIR/git")"
    local gh_mock="$git_bash $(cygpath -m "$_MOCK_DIR/gh")"
  else
    local git_mock="bash $_MOCK_DIR/git"
    local gh_mock="bash $_MOCK_DIR/gh"
  fi
  GH_PR_CONTEXT_GIT="$git_mock" GH_PR_CONTEXT_GH="$gh_mock" \
    timeout 15 $python_cmd "$python_script" "$@"
}

run_python_no_mock() {
  $python_cmd "$python_script" "$@"
}

# --- Tests ---

test_py_monitor_comments_new_review_comment() {
  setup_mock_dir
  write_git_mock
  local initial='[{"id":101,"in_reply_to_id":null}]'
  local changed='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  write_gh_stateful_mock "$initial" '[]' "$changed" '[]'
  local output
  output=$(run_python monitor comments --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "type: new-comment" \
    && echo "$output" | grep -qF "count: 1"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: new review comment (output: $output)"
  fi
}

test_py_monitor_comments_new_issue_comment() {
  setup_mock_dir
  write_git_mock
  local initial='[{"id":201}]'
  local changed='[{"id":201},{"id":202}]'
  write_gh_stateful_mock '[]' "$initial" '[]' "$changed"
  local output
  output=$(run_python monitor comments --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "type: new-comment" \
    && echo "$output" | grep -qF "count: 1"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: new issue comment (output: $output)"
  fi
}

test_py_monitor_comments_multiple_new_comments() {
  setup_mock_dir
  write_git_mock
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null},{"id":103,"in_reply_to_id":null}]'
  local initial_issues='[{"id":201}]'
  local changed_issues='[{"id":201},{"id":202}]'
  write_gh_stateful_mock "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues"
  local output
  output=$(run_python monitor comments --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "type: new-comment" \
    && echo "$output" | grep -qF "count: 3"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: multiple new comments (output: $output)"
  fi
}

test_py_monitor_comments_existing_not_reported() {
  setup_mock_dir
  write_git_mock
  local reviews='[{"id":101,"in_reply_to_id":null}]'
  local issues='[{"id":201}]'
  write_gh_no_change_mock "$reviews" "$issues"
  local output exit_code=0
  output=$(run_python monitor comments --pr 42 --interval 1 --timeout 2s 2>&1) || exit_code=$?
  cleanup_mock_dir
  if echo "$output" | grep -qF "timed out" \
    && ! echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: existing comments should not be reported (output: $output)"
  fi
}

test_py_monitor_comments_reply_not_counted() {
  setup_mock_dir
  write_git_mock
  local initial='[{"id":101,"in_reply_to_id":null}]'
  local changed='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":101}]'
  write_gh_stateful_mock "$initial" '[]' "$changed" '[]'
  local output exit_code=0
  output=$(run_python monitor comments --pr 42 --interval 1 --timeout 2s 2>&1) || exit_code=$?
  cleanup_mock_dir
  if ! echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply should not be counted as new comment (output: $output)"
  fi
}

test_py_monitor_comments_output_format() {
  setup_mock_dir
  write_git_mock
  local changed='[{"id":101,"in_reply_to_id":null}]'
  write_gh_stateful_mock '[]' '[]' "$changed" '[]'
  local output
  output=$(run_python monitor comments --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
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

test_py_monitor_comments_check_flag_rejected() {
  assert_stderr_contains "--check rejected for monitor comments" \
    "unknown option: --check (only valid with monitor status)" \
    run_python_no_mock monitor comments --check ci.yml
}

test_py_monitor_comments_explicit_pr() {
  setup_mock_dir
  write_git_mock
  local initial='[{"id":101,"in_reply_to_id":null}]'
  local changed='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  write_gh_stateful_mock "$initial" '[]' "$changed" '[]'
  local exit_code=0
  run_python monitor comments --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: explicit --pr 42 should succeed (exit: $exit_code)"
  fi
}

test_py_monitor_comments_auto_detect() {
  setup_mock_dir
  write_git_mock
  local initial='[{"id":101,"in_reply_to_id":null}]'
  local changed='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  write_gh_auto_detect_mock "$initial" '[]' "$changed" '[]'
  local output
  output=$(run_python monitor comments --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect PR should work (output: $output)"
  fi
}

test_py_monitor_comments_no_pr_exits_nonzero() {
  setup_mock_dir
  write_git_mock
  write_gh_no_pr_mock
  local exit_code=0
  run_python monitor comments --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR should exit non-zero"
  fi
}

test_py_monitor_comments_no_pr_stderr_message() {
  setup_mock_dir
  write_git_mock
  write_gh_no_pr_mock
  local output
  output=$(run_python monitor comments --interval 1 2>&1) || true
  cleanup_mock_dir
  if echo "$output" | grep -qF "no open PR found"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR should mention 'no open PR found' (output: $output)"
  fi
}

test_py_monitor_comments_api_failure_exits_nonzero() {
  setup_mock_dir
  write_git_mock
  local initial='[{"id":101,"in_reply_to_id":null}]'
  write_gh_api_failure_mock "$initial" '[]'
  local exit_code=0
  run_python monitor comments --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: API failure should exit non-zero"
  fi
}

test_py_monitor_comments_help_exits_zero() {
  assert_exit 0 "monitor comments --help exits 0" run_python_no_mock monitor comments --help
  assert_exit 0 "monitor comments -h exits 0" run_python_no_mock monitor comments -h
}

test_py_monitor_comments_missing_pr_value_exits_nonzero() {
  assert_stderr_contains "comments --pr without value gives clear message" "missing value for --pr" run_python_no_mock monitor comments --pr
}

test_py_monitor_comments_missing_interval_value_exits_nonzero() {
  assert_stderr_contains "comments --interval without value gives clear message" "missing value for --interval" run_python_no_mock monitor comments --interval
}

test_py_monitor_comments_invalid_interval_exits_nonzero() {
  assert_stderr_contains "comments --interval abc gives clear message" "invalid --interval value: abc" run_python_no_mock monitor comments --interval abc
}

test_py_monitor_comments_zero_interval_exits_nonzero() {
  assert_stderr_contains "comments --interval 0 gives clear message" "invalid --interval value: 0" run_python_no_mock monitor comments --interval 0
}

test_py_monitor_comments_negative_interval_exits_nonzero() {
  assert_stderr_contains "comments --interval -1 gives clear message" "invalid --interval value: -1" run_python_no_mock monitor comments --interval -1
}

test_py_monitor_comments_missing_timeout_value_exits_nonzero() {
  assert_stderr_contains "comments --timeout without value gives clear message" "missing value for --timeout" run_python_no_mock monitor comments --timeout
}

test_py_monitor_comments_invalid_timeout_exits_nonzero() {
  assert_stderr_contains "comments --timeout abc gives clear message" "invalid duration" run_python_no_mock monitor comments --timeout abc
}

test_py_monitor_comments_timeout_exits_two() {
  setup_mock_dir
  write_git_mock
  local reviews='[{"id":101,"in_reply_to_id":null}]'
  write_gh_no_change_mock "$reviews" '[]'
  local exit_code=0
  run_python monitor comments --pr 42 --interval 1 --timeout 2s >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: timeout should exit 2 (got $exit_code)"
  fi
}

test_py_monitor_comments_timeout_stderr_message() {
  setup_mock_dir
  write_git_mock
  local reviews='[{"id":101,"in_reply_to_id":null}]'
  write_gh_no_change_mock "$reviews" '[]'
  local stderr_output
  stderr_output=$(run_python monitor comments --pr 42 --interval 1 --timeout 2s 2>&1 >/dev/null) || true
  cleanup_mock_dir
  if echo "$stderr_output" | grep -qF "monitor timed out after 2s"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: timeout stderr should contain 'monitor timed out after 2s' (got: $stderr_output)"
  fi
}

test_py_monitor_comments_timeout_minutes() {
  setup_mock_dir
  write_git_mock
  local initial='[{"id":101,"in_reply_to_id":null}]'
  local changed='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  write_gh_stateful_mock "$initial" '[]' "$changed" '[]'
  local exit_code=0
  run_python monitor comments --pr 42 --interval 1 --timeout 5m >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --timeout 5m should be accepted (got exit $exit_code)"
  fi
}

test_py_monitor_comments_timeout_hours() {
  setup_mock_dir
  write_git_mock
  local initial='[{"id":101,"in_reply_to_id":null}]'
  local changed='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  write_gh_stateful_mock "$initial" '[]' "$changed" '[]'
  local exit_code=0
  run_python monitor comments --pr 42 --interval 1 --timeout 1h >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --timeout 1h should be accepted (got exit $exit_code)"
  fi
}

test_py_monitor_comments_no_timeout_preserves_behavior() {
  setup_mock_dir
  write_git_mock
  local initial='[{"id":101,"in_reply_to_id":null}]'
  local changed='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  write_gh_stateful_mock "$initial" '[]' "$changed" '[]'
  local exit_code=0
  run_python monitor comments --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no timeout should detect change and exit 0 (got exit $exit_code)"
  fi
}

test_py_monitor_comments_help_shows_options() {
  local output
  output=$(run_python_no_mock monitor comments --help 2>&1)
  if echo "$output" | grep -qF -- "--pr" \
    && echo "$output" | grep -qF -- "--interval" \
    && echo "$output" | grep -qF -- "--timeout"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor comments --help should list --pr, --interval, --timeout (output: $output)"
  fi
}

test_py_monitor_comments_unknown_option_exits_nonzero() {
  assert_exit 1 "monitor comments unknown option exits 1" run_python_no_mock monitor comments --bogus
}

test_names+=(
  test_py_monitor_comments_new_review_comment
  test_py_monitor_comments_new_issue_comment
  test_py_monitor_comments_multiple_new_comments
  test_py_monitor_comments_existing_not_reported
  test_py_monitor_comments_reply_not_counted
  test_py_monitor_comments_output_format
  test_py_monitor_comments_check_flag_rejected
  test_py_monitor_comments_explicit_pr
  test_py_monitor_comments_auto_detect
  test_py_monitor_comments_no_pr_exits_nonzero
  test_py_monitor_comments_no_pr_stderr_message
  test_py_monitor_comments_api_failure_exits_nonzero
  test_py_monitor_comments_help_exits_zero
  test_py_monitor_comments_missing_pr_value_exits_nonzero
  test_py_monitor_comments_missing_interval_value_exits_nonzero
  test_py_monitor_comments_invalid_interval_exits_nonzero
  test_py_monitor_comments_zero_interval_exits_nonzero
  test_py_monitor_comments_negative_interval_exits_nonzero
  test_py_monitor_comments_missing_timeout_value_exits_nonzero
  test_py_monitor_comments_invalid_timeout_exits_nonzero
  test_py_monitor_comments_timeout_exits_two
  test_py_monitor_comments_timeout_stderr_message
  test_py_monitor_comments_timeout_minutes
  test_py_monitor_comments_timeout_hours
  test_py_monitor_comments_no_timeout_preserves_behavior
  test_py_monitor_comments_help_shows_options
  test_py_monitor_comments_unknown_option_exits_nonzero
)

# --- Run tests (only when executed directly, not sourced) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail

  _summary_on_exit() {
    local rc=$?
    if [ "$rc" -ne 0 ] || [ "${fail:-0}" -gt 0 ]; then
      echo "FAILED: exit ${rc}, ${fail:-0} test(s) failed, ${pass:-0} passed" >&2
    fi
    exit "$rc"
  }
  trap _summary_on_exit EXIT

  echo "--- test_python_monitor_comments.sh"
  for t in "${test_names[@]}"; do
    "$t"
  done

  echo ""
  echo "$pass passed, $fail failed" >&2
  [ "$fail" -eq 0 ]
fi
