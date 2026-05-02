#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
script="$repo_root/gh-pr-context"

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

assert_output_contains() {
  local desc=$1 needle=$2; shift 2
  local actual_exit=0 output
  output=$("$@" 2>&1) || actual_exit=$?
  if echo "$output" | grep -qF "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $desc (output did not contain: $needle)"
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

for test_file in "$script_dir"/test_*.sh; do
  [ -f "$test_file" ] || continue
  echo "--- $(basename "$test_file")"
  test_names=()
  # shellcheck source=/dev/null
  source "$test_file"
  for t in "${test_names[@]}"; do
    "$t"
  done
done

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
