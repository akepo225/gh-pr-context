#!/usr/bin/env bash

ORIGINAL_PATH="$HOME/bin:$PATH"

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# setup_mocks_base creates a temporary mock directory and installs a minimal git mock that returns a fixed remote URL and branch name.
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

# setup_mocks_comments creates a mock `gh` in $mock_dir (calls setup_mocks_base) that echoes the provided JSON for `pulls/42/comments` and `issues/42/comments` and returns `[]` for `pulls/comments/*/replies`; parameters: `pr_reviews` — JSON to echo for `pulls/42/comments`, `pr_issues` — JSON to echo for `issues/42/comments`.
setup_mocks_comments() {
  local pr_reviews="$1" pr_issues="$2"
  setup_mocks_base
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42/comments"*)\n'   >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$pr_reviews" >> "$mock_dir/gh"
  printf '    ;;\n'                      >> "$mock_dir/gh"
  printf '  *"issues/42/comments"*)\n'  >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$pr_issues"  >> "$mock_dir/gh"
  printf '    ;;\n'                      >> "$mock_dir/gh"
  printf '  *"pulls/comments/"*"/replies"*)\n' >> "$mock_dir/gh"
  printf '    echo "[]"\n'              >> "$mock_dir/gh"
  printf '    ;;\n'                     >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'            >> "$mock_dir/gh"
  printf 'esac\n'                      >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

# setup_mocks_comments_with_reply creates a temporary mock environment, writes the provided reply JSON to replies_77.json, and installs a mock `gh` that returns the given PR review comments, empty issue comments, and serves per-comment reply JSON (by comment id) for tests.
setup_mocks_comments_with_reply() {
  local pr_reviews="$1" reply_json="$2"
  setup_mocks_base
  echo "$reply_json" > "$mock_dir/replies_77.json"
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42/comments"*)\n'   >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$pr_reviews" >> "$mock_dir/gh"
  printf '    ;;\n'                      >> "$mock_dir/gh"
  printf '  *"issues/42/comments"*)\n'  >> "$mock_dir/gh"
  printf "    echo '[]'\n"              >> "$mock_dir/gh"
  printf '    ;;\n'                      >> "$mock_dir/gh"
  printf '  *"pulls/comments/"*"/replies"*)\n' >> "$mock_dir/gh"
  cat >> "$mock_dir/gh" << 'RMOCK'
    _cid=$(echo "$*" | sed -E 's/.*pulls\/comments\/([0-9]+)\/replies.*/\1/')
    _d=$(dirname "$0")
    [ -f "${_d}/replies_${_cid}.json" ] && cat "${_d}/replies_${_cid}.json" || echo "[]"
    ;;
RMOCK
  printf '  *) exit 1 ;;\n' >> "$mock_dir/gh"
  printf 'esac\n'           >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

# setup_mocks_status creates a temporary mock environment and writes a mock `gh` executable that returns the fixed HEAD SHA for `pulls/42` and echoes the provided `check_runs` JSON when invoked with `check-runs`.
setup_mocks_status() {
  local check_runs="$1"
  setup_mocks_base
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42"*)\n'                   >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$HEAD_SHA"          >> "$mock_dir/gh"
  printf '    ;;\n'                             >> "$mock_dir/gh"
  printf '  *"check-runs"*)\n'                 >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$check_runs"        >> "$mock_dir/gh"
  printf '    ;;\n'                             >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'                    >> "$mock_dir/gh"
  printf 'esac\n'                              >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

# setup_mocks_logs creates a temporary mock directory and an executable `gh` that returns the fixed HEAD_SHA for `pulls/42`, the provided `check_runs` JSON for check-run queries, and the given `log_content` for `logs` requests.
setup_mocks_logs() {
  local check_runs="$1" log_content="$2"
  setup_mocks_base
  printf '#!/usr/bin/env bash\ncase "$*" in\n' > "$mock_dir/gh"
  printf '  *"pulls/42"*)\n'                   >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$HEAD_SHA"          >> "$mock_dir/gh"
  printf '    ;;\n'                             >> "$mock_dir/gh"
  printf '  *"check-runs"*)\n'                 >> "$mock_dir/gh"
  printf "    echo '%s'\n" "$check_runs"        >> "$mock_dir/gh"
  printf '    ;;\n'                             >> "$mock_dir/gh"
  printf '  *"logs"*)\n'                        >> "$mock_dir/gh"
  printf "    printf '%%s' '%s'\n" "$log_content" >> "$mock_dir/gh"
  printf '    ;;\n'                             >> "$mock_dir/gh"
  printf '  *) exit 1 ;;\n'                    >> "$mock_dir/gh"
  printf 'esac\n'                              >> "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
}

# run_script runs the target script with the mock directory prepended to PATH so the mock executables override real tools.
run_script() {
  PATH="$mock_dir:$ORIGINAL_PATH" bash "$script" "$@"
}

# cleanup_mocks removes the temporary mock directory used for test mocks.
cleanup_mocks() {
  rm -rf "$mock_dir"
}

test_names+=(
  test_fmt_review_comment_delimiter
  test_fmt_review_comment_field_order
  test_fmt_review_comment_no_raw_json
  test_fmt_review_comment_no_trailing_whitespace_on_fields
  test_fmt_issue_comment_delimiter
  test_fmt_issue_comment_fields_present
  test_fmt_issue_comment_no_path_line
  test_fmt_issue_comment_no_raw_json
  test_fmt_reply_marker
  test_fmt_reply_fields
  test_fmt_check_completed_delimiter_and_fields
  test_fmt_check_non_completed_no_conclusion_field
  test_fmt_check_no_raw_json
  test_fmt_log_delimiter_and_name
  test_fmt_log_no_raw_json
  test_fmt_empty_comments_produces_no_output
  test_fmt_empty_checks_produces_no_output
  test_fmt_all_passing_logs_no_output
)

# test_fmt_review_comment_delimiter verifies that formatted review comments begin with `--- review-comment` on a line by itself.
test_fmt_review_comment_delimiter() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/app.sh","line":5,"body":"fix this"}]'
  setup_mocks_comments "$review" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qxF -- "--- review-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: review comment must start with '--- review-comment' on its own line (output: $output)"
  fi
}

# test_fmt_review_comment_field_order tests that review comment fields appear in the order author→created→path→line→body in the formatted comments output.
test_fmt_review_comment_field_order() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/app.sh","line":5,"body":"fix this"}]'
  setup_mocks_comments "$review" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local author_n created_n path_n line_n body_n
  author_n=$(echo "$output"  | grep -n "^author:"  | head -1 | cut -d: -f1)
  created_n=$(echo "$output" | grep -n "^created:" | head -1 | cut -d: -f1)
  path_n=$(echo "$output"   | grep -n "^path:"    | head -1 | cut -d: -f1)
  line_n=$(echo "$output"   | grep -n "^line:"    | head -1 | cut -d: -f1)
  body_n=$(echo "$output"   | grep -n "^body:"    | head -1 | cut -d: -f1)
  if [ "$author_n" -lt "$created_n" ] \
    && [ "$created_n" -lt "$path_n" ] \
    && [ "$path_n" -lt "$line_n" ] \
    && [ "$line_n" -lt "$body_n" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: review comment fields must appear in order author→created→path→line→body (lines: $author_n $created_n $path_n $line_n $body_n)"
  fi
}

# test_fmt_review_comment_no_raw_json ensures formatted review comment output contains no raw JSON-like characters (`[`, `{`) at the start of any line.
test_fmt_review_comment_no_raw_json() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/app.sh","line":5,"body":"fix this"}]'
  setup_mocks_comments "$review" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if ! echo "$output" | grep -qP '^\s*[\[{]'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: raw JSON must not appear in output (output: $output)"
  fi
}

# test_fmt_review_comment_no_trailing_whitespace_on_fields checks that formatted field lines (author, created, path, line, body, name, status, conclusion) do not end with trailing whitespace.
test_fmt_review_comment_no_trailing_whitespace_on_fields() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/app.sh","line":5,"body":"fix this"}]'
  setup_mocks_comments "$review" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  local bad_lines
  bad_lines=$(echo "$output" | grep -P '^(author|created|path|line|body|name|status|conclusion):.*\s+$' || true)
  if [ -z "$bad_lines" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: field lines must not have trailing whitespace (bad lines: $bad_lines)"
  fi
}

# test_fmt_issue_comment_delimiter verifies that running `comments --pr` emits a line containing only `--- issue-comment` for issue comments.
test_fmt_issue_comment_delimiter() {
  local issue='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"looks good"}]'
  setup_mocks_comments '[]' "$issue"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qxF -- "--- issue-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comment must start with '--- issue-comment' on its own line (output: $output)"
  fi
}

# test_fmt_issue_comment_fields_present verifies that issue comment output contains `author`, `created`, and `body` fields.
test_fmt_issue_comment_fields_present() {
  local issue='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"hello world"}]'
  setup_mocks_comments '[]' "$issue"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "author: bob" \
    && echo "$output" | grep -qF "created: 2025-01-01T11:00:00Z" \
    && echo "$output" | grep -qF "body: hello world"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comment missing author/created/body (output: $output)"
  fi
}

# test_fmt_issue_comment_no_path_line ensures issue comment output contains no lines beginning with `path:` or `line:`.
test_fmt_issue_comment_no_path_line() {
  local issue='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"hello"}]'
  setup_mocks_comments '[]' "$issue"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if ! echo "$output" | grep -qE "^path:|^line:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comment must not contain path: or line: fields (output: $output)"
  fi
}

# test_fmt_issue_comment_no_raw_json verifies that issue comment output does not contain lines beginning with JSON delimiters (`[` or `{`), ensuring no raw JSON is printed.
test_fmt_issue_comment_no_raw_json() {
  local issue='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"hi"}]'
  setup_mocks_comments '[]' "$issue"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if ! echo "$output" | grep -qP '^\s*[\[{]'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: raw JSON must not appear in issue comment output (output: $output)"
  fi
}

# test_fmt_reply_marker verifies that a reply is rendered using exactly the line '>>> reply' on its own line.
test_fmt_reply_marker() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"}]'
  local reply='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"a reply"}]'
  setup_mocks_comments_with_reply "$review" "$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qxF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply must use exactly '>>> reply' marker on its own line (output: $output)"
  fi
}

