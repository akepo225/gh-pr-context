#!/usr/bin/env bash

ORIGINAL_PATH="$HOME/bin:$PATH"

KNOWN_SHA="cccccccccccccccccccccccccccccccccccccccc"
UNKNOWN_SHA="dddddddddddddddddddddddddddddddddddddddd"

HEAD_EPOCH="1742040000"
SHA_EPOCH="1751587200"

setup_mocks() {
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/git" << GIT_EOF
#!/usr/bin/env bash
case "\$*" in
  "remote get-url origin")       echo "https://github.com/acme/widgets.git" ;;
  "rev-parse --abbrev-ref HEAD") echo "my-feature" ;;
  "log -1 --format=%ct HEAD")    echo "$HEAD_EPOCH" ;;
  "log -1 --format=%ct $KNOWN_SHA") echo "$SHA_EPOCH" ;;
  "log -1 --format=%ct $UNKNOWN_SHA") exit 1 ;;
  *) exit 1 ;;
esac
GIT_EOF
  chmod +x "$mock_dir/git"

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42/comments"*)\n'           >> "$mock_dir/gh"
  printf "    echo '[]'\n"                       >> "$mock_dir/gh"
  printf '    ;;\n'                              >> "$mock_dir/gh"
  printf '  *"issues/42/comments"*)\n'          >> "$mock_dir/gh"
  printf "    echo '[]'\n"                       >> "$mock_dir/gh"
  printf '    ;;\n'                              >> "$mock_dir/gh"
  printf '  *"pulls/comments/42/replies"*)\n'   >> "$mock_dir/gh"
  printf "    echo '[]'\n"                       >> "$mock_dir/gh"
  printf '    ;;\n'                              >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'                     >> "$mock_dir/gh"
  printf 'esac\n'                               >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

run_script() {
  PATH="$mock_dir:$ORIGINAL_PATH" bash "$script" "$@"
}

cleanup_mocks() {
  rm -rf "$mock_dir"
}

test_names+=(
  test_since_empty_resolves_to_empty
  test_since_last_commit_exits_zero
  test_since_last_commit_format_is_iso8601
  test_since_known_sha_exits_zero
  test_since_known_sha_format_is_iso8601
  test_since_date_only_exits_zero
  test_since_date_only_appends_midnight_utc
  test_since_datetime_exits_zero
  test_since_datetime_appends_z
  test_since_unknown_sha_exits_nonzero
  test_since_unknown_sha_stderr_mentions_unknown_commit
  test_since_invalid_format_exits_nonzero
  test_since_invalid_format_stderr_message
  test_since_invalid_month_exits_nonzero
  test_since_invalid_day_exits_nonzero
  test_since_invalid_hour_exits_nonzero
  test_since_short_sha_treated_as_invalid
)

test_since_empty_resolves_to_empty() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: omitting --since should exit 0 (exit: $exit_code)"
  fi
}

test_since_last_commit_exits_zero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since last-commit >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since last-commit should exit 0 (exit: $exit_code)"
  fi
}

test_since_last_commit_format_is_iso8601() {
  setup_mocks
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42/comments"*)\n'            >> "$mock_dir/gh"
  printf '    echo '"'"'[]'"'"'\n'               >> "$mock_dir/gh"
  printf '    ;;\n'                               >> "$mock_dir/gh"
  printf '  *"issues/42/comments"*)\n'           >> "$mock_dir/gh"
  printf "    echo '[{\"user\":{\"login\":\"bot\"},\"created_at\":\"2099-01-01T00:00:00Z\",\"body\":\"future\"}]'\n" >> "$mock_dir/gh"
  printf '    ;;\n'                               >> "$mock_dir/gh"
  printf '  *"pulls/comments/42/replies"*)\n'   >> "$mock_dir/gh"
  printf "    echo '[]'\n"                       >> "$mock_dir/gh"
  printf '    ;;\n'                              >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'                     >> "$mock_dir/gh"
  printf 'esac\n'                                >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
  local output exit_code=0
  output=$(run_script comments --pr 42 --since last-commit 2>&1) || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "future"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: last-commit timestamp should be valid ISO-8601 and allow future comments through (exit: $exit_code, output: $output)"
  fi
}

test_since_known_sha_exits_zero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since "$KNOWN_SHA" >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <known-sha> should exit 0 (exit: $exit_code)"
  fi
}

test_since_known_sha_format_is_iso8601() {
  setup_mocks
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42/comments"*)\n'            >> "$mock_dir/gh"
  printf '    echo '"'"'[]'"'"'\n'               >> "$mock_dir/gh"
  printf '    ;;\n'                               >> "$mock_dir/gh"
  printf '  *"issues/42/comments"*)\n'           >> "$mock_dir/gh"
  printf "    echo '[{\"user\":{\"login\":\"bot\"},\"created_at\":\"2099-01-01T00:00:00Z\",\"body\":\"future\"}]'\n" >> "$mock_dir/gh"
  printf '    ;;\n'                               >> "$mock_dir/gh"
  printf '  *"pulls/comments/42/replies"*)\n'   >> "$mock_dir/gh"
  printf "    echo '[]'\n"                       >> "$mock_dir/gh"
  printf '    ;;\n'                              >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'                     >> "$mock_dir/gh"
  printf 'esac\n'                                >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
  local output exit_code=0
  output=$(run_script comments --pr 42 --since "$KNOWN_SHA" 2>&1) || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "future"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <sha> timestamp should be valid ISO-8601 and allow future comments through (exit: $exit_code, output: $output)"
  fi
}

