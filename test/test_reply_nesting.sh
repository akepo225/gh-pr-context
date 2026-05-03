#!/usr/bin/env bash

ORIGINAL_PATH="$HOME/bin:$PATH"

# setup_mocks_base creates a temporary mock directory and installs an executable mock `git` that returns a fixed repo URL for `remote get-url origin` and a fixed branch for `rev-parse --abbrev-ref HEAD`, exiting with status 1 for any other invocation.
setup_mocks_base() {
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/git" << 'GIT_EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin")       echo "https://github.com/acme/widgets.git" ;;
  "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
  *) exit 1 ;;
esac
GIT_EOF
  chmod +x "$mock_dir/git"
}

# setup_mocks_nesting creates a temporary mock environment (mock `git` and `gh` CLIs) and per-comment reply JSON fixtures for testing comment/reply nesting; it accepts `pr_reviews` and `pr_issues` JSON strings followed by zero or more `"<cid>:<json>"` reply_spec arguments and writes `replies_<cid>.json`, then installs a `gh` mock that returns the provided data for pulls/42/comments, issues/42/comments, and pulls/comments/<id>/replies.
setup_mocks_nesting() {
  local pr_reviews="$1"
  local pr_issues="$2"
  shift 2

  setup_mocks_base

  local reply_spec cid rdata
  for reply_spec in "$@"; do
    cid="${reply_spec%%:*}"
    rdata="${reply_spec#*:}"
    echo "$rdata" > "$mock_dir/replies_${cid}.json"
  done

  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42/comments"*)\n'                >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$pr_reviews"              >> "$mock_dir/gh"
  printf '    ;;\n'                                   >> "$mock_dir/gh"
  printf '  *"issues/42/comments"*)\n'               >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$pr_issues"               >> "$mock_dir/gh"
  printf '    ;;\n'                                   >> "$mock_dir/gh"
  printf '  *"pulls/comments/"*"/replies"*)\n'       >> "$mock_dir/gh"
  cat >> "$mock_dir/gh" << 'REPLY_MOCK'
    _cid=$(echo "$*" | sed -E 's/.*pulls\/comments\/([0-9]+)\/replies.*/\1/')
    _mdir=$(dirname "$0")
    if [ -f "${_mdir}/replies_${_cid}.json" ]; then
      cat "${_mdir}/replies_${_cid}.json"
    else
      echo "[]"
    fi
    ;;
REPLY_MOCK
  printf '  *) exit 1 ;;\n'                          >> "$mock_dir/gh"
  printf 'esac\n'                                    >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

# run_script executes the target script with the mock directory placed first in PATH, passing through all arguments.
run_script() {
  PATH="$mock_dir:$ORIGINAL_PATH" bash "$script" "$@"
}

# cleanup_mocks removes the temporary mock directory created for test mocks.
cleanup_mocks() {
  rm -rf "$mock_dir"
}

test_names+=(
  test_nesting_reply_block_present
  test_nesting_reply_appears_after_parent
  test_nesting_reply_uses_marker
  test_nesting_reply_contains_author_created_body
  test_nesting_in_reply_to_id_not_top_level
  test_nesting_no_replies_no_marker
  test_nesting_issue_comment_no_reply_marker
  test_nesting_multiple_parents_independent_replies
  test_nesting_reply_only_under_correct_parent
  test_nesting_replies_sorted_chronologically
  test_nesting_multiple_replies_under_one_parent
)

# test_nesting_reply_block_present verifies that a review comment with a nested reply produces a reply block containing the literal ">>> reply" marker.
# Mocks a single review comment and its reply, runs `comments --pr 42`, and increments the global `pass`/`fail` counters based on whether the marker appears in the output.
test_nesting_reply_block_present() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"}]'
  local reply='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"nested reply"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply block should contain '>>> reply' marker (output: $output)"
  fi
}

# test_nesting_reply_appears_after_parent verifies that the reply marker ">>> reply" appears after its parent review comment in the script output.
test_nesting_reply_appears_after_parent() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent comment"}]'
  local reply='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"nested reply"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local parent_line reply_line
  parent_line=$(echo "$output" | grep -n "body: parent comment" | cut -d: -f1)
  reply_line=$(echo "$output" | grep -n ">>> reply" | cut -d: -f1)
  if [ -n "$parent_line" ] && [ -n "$reply_line" ] && [ "$reply_line" -gt "$parent_line" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: >>> reply ($reply_line) should appear after parent ($parent_line) (output: $output)"
  fi
}

# test_nesting_reply_uses_marker verifies that a nested review reply is rendered with the ">>> reply" marker.
test_nesting_reply_uses_marker() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"p"}]'
  local reply='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"r"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: nested reply must use '>>> reply' prefix (output: $output)"
  fi
}

