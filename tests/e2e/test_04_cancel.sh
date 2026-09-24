#!/usr/bin/env bash
# Covers: TST-PLN-0012
# Cancel exits 2 without a result; so does quitting Neovim with the review
# still open (the VimLeavePre safety net).
source "$(dirname "$0")/lib.sh"

SESSION="up_e2e_04"
trap 'cleanup_session "$SESSION"' EXIT

start_nvim "$SESSION" "$PLUGIN_ROOT" -c "'Ultraplan $FIXTURE_PLAN'"
wait_for "$SESSION" "Sample plan"
send_keys "$SESSION" Escape
send_keys "$SESSION" " Pq"
wait_for_exit "$SESSION"
[ "$(exit_code_for "$SESSION")" = "2" ] || { echo "FAIL: cancel exit code $(exit_code_for "$SESSION")"; exit 1; }
[ ! -e "$(result_file_for "$SESSION")" ] || { echo "FAIL: result file written on cancel"; exit 1; }
cleanup_session "$SESSION"

start_nvim "$SESSION" "$PLUGIN_ROOT" -c "'Ultraplan $FIXTURE_PLAN'"
wait_for "$SESSION" "Sample plan"
send_cmd "$SESSION" "qa"
wait_for_exit "$SESSION"
[ "$(exit_code_for "$SESSION")" = "2" ] || { echo "FAIL: :qa exit code $(exit_code_for "$SESSION")"; exit 1; }
[ ! -e "$(result_file_for "$SESSION")" ] || { echo "FAIL: result file written on :qa"; exit 1; }

echo "PASS"
