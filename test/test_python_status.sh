#!/usr/bin/env bash

# Python status command tests using mock executables via GH_PR_CONTEXT_GH/GIT env vars.

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

test_py_status_completed_check() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  local output
  output=$(run_python status --pr 42 2>&1)
  cleanup_mock_dir
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

test_py_status_in_progress_omits_conclusion() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":1,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null}]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  local output
  output=$(run_python status --pr 42 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "status: in_progress" \
    && ! echo "$output" | grep -qF "conclusion:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: in_progress check should omit conclusion (output: $output)"
  fi
}

test_py_status_sorted_by_name() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":2,"check_runs":[{"name":"Zebra","status":"completed","conclusion":"success"},{"name":"Alpha","status":"completed","conclusion":"success"}]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  local output
  output=$(run_python status --pr 42 2>&1)
  cleanup_mock_dir
  local first_name
  first_name=$(echo "$output" | grep -m1 "name:" | sed 's/name: //')
  if [ "$first_name" = "Alpha" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected Alpha first, got: $first_name (output: $output)"
  fi
}

test_py_status_empty_checks() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":0,"check_runs":[]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  local output
  output=$(run_python status --pr 42 2>&1)
  cleanup_mock_dir
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: empty check_runs should produce no output (got: $output)"
  fi
}

test_py_status_multiple_conclusions() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":3,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"Test","status":"completed","conclusion":"failure"},{"name":"Deploy","status":"completed","conclusion":"cancelled"}]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  local output
  output=$(run_python status --pr 42 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "conclusion: success" \
    && echo "$output" | grep -qF "conclusion: failure" \
    && echo "$output" | grep -qF "conclusion: cancelled"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: mixed conclusions not all present (output: $output)"
  fi
}

test_py_status_sha_lookup_failure() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":0,"check_runs":[]}'
  write_gh_mock "
    *\"pulls/42\"*) exit 1 ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  local output
  output=$(run_python status --pr 42 2>&1) || true
  cleanup_mock_dir
  if echo "$output" | grep -qF "failed to resolve head SHA"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SHA lookup failure should mention 'failed to resolve head SHA' (output: $output)"
  fi
}

test_py_status_exits_zero() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  assert_exit 0 "status exits 0 on success" run_python status --pr 42
  cleanup_mock_dir
}

test_py_status_help_exits_zero() {
  setup_mock_dir
  write_git_mock
  write_gh_mock '*) exit 1 ;;'
  assert_exit 0 "status --help exits 0" run_python status --help
  assert_exit 0 "status -h exits 0" run_python status -h
  cleanup_mock_dir
}

test_py_status_unknown_option_exits_nonzero() {
  setup_mock_dir
  write_git_mock
  local check_runs='{"total_count":0,"check_runs":[]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) echo '$check_runs' ;;"
  local exit_code=0
  run_python status --pr 42 --bogus >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: unknown option should exit non-zero"
  fi
}

test_py_status_missing_pr_value() {
  assert_stderr_contains "status --pr without value gives clear message" "missing value for --pr" $python_cmd "$python_script" status --pr
}

test_py_status_paginated_merges_all_checks() {
  setup_mock_dir
  write_git_mock
  local page1='{"total_count":3,"check_runs":[{"name":"Zebra","status":"completed","conclusion":"success"}]}'
  local page2='{"total_count":3,"check_runs":[{"name":"Alpha","status":"completed","conclusion":"failure"}]}'
  write_gh_mock "
    *\"pulls/42\"*) echo '$HEAD_SHA' ;;
    *\"check-runs\"*) printf '%s\n' '$page1' '$page2' ;;"
  local output
  output=$(run_python status --pr 42 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "name: Alpha" \
    && echo "$output" | grep -qF "name: Zebra"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: paginated response should merge all pages (output: $output)"
  fi
}

# --- Run tests ---
test_names=(
  test_py_status_completed_check
  test_py_status_in_progress_omits_conclusion
  test_py_status_sorted_by_name
  test_py_status_empty_checks
  test_py_status_multiple_conclusions
  test_py_status_sha_lookup_failure
  test_py_status_exits_zero
  test_py_status_help_exits_zero
  test_py_status_unknown_option_exits_nonzero
  test_py_status_missing_pr_value
  test_py_status_paginated_merges_all_checks
)

echo "--- test_python_status.sh"
for t in "${test_names[@]}"; do
  "$t"
done

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
