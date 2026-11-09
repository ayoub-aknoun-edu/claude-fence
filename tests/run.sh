#!/usr/bin/env bash
# Self-contained test suite. Runs in a throwaway $HOME with a fake `claude`; never touches real accounts.
set -uo pipefail
with_timeout() { local secs="$1"; shift; "$@" & local pid=$!; ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) & local w=$!; wait "$pid" 2>/dev/null; local rc=$?; kill "$w" 2>/dev/null; wait "$w" 2>/dev/null; return $rc; }
HERE="$(cd "$(dirname "$0")/.." && pwd -P)"
CF="$HERE/bin/cfence"
PASS=0; FAIL=0

T="$(mktemp -d)" || exit 1; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.claude/skills" "$HOME/.claude/agents" "$T/fakebin"
unset CLAUDE_CONFIG_DIR CFENCE_PROFILE CFENCE_PID TMUX TMUX_PANE XDG_CONFIG_HOME XDG_DATA_HOME CFENCE_PROFILES_DIR CFENCE_FORCE CFENCE_NO_TMUX GIT_DIR GIT_WORK_TREE
export SHELL=/bin/bash
echo '{"theme":"dark","hasCompletedOnboarding":true,"mcpServers":{"plane":{"type":"stdio","command":"uvx","env":{"K":"v"}},"other":{"command":"x"}},"oauthAccount":{"emailAddress":"me@work.com","organizationName":"Acme"}}' > "$HOME/.claude.json"
echo "# rules" > "$HOME/.claude/CLAUDE.md"; echo '{}' > "$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude/projects/-x/memory"; echo mem > "$HOME/.claude/projects/-x/memory/a.md"

cat > "$T/fakebin/claude" <<'EOF'
#!/bin/sh
echo "FAKE cfg=${CLAUDE_CONFIG_DIR:-<unset>} prof=${CFENCE_PROFILE:-} args=$*"
EOF
chmod +x "$T/fakebin/claude"
export PATH="$T/fakebin:$PATH"
export CFENCE_QUIET=1

