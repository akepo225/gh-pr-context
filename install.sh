#!/usr/bin/env bash
set -euo pipefail

REPO="akepo225/gh-pr-context"
GH_PR_CONTEXT_VERSION="${GH_PR_CONTEXT_VERSION:-master}"
SCRIPT_NAME="gh-pr-context"

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

_tmpfiles=()
cleanup_tmpfiles() { rm -f "${_tmpfiles[@]}" 2>/dev/null || true; }
trap cleanup_tmpfiles EXIT

download() {
  local src="$1" dest="$2"
  local tmp
  tmp=$(mktemp 2>/dev/null) || die "failed to create temp file"
  _tmpfiles+=("$tmp")
  curl -fsSL "$RAW_BASE/$src" -o "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; die "failed to download $src"; }
  mv "$tmp" "$dest" 2>/dev/null || { rm -f "$tmp"; die "failed to write to $dest"; }
  _tmpfiles=("${_tmpfiles[@]//$tmp}")
  chmod +x "$dest" 2>/dev/null || true
}

_is_windows() {
  [[ "$(uname -s 2>/dev/null)" == MINGW* || "$(uname -s 2>/dev/null)" == MSYS* || "$(uname -s 2>/dev/null)" == CYGWIN* ]]
}
ON_WINDOWS=""
is_windows() {
  if [ -z "$ON_WINDOWS" ]; then
    if _is_windows; then ON_WINDOWS=1; else ON_WINDOWS=0; fi
  fi
  [ "$ON_WINDOWS" = "1" ]
}

_find_python_cmd() {
  if command -v python >/dev/null 2>&1 && python --version >/dev/null 2>&1; then
    echo "python"
  elif command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then
    echo "python3"
  elif command -v py >/dev/null 2>&1 && py -3 --version >/dev/null 2>&1; then
    echo "py -3"
  else
    echo ""
  fi
}

_windows_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1" 2>/dev/null || echo "$1"
  else
    local p="$1"
    if [[ "$p" =~ ^/([a-zA-Z])/ ]]; then
      p="${p/#\/${BASH_REMATCH[1]}\//${BASH_REMATCH[1],,}:/}"
    fi
    echo "$p"
  fi
}

download "$SCRIPT_NAME" "$install_dir/$SCRIPT_NAME"
echo "installed $SCRIPT_NAME to $install_dir/$SCRIPT_NAME"

if is_windows; then
  download "${SCRIPT_NAME}.py" "$install_dir/${SCRIPT_NAME}.py"
  local_python=$(_find_python_cmd)
  if [ -z "$local_python" ]; then
    echo "warning: python not found; ${SCRIPT_NAME}.cmd will not work until Python is installed" >&2
  fi
  cat > "$install_dir/${SCRIPT_NAME}.cmd" << CMDEOF
@echo off
${local_python:-python} "%~dp0gh-pr-context.py" %*
CMDEOF
  echo "installed ${SCRIPT_NAME}.cmd to $install_dir/${SCRIPT_NAME}.cmd"
fi

resolved=$(command -v "$SCRIPT_NAME" 2>/dev/null) || true
if [ -z "$resolved" ]; then
  echo "warning: $SCRIPT_NAME is not on your PATH" >&2
  echo "  Add it by running:" >&2
  if is_windows; then
    echo "    \$env:PATH = \"$(_windows_path "$install_dir");\" + \$env:PATH" >&2
  else
    echo "    export PATH=\"$install_dir:\$PATH\"" >&2
  fi
fi
