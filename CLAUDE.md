# gh-pr-context

Bash CLI that fetches PR context (comments, CI status, failure logs) for LLM coding assistants.

## Release Process

When creating a new release:

1. Bump `version="X.Y.Z"` in `gh-pr-context` (line 4)
2. Add a `## vX.Y.Z` section to `CHANGELOG.md`
3. Commit both changes
4. Tag: `git tag vX.Y.Z`
5. Push: `git push && git push --tags`

The CI version/tag consistency check will fail if the script version doesn't match the latest tag.