ok()   { PASS=$((PASS+1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; if [[ -n "${2:-}" ]]; then echo "       $2"; fi; return 0; }
eq()   { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "expected [$3] got [$2]"; }
has()  { [[ "$2" == *"$3"* ]] && ok "$1" || bad "$1" "expected to contain [$3] got [$2]"; }
hasnt(){ [[ "$2" != *"$3"* ]] && ok "$1" || bad "$1" "must not contain [$3] got [$2]"; }
code() { local want="$1" name="$2"; shift 2; "$@" >/dev/null 2>&1; local rc=$?; [[ $rc -eq $want ]] && ok "$name" || bad "$name" "exit $rc, wanted $want"; }

$CF init --no-rc >/dev/null
SHIM="$HOME/.local/share/cfence/shims"

echo "[profiles]"
$CF add work2 --share-state >/dev/null; $CF add personal >/dev/null
P="$HOME/.claude-profiles"
[[ -L "$P/personal/skills" ]] && ok "shared dirs are symlinks" || bad "skills symlink"
[[ ! -e "$P/personal/projects" ]] && ok "private profile does NOT share projects/memory" || bad "personal must not share state"
[[ -L "$P/work2/projects" ]] && ok "--share-state links projects (memory)" || bad "work2 projects link"
eq "work2 sees main's memory" "$(cat "$P/work2/projects/-x/memory/a.md")" "mem"
eq "profile dir is mode 700" "$(stat -c %a "$P/personal" 2>/dev/null || stat -f %Lp "$P/personal")" "700"
eq "onboarding flag seeded" "$(python3 -c "import json;print(json.load(open('$P/personal/.claude.json'))['hasCompletedOnboarding'])")" "True"
hasnt "account NOT copied into new profile" "$(cat "$P/personal/.claude.json")" "me@work.com"
for bad_name in "Bad" "../x" "-x" "a b" "main" ""; do code 1 "rejects name '$bad_name'" $CF add "$bad_name"; done
code 1 "duplicate profile rejected" $CF add personal
[[ -x "$SHIM/claude-personal" ]] && ok "per-profile shim exists" || bad "shim claude-personal"

echo "[binding + guard]"
mkdir -p "$T/w/proj/sub" "$T/w/proj-x" "$T/w/with space/deep" "$T/w/nested/inner"
$CF bind personal "$T/w/proj" >/dev/null
$CF bind work2 "$T/w/with space" >/dev/null
$CF bind work2 "$T/w/nested" >/dev/null; $CF bind personal "$T/w/nested/inner" >/dev/null
eq "subdir inherits binding" "$(cd "$T/w/proj/sub" && $CF which -q)" "personal"
eq "sibling with same prefix is NOT bound (proj-x)" "$(cd "$T/w/proj-x" && $CF which -q)" "main"
eq "path with spaces" "$(cd "$T/w/with space/deep" && $CF which -q)" "work2"
eq "longest prefix wins" "$(cd "$T/w/nested/inner" && $CF which -q)" "personal"
eq "outer binding for outer dir" "$(cd "$T/w/nested" && $CF which -q)" "work2"
ln -s "$T/w/proj" "$T/link"; eq "symlinked cwd resolves physically" "$(cd "$T/link/sub" && $CF which -q)" "personal"
out="$(cd "$T/w/proj/sub" && $CF run -- hi)"; has "bound run uses CLAUDE_CONFIG_DIR" "$out" "cfg=$P/personal"
out="$(cd "$T/w/proj-x" && CLAUDE_CONFIG_DIR=/leaked $CF run -- hi)"; has "main run IGNORES leaked CLAUDE_CONFIG_DIR" "$out" "cfg=<unset>"
code 3 "wrong profile in fenced dir is refused" bash -c "cd '$T/w/proj' && $CF run -p work2 -- hi"
code 0 "--force overrides the fence (exit code)" bash -c "cd '$T/w/proj' && $CF run --force -p work2 -- hi"
code 3 "shim claude-work2 refused in personal dir" bash -c "cd '$T/w/proj' && PATH='$SHIM:$PATH' claude-work2 hi"
out="$(cd "$T/w/proj" && PATH="$SHIM:$PATH" claude-work2 --force hi 2>/dev/null)"; has "shim: claude-work2 --force overrides the fence" "$out" "cfg=$P/work2"; hasnt "shim: --force is consumed, not passed to claude" "$out" "args=--force"
out="$(cd "$T/w/proj-x" && PATH="$SHIM:$PATH" claude-work2 hi)"; has "shim override works in unbound dir" "$out" "cfg=$P/work2"
out="$(cd "$T/w/proj" && PATH="$SHIM:$PATH" claude hi there)"; has "plain claude shim passes args + picks binding" "$out" "args=hi there"

echo "[worst cases]"
mv "$P/work2" "$P/work2.gone"
code 3 "binding to a missing profile fails CLOSED (no fallback to main)" bash -c "cd '$T/w/with space' && $CF run -- hi"
mv "$P/work2.gone" "$P/work2"
echo "personal /nonexistent" >> "$HOME/.config/cfence/bindings"; code 0 "stale binding path does not break other dirs" bash -c "cd '$T/w/proj' && $CF run -- x"
code 1 "bind to nonexistent dir rejected" $CF bind personal "$T/nope"
code 1 "bind to nonexistent profile rejected" $CF bind ghost "$T/w"

echo "[inheritance / subagents]"
# nested claude from inside a claude process: parent pid must be a real ancestor
out="$(cd "$T/w/proj-x" && CFENCE_PROFILE=work2 CFENCE_PID=$$ bash -c "$CF run -- nested")"; has "legit nested call inherits parent profile" "$out" "prof=work2"
out="$(cd "$T/w/proj-x" && CFENCE_PROFILE=work2 CFENCE_PID=999999 $CF run -- nested)"; has "forged/stale CFENCE_PID is ignored" "$out" "prof=main"
code 3 "inherited profile cannot escape a fence" bash -c "cd '$T/w/proj' && CFENCE_PROFILE=work2 CFENCE_PID=$$ bash -c \"$CF run -- n\""

echo "[git worktrees (cw)]"
if command -v git >/dev/null; then
  R="$T/w/repo"; mkdir -p "$R"; ( cd "$R" && git init -q && git -c user.email=a@b -c user.name=t commit -q --allow-empty -m i && git worktree add -q -b feat "$T/w/repo-feat" ) >/dev/null 2>&1
  $CF bind personal "$R" >/dev/null
  eq "sibling worktree inherits the repo's binding" "$(cd "$T/w/repo-feat" && $CF which -q)" "personal"
else echo "  skip (no git)"; fi

echo "[concurrent writer]"
# a running Claude rewrites ~/.claude.json while cfence is mid-sync: its change must survive, and ours must still land
$CF add racer >/dev/null; $CF mcp share plane >/dev/null; $CF mcp sync >/dev/null
RJ="$P/racer/.claude.json"; python3 - "$RJ" <<'PYX'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.pop("mcpServers",None); json.dump(d,open(p,"w"))
PYX
rm -f "$P/racer/.cfence-mcp-stamp"
( CFENCE_TEST_PAUSE=1 $CF mcp sync >/dev/null 2>&1 ) & RPID=$!
sleep 0.4; python3 - "$RJ" <<'PYX'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["lateKey"]="kept"; json.dump(d,open(p,"w"))
PYX
wait $RPID
eq "concurrent write by another process is not lost" "$(python3 -c "import json;print(json.load(open('$RJ')).get('lateKey'))")" "kept"
eq "...and the sync still applied on top of it" "$(python3 -c "import json;print('plane' in json.load(open('$RJ')).get('mcpServers',{}))")" "True"
$CF remove racer --yes >/dev/null

echo "[git layouts]"
if command -v git >/dev/null; then
  G="git -c user.email=a@b -c user.name=t -c protocol.file.allow=always"
  # bare repo: worktrees live elsewhere and follow the bare dir's binding
  $G init -q --bare "$T/gl/bare.git" >/dev/null 2>&1 && ( cd "$T/gl/bare.git" && $G worktree add -q --orphan -b m "$T/gl/bare-wt" ) >/dev/null 2>&1
  if [[ -d "$T/gl/bare-wt" ]]; then
    eq "bare repo: its worktree is unbound before binding" "$(cd "$T/gl/bare-wt" && $CF which -q)" "main"
    $CF bind personal "$T/gl/bare.git" >/dev/null
    eq "bare repo: a worktree follows the bare dir's binding" "$(cd "$T/gl/bare-wt" && $CF which -q)" "personal"
    eq "bare repo: the bare dir itself is fenced" "$(cd "$T/gl/bare.git" && $CF which -q)" "personal"
    $CF unbind "$T/gl/bare.git" >/dev/null
  else ok "(skipped: this git cannot create an orphan worktree)"; fi
  # --separate-git-dir: working tree binding covers it; linked worktrees need the git dir bound too
  mkdir -p "$T/gl/sg" "$T/gl/store"
  ( cd "$T/gl/sg" && $G init -q --separate-git-dir="$T/gl/store/sg.git" . && $G commit -q --allow-empty -m i && $G worktree add -q -b f "$T/gl/sg-feat" ) >/dev/null 2>&1
  $CF bind personal "$T/gl/sg" >/dev/null
  eq "separate-git-dir: the working tree is fenced" "$(cd "$T/gl/sg" && $CF which -q)" "personal"
  $CF bind personal "$T/gl/store/sg.git" >/dev/null
  eq "separate-git-dir: a linked worktree follows the bound git dir" "$(cd "$T/gl/sg-feat" && $CF which -q)" "personal"
  $CF unbind "$T/gl/sg" >/dev/null; $CF unbind "$T/gl/store/sg.git" >/dev/null
  # submodule: lives inside the superproject, so the superproject's binding applies
  mkdir -p "$T/gl/sup"
  ( cd "$T/gl/sup" && $G init -q && $G commit -q --allow-empty -m i && $G submodule add -q "$T/gl/sg" sub && $G commit -qm s ) >/dev/null 2>&1
  $CF bind personal "$T/gl/sup" >/dev/null
  eq "submodule: inherits the superproject's binding" "$(cd "$T/gl/sup/sub" && $CF which -q)" "personal"
  $CF unbind "$T/gl/sup" >/dev/null
else echo "  skip (no git)"; fi

echo "[mcp registry]"
$CF mcp share plane >/dev/null
eq "registry has the server" "$($CF mcp list | cut -f1)" "plane"
(cd "$T/w/proj" && $CF run -- x >/dev/null)
eq "server appears in a profile on next launch" "$(python3 -c "import json;print(sorted(json.load(open('$P/personal/.claude.json'))['mcpServers']))")" "['plane']"
eq "main keeps its other servers" "$(python3 -c "import json;print(sorted(json.load(open('$HOME/.claude.json'))['mcpServers']))")" "['other', 'plane']"
eq "registry is chmod 600" "$(stat -c %a "$HOME/.config/cfence/mcp.json" 2>/dev/null || stat -f %Lp "$HOME/.config/cfence/mcp.json")" "600"
code 1 "sharing a non-existent server fails" $CF mcp share nothere
echo '{ broken' > "$P/work2/.claude.json"
code 1 "corrupt .claude.json is refused, not clobbered" $CF mcp sync
eq "corrupt file left untouched" "$(cat "$P/work2/.claude.json")" "{ broken"
echo '{}' > "$P/work2/.claude.json"
$CF mcp unshare plane >/dev/null
eq "unshare drops it from non-main profiles" "$(python3 -c "import json;print(json.load(open('$P/personal/.claude.json')).get('mcpServers',{}))")" "{}"

echo "[remove / doctor / shim safety]"
$CF remove personal >/dev/null 2>&1 && bad "remove requires --yes" || ok "remove requires --yes"
$CF remove work2 --yes >/dev/null
[[ -e "$HOME/.claude/projects/-x/memory/a.md" ]] && ok "removing a share-state profile leaves main's memory intact" || bad "main memory destroyed!"
code 1 "cannot remove main" $CF remove main --yes
out="$(PATH="$SHIM:$PATH" $CF doctor 2>&1)"; has "doctor sees the shim first on PATH" "$out" "resolves to the cfence shim"
out="$($CF doctor 2>&1)"; has "doctor flags PATH without shim" "$out" "not the shim"
out="$(PATH="$SHIM:/usr/bin:/bin" $CF run -- x 2>&1)"; has "no real claude => clear error, no infinite loop" "$out" "cannot find the real"
echo "[tmux indicator]"
if command -v tmux >/dev/null; then
  S="cfence-test-$$"; tmux -L "$S" -f /dev/null new-session -d -s t -x 80 -y 24 2>/dev/null
  PANE="$(tmux -L "$S" list-panes -t t -F '#{pane_id}')"; SOCK="$(tmux -L "$S" display -p '#{socket_path}')"
  mkdir -p "$T/tbin"; printf '#!/bin/sh\nexec %s -L %s "$@"\n' "$(command -v tmux)" "$S" > "$T/tbin/tmux"; chmod +x "$T/tbin/tmux"
  mkdir -p "$T/tbin/real"; printf '#!/bin/sh\ntmux display -p -t %s "#{@cfence}" > "%s/tmuxseen"\nexit 7\n' "$PANE" "$T" > "$T/fakebin/claude"
  ( cd "$T/w/proj" && TMUX="$SOCK,1,0" TMUX_PANE="$PANE" PATH="$T/tbin:$T/fakebin:$PATH" "$CF" run -- x ) >/dev/null 2>&1; rc=$?
  eq "pane label is set before claude starts" "$(cat "$T/tmuxseen" 2>/dev/null)" "personal"
  eq "claude's exit code passes through" "$rc" "7"
  # the wrapper must not stay in the process tree (else tmux names the window after bash)
  printf '#!/bin/sh\nps -o ppid= -p $$ > "%s/ppid"\nps -o comm= -p "$(cat "%s/ppid")" > "%s/parentcomm"\n' "$T" "$T" "$T" > "$T/fakebin/claude"
  ( cd "$T/w/proj" && TMUX="$SOCK,1,0" TMUX_PANE="$PANE" PATH="$T/tbin:$T/fakebin:$PATH" bash -c "$CF run -- x" ) >/dev/null 2>&1
  [[ "$(cat "$T/parentcomm" 2>/dev/null)" != *cfence* ]] && ok "cfence execs (not a lingering wrapper process)" || bad "wrapper still in process tree" "$(cat "$T/parentcomm")"
  tmux -L "$S" kill-server 2>/dev/null
else echo "  skip (no tmux)"; fi

echo "[security regressions]"
mkdir -p "$T/s/fenced/proj" "$T/s/fenced2 " "$T/s/inj" "$T/s/evil"
$CF bind personal "$T/s/fenced" >/dev/null
# H1: env cannot force or impersonate out of a fence
out="$(cd "$T/s/fenced/proj" && CFENCE_FORCE=1 CFENCE_PROFILE=work2 CFENCE_PID=$PPID $CF run -- x 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" != *"cfg=$P/work2"* ]] && ok "H1 env CFENCE_FORCE/PROFILE/PID cannot escape a fence" || bad "H1 bypass" "$out"
# H2: credential env vars stripped inside a fence, kept elsewhere
cat > "$T/fakebin/claude" <<'FAKE'
#!/bin/sh
echo "FAKE cfg=${CLAUDE_CONFIG_DIR:-<unset>} key=${ANTHROPIC_API_KEY:-none} tok=${CLAUDE_CODE_OAUTH_TOKEN:-none}"
FAKE
out="$(cd "$T/s/fenced/proj" && ANTHROPIC_API_KEY=k CLAUDE_CODE_OAUTH_TOKEN=t $CF run -- x 2>/dev/null)"
has "H2 API key stripped in fence" "$out" "key=none"; has "H2 oauth token stripped in fence" "$out" "tok=none"
out="$(cd "$T/w/proj-x" && ANTHROPIC_API_KEY=k $CF run -- x 2>/dev/null)"; has "H2 unfenced dir keeps API key (API-key users unaffected)" "$out" "key=k"
# M1: trailing-space dir name
$CF bind personal "$T/s/fenced2 " >/dev/null
eq "M1 dir name with trailing space is fenced" "$(cd "$T/s/fenced2 " && $CF which -q)" "personal"
# M2: newline in dir name rejected (no bindings injection)
NL="$T/s/inj/x"$'\n'"personal $T/s/evil"; mkdir -p "$NL"
code 1 "M2 newline in path rejected" $CF bind work2 "$NL"
eq "M2 no injected binding" "$(cd "$T/s/evil" && $CF which -q)" "main"
# M3: stray .git file must not borrow another repo's fence
if command -v git >/dev/null; then
  mkdir -p "$T/s/atk"; echo "gitdir: $R/.git" > "$T/s/atk/.git"
  eq "M3 forged .git file does not inherit a fence" "$(cd "$T/s/atk" && $CF which -q 2>/dev/null)" "main"
  eq "M3 real registered worktree still works" "$(cd "$T/w/repo-feat" && $CF which -q)" "personal"
