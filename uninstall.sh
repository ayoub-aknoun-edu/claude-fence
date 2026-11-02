#!/usr/bin/env bash
# Removes shims, the PATH block and the cfence binary. Keeps profiles, logins, bindings.
set -euo pipefail
PREFIX="${PREFIX:-$HOME/.local/bin}"
[[ -x "$PREFIX/cfence" ]] && "$PREFIX/cfence" uninstall
rm -f "$PREFIX/cfence" && echo "✓ removed $PREFIX/cfence"
