#!/usr/bin/env bash
set -euo pipefail

REPO="akepo225/gh-pr-context"
BRANCH="master"
SCRIPT_NAME="gh-pr-context"
RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"

die() {
  echo "error: $1" >&2
  exit 1
}

install_dir="${INSTALL_DIR:-${1:-$HOME/.local/bin}}"

mkdir -p "$install_dir" || die "failed to create directory: $install_dir"

tmp=$(mktemp) || die "failed to create temp file"
trap 'rm -f "$tmp"' EXIT

curl -fsSL "$RAW_BASE/$SCRIPT_NAME" -o "$tmp" || die "failed to download $SCRIPT_NAME"

mv "$tmp" "$install_dir/$SCRIPT_NAME" || die "failed to write to $install_dir/$SCRIPT_NAME"
chmod +x "$install_dir/$SCRIPT_NAME" || die "failed to set executable permissions on $install_dir/$SCRIPT_NAME"

echo "installed $SCRIPT_NAME to $install_dir/$SCRIPT_NAME"
