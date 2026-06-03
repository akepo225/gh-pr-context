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

write_gh_stateful_mock() {
  local initial_check="$1"
  local changed_check="$2"
  local sha_first="${3:-$HEAD_SHA}"
  local sha_subsequent="${4:-$HEAD_SHA}"
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
  *"pulls/42"*"--jq"*)
    if [ "\$call_num" -le 1 ]; then
      echo '$sha_first'
    else
      echo '$sha_subsequent'
    fi
    ;;
  *"check-runs"*)
    if [ "\$call_num" -le 2 ]; then
      printf '%s' '$initial_check'
    else
      printf '%s' '$changed_check'
    fi
    ;;
  *) exit 1 ;;
esac
GHEOF
  chmod +x "$_MOCK_DIR/gh"
}

write_gh_auto_detect_mock() {
  local initial_check="$1"
  local changed_check="$2"
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
  *"pulls?head=acme:feature-branch"*"--jq"*) echo '42' ;;
  *"pulls/42"*"--jq"*)
    echo '$HEAD_SHA'
    ;;
  *"check-runs"*)
    if [ "\$call_num" -le 3 ]; then
      printf '%s' '$initial_check'
    else
      printf '%s' '$changed_check'
    fi
    ;;
  *) exit 1 ;;
esac
GHEOF
  chmod +x "$_MOCK_DIR/gh"
}

write_gh_no_pr_mock() {
  cat > "$_MOCK_DIR/gh" << 'GH_EOF'
#!/usr/bin/env bash
case "$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false' ;;
  *"pulls?head=acme:feature-branch"*"--jq"*) echo '' ;;
  *) exit 1 ;;
esac
GH_EOF
  chmod +x "$_MOCK_DIR/gh"
}

write_gh_api_failure_mock() {
  local initial_check="$1"
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
  *"pulls/42"*"--jq"*) echo '$HEAD_SHA' ;;
  *"check-runs"*)
    if [ "\$call_num" -le 2 ]; then
      printf '%s' '$initial_check'
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
  cat > "$_MOCK_DIR/gh" << GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
  *"pulls/42"*"--jq"*) echo '$HEAD_SHA' ;;
  *"check-runs"*)
    echo '{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
    ;;
  *) exit 1 ;;
esac
GHEOF
  chmod +x "$_MOCK_DIR/gh"
}

write_gh_static_mock() {
  local check_data="$1"
  cat > "$_MOCK_DIR/gh" << GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
  *"pulls/42"*"--jq"*) echo '$HEAD_SHA' ;;
  *"check-runs"*)
    printf '%s' '$check_data'
    ;;
  *) exit 1 ;;
esac
GHEOF
  chmod +x "$_MOCK_DIR/gh"
}

write_gh_no_change_mock() {
  cat > "$_MOCK_DIR/gh" << GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
  *"pulls/42"*"--jq"*) echo '$HEAD_SHA' ;;
  *"check-runs"*)
    echo '{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
    ;;
  *) exit 1 ;;
esac
GHEOF
  chmod +x "$_MOCK_DIR/gh"
}

write_gh_static_mock() {
  local check_data="$1"
  cat > "$_MOCK_DIR/gh" << GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"repos/acme/widgets"*"--jq"*".fork"*) echo 'false'; exit 0 ;;
  *"pulls/42"*"--jq"*) echo '$HEAD_SHA' ;;
  *"check-runs"*)
    printf '%s' '$check_data'
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

