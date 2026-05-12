#!/usr/bin/env bash

source "$script"

test_names+=(
  test_parse_duration_seconds
  test_parse_duration_minutes
  test_parse_duration_hours
  test_parse_duration_zero
  test_parse_duration_multi_digit_seconds
  test_parse_duration_large_hours
  test_parse_duration_bare_number_exits_nonzero
  test_parse_duration_negative_exits_nonzero
  test_parse_duration_non_numeric_exits_nonzero
  test_parse_duration_empty_exits_nonzero
  test_parse_duration_bare_number_stderr
  test_parse_duration_negative_stderr
)

test_parse_duration_seconds() {
  local result
  result=$(parse_duration "30s") || { fail=$((fail + 1)); echo "FAIL: 30s should exit 0"; return; }
  if [ "$result" = "30" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: parse_duration 30s expected 30 got $result"
  fi
}

test_parse_duration_minutes() {
  local result
  result=$(parse_duration "5m") || { fail=$((fail + 1)); echo "FAIL: 5m should exit 0"; return; }
  if [ "$result" = "300" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: parse_duration 5m expected 300 got $result"
  fi
}

test_parse_duration_hours() {
  local result
  result=$(parse_duration "1h") || { fail=$((fail + 1)); echo "FAIL: 1h should exit 0"; return; }
  if [ "$result" = "3600" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: parse_duration 1h expected 3600 got $result"
  fi
}

test_parse_duration_zero() {
  local result
  result=$(parse_duration "0s") || { fail=$((fail + 1)); echo "FAIL: 0s should exit 0"; return; }
  if [ "$result" = "0" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: parse_duration 0s expected 0 got $result"
  fi
}

test_parse_duration_multi_digit_seconds() {
  local result
  result=$(parse_duration "90s") || { fail=$((fail + 1)); echo "FAIL: 90s should exit 0"; return; }
  if [ "$result" = "90" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: parse_duration 90s expected 90 got $result"
  fi
}

test_parse_duration_large_hours() {
  local result
  result=$(parse_duration "100h") || { fail=$((fail + 1)); echo "FAIL: 100h should exit 0"; return; }
  if [ "$result" = "360000" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: parse_duration 100h expected 360000 got $result"
  fi
}

test_parse_duration_bare_number_exits_nonzero() {
  local ec=0
  (parse_duration "300") >/dev/null 2>&1 || ec=$?
  if [ "$ec" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: bare number 300 should exit 1 got $ec"
  fi
}

test_parse_duration_negative_exits_nonzero() {
  local ec=0
  (parse_duration "-5m") >/dev/null 2>&1 || ec=$?
  if [ "$ec" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: negative -5m should exit 1 got $ec"
  fi
}

test_parse_duration_non_numeric_exits_nonzero() {
  local ec=0
  (parse_duration "abc") >/dev/null 2>&1 || ec=$?
  if [ "$ec" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: non-numeric abc should exit 1 got $ec"
  fi
}

test_parse_duration_empty_exits_nonzero() {
  local ec=0
  (parse_duration "") >/dev/null 2>&1 || ec=$?
  if [ "$ec" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: empty string should exit 1 got $ec"
  fi
}

test_parse_duration_bare_number_stderr() {
  local output
  output=$(parse_duration "300" 2>&1 >/dev/null) || true
  if echo "$output" | grep -qF "invalid duration"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: bare number stderr should contain 'invalid duration' got: $output"
  fi
}

test_parse_duration_negative_stderr() {
  local output
  output=$(parse_duration "-5m" 2>&1 >/dev/null) || true
  if echo "$output" | grep -qF "invalid duration"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: negative stderr should contain 'invalid duration' got: $output"
  fi
}
