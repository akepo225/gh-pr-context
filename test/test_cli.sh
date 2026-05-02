#!/usr/bin/env bash

test_names+=(
  test_no_args_exits_nonzero
  test_help_flag_exits_zero
  test_unknown_command_exits_nonzero
  test_unknown_option_exits_nonzero
  test_missing_pr_value_exits_nonzero
  test_missing_pr_value_stderr_message
  test_missing_since_value_exits_nonzero
  test_missing_since_value_stderr_message
  test_since_invalid_format_exits_nonzero
  test_since_invalid_format_stderr_message
  test_since_malformed_sha_exits_nonzero
  test_since_malformed_sha_stderr_message
  test_since_invalid_calendar_date_exits_nonzero
  test_since_invalid_calendar_date_stderr_message
)

test_no_args_exits_nonzero() {
  assert_exit 1 "no args should exit 1" bash "$script"
}

test_help_flag_exits_zero() {
  assert_exit 0 "--help exits 0" bash "$script" --help
  assert_exit 0 "-h exits 0" bash "$script" -h
}

test_unknown_command_exits_nonzero() {
  assert_exit 1 "unknown command exits non-zero" bash "$script" bogus
}

test_unknown_option_exits_nonzero() {
  assert_exit 1 "unknown option on comments exits non-zero" bash "$script" comments --bogus
}

test_missing_pr_value_exits_nonzero() {
  assert_exit 1 "--pr without value exits non-zero" bash "$script" comments --pr
}

test_missing_pr_value_stderr_message() {
  assert_stderr_contains "--pr without value gives clear message" "missing value for --pr" bash "$script" comments --pr
}

test_missing_since_value_exits_nonzero() {
  assert_exit 1 "--since without value exits non-zero" bash "$script" comments --since
}

test_missing_since_value_stderr_message() {
  assert_stderr_contains "--since without value gives clear message" "missing value for --since" bash "$script" comments --since
}

test_since_invalid_format_exits_nonzero() {
  assert_exit 1 "--since with invalid format exits non-zero" bash "$script" comments --since "not-a-date"
}

test_since_invalid_format_stderr_message() {
  assert_stderr_contains "--since invalid format gives clear message" "invalid --since value" bash "$script" comments --since "not-a-date"
}

test_since_malformed_sha_exits_nonzero() {
  assert_exit 1 "--since with short SHA exits non-zero" bash "$script" comments --since "abc123"
}

test_since_malformed_sha_stderr_message() {
  assert_stderr_contains "--since short SHA gives clear message" "invalid --since value" bash "$script" comments --since "abc123"
}

test_since_invalid_calendar_date_exits_nonzero() {
  assert_exit 1 "--since with impossible date exits non-zero" bash "$script" comments --since "2025-13-40"
  assert_exit 1 "--since with invalid month exits non-zero" bash "$script" comments --since "2025-13-01"
  assert_exit 1 "--since with invalid day exits non-zero" bash "$script" comments --since "2023-02-30"
  assert_exit 1 "--since with invalid hour exits non-zero" bash "$script" comments --since "2023-01-01T25:00:00"
}

test_since_invalid_calendar_date_stderr_message() {
  assert_stderr_contains "--since impossible date gives clear message" "invalid --since value" bash "$script" comments --since "2025-13-40"
  assert_stderr_contains "--since invalid month gives clear message" "invalid --since value" bash "$script" comments --since "2025-13-01"
  assert_stderr_contains "--since invalid day gives clear message" "invalid --since value" bash "$script" comments --since "2023-02-30"
  assert_stderr_contains "--since invalid hour gives clear message" "invalid --since value" bash "$script" comments --since "2023-01-01T25:00:00"
}
