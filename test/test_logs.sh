#!/usr/bin/env bash

ORIGINAL_PATH="$HOME/bin:$PATH"

HEAD_SHA="abc123def456abc123def456abc123def456abc1"

setup_mocks() {
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/git" << 'GIT_EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
  "branch --show-current") echo "feature-branch" ;;
  "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
  *) exit 1 ;;
esac
GIT_EOF
  chmod +x "$mock_dir/git"
}

setup_mocks_logs() {
  local check_runs="$1"
  local log_content="$2"

  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$HEAD_SHA" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *"check-runs"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$check_runs" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *"logs"*)\n' >> "$mock_dir/gh"
  printf "    printf '%%s' '%s'\n" "$log_content" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_logs_multi() {
  local check_runs="$1"
  shift

  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$HEAD_SHA" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *"check-runs"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$check_runs" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"

  local idx=0
  while [ $# -gt 0 ]; do
    local job_id="$1"
    local log_content="$2"
    shift 2
    printf '  *"jobs/%s/logs"*)\n' "$job_id" >> "$mock_dir/gh"
    printf "    printf '%%s' '%s'\n" "$log_content" >> "$mock_dir/gh"
    printf '    ;;\n' >> "$mock_dir/gh"
    idx=$((idx + 1))
  done

  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_logs_auto() {
  local check_runs="$1"
  local log_content="$2"

  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls?head=acme:feature-branch"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" '42' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *"pulls/42"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$HEAD_SHA" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *"check-runs"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$check_runs" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *"logs"*)\n' >> "$mock_dir/gh"
  printf "    printf '%%s' '%s'\n" "$log_content" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_logs_no_pr() {
  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls?head=acme:feature-branch"*)\n' >> "$mock_dir/gh"
  printf '    echo ""\n' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_logs_sha_fails() {
  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls?head=acme:feature-branch"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" '42' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *"pulls/42"*)\n' >> "$mock_dir/gh"
  printf '    exit 1\n' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_logs_no_log() {
  local check_runs="$1"

  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$HEAD_SHA" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *"check-runs"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$check_runs" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *"logs"*)\n' >> "$mock_dir/gh"
  printf '    exit 1\n' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

run_script() {
  PATH="$mock_dir:$ORIGINAL_PATH" bash "$script" "$@"
}

cleanup_mocks() {
  rm -rf "$mock_dir"
}

test_names+=(
  test_logs_failed_check_shows_log
  test_logs_all_passing_no_output
  test_logs_multiple_failures
  test_logs_explicit_pr
  test_logs_auto_detect
  test_logs_truncation_at_500_lines
  test_logs_truncation_notice_format
  test_logs_under_500_no_truncation
  test_logs_no_pr_found_exits_nonzero
  test_logs_sha_lookup_failure
  test_logs_missing_pr_value_exits_nonzero
  test_logs_missing_pr_value_stderr_message
  test_logs_empty_pr_value_exits_nonzero
  test_logs_unknown_option_exits_nonzero
  test_logs_help_exits_zero
  test_logs_log_fetch_fails_shows_placeholder
)

test_logs_failed_check_shows_log() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content="Running tests...\nTest failed: expected 200 got 500"
  setup_mocks_logs "$check_runs" "$log_content"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF -- "--- log" \
    && echo "$output" | grep -qF "name: CI" \
    && echo "$output" | grep -qF "Running tests..." \
    && echo "$output" | grep -qF "Test failed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: failed check should show log block with name and content (output: $output)"
  fi
}

test_logs_all_passing_no_output() {
  local check_runs='{"total_count":2,"check_runs":[{"id":111,"name":"Build","status":"completed","conclusion":"success"},{"id":222,"name":"Test","status":"completed","conclusion":"success"}]}'
  setup_mocks_logs "$check_runs" "should not appear"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: all passing checks should produce no output (got: $output)"
  fi
}

test_logs_multiple_failures() {
  local check_runs='{"total_count":2,"check_runs":[{"id":222,"name":"Test","status":"completed","conclusion":"failure"},{"id":111,"name":"Build","status":"completed","conclusion":"failure"}]}'
  setup_mocks_logs_multi "$check_runs" 111 "build error at line 5" 222 "test assertion failed"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
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

test_logs_explicit_pr() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content="error in CI"
  setup_mocks_logs "$check_runs" "$log_content"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "name: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --pr 42 should return failed check logs (output: $output)"
  fi
}

test_logs_auto_detect() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content="error in CI"
  setup_mocks_logs_auto "$check_runs" "$log_content"
  local output
  output=$(run_script logs 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "name: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect should resolve PR and return logs (output: $output)"
  fi
}

test_logs_truncation_at_500_lines() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content
  log_content=$(seq 1 600 | paste -sd '\n' -)
  setup_mocks_logs "$check_runs" "$log_content"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
  local content_lines
  content_lines=$(echo "$output" | grep -v -e "--- log" -e "name:" -e "truncated" | grep -c .)
  if [ "$content_lines" -le 500 ] && echo "$output" | grep -qF "[truncated:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected at most 500 content lines with truncation notice (content_lines: $content_lines, output: $output)"
  fi
}

test_logs_truncation_notice_format() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content
  log_content=$(seq 1 600 | paste -sd '\n' -)
  setup_mocks_logs "$check_runs" "$log_content"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "[truncated: 100 lines omitted]"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected '[truncated: 100 lines omitted]' (output: $output)"
  fi
}

test_logs_under_500_no_truncation() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log_content
  log_content=$(seq 1 10 | paste -sd '\n' -)
  setup_mocks_logs "$check_runs" "$log_content"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
  if ! echo "$output" | grep -q "truncated"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: under 500 lines should not show truncation notice (output: $output)"
  fi
}

test_logs_no_pr_found_exits_nonzero() {
  setup_mocks_logs_no_pr
  local exit_code=0
  run_script logs >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR found should exit non-zero"
  fi
}

test_logs_sha_lookup_failure() {
  setup_mocks_logs_sha_fails
  local output
  output=$(run_script logs 2>&1) || true
  cleanup_mocks
  if echo "$output" | grep -qF "failed to resolve head SHA"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SHA lookup failure should mention 'failed to resolve head SHA' (output: $output)"
  fi
}

test_logs_missing_pr_value_exits_nonzero() {
  assert_exit 1 "logs --pr without value exits non-zero" bash "$script" logs --pr
}

test_logs_missing_pr_value_stderr_message() {
  assert_stderr_contains "logs --pr without value gives clear message" "missing value for --pr" bash "$script" logs --pr
}

test_logs_empty_pr_value_exits_nonzero() {
  assert_exit 1 "logs --pr empty exits non-zero" bash "$script" logs --pr ""
}

test_logs_unknown_option_exits_nonzero() {
  setup_mocks
  local exit_code=0
  PATH="$mock_dir:$ORIGINAL_PATH" bash "$script" logs --pr 42 --bogus >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: unknown option should exit non-zero"
  fi
}

test_logs_help_exits_zero() {
  assert_exit 0 "logs --help exits 0" bash "$script" logs --help
  assert_exit 0 "logs -h exits 0" bash "$script" logs -h
}

test_logs_log_fetch_fails_shows_placeholder() {
  local check_runs='{"total_count":1,"check_runs":[{"id":111,"name":"CI","status":"completed","conclusion":"failure"}]}'
  setup_mocks_logs_no_log "$check_runs"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF -- "--- log" \
    && echo "$output" | grep -qF "name: CI" \
    && echo "$output" | grep -qF "[log not available]"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: log fetch failure should show placeholder (output: $output)"
  fi
}
