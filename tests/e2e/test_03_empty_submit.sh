#!/usr/bin/env bash
# Covers: TST-PLN-0011
# Submitting with no comments is an approval: exit 0, note null, no
# comments, and the summary says so before confirming.
source "$(dirname "$0")/lib.sh"

SESSION="pr_e2e_03"
trap 'cleanup_session "$SESSION"' EXIT

start_nvim "$SESSION" "$PLUGIN_ROOT" -c "'PlanReview $FIXTURE_PLAN'"
wait_for "$SESSION" "Sample plan"

send_cmd "$SESSION" "PlanReviewSubmit"
wait_for "$SESSION" "approve the plan"
assert_pane_contains "$SESSION" "approved as written"
send_keys "$SESSION" Enter
wait_for_exit "$SESSION"

[ "$(exit_code_for "$SESSION")" = "0" ] || { echo "FAIL: exit code $(exit_code_for "$SESSION")"; exit 1; }
review=$(cat "$(result_file_for "$SESSION")")
assert_json_valid "$review"
[ "$(jq -r '.note' "$review")" = "null" ] || { echo "FAIL: note not null"; exit 1; }
[ "$(jq -r '.comments | length' "$review")" = "0" ] || { echo "FAIL: comments not empty"; exit 1; }
grep -q '"note":null' "$review" || { echo "FAIL: note key missing from JSON"; cat "$review"; exit 1; }
grep -q '"comments":\[\]' "$review" || { echo "FAIL: comments not []"; cat "$review"; exit 1; }

echo "PASS"
