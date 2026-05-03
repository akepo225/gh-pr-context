#!/usr/bin/env bash

ORIGINAL_PATH="$HOME/bin:$PATH"

setup_mocks_base() {
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/git" << 'GIT_EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
  "rev-parse --abbrev-ref HEAD") echo "my-feature" ;;
  *) exit 1 ;;
esac
GIT_EOF
  chmod +x "$mock_dir/git"
}

setup_mocks_auto_detect() {
  setup_mocks_base
  local head_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls?head=acme:my-feature"*)\n'         >> "$mock_dir/gh"
  printf "    echo '99'\n"                              >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *"pulls/99/comments"*)\n'                  >> "$mock_dir/gh"
  printf "    echo '[]'\n"                             >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *"issues/99/comments"*)\n'                 >> "$mock_dir/gh"
  printf "    echo '[]'\n"                             >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *"pulls/99"*)\n'                           >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$head_sha"                 >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *"check-runs"*)\n'                         >> "$mock_dir/gh"
  printf '    echo '"'"'{"total_count":0,"check_runs":[]}'"'"'\n' >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'                           >> "$mock_dir/gh"
  printf 'esac\n'                                     >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_explicit_pr() {
  setup_mocks_base
  local head_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls?head="*)\n'                        >> "$mock_dir/gh"
  printf '    echo "SHOULD NOT BE CALLED" >&2; exit 1\n' >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *"pulls/55/comments"*)\n'                  >> "$mock_dir/gh"
  printf "    echo '[]'\n"                             >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *"issues/55/comments"*)\n'                 >> "$mock_dir/gh"
  printf "    echo '[]'\n"                             >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *"pulls/55"*)\n'                           >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$head_sha"                 >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *"check-runs"*)\n'                         >> "$mock_dir/gh"
  printf '    echo '"'"'{"total_count":0,"check_runs":[]}'"'"'\n' >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'                           >> "$mock_dir/gh"
  printf 'esac\n'                                     >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_no_pr() {
  setup_mocks_base
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls?head=acme:my-feature"*)\n'         >> "$mock_dir/gh"
  printf '    echo ""\n'                               >> "$mock_dir/gh"
  printf '    ;;\n'                                    >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'                           >> "$mock_dir/gh"
  printf 'esac\n'                                     >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_api_fail() {
  setup_mocks_base
  printf '#!/usr/bin/env bash\nexit 1\n' > "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

run_script() {
  PATH="$mock_dir:$ORIGINAL_PATH" bash "$script" "$@"
}

cleanup_mocks() {
  rm -rf "$mock_dir"
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
  cleanup_mocks
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
  cleanup_mocks
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
  cleanup_mocks
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
  cleanup_mocks
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
  cleanup_mocks
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
  cleanup_mocks
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
  cleanup_mocks
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
  cleanup_mocks
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
  cleanup_mocks
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
  cleanup_mocks
  if echo "$output" | grep -qiF "failed"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: API failure should emit a failure message (output: $output)"
  fi
}
