# claude-fence (`cfence`)

**Fence your Claude Code accounts to directories.** Type `claude` anywhere — the right account is used, and the wrong one is *refused*.

```console
~/work/acme-api   $ claude            # ▶ claude [work2] (fenced)
~/oss/my-project  $ claude            # ▶ claude [personal] (fenced)
~/work/acme-api   $ claude-personal   # ✗ fenced to 'work2' but 'personal' was requested. Use --force …
```

<p align="center"><img src="assets/demo.gif" alt="cfence demo: each directory uses its own Claude account; the wrong one is refused" width="760"></p>

If you have a personal plan *and* one or more company accounts, you have probably hit one of these:

- you `/logout` + `/login` all day, and forget which account you're on;
- a client/employer **forbids** using your personal account on their code (or the other way round) and a slip is a real problem;
- your skills, agents, MCP servers and memory live in `~/.claude` and you don't want to rebuild them per account;
- you spawn Claude from scripts, `tmux` windows, git worktrees or sub-processes and the account silently changes.

`cfence` solves these with Claude Code's own `CLAUDE_CONFIG_DIR` mechanism — no credential swapping, no patching, no daemon.

## Features

| | |
|---|---|
| **Directory fences** | `cfence bind work ~/work` → every `claude` under `~/work` (and its git worktrees) uses `work`. Longest-prefix wins, so nested exceptions work. |
| **Fails closed** | Asking for another account inside a fenced dir is refused. A binding to a deleted profile *refuses to launch* instead of falling back to your default account. |
| **Works everywhere `claude` is called** | A `claude` shim on `PATH` (not a shell function) covers scripts, `tmux` panes, `git worktree` helpers, `claude -p` from inside Claude, tmux-resurrect, etc. |
| **Shared brain, separate logins** | Skills, agents, commands, rules, hooks, plugins and `settings.json` are symlinked from `~/.claude` into every profile. |
| **Optional shared memory** | `cfence add work2 --share-state` also shares sessions, memory and history with your main profile (for accounts of the *same* org/person). Personal profiles stay private by default. |
| **Shared MCP servers** | `cfence mcp share <server>` copies a user-scope MCP server into every profile, kept in sync automatically. |
| **tmux status** | The active profile is shown (with a stable colour) in the tmux status bar while `claude` runs in a pane. |
| **Safe by default** | Profile dirs `0700`, secrets `0600`, no code is ever `source`d, JSON files are never rewritten if they fail to parse, `doctor` checks everything. |
| **Tiny** | One bash file (bash ≥ 3.2) + `python3` stdlib. No Node, no Rust, no daemon. |

## Install

```sh
git clone https://github.com/ayoub-aknoun-edu/claude-fence && cd claude-fence
./install.sh            # symlinks cfence into ~/.local/bin, creates shims, offers to edit your shell rc
exec "$SHELL"           # pick up the new PATH
cfence doctor           # everything should be ✓
```

