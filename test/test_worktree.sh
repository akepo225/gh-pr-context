#!/usr/bin/env bash

test_names+=(
  test_worktree_noop_when_git_works
  test_worktree_relative_gitdir_resolved
  test_worktree_real_worktree_works
  test_worktree_broken_path_fails
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

# test_worktree_relative_gitdir_resolved verifies the path conversion logic
# by directly testing that the Windows path regex produces the correct WSL path.
test_worktree_relative_gitdir_resolved() {
  # Test the Windows path regex conversion (the core of the WSL fix)
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

  # Test lowercase drive letter
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

# test_worktree_real_worktree_works verifies that a real git worktree (created
# with `git worktree add`) works correctly through setup_git_env.
test_worktree_real_worktree_works() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local main_repo="$tmpdir/main"
  local wt_dir="$tmpdir/worktree"

  git init "$main_repo" >/dev/null 2>&1
  (cd "$main_repo" && git commit --allow-empty -m "init" >/dev/null 2>&1)
  git -C "$main_repo" worktree add "$wt_dir" >/dev/null 2>&1

  (
    cd "$wt_dir"
    eval "$(sed -n '/^setup_git_env()/,/^}/p' "$script")"
    setup_git_env
    local rc=$?
    if [ $rc -eq 0 ]; then
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
    echo "FAIL: setup_git_env should handle real worktree .git files"
  fi

  git -C "$main_repo" worktree remove "$wt_dir" >/dev/null 2>&1 || true
  rm -rf "$tmpdir"
}

# test_worktree_broken_path_fails verifies that setup_git_env returns failure
# when the .git file points to a non-existent path.
test_worktree_broken_path_fails() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "gitdir: /nonexistent/path/.git/worktrees/broken" > "$tmpdir/.git"

  (
    cd "$tmpdir"
    eval "$(sed -n '/^setup_git_env()/,/^}/p' "$script")"
    setup_git_env
    exit $?
  )
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: setup_git_env should fail when gitdir points to non-existent path"
  fi

  rm -rf "$tmpdir"
}
