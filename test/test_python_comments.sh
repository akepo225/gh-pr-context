#!/usr/bin/env bash

# Python comments command tests using mock executables via GH_PR_CONTEXT_GH/GIT env vars.

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
python_script="$repo_root/gh-pr-context.py"
if command -v py >/dev/null 2>&1; then
  python_cmd="py -3"
else
  python_cmd="python3"
fi

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

setup_mock_dir() {
  _MOCK_DIR=$(mktemp -d)
}

cleanup_mock_dir() {
  if [ -n "$_MOCK_DIR" ] && [ -d "$_MOCK_DIR" ]; then
    rm -rf "$_MOCK_DIR"
  fi
}

write_git_mock() {
  cat > "$_MOCK_DIR/git" << 'GIT_EOF'
#!/usr/bin/env bash
case "$*" in
  "rev-parse --git-dir") echo ".git" ;;
  "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
  "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
  *) exit 1 ;;
esac
GIT_EOF
  chmod +x "$_MOCK_DIR/git"
}

# Write gh mock. $1 = body of case statement
write_gh_mock() {
  local body="$1"
  cat > "$_MOCK_DIR/gh" << GHSCRIPT
#!/usr/bin/env bash
case "\$*" in
  $body
  *) exit 1 ;;
esac
GHSCRIPT
  chmod +x "$_MOCK_DIR/gh"
}

run_python() {
  if command -v cygpath >/dev/null 2>&1; then
    # Windows: Python's subprocess.run("bash") resolves to WSL bash, not Git Bash.
    # Use the full path to Git Bash with forward-slash Windows paths for the mocks.
    local git_bash='"C:/Program Files/Git/usr/bin/bash.exe"'
    local git_mock="$git_bash $(cygpath -m "$_MOCK_DIR/git")"
    local gh_mock="$git_bash $(cygpath -m "$_MOCK_DIR/gh")"
  else
    # Linux: mock scripts can be executed directly by bash
    local git_mock="bash $_MOCK_DIR/git"
    local gh_mock="bash $_MOCK_DIR/gh"
  fi
  GH_PR_CONTEXT_GIT="$git_mock" GH_PR_CONTEXT_GH="$gh_mock" \
    $python_cmd "$python_script" "$@"
}

# --- Tests ---

test_py_comments_empty_pr_no_output() {
  setup_mock_dir
  write_git_mock
  write_gh_mock '
    *"pulls/42/comments"*) echo '"'"'[]'"'"' ;;
    *"issues/42/comments"*) echo '"'"'[]'"'"' ;;'
  local output
  output=$(run_python comments --pr 42 2>&1) || true
  cleanup_mock_dir
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: empty PR should produce no output (got: $output)"
  fi
}

test_py_comments_review_only() {
  setup_mock_dir
  write_git_mock
  write_gh_mock '
    *"pulls/42/comments"*) echo '"'"'[{"id":1,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/main.sh","line":5,"body":"nit: use double quotes"}]'"'"' ;;
    *"issues/42/comments"*) echo '"'"'[]'"'"' ;;
    *"pulls/comments/"*"/replies"*) echo '"'"'[]'"'"' ;;'
  local output
  output=$(run_python comments --pr 42 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "review-comment" && echo "$output" | grep -qF "alice"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: review comment output missing expected fields (output: $output)"
  fi
}

test_py_comments_issue_only() {
  setup_mock_dir
  write_git_mock
  write_gh_mock '
    *"pulls/42/comments"*) echo '"'"'[]'"'"' ;;
    *"issues/42/comments"*) echo '"'"'[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"looks good"}]'"'"' ;;
    *"pulls/comments/"*"/replies"*) echo '"'"'[]'"'"' ;;'
  local output
  output=$(run_python comments --pr 42 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "issue-comment" && echo "$output" | grep -qF "bob"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comment output missing expected fields (output: $output)"
  fi
}

