#!/usr/bin/env bash

PATH="$HOME/bin:$PATH"

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

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

setup_mocks_comments() {
  _MOCK_PR_REVIEWS="$1"
  _MOCK_PR_ISSUES="$2"
  setup_mocks_base
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo "$_MOCK_PR_REVIEWS" ;;
      *"issues/42/comments"*) echo "$_MOCK_PR_ISSUES" ;;
      *"pulls/comments/"*"/replies"*) echo '[]' ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_comments_with_reply() {
  _MOCK_PR_REVIEWS="$1"
  _MOCK_REPLY_77="$2"
  setup_mocks_base
  gh() {
    case "$*" in
      *"pulls/42/comments"*) echo "$_MOCK_PR_REVIEWS" ;;
      *"issues/42/comments"*) echo '[]' ;;
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

setup_mocks_status() {
  _MOCK_CHECK_RUNS="$1"
  setup_mocks_base
  gh() {
    case "$*" in
      *"pulls/42"*) echo "$HEAD_SHA" ;;
      *"check-runs"*) echo "$_MOCK_CHECK_RUNS" ;;
      *) exit 1 ;;
    esac
  }
}

setup_mocks_logs() {
  _MOCK_CHECK_RUNS="$1"
  _MOCK_LOG_CONTENT="$2"
  setup_mocks_base
  gh() {
    case "$*" in
      *"pulls/42"*) echo "$HEAD_SHA" ;;
      *"check-runs"*) echo "$_MOCK_CHECK_RUNS" ;;
      *"logs"*) printf '%s' "$_MOCK_LOG_CONTENT" ;;
      *) exit 1 ;;
    esac
  }
}

run_script() {
  export -f git gh
  export _MOCK_PR_REVIEWS _MOCK_PR_ISSUES _MOCK_CHECK_RUNS _MOCK_LOG_CONTENT _MOCK_REPLY_77 HEAD_SHA
  bash "$script" "$@"
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

test_fmt_review_comment_delimiter() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/app.sh","line":5,"body":"fix this"}]'
  setup_mocks_comments "$review" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  if echo "$output" | grep -qxF -- "--- review-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: review comment must start with '--- review-comment' on its own line (output: $output)"
  fi
}

test_fmt_review_comment_field_order() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/app.sh","line":5,"body":"fix this"}]'
  setup_mocks_comments "$review" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
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

test_fmt_review_comment_no_raw_json() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/app.sh","line":5,"body":"fix this"}]'
  setup_mocks_comments "$review" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  if ! echo "$output" | grep -qP '^\s*[\[{]'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: raw JSON must not appear in output (output: $output)"
  fi
}

test_fmt_review_comment_no_trailing_whitespace_on_fields() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"src/app.sh","line":5,"body":"fix this"}]'
  setup_mocks_comments "$review" '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  local bad_lines
  bad_lines=$(echo "$output" | grep -P '^(author|created|path|line|body|name|status|conclusion):.*\s+$' || true)
  if [ -z "$bad_lines" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: field lines must not have trailing whitespace (bad lines: $bad_lines)"
  fi
}

test_fmt_issue_comment_delimiter() {
  local issue='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"looks good"}]'
  setup_mocks_comments '[]' "$issue"
  local output
  output=$(run_script comments --pr 42 2>&1)
  if echo "$output" | grep -qxF -- "--- issue-comment"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comment must start with '--- issue-comment' on its own line (output: $output)"
  fi
}

test_fmt_issue_comment_fields_present() {
  local issue='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"hello world"}]'
  setup_mocks_comments '[]' "$issue"
  local output
  output=$(run_script comments --pr 42 2>&1)
  if echo "$output" | grep -qF "author: bob" \
    && echo "$output" | grep -qF "created: 2025-01-01T11:00:00Z" \
    && echo "$output" | grep -qF "body: hello world"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comment missing author/created/body (output: $output)"
  fi
}

test_fmt_issue_comment_no_path_line() {
  local issue='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"hello"}]'
  setup_mocks_comments '[]' "$issue"
  local output
  output=$(run_script comments --pr 42 2>&1)
  if ! echo "$output" | grep -qE "^path:|^line:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: issue comment must not contain path: or line: fields (output: $output)"
  fi
}

test_fmt_issue_comment_no_raw_json() {
  local issue='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"hi"}]'
  setup_mocks_comments '[]' "$issue"
  local output
  output=$(run_script comments --pr 42 2>&1)
  if ! echo "$output" | grep -qP '^\s*[\[{]'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: raw JSON must not appear in issue comment output (output: $output)"
  fi
}