fi
# M4: bad profile names never reach the filesystem
code 2 "M4 -p ../../.. rejected" $CF run -p ../../.. -- x
code 1 "M4 env with traversal rejected" $CF env ../../x
# M5: uninstall never truncates an rc file lacking the END marker
printf 'a\nb\n# >>> cfence >>>\nexport PATH=x\nc\nd\n' > "$HOME/.zshrc"; $CF uninstall >/dev/null 2>&1
eq "M5 rc without END marker left intact" "$(wc -l < "$HOME/.zshrc" | tr -d ' ')" "6"
# L3: backslash in dir name can be unbound
BS="$T/s/bs\\tx"; mkdir -p "$BS"; $CF bind personal "$BS" >/dev/null; $CF unbind "$BS" >/dev/null
eq "L3 unbind handles backslashes" "$(grep -c -F 'bs\tx' "$HOME/.config/cfence/bindings" || true)" "0"
# L5: env respects the fence
code 3 "L5 cfence env refuses cross-account inside a fence" bash -c "cd '$T/s/fenced/proj' && $CF env main"

echo "[review regressions]"
# shim recursion: a cfence shim reachable via another PATH dir must not loop forever
$CF init --no-rc >/dev/null; mkdir -p "$T/o"; ln -sf "$SHIM/claude" "$T/o/claude"
out="$(cd "$T/w/proj-x" && PATH="$T/o:/usr/bin:/bin" with_timeout 5 "$CF" run -- x 2>&1)"; rc=$?
[[ $rc -ne 137 && "$out" == *"shim"* ]] && ok "shim reached via other dir => error, no infinite loop" || bad "recursion guard" "rc=$rc $out"
# config/bindings last line without trailing newline
printf 'personal %s' "$T/w/proj-x" >> "$HOME/.config/cfence/bindings"
eq "binding on last line without newline is honoured" "$(cd "$T/w/proj-x" && $CF which -q)" "personal"
$CF unbind "$T/w/proj-x" >/dev/null
# unbind of a directory that no longer exists
mkdir -p "$T/w/gone"; $CF bind personal "$T/w/gone" >/dev/null; rm -rf "$T/w/gone"
$CF unbind "$T/w/gone" >/dev/null 2>&1; eq "unbind works for deleted dir" "$(grep -c -F "$T/w/gone" "$HOME/.config/cfence/bindings" || true)" "0"
# unbind of a deleted dir reached through a symlinked parent (macOS: /var -> /private/var)
mkdir -p "$T/realp/d"; ln -sfn "$T/realp" "$T/linkp"; $CF bind personal "$T/linkp/d" >/dev/null; rm -rf "$T/realp/d"
$CF unbind "$T/linkp/d" >/dev/null 2>&1; eq "unbind deleted dir under a symlinked parent" "$(grep -c -F "realp/d" "$HOME/.config/cfence/bindings" || true)" "0"
# sync failure must never block launch
$CF mcp share plane >/dev/null; echo '{ broken' > "$P/personal/.claude.json"; rm -f "$P/personal/.cfence-mcp-stamp"
out="$(cd "$T/w/proj" && $CF run -- hi 2>&1)"; has "corrupt profile json does not block launch" "$out" "FAKE"
echo '{}' > "$P/personal/.claude.json"
# --force really switches account
$CF add alt >/dev/null; out="$(cd "$T/w/proj" && $CF run --force -p alt -- hi 2>/dev/null)"; has "--force really launches the other profile" "$out" "cfg=$P/alt"; $CF remove alt --yes >/dev/null
# mcp unshare must not delete a profile's own different server of the same name
$CF add dev >/dev/null; python3 - "$P/dev/.claude.json" <<'PYX'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["mcpServers"]={"plane":{"command":"MINE"}}; json.dump(d,open(p,"w"))
PYX
$CF mcp unshare plane >/dev/null
eq "unshare keeps a profile's own same-named server" "$(python3 -c "import json;print(json.load(open('$P/dev/.claude.json'))['mcpServers']['plane']['command'])")" "MINE"
$CF remove dev --yes >/dev/null
# add rolls back when main json is unreadable
cp "$HOME/.claude.json" "$T/main.bak"; echo '{ nope' > "$HOME/.claude.json"
code 1 "add fails cleanly when ~/.claude.json is corrupt" $CF add half
[[ ! -e "$P/half" ]] && ok "no half-created profile left behind" || bad "half profile remained"
cp "$T/main.bak" "$HOME/.claude.json"
# non-tty init without --yes must not edit rc files
: > "$HOME/.bashrc"; SHELL=/bin/bash $CF init --no-rc >/dev/null; SHELL=/bin/bash $CF init </dev/null >/dev/null 2>&1
eq "init without --yes and without a tty leaves rc untouched" "$(wc -c < "$HOME/.bashrc" | tr -d ' ')" "0"
SHELL=/bin/bash $CF init --yes >/dev/null 2>&1; has "init --yes writes PATH block" "$(cat "$HOME/.bashrc" "$HOME/.bash_profile" 2>/dev/null)" "$SHIM"
printf '#!/bin/sh\nexit 7\n' > "$T/fakebin/claude"
if command -v tmux >/dev/null; then
  S2="cfence-t2-$$"; tmux -L "$S2" -f /dev/null new-session -d -s t 2>/dev/null
  PANE2="$(tmux -L "$S2" list-panes -t t -F '#{pane_id}')"; SOCK2="$(tmux -L "$S2" display -p '#{socket_path}')"
  mkdir -p "$T/tbin2"; printf '#!/bin/sh\nexec %s -L %s "$@"\n' "$(command -v tmux)" "$S2" > "$T/tbin2/tmux"; chmod +x "$T/tbin2/tmux"
  ( cd "$T/w/proj" && TMUX="$SOCK2,1,0" TMUX_PANE="$PANE2" PATH="$T/tbin2:$T/fakebin:$PATH" "$CF" run -- x ) >/dev/null 2>&1; rc=$?
  eq "tmux wrapper passes through claude's exit code" "$rc" "7"
  tmux -L "$S2" kill-server 2>/dev/null
