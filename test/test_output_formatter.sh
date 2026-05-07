#!/usr/bin/env bash

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# setup_mocks_base defines mock `git` and `gh` functions for tests; the mock `git` returns a fixed repo URL for `remote get-url origin` and a fixed branch for `rev-parse --abbrev-ref HEAD`, while the mock `gh` exits with status 1 by default.
setup_mocks_base() {
  git() {
    case "$*" in
      "rev-parse --git-dir") echo ".git" ;;
      "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
      "rev-parse --abbrev-ref HEAD") echo "feature-branch" ;;
      *) exit 1 ;;
    esac
  }
  gh() {
    exit 1
  }
}

# setup_mocks_comments sets mock PR review and issue comment payloads and defines a gh() mock that returns the first argument for pulls/42/comments, the second for issues/42/comments, and an empty array for pull comment replies.
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

# setup_mocks_comments_with_reply sets up mock `git`/`gh` functions and configures `gh` to return the provided PR review JSON, an empty issues list, and per-comment reply JSON (second argument is stored as `_MOCK_REPLY_77`).
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

# setup_mocks_status defines git/gh mock functions for status-related API calls and stores the provided check-runs payload.
# The first argument is the JSON/string payload to be returned for `check-runs` API calls; calls matching `pulls/42` return `HEAD_SHA`.
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

# setup_mocks_logs configures mock payloads and defines a gh() function that returns the pull SHA for pulls/42 requests, the provided check-runs JSON for check-runs requests, or the provided log content for logs requests.
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

# run_script exports mock `git` and `gh` functions and mock payload variables, then invokes the target script stored in `$script` with the provided arguments.
run_script() {
  export -f git gh
  export _MOCK_PR_REVIEWS _MOCK_PR_ISSUES _MOCK_CHECK_RUNS _MOCK_LOG_CONTENT _MOCK_REPLY_77 HEAD_SHA
  timeout 15 bash "$script" "$@" </dev/null
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

# test_fmt_review_comment_delimiter checks that formatted review comments begin with a standalone line containing '--- review-comment'.
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

# test_fmt_review_comment_field_order tests that the formatted review-comment output lists fields in the order author → created → path → line → body.
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

# test_fmt_review_comment_no_raw_json ensures review comment output contains no raw JSON or array/object tokens at the start of any line.
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

# test_fmt_review_comment_no_trailing_whitespace_on_fields checks that lines starting with author, created, path, line, body, name, status, or conclusion do not end with trailing whitespace.
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

# test_fmt_issue_comment_delimiter verifies that issue comments output begins with a line containing only '--- issue-comment'.
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

# test_fmt_issue_comment_fields_present verifies that the formatted issue comment output includes `author`, `created`, and `body` fields.
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

# test_fmt_issue_comment_no_path_line ensures issue comment output does not include `path:` or `line:` fields.
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

# test_fmt_issue_comment_no_raw_json ensures issue comment output contains no raw JSON/array/object tokens at the start of any line.
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

# test_fmt_reply_marker verifies that a reply comment is emitted with a single-line ">>> reply" marker.
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

# test_fmt_reply_fields verifies that a reply block contains the `author`, `created`, and `body` fields.
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

# test_fmt_check_completed_delimiter_and_fields verifies the `status` subcommand emits a `--- check` delimiter and includes `name`, `status`, and `conclusion` fields for a completed check run.
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

# test_fmt_check_non_completed_no_conclusion_field verifies that a queued check run's formatted output contains a `status:` line and does not include a `conclusion:` field.
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

# test_fmt_check_no_raw_json verifies that the `status` subcommand's output does not contain raw JSON array/object tokens (`[`, `{`) at the start of any line.
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

# test_fmt_log_delimiter_and_name verifies that the `logs` command emits a `--- log` delimiter and includes the `name: Test Suite` field for a failed completed check run with logs.
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

# test_fmt_log_no_raw_json verifies that header lines produced by the `logs` command (lines starting with '--- log' or 'name:') do not contain raw JSON or array/object tokens.
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

# test_fmt_empty_comments_produces_no_output verifies that when both PR review comments and issue comments are empty the target script produces no output.
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

# test_fmt_all_passing_logs_no_output verifies that when all check runs conclude "success" the `logs` subcommand produces no output.
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
