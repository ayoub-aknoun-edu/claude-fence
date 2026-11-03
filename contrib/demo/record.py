#!/usr/bin/env python3
"""Record the README demo as an asciicast (v2): a real tmux session driving the real cfence.

Everything runs in a throwaway $HOME (all XDG dirs redirected) with a fake `claude`; your real
accounts and config are never touched. The tmux status bar uses contrib/tmux.conf unchanged.

Usage:  python3 contrib/demo/record.py [out_dir]      # writes out_dir/demo.cast
Render: agg -q --font-family "JetBrainsMono Nerd Font Mono,DejaVu Sans Mono" --font-size 16 --fps-cap 12 --idle-time-limit 3 --theme dracula --last-frame-duration 4 demo.cast demo.gif
"""
import fcntl, json, os, pty, random, select, shutil, struct, subprocess, sys, tempfile, termios, time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
COLS, ROWS = 100, 28
SOCK = "cfence-demo"
SHOW_HOME = "/home/you"          # what the viewer sees; the real sandbox home has the SAME length so tmux's layout is untouched

# The fake claude draws a small Claude-Code-like box, then the REAL `cfence statusline` row, and stays alive as a process
# named "claude" (exec -a) so tmux treats the pane as running claude and shows the profile badge.
FAKE_CLAUDE = r"""#!/bin/bash
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
json="$cfg/.claude.json"; [ -z "$CLAUDE_CONFIG_DIR" ] && json="$HOME/.claude.json"
who=$(python3 -c "import json;a=json.load(open('$json'))['oauthAccount'];print(a['emailAddress']+'  ('+a['organizationName']+')')")
printf '\033[38;5;209m╭────────────────────────────────────────────────────────╮\033[0m\n'
printf '\033[38;5;209m│\033[0m \033[38;5;209m✻\033[0m Claude Code   \033[1m%-38s\033[0m \033[38;5;209m│\033[0m\n' "$who"
printf '\033[38;5;209m│\033[0m   \033[2m%-52s\033[0m \033[38;5;209m│\033[0m\n' "$(pwd | sed "s|^$HOME|~|")"
printf '\033[38;5;209m╰────────────────────────────────────────────────────────╯\033[0m\n'
printf ' \033[2m> try "fix the failing test"\033[0m\n\n'
printf ' %s\n' "$(cfence statusline)"
exec -a claude sleep 3600
"""

TMUX_CONF = """set -g default-terminal "tmux-256color"
set -g status-style "bg=#1e2030,fg=#a5adcb"
set -g status-left "#[bold,fg=#8aadf4] cfence #[default]"
set -g status-right-length 80
set -g window-status-separator " "
set -g window-status-format " #I:#W "
set -g window-status-current-format "#[fg=#cad3f5,bold] #I:#W "
set -g status-right ""
set -g escape-time 0
set -g status-interval 1
set -g automatic-rename on
source-file {repo}/contrib/tmux.conf
"""

def setup(home):
    env = {"HOME": home, "PATH": f"{home}/.local/share/cfence/shims:{REPO}/bin:{home}/fakebin:/usr/bin:/bin",
           "TERM": "xterm-256color", "LANG": "C.UTF-8", "SHELL": "/bin/bash", "COLORTERM": "truecolor",
           "XDG_CONFIG_HOME": f"{home}/.config", "XDG_DATA_HOME": f"{home}/.local/share",
           "XDG_STATE_HOME": f"{home}/.local/state", "XDG_CACHE_HOME": f"{home}/.cache",
           }
    for d in (".claude", "work/acme-api", "oss/my-project", "fakebin"):
        os.makedirs(f"{home}/{d}", exist_ok=True)
    open(f"{home}/fakebin/claude", "w").write(FAKE_CLAUDE); os.chmod(f"{home}/fakebin/claude", 0o755)
    def account(path, email, org):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        json.dump({"oauthAccount": {"emailAddress": email, "organizationName": org}, "hasCompletedOnboarding": True}, open(path, "w"))
    account(f"{home}/.claude.json", "you@acme.com", "Acme")
    run = lambda *a, cwd=home: subprocess.run(a, env=env, check=True, capture_output=True, cwd=cwd)
    cf = f"{REPO}/bin/cfence"
    run(cf, "init", "--no-rc")
    run(cf, "add", "personal"); account(f"{home}/.claude-profiles/personal/.claude.json", "you@gmail.com", "Personal")
    run(cf, "add", "client");   account(f"{home}/.claude-profiles/client/.claude.json", "you@client.io", "Client Inc")
    run(cf, "bind", "main", f"{home}/work"); run(cf, "bind", "personal", f"{home}/oss")
    gi = ["git", "-c", "user.email=you@gmail.com", "-c", "user.name=you"]
    run(*gi, "init", "-q", cwd=f"{home}/oss/my-project"); run(*gi, "commit", "-q", "--allow-empty", "-m", "init", cwd=f"{home}/oss/my-project")
    open(f"{home}/bashrc", "w").write(r'PS1="\[\e[1;32m\]\w\[\e[0m\] \$ "' + "\n")
    conf = f"{home}/tmux.conf"; open(conf, "w").write(TMUX_CONF.format(repo=REPO))
    return env, conf