fi

echo "[completion]"
for sh in bash zsh fish; do out="$($CF completion $sh)"; has "completion $sh emits a script" "$out" "cfence"; done
code 1 "completion with unknown shell fails" $CF completion tcsh
eq "_profiles lists profile names" "$($CF _profiles | tr '\n' ' ')" "$($CF list | awk 'NR>1{print $1}' | tr '\n' ' ')"
BINDIR="$(dirname "$CF")"
r="$(PATH="$BINDIR:$PATH" bash -c 'eval "$(cfence completion bash)"; COMP_WORDS=(cfence login ""); COMP_CWORD=2; _cfence; echo "${COMPREPLY[*]}"')"
has "bash completion offers profiles for login" "$r" "main"
r="$(PATH="$BINDIR:$PATH" bash -c 'eval "$(cfence completion bash)"; COMP_WORDS=(cfence ""); COMP_CWORD=1; _cfence; echo "${COMPREPLY[*]}"')"
has "bash completion offers subcommands" "$r" "doctor"

echo "[rename]"
mkdir -p "$T/r/dir with space" "$T/r/plain"
$CF add oldname >/dev/null; $CF bind oldname "$T/r/dir with space" >/dev/null; $CF bind oldname "$T/r/plain" >/dev/null
$CF bind personal "$T/r/other" >/dev/null 2>&1 || { mkdir -p "$T/r/other"; $CF bind personal "$T/r/other" >/dev/null; }
echo '{"x":1}' > "$P/oldname/marker.json"
printf '#!/bin/sh\necho "FAKE cfg=$CLAUDE_CONFIG_DIR"\n' > "$T/fakebin/claude"
$CF rename oldname newname >/dev/null; rc=$?
eq "rename succeeds" "$rc" "0"
[[ -f "$P/newname/marker.json" && ! -e "$P/oldname" ]] && ok "rename moves the profile directory" || bad "dir not moved"
[[ -x "$SHIM/claude-newname" && ! -e "$SHIM/claude-oldname" ]] && ok "rename swaps the shim" || bad "shim not swapped"
eq "binding with spaces follows the rename" "$(cd "$T/r/dir with space" && $CF which -q)" "newname"
eq "plain binding follows the rename" "$(cd "$T/r/plain" && $CF which -q)" "newname"
eq "unrelated binding untouched" "$(cd "$T/r/other" && $CF which -q)" "personal"
has "renamed profile launches with its new dir" "$(cd "$T/r/plain" && $CF run -- hi 2>/dev/null)" "cfg=$P/newname"
code 1 "rename main refused" $CF rename main foo
code 1 "rename to main refused" $CF rename newname main
code 1 "rename onto existing profile refused" $CF rename newname personal
code 1 "rename unknown profile refused" $CF rename ghost2 foo
code 1 "rename to invalid name refused" $CF rename newname "Bad Name"
code 1 "rename needs two args" $CF rename newname
$CF remove newname --yes >/dev/null

