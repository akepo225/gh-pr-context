#!/usr/bin/env bash

KNOWN_SHA="cccccccccccccccccccccccccccccccccccccccc"
UNKNOWN_SHA="dddddddddddddddddddddddddddddddddddddddd"
SHORT_SHA="ccccccc"
UNKNOWN_SHORT_SHA="ddddddd"
API_SHA="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
API_SHA_SHORT="eeeeeee"
API_DATE="2025-07-04T12:00:00Z"

HEAD_EPOCH="1742040000"
SHA_EPOCH="1751587200"

# setup_mocks defines mocked `git` and `gh` shell functions that return deterministic responses for a small set of calls used by the tests.
setup_mocks() {
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "my-feature" ;;
      "rev-parse $KNOWN_SHA") echo "$KNOWN_SHA" ;;
      "rev-parse $SHORT_SHA") echo "$KNOWN_SHA" ;;
      "rev-parse $UNKNOWN_SHA") echo "$UNKNOWN_SHA" ;;
      "rev-parse $UNKNOWN_SHORT_SHA") exit 1 ;;
      "rev-parse $API_SHA") echo "$API_SHA" ;;
      "rev-parse $API_SHA_SHORT") echo "$API_SHA" ;;
      "log -1 --format=%ct HEAD") echo "$HEAD_EPOCH" ;;
      "log -1 --format=%ct $KNOWN_SHA") echo "$SHA_EPOCH" ;;
      "log -1 --format=%ct $UNKNOWN_SHA") exit 1 ;;
      "log -1 --format=%ct $API_SHA") exit 1 ;;
      *) exit 1 ;;
    esac
  }
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo '[]' ;;
      *"issues/42/comments"*) echo '[]' ;;
      *"pulls/comments/42/replies"*) echo '[]' ;;
      *commits/eeee*) echo '2025-07-04T12:00:00Z' ;;
      *) exit 1 ;;
    esac
  }
}

# run_script exports the mocked `git` and `gh` functions and related SHA/epoch variables, then executes the target script with the provided arguments and propagates its exit status.
run_script() {
  export -f git gh
  export KNOWN_SHA UNKNOWN_SHA SHORT_SHA UNKNOWN_SHORT_SHA API_SHA API_SHA_SHORT API_DATE HEAD_EPOCH SHA_EPOCH
  timeout 15 bash "$script" "$@" </dev/null
}

test_names+=(
  test_since_empty_resolves_to_empty
  test_since_last_commit_exits_zero
  test_since_last_commit_format_is_iso8601
  test_since_known_sha_exits_zero
  test_since_known_sha_format_is_iso8601
  test_since_short_sha_resolves_via_rev_parse
  test_since_short_sha_format_is_iso8601
  test_since_short_sha_unknown_exits_nonzero
  test_since_short_sha_unknown_stderr_mentions_sha
  test_since_api_fallback_exits_zero
  test_since_api_fallback_format_is_iso8601
  test_since_api_failure_exits_nonzero
  test_since_api_failure_stderr_mentions_unknown_commit
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
)

# test_since_empty_resolves_to_empty verifies that invoking the comments command without a `--since` value exits with status 0.
test_since_empty_resolves_to_empty() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: omitting --since should exit 0 (exit: $exit_code)"
  fi
}

# test_since_last_commit_exits_zero verifies that invoking `comments --pr 42 --since last-commit` exits successfully and updates the `pass`/`fail` counters.
test_since_last_commit_exits_zero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since last-commit >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since last-commit should exit 0 (exit: $exit_code)"
  fi
}

# test_since_last_commit_format_is_iso8601 verifies that a timestamp resolved for last-commit is formatted as ISO-8601 and accepted by the script (comments with future timestamps are included).
test_since_last_commit_format_is_iso8601() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo '[]' ;;
      *"issues/42/comments"*) echo '[{"user":{"login":"bot"},"created_at":"2099-01-01T00:00:00Z","body":"future"}]' ;;
      *"pulls/comments/42/replies"*) echo '[]' ;;
      *) exit 1 ;;
    esac
  }
  local output exit_code=0
  output=$(run_script comments --pr 42 --since last-commit 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "future"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: last-commit timestamp should be valid ISO-8601 and allow future comments through (exit: $exit_code, output: $output)"
  fi
}

# test_since_known_sha_exits_zero verifies that running the script with `--since` set to a known commit SHA exits with status 0.
test_since_known_sha_exits_zero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since "$KNOWN_SHA" >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <known-sha> should exit 0 (exit: $exit_code)"
  fi
}