test_fmt_reply_marker() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"}]'
  local reply='[{"user":{"login":"bob"},"created_at":"2025-01-01T11:00:00Z","body":"a reply"}]'
  setup_mocks_comments_with_reply "$review" "$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  if echo "$output" | grep -qxF ">>> reply"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply must use exactly '>>> reply' marker on its own line (output: $output)"
  fi
}

test_fmt_reply_fields() {
  local review='[{"id":77,"user":{"login":"alice"},"created_at":"2025-01-01T10:00:00Z","path":"a.sh","line":1,"body":"parent"}]'
  local reply='[{"user":{"login":"replyauthor"},"created_at":"2025-03-15T09:00:00Z","body":"the reply body"}]'
  setup_mocks_comments_with_reply "$review" "$reply"
  local output
  output=$(run_script comments --pr 42 2>&1)
  if echo "$output" | grep -qF "author: replyauthor" \
    && echo "$output" | grep -qF "created: 2025-03-15T09:00:00Z" \
    && echo "$output" | grep -qF "body: the reply body"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: reply block must contain author, created, body fields (output: $output)"
  fi
}

test_fmt_check_completed_delimiter_and_fields() {
  local checks='{"total_count":1,"check_runs":[{"name":"Build","status":"completed","conclusion":"success"}]}'
  setup_mocks_status "$checks"
  local output
  output=$(run_script status --pr 42 2>&1)
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

test_fmt_check_non_completed_no_conclusion_field() {
  local checks='{"total_count":1,"check_runs":[{"name":"Lint","status":"queued","conclusion":null}]}'
  setup_mocks_status "$checks"
  local output
  output=$(run_script status --pr 42 2>&1)
  if echo "$output" | grep -qF "status: queued" && ! echo "$output" | grep -qF "conclusion:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: non-completed check must omit conclusion field (output: $output)"
  fi
}

test_fmt_check_no_raw_json() {
  local checks='{"total_count":1,"check_runs":[{"name":"CI","status":"completed","conclusion":"failure"}]}'
  setup_mocks_status "$checks"
  local output
  output=$(run_script status --pr 42 2>&1)
  if ! echo "$output" | grep -qP '^\s*[\[{]'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: raw JSON must not appear in status output (output: $output)"
  fi
}

test_fmt_log_delimiter_and_name() {
  local checks='{"total_count":1,"check_runs":[{"id":99,"name":"Test Suite","status":"completed","conclusion":"failure"}]}'
  local log="line one\nline two"
  setup_mocks_logs "$checks" "$log"
  local output
  output=$(run_script logs --pr 42 2>&1)
  if echo "$output" | grep -qxF -- "--- log" && echo "$output" | grep -qF "name: Test Suite"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: log block must have '--- log' delimiter and 'name:' field (output: $output)"
  fi
}

test_fmt_log_no_raw_json() {
  local checks='{"total_count":1,"check_runs":[{"id":99,"name":"CI","status":"completed","conclusion":"failure"}]}'
  local log="error: build failed"
  setup_mocks_logs "$checks" "$log"
  local output
  output=$(run_script logs --pr 42 2>&1)
  local header_lines
  header_lines=$(echo "$output" | grep -E "^(--- log|name:)")
  if ! echo "$header_lines" | grep -qP '[\[{]'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: log header lines must not contain raw JSON (output: $output)"
  fi
}

test_fmt_empty_comments_produces_no_output() {
  setup_mocks_comments '[]' '[]'
  local output
  output=$(run_script comments --pr 42 2>&1)
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: empty PR comments must produce no output (got: $output)"
  fi
}

test_fmt_empty_checks_produces_no_output() {
  local checks='{"total_count":0,"check_runs":[]}'
  setup_mocks_status "$checks"
  local output
  output=$(run_script status --pr 42 2>&1)
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: empty check_runs must produce no output (got: $output)"
  fi
}

test_fmt_all_passing_logs_no_output() {
  local checks='{"total_count":2,"check_runs":[{"id":1,"name":"A","status":"completed","conclusion":"success"},{"id":2,"name":"B","status":"completed","conclusion":"success"}]}'
  setup_mocks_logs "$checks" "should not appear"
  local output
  output=$(run_script logs --pr 42 2>&1)
  if [ -z "$output" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: all-passing checks must produce no log output (got: $output)"
  fi
}
