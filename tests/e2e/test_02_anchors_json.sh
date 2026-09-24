#!/usr/bin/env bash
# Covers: TST-PLN-0009 TST-PLN-0010
# One of each anchor (line, visual range, section, whole plan) lands in the
# submitted JSON with the right span, heading, quoted text and body, sorted
# by line, with the markdown rendering embedded.
source "$(dirname "$0")/lib.sh"

SESSION="up_e2e_02"
trap 'cleanup_session "$SESSION"' EXIT

start_nvim "$SESSION" "$PLUGIN_ROOT" -c "'Ultraplan $FIXTURE_PLAN'"
wait_for "$SESSION" "Sample plan"

# Line comment on line 5 (inside ## Context).
send_keys "$SESSION" Escape
send_keys "$SESSION" "5G"
send_keys "$SESSION" " Pr"
type_comment "$SESSION" "stale how long?"

# Section comment from line 20 (inside ### Risks, lines 18-21).
send_keys "$SESSION" "20G"
send_keys "$SESSION" " PS"
type_comment "$SESSION" "quantify the risk"

# Whole-plan note.
send_keys "$SESSION" " PR"
type_comment "$SESSION" "looks good overall"

# Visual range over lines 10-11.
send_keys "$SESSION" "10G"
send_keys "$SESSION" "V"
send_keys "$SESSION" "j"
send_keys "$SESSION" " Pr"
type_comment "$SESSION" "merge steps 1 and 2"

# Markers are painted.
assert_pane_contains "$SESSION" "stale how long?"
assert_pane_contains "$SESSION" "merge steps 1 and 2"
assert_pane_contains "$SESSION" "whole plan:"

send_cmd "$SESSION" "UltraplanSubmit"
wait_for "$SESSION" "Send 4 comments"
send_keys "$SESSION" Enter
wait_for_exit "$SESSION"

[ "$(exit_code_for "$SESSION")" = "0" ] || { echo "FAIL: exit code $(exit_code_for "$SESSION")"; exit 1; }
result_file=$(result_file_for "$SESSION")
assert_file_exists "$result_file"
review=$(cat "$result_file")
assert_file_exists "$review"
assert_json_valid "$review"

check() {
  local expr="$1" want="$2"
  local got
  got=$(jq -r "$expr" "$review")
  if [ "$got" != "$want" ]; then
    echo "FAIL: $expr = '$got', want '$want'"
    jq . "$review"
    exit 1
  fi
}

check '.version' '1'
check '.note' 'looks good overall'
check '.plan.line_count' '24'
check '.plan.sha256 | length' '64'
check '.comments | length' '3'
check '[.comments[].lineno] | @csv' '5,10,18'
check '.comments[0] | [.kind, .end_lineno, .heading] | @csv' '"line",5,"## Context"'
check '.comments[0].text' 'The widget service returns stale data after a deploy because the cache'
check '.comments[0].body' 'stale how long?'
check '.comments[1] | [.kind, .end_lineno, .heading] | @csv' '"range",11,"## Approach"'
check '.comments[1].text' $'1. Add a version key to every cache entry.\n2. Bump the key on deploy.'
check '.comments[2] | [.kind, .end_lineno, .heading, .text] | @csv' '"section",21,"### Risks",'
check '.comments[2].body' 'quantify the risk'
check '.markdown | startswith("Plan review: fixture_plan.md")' 'true'
check '.markdown | contains("## L18-21, section ### Risks")' 'true'
check '.markdown | contains("> 1. Add a version key")' 'true'

echo "PASS"
