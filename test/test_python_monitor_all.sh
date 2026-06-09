#!/usr/bin/env bash

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
python_script="$repo_root/gh-pr-context.py"
if command -v py >/dev/null 2>&1; then
  python_cmd="py -3"
else
  python_cmd="python3"
fi

HEAD_SHA="abc123def456abc123def456abc123def456abc1"
NEW_SHA="def456abc123def456abc123def456abc123def4"

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

write_gh_stateful_mock_all() {
  local initial_checks="$1"
  local changed_checks="$2"
  local initial_reviews="$3"
  local initial_issues="$4"
  local changed_reviews="$5"
  local changed_issues="$6"
  local sha_threshold="${7:-2}"
  local checks_threshold="${8:-2}"
  local review_threshold="${9:-3}"
  local issue_threshold="${10:-4}"
  echo 0 > "$_MOCK_DIR/counter_sha"
  echo 0 > "$_MOCK_DIR/counter_checks"
  echo 0 > "$_MOCK_DIR/counter_reviews"
  echo 0 > "$_MOCK_DIR/counter_issues"
  cat > "$_MOCK_DIR/gh" << GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
esac
case "\$*" in
  *"pulls/42"*"--jq"*)
    n=\$(cat "$_MOCK_DIR/counter_sha")
    n=\$((n + 1))
    echo "\$n" > "$_MOCK_DIR/counter_sha"
    if [ "\$n" -le $sha_threshold ]; then
      echo '$HEAD_SHA'
    else
      echo '$NEW_SHA'
    fi
    ;;
  *"check-runs"*)
    n=\$(cat "$_MOCK_DIR/counter_checks")
    n=\$((n + 1))
    echo "\$n" > "$_MOCK_DIR/counter_checks"
    if [ "\$n" -le $checks_threshold ]; then
      printf '%s' '$initial_checks'
    else
      printf '%s' '$changed_checks'
    fi
    ;;
  *"repos/acme/widgets/pulls/42/comments"*)
    n=\$(cat "$_MOCK_DIR/counter_reviews")
    n=\$((n + 1))
    echo "\$n" > "$_MOCK_DIR/counter_reviews"
    if [ "\$n" -le $review_threshold ]; then
      printf '%s' '$initial_reviews'
    else
      printf '%s' '$changed_reviews'
    fi
    ;;
  *"repos/acme/widgets/issues/42/comments"*)
    n=\$(cat "$_MOCK_DIR/counter_issues")
    n=\$((n + 1))
    echo "\$n" > "$_MOCK_DIR/counter_issues"
    if [ "\$n" -le $issue_threshold ]; then
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

write_gh_no_change_mock_all() {
  local initial_checks="$1"
  local initial_reviews="$2"
  local initial_issues="$3"
  cat > "$_MOCK_DIR/gh" << GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
  *"pulls/42"*"--jq"*) echo '$HEAD_SHA' ;;
  *"check-runs"*)
    printf '%s' '$initial_checks'
    ;;
  *"repos/acme/widgets/pulls/42/comments"*)
    printf '%s' '$initial_reviews'
    ;;
  *"repos/acme/widgets/issues/42/comments"*)
    printf '%s' '$initial_issues'
    ;;
  *) echo "UNMATCHED: \$*" >&2; exit 1 ;;
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

# --- Functional tests ---

test_py_monitor_all_status_only() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  write_gh_stateful_mock_all "$initial" "$changed" '[]' '[]' '[]' '[]' 999
  local output
  output=$(run_python monitor --all --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "type: status" \
    && echo "$output" | grep -qF "check: CI" \
    && echo "$output" | grep -qF "from: in_progress" \
    && echo "$output" | grep -qF "to: completed" \
    && echo "$output" | grep -qF "conclusion: success" \
    && ! echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: status only (output: $output)"
  fi
}

