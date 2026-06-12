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
  if ! is_windows; then
    chmod +x "$dest" 2>/dev/null || die "failed to set executable bit on $dest"
  else
    chmod +x "$dest" 2>/dev/null || true
  fi
}

_is_windows() {
  local osname
  osname="$(uname -s 2>/dev/null)"
  [[ "$osname" == MINGW* || "$osname" == MSYS* || "$osname" == CYGWIN* ]]
}
ON_WINDOWS=""
is_windows() {
  if [ -z "$ON_WINDOWS" ]; then
    if _is_windows; then ON_WINDOWS=1; else ON_WINDOWS=0; fi
  fi
  [ "$ON_WINDOWS" = "1" ]
}

_python_version_ok() {
  local cmd="$1"
  shift
  local ver
  ver=$("$cmd" "$@" -c "import sys; print(sys.version_info >= (3, 11))" 2>/dev/null) || return 1
  [ "$ver" = "True" ]
}

_find_python_cmd() {
  if is_windows; then
    if command -v py >/dev/null 2>&1 && _python_version_ok py -3; then
      echo "py -3"
    elif command -v python >/dev/null 2>&1 && _python_version_ok python; then
      echo "python"
    elif command -v python3 >/dev/null 2>&1 && _python_version_ok python3; then
      echo "python3"
    else
      echo ""
    fi
  else
    if command -v python3 >/dev/null 2>&1 && _python_version_ok python3; then
      echo "python3"
    elif command -v python >/dev/null 2>&1 && _python_version_ok python; then
      echo "python"
    else
      echo ""
    fi
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
    die "no Python 3.11+ found (tried python, python3, py -3); install Python first"
  fi
  cat > "$install_dir/${SCRIPT_NAME}.cmd" << CMDEOF
@echo off
${local_python} "%~dp0gh-pr-context.py" %*
CMDEOF
  echo "installed ${SCRIPT_NAME}.cmd to $install_dir/${SCRIPT_NAME}.cmd"
fi

resolved=$(command -v "$SCRIPT_NAME" 2>/dev/null) || true
if is_windows; then
  if [ -z "$resolved" ]; then
    echo "warning: $SCRIPT_NAME is not on your PATH" >&2
  fi
  echo "  Add it to PowerShell PATH by running:" >&2
  echo "    \$env:PATH = \"$(_windows_path "$install_dir");\" + \$env:PATH" >&2
elif [ -z "$resolved" ]; then
  echo "warning: $SCRIPT_NAME is not on your PATH" >&2
  echo "  Add it by running:" >&2
  echo "    export PATH=\"$install_dir:\$PATH\"" >&2
fi
