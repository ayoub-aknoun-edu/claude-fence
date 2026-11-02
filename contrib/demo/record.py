#!/usr/bin/env python3
"""Record the README demo as an asciicast (v2) and render it with `agg`.

Everything runs in a throwaway $HOME with a fake `claude`; your real accounts are never touched.
Usage: python3 contrib/demo/record.py [out_dir]      (then: agg demo.cast demo.gif ...)
"""
import fcntl, json, os, pty, random, select, shutil, struct, subprocess, sys, tempfile, termios, time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
COLS, ROWS = 96, 24

FAKE_CLAUDE = r"""#!/bin/sh
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
json="$cfg/.claude.json"; [ -z "$CLAUDE_CONFIG_DIR" ] && json="$HOME/.claude.json"
who=$(python3 -c "import json,sys;print(json.load(open('$json'))['oauthAccount']['emailAddress'])")
printf '\033[38;5;209m  ✻ Claude Code\033[0m  ·  signed in as \033[1m%s\033[0m\n' "$who"
printf '\033[2m    config: %s\033[0m\n' "$(echo "$cfg" | sed "s|^$HOME|~|")"
"""

def setup(home):
    env = {"HOME": home, "PATH": f"{home}/.local/share/cfence/shims:{REPO}/bin:/usr/bin:/bin",
           "TERM": "xterm-256color", "LANG": "C.UTF-8", "SHELL": "/bin/bash", "CFENCE_PROFILES_DIR": f"{home}/.claude-profiles"}
    for d in (".claude", "work/acme-api", "oss/my-project", "fakebin"):
        os.makedirs(f"{home}/{d}", exist_ok=True)
    fake = f"{home}/fakebin/claude"
    open(fake, "w").write(FAKE_CLAUDE); os.chmod(fake, 0o755)
    def account(path, email, org):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        json.dump({"oauthAccount": {"emailAddress": email, "organizationName": org}, "hasCompletedOnboarding": True}, open(path, "w"))
    account(f"{home}/.claude.json", "you@acme.com", "Acme")
    run = lambda *a: subprocess.run([f"{REPO}/bin/cfence", *a], env=env, check=True, capture_output=True, cwd=home)
    run("init", "--no-rc")
    open(f"{home}/.config/cfence/config", "a").write(f"real_claude={fake}\n")
    run("add", "personal"); account(f"{home}/.claude-profiles/personal/.claude.json", "you@gmail.com", "Personal")
    run("add", "client");   account(f"{home}/.claude-profiles/client/.claude.json", "you@client.io", "Client Inc")
    run("bind", "main", f"{home}/work"); run("bind", "personal", f"{home}/oss")
    env["PS1"] = r"\[\e[1;32m\]\w\[\e[0m\] \$ "
    return env

SCRIPT = [  # (typed text, seconds to wait afterwards)
    ("# 3 Claude accounts, each fenced to its own directories", 0.8),
    ("cfence list", 2.2),
    ("cd ~/work/acme-api", 0.8),
    ("claude", 2.0),
    ("cd ~/oss/my-project", 0.8),
    ("claude", 2.0),
    ("# the wrong account is refused, not silently used:", 1.0),
    ("claude-client", 2.6),
    ("cfence which", 2.2),
]

def main():
    home = tempfile.mkdtemp(prefix="cfence-demo-")
    try:
        env = setup(home)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        p = subprocess.Popen(["bash", "--norc", "--noprofile", "-i"], stdin=slave, stdout=slave, stderr=slave, env=env, cwd=home, close_fds=True)
        os.close(slave)
        events, t0 = [], time.time()
        def pump(duration):
            end = time.time() + duration
            while time.time() < end:
                r, _, _ = select.select([master], [], [], 0.02)
                if r:
                    try: data = os.read(master, 4096)
                    except OSError: return
                    if data: events.append([round(time.time() - t0, 3), "o", data.decode("utf-8", "replace")])
        pump(0.5); events.clear(); t0 = time.time()
        events.append([0.0, "o", "\x1b[2J\x1b[H"]); os.write(master, b"\n"); pump(0.6)
        for text, wait in SCRIPT:
            for ch in text:
                os.write(master, ch.encode()); pump(random.uniform(0.03, 0.07))
            pump(0.25); os.write(master, b"\n"); pump(wait)
        pump(0.3)
        header = {"version": 2, "width": COLS, "height": ROWS, "timestamp": int(t0), "env": {"SHELL": "/bin/bash", "TERM": "xterm-256color"}}
        os.makedirs(OUT, exist_ok=True)
        with open(os.path.join(OUT, "demo.cast"), "w") as f:
            f.write(json.dumps(header) + "\n")
            for e in events:  # hide the throwaway home dir in output (e.g. in refusal messages)
                e[2] = e[2].replace(home, "/home/you")
                f.write(json.dumps(e) + "\n")
        print("wrote", os.path.join(OUT, "demo.cast"))
    finally:
        shutil.rmtree(home, ignore_errors=True)

if __name__ == "__main__":
    main()