echo "[statusline]"
eq "statusline: unset config dir outside any session shows the cwd binding" "$(cd "$T/s/fenced/proj" && env -u CLAUDE_CONFIG_DIR -u CFENCE_PROFILE $CF statusline --plain </dev/null)" "[personal]"
eq "statusline: cfence-launched main session is main" "$(cd "$T/s/fenced/proj" && env -u CLAUDE_CONFIG_DIR CFENCE_PROFILE=main $CF statusline --plain </dev/null)" "[main]"
eq "statusline: unbound dir outside a session is main" "$(cd "$T/s/evil" && env -u CLAUDE_CONFIG_DIR -u CFENCE_PROFILE $CF statusline --plain </dev/null)" "[main]"
eq "statusline: profile dir maps to its name" "$(CLAUDE_CONFIG_DIR="$P/work2" $CF statusline --plain </dev/null)" "[work2]"
eq "statusline: trailing slash tolerated" "$(CLAUDE_CONFIG_DIR="$P/work2/" $CF statusline --plain </dev/null)" "[work2]"
eq "statusline: unknown config dir shows ?" "$(CLAUDE_CONFIG_DIR=/elsewhere $CF statusline --plain </dev/null)" "[?]"
has "statusline: colour output uses a truecolor escape" "$(echo '{}' | CLAUDE_CONFIG_DIR="$P/work2" $CF statusline)" $'\033[38;2;'
eq "statusline: NO_COLOR gives plain text" "$(NO_COLOR=1 CLAUDE_CONFIG_DIR="$P/work2" $CF statusline </dev/null)" "[work2]"
code 0 "statusline never fails (even with a broken HOME config)" env CFENCE_PROFILES_DIR=/nonexistent $CF statusline

