# Changelog

## v0.1.0

Initial release.

- **comments** — Fetch review comments and issue comments, merged and sorted by `created_at`. Review comment replies nested under parents with `>>>` markers.
- **--since filtering** — Filter comments by `last-commit`, a git SHA, a date (`YYYY-MM-DD`), or a datetime (`YYYY-MM-DDTHH:mm:ss`).
- **status** — Fetch CI check run status for the PR head commit.
- **logs** — Fetch logs for failed CI checks, truncated at 500 lines.
- **install script** — Curl-able installer (`install.sh`) with configurable install directory.
- **test harness** — 147 unit tests covering CLI parsing, PR resolution, --since resolution, comments, reply nesting, output formatting, status, logs, and install.
