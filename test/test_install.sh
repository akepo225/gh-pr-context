#!/usr/bin/env bash

: "${repo_root:?repo_root must be set by test harness}"
install_script="$repo_root/install.sh"

# setup_mock_curl creates a mock `curl` executable in the given directory; when `behavior` is `success` the mock writes a `#!/usr/bin/env bash` header to the file provided with `-o`, otherwise the mock exits with status 1.
setup_mock_curl() {
  local mockdir="$1"
  local behavior="${2:-success}"
  mkdir -p "$mockdir"
  if [ "$behavior" = "success" ]; then
    cat > "$mockdir/curl" << 'MOCK'
#!/usr/bin/env bash
outfile=""
for arg in "$@"; do
  prev="${last:-}"
  last="$arg"
  if [ "$prev" = "-o" ]; then
    outfile="$arg"
  fi
done
if [ -n "$outfile" ]; then
  echo "#!/usr/bin/env bash" > "$outfile"
fi
MOCK
  else
    printf '#!/usr/bin/env bash\nexit 1\n' > "$mockdir/curl"
  fi
  chmod +x "$mockdir/curl"
}

# cleanup_tmpdir removes the specified directory and all of its contents recursively.
cleanup_tmpdir() {
  rm -rf "$1"
}

test_names+=(
  test_install_default_dir
  test_install_custom_dir_arg
  test_install_custom_dir_env_var
  test_install_env_var_takes_precedence_over_arg
  test_install_file_is_executable
  test_install_curl_failure_exits_nonzero
  test_install_success_message
  test_install_curl_failure_stderr
  test_install_path_warning_when_not_on_path
  test_install_no_path_warning_when_on_path
)

# test_install_default_dir verifies that running the installer with an empty INSTALL_DIR installs an executable `gh-pr-context` into `$HOME/.local/bin`.
test_install_default_dir() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local fake_home="$tmpdir/home"
  mkdir -p "$fake_home"
  local mockdir="$tmpdir/mock-bin"
  setup_mock_curl "$mockdir" success
  local output
  output=$(HOME="$fake_home" INSTALL_DIR="" PATH="$mockdir:$PATH" bash "$install_script" 2>&1)
  local expected="$fake_home/.local/bin/gh-pr-context"
  if [ -f "$expected" ] && [ -x "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: default dir - file not found or not executable at $expected"
  fi
  cleanup_tmpdir "$tmpdir"
}

# test_install_custom_dir_arg verifies the installer places an executable `gh-pr-context` in the custom directory provided as the first argument.
test_install_custom_dir_arg() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local custom="$tmpdir/my-bin"
  local mockdir="$tmpdir/mock-bin"
  setup_mock_curl "$mockdir" success
  local output
  output=$(INSTALL_DIR="" PATH="$mockdir:$PATH" bash "$install_script" "$custom" 2>&1)
  local expected="$custom/gh-pr-context"
  if [ -f "$expected" ] && [ -x "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: custom dir arg - file not found or not executable at $expected"
  fi
  cleanup_tmpdir "$tmpdir"
}

# test_install_custom_dir_env_var verifies the installer creates an executable `gh-pr-context` in the directory specified by the `INSTALL_DIR` environment variable.
test_install_custom_dir_env_var() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local custom="$tmpdir/env-bin"
  local mockdir="$tmpdir/mock-bin"
  setup_mock_curl "$mockdir" success
  local output
  output=$(INSTALL_DIR="$custom" PATH="$mockdir:$PATH" bash "$install_script" 2>&1)
  local expected="$custom/gh-pr-context"
  if [ -f "$expected" ] && [ -x "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: custom dir env var - file not found or not executable at $expected"
  fi
  cleanup_tmpdir "$tmpdir"
}

