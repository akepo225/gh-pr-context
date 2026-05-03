## AGENTS.md

### Project

Single-file bash CLI (`gh-pr-context`) that wraps `gh api` for LLM consumption. No build step, no dependencies beyond `gh`, `jq`, and bash.

### Commands to run

```bash
bash test/run.sh
```

There is no build, lint, or typecheck. The only verification step is the test runner.

### Architecture

Everything lives in one script (`gh-pr-context`). Internally it has logical modules (CLI parser, PR resolver, `--since` resolver, comments/status/logs fetchers, output formatter) but they are functions in the same file, not separate files.

Tests live in `test/`. Each test file sources the main script and mocks `gh` and `git` via shell function overrides. Tests run without network access.

### Key constraints

- **Output format is the contract.** The terse plain-text format (`---` delimiters, `>>>` for replies, key-value fields) is designed for LLMs. Do not wrap in JSON, add decorative headers, or change delimiters without updating the PRD (#1).
- **Comments sorted ascending by `created_at`** (oldest first) for determinism.
- **PR head SHA comes from the PR object via `gh api`**, not from local HEAD (which may differ from the remote branch).
- **GitHub owner/repo resolved from `origin` remote** via `git remote get-url`.
- **`set -euo pipefail`** — strict error handling. Exit non-zero with one-line stderr on any failure.
- **`jq` is required.** Validate it's on PATH at startup and exit with a clear error if missing.
- **No Node.js.** If bash becomes unwieldy, the fallback is a single Python file with no external deps.
- **Log truncation at 500 lines** with a `[truncated: N lines omitted]` notice.
- **Issue comments are flat.** Only review comments get nested replies. Do not pseudo-thread issue comments.

### GitHub API endpoints used

| Purpose | Endpoint |
|---|---|
| PR from branch | `repos/{owner}/{repo}/pulls?head={owner}:{branch}` |
| Review comments | `repos/{owner}/{repo}/pulls/{pr}/comments` |
| Comment replies | `repos/{owner}/{repo}/pulls/comments/{id}/replies` |
| Issue comments | `repos/{owner}/{repo}/issues/{pr}/comments` |
| Check runs | `repos/{owner}/{repo}/commits/{sha}/check-runs` |

### Issue tracker

GitHub Issues at `akepo225/gh-pr-context`. Issues labeled `needs-triage` await triage before work begins.

### Execution order

Issues must be implemented in dependency order: #2 → #3/#4/#5 (parallel-safe, but #2 first) → #6 → #7 → #8.

## Agent skills

### Issue tracker

GitHub Issues at `akepo225/gh-pr-context`. Uses `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five-label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.
