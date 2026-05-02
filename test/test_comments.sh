#!/usr/bin/env bash

ORIGINAL_PATH="$HOME/bin:$PATH"

setup_mocks() {
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/git" << 'GIT_EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
  "branch --show-current") echo "feature-branch" ;;
  "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
  *) exit 1 ;;
esac
GIT_EOF
  chmod +x "$mock_dir/git"
}

setup_mocks_with_pr() {
  local pr_reviews="$1"
  local pr_issues="$2"

  setup_mocks

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *\"pulls?head=acme:feature-branch\"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" '[{"number":42}]' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *\"pulls/42/comments\"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$pr_reviews" >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *\"issues/42/comments\"*)\n' >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$pr_issues" >> "$mock_dir/gh"
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
  test_comments_empty_pr_no_output
  test_comments_review_only
  test_comments_issue_only
  test_comments_sorted_by_date
  test_comments_review_has_path_and_line
  test_comments_issue_no_path_or_line
  test_comments_explicit_pr
  test_comments_exits_zero_on_success
  test_comments_multiline_body
  test_comments_multiple_review_sorted
)

test_comments_empty_pr_no_output() {
  setup_mocks_with_pr '[]' '[]'
  local output
  output=$(run_script comments --pr 42 2>&1) || true
  cleanup_mocks
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: empty PR should produce no output (got: $output)"
  fi
}

test_comments_review_only() {
  setup_mocks_with_pr '[{"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/main.sh","line":5,"body":"nit: use double quotes"}]' '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "review-comment" && echo "$output" | grep -qF "alice"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: review comment output missing expected fields"
  fi
}

test_comments_issue_only() {
  setup_mocks_with_pr '[]' '[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"looks good"}]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "issue-comment" && echo "$output" | grep -qF "bob"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comment output missing expected fields"
  fi
}

test_comments_sorted_by_date() {
  local review_json='[{"user":{"login":"alice"},"created_at":"2025-01-02T10:00:00Z","path":"a.sh","line":1,"body":"review later"}]'
  local issue_json='[{"user":{"login":"bob"},"created_at":"2025-01-01T10:00:00Z","body":"issue earlier"}]'
  setup_mocks_with_pr "$review_json" "$issue_json"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local first_author
  first_author=$(echo "$output" | grep -m1 "author:" | head -1 | sed 's/author: //')
  if [ "$first_author" = "bob" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected bob (issue comment) first, got: $first_author"
  fi
}

test_comments_review_has_path_and_line() {
  setup_mocks_with_pr '[{"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/main.sh","line":42,"body":"fix this"}]' '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -q "path: src/main.sh" && echo "$output" | grep -q "line: 42"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: review comment missing path/line fields"
  fi
}

test_comments_issue_no_path_or_line() {
  setup_mocks_with_pr '[]' '[{"user":{"login":"bob"},"created_at":"2025-01-01T10:00:00Z","body":"general comment"}]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -q "path:" || echo "$output" | grep -q "line:"; then
    fail=$((fail + 1))
    echo "FAIL: issue comment should not contain path or line fields"
  else
    pass=$((pass + 1))
  fi
}

test_comments_explicit_pr() {
  setup_mocks_with_pr '[]' '[{"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","body":"hello"}]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "alice"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: explicit --pr 42 should return comments"
  fi
}

test_comments_exits_zero_on_success() {
  setup_mocks_with_pr '[]' '[{"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","body":"ok"}]'
  assert_exit 0 "comments exits 0 on success" run_script comments --pr 42
  cleanup_mocks
}

test_comments_multiline_body() {
  setup_mocks_with_pr '[{"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"line one\nline two"}]' '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "line one" && echo "$output" | grep -qF "line two"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: multiline body not fully rendered (output: $output)"
  fi
}

test_comments_multiple_review_sorted() {
  local review_json='[{"user":{"login":"bob"},"created_at":"2025-01-03T10:00:00Z","path":"a.sh","line":1,"body":"later"},{"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"b.sh","line":2,"body":"earlier"}]'
  setup_mocks_with_pr "$review_json" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local first_author
  first_author=$(echo "$output" | grep -m1 "author:" | head -1 | sed 's/author: //')
  if [ "$first_author" = "alice" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected alice (earlier) first, got: $first_author"
  fi
}