# test_install_env_var_takes_precedence_over_arg verifies that the INSTALL_DIR environment variable takes precedence over a positional argument by ensuring `gh-pr-context` is created in the directory specified by `INSTALL_DIR`.
test_install_env_var_takes_precedence_over_arg() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local envdir="$tmpdir/env-dir"
  local argdir="$tmpdir/arg-dir"
  local mockdir="$tmpdir/mock-bin"
  setup_mock_curl "$mockdir" success
  local output
  output=$(INSTALL_DIR="$envdir" PATH="$mockdir:$PATH" bash "$install_script" "$argdir" 2>&1)
  if [ -f "$envdir/gh-pr-context" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: env var should be used when set (arg should be ignored)"
  fi
  cleanup_tmpdir "$tmpdir"
}

# test_install_file_is_executable verifies the installer creates an executable `gh-pr-context` in a custom `INSTALL_DIR`.
test_install_file_is_executable() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local custom="$tmpdir/bin"
  local mockdir="$tmpdir/mock-bin"
  setup_mock_curl "$mockdir" success
  INSTALL_DIR="$custom" PATH="$mockdir:$PATH" bash "$install_script" >/dev/null 2>&1
  if [ -x "$custom/gh-pr-context" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: installed file should be executable"
  fi
  cleanup_tmpdir "$tmpdir"
}

# test_install_curl_failure_exits_nonzero ensures the installer exits with a non-zero status when the mocked `curl` fails.
test_install_curl_failure_exits_nonzero() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local custom="$tmpdir/bin"
  local mockdir="$tmpdir/mock-bin"
  setup_mock_curl "$mockdir" failure
  local exit_code=0
  INSTALL_DIR="$custom" PATH="$mockdir:$PATH" bash "$install_script" >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: curl failure should exit non-zero"
  fi
  cleanup_tmpdir "$tmpdir"
}

# test_install_success_message verifies the installer prints a success message including the installed gh-pr-context path.
test_install_success_message() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local custom="$tmpdir/bin"
  local mockdir="$tmpdir/mock-bin"
  setup_mock_curl "$mockdir" success
  local output
  output=$(INSTALL_DIR="$custom" PATH="$mockdir:$PATH" bash "$install_script" 2>&1)
  if echo "$output" | grep -q "installed gh-pr-context to $custom/gh-pr-context"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: success message should contain installed path (got: $output)"
  fi
  cleanup_tmpdir "$tmpdir"
}

# test_install_curl_failure_stderr verifies that when `curl` fails the installer writes an `error:` message to stderr.
test_install_curl_failure_stderr() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local custom="$tmpdir/bin"
  local mockdir="$tmpdir/mock-bin"
  setup_mock_curl "$mockdir" failure
  local stderr
  stderr=$(INSTALL_DIR="$custom" PATH="$mockdir:$PATH" bash "$install_script" 2>&1 >/dev/null) || true
  if echo "$stderr" | grep -q "error:"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: curl failure should output error to stderr (got: $stderr)"
  fi
  cleanup_tmpdir "$tmpdir"
}

# test_install_path_warning_when_not_on_path verifies the installer warns when the install directory is not on PATH.
test_install_path_warning_when_not_on_path() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local custom="$tmpdir/bin"
  local mockdir="$tmpdir/mock-bin"
  setup_mock_curl "$mockdir" success
  local stderr
  stderr=$(INSTALL_DIR="$custom" PATH="$mockdir:$PATH" bash "$install_script" 2>&1 >/dev/null) || true
  if echo "$stderr" | grep -q "warning: gh-pr-context is not on your PATH"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: should warn when install dir is not on PATH (got: $stderr)"
  fi
  cleanup_tmpdir "$tmpdir"
}

# test_install_no_path_warning_when_on_path verifies no warning is printed when the install directory is on PATH.
test_install_no_path_warning_when_on_path() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local custom="$tmpdir/bin"
  local mockdir="$tmpdir/mock-bin"
  setup_mock_curl "$mockdir" success
  local stderr
  stderr=$(INSTALL_DIR="$custom" PATH="$custom:$mockdir:$PATH" bash "$install_script" 2>&1 >/dev/null) || true
  if echo "$stderr" | grep -q "warning: gh-pr-context is not on your PATH"; then
    fail=$((fail + 1))
    echo "FAIL: should not warn when install dir is on PATH (got: $stderr)"
  else
    pass=$((pass + 1))
  fi
  cleanup_tmpdir "$tmpdir"
}
