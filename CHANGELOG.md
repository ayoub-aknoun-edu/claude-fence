# Changelog

## 0.1.0 — unreleased
- Profiles via `CLAUDE_CONFIG_DIR`, shared skills/agents/rules/hooks/plugins/settings by symlink, optional shared state (`--share-state`).
- Directory fences (longest prefix, git-worktree aware) enforced by a `claude` shim; fail-closed on missing profiles / unreadable bindings.
- Credential environment variables stripped inside fenced directories; environment cannot override a fence.
- Shared MCP registry synced into every profile.
- tmux status label (window keeps its `claude` name: cfence `exec`s into claude).
- `doctor`, `env` (bash/zsh/fish), `uninstall`; installer for bash/zsh.
