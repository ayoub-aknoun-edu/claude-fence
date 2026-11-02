# Contributing

Thanks for helping! The project is one bash script (`bin/cfence`), an installer and a test suite.

- **Run the tests:** `bash tests/run.sh` (isolated: throwaway `$HOME`, fake `claude`, private tmux socket). Run it with `/bin/bash` too on macOS — we target **bash 3.2** (no associative arrays, `mapfile`, `${var,,}`; guard empty arrays under `set -u`).
- **Lint:** `shellcheck -x -S warning bin/cfence install.sh uninstall.sh tests/run.sh`.
- **Every behaviour change needs a test.** Security-relevant behaviour (the fence must fail *closed*) needs a regression test that fails without your change.
- **Manual testing:** `HOME=$(mktemp -d)` is **not** enough — unset `XDG_CONFIG_HOME`/`XDG_DATA_HOME` too, or you will write to your real cfence config.
- **Design rules:** never `source` user files; validate every profile name and path that reaches the filesystem; refuse rather than fall back to another account; keep `claude` the foreground process (no lingering wrapper).
- Conventional commit messages (`feat:`, `fix:`, `docs:`, `test:`).