# test_fmt_reply_fields verifies that a reply block in the formatted comments output includes `author`, `created`, and `body` fields.
test_fmt_reply_fields() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"}]'
  local reply='[{"user":{"login":"replyauthor"},"created_at":"2025-03-15T09:00:00Z","body":"the reply body"}]'
  setup_mocks_comments_with_reply "$review" "$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "author: replyauthor" \
    && echo "$output" | grep -qF "created: 2025-03-15T09:00:00Z" \
    && echo "$output" | grep -qF "body: the reply body"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply block must contain author, created, body fields (output: $output)"
  fi
}

# test_fmt_check_completed_delimiter_and_fields verifies that a completed check run produces a `--- check` delimiter and includes `name:`, `status: completed`, and `conclusion: success` in the formatter output.
test_fmt_check_completed_delimiter_and_fields() {
  local checks='{"total_count":1,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"}]}'
  setup_mocks_status "$checks"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qxF -- "--- check" \
    && echo "$output" | grep -qF "name: Build" \
    && echo "$output" | grep -qF "status: completed" \
    && echo "$output" | grep -qF "conclusion: success"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: completed check must have --- check delimiter + name/status/conclusion (output: $output)"
  fi
}

# test_fmt_check_non_completed_no_conclusion_field verifies that a non-completed check outputs its `status` and omits any `conclusion:` field.
test_fmt_check_non_completed_no_conclusion_field() {
  local checks='{"total_count":1,"check_runs":[{"name":"Lint","status":"queued","conclusion":null}]}'
  setup_mocks_status "$checks"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qF "status: queued" && ! echo "$output" | grep -qF "conclusion:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: non-completed check must omit conclusion field (output: $output)"
  fi
}

