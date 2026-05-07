# Changelog

## v0.2.2

- **Short SHA support** — `--since` now accepts 7-40 character hex SHAs (previously only 40-character SHAs).
- **GitHub API fallback** — When a commit is not available locally, `--since` falls back to the GitHub API to resolve the timestamp.

## v0.2.1

- **WSL worktree fix** — Resolve git worktree paths on WSL where `.git` is a file pointing to the worktree.

## v0.2.0

- **GH_PR_CONTEXT_VERSION** — Install a specific version by setting the env var (e.g., `GH_PR_CONTEXT_VERSION=v0.2.0`).
- **PATH warning** — Post-install check warns if `gh-pr-context` is not on PATH.
- **CI version gate** — Automated check that script version matches the latest git tag.
- **Windows CRLF fix** — Strip `\r` from `jq` output to prevent corrupted API URLs on Windows/Git Bash.

## v0.1.0

Initial release.

- **comments** — Fetch review comments and issue comments, merged and sorted by `created_at`. Review comment replies nested under parents with `>>>` markers.
- **--since filtering** — Filter comments by `last-commit`, a git SHA, a date (`YYYY-MM-DD`), or a datetime (`YYYY-MM-DDTHH:mm:ss`).
- **status** — Fetch CI check run status for the PR head commit.
- **logs** — Fetch logs for failed CI checks, truncated at 500 lines.
- **install script** — Curl-able installer (`install.sh`) with configurable install directory.
- **test harness** — 147 unit tests covering CLI parsing, PR resolution, --since resolution, comments, reply nesting, output formatting, status, logs, and install.
