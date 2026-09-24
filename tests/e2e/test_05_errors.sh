#!/usr/bin/env bash
# Covers: TST-PLN-0013 TST-PLN-0014
# A missing plan exits 1 with a typed message on stderr. A review started
# from a directory that is not a git repository still saves and exits 0
# (nothing here depends on git).
source "$(dirname "$0")/lib.sh"

SESSION="up_e2e_05"
trap 'cleanup_session "$SESSION"; rm -rf "${SCRATCH:-}"' EXIT

start_nvim "$SESSION" "$PLUGIN_ROOT" -c "'Ultraplan /nonexistent/plan.md'"
wait_for_exit "$SESSION"
[ "$(exit_code_for "$SESSION")" = "1" ] || { echo "FAIL: missing plan exit code $(exit_code_for "$SESSION")"; exit 1; }
stderr_for "$SESSION" | grep -q "ultraplan: plan_not_found:" || { echo "FAIL: stderr lacks plan_not_found"; stderr_for "$SESSION"; exit 1; }
cleanup_session "$SESSION"

SCRATCH=$(mktemp -d -t up-nogit.XXXXXX)
cp "$FIXTURE_PLAN" "$SCRATCH/plan.md"
start_nvim "$SESSION" "$SCRATCH" -c "'Ultraplan plan.md'"
wait_for "$SESSION" "Sample plan"
send_cmd "$SESSION" "UltraplanSubmit"
wait_for "$SESSION" "approve the plan"
send_keys "$SESSION" Enter
wait_for_exit "$SESSION"
[ "$(exit_code_for "$SESSION")" = "0" ] || { echo "FAIL: non-git submit exit code $(exit_code_for "$SESSION")"; stderr_for "$SESSION"; exit 1; }
review=$(cat "$(result_file_for "$SESSION")")
assert_json_valid "$review"
[ "$(jq -r '.plan.path' "$review")" = "$(cd "$SCRATCH" && pwd -P)/plan.md" ] || { echo "FAIL: plan path not absolute: $(jq -r '.plan.path' "$review")"; exit 1; }

echo "PASS"