test_py_monitor_all_comments_only() {
  setup_mock_dir
  write_git_mock
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  write_gh_stateful_mock_all '{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}' \
    '{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}' \
    "$initial_reviews" '[]' "$changed_reviews" '[]' 999
  local output
  output=$(run_python monitor --all --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "type: new-comment" \
    && echo "$output" | grep -qF "count: 1" \
    && ! echo "$output" | grep -qF "type: status"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: comments only (output: $output)"
  fi
}

test_py_monitor_all_mixed_changes_status_first() {
  setup_mock_dir
  write_git_mock
  local initial_checks='{"total_count":2,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null},{"name":"Test","status":"queued","conclusion":null}]}'
  local changed_checks='{"total_count":2,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"Test","status":"completed","conclusion":"failure"}]}'
  local initial_reviews='[{"id":101,"in_reply_to_id":null}]'
  local changed_reviews='[{"id":101,"in_reply_to_id":null},{"id":102,"in_reply_to_id":null}]'
  local initial_issues='[{"id":201}]'
  local changed_issues='[{"id":201},{"id":202}]'
  write_gh_stateful_mock_all "$initial_checks" "$changed_checks" \
    "$initial_reviews" "$initial_issues" "$changed_reviews" "$changed_issues" 999 1 1 1
  local output
  output=$(run_python monitor --all --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
  local first_type last_type
  first_type=$(echo "$output" | grep "type:" | head -1 | tr -d '\r')
  last_type=$(echo "$output" | grep "type:" | tail -1 | tr -d '\r')
  local first_check second_check
  first_check=$(echo "$output" | grep -m1 "check:" | sed 's/check: //' | tr -d '\r')
  second_check=$(echo "$output" | grep "check:" | sed 's/check: //' | tail -1 | tr -d '\r')
  if [ "$first_type" = "type: status" ] \
    && [ "$last_type" = "type: new-comment" ] \
    && [ "$first_check" = "Build" ] \
    && [ "$second_check" = "Test" ] \
    && echo "$output" | grep -qF "count: 2"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: mixed changes status first (first_type=$first_type, last_type=$last_type, first_check=$first_check, second_check=$second_check, output: $output)"
  fi
}

test_py_monitor_all_new_commit() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  write_gh_stateful_mock_all "$initial" "$initial" '[]' '[]' '[]' '[]' 1
  local output
  output=$(run_python monitor --all --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "type: new-commit" \
    && echo "$output" | grep -qF "sha: $NEW_SHA" \
    && ! echo "$output" | grep -qF "type: status" \
    && ! echo "$output" | grep -qF "type: new-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: new commit (output: $output)"
  fi
}

# --- CLI validation tests ---

test_py_monitor_all_help() {
  assert_exit 0 "monitor --all --help exits 0" run_python_no_mock monitor --all --help
  assert_exit 0 "monitor --all -h exits 0" run_python_no_mock monitor --all -h
}

test_py_monitor_all_reject_check_flag() {
  assert_stderr_contains "--check rejected for monitor --all" \
    "unknown option: --check (only valid with monitor status)" \
    run_python_no_mock monitor --all --check CI
}

test_py_monitor_all_missing_interval_value() {
  assert_stderr_contains "--all --interval without value gives clear message" \
    "missing value for --interval" \
    run_python_no_mock monitor --all --interval
}

test_py_monitor_all_invalid_interval() {
  assert_stderr_contains "--all --interval abc gives clear message" \
    "invalid --interval value: abc" \
    run_python_no_mock monitor --all --interval abc
  assert_stderr_contains "--all --interval 0 gives clear message" \
    "invalid --interval value: 0" \
    run_python_no_mock monitor --all --interval 0
  assert_stderr_contains "--all --interval -1 gives clear message" \
    "invalid --interval value: -1" \
    run_python_no_mock monitor --all --interval -1
}

test_py_monitor_all_unknown_option() {
  assert_exit 1 "monitor --all unknown option exits 1" run_python_no_mock monitor --all --bogus
}

test_py_monitor_all_missing_pr_value() {
  assert_stderr_contains "--all --pr without value gives clear message" \
    "missing value for --pr" \
    run_python_no_mock monitor --all --pr
}

test_py_monitor_all_missing_timeout_value() {
  assert_stderr_contains "--all --timeout without value gives clear message" \
    "missing value for --timeout" \
    run_python_no_mock monitor --all --timeout
}

test_py_monitor_all_invalid_timeout() {
  assert_stderr_contains "--all --timeout abc gives clear message" \
    "invalid duration" \
    run_python_no_mock monitor --all --timeout abc
}

test_py_monitor_all_timeout_exits_two() {
  setup_mock_dir
  write_git_mock
  local checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local reviews='[{"id":101,"in_reply_to_id":null}]'
  local issues='[{"id":201}]'
  write_gh_no_change_mock_all "$checks" "$reviews" "$issues"
  local exit_code=0
  run_python monitor --all --pr 42 --interval 1 --timeout 2s >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: timeout should exit 2 (got $exit_code)"
  fi
}

test_py_monitor_all_timeout_stderr_message() {
  setup_mock_dir
  write_git_mock
  local checks='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local reviews='[{"id":101,"in_reply_to_id":null}]'
  local issues='[{"id":201}]'
  write_gh_no_change_mock_all "$checks" "$reviews" "$issues"
  local stderr_output
  stderr_output=$(run_python monitor --all --pr 42 --interval 1 --timeout 2s 2>&1 >/dev/null) || true
  cleanup_mock_dir
  if echo "$stderr_output" | grep -qF "monitor timed out after 2s"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: timeout stderr should contain 'monitor timed out after 2s' (got: $stderr_output)"
  fi
}

test_py_monitor_all_help_shows_options() {
  local output
  output=$(run_python_no_mock monitor --all --help 2>&1)
  if echo "$output" | grep -qF -- "--pr" \
    && echo "$output" | grep -qF -- "--interval" \
    && echo "$output" | grep -qF -- "--timeout"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --all --help should list --pr, --interval, --timeout (output: $output)"
  fi
}

test_py_monitor_help_shows_all() {
  local output
  output=$(run_python_no_mock monitor --help 2>&1)
  if echo "$output" | grep -qF -- "--all"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor --help should list --all (output: $output)"
  fi
}

test_names+=(
  test_py_monitor_all_status_only
  test_py_monitor_all_comments_only
  test_py_monitor_all_mixed_changes_status_first
  test_py_monitor_all_new_commit
  test_py_monitor_all_help
  test_py_monitor_all_reject_check_flag
  test_py_monitor_all_missing_interval_value
  test_py_monitor_all_invalid_interval
  test_py_monitor_all_unknown_option
  test_py_monitor_all_missing_pr_value
  test_py_monitor_all_missing_timeout_value
  test_py_monitor_all_invalid_timeout
  test_py_monitor_all_timeout_exits_two
  test_py_monitor_all_timeout_stderr_message
  test_py_monitor_all_help_shows_options
  test_py_monitor_help_shows_all
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

  echo "--- test_python_monitor_all.sh"
  for t in "${test_names[@]}"; do
    "$t"
  done

  echo ""
  echo "$pass passed, $fail failed" >&2
  [ "$fail" -eq 0 ]
fi