test_since_date_only_exits_zero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since 2025-06-15 >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since YYYY-MM-DD should exit 0 (exit: $exit_code)"
  fi
}

test_since_date_only_appends_midnight_utc() {
  setup_mocks
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42/comments"*)\n'            >> "$mock_dir/gh"
  printf '    echo '"'"'[]'"'"'\n'               >> "$mock_dir/gh"
  printf '    ;;\n'                               >> "$mock_dir/gh"
  printf '  *"issues/42/comments"*)\n'           >> "$mock_dir/gh"
  printf "    echo '[{\"user\":{\"login\":\"alice\"},\"created_at\":\"2025-06-15T00:00:00Z\",\"body\":\"on midnight\"}]'\n" >> "$mock_dir/gh"
  printf '    ;;\n'                               >> "$mock_dir/gh"
  printf '  *"pulls/comments/42/replies"*)\n'   >> "$mock_dir/gh"
  printf "    echo '[]'\n"                       >> "$mock_dir/gh"
  printf '    ;;\n'                              >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'                     >> "$mock_dir/gh"
  printf 'esac\n'                                >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
  local output exit_code=0
  output=$(run_script comments --pr 42 --since 2025-06-15 2>&1) || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "on midnight"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: YYYY-MM-DD should resolve to midnight UTC and include comments at that instant (exit: $exit_code, output: $output)"
  fi
}

test_since_datetime_exits_zero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since 2025-06-15T08:30:00 >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since YYYY-MM-DDTHH:mm:ss should exit 0 (exit: $exit_code)"
  fi
}

test_since_datetime_appends_z() {
  setup_mocks
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42/comments"*)\n'            >> "$mock_dir/gh"
  printf '    echo '"'"'[]'"'"'\n'               >> "$mock_dir/gh"
  printf '    ;;\n'                               >> "$mock_dir/gh"
  printf '  *"issues/42/comments"*)\n'           >> "$mock_dir/gh"
  printf "    echo '[{\"user\":{\"login\":\"bob\"},\"created_at\":\"2025-06-15T08:30:00Z\",\"body\":\"exact ts\"}]'\n" >> "$mock_dir/gh"
  printf '    ;;\n'                               >> "$mock_dir/gh"
  printf '  *"pulls/comments/42/replies"*)\n'   >> "$mock_dir/gh"
  printf "    echo '[]'\n"                       >> "$mock_dir/gh"
  printf '    ;;\n'                              >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'                     >> "$mock_dir/gh"
  printf 'esac\n'                                >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
  local output exit_code=0
  output=$(run_script comments --pr 42 --since 2025-06-15T08:30:00 2>&1) || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "exact ts"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: datetime without Z should append Z and include comment at that instant (exit: $exit_code, output: $output)"
  fi
}

test_since_unknown_sha_exits_nonzero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since "$UNKNOWN_SHA" >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <unknown-sha> should exit non-zero"
  fi
}

test_since_unknown_sha_stderr_mentions_unknown_commit() {
  setup_mocks
  local output
  output=$(run_script comments --pr 42 --since "$UNKNOWN_SHA" 2>&1) || true
  cleanup_mocks
  if echo "$output" | grep -qF "unknown commit"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <unknown-sha> should mention 'unknown commit' (output: $output)"
  fi
}

test_since_invalid_format_exits_nonzero() {
  assert_exit 1 "--since with arbitrary string exits non-zero" bash "$script" comments --pr 42 --since "not-a-date-at-all"
}

test_since_invalid_format_stderr_message() {
  assert_stderr_contains "--since invalid format error message" "invalid --since value" bash "$script" comments --pr 42 --since "not-a-date-at-all"
}

test_since_invalid_month_exits_nonzero() {
  assert_exit 1 "--since with month 13 exits non-zero" bash "$script" comments --pr 42 --since "2025-13-01"
}

test_since_invalid_day_exits_nonzero() {
  assert_exit 1 "--since with day 32 exits non-zero" bash "$script" comments --pr 42 --since "2025-01-32"
}

test_since_invalid_hour_exits_nonzero() {
  assert_exit 1 "--since with hour 25 exits non-zero" bash "$script" comments --pr 42 --since "2025-01-01T25:00:00"
}

test_since_short_sha_treated_as_invalid() {
  assert_exit 1 "--since with 7-char sha exits non-zero" bash "$script" comments --pr 42 --since "abc1234"
  assert_stderr_contains "--since 7-char sha emits invalid error" "invalid --since value" bash "$script" comments --pr 42 --since "abc1234"
}
