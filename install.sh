#!/usr/bin/env bash
set -euo pipefail

REPO="akepo225/gh-pr-context"
GH_PR_CONTEXT_VERSION="${GH_PR_CONTEXT_VERSION:-master}"
SCRIPT_NAME="gh-pr-context"

# die prints an error message to stderr and exits with status 1.
die() {
  echo "error: $1" >&2
  exit 1
}

if [[ ! "$GH_PR_CONTEXT_VERSION" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
  die "invalid GH_PR_CONTEXT_VERSION: $GH_PR_CONTEXT_VERSION"
fi

RAW_BASE="https://raw.githubusercontent.com/$REPO/$GH_PR_CONTEXT_VERSION"

install_dir="${INSTALL_DIR:-${1:-$HOME/.local/bin}}"

mkdir -p "$install_dir" 2>/dev/null || die "failed to create directory: $install_dir"

tmp=$(mktemp 2>/dev/null) || die "failed to create temp file"
trap 'rm -f "$tmp"' EXIT

curl -fsSL "$RAW_BASE/$SCRIPT_NAME" -o "$tmp" >/dev/null 2>&1 || die "failed to download $SCRIPT_NAME"

mv "$tmp" "$install_dir/$SCRIPT_NAME" 2>/dev/null || die "failed to write to $install_dir/$SCRIPT_NAME"
chmod +x "$install_dir/$SCRIPT_NAME" 2>/dev/null || die "failed to set executable permissions on $install_dir/$SCRIPT_NAME"

echo "installed $SCRIPT_NAME to $install_dir/$SCRIPT_NAME"

resolved=$(command -v "$SCRIPT_NAME" 2>/dev/null) || true
if [ -z "$resolved" ]; then
  echo "warning: $SCRIPT_NAME is not on your PATH" >&2
  echo "  Add it by running:" >&2
  echo "    export PATH=\"$install_dir:\$PATH\"" >&2
fi
