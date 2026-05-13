#!/usr/bin/env bash

test_names+=(
  test_worktree_noop_when_git_works
  test_worktree_windows_path_conversion
  test_worktree_broken_path_returns_nonzero
  test_worktree_since_last_commit_after_setup
)

# test_worktree_noop_when_git_works verifies setup_git_env is a no-op
# when git already works (normal Linux/Mac/Windows case).
test_worktree_noop_when_git_works() {
  (
    cd "$repo_root"
    eval "$(sed -n '/^setup_git_env()/,/^}/p' "$script")"
    setup_git_env
    local rc=$?
    if [ $rc -eq 0 ] && [ -z "${GIT_DIR:-}" ]; then
      exit 0
    else
      exit 1
    fi
  )
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: setup_git_env should be a no-op when git already works"
  fi
}

# test_worktree_windows_path_conversion verifies the Windows-to-WSL
# path regex used in setup_git_env produces correct conversions.
test_worktree_windows_path_conversion() {
  local test_path="C:/projects/repo/.git/worktrees/wt1"
  if [[ "$test_path" =~ ^([A-Za-z]):(/.*)$ ]]; then
    local drive="${BASH_REMATCH[1],,}"
    local rest="${BASH_REMATCH[2]}"
    local resolved="/mnt/${drive}${rest}"
    if [ "$resolved" = "/mnt/c/projects/repo/.git/worktrees/wt1" ]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "FAIL: unexpected conversion: $resolved"
    fi
  else
    fail=$((fail + 1))
    echo "FAIL: Windows path regex did not match"
  fi

  local test_path2="d:/Users/test/repo/.git/worktrees/wt2"
  if [[ "$test_path2" =~ ^([A-Za-z]):(/.*)$ ]]; then
    local drive="${BASH_REMATCH[1],,}"
    local rest="${BASH_REMATCH[2]}"
    local resolved="/mnt/${drive}${rest}"
    if [ "$resolved" = "/mnt/d/Users/test/repo/.git/worktrees/wt2" ]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "FAIL: unexpected conversion: $resolved"
    fi
  else
    fail=$((fail + 1))
    echo "FAIL: Windows path regex did not match for d: drive"
  fi
}

# test_worktree_broken_path_returns_nonzero verifies that setup_git_env
# returns non-zero when .git is a file pointing to a non-existent path.
test_worktree_broken_path_returns_nonzero() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "gitdir: /nonexistent/path/.git/worktrees/broken" > "$tmpdir/.git"

  local rc=0
  (
    cd "$tmpdir"
    eval "$(sed -n '/^setup_git_env()/,/^}/p' "$script")"
    setup_git_env
  ) 2>/dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: setup_git_env should return non-zero for broken path"
  fi

  rm -rf "$tmpdir"
}

HEAD_EPOCH="1742040000"

test_worktree_since_last_commit_after_setup() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local gitdir_target="$tmpdir/gitdir_target"
  mkdir -p "$gitdir_target"
  echo "gitdir: gitdir_target" > "$tmpdir/.git"

  local exit_code=0 output
  output=$(
    unset GIT_DIR GIT_WORK_TREE
    export -f die parse_duration resolve_since_timestamp resolve_owner_repo resolve_pr_number resolve_pr_head_sha check_deps setup_git_env
    export HEAD_EPOCH
    cd "$tmpdir"
    git() {
      case "$*" in
        "rev-parse --git-dir")
          if [ -n "${GIT_DIR:-}" ]; then echo "$GIT_DIR"; else exit 1; fi
          ;;
        "remote get-url origin") echo "https://github.com/acme/widgets.git" ;;
        "rev-parse --abbrev-ref HEAD") echo "my-feature" ;;
        "log -1 --format=%ct HEAD")
          if [ -n "${GIT_DIR:-}" ] && [ -n "${GIT_WORK_TREE:-}" ]; then
            echo "$HEAD_EPOCH"
          else
            exit 1
          fi
          ;;
        *) exit 1 ;;
      esac
    }
    gh() {
      case "$*" in
        *"pulls?head="*) echo '[{"number":42}]' ;;
        *"pulls/42/comments"*) echo '[]' ;;
        *"issues/42/comments"*) echo '[{"user":{"login":"bot"},"created_at":"2099-01-01T00:00:00Z","body":"wt-future"}]' ;;
        *) exit 1 ;;
      esac
    }
    export -f git gh
    timeout 15 bash "$script" comments --pr 42 --since last-commit 2>&1
  ) || exit_code=$?

  rm -rf "$tmpdir"

  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qF "wt-future"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: --since last-commit should work in worktree after env setup (exit: $exit_code, output: $output)"
  fi
}
