#!/usr/bin/env bash

ORIGINAL_PATH="$HOME/bin:$PATH"

HEAD_SHA="abc123def456abc123def456abc123def456abc1"

setup_mocks() {
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/git" << GIT_EOF
#!/usr/bin/env bash
case "\$*" in
  "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
  "branch --show-current") echo "feature-branch" ;;
  "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
  *) exit 1 ;;
esac
GIT_EOF
  chmod +x "$mock_dir/git"
}

setup_mocks_status() {
  local check_runs="$1"

  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *\"pulls/42\"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$HEAD_SHA" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *\"check-runs\"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$check_runs" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_status_auto() {
  local check_runs="$1"

  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *\"pulls?head=acme:feature-branch\"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" '42' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *\"pulls/42\"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$HEAD_SHA" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *\"check-runs\"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$check_runs" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_status_no_pr() {
  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *\"pulls?head=acme:feature-branch\"*)\n' >> "$mock_dir/gh"
  printf '    echo ""\n' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_status_paginated() {
  local page1="$1"
  local page2="$2"

  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *\"pulls/42\"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$HEAD_SHA" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *\"check-runs\"*)\n' >> "$mock_dir/gh"
  printf "    printf '%%s\\n' '%s' '%s'\n" "$page1" "$page2" >> "$mock_dir/gh"
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
  test_status_completed_check
  test_status_in_progress_omits_conclusion
  test_status_queued_omits_conclusion
  test_status_sorted_by_name
  test_status_explicit_pr
  test_status_auto_detect
  test_status_exits_zero
  test_status_no_pr_found_exits_nonzero
  test_status_no_pr_found_stderr_message
  test_status_empty_checks
  test_status_multiple_conclusions
  test_status_unknown_option_exits_nonzero
  test_status_missing_pr_value_exits_nonzero
  test_status_missing_pr_value_stderr_message
  test_status_help_exits_zero
  test_status_paginated_merges_all_checks
  test_status_sha_lookup_failure_stderr_message
)

test_status_completed_check() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
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

test_status_in_progress_omits_conclusion() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"Build","status":"in_progress","conclusion":null}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "status: in_progress" \
    && ! echo "$output" | grep -qF "conclusion:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: in_progress check should omit conclusion (output: $output)"
  fi
}

test_status_queued_omits_conclusion() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"Lint","status":"queued","conclusion":null}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "status: queued" \
    && ! echo "$output" | grep -qF "conclusion:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: queued check should omit conclusion (output: $output)"
  fi
}

test_status_sorted_by_name() {
  local check_runs='{"total_count":2,"check_runs":[{"name":"Zebra","status":"completed","conclusion":"success"},{"name":"Alpha","status":"completed","conclusion":"success"}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  local first_name
  first_name=$(echo "$output" | grep -m1 "name:" | sed 's/name: //')
  if [ "$first_name" = "Alpha" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected Alpha first, got: $first_name (output: $output)"
  fi
}

test_status_explicit_pr() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "name: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --pr 42 should return check status (output: $output)"
  fi
}

test_status_auto_detect() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_status_auto "$check_runs"
  local output
  output=$(run_script status 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "name: CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: auto-detect should resolve PR and return check status (output: $output)"
  fi
}

test_status_exits_zero() {
  local check_runs='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
  setup_mocks_status "$check_runs"
  assert_exit 0 "status exits 0 on success" run_script status --pr 42
  cleanup_mocks
}

test_status_no_pr_found_exits_nonzero() {
  setup_mocks_status_no_pr
  local exit_code=0
  run_script status >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR found should exit non-zero"
  fi
}

test_status_empty_checks() {
  local check_runs='{"total_count":0,"check_runs":[]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: empty check_runs should produce no output (got: $output)"
  fi
}

test_status_multiple_conclusions() {
  local check_runs='{"total_count":3,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"},{"name":"Test","status":"completed","conclusion":"failure"},{"name":"Deploy","status":"completed","conclusion":"cancelled"}]}'
  setup_mocks_status "$check_runs"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "conclusion: success" \
    && echo "$output" | grep -qF "conclusion: failure" \
    && echo "$output" | grep -qF "conclusion: cancelled"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: mixed conclusions not all present (output: $output)"
  fi
}

test_status_unknown_option_exits_nonzero() {
  setup_mocks
  local exit_code=0
  PATH="$mock_dir:$ORIGINAL_PATH" bash "$script" status --pr 42 --bogus >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: unknown option should exit non-zero"
  fi
}

test_status_no_pr_found_stderr_message() {
  setup_mocks_status_no_pr
  local output
  output=$(run_script status 2>&1) || true
  cleanup_mocks
  if echo "$output" | grep -qF "no open PR found"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: no PR found should mention 'no open PR found' (output: $output)"
  fi
}

test_status_missing_pr_value_exits_nonzero() {
  assert_exit 1 "status --pr without value exits non-zero" bash "$script" status --pr
}

test_status_missing_pr_value_stderr_message() {
  assert_stderr_contains "status --pr without value gives clear message" "missing value for --pr" bash "$script" status --pr
}

test_status_help_exits_zero() {
  assert_exit 0 "status --help exits 0" bash "$script" status --help
  assert_exit 0 "status -h exits 0" bash "$script" status -h
}

test_status_paginated_merges_all_checks() {
  local page1='{"total_count":3,"check_runs":[{"name":"Zebra","status":"completed","conclusion":"success"}]}'
  local page2='{"total_count":3,"check_runs":[{"name":"Alpha","status":"completed","conclusion":"failure"}]}'
  setup_mocks_status_paginated "$page1" "$page2"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "name: Alpha" \
    && echo "$output" | grep -qF "name: Zebra"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: paginated response should merge all pages (output: $output)"
  fi
}

setup_mocks_status_sha_fails() {
  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *\"pulls?head=acme:feature-branch\"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" '42' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *\"pulls/42\"*)\n' >> "$mock_dir/gh"
  printf '    exit 1\n' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

test_status_sha_lookup_failure_stderr_message() {
  setup_mocks_status_sha_fails
  local output
  output=$(run_script status 2>&1) || true
  cleanup_mocks
  if echo "$output" | grep -qF "failed to resolve head SHA"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: SHA lookup failure should mention 'failed to resolve head SHA' (output: $output)"
  fi
}
