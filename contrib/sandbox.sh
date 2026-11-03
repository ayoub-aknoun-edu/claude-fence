# Try cfence safely: `source contrib/sandbox.sh` gives THIS shell a throwaway HOME (all XDG dirs too)
# and a fake `claude` that prints which profile it ran under. Your real accounts and config are not touched.
# Leave by closing the terminal (or `exit` if you started a subshell). Works in bash and zsh.
if [ -n "${ZSH_VERSION:-}" ]; then _cf_here="${(%):-%x}"; else _cf_here="${BASH_SOURCE[0]}"; fi
_cf_repo="$(cd "$(dirname "$_cf_here")/.." && pwd)"
export HOME="$(mktemp -d)"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
unset CLAUDE_CONFIG_DIR CFENCE_PROFILE CFENCE_PID CFENCE_PROFILES_DIR TMUX TMUX_PANE
mkdir -p "$HOME/.claude" "$HOME/fakebin" "$HOME/work/a" "$HOME/oss/b"
echo '{"oauthAccount":{"emailAddress":"main@work.com","organizationName":"Work"},"mcpServers":{"plane":{"command":"uvx"}}}' > "$HOME/.claude.json"
printf '#!/bin/sh\necho "FAKE claude  cfg=${CLAUDE_CONFIG_DIR:-<main>}  prof=${CFENCE_PROFILE:-}  args=$*"\n' > "$HOME/fakebin/claude"
chmod +x "$HOME/fakebin/claude"
export PATH="$HOME/.local/share/cfence/shims:$_cf_repo/bin:$HOME/fakebin:/usr/bin:/bin"
export SHELL=/bin/bash
cd "$HOME" || return
echo "cfence sandbox: HOME=$HOME"
echo "config will go to $XDG_CONFIG_HOME/cfence (must be under the sandbox HOME)"
unset _cf_here _cf_repo
