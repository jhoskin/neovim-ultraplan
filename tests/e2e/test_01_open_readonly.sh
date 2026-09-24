#!/usr/bin/env bash
# Covers: TST-PLN-0008
# The plan opens in its own scratch buffer: named, read-only, private
# filetype, no LSP client, cursor in the plan window.
source "$(dirname "$0")/lib.sh"

SESSION="up_e2e_01"
trap 'cleanup_session "$SESSION"' EXIT

start_nvim "$SESSION" "$PLUGIN_ROOT" -c "'Ultraplan $FIXTURE_PLAN'"
wait_for "$SESSION" "Sample plan"

send_cmd "$SESSION" "lua print(vim.api.nvim_buf_get_name(0), vim.bo.filetype, tostring(vim.bo.modifiable), #vim.lsp.get_clients({bufnr=0}), vim.wo.signcolumn)"
assert_pane_contains "$SESSION" "ultraplan://fixture_plan.md ultraplan false 0 yes"

# Typing must not change the buffer.
send_keys "$SESSION" Escape
send_keys "$SESSION" "gg"
send_keys "$SESSION" "ihello"
send_keys "$SESSION" Escape
send_cmd "$SESSION" "lua print('LINE1=' .. vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])"
assert_pane_contains "$SESSION" "LINE1=# Sample plan"

assert_session_alive "$SESSION"
echo "PASS"