# test_since_known_sha_format_is_iso8601 verifies that when --since is given a known commit SHA the script emits an ISO-8601 timestamp accepted by the API and thus includes comments with a future `created_at` value.
test_since_known_sha_format_is_iso8601() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo '[]' ;;
      *"issues/42/comments"*) echo '[{"user":{"login":"bot"},"created_at":"2099-01-01T00:00:00Z","body":"future"}]' ;;
      *"pulls/comments/42/replies"*) echo '[]' ;;
      *) exit 1 ;;
    esac
  }
  local output exit_code=0
  output=$(run_script comments --pr 42 --since "$KNOWN_SHA" 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "future"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <sha> timestamp should be valid ISO-8601 and allow future comments through (exit: $exit_code, output: $output)"
  fi
}

# test_since_date_only_exits_zero verifies that running the script with a date-only `--since` value (YYYY-MM-DD) exits with status 0.
test_since_date_only_exits_zero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since 2025-06-15 >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since YYYY-MM-DD should exit 0 (exit: $exit_code)"
  fi
}

# test_since_date_only_appends_midnight_utc verifies that a date-only `--since` value (YYYY-MM-DD) is treated as midnight UTC and that comments with `created_at` equal to that timestamp are included.
test_since_date_only_appends_midnight_utc() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo '[]' ;;
      *"issues/42/comments"*) echo '[{"user":{"login":"alice"},"created_at":"2025-06-15T00:00:00Z","body":"on midnight"}]' ;;
      *"pulls/comments/42/replies"*) echo '[]' ;;
      *) exit 1 ;;
    esac
  }
  local output exit_code=0
  output=$(run_script comments --pr 42 --since 2025-06-15 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "on midnight"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: YYYY-MM-DD should resolve to midnight UTC and include comments at that instant (exit: $exit_code, output: $output)"
  fi
}

# test_since_datetime_exits_zero verifies that passing a date-time without a timezone (YYYY-MM-DDTHH:mm:ss) to `--since` causes the script to exit with status 0.
test_since_datetime_exits_zero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since 2025-06-15T08:30:00 >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since YYYY-MM-DDTHH:mm:ss should exit 0 (exit: $exit_code)"
  fi
}

# test_since_datetime_appends_z verifies that a datetime without a trailing "Z" is treated as UTC (appending "Z") so the script includes comments whose created_at matches that exact timestamp.
test_since_datetime_appends_z() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo '[]' ;;
      *"issues/42/comments"*) echo '[{"user":{"login":"bob"},"created_at":"2025-06-15T08:30:00Z","body":"exact ts"}]' ;;
      *"pulls/comments/42/replies"*) echo '[]' ;;
      *) exit 1 ;;
    esac
  }
  local output exit_code=0
  output=$(run_script comments --pr 42 --since 2025-06-15T08:30:00 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "exact ts"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: datetime without Z should append Z and include comment at that instant (exit: $exit_code, output: $output)"
  fi
}

# test_since_unknown_sha_exits_nonzero verifies that running the script with --since set to an unknown commit SHA results in a non-zero exit status.
test_since_unknown_sha_exits_nonzero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since "$UNKNOWN_SHA" >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <unknown-sha> should exit non-zero"
  fi
}

# test_since_unknown_sha_stderr_mentions_unknown_commit verifies that running the script with --since set to an unknown commit SHA writes "unknown commit" to stderr.
test_since_unknown_sha_stderr_mentions_unknown_commit() {
  setup_mocks
  local output
  output=$(run_script comments --pr 42 --since "$UNKNOWN_SHA" 2>&1) || true
  if echo "$output" | grep -qF "unknown commit"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <unknown-sha> should mention 'unknown commit' (output: $output)"
  fi
}

# test_since_invalid_format_exits_nonzero verifies that supplying a non-date string to --since causes the script to exit with status 1.
test_since_invalid_format_exits_nonzero() {
  assert_exit 1 "--since with arbitrary string exits non-zero" bash "$script" comments --pr 42 --since "not-a-date-at-all"
}

# test_since_invalid_format_stderr_message verifies that providing an invalid `--since` value prints "invalid --since value" to stderr.
test_since_invalid_format_stderr_message() {
  assert_stderr_contains "--since invalid format error message" "invalid --since value" bash "$script" comments --pr 42 --since "not-a-date-at-all"
}

# test_since_invalid_month_exits_nonzero verifies that invoking the script with `--since "2025-13-01"` causes it to exit with a non-zero status.
test_since_invalid_month_exits_nonzero() {
  assert_exit 1 "--since with month 13 exits non-zero" bash "$script" comments --pr 42 --since "2025-13-01"
}

# test_since_invalid_day_exits_nonzero verifies that passing `--since "2025-01-32"` causes the script to exit with status 1.
test_since_invalid_day_exits_nonzero() {
  assert_exit 1 "--since with day 32 exits non-zero" bash "$script" comments --pr 42 --since "2025-01-32"
}

