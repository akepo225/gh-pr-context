# ADR-0001: Windows runtime strategy

## Status

Accepted - 2026-05-17.

## Context

`gh-pr-context` is currently a single-file Bash CLI with no build step. It shells out to `gh api` for GitHub data, uses `jq` for JSON processing, and depends on `git` for repository context. The current documented runtime requirements are `gh`, `jq`, `git`, and Bash 5.1+.

The project's output format is the product contract. Commands return terse plain text with stable delimiters, field ordering, sorting, nested review replies, flat issue comments, and one-line `error:` messages on failure. Any Windows-native runtime must preserve that behavior rather than introduce a new object or JSON output shape.

The [PRD](../../PRD.md) originally scoped Windows-native support out and targeted Bash environments such as macOS, Linux, WSL, and Git Bash. Issue #55 changes that direction: future slices need a native Windows strategy before implementation can begin. Existing project guidance already states that, if Bash becomes unwieldy, the fallback is a single Python file with no external dependencies and no Node.js.

## Decision Drivers

- Preserve the plain-text output contract with minimal formatting risk.
- Keep the implementation single-file and dependency-light.
- Avoid requiring `jq` for native Windows users.
- Provide a credible Windows install path.
- Keep test strategy focused on deterministic output parity.
- Minimize long-term maintenance burden across runtimes.

## Considered Options

### Single-file Python CLI

A native Windows entry point implemented as one Python file with no external Python packages. It uses the Python standard library for command parsing, JSON processing, subprocess execution, text encoding, and newline control. It shells out to `gh api` and `git` for the same external boundaries the Bash script uses today.

### Native PowerShell script

A `.ps1` rewrite using PowerShell-native facilities such as `Invoke-RestMethod`, `ConvertFrom-Json`, and the object pipeline.

### Compiled single-binary CLI

A Go or Rust rewrite could avoid requiring Python on Windows, but it would introduce a build toolchain, release artifacts, and cross-compilation workflow that conflict with the current no-build-step project model. There is no existing Go or Rust codebase precedent in this repository.

## Decision

Native Windows support will be implemented as a **single-file Python CLI with no external Python dependencies**.

For Windows-native usage:

- `gh` remains required and must be authenticated.
- `git` remains required for repository and branch context.
- Python 3.11 or later is required and must be discoverable as `py`, `python`, or `python3` by the installer or wrapper.
- `jq` is not required; Python's standard library `json` module replaces it.
- Bash is not required for the Windows-native entry point.
- Node.js remains out of scope.

The Python implementation should call external commands with argument arrays rather than shell strings, parse JSON with the standard library, write UTF-8 text, and normalize command output to LF line endings.

## Rationale

Python best matches the project's existing fallback direction while reducing risk to the output contract. The current Bash implementation constructs a precise text API from JSON data. A Python port can keep that model explicit: parse JSON into dictionaries and lists, sort deterministic collections, then write exact strings.

PowerShell has the strongest built-in availability on Windows, but it raises parity risk for this project. PowerShell's default object pipeline, array enumeration behavior, formatting system, and version differences between Windows PowerShell 5.1 and PowerShell 7 are useful for interactive administration but make byte-for-byte plain-text parity harder to reason about. Because `gh-pr-context` is consumed by LLMs, stable text output is more important than idiomatic shell objects.

Python also leaves open a future path to a shared cross-platform implementation. A PowerShell rewrite would almost certainly remain a Windows-only second codebase beside Bash, increasing formatter and test duplication.

## Output Compatibility Requirements

The Windows-native Python implementation must preserve the existing output contract:

- `comments` output uses `--- review-comment`, `--- issue-comment`, and `>>> reply` markers.
- Review comment replies are nested only under review comments.
- Issue comments remain flat.
- Comments are sorted ascending by `created_at`.
- Check output uses `--- check` records with the existing fields.
- Failed log output preserves the existing truncation behavior and notice.
- Errors exit non-zero and print one `error:` line to stderr.
- Output is UTF-8 text with LF newlines for deterministic parity across Windows and Unix-like environments.

The Python port must not introduce JSON wrapping, decorative headers, PowerShell objects, or platform-specific line endings into the command output.

## Install Path

The Windows install path should be documented separately from the existing curl-to-Bash installer. It should install or expose a command named `gh-pr-context` that runs the Python entry point through an available Python launcher. This work is tracked by #56.

The installer or setup documentation should:

- Prefer the Windows `py` launcher, then fall back to `python` or `python3`.
- Fail with a clear one-line error if Python 3.11 or later is unavailable.
- Detect and reject the Windows Store `python` app execution alias when it does not resolve to a real interpreter.
- Require `gh` and `git` on `PATH`.
- Avoid requiring `jq` or Bash for native Windows usage.
- Keep version pinning behavior equivalent to the existing installer where practical.

Python is not guaranteed on stock Windows installations, so the Windows documentation must explicitly call out how to install it. This is an accepted tradeoff because it protects output parity and reduces dual-runtime drift.

## Testing Strategy

The existing Bash test suite remains authoritative for the current Bash implementation and continues to run with:

```bash
bash test/run.sh
```

The Python implementation should add behavior tests that use mocked `gh` and `git` commands or fixture-backed subprocess boundaries. Tests should compare Python command output against golden examples derived from the existing Bash behavior, especially for:

- Comment sorting and reply nesting.
- `--since` timestamp filtering.
- Check status formatting.
- Failed log truncation.
- One-line stderr errors.
- UTF-8 and LF output normalization.

CI should add a `windows-latest` job for the Python entry point once the port exists. That work is tracked by #60, and the job should not require network access for unit tests.

## Consequences

Positive consequences:

- Aligns with the documented no-external-dependency Python fallback.
- Removes `jq` and Bash from the native Windows runtime path.
- Keeps output formatting explicit and easier to test for exact parity.
- Reduces the chance of PowerShell-specific formatting or newline drift.
- Gives future Windows implementation issues a clear dependency and testing target.

Negative consequences:

- Python is an additional Windows prerequisite and is not guaranteed on every stock Windows machine.
- Until a full Python port exists, Bash remains the only implemented runtime.
- Maintaining Bash and Python in parallel still carries duplication risk unless a later decision makes Python the primary cross-platform implementation.

This ADR supersedes the [PRD](../../PRD.md)'s original statement that Windows-native support is out of scope for future Windows support work. It does not change the current Bash CLI behavior by itself.