test_py_comments_sorted_by_date() {
  setup_mock_dir
  write_git_mock
  local review_json='[{"id":2,"user":{"login":"alice"},"created_at":"2025-01-02T10:00:00Z","path":"a.sh","line":1,"body":"review later"}]'
  local issue_json='[{"user":{"login":"bob"},"created_at":"2025-01-01T10:00:00Z","body":"issue earlier"}]'
  write_gh_mock "
    *\"pulls/42/comments\"*) echo '$review_json' ;;
    *\"issues/42/comments\"*) echo '$issue_json' ;;
    *\"pulls/comments/\"*\"/replies\"*) echo '[]' ;;"
  local output
  output=$(run_python comments --pr 42 2>&1)
  cleanup_mock_dir
  local first_author
  first_author=$(echo "$output" | grep -m1 "author:" | head -1 | sed 's/author: //')
  if [ "$first_author" = "bob" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected bob (issue comment) first, got: $first_author (output: $output)"
  fi
}

test_py_comments_review_with_replies() {
  setup_mock_dir
  write_git_mock
  local review_json='[{"id":101,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/main.sh","line":5,"body":"nit: use double quotes"},{"id":201,"in_reply_to_id":101,"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","path":"src/main.sh","line":5,"body":"done, fixed"}]'
  write_gh_mock "
    *\"pulls/42/comments\"*) echo '$review_json' ;;
    *\"issues/42/comments\"*) echo '[]' ;;
    *\"pulls/comments/\"*\"/replies\"*) echo '[]' ;;"
  local output
  output=$(run_python comments --pr 42 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF ">>> reply" \
    && echo "$output" | grep -qF "author: bob" \
    && echo "$output" | grep -qF "body: done, fixed" \
    && echo "$output" | grep -qF "created: 2025-01-01T11:00:00Z"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: review comment with replies missing >>> reply block (output: $output)"
  fi
}

test_py_comments_issue_stays_flat() {
  setup_mock_dir
  write_git_mock
  local review_json='[{"id":101,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"review"},{"id":201,"in_reply_to_id":101,"user":{"login":"carol"},"created_at":"2025-01-01T12:00:00Z","path":"a.sh","line":1,"body":"a reply"}]'
  local issue_json='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"issue comment"}]'
  write_gh_mock "
    *\"pulls/42/comments\"*) echo '$review_json' ;;
    *\"issues/42/comments\"*) echo '$issue_json' ;;
    *\"pulls/comments/\"*\"/replies\"*) echo '[]' ;;"
  local output
  output=$(run_python comments --pr 42 2>&1)
  cleanup_mock_dir
  local issue_block
  issue_block=$(echo "$output" | sed -n '/--- issue-comment/,/^---/p')
  if echo "$issue_block" | grep -qF "bob" \
    && ! echo "$issue_block" | grep -qF ">>>"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comments should not have >>> markers (output: $output)"
  fi
}

test_py_comments_review_no_replies() {
  setup_mock_dir
  write_git_mock
  local review_json='[{"id":101,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/main.sh","line":5,"body":"nit: use double quotes"}]'
  write_gh_mock "
    *\"pulls/42/comments\"*) echo '$review_json' ;;
    *\"issues/42/comments\"*) echo '[]' ;;
    *\"pulls/comments/\"*\"/replies\"*) echo '[]' ;;"
  local output
  output=$(run_python comments --pr 42 2>&1)
  cleanup_mock_dir
  if echo "$output" | grep -qF "review-comment" && ! echo "$output" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: review comment without replies should not have >>> reply (output: $output)"
  fi
}

test_py_comments_exits_zero_on_success() {
  setup_mock_dir
  write_git_mock
  write_gh_mock '
    *"pulls/42/comments"*) echo '"'"'[{"id":1,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"ok"}]'"'"' ;;
    *"issues/42/comments"*) echo '"'"'[]'"'"' ;;
    *"pulls/comments/"*"/replies"*) echo '"'"'[]'"'"' ;;'
  assert_exit 0 "comments exits 0 on success" run_python comments --pr 42
  cleanup_mock_dir
}

test_py_comments_help_exits_zero() {
  setup_mock_dir
  write_git_mock
  write_gh_mock '*) exit 1 ;;'
  assert_exit 0 "comments --help exits 0" run_python comments --help
  assert_exit 0 "comments -h exits 0" run_python comments -h
  cleanup_mock_dir
}

test_py_comments_unknown_option_exits_nonzero() {
  setup_mock_dir
  write_git_mock
  write_gh_mock '*) exit 1 ;;'
  local exit_code=0
  run_python comments --pr 42 --bogus >/dev/null 2>&1 || exit_code=$?
  cleanup_mock_dir
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: unknown option should exit non-zero"
  fi
}

test_py_comments_missing_pr_value() {
  assert_stderr_contains "comments --pr without value gives clear message" "missing value for --pr" $python_cmd "$python_script" comments --pr
}

# --- Run tests ---
test_names=(
  test_py_comments_empty_pr_no_output
  test_py_comments_review_only
  test_py_comments_issue_only
  test_py_comments_sorted_by_date
  test_py_comments_review_with_replies
  test_py_comments_issue_stays_flat
  test_py_comments_review_no_replies
  test_py_comments_exits_zero_on_success
  test_py_comments_help_exits_zero
  test_py_comments_unknown_option_exits_nonzero
  test_py_comments_missing_pr_value
)

echo "--- test_python_comments.sh"
for t in "${test_names[@]}"; do
  "$t"
done

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