# (kind, text, seconds to wait afterwards): "type" types + Enter, "key" sends a tmux key, "tmux" runs a tmux command
SCRIPT = [
    ("type", "# 3 Claude accounts. Every folder gets its own, automatically.", 1.0),
    ("type", "cfence list", 2.8),
    ("type", "cfence bindings", 2.4),
    ("type", "cd ~/work/acme-api", 0.6),
    ("type", "claude", 3.2),
    ("key", "C-c", 0.5),
    ("type", "clear", 0.3),
    ("type", "cd ~/oss/my-project", 0.6),
    ("type", "claude", 3.2),
    ("key", "C-c", 0.5),
    ("type", "clear", 0.3),
    ("type", "# the wrong account is refused, not silently used:", 0.8),
    ("type", "claude-client", 3.2),
    ("type", "clear", 0.3),
    ("type", "# git worktrees inherit the fence:", 0.6),
    ("type", "git worktree add -q ../my-project-fix && cd ../my-project-fix", 1.2),
    ("type", "cfence which", 3.0),
    ("type", "clear", 0.3),
    ("type", "# IDEs and scripts get the right account too:", 0.6),
    ("type", "cfence launch -- sh -c 'echo $CLAUDE_CONFIG_DIR'", 2.8),
    ("type", "clear", 0.3),
    ("type", "# tmux: one window per account, badge follows the pane", 0.8),
    ("type", "cd ../my-project && claude", 2.6),
    ("tmux", "new-window -c {home}/work/acme-api", 0.8),
    ("type", "claude", 2.6),
    ("tmux", "previous-window", 2.0),
    ("tmux", "next-window", 2.0),
    ("tmux", "previous-window", 2.0),
]

def main():
    home = "/tmp/%s/yo" % random.choice("abcdefghijklmnopqrstuvwxyz")   # 9 chars, like "/home/you"
    assert len(home) == len(SHOW_HOME), home
    if os.path.exists(home): sys.exit(f"{home} already exists; remove it and retry")
    os.makedirs(home)
    try:
        env, conf = setup(home)
        tm = lambda *a: subprocess.run(["tmux", "-L", SOCK, *a], env=env, check=True, capture_output=True)
        subprocess.run(["tmux", "-L", SOCK, "kill-server"], env=env, capture_output=True)
        tm("-f", conf, "new-session", "-d", "-s", "demo", "-x", str(COLS), "-y", str(ROWS), "-c", home, f"bash --rcfile {home}/bashrc -i")
        tm("set", "-g", "default-command", f"bash --rcfile {home}/bashrc -i")
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        cenv = dict(env); cenv.pop("TMUX", None)
        client = subprocess.Popen(["tmux", "-L", SOCK, "attach", "-t", "demo"], stdin=slave, stdout=slave, stderr=slave, env=cenv, close_fds=True)
        os.close(slave)
        events, t0 = [], time.time()
        def pump(duration):
            end = time.time() + duration
            while time.time() < end:
                r, _, _ = select.select([master], [], [], 0.02)
                if r:
                    try: data = os.read(master, 8192)
                    except OSError: return
                    if data: events.append([round(time.time() - t0, 3), "o", data.decode("utf-8", "replace")])
        pump(0.8); events.clear(); t0 = time.time()
        events.append([0.0, "o", "\x1b[2J\x1b[H"]); tm("send-keys", "-t", "demo", "clear", "Enter"); pump(0.6)
        for kind, text, wait in SCRIPT:
            if kind == "type":
                for ch in text:
                    tm("send-keys", "-t", "demo", "-l", ch); pump(random.uniform(0.025, 0.06))
                pump(0.25); tm("send-keys", "-t", "demo", "Enter")
            elif kind == "key": tm("send-keys", "-t", "demo", text)
            else: tm(*text.format(home=home).split(" "))
            pump(wait)
        pump(0.5)
        header = {"version": 2, "width": COLS, "height": ROWS, "timestamp": int(t0), "env": {"SHELL": "/bin/bash", "TERM": "xterm-256color"}}
        os.makedirs(OUT, exist_ok=True)
        with open(os.path.join(OUT, "demo.cast"), "w") as f:
            f.write(json.dumps(header) + "\n")
            for e in events:                       # same-length swap keeps tmux's absolute cursor positioning intact
                e[2] = e[2].replace(home, SHOW_HOME)
                f.write(json.dumps(e) + "\n")
        print("wrote", os.path.join(OUT, "demo.cast"), f"({len(events)} events, {events[-1][0]:.0f}s)")
        client.terminate()
    finally:
        subprocess.run(["tmux", "-L", SOCK, "kill-server"], env={"PATH": "/usr/bin:/bin"}, capture_output=True)
        shutil.rmtree(os.path.dirname(home), ignore_errors=True)

if __name__ == "__main__":
    main()
