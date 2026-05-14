# gh-pr-context

Token-efficient PR context CLI for LLM coding assistants. Wraps `gh api` to fetch review comments, issue comments, and CI/CD status — output in a terse, structured plain-text format optimized for LLM consumption, not JSON.

## Requirements

- [gh](https://cli.github.com/) (authenticated)
- [jq](https://jqlang.github.io/jq/)
- bash

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/akepo225/gh-pr-context/master/install.sh | bash
```

Install to a custom directory:

```bash
curl -fsSL https://raw.githubusercontent.com/akepo225/gh-pr-context/master/install.sh | bash -s /usr/local/bin
```

Or use the `INSTALL_DIR` environment variable:

```bash
curl -fsSL https://raw.githubusercontent.com/akepo225/gh-pr-context/master/install.sh | INSTALL_DIR=/usr/local/bin bash
```

Install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/akepo225/gh-pr-context/master/install.sh | GH_PR_CONTEXT_VERSION=<tag> bash
```

For example, to install `v0.2.2`:

```bash
curl -fsSL https://raw.githubusercontent.com/akepo225/gh-pr-context/master/install.sh | GH_PR_CONTEXT_VERSION=v0.2.2 bash
```

## Usage

All commands auto-detect the PR from the current branch. Pass `--pr <number>` to target a specific PR.

### Comments

```bash
# All comments on the current PR
gh-pr-context comments

# Specific PR
gh-pr-context comments --pr 42

# Only comments after the latest commit
gh-pr-context comments --since last-commit

# Only comments after a specific commit
gh-pr-context comments --since abc123def456...

# Only comments on or after a date
gh-pr-context comments --since 2025-05-01

# Only comments on or after a datetime
gh-pr-context comments --since 2025-05-01T12:30:00
```

### CI Status

```bash
gh-pr-context status
```

### Failed Check Logs

```bash
# Logs for failed checks only; no output if all pass
gh-pr-context logs
```

## Output Format

Comments are returned as terse plain-text with clear delimiters. Review comment replies are nested under their parent. Example:

```text
--- review-comment
author: someone
created: 2025-05-01T14:32:00Z
path: src/main.sh
line: 42
body: This function should handle the edge case where the array is empty.
>>> reply
author: reviewer
created: 2025-05-01T14:35:00Z
body: Good catch, will fix.

--- issue-comment
author: someone
created: 2025-05-01T15:00:00Z
body: LGTM, just the one comment above.
```

Status output:

```text
--- check
name: CI
status: completed
conclusion: success

--- check
name: Lint
status: completed
conclusion: failure
```

## `--since` Options

| Value | Behavior |
|---|---|
| *(omitted)* | All comments |
| `last-commit` | Comments after the latest commit timestamp |
| `<SHA>` | Comments after that commit's timestamp |
| `YYYY-MM-DD` | Comments on or after that date (UTC) |
| `YYYY-MM-DDTHH:mm:ss` | Comments on or after that datetime (UTC) |

## Agent Skills

Integrations for AI coding assistants that use `gh-pr-context`.

### Claude Code GitHub Action

This repo includes a [Claude Code Action](https://github.com/anthropics/claude-code-action) workflow (`.github/workflows/claude.yml`) that enables AI-assisted PR reviews and issue handling directly in GitHub. Mention `@claude` in a PR comment or issue to trigger it.

### CLI Skills

### Install

```bash
npx skills@latest add akepo225/gh-pr-context
```

Or manually copy the skill:

```bash
mkdir -p ~/.agents/skills/deliver
cp skills/deliver/SKILL.md ~/.agents/skills/deliver/SKILL.md

mkdir -p ~/.agents/skills/to-issues
cp skills/to-issues/SKILL.md ~/.agents/skills/to-issues/SKILL.md
```

Requires `gh-pr-context` on PATH — see [Install](#install) above.

### Reference

| Skill | Description |
|---|---|
| [deliver](skills/deliver/SKILL.md) | Pre-delivery QA & review workflow. Fetches PR comments, CI status, and failed check logs. Invoke before creating a PR. |
| [to-issues](skills/to-issues/SKILL.md) | Break a plan into independently-grabbable issues using vertical slices. Based on [Matt Pocock's agent skills](https://github.com/mattpocockuk/agent-skills). |

The to-issues skill is based on [Matt Pocock's agent skills](https://github.com/mattpocockuk/agent-skills), used under the MIT license.

## License

MIT
