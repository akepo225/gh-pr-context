#!/usr/bin/env bash

# setup_mocks_base defines test mocks for `git` and `gh`; `git` returns fixed values for repository URL and branch name for specific queries, and `gh` exits nonzero for any invocation.
setup_mocks_base() {
  git() {
    case "$*" in
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) exit 1 ;;
    esac
  }
  gh() {
    exit 1
  }
}

_MOCK_REPLY_IDS=""

# _clear_reply_vars unsets all per-reply `_MOCK_REPLY_<id>` variables and clears the `_MOCK_REPLY_IDS` list.
_clear_reply_vars() {
  for cid in $_MOCK_REPLY_IDS; do
    unset "_MOCK_REPLY_${cid}" 2>/dev/null || true
  done
  _MOCK_REPLY_IDS=""
}

# setup_mocks_nesting sets up shell mocks and exports mock PR review, issue, and per-comment reply data used by nesting tests.
# The first argument is PR review JSON, the second is issue comment JSON, and remaining arguments are reply specs of the form `cid:rdata` which are exported as `_MOCK_REPLY_<cid>`.
setup_mocks_nesting() {
  _MOCK_PR_REVIEWS="$1"
  _MOCK_PR_ISSUES="$2"
  shift 2

  setup_mocks_base
  _clear_reply_vars

  local reply_spec cid rdata
  for reply_spec in "$@"; do
    cid="${reply_spec%%:*}"
    rdata="${reply_spec#*:}"
    export "_MOCK_REPLY_${cid}=$rdata"
    _MOCK_REPLY_IDS="$_MOCK_REPLY_IDS $cid"
  done

  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo "$_MOCK_PR_REVIEWS" ;;
      *"issues/42/comments"*) echo "$_MOCK_PR_ISSUES" ;;
      *"pulls/comments/"*"/replies"*)
        local cid
        cid=$(echo "$*" | sed -E 's/.*pulls\/comments\/([0-9]+)\/replies.*/\1/')
        local var="_MOCK_REPLY_${cid}"
        echo "${!var:-[]}"
        ;;
      *) exit 1 ;;
    esac
  }
}

# run_script exports mock git/gh functions and mock data variables, then invokes the target script with any provided arguments.
run_script() {
  export -f git gh
  export _MOCK_PR_REVIEWS _MOCK_PR_ISSUES
  # _MOCK_REPLY_* vars are exported by setup_mocks_nesting
  bash "$script" "$@"
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

# test_nesting_reply_block_present verifies that when a PR review comment has a nested reply, the script output includes the ">>> reply" marker.
test_nesting_reply_block_present() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"}]'
  local reply='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"nested reply"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  if echo "$output" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply block should contain '>>> reply' marker (output: $output)"
  fi
}

test_nesting_reply_appears_after_parent() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent comment"}]'
  local reply='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"nested reply"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
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

# test_nesting_reply_uses_marker verifies that a nested reply is rendered with the '>>> reply' marker in the script output.
# Sets up one review and one reply, runs the script for the PR, and passes only if the output contains ">>> reply".
test_nesting_reply_uses_marker() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"p"}]'
  local reply='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"r"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  if echo "$output" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: nested reply must use '>>> reply' prefix (output: $output)"
  fi
}

test_nesting_reply_contains_author_created_body() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"p"}]'
  local reply='[{"user":{"login":"replyuser"},"created_at":"2025-06-01T08:00:00Z","body":"reply body text"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  if echo "$output" | grep -qF "author: replyuser" \
    && echo "$output" | grep -qF "created: 2025-06-01T08:00:00Z" \
    && echo "$output" | grep -qF "body: reply body text"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply block must contain author, created, and body fields (output: $output)"
  fi
}

