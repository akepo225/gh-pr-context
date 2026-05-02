#!/usr/bin/env bash

ORIGINAL_PATH="$HOME/bin:$PATH"

KNOWN_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
UNKNOWN_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
MOCK_HEAD_TS="2025-06-01T10:00:00Z"
MOCK_SHA_TS="2025-06-15T12:00:00Z"
MOCK_HEAD_EPOCH="1748772000"
MOCK_SHA_EPOCH="1749988800"

setup_mocks() {
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/git" << GIT_EOF
#!/usr/bin/env bash
case "\$*" in
  "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
  "branch --show-current") echo "feature-branch" ;;
  "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
  "log -1 --format=%ct HEAD") echo "$MOCK_HEAD_EPOCH" ;;
  "log -1 --format=%ct $KNOWN_SHA") echo "$MOCK_SHA_EPOCH" ;;
  "log -1 --format=%ct $UNKNOWN_SHA") exit 1 ;;
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
  printf '  *\"pulls/comments/\"*\"/replies\"*)\n' >> "$mock_dir/gh"
  printf '    echo "[]"\n' >> "$mock_dir/gh"
  printf '    ;;\n' >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n' >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

setup_mocks_with_pr_and_replies() {
  local pr_reviews="$1"
  local pr_issues="$2"
  shift 2

  setup_mocks

  local reply_spec cid rdata
  for reply_spec in "$@"; do
    cid="${reply_spec%%:*}"
    rdata="${reply_spec#*:}"
    echo "$rdata" > "$mock_dir/replies_${cid}.json"
  done

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
  printf '  *\"pulls/comments/\"*\"/replies\"*)\n' >> "$mock_dir/gh"
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
  test_comments_review_with_replies
  test_comments_review_no_replies
  test_comments_mixed_replies
  test_comments_issue_stays_flat
  test_comments_replies_sorted_under_parent
  test_comments_reply_in_main_response_not_duplicated
  test_since_last_commit_filters_old
  test_since_date_filters_old
  test_since_datetime_filters_old
  test_since_sha_filters_old
  test_since_no_filter_returns_all
  test_since_all_overrides_since
  test_since_last_commit_includes_equal
  test_since_filters_replies_too
  test_since_unknown_sha_exits_nonzero
  test_since_unknown_sha_stderr_message
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

test_comments_review_with_replies() {
  local review_json='[{"id":101,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/main.sh","line":5,"body":"nit: use double quotes"}]'
  local replies_data='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"done, fixed"}]'
  setup_mocks_with_pr_and_replies "$review_json" '[]' "101:$replies_data"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
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

test_comments_review_no_replies() {
  local review_json='[{"id":101,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/main.sh","line":5,"body":"nit: use double quotes"}]'
  setup_mocks_with_pr_and_replies "$review_json" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "review-comment" && ! echo "$output" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: review comment without replies should not have >>> reply (output: $output)"
  fi
}

test_comments_mixed_replies() {
  local review_json='[{"id":101,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"has replies"},{"id":102,"user":{"login":"carol"},"created_at":"2025-01-01T09:00:00Z","path":"b.sh","line":2,"body":"no replies"}]'
  local replies_data='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"reply here"}]'
  setup_mocks_with_pr_and_replies "$review_json" '[]' "101:$replies_data"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local alice_block carol_block
  alice_block=$(echo "$output" | sed -n '/author: alice/,/^---/p')
  carol_block=$(echo "$output" | sed -n '/author: carol/,/^---/p')
  if echo "$alice_block" | grep -qF ">>> reply" \
    && ! echo "$carol_block" | grep -qF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: mixed replies - only alice should have >>> reply (output: $output)"
  fi
}

test_comments_issue_stays_flat() {
  local review_json='[{"id":101,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"review"}]'
  local issue_json='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"issue comment"}]'
  local replies_data='[{"user":{"login":"carol"},"created_at":"2025-01-01T12:00:00Z","body":"a reply"}]'
  setup_mocks_with_pr_and_replies "$review_json" "$issue_json" "101:$replies_data"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
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

test_comments_replies_sorted_under_parent() {
  local review_json='[{"id":101,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"}]'
  local replies_data='[{"user":{"login":"carol"},"created_at":"2025-01-01T12:00:00Z","body":"later reply"},{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"earlier reply"}]'
  setup_mocks_with_pr_and_replies "$review_json" '[]' "101:$replies_data"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local first_reply_author
  first_reply_author=$(echo "$output" | grep -A1 ">>> reply" | grep "author:" | head -1 | sed 's/.*author: //')
  if [ "$first_reply_author" = "bob" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: replies should be sorted by created_at, expected bob first, got: $first_reply_author (output: $output)"
  fi
}

test_comments_reply_in_main_response_not_duplicated() {
  local review_json='[{"id":101,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"},{"id":102,"in_reply_to_id":101,"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","path":"a.sh","line":1,"body":"inline reply"}]'
  local replies_data='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"inline reply"}]'
  setup_mocks_with_pr_and_replies "$review_json" '[]' "101:$replies_data"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local reply_count
  reply_count=$(echo "$output" | grep -cF ">>> reply" || true)
  if [ "$reply_count" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply should appear exactly once, got $reply_count occurrences (output: $output)"
  fi
}

test_since_last_commit_filters_old() {
  local review_json='[{"user":{"login":"alice"},"created_at":"2025-05-01T09:00:00Z","path":"a.sh","line":1,"body":"old comment"},{"user":{"login":"bob"},"created_at":"2025-07-01T10:00:00Z","path":"b.sh","line":2,"body":"new comment"}]'
  local issue_json='[{"user":{"login":"carol"},"created_at":"2025-06-01T10:00:00Z","body":"exact match"}]'
  setup_mocks_with_pr "$review_json" "$issue_json"
  local output
  output=$(run_script comments --pr 42 --since last-commit 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "bob" \
    && echo "$output" | grep -qF "carol" \
    && ! echo "$output" | grep -qF "alice"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since last-commit should filter old comments (output: $output)"
  fi
}

test_since_date_filters_old() {
  local review_json='[{"user":{"login":"alice"},"created_at":"2025-05-15T23:59:59Z","path":"a.sh","line":1,"body":"before date"},{"user":{"login":"bob"},"created_at":"2025-06-01T00:00:00Z","path":"b.sh","line":2,"body":"on date"}]'
  local issue_json='[{"user":{"login":"carol"},"created_at":"2025-06-15T12:00:00Z","body":"after date"}]'
  setup_mocks_with_pr "$review_json" "$issue_json"
  local output
  output=$(run_script comments --pr 42 --since 2025-06-01 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "bob" \
    && echo "$output" | grep -qF "carol" \
    && ! echo "$output" | grep -qF "alice"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since 2025-06-01 should filter comments before that date (output: $output)"
  fi
}

test_since_datetime_filters_old() {
  local review_json='[{"user":{"login":"alice"},"created_at":"2025-06-01T09:59:59Z","path":"a.sh","line":1,"body":"before datetime"},{"user":{"login":"bob"},"created_at":"2025-06-01T10:00:00Z","path":"b.sh","line":2,"body":"exact datetime"}]'
  local issue_json='[{"user":{"login":"carol"},"created_at":"2025-06-01T12:00:00Z","body":"after datetime"}]'
  setup_mocks_with_pr "$review_json" "$issue_json"
  local output
  output=$(run_script comments --pr 42 --since 2025-06-01T10:00:00 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "bob" \
    && echo "$output" | grep -qF "carol" \
    && ! echo "$output" | grep -qF "alice"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since 2025-06-01T10:00:00 should filter comments before that datetime (output: $output)"
  fi
}

test_since_sha_filters_old() {
  local review_json='[{"user":{"login":"alice"},"created_at":"2025-06-10T09:00:00Z","path":"a.sh","line":1,"body":"before sha"},{"user":{"login":"bob"},"created_at":"2025-06-20T10:00:00Z","path":"b.sh","line":2,"body":"after sha"}]'
  local issue_json='[{"user":{"login":"carol"},"created_at":"2025-06-15T12:00:00Z","body":"exact sha ts"}]'
  setup_mocks_with_pr "$review_json" "$issue_json"
  local output
  output=$(run_script comments --pr 42 --since "$KNOWN_SHA" 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "bob" \
    && echo "$output" | grep -qF "carol" \
    && ! echo "$output" | grep -qF "alice"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since <SHA> should filter comments before SHA timestamp (output: $output)"
  fi
}

test_since_no_filter_returns_all() {
  local review_json='[{"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"old"},{"user":{"login":"bob"},"created_at":"2025-12-01T10:00:00Z","path":"b.sh","line":2,"body":"new"}]'
  local issue_json='[{"user":{"login":"carol"},"created_at":"2025-06-01T10:00:00Z","body":"mid"}]'
  setup_mocks_with_pr "$review_json" "$issue_json"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "alice" \
    && echo "$output" | grep -qF "bob" \
    && echo "$output" | grep -qF "carol"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: without --since all comments should be returned (output: $output)"
  fi
}

test_since_all_overrides_since() {
  local review_json='[{"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"old"},{"user":{"login":"bob"},"created_at":"2025-12-01T10:00:00Z","path":"b.sh","line":2,"body":"new"}]'
  local issue_json='[{"user":{"login":"carol"},"created_at":"2025-06-01T10:00:00Z","body":"mid"}]'
  setup_mocks_with_pr "$review_json" "$issue_json"
  local output
  output=$(run_script comments --pr 42 --all --since 2025-12-01T00:00:00 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "alice" \
    && echo "$output" | grep -qF "bob" \
    && echo "$output" | grep -qF "carol"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --all should override --since and return all comments (output: $output)"
  fi
}

test_since_last_commit_includes_equal() {
  local issue_json="[{\"user\":{\"login\":\"alice\"},\"created_at\":\"$MOCK_HEAD_TS\",\"body\":\"exactly at HEAD ts\"}]"
  setup_mocks_with_pr '[]' "$issue_json"
  local output
  output=$(run_script comments --pr 42 --since last-commit 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "alice"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since should include comments at exact timestamp (output: $output)"
  fi
}

test_since_filters_replies_too() {
  local review_json='[{"id":101,"user":{"login":"alice"},"created_at":"2025-07-01T10:00:00Z","path":"a.sh","line":1,"body":"new parent"}]'
  local replies_data='[{"user":{"login":"bob"},"created_at":"2025-05-01T10:00:00Z","body":"old reply"},{"user":{"login":"carol"},"created_at":"2025-08-01T10:00:00Z","body":"new reply"}]'
  setup_mocks_with_pr_and_replies "$review_json" '[]' "101:$replies_data"
  local output
  output=$(run_script comments --pr 42 --since 2025-06-01T00:00:00 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "carol" \
    && ! echo "$output" | grep -qF "old reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since should filter replies too (output: $output)"
  fi
}

test_since_unknown_sha_exits_nonzero() {
  setup_mocks_with_pr '[]' '[]'
  local exit_code=0
  run_script comments --pr 42 --since "$UNKNOWN_SHA" >/dev/null 2>&1 || exit_code=$?
  cleanup_mocks
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since with unknown SHA should exit non-zero"
  fi
}

test_since_unknown_sha_stderr_message() {
  setup_mocks_with_pr '[]' '[]'
  local output
  output=$(run_script comments --pr 42 --since "$UNKNOWN_SHA" 2>&1) || true
  cleanup_mocks
  if echo "$output" | grep -qF "unknown commit"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since with unknown SHA should mention unknown commit (output: $output)"
  fi
}
