#!/usr/bin/env bash
# Covers: TST-PLN-0019 TST-PLN-0020
# The launcher, driven without kitty (UP_KITTEN_BIN=false) against the
# minimal test config: unsafe and missing paths are refused; start returns a
# handle and status reports running; cancel from inside Neovim makes wait
# exit 2 and tears the session down; a submitted review makes wait print
# the JSON and exit 0; the cancel subcommand removes the state files.
# Skipped (exit 0) when zmx is not installed.
set -uo pipefail

PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ZMX="${UP_ZMX_BIN:-/opt/homebrew/bin/zmx}"
if [ ! -x "$ZMX" ]; then
  echo "SKIP: zmx not found at $ZMX"
  exit 0
fi

export UP_ZMX_BIN="$ZMX"
export UP_KITTEN_BIN=/usr/bin/false
export UP_WORKDIR
UP_WORKDIR=$(mktemp -d -t up-launch.XXXXXX)
# Silence the test-config banner: with no terminal attached yet, Neovim's
# startup messages would otherwise stack into a hit-enter prompt.
export UP_NVIM_BIN="nvim -u $PLUGIN_ROOT/tests/minimal_init.lua --cmd 'let g:ultraplan_silent=1'"
L="$PLUGIN_ROOT/scripts/ultraplan-launch"
PLAN="$PLUGIN_ROOT/tests/e2e/fixture_plan.md"

cleanup() {
  for st in "$UP_WORKDIR"/review.*.state; do
    [ -e "$st" ] && "$L" cancel "${st%.state}" >/dev/null 2>&1
  done
  rm -rf "$UP_WORKDIR"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*"
  exit 1
}

send() { printf '%s' "$2" | "$ZMX" send "$1"; sleep 0.4; }
esc() { printf '\x1b' | "$ZMX" send "$1"; sleep 0.3; }
session_of() { sed -n 's/^session=//p' "$1.state"; }
ready() {
  local i
  for i in $(seq 1 60); do
    "$ZMX" history "$1" 2>/dev/null | grep -q "whole plan" && return 0
    sleep 0.5
  done
  echo "--- session history:"; "$ZMX" history "$1" | tail -5
  fail "review did not open in session $1"
}

# Validation.
"$L" start "$PLAN'x" >/dev/null 2>&1 && fail "unsafe path accepted"
"$L" start /nonexistent/plan.md >/dev/null 2>&1 && fail "missing plan accepted"
"$L" >/dev/null 2>&1 && fail "no subcommand accepted"

# Cancel path.
H=$("$L" start "$PLAN" 2>/dev/null) || fail "start failed"
[ -f "$H.state" ] || fail "no state file for $H"
S=$(session_of "$H")
ready "$S"
"$L" status "$H" >/dev/null 2>&1; rc=$?
[ "$rc" = "3" ] || fail "status rc=$rc, want 3"
esc "$S"; send "$S" $':UltraplanCancel\r'
"$L" wait "$H" >/dev/null 2>&1; rc=$?
[ "$rc" = "2" ] || fail "wait after cancel rc=$rc, want 2"
[ ! -e "$H.state" ] || fail "state file survived cancel"
"$ZMX" list --short | grep -qx "$S" && fail "session $S survived cancel"

# Submit path.
H=$("$L" start "$PLAN" 2>/dev/null) || fail "second start failed"
S=$(session_of "$H")
ready "$S"
# Add the comment through the store and submit directly: keystroke handling
# is covered by the tmux tests; this one is about the launcher's handshake.
esc "$S"; send "$S" $':lua require("ultraplan")._session.store:add({ lineno = 5, body = "from the launcher test" })\r'
esc "$S"; send "$S" $':lua require("ultraplan")._do_submit()\r'
OUT=$("$L" wait "$H" 2>/dev/null); rc=$?
[ "$rc" = "0" ] || fail "wait after submit rc=$rc, want 0"
echo "$OUT" | jq -e '.comments | length == 1' >/dev/null || fail "unexpected JSON: $OUT"
[ "$(echo "$OUT" | jq -r '.comments[0].body')" = "from the launcher test" ] || fail "wrong body"
[ ! -e "$H.state" ] || fail "state file survived submit"

# cancel subcommand on a fresh review.
H=$("$L" start "$PLAN" 2>/dev/null) || fail "third start failed"
S=$(session_of "$H")
"$L" cancel "$H" >/dev/null 2>&1 || fail "cancel subcommand failed"
[ ! -e "$H" ] && [ ! -e "$H.state" ] || fail "cancel left files behind"
sleep 0.5
"$ZMX" list --short | grep -qx "$S" && fail "session $S survived the cancel subcommand"

echo "PASS"