# test_since_invalid_hour_exits_nonzero verifies that invoking the script with --since "2025-01-01T25:00:00" causes the command to exit with status 1.
test_since_invalid_hour_exits_nonzero() {
  assert_exit 1 "--since with hour 25 exits non-zero" bash "$script" comments --pr 42 --since "2025-01-01T25:00:00"
}

# test_since_short_sha_resolves_via_rev_parse verifies that a 7-char SHA matching a known commit resolves successfully.
test_since_short_sha_resolves_via_rev_parse() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since "$SHORT_SHA" >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <7-char sha> should exit 0 (exit: $exit_code)"
  fi
}

# test_since_short_sha_format_is_iso8601 verifies that a short SHA produces a valid ISO-8601 timestamp that allows future comments through.
test_since_short_sha_format_is_iso8601() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo '[]' ;;
      *"issues/42/comments"*) echo '[{"user":{"login":"bot"},"created_at":"2099-01-01T00:00:00Z","body":"future-short"}]' ;;
      *"pulls/comments/42/replies"*) echo '[]' ;;
      *) exit 1 ;;
    esac
  }
  local output exit_code=0
  output=$(run_script comments --pr 42 --since "$SHORT_SHA" 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "future-short"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <short-sha> timestamp should be valid ISO-8601 (exit: $exit_code, output: $output)"
  fi
}

# test_since_short_sha_unknown_exits_nonzero verifies that an unknown 7-char SHA exits non-zero.
test_since_short_sha_unknown_exits_nonzero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since "$UNKNOWN_SHORT_SHA" >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <unknown-7-char-sha> should exit non-zero"
  fi
}

# test_since_short_sha_unknown_stderr_mentions_sha verifies that a failed short SHA resolution mentions "ambiguous or unknown SHA".
test_since_short_sha_unknown_stderr_mentions_sha() {
  setup_mocks
  local output
  output=$(run_script comments --pr 42 --since "$UNKNOWN_SHORT_SHA" 2>&1) || true
  if echo "$output" | grep -qF "ambiguous or unknown SHA"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <unknown-7-char-sha> should mention 'ambiguous or unknown SHA' (output: $output)"
  fi
}

# test_since_api_fallback_exits_zero verifies that when git rev-parse succeeds but git log fails, the GitHub API fallback is used and the command exits 0.
test_since_api_fallback_exits_zero() {
  setup_mocks
  local exit_code=0
  run_script comments --pr 42 --since "$API_SHA" >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <api-only-sha> should exit 0 via API fallback (exit: $exit_code)"
  fi
}

# test_since_api_fallback_format_is_iso8601 verifies the API fallback produces a valid ISO-8601 timestamp by checking that a comment with a future created_at passes the filter.
test_since_api_fallback_format_is_iso8601() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo '[]' ;;
      *"issues/42/comments"*) echo '[{"user":{"login":"bot"},"created_at":"2099-01-01T00:00:00Z","body":"future-api"}]' ;;
      *"pulls/comments/42/replies"*) echo '[]' ;;
      *commits/eeee*) echo '2025-07-04T12:00:00Z' ;;
      *) exit 1 ;;
    esac
  }
  local output exit_code=0
  output=$(run_script comments --pr 42 --since "$API_SHA" 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "future-api"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: API fallback timestamp should be valid ISO-8601 and allow future comments through (exit: $exit_code, output: $output)"
  fi
}

# test_since_api_failure_exits_nonzero verifies that when both git log and gh api fail, the command exits non-zero.
test_since_api_failure_exits_nonzero() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo '[]' ;;
      *"issues/42/comments"*) echo '[]' ;;
      *"pulls/comments/42/replies"*) echo '[]' ;;
      *"commits/"*) exit 1 ;;
      *) exit 1 ;;
    esac
  }
  local exit_code=0
  run_script comments --pr 42 --since "$API_SHA" >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <sha> should exit non-zero when both git log and API fail"
  fi
}

# test_since_api_failure_stderr_mentions_unknown_commit verifies that when both local and API resolution fail, stderr mentions "unknown commit".
test_since_api_failure_stderr_mentions_unknown_commit() {
  setup_mocks
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo '[]' ;;
      *"issues/42/comments"*) echo '[]' ;;
      *"pulls/comments/42/replies"*) echo '[]' ;;
      *"commits/"*) exit 1 ;;
      *) exit 1 ;;
    esac
  }
  local output
  output=$(run_script comments --pr 42 --since "$API_SHA" 2>&1) || true
  if echo "$output" | grep -qF "unknown commit"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: API failure should mention 'unknown commit' (output: $output)"
  fi
}