test_py_monitor_status_single_check_change() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  write_gh_stateful_mock "$initial" "$changed"
  local output
  output=$(run_python monitor status --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
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

test_py_monitor_status_multiple_changes_sorted() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":2,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null},{"name":"Test","status":"queued","conclusion":null}]}'
  local changed='{"total_count":2,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"Test","status":"completed","conclusion":"failure"}]}'
  write_gh_stateful_mock "$initial" "$changed"
  local output
  output=$(run_python monitor status --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
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

test_py_monitor_status_new_check_appearing() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  local changed='{"total_count":2,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"},{"name":"Lint","status":"in_progress","conclusion":null}]}'
  write_gh_stateful_mock "$initial" "$changed"
  local output
  output=$(run_python monitor status --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "check: Lint" \
    && echo "$output" | grep -qF "from: absent" \
    && echo "$output" | grep -qF "to: in_progress"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: new check appearing (output: $output)"
  fi
}

test_py_monitor_status_check_disappearing() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":2,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"},{"name":"Lint","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  write_gh_stateful_mock "$initial" "$changed"
  local output
  output=$(run_python monitor status --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "check: Lint" \
    && echo "$output" | grep -qF "from: in_progress" \
    && echo "$output" | grep -qF "to: absent"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: check disappearing (output: $output)"
  fi
}

test_py_monitor_status_sha_change() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  write_gh_stateful_mock "$initial" "$initial" "$HEAD_SHA" "$NEW_SHA"
  local output
  output=$(run_python monitor status --pr 42 --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF -- "--- change" \
    && echo "$output" | grep -qF "type: new-commit" \
    && echo "$output" | grep -qF "sha: $NEW_SHA"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SHA change detection (output: $output)"
  fi
}

test_py_monitor_status_explicit_pr() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  write_gh_stateful_mock "$initial" "$changed"
  local exit_code=0
  run_python monitor status --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: explicit --pr 42 should succeed (exit: $exit_code)"
  fi
}

test_py_monitor_status_auto_detect() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  write_gh_auto_detect_mock "$initial" "$changed"
  local output
  output=$(run_python monitor status --interval 1 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "check: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect PR should work (output: $output)"
  fi
}

test_py_monitor_status_no_pr_exits_nonzero() {
  setup_mock_dir
  write_git_mock
  write_gh_no_pr_mock
  local exit_code=0
  run_python monitor status --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR should exit non-zero"
  fi
}

test_py_monitor_status_no_pr_stderr_message() {
  setup_mock_dir
  write_git_mock
  write_gh_no_pr_mock
  local output
  output=$(run_python monitor status --interval 1 2>&1) || true
  cleanup_mock_dir
  if echo "$output" | grep -qF "no open PR found"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR should mention 'no open PR found' (output: $output)"
  fi
}

test_py_monitor_status_api_failure_exits_nonzero() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  write_gh_api_failure_mock "$initial"
  local exit_code=0
  run_python monitor status --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: API failure should exit non-zero"
  fi
}

test_py_monitor_no_subcommand_exits_nonzero() {
  assert_exit 1 "monitor with no subcommand exits 1" run_python_no_mock monitor
}

test_py_monitor_help_exits_zero() {
  assert_exit 0 "monitor --help exits 0" run_python_no_mock monitor --help
  assert_exit 0 "monitor -h exits 0" run_python_no_mock monitor -h
}

test_py_monitor_status_help_exits_zero() {
  assert_exit 0 "monitor status --help exits 0" run_python_no_mock monitor status --help
  assert_exit 0 "monitor status -h exits 0" run_python_no_mock monitor status -h
}

test_py_monitor_status_unknown_option_exits_nonzero() {
  assert_exit 1 "monitor status unknown option exits 1" run_python_no_mock monitor status --bogus
}

test_py_monitor_status_missing_pr_value_exits_nonzero() {
  assert_stderr_contains "status --pr without value gives clear message" "missing value for --pr" run_python_no_mock monitor status --pr
}

test_py_monitor_status_missing_interval_value_exits_nonzero() {
  assert_stderr_contains "status --interval without value gives clear message" "missing value for --interval" run_python_no_mock monitor status --interval
}

test_py_monitor_status_invalid_interval_exits_nonzero() {
  assert_stderr_contains "status --interval abc gives clear message" "invalid --interval value: abc" run_python_no_mock monitor status --interval abc
}

