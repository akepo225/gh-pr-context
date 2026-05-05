---
name: pr-qa-review
description: QA & delivery review workflow for PRs using gh-pr-context to fetch PR comments, CI status, and failed check logs. Use when implementation is complete and ready for self-review, QA, and PR creation. Triggers: "qa review", "delivery review", "ready to ship", "self-review", "create PR", "review my changes".
compatibility: Requires gh-pr-context on PATH, gh (authenticated), jq, and bash
allowed-tools: Bash(gh-pr-context:*) Bash(gh:*) Bash(jq:*) Bash(git:*)
---

# PR QA & Delivery Review

Run this workflow when implementation is complete, before shipping.

## Prerequisites

Requires `gh-pr-context` on PATH. If missing, install:

```bash
curl -fsSL https://raw.githubusercontent.com/akepo225/gh-pr-context/v0.2.1/install.sh | bash
```

Verify: `gh-pr-context --help`. Requires `gh` (authenticated), `jq`, and `bash`.

## Workflow

### 1. Self-Review

- Re-read the implementation plan and original issue. Verify every acceptance criterion is met.
- Audit the diff for: bugs, typos, missing error handling, unhandled edge cases, hardcoded values, leftover debug code, incomplete TODOs.
- Check documentation (README, inline docs, AGENTS.md) is up to date.
- Verify no unintended files were modified or created.

### 2. Integration & Dependency Check

- Confirm all new dependencies are intentional and documented.
- Verify imports, exports, and module boundaries are correct.
- Ensure no breaking changes to existing interfaces.

### 3. Runtime Verification

- Run the full test suite. All tests must pass.
- Run linting, typechecking, or static analysis defined in the project.
- Exercise changed functionality manually or via integration tests where applicable.
- Check container logs, server output, or browser console for errors if relevant.

### 4. Gather PR Context

Run these commands in the project directory (branch must have an open PR, or pass `--pr <number>`):

```bash
# All comments (review comments with nested replies + issue comments)
gh-pr-context comments

# Only new comments since your latest commit (uses commit timestamp, not push time)
gh-pr-context comments --since last-commit

# CI check status
gh-pr-context status

# Logs for failed checks (no output if all pass)
gh-pr-context logs
```

Read the output carefully. For each comment or failed check, determine if action is needed.

**Output format reference:**

- `--- review-comment` — Inline code review comment. Fields: `path`, `line`, `body`. Replies nested under `>>> reply`.
- `--- issue-comment` — General PR comment. Fields: `author`, `created`, `body`. Flat, no replies.
- `--- check` — CI check. Fields: `name`, `status`, optional `conclusion`.
- `--- log` — Failed check log. Fields: `name`, log body. Truncated at 500 lines with `[truncated: N lines omitted]`.

### 5. Fix All Findings

Address every legitimate issue from steps 1–4. Dismiss only clearly false positives — explain dismissals in the commit message or PR description.

### 6. Create a Pull Request (skip if PR already exists)

- Do **not** push to `main`. Create a feature branch and open a PR.
- Write a clear summary: what changed, why, and how it was tested.
- Link the original issue.

### 7. Monitor & Iterate

- Re-run `gh-pr-context comments --since last-commit` after each push to catch new feedback.
- Re-run `gh-pr-context status` and `gh-pr-context logs` to verify CI.
- Evaluate each review comment. Implement only comments that provide substantial, grounded improvements.
- Push fixes, wait for re-check, repeat until the PR is mergeable.