# test_nesting_reply_contains_author_created_body verifies that a reply's rendered block includes the `author`, `created`, and `body` fields.
test_nesting_reply_contains_author_created_body() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"p"}]'
  local reply='[{"user":{"login":"replyuser"},"created_at":"2025-06-01T08:00:00Z","body":"reply body text"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "author: replyuser" \
    && echo "$output" | grep -qF "created: 2025-06-01T08:00:00Z" \
    && echo "$output" | grep -qF "body: reply body text"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply block must contain author, created, and body fields (output: $output)"
  fi
}

# test_nesting_in_reply_to_id_not_top_level ensures a review comment that has an `in_reply_to_id` is not rendered as a top-level `review-comment` block when running `comments --pr 42`.
test_nesting_in_reply_to_id_not_top_level() {
  local review='[
    {"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"},
    {"id":11,"in_reply_to_id":10,"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","path":"a.sh","line":1,"body":"inline child"}
  ]'
  local reply='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"inline child"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local block_count
  block_count=$(echo "$output" | grep -c "^--- review-comment" || true)
  if [ "$block_count" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: comment with in_reply_to_id should not appear as top-level review-comment (blocks: $block_count, output: $output)"
  fi
}

# test_nesting_no_replies_no_marker verifies that a review comment without replies does not produce the ">>> reply" marker in the script output.
test_nesting_no_replies_no_marker() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"lone parent"}]'
  setup_mocks_nesting "$review" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if ! echo "$output" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: comment with no replies must not contain '>>> reply' (output: $output)"
  fi
}

# test_nesting_issue_comment_no_reply_marker verifies that issue-level comments are rendered without the '>>> reply' marker.
test_nesting_issue_comment_no_reply_marker() {
  local issue='[{"user":{"login":"carol"},"created_at":"2025-01-01T10:00:00Z","body":"issue-level comment"}]'
  setup_mocks_nesting '[]' "$issue"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "issue-comment" && ! echo "$output" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comments must never have '>>> reply' markers (output: $output)"
  fi
}

# test_nesting_multiple_parents_independent_replies verifies that two separate review comments each render their own independent replies and updates the global pass/fail counters.
test_nesting_multiple_parents_independent_replies() {
  local review='[
    {"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent A"},
    {"id":20,"user":{"login":"carol"},"created_at":"2025-01-01T12:00:00Z","path":"b.sh","line":2,"body":"parent B"}
  ]'
  local reply10='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"reply to A"}]'
  local reply20='[{"user":{"login":"dave"},"created_at":"2025-01-01T13:00:00Z","body":"reply to B"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply10" "20:$reply20"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "reply to A" && echo "$output" | grep -qF "reply to B"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: each parent must carry its own independent replies (output: $output)"
  fi
}

# test_nesting_reply_only_under_correct_parent verifies that a reply is rendered only under its corresponding parent review comment and not under other parent comment blocks.
test_nesting_reply_only_under_correct_parent() {
  local review='[
    {"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent A"},
    {"id":20,"user":{"login":"carol"},"created_at":"2025-01-01T12:00:00Z","path":"b.sh","line":2,"body":"parent B"}
  ]'
  local reply10='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"only for A"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply10"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local parent_b_section
  parent_b_section=$(echo "$output" | sed -n '/body: parent B/,/^---/p')
  if echo "$output" | grep -qF "only for A" && ! echo "$parent_b_section" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply should appear only under correct parent (output: $output)"
  fi
}

# test_nesting_replies_sorted_chronologically verifies that replies for a review comment are rendered in ascending order by `created_at`, so the oldest reply appears first.
test_nesting_replies_sorted_chronologically() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"}]'
  local replies='[
    {"user":{"login":"charlie"},"created_at":"2025-01-03T10:00:00Z","body":"third"},
    {"user":{"login":"bob"},"created_at":"2025-01-02T10:00:00Z","body":"second"},
    {"user":{"login":"alice"},"created_at":"2025-01-01T11:00:00Z","body":"first"}
  ]'
  setup_mocks_nesting "$review" '[]' "10:$replies"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local first_reply_body
  first_reply_body=$(echo "$output" | grep -A3 ">>> reply" | grep "body:" | head -1 | sed 's/body: //')
  if [ "$first_reply_body" = "first" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: replies must be sorted ascending by created_at, expected 'first', got: '$first_reply_body' (output: $output)"
  fi
}

# test_nesting_multiple_replies_under_one_parent verifies that two separate replies to a single review comment produce two distinct `>>> reply` markers in the script output.
test_nesting_multiple_replies_under_one_parent() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"}]'
  local replies='[
    {"user":{"login":"bob"},"created_at":"2025-01-02T10:00:00Z","body":"reply one"},
    {"user":{"login":"carol"},"created_at":"2025-01-03T10:00:00Z","body":"reply two"}
  ]'
  setup_mocks_nesting "$review" '[]' "10:$replies"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local reply_count
  reply_count=$(echo "$output" | grep -c ">>> reply" || true)
  if [ "$reply_count" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected 2 reply markers, got $reply_count (output: $output)"
  fi
}