test_py_monitor_status_zero_interval_exits_nonzero() {
  assert_stderr_contains "status --interval 0 gives clear message" "invalid --interval value: 0" run_python_no_mock monitor status --interval 0
}

test_py_monitor_status_negative_interval_exits_nonzero() {
  assert_stderr_contains "status --interval -1 gives clear message" "invalid --interval value: -1" run_python_no_mock monitor status --interval -1
}

test_py_monitor_status_timeout_exits_two() {
  setup_mock_dir
  write_git_mock
  write_gh_no_change_mock
  local exit_code=0
  run_python monitor status --pr 42 --interval 1 --timeout 3s >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: timeout should exit 2 (got $exit_code)"
  fi
}

test_py_monitor_status_timeout_stderr_message() {
  setup_mock_dir
  write_git_mock
  write_gh_no_change_mock
  local stderr_output
  stderr_output=$(run_python monitor status --pr 42 --interval 1 --timeout 2s 2>&1 >/dev/null) || true
  cleanup_mock_dir
  if echo "$stderr_output" | grep -qF "monitor timed out after 2s"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: timeout stderr should contain 'monitor timed out after 2s' (got: $stderr_output)"
  fi
}

test_py_monitor_status_timeout_minutes() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  write_gh_stateful_mock "$initial" "$changed"
  local exit_code=0
  run_python monitor status --pr 42 --interval 1 --timeout 5m >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --timeout 5m should be accepted (got exit $exit_code)"
  fi
}

test_py_monitor_status_timeout_hours() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  write_gh_stateful_mock "$initial" "$changed"
  local exit_code=0
  run_python monitor status --pr 42 --interval 1 --timeout 1h >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --timeout 1h should be accepted (got exit $exit_code)"
  fi
}

test_py_monitor_status_no_timeout_preserves_behavior() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  write_gh_stateful_mock "$initial" "$changed"
  local exit_code=0
  run_python monitor status --pr 42 --interval 1 >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no timeout should detect change and exit 0 (got exit $exit_code)"
  fi
}

test_py_monitor_status_missing_timeout_value_exits_nonzero() {
  assert_stderr_contains "status --timeout without value gives clear message" "missing value for --timeout" run_python_no_mock monitor status --timeout
}

test_py_monitor_status_invalid_timeout_exits_nonzero() {
  assert_stderr_contains "status --timeout abc gives clear message" "invalid duration" run_python_no_mock monitor status --timeout abc
}

test_py_monitor_status_help_shows_timeout() {
  local output
  output=$(run_python_no_mock monitor status --help 2>&1)
  if echo "$output" | grep -qF -- "--timeout"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor status --help should list --timeout (output: $output)"
  fi
}

test_py_monitor_status_check_missing_value_flag() {
  assert_stderr_contains "--check followed by flag gives clear message" "missing value for --check" run_python_no_mock monitor status --check --timeout 30s
}

test_py_monitor_status_check_missing_value_last() {
  assert_stderr_contains "--check as last arg gives clear message" "missing value for --check" run_python_no_mock monitor status --check
}

test_py_monitor_status_check_empty_value_rejected() {
  assert_stderr_contains "--check empty gives clear message" "missing value for --check" run_python_no_mock monitor status --check ""
}

test_py_monitor_status_check_filters_to_named_check() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":2,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null},{"name":"CI","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":2,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"CI","status":"completed","conclusion":"failure"}]}'
  write_gh_stateful_mock "$initial" "$changed"
  local output
  output=$(run_python monitor status --pr 42 --interval 1 --check CI 2>&1)
  cleanup_mock_dir
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

test_py_monitor_status_check_ignores_other_changes() {
  setup_mock_dir
  write_git_mock
  local check_data='{"total_count":2,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"CI","status":"in_progress","conclusion":null}]}'
  write_gh_static_mock "$check_data"
  local exit_code=0
  run_python monitor status --pr 42 --interval 1 --check CI --timeout 2s >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check CI should not detect Build change, should timeout exit 2 (got $exit_code)"
  fi
}

