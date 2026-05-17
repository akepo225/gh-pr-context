#!/usr/bin/env bash

# Python logs command tests using mock executables via GH_PR_CONTEXT_GH/GIT env vars.

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
python_script="$repo_root/gh-pr-context.py"
python_cmd="py -3"

HEAD_SHA="abc123def456abc123def456abc123def456abc1"

pass=0
fail=0

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
  _MOCK_DIR=$(TMPDIR="$TEMP" mktemp -d)
}

cleanup_mock_dir() {
  if [ -n "$_MOCK_DIR" ] && [ -d "$_MOCK_DIR" ]; then
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

# Write gh mock. $1 = body of case statement
write_gh_mock() {
  local body="$1"
  cat > "$_MOCK_DIR/gh" << GHSCRIPT
#!/usr/bin/env bash
case "\$*" in
  $body
  *) exit 1 ;;
esac
GHSCRIPT
  chmod +x "$_MOCK_DIR/gh"
}

run_python() {
  local git_bash='"C:/Program Files/Git/usr/bin/bash.exe"'
  local git_mock="$git_bash $(cygpath -m "$_MOCK_DIR/git")"
  local gh_mock="$git_bash $(cygpath -m "$_MOCK_DIR/gh")"
  GH_PR_CONTEXT_GIT="$git_mock" GH_PR_CONTEXT_GH="$gh_mock" \
    $python_cmd "$python_script" "$@"
}

# --- Tests ---

test_py_logs_failed_check_shows_log() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content="Running tests...\nTest failed: expected 200 got 500"
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;
    *\"jobs/111/logs\"*) printf '%s' '$log_content' ;;"
  local output
  output=$(run_python logs --pr 42 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF -- "--- log" \
    && echo "$output" | grep -qF "name: CI" \
    && echo "$output" | grep -qF "Running tests..." \
    && echo "$output" | grep -qF "Test failed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: failed check should show log block (output: $output)"
  fi
}

test_py_logs_all_passing_no_output() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":2,"check_runs":[{"id":111,"name":"Build","status":"completed","conclusion":"success"},{"id":222,"name":"Test","status":"completed","conclusion":"success"}]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  local output
  output=$(run_python logs --pr 42 2>&1)
  cleanup_mock_dir
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: all passing checks should produce no output (got: $output)"
  fi
}

test_py_logs_multiple_failures() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":2,"check_runs":[{"id":222,"name":"Test","status":"completed","conclusion":"failure"},{"id":111,"name":"Build","status":"completed","conclusion":"failure"}]}'
  echo "build error at line 5" > "$_MOCK_DIR/log_111.txt"
  echo "test assertion failed" > "$_MOCK_DIR/log_222.txt"
  local win_mock_dir
  win_mock_dir=$(cygpath -m "$_MOCK_DIR")
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;
    *\"jobs/111/logs\"*) cat '$win_mock_dir/log_111.txt' ;;
    *\"jobs/222/logs\"*) cat '$win_mock_dir/log_222.txt' ;;"
  local output
  output=$(run_python logs --pr 42 2>&1)
  cleanup_mock_dir
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

test_py_logs_truncation_at_500_lines() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  seq 1 600 > "$_MOCK_DIR/log_111.txt"
  local win_log_file
  win_log_file=$(cygpath -m "$_MOCK_DIR/log_111.txt")
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;
    *\"jobs/111/logs\"*) cat '$win_log_file' ;;"
  local output
  output=$(run_python logs --pr 42 2>&1)
  cleanup_mock_dir
  local content_lines
  content_lines=$(echo "$output" | grep -v -e "--- log" -e "name:" -e "truncated" | grep -c .)
  if [ "$content_lines" -le 500 ] && echo "$output" | grep -qF "[truncated:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected at most 500 content lines with truncation notice (content_lines: $content_lines, output: $output)"
  fi
}

test_py_logs_truncation_notice_format() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  seq 1 600 > "$_MOCK_DIR/log_111.txt"
  local win_log_file
  win_log_file=$(cygpath -m "$_MOCK_DIR/log_111.txt")
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;
    *\"jobs/111/logs\"*) cat '$win_log_file' ;;"
  local output
  output=$(run_python logs --pr 42 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "[truncated: 100 lines omitted]"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected '[truncated: 100 lines omitted]' (output: $output)"
  fi
}

test_py_logs_under_500_no_truncation() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  seq 1 10 > "$_MOCK_DIR/log_111.txt"
  local win_log_file
  win_log_file=$(cygpath -m "$_MOCK_DIR/log_111.txt")
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;
    *\"jobs/111/logs\"*) cat '$win_log_file' ;;"
  local output
  output=$(run_python logs --pr 42 2>&1)
  cleanup_mock_dir
  if ! echo "$output" | grep -q "truncated"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: under 500 lines should not show truncation notice (output: $output)"
  fi
}

test_py_logs_log_fetch_fails_shows_placeholder() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  local output
  output=$(run_python logs --pr 42 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF -- "--- log" \
    && echo "$output" | grep -qF "name: CI" \
    && echo "$output" | grep -qF "[log not available]"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: log fetch failure should show placeholder (output: $output)"
  fi
}

test_py_logs_sha_lookup_failure() {
  setup_mock_dir
  write_git_mock
  write_gh_mock '*) exit 1 ;;'
  local output
  output=$(run_python logs --pr 42 2>&1) || true
  cleanup_mock_dir
  if echo "$output" | grep -qF "failed to resolve head SHA"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SHA lookup failure should mention 'failed to resolve head SHA' (output: $output)"
  fi
}

test_py_logs_exits_zero() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  echo "error in CI" > "$_MOCK_DIR/log_111.txt"
  local win_log_file
  win_log_file=$(cygpath -m "$_MOCK_DIR/log_111.txt")
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;
    *\"jobs/111/logs\"*) cat '$win_log_file' ;;"
  assert_exit 0 "logs exits 0 on success" run_python logs --pr 42
  cleanup_mock_dir
}

test_py_logs_help_exits_zero() {
  setup_mock_dir
  write_git_mock
  write_gh_mock '*) exit 1 ;;'
  assert_exit 0 "logs --help exits 0" run_python logs --help
  assert_exit 0 "logs -h exits 0" run_python logs -h
  cleanup_mock_dir
}

test_py_logs_unknown_option_exits_nonzero() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":0,"check_runs":[]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  local exit_code=0
  run_python logs --pr 42 --bogus >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: unknown option should exit non-zero"
  fi
}

test_py_logs_missing_pr_value() {
  assert_stderr_contains "logs --pr without value gives clear message" "missing value for --pr" $python_cmd "$python_script" logs --pr
}

# --- Run tests ---
test_names=(
  test_py_logs_failed_check_shows_log
  test_py_logs_all_passing_no_output
  test_py_logs_multiple_failures
  test_py_logs_truncation_at_500_lines
  test_py_logs_truncation_notice_format
  test_py_logs_under_500_no_truncation
  test_py_logs_log_fetch_fails_shows_placeholder
  test_py_logs_sha_lookup_failure
  test_py_logs_exits_zero
  test_py_logs_help_exits_zero
  test_py_logs_unknown_option_exits_nonzero
  test_py_logs_missing_pr_value
)

echo "--- test_python_logs.sh"
for t in "${test_names[@]}"; do
  "$t"
done

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
