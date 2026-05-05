# Changelog

## v0.2.1

- **SKILL.md YAML fix** — Quote frontmatter values to prevent YAML parsing errors with colons in descriptions.

## v0.2.0

- **pr-qa-review skill** — Agent skill for QA & delivery review workflow using gh-pr-context to fetch PR comments, CI status, and failed check logs.
- **Agent skills framework** — SKILL.md format with frontmatter for name, description, compatibility, and allowed-tools.
- **`--version` flag** — Show version information.
- **Date validation** — Round-trip date check for Linux compatibility.
- **Test refactor** — Shell function overrides replacing PATH injection for better test isolation.
- **Error handling** — Improved 404 handling for reply threads.
- **CI version check** — Validate script version matches the latest git tag.

## v0.1.0

Initial release.

- **comments** — Fetch review comments and issue comments, merged and sorted by `created_at`. Review comment replies nested under parents with `>>>` markers.
- **--since filtering** — Filter comments by `last-commit`, a git SHA, a date (`YYYY-MM-DD`), or a datetime (`YYYY-MM-DDTHH:mm:ss`).
- **status** — Fetch CI check run status for the PR head commit.
- **logs** — Fetch logs for failed CI checks, truncated at 500 lines.
- **install script** — Curl-able installer (`install.sh`) with configurable install directory.
- **test harness** — 147 unit tests covering CLI parsing, PR resolution, --since resolution, comments, reply nesting, output formatting, status, logs, and install.