# test_fmt_check_no_raw_json asserts that the `status --pr` output contains no lines beginning with raw JSON characters (`[` or `{`).
test_fmt_check_no_raw_json() {
  local checks='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"failure"}]}'
  setup_mocks_status "$checks"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  if ! echo "$output" | grep -qP '^\s*[\[{]'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: raw JSON must not appear in status output (output: $output)"
  fi
}

# test_fmt_log_delimiter_and_name verifies that logs output includes the '--- log' delimiter and a `name:` field for a check run.
test_fmt_log_delimiter_and_name() {
  local checks='{"total_count":1,"check_runs":[{"id":99,"name":"Test Suite","status":"completed","conclusion":"failure"}]}'
  local log="line one\nline two"
  setup_mocks_logs "$checks" "$log"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
  if echo "$output" | grep -qxF -- "--- log" && echo "$output" | grep -qF "name: Test Suite"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: log block must have '--- log' delimiter and 'name:' field (output: $output)"
  fi
}

# test_fmt_log_no_raw_json verifies that `logs --pr` header lines (`--- log` and `name:`) do not contain raw JSON-like characters such as `[` or `{`.
test_fmt_log_no_raw_json() {
  local checks='{"total_count":1,"check_runs":[{"id":99,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log="error: build failed"
  setup_mocks_logs "$checks" "$log"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
  local header_lines
  header_lines=$(echo "$output" | grep -E "^(--- log|name:)")
  if ! echo "$header_lines" | grep -qP '[\[{]'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: log header lines must not contain raw JSON (output: $output)"
  fi
}

# test_fmt_empty_comments_produces_no_output verifies that when PR review comments and issue comments are empty the formatter produces no output.
test_fmt_empty_comments_produces_no_output() {
  setup_mocks_comments '[]' '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  cleanup_mocks
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: empty PR comments must produce no output (got: $output)"
  fi
}

# test_fmt_empty_checks_produces_no_output verifies that running `status --pr` produces no output when the repository has zero check runs.
test_fmt_empty_checks_produces_no_output() {
  local checks='{"total_count":0,"check_runs":[]}'
  setup_mocks_status "$checks"
  local output
  output=$(run_script status --pr 42 2>&1)
  cleanup_mocks
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: empty check_runs must produce no output (got: $output)"
  fi
}

# test_fmt_all_passing_logs_no_output verifies that when all check runs conclude with success, the `logs --pr` command produces no output.
test_fmt_all_passing_logs_no_output() {
  local checks='{"total_count":2,"check_runs":[{"id":1,"name":"A","status":"completed","conclusion":"success"},{"id":2,"name":"B","status":"completed","conclusion":"success"}]}'
  setup_mocks_logs "$checks" "should not appear"
  local output
  output=$(run_script logs --pr 42 2>&1)
  cleanup_mocks
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: all-passing checks must produce no log output (got: $output)"
  fi
}
