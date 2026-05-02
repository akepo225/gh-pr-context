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

```
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

```
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

## License

MIT