test_py_monitor_status_check_appears_after_delay() {
  setup_mock_dir
  write_git_mock
  local initial='{"total_count":1,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null}]}'
  local changed='{"total_count":2,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null},{"name":"CI","status":"in_progress","conclusion":null}]}'
  write_gh_stateful_mock "$initial" "$changed"
  local output
  output=$(run_python monitor status --pr 42 --interval 1 --check CI 2>&1)
  cleanup_mock_dir
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

test_py_monitor_status_check_timeout_missing_check() {
  setup_mock_dir
  write_git_mock
  local check_data='{"total_count":1,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null}]}'
  write_gh_static_mock "$check_data"
  local exit_code=0
  run_python monitor status --pr 42 --interval 1 --check CI --timeout 2s >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check with missing check and --timeout should exit 2 (got $exit_code)"
  fi
}

test_py_monitor_status_check_case_sensitive() {
  setup_mock_dir
  write_git_mock
  local check_data='{"total_count":1,"check_runs":[{"name":"ci","status":"in_progress","conclusion":null}]}'
  write_gh_static_mock "$check_data"
  local exit_code=0
  run_python monitor status --pr 42 --interval 1 --check CI --timeout 2s >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --check CI should not match ci, should timeout exit 2 (got $exit_code)"
  fi
}

test_py_monitor_status_help_shows_check() {
  local output
  output=$(run_python_no_mock monitor status --help 2>&1)
  if echo "$output" | grep -qF -- "--check"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: monitor status --help should list --check (output: $output)"
  fi
}

test_py_usage_lists_monitor() {
  local output
  output=$(run_python_no_mock --help 2>&1)
  if echo "$output" | grep -qF "monitor"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: usage should list monitor command"
  fi
}

test_names+=(
  test_py_monitor_status_single_check_change
  test_py_monitor_status_multiple_changes_sorted
  test_py_monitor_status_new_check_appearing
  test_py_monitor_status_check_disappearing
  test_py_monitor_status_sha_change
  test_py_monitor_status_explicit_pr
  test_py_monitor_status_auto_detect
  test_py_monitor_status_no_pr_exits_nonzero
  test_py_monitor_status_no_pr_stderr_message
  test_py_monitor_status_api_failure_exits_nonzero
  test_py_monitor_no_subcommand_exits_nonzero
  test_py_monitor_help_exits_zero
  test_py_monitor_status_help_exits_zero
  test_py_monitor_status_unknown_option_exits_nonzero
  test_py_monitor_status_missing_pr_value_exits_nonzero
  test_py_monitor_status_missing_interval_value_exits_nonzero
  test_py_monitor_status_invalid_interval_exits_nonzero
  test_py_monitor_status_zero_interval_exits_nonzero
  test_py_monitor_status_negative_interval_exits_nonzero
  test_py_monitor_status_timeout_exits_two
  test_py_monitor_status_timeout_stderr_message
  test_py_monitor_status_timeout_minutes
  test_py_monitor_status_timeout_hours
  test_py_monitor_status_no_timeout_preserves_behavior
  test_py_monitor_status_missing_timeout_value_exits_nonzero
  test_py_monitor_status_invalid_timeout_exits_nonzero
  test_py_monitor_status_help_shows_timeout
  test_py_monitor_status_check_missing_value_flag
  test_py_monitor_status_check_missing_value_last
  test_py_monitor_status_check_empty_value_rejected
  test_py_monitor_status_check_filters_to_named_check
  test_py_monitor_status_check_ignores_other_changes
  test_py_monitor_status_check_appears_after_delay
  test_py_monitor_status_check_timeout_missing_check
  test_py_monitor_status_check_case_sensitive
  test_py_monitor_status_help_shows_check
  test_py_usage_lists_monitor
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

  echo "--- test_python_monitor_status.sh"
  for t in "${test_names[@]}"; do
    "$t"
  done

  echo ""
  echo "$pass passed, $fail failed" >&2
  [ "$fail" -eq 0 ]
fi
