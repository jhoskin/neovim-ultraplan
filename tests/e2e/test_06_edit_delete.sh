#!/usr/bin/env bash
# Covers: TST-PLN-0015
# The comment key on a covered line edits the existing comment (prefilled),
# delete removes the covering comment, a second comment on the same start
# line replaces the first, and delete with nothing under the cursor drops
# the whole-plan note.
source "$(dirname "$0")/lib.sh"

SESSION="pr_e2e_06"
trap 'cleanup_session "$SESSION"' EXIT

count() {
  send_cmd "$SESSION" "lua print('COUNT=' .. require('planreview')._session.store:count())"
}

start_nvim "$SESSION" "$PLUGIN_ROOT" -c "'PlanReview $FIXTURE_PLAN'"
wait_for "$SESSION" "Sample plan"

# Range 10-11, then press the comment key on line 11: the float is prefilled.
send_keys "$SESSION" Escape
send_keys "$SESSION" "10G"
send_keys "$SESSION" "V"
send_keys "$SESSION" "j"
send_keys "$SESSION" " Pr"
type_comment "$SESSION" "first draft"
send_keys "$SESSION" "11G"
send_keys "$SESSION" " Pr"
sleep 0.5
assert_pane_contains "$SESSION" "Range comment L10-11"
assert_pane_contains "$SESSION" "first draft"
send_keys "$SESSION" Escape
send_keys "$SESSION" "A"
type_comment "$SESSION" " (edited)"
send_cmd "$SESSION" "lua local c = require('planreview')._session.store:get(10); print('REC=' .. c.kind .. ':' .. c.end_lineno .. ':' .. c.body)"
assert_pane_contains "$SESSION" "REC=range:11:first draft (edited)"

# A line comment on line 10 replaces the range comment (same start line).
send_keys "$SESSION" "10G"
send_keys "$SESSION" " Pd"
sleep 0.3
count
assert_pane_contains "$SESSION" "COUNT=0"
send_keys "$SESSION" " Pr"
type_comment "$SESSION" "just this line"
send_cmd "$SESSION" "lua local c = require('planreview')._session.store:get(10); print('REC2=' .. c.kind .. ':' .. c.end_lineno)"
assert_pane_contains "$SESSION" "REC2=line:10"

# Delete with nothing under the cursor removes the whole-plan note.
send_keys "$SESSION" " PR"
type_comment "$SESSION" "overall"
count
assert_pane_contains "$SESSION" "COUNT=2"
send_keys "$SESSION" "3G"
send_keys "$SESSION" " Pd"
sleep 0.3
count
assert_pane_contains "$SESSION" "COUNT=1"

# Navigation: ]c from the top lands on the remaining comment, ]] on a heading.
send_keys "$SESSION" "gg"
send_keys "$SESSION" "]c"
send_cmd "$SESSION" "lua print('CUR=' .. vim.api.nvim_win_get_cursor(0)[1])"
assert_pane_contains "$SESSION" "CUR=10"
send_keys "$SESSION" "]]"
send_cmd "$SESSION" "lua print('HEAD=' .. vim.api.nvim_win_get_cursor(0)[1])"
assert_pane_contains "$SESSION" "HEAD=18"

echo "PASS"
