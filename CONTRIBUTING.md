# Contributing

Thanks for helping! The project is one bash script (`bin/cfence`), an installer and a test suite.

- **Run the tests:** `bash tests/run.sh` (isolated: throwaway `$HOME`, fake `claude`, private tmux socket). Run it with `/bin/bash` too on macOS — we target **bash 3.2** (no associative arrays, `mapfile`, `${var,,}`; guard empty arrays under `set -u`).
- **Lint:** `shellcheck -x -S warning bin/cfence install.sh uninstall.sh tests/run.sh`.
- **Every behaviour change needs a test.** Security-relevant behaviour (the fence must fail *closed*) needs a regression test that fails without your change.
- **Manual testing:** `HOME=$(mktemp -d)` is **not** enough — unset `XDG_CONFIG_HOME`/`XDG_DATA_HOME` too, or you will write to your real cfence config.
- **Design rules:** never `source` user files; validate every profile name and path that reaches the filesystem; refuse rather than fall back to another account; keep `claude` the foreground process (no lingering wrapper).
- Conventional commit messages (`feat:`, `fix:`, `docs:`, `test:`).

- **Demo GIF:** `assets/demo.gif` is generated, not hand-made: `python3 contrib/demo/record.py out/` writes a cast from a real shell session in a throwaway `$HOME` with a fake `claude`; render it with [agg](https://github.com/asciinema/agg) (`agg out/demo.cast assets/demo.gif --theme dracula --font-size 18 --speed 1.5 --idle-time-limit 2`).

## Trying it safely

`source contrib/sandbox.sh` gives your current shell a throwaway `HOME` (and XDG dirs) plus a fake `claude`, so you can run any `cfence` command without touching real accounts. Close the terminal to leave.

## Releasing (maintainers)

1. Open a `chore: release X.Y.Z` PR: set `CFENCE_VERSION` in `bin/cfence` and rename `## Unreleased` in `CHANGELOG.md` to `## X.Y.Z — YYYY-MM-DD` (keep an empty `## Unreleased` above it). Merge it.
2. Tag the merge commit and push the tag: `git tag -a vX.Y.Z <commit> -m "claude-fence vX.Y.Z" && git push origin vX.Y.Z`.
3. The `release` workflow publishes the GitHub release from the changelog section. It fails (and publishes nothing) if the tag doesn't match `CFENCE_VERSION`, isn't on `main`, or has no changelog entry. Never move or reuse a published tag; ship a new patch instead.
