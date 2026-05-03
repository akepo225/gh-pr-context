#!/usr/bin/env bash

ORIGINAL_PATH="$HOME/bin:$PATH"

# setup_mocks_base creates a temporary mock directory and installs a mock git executable that returns a fixed remote URL for "remote get-url origin" and a fixed branch name for "rev-parse --abbrev-ref HEAD".
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

# setup_mocks_auto_detect creates mock `git` and `gh` executables in the temporary mock directory that simulate auto-detection of an open pull request (PR 99) and return canned responses for PR details, comments, issue comments, and check-runs.
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

# setup_mocks_explicit_pr creates temporary mock git and gh commands where gh returns data for PR 55 (a fixed head SHA, empty comments, and empty check-runs) and fails with an error if PR auto-detection is attempted.
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

# setup_mocks_no_pr creates mock `git` and `gh` executables in `$mock_dir`; the `gh` mock returns an empty response for `pulls?head=acme:my-feature` (simulating no open PR) and exits with status 1 for any other invocation.
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

# setup_mocks_api_fail creates mock environment and places a `gh` mock that immediately exits with status 1 to simulate API failures.
setup_mocks_api_fail() {
  setup_mocks_base
  printf '#!/usr/bin/env bash\nexit 1\n' > "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

# run_script executes the target script under test with the mock directory prepended to PATH, forwarding all arguments.
run_script() {
  PATH="$mock_dir:$ORIGINAL_PATH" bash "$script" "$@"
}

# cleanup_mocks removes the temporary mock directory created by the setup functions.
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

# test_pr_resolution_auto_detect_comments verifies that auto-detection resolves to pull request 99 and that running the `comments` subcommand exits successfully, updating the global pass/fail counters and printing a failure message on error.
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

# test_pr_resolution_auto_detect_status verifies that auto-detect finds PR 99 and the `status` subcommand exits successfully.
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

# test_pr_resolution_auto_detect_logs runs the `logs` subcommand with auto-detected PR mocks and increments `pass` on success or `fail` and prints a failure message on non-zero exit.
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

# test_pr_resolution_explicit_pr_skips_autodetect_comments verifies that invoking the script's `comments` subcommand with an explicit `--pr` uses the provided PR and does not trigger auto-detection.
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

# test_pr_resolution_explicit_pr_skips_autodetect_status verifies that providing `--pr` prevents auto-detection when running the `status` subcommand; it increments `pass` on success or `fail` and prints a failure message containing the exit code and captured output.
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

# test_pr_resolution_explicit_pr_skips_autodetect_logs verifies that running the script's `logs` subcommand with `--pr 55` does not invoke auto-detection (output must not contain "SHOULD NOT BE CALLED") and increments the `pass` or `fail` counters accordingly.
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

# test_pr_resolution_no_pr_found_exits_nonzero verifies that the target script exits with a non-zero status when no open pull request is found.
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

# test_pr_resolution_no_pr_found_stderr_message verifies that when no open PR exists the script writes "no open PR found" to stderr.
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

# test_pr_resolution_api_fail_exits_nonzero Verifies that when the mocked GitHub CLI fails, invoking the script's `comments` command exits with a non-zero status; increments `pass` on non-zero, otherwise increments `fail` and prints a failure message.
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

# test_pr_resolution_api_fail_stderr_message verifies that when the GitHub API returns an error the script prints a failure message containing "failed" (case-insensitive) and updates the pass/fail counters.
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