# test_nesting_in_reply_to_id_not_top_level ensures a review comment with `in_reply_to_id` is treated as a child and does not produce a separate top-level `review-comment` block in the script output.
test_nesting_in_reply_to_id_not_top_level() {
  local review='[
    {"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"},
    {"id":11,"in_reply_to_id":10,"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","path":"a.sh","line":1,"body":"inline child"}
  ]'
  local reply='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"inline child"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  local block_count
  block_count=$(echo "$output" | grep -c "^--- review-comment" || true)
  if [ "$block_count" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: comment with in_reply_to_id should not appear as top-level review-comment (blocks: $block_count, output: $output)"
  fi
}

# test_nesting_no_replies_no_marker checks that a single review comment with no replies does not produce the reply marker '>>> reply' in the script output.
test_nesting_no_replies_no_marker() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"lone parent"}]'
  setup_mocks_nesting "$review" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  if ! echo "$output" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: comment with no replies must not contain '>>> reply' (output: $output)"
  fi
}

# test_nesting_issue_comment_no_reply_marker verifies that issue-level comments are shown as `issue-comment` and never include the `>>> reply` marker.
test_nesting_issue_comment_no_reply_marker() {
  local issue='[{"user":{"login":"carol"},"created_at":"2025-01-01T10:00:00Z","body":"issue-level comment"}]'
  setup_mocks_nesting '[]' "$issue"
  local output
  output=$(run_script comments --pr 42 2>&1)
  if echo "$output" | grep -qF "issue-comment" && ! echo "$output" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comments must never have '>>> reply' markers (output: $output)"
  fi
}

# test_nesting_multiple_parents_independent_replies verifies that two separate review comments each include their own replies by asserting the output contains both reply bodies.
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
  if echo "$output" | grep -qF "reply to A" && echo "$output" | grep -qF "reply to B"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: each parent must carry its own independent replies (output: $output)"
  fi
}

# test_nesting_reply_only_under_correct_parent verifies that a reply is rendered only beneath its matching parent review comment and not under other review comments.
test_nesting_reply_only_under_correct_parent() {
  local review='[
    {"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent A"},
    {"id":20,"user":{"login":"carol"},"created_at":"2025-01-01T12:00:00Z","path":"b.sh","line":2,"body":"parent B"}
  ]'
  local reply10='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"only for A"}]'
  setup_mocks_nesting "$review" '[]' "10:$reply10"
  local output
  output=$(run_script comments --pr 42 2>&1)
  local parent_b_section
  parent_b_section=$(echo "$output" | sed -n '/body: parent B/,/^---/p')
  if echo "$output" | grep -qF "only for A" && ! echo "$parent_b_section" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply should appear only under correct parent (output: $output)"
  fi
}

# test_nesting_replies_sorted_chronologically verifies that replies attached to a review are emitted in ascending order by `created_at` (earliest reply appears first).
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
  local first_reply_body
  first_reply_body=$(echo "$output" | grep -A3 ">>> reply" | grep "body:" | head -1 | sed 's/body: //')
  if [ "$first_reply_body" = "first" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: replies must be sorted ascending by created_at, expected 'first', got: '$first_reply_body' (output: $output)"
  fi
}

# test_nesting_multiple_replies_under_one_parent verifies that two reply blocks are rendered under a single parent review comment; increments `pass` if exactly two `>>> reply` markers are found, otherwise increments `fail` and prints a FAIL message with the captured output.
test_nesting_multiple_replies_under_one_parent() {
  local review='[{"id":10,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"}]'
  local replies='[
    {"user":{"login":"bob"},"created_at":"2025-01-02T10:00:00Z","body":"reply one"},
    {"user":{"login":"carol"},"created_at":"2025-01-03T10:00:00Z","body":"reply two"}
  ]'
  setup_mocks_nesting "$review" '[]' "10:$replies"
  local output
  output=$(run_script comments --pr 42 2>&1)
  local reply_count
  reply_count=$(echo "$output" | grep -c ">>> reply" || true)
  if [ "$reply_count" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected 2 reply markers, got $reply_count (output: $output)"
  fi
}