echo "[launch]"
$CF add lprof >/dev/null
printf '#!/bin/sh\necho "APP cfg=${CLAUDE_CONFIG_DIR:-<unset>} prof=$CFENCE_PROFILE key=${ANTHROPIC_API_KEY:-none} args=$*"\n' > "$T/fakebin/fakeapp"; chmod +x "$T/fakebin/fakeapp"
out="$(cd "$T/s/fenced/proj" && PATH="$T/fakebin:$PATH" ANTHROPIC_API_KEY=k $CF launch -- fakeapp a b 2>/dev/null)"
has "launch runs the command under the bound profile" "$out" "cfg=$P/personal"; has "launch sets CFENCE_PROFILE" "$out" "prof=personal"
has "launch strips credential vars in a fence" "$out" "key=none"; has "launch passes arguments through" "$out" "args=a b"
out="$(cd "$T/w/proj-x" && PATH="$T/fakebin:$PATH" $CF launch -- fakeapp 2>/dev/null)"; has "launch in an unbound dir uses main" "$out" "prof=main"
out="$(cd "$T/w/proj-x" && PATH="$T/fakebin:$PATH" $CF launch -p lprof -- fakeapp 2>/dev/null)"; has "launch -p picks a profile" "$out" "cfg=$P/lprof"
code 3 "launch refuses a profile that contradicts the fence" bash -c "cd '$T/s/fenced/proj' && PATH='$T/fakebin:$PATH' $CF launch -p lprof -- fakeapp"
out="$(cd "$T/s/fenced/proj" && PATH="$T/fakebin:$PATH" $CF launch --force -p lprof -- fakeapp 2>/dev/null)"; has "launch --force overrides" "$out" "cfg=$P/lprof"
code 127 "launch of a missing command fails" $CF launch -- definitely-not-a-command-xyz
code 2 "launch without a command is a usage error" $CF launch
printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/cursor"; chmod +x "$T/fakebin/cursor"
out="$(cd "$T/w/proj-x" && PATH="$T/fakebin:$PATH" $CF launch -- cursor 0 2>&1)"
hasnt "no 'already running' warning when the IDE is not running" "$out" "already running"
mkdir -p "$T/ide"; printf '#!/bin/sh\nsleep 20\n' > "$T/ide/zed"; printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/zed"; chmod +x "$T/ide/zed" "$T/fakebin/zed"
"$T/ide/zed" & IDEPID=$!; sleep 0.5
if pgrep -x zed >/dev/null 2>&1; then
  out="$(cd "$T/w/proj-x" && PATH="$T/fakebin:$PATH" $CF launch -- zed 2>&1)"; has "warns when the IDE is already running" "$out" "already running"
