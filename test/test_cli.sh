#!/usr/bin/env bash

test_names+=(
  test_no_args_exits_nonzero
  test_help_flag_exits_zero
  test_unknown_command_exits_nonzero
  test_unknown_option_exits_nonzero
  test_missing_pr_value_exits_nonzero
  test_missing_pr_value_stderr_message
  test_since_flag_not_yet_implemented
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

test_since_flag_not_yet_implemented() {
  assert_stderr_contains "--since not yet implemented" "not yet implemented" bash "$script" comments --since 2025-01-01
}
