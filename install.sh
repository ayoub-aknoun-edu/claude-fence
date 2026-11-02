#!/usr/bin/env bash
# cfence installer — idempotent. Usage: ./install.sh [--prefix DIR] [--yes] [--no-rc] [--copy]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PREFIX="${PREFIX:-$HOME/.local/bin}"; YES=""; NORC=""; COPY=0
while [[ $# -gt 0 ]]; do case "$1" in
  --prefix) PREFIX="${2:?--prefix needs a dir}"; shift;; --yes|-y) YES="--yes";; --no-rc) NORC="--no-rc";; --copy) COPY=1;;
  -h|--help) sed -n '2p' "$0"; exit 0;; *) echo "unknown option: $1" >&2; exit 1;; esac; shift; done

command -v python3 >/dev/null || { echo "python3 is required (stdlib only)." >&2; exit 1; }
command -v claude  >/dev/null || echo "note: 'claude' not found on PATH yet — install Claude Code first (https://docs.claude.com/claude-code)" >&2
[[ "${BASH_VERSINFO[0]}" -ge 3 ]] || { echo "bash >= 3.2 required" >&2; exit 1; }

mkdir -p "$PREFIX"
if (( COPY )); then install -m 0755 "$HERE/bin/cfence" "$PREFIX/cfence"; else ln -sf "$HERE/bin/cfence" "$PREFIX/cfence"; fi
echo "✓ installed $PREFIX/cfence $( ((COPY)) && echo '(copy)' || echo '(symlink to this clone — git pull to update)')"
case ":$PATH:" in *":$PREFIX:"*) ;; *) echo "note: $PREFIX is not on your PATH";; esac

"$PREFIX/cfence" init $YES $NORC
echo; "$PREFIX/cfence" doctor || echo "(doctor warnings above are normal until you open a new shell)"