else ok "(skipped: this OS cannot see the fake editor by name)"; fi
kill "$IDEPID" 2>/dev/null; wait "$IDEPID" 2>/dev/null

$CF remove lprof --yes >/dev/null

echo "[wsl]"
printf 'Linux version 5.15.153.1-microsoft-standard-WSL2 (root@x)\n' > "$T/procv"; printf 'Linux version 6.1.0-generic (builder)\n' > "$T/procv-plain"
cp "$HOME/.config/cfence/bindings" "$T/bindings.bak"; echo "personal /mnt/c/Users/x/proj" >> "$HOME/.config/cfence/bindings"
out="$(CFENCE_PROC_VERSION="$T/procv" $CF doctor 2>&1)"
has "doctor detects WSL" "$out" "WSL detected"; has "doctor warns about a fence on a Windows drive" "$out" "Windows drive"
out="$(CFENCE_PROC_VERSION="$T/procv-plain" $CF doctor 2>&1)"
hasnt "no WSL output on plain Linux" "$out" "WSL detected"; hasnt "no Windows-drive warning on plain Linux" "$out" "Windows drive"
out="$(CFENCE_PROC_VERSION="$T/procv" CFENCE_PROFILES_DIR=/mnt/d/profiles $CF doctor 2>&1)"; has "doctor warns when profiles live on a Windows drive" "$out" "is on a Windows drive"
cp "$T/bindings.bak" "$HOME/.config/cfence/bindings"

echo "[same folder, different spelling]"
mkdir -p "$T/c/real/sub/deep" "$T/c/other"; ln -sfn "$T/c/real" "$T/c/alias"
cp "$HOME/.config/cfence/bindings" "$T/bindings.bak2"
echo "personal $T/c/alias" >> "$HOME/.config/cfence/bindings"      # hand-edited, non-canonical spelling
eq "binding written with another spelling still fences the folder" "$(cd "$T/c/real/sub/deep" && $CF which -q)" "personal"
$CF bind main "$T/c/real/sub" >/dev/null
eq "a deeper binding still beats the alias-spelled parent" "$(cd "$T/c/real/sub/deep" && $CF which -q)" "main"
eq "the parent (alias-spelled binding) still applies above it" "$(cd "$T/c/real" && $CF which -q)" "personal"
$CF unbind "$T/c/real/sub" >/dev/null
$CF bind work_x "$T/c/real" >/dev/null 2>&1 || true
$CF add dupe >/dev/null; $CF bind dupe "$T/c/real" >/dev/null
eq "re-binding replaces the entry made under another spelling (no duplicates)" "$(grep -c -F "$T/c/" "$HOME/.config/cfence/bindings")" "1"
eq "...and the new profile wins" "$(cd "$T/c/real/sub" && $CF which -q)" "dupe"
echo "personal $T/c/alias" >> "$HOME/.config/cfence/bindings"
$CF unbind "$T/c/real" >/dev/null
eq "unbind removes every spelling of the folder" "$(grep -c -F "$T/c/" "$HOME/.config/cfence/bindings" || true)" "0"
$CF remove dupe --yes >/dev/null
# a case-insensitive filesystem (default APFS): the same folder typed in another case must stay fenced
mkdir -p "$T/ci/Proj"; ALT="$T/ci/pROJ"
if [[ -d "$ALT" ]]; then
  $CF bind personal "$T/ci/Proj" >/dev/null
  eq "case-insensitive fs: other-case spelling of a fenced folder is still fenced" "$(cd "$ALT" && $CF which -q)" "personal"
