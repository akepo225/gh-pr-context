# PRD: `gh-pr-context` CLI Utility

## Problem Statement

Coding assistants (LLMs) acting on PR review feedback waste tokens and introduce non-determinism when they shell out to `gh api` directly — they have to discover the right endpoints, parse verbose JSON responses, and reconstruct threading. There is no lightweight, token-efficient tool that gives an LLM exactly the PR context it needs in a deterministic, parseable format.

## Solution

A single-file CLI tool (`gh-pr-context`) that wraps `gh api` and outputs terse, structured plain-text PR context — comments (with nested replies), CI status, and failure logs — optimized for LLM consumption. It auto-detects the PR from the current branch, supports time-bounded comment filtering via `--since`, and requires zero project-specific setup.

## User Stories

1. As an LLM coding assistant, I want to run `gh-pr-context comments` and get all review and issue comments on the current PR in a compact format, so that I can understand review feedback without wasting tokens on raw JSON.
2. As an LLM coding assistant, I want review comment replies nested under their parent comment, so that I can follow conversation threads without reconstructing threading myself.
3. As an LLM coding assistant, I want to run `gh-pr-context comments --since last-commit` and get only comments posted after my latest commit, so that I can focus on new feedback I haven't addressed.
4. As an LLM coding assistant, I want to run `gh-pr-context comments --since <SHA>` and get comments after a specific commit, so that I can narrow context to feedback since an arbitrary point.
5. As an LLM coding assistant, I want to run `gh-pr-context comments --since 2025-05-01` and get comments on or after that date, so that I can filter by calendar date.
6. As an LLM coding assistant, I want to run `gh-pr-context comments --since 2025-05-01T12:30:00` and get comments on or after that datetime, so that I can filter with fine-grained time precision.
7. As an LLM coding assistant, I want to specify `--pr 42` to target any PR regardless of my current branch, so that I can fetch context for arbitrary PRs.
8. As an LLM coding assistant, I want to run `gh-pr-context status` and get the CI check states for the PR head commit, so that I know whether tests pass before proceeding.
9. As an LLM coding assistant, I want to run `gh-pr-context logs` and get logs for failed CI checks only, so that I can diagnose failures without sifting through passing check output.
10. As an LLM coding assistant, I want deterministic output every time I run the same command, so that my behavior is reproducible.
11. As an LLM coding assistant, I want the tool to exit non-zero with a one-line error on failure, so that my orchestration layer can detect and handle errors.
12. As a developer setting up an LLM workflow, I want to install `gh-pr-context` via a single curl command, so that I can add it to any environment without a package manager.
13. As a developer, I want the tool to work in any git repo with a GitHub remote, so that I don't need project-specific configuration.
14. As an LLM coding assistant, I want issue comments returned flat (no pseudo-threading), so that I get an accurate representation of GitHub's data model.
15. As an LLM coding assistant, I want truncated logs to include a note about truncation, so that I know when output is incomplete.
16. As an LLM coding assistant, I want review comment replies filtered by the same `--since` criteria as top-level comments, so that filtering is consistent across the thread.

## Implementation Decisions

### Modules

The tool is a single bash script. Internally, it is organized into the following logical modules, each testable in isolation:

1. **CLI Parser** — Parses the command (`comments`, `status`, `logs`) and flags (`--pr`, `--since`, `--all`). Validates inputs and dispatches to the appropriate handler.

2. **PR Resolution Module** — Given an optional PR number, returns the PR number to operate on. If omitted, calls `gh api` to look up the PR associated with the current branch on the detected GitHub remote. Exits with an error if no PR is found.

3. **`--since` Resolution Module** — Parses the `--since` flag value into an ISO 8601 timestamp used for filtering. Handles five cases:
   - Omitted → no filter (return all)
   - `last-commit` → resolve HEAD commit timestamp via `git log`
   - 7-40 char hex SHA → resolve that commit's timestamp via `git log`, with GitHub API fallback
   - `YYYY-MM-DD` → treat as `YYYY-MM-DDT00:00:00Z`
   - `YYYY-MM-DDTHH:mm:ss` → treat as UTC

4. **Comments Fetcher** — Fetches review comments (via `repos/{owner}/{repo}/pulls/{pr}/comments`), review comment replies (via `repos/{owner}/{repo}/pulls/comments/{id}/replies`), and issue comments (via `repos/{owner}/{repo}/issues/{pr}/comments`). Applies the `--since` timestamp filter. Groups replies under their parent review comment. Returns issue comments flat.