Options: `--prefix DIR`, `--copy` (copy instead of symlink), `--yes` (no prompts), `--no-rc` (don't touch rc files; add `export PATH="$HOME/.local/share/cfence/shims:$PATH"` yourself — shim dir **must come first**). Supports bash, zsh and fish (fish is exercised in CI; its PATH line is session-scoped, so nothing persists after `uninstall`; for `--no-rc` on fish add `set -gx PATH $HOME/.local/share/cfence/shims (string match -v -- $HOME/.local/share/cfence/shims $PATH)`). Uninstall: `./uninstall.sh` (keeps your profiles and logins).

Requirements: Claude Code, bash ≥ 3.2, python3. The test suite runs in CI on Linux and on macOS (including stock bash 3.2); it has not been run on a real Mac desktop session or on WSL — reports welcome. Windows: use WSL.

## Quick start

```sh
cfence add work2 --share-state --login   # 2nd company account, shares memory with main; opens browser to sign in
cfence add personal --login              # personal account, fully private
cfence bind work2    ~/work/other-org
cfence bind personal ~/oss
cfence bind personal ~/side-projects
cfence list                              # profiles, accounts, which one is active here
```

Your existing `~/.claude` login is the built-in profile **`main`** — untouched, and the default wherever nothing is bound.

| Command | What it does |
|---|---|
| `claude` | Launch with the profile for the current directory. |
| `claude-<name>` | One-off override for that profile (refused inside a fence unless `--force`). |
| `cfence which [-q]` | Which profile applies here, and why (explicit / inherited / bound path / default). |
| `cfence bind <profile> [dir]` · `unbind [dir]` · `bindings` | Manage fences. |
| `cfence env [name] [--fish]` | Print `export CLAUDE_CONFIG_DIR=…` for IDEs/other tools: `eval "$(cfence env personal)"` (honours fences). |
| `cfence mcp share|unshare|list|sync` | Shared MCP registry. |
| `cfence launch [-p name] [--force] -- <cmd>` | Run any command (editor, app) under the profile for the current directory. |
| `cfence statusline [--plain]` | Print the active profile for a Claude Code `statusLine`. |
| `cfence rename <old> <new>` | Rename a profile; its shim and every directory binding follow. |
| `cfence remove <name> --yes` | Delete a profile (login + private data). Shared files and main are never touched. |
| `cfence completion bash\|zsh\|fish` | Print a shell completion script. |
| `cfence doctor` | Diagnose PATH, shims, modes, diverged files, stale bindings, tmux env leaks. |

### Shell completion

Tab-complete commands, profile names and directories (bash, zsh, fish):

```bash
echo 'eval "$(cfence completion zsh)"'  >> ~/.zshrc      # zsh
echo 'eval "$(cfence completion bash)"' >> ~/.bashrc     # bash
cfence completion fish > ~/.config/fish/completions/cfence.fish   # fish
```

### IDEs and GUI apps (VS Code, JetBrains, …)

Anything that runs `claude` **inside a shell** is already covered: the integrated terminal of VS Code or JetBrains, tmux panes, scripts. The shim does the work.

Editor *extensions* start Claude themselves, with the editor's environment, so the shim never runs. Start the editor through cfence instead:

```bash
cd ~/work/acme-api
cfence launch code .          # VS Code and its Claude extension get this directory's account
cfence launch -p personal -- idea .
```

`launch` applies the same rules as `claude`: the directory's profile (or `-p`), the fence guard (`--force` to override), credential variables stripped inside fenced directories. It then runs your command with that profile's `CLAUDE_CONFIG_DIR`.

**Limits you should know about**

- An editor has **one** environment per running process. If VS Code is already open, `code .` hands the folder to the existing process and the new window keeps the *first* window's account. cfence warns when it sees a known editor already running. Close it first, or use a separate instance per account: `cfence launch code --user-data-dir ~/.vscode-personal .`
- Launching from a desktop icon, Spotlight or the Dock bypasses cfence entirely; make a launcher that calls `cfence launch`, or start the editor from a terminal.
- The extension reading `CLAUDE_CONFIG_DIR` from the editor's environment is expected, but not yet verified for every editor/version. If an extension shows the wrong account, tell us (`cfence doctor` output + editor version).

### Windows (WSL2)

cfence is a bash tool, so **native Windows (PowerShell/cmd) is not supported**. **WSL2 is expected to work**: it is a real Linux userland, and cfence's Linux test suite is what runs in CI. It has not been run on WSL itself yet, so treat it as unverified and please report what you find.

- Install and run cfence **inside** the WSL distro (`./install.sh` there), and keep `~` and your fenced projects in the **Linux filesystem** (`~/projects/...`), not under `/mnt/c/...`. Windows drives have unreliable symlinks and permissions. `cfence doctor` detects WSL and warns about this.
- `claude` in the WSL terminal and in tmux behaves exactly as on Linux.
- VS Code on Windows connected to WSL (Remote - WSL): `cfence launch code .` from WSL starts the Windows app, whose remote server may be an already-running process; see the IDE limits above. Unverified.

### Claude statusline

Show which account a session is really running under, inside Claude Code itself. `cfence statusline` reads the session's `CLAUDE_CONFIG_DIR`, so it is correct even when you forced another profile. Add to `~/.claude/settings.json` (shared by every profile, so one edit covers all of them):

```json
{ "statusLine": { "type": "command", "command": "cfence statusline" } }
```

Already have a status line? Prepend the segment:

```bash
#!/usr/bin/env bash
input="$(cat)"
printf '%s ' "$(cfence statusline </dev/null)"
printf '%s' "$input" | your-existing-statusline
```

The statusline is shown by the terminal UI; the VS Code extension does not display it (confirmed with `cfence launch code`: the extension itself shows the account, the segment does not appear). `--plain` (or `NO_COLOR=1`) prints `[name]` without colour. It never fails and never blocks on stdin.

### tmux

```sh
cat contrib/tmux.conf >> ~/.tmux.conf   # then: tmux source-file ~/.tmux.conf
```

Adds `⬤ profile` to `status-right` and a `●` in window names while `claude` runs. If you use tmux-continuum, keep the snippet *before* its load line (it hooks `status-right`).

## How it works

```
claude ──▶ shim ──▶ cfence run ──▶ picks profile ──▶ exec <real claude>   (CLAUDE_CONFIG_DIR=…)
                         │
   precedence:  explicit (claude-<name> / -p)  >  inherited from a parent claude  >  directory binding  >  main
   guard:       if the directory is fenced and the choice differs → refuse (exit 3)
```

* **Profiles** live in `~/.claude-profiles/<name>/` (own `.credentials.json`, `.claude.json`, history…). `main` = `~/.claude`.
* **Bindings** are in `~/.config/cfence/bindings` (`<profile> <absolute path>`), *outside* your repos, so you never commit "personal" into a company repo or your public dotfiles.
* **Worktrees:** if the cwd isn't bound, cfence also tries the git *main worktree* — so `git worktree add ../repo-feature` inherits the repo's fence.
* **Real binary:** found by removing the shim dir from `PATH`; Claude's self-updater keeps working.
* **Per-launch sync:** shared symlinks and the MCP registry are re-applied on launch (cheap; Python runs only when the registry changed).

### Subagents, tmux windows, Codex bridges

| Scenario | Account used |
|---|---|
| Claude's built-in subagents / Task tool | Same process → same account. |
| `claude -p …` run by Claude's Bash tool | Inherits the parent's profile — but only if the recorded parent PID is a *real ancestor* (leaked/forged env vars are ignored), and **never** out of a fence. |
| New tmux window/pane (e.g. a `cw`-style worktree helper, tmux-resurrect restore) | tmux does *not* pass the caller's env to new panes, so the fresh shell → shim resolves by **directory binding** (+ worktree fallback). Bind the repo and it just works. |
| Codex/other-agent bridges that shell out to `claude` (e.g. `cx takeover claude`) | Go through the shim → resolved by directory. Bridges that launch *Codex* are unaffected (different tool/account). |
| IDE extensions, GUI launchers, anything that bypasses your shell `PATH` | **Not covered** → `eval "$(cfence env <profile>)"` or set `CLAUDE_CONFIG_DIR` in that tool. |

## Worst cases & guarantees

| Situation | Behaviour |
|---|---|
| Asking for account B inside a directory fenced to A | Refused (exit 3). Override only with the explicit `--force` flag (deliberately **not** settable via environment). |
| Same folder, another spelling (`~/Work` vs `~/work` on case-insensitive macOS/Windows drives, bind mounts, a hand-edited non-canonical path) | Fences match by **inode**, not just by string, so every spelling of a fenced folder is fenced. Re-binding or unbinding replaces/removes all spellings. |
| Fence points at a deleted/renamed profile | Refused — **never** falls back to `main`. |
| `CLAUDE_CONFIG_DIR` leaked into your shell / tmux server | Ignored by `claude` (cfence always sets or unsets it explicitly); `doctor` warns about it. |
| `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` etc. in the environment (they outrank the profile login) | Stripped (with a warning) inside fenced directories; `doctor` warns about them elsewhere. |
| Shim dir not first on `PATH` (so plain `claude` bypasses cfence) | `doctor` fails loudly. This is the one silent-failure mode — run `cfence doctor` after setup. |
| `~/.claude.json` of a profile is corrupt | MCP sync aborts without writing; a one-time `.cfence-bak` backup is made before any rewrite. |
| `kill <cfence pid>` on the wrapper (tmux only) | In tmux the wrapper stays alive to clear the pane label, so killing *only the wrapper* leaves `claude` running (closing the pane / Ctrl-C is fine). Set `CFENCE_NO_TMUX=1` to `exec` instead. |
| Two profiles share state and Claude rewrites a symlinked file | `doctor` reports diverged (non-symlink) shared items. |
| Deleting a `--share-state` profile | Only the profile dir is removed; symlink *targets* in `~/.claude` (your memory!) are never followed. |
| Shared-state profile with a **personal** account | Don't. Sessions/memory would mix; keep personal profiles private (the default). |

Known limits: shared `settings.json` applies to every profile, so account-level keys in it (`apiKeyHelper`, `forceLoginOrgUUID`, `env.ANTHROPIC_*`) leak across accounts — `doctor` warns. `mcp share` copies MCP secrets into every profile (files are `0600`). Concurrent writes to `~/.claude.json` by a running Claude and by cfence's MCP sync are not locked (rare; a one-time backup is kept). fences are *ergonomic guard rails* for one human on one machine, not a security boundary against someone with shell access. OAuth connectors (Slack, Figma, claude.ai MCPs…) belong to the **account**, not the profile, so they differ per login by design.

**Not for:** pooling subscriptions to dodge rate limits or terms of service. This tool is for keeping *your own* accounts (work/personal/client) separated.

## Configuration

`~/.config/cfence/config` (plain `key=value`, never sourced as code):

```ini
share_extra=AGENTS.md scripts      # extra items from ~/.claude to symlink into every profile
real_claude=/path/to/claude        # only if auto-detection fails
```

Env: `CFENCE_QUIET=1` (no banner), `CFENCE_NO_TMUX=1` (no pane indicator), `CFENCE_PROFILES_DIR`.

## Alternatives

The space is busy; pick what fits. [clauth](https://github.com/uwuclxdy/clauth) (accounts + usage monitor/TUI), [claude-code-account-switcher](https://github.com/Nemo-Illusionist/claude-code-account-switcher) (Rust, activates on `cd`), [claude-code-profiles](https://github.com/quinnjr/claude-code-profiles), [ccs](https://github.com/vika2603/ccs), [silo](https://github.com/0xNyk/silo). `cfence` focuses on **enforcement** (fail-closed fences), **coverage** (subprocesses, tmux, worktrees via a shim) and **sharing** (memory, MCPs, skills).

## Development

```sh
bash tests/run.sh        # runs in a throwaway $HOME with a fake `claude`; never touches real accounts
```

PRs welcome — please add a test for every behaviour change. MIT licensed.