else ok "(skipped: this filesystem is case-sensitive; the symlink tests above cover the same mechanism)"; fi
cp "$T/bindings.bak2" "$HOME/.config/cfence/bindings"

echo "[fish]"
if command -v fish >/dev/null 2>&1; then
  FPATH_BASE="$PATH"; FISHCFG="$HOME/.config/fish/config.fish"; rm -f "$FISHCFG"
  $CF init --no-rc >/dev/null
  SHELL="$(command -v fish)" $CF init --yes >/dev/null 2>&1
  has "init writes a PATH block to config.fish for fish users" "$(cat "$FISHCFG" 2>/dev/null)" "set -gx PATH"
  hasnt "the fish block does not use universal-scope fish_add_path" "$(cat "$FISHCFG")" "fish_add_path"
  eq "fish: shim dir is first in PATH" "$(fish -c 'echo $PATH[1]' 2>/dev/null)" "$SHIM"
  eq "fish: claude resolves to the shim" "$(fish -c 'type -p claude' 2>/dev/null)" "$SHIM/claude"
  eq "fish: sourcing the config twice does not duplicate the entry" "$(fish -c "source $FISHCFG; source $FISHCFG; count (string match -- '$SHIM' \$PATH)" 2>/dev/null)" "1"
  eq "fish: shim dir moves to the front when already present later in PATH" "$(PATH="$FPATH_BASE:$SHIM" fish -c 'echo $PATH[1]' 2>/dev/null)" "$SHIM"
  [[ ! -f "$HOME/.local/share/fish/fish_variables" ]] || ! grep -q cfence "$HOME/.local/share/fish/fish_variables" && ok "fish: nothing cfence-related persists in fish_variables" || bad "fish_variables polluted"
  out="$(cd "$T/w/proj" && fish -c 'claude x' 2>/dev/null)"; has "fish: running claude goes through cfence" "$out" "FAKE"
  # profile dir containing a space and a quote must survive `cfence env --fish`
  SP="$T/we ird'd\\ir"; mkdir -p "$SP"; CFENCE_PROFILES_DIR="$SP" $CF add quoted >/dev/null 2>&1
  eq "fish: cfence env --fish quotes awkward paths" "$(CFENCE_PROFILES_DIR="$SP" $CF env quoted --fish | fish -c 'source; echo $CLAUDE_CONFIG_DIR' 2>/dev/null)" "$SP/quoted"
  CFENCE_PROFILES_DIR="$SP" $CF remove quoted --yes >/dev/null 2>&1; rm -rf "$SP"
  eq "fish: cfence env main unsets the variable" "$(CLAUDE_CONFIG_DIR=/x $CF env main --fish | fish -c 'set -gx CLAUDE_CONFIG_DIR /x; source; echo "[$CLAUDE_CONFIG_DIR]"' 2>/dev/null)" "[]"
  has "fish completions offer profile names" "$(PATH="$HERE/bin:$PATH" fish -c "$($CF completion fish)"$'\n''complete -C "cfence login "' 2>/dev/null | tr '\n' ' ')" "main"
  has "fish completions offer subcommands" "$(PATH="$HERE/bin:$PATH" fish -c "$($CF completion fish)"$'\n''complete -C "cfence lau"' 2>/dev/null)" "launch"
  # a stale universal entry left by older cfence versions is removed by uninstall
  fish -c "fish_add_path -m $SHIM" >/dev/null 2>&1
  has "(setup) legacy universal entry present" "$(fish -c 'set -S fish_user_paths' 2>/dev/null)" "universal"
  $CF uninstall >/dev/null 2>&1
  hasnt "uninstall removes the legacy universal fish_user_paths entry" "$(fish -c 'echo $fish_user_paths' 2>/dev/null)" "$SHIM"
  hasnt "uninstall removes the fish config block" "$(cat "$FISHCFG")" "cfence"
  rm -f "$FISHCFG"; $CF init --no-rc >/dev/null
else ok "(skipped: fish is not installed)"; fi

echo
echo "passed: $PASS   failed: $FAIL"
[[ $FAIL -eq 0 ]]