5. **Status Fetcher** — Fetches the combined status and check suites for the PR head commit (via `repos/{owner}/{repo}/commits/{sha}/check-runs` and/or `repos/{owner}/{repo}/commits/{sha}/status`). Outputs name, status, and conclusion for each check.

6. **Logs Fetcher** — For each check with conclusion `failure`, fetches the log URL from the check run, downloads and decodes the log. Truncates at 500 lines with a truncation notice. Returns nothing if all checks pass.

7. **Output Formatter** — Shared helper functions that produce the terse plain-text output format. Uses clear delimiters (e.g., `---` between comments, `>>>` for reply nesting). No JSON wrapping, no decorative headers.

### Technical Decisions

- The script is written in **bash** using `gh api` for GitHub API calls and `jq` for minimal field extraction from JSON responses.
- If bash becomes unwieldy (e.g., for log download/decoding), a single Python file with no external dependencies is an acceptable fallback. No Node.js.
- The GitHub repo/owner is resolved from the git remote (default: `origin`) using `git remote get-url`.
- The PR head SHA is fetched from the PR object via `gh api` (not from the local HEAD, which may differ).
- Output ordering: comments are sorted by creation date ascending (oldest first) for determinism.
- The `--since` filter compares against `created_at` timestamps from the GitHub API.
- Log download uses the `download_url` from check run details, or falls back to `gh api` with appropriate accept headers.
- The script uses `set -euo pipefail` for strict error handling.

## Testing Decisions

### What makes a good test

Tests verify external behavior (output format, exit codes, error messages) and never depend on internal implementation details like function names or variable names. Tests mock `gh api` and `git` calls via PATH manipulation or function overriding so they run without network access.

### Modules to test

All modules will be tested:

1. **CLI Parser** — Test that valid commands and flags parse correctly. Test that invalid commands, missing arguments, and unknown flags produce non-zero exit and a stderr message.

2. **PR Resolution Module** — Test auto-detection from branch name (mock `gh api` response). Test explicit `--pr` passthrough. Test error when no PR found for branch.

3. **`--since` Resolution Module** — Test each of the five input variants resolves to the correct timestamp. Test edge cases: empty string, invalid date format, non-existent SHA.

4. **Comments Fetcher** — Test that review comments and issue comments are fetched from the correct endpoints. Test `--since` filtering excludes older comments. Test reply nesting: replies appear under their parent, not flat. Test that issue comments are flat. Test empty PR returns no output.

5. **Status Fetcher** — Test that check runs are fetched and output in the expected format. Test checks in various states (queued, in_progress, completed with different conclusions).

6. **Logs Fetcher** — Test that only failed check logs are included. Test truncation at 500 lines. Test that all-passing checks produce no output.

7. **Output Formatter** — Test output format matches the spec exactly: correct delimiters, correct field order, no extra whitespace or JSON.

### Prior art

This is a greenfield project. Tests will use a bash testing pattern with:
- A `test/` directory containing one test file per module.
- Each test file sources the main script and overrides `gh` and `git` with mock functions.
- A `test/run.sh` runner that executes all test files and reports pass/fail.

## Out of Scope

- **Diff context for review comments** — The tool returns the comment body, path, and line. Fetching the diff hunk is out of scope.
- **Comment creation or mutation** — Read-only. The tool never posts, edits, or deletes comments.
- **Pagination controls** — The tool fetches all matching comments automatically. No `--page` or `--limit` flag.
- **Multi-repo support** — One repo per invocation, detected from the git remote.
- **Caching** — Every invocation hits the API fresh. No local cache.
- **Auth management** — The tool assumes `gh` is already authenticated. No login or token handling.
- **Shell completions** — No bash/zsh/fish completion scripts.
- **Man page or `--help` prose** — Minimal usage output only (`usage: gh-pr-context <command> [options]`).
- **Windows-native support** — Targets bash environments (macOS, Linux, WSL). PowerShell support is not a goal.

## Further Notes

- The tool is designed to be called by LLMs, so output stability across versions matters. Breaking format changes should be versioned.
- The install script should place the file at `~/.local/bin/gh-pr-context` (or a user-specified directory) and make it executable.
- The script should begin with a `#!/usr/bin/env bash` shebang and a brief header comment with the version.
- If `jq` is not installed, the script should exit with a clear error message to stderr.
