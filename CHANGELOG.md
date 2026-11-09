# Changelog

## Unreleased
- **fix:** `--force` now works through the shims (`claude-work2 --force`, `claude --force`). It used to be passed on to Claude instead of lifting the fence, so the override was only usable via `cfence run --force`.

## 0.2.3 — 2026-11-03
- **docs:** new README demo (real tmux session: per-folder accounts, refusal, worktrees, `launch`, tmux status badge) and a reworked reproducible recorder (`contrib/demo/record.py`); `contrib/sandbox.sh` gives a throwaway HOME to try cfence without touching real accounts.
- **hardening:** MCP sync and profile seeding now detect a concurrent change to `.claude.json` (e.g. a running Claude) and redo their edit on the fresh content instead of overwriting it. README caveat for account-level keys in the shared `settings.json` now says how to keep them per profile.
- **docs:** a "Platform verification report" issue form for WSL2, real-Mac and VS Code reports, linked from the README.
- **release automation:** pushing a `v*` tag now publishes the GitHub release from the matching CHANGELOG section, and refuses if the tag doesn't match `CFENCE_VERSION`, isn't on `main`, or has no changelog entry.

## 0.2.2 — 2026-11-03
- **fix:** linked worktrees of a **bare repo** now inherit the bare directory's binding (before, they silently fell back to `main`). Submodules and `--separate-git-dir` are now covered by tests; for `--separate-git-dir` repos, bind the git directory as well (documented).

## 0.2.1 — 2026-11-03
- **fish fixes:** the PATH line is now session-scoped (`set -gx PATH …`) so nothing persists in fish's universal variables after `uninstall`; `uninstall` removes the stale `fish_user_paths` entry that earlier versions left; `cfence env --fish` quotes paths; CI now tests fish on Linux and macOS. Existing fish users: run `cfence uninstall && cfence init` once to replace the old block.

## 0.2.0 — 2026-11-02
- **Security fix:** directory bindings now match by inode as well as by path string, so a fenced folder stays fenced under another spelling (different case on case-insensitive filesystems such as default macOS APFS, bind mounts, hand-edited non-canonical paths). `bind`/`unbind` replace/remove every spelling of a folder.
- `doctor` detects WSL and warns when profiles or fenced directories are on a Windows drive (`/mnt/<x>/`). README documents WSL2 support (unverified) and that native Windows is unsupported.
- `cfence launch [-p name] [--force] -- <cmd>`: start an editor or any app under the directory's profile, with the same fence rules as `claude`; warns when a known editor is already running (it would reuse that process).
- `cfence statusline`: profile segment for Claude Code's `statusLine` (reads the real `CLAUDE_CONFIG_DIR`; colour or `--plain`; never fails or blocks).
- `cfence rename <old> <new>`: renames a profile and carries its shim and directory bindings along (rolls back if bindings cannot be updated).
- `cfence completion bash|zsh|fish`: tab-completion for commands, profile names and directories.

## 0.1.0 — 2026-11-02
- Profiles via `CLAUDE_CONFIG_DIR`, shared skills/agents/rules/hooks/plugins/settings by symlink, optional shared state (`--share-state`).
- Directory fences (longest prefix, git-worktree aware) enforced by a `claude` shim; fail-closed on missing profiles / unreadable bindings.
- Credential environment variables stripped inside fenced directories; environment cannot override a fence.
- Shared MCP registry synced into every profile.
- tmux status label (window keeps its `claude` name: cfence `exec`s into claude).
- `doctor`, `env` (bash/zsh/fish), `uninstall`; installer for bash/zsh.
