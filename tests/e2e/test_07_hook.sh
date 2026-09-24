#!/usr/bin/env bash
# Covers: TST-PLN-0016 TST-PLN-0017 TST-PLN-0018
# The ExitPlanMode hook, driven with a stub launcher (no Neovim, no kitty):
# comments produce exactly the deny JSON; an empty review, a cancel and an
# error print nothing and exit 0; the opt-outs and missing fields never
# invoke the launcher; a plan file that differs from the plan text is
# replaced by a temp file holding the text.
set -uo pipefail

PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HOOK="$PLUGIN_ROOT/scripts/plan-review-hook"
WORK=$(mktemp -d -t pr-hook.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

STUB="$WORK/stub-launcher"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
# Stub launcher: records calls, returns canned results.
echo "$1 ${2:-}" >> "$STUB_LOG"
case "$1" in
  start) echo "$STUB_LOG.handle" ;;
  wait) cat "$STUB_JSON"; exit "${STUB_RC:-0}" ;;
  cancel) touch "$STUB_LOG.cancelled" ;;
esac
EOF
chmod +x "$STUB"

export PLAN_REVIEW_LAUNCHER="$STUB" PLAN_REVIEW_REQUIRE_KITTY=0 PLAN_REVIEW_WORKDIR="$WORK/wd" PLAN_REVIEW_OFF_FILE="$WORK/off"
export STUB_LOG="$WORK/calls" STUB_JSON="$WORK/review.json"
unset CLAUDE_PLAN_REVIEW

PLAN="$WORK/plan.md"
printf '# Plan\n\n## Step\n\nDo the thing.\n' > "$PLAN"
plan_text=$(cat "$PLAN")

input() {
  jq -n --arg path "$1" --arg plan "$2" \
    '{session_id:"s1", cwd:"/tmp", tool_name:"ExitPlanMode", tool_input:{plan:$plan, planFilePath:$path}}'
}

# run_hook <stdin-json>: runs the hook in this shell (no pipeline, so the
# result variables survive).
run_hook() {
  rm -f "$STUB_LOG" "$STUB_LOG.cancelled"
  HOOK_OUT=$(printf '%s' "$1" | "$HOOK" 2>"$WORK/stderr")
  HOOK_RC=$?
}

fail() {
  echo "FAIL: $*"
  echo "--- stdout: $HOOK_OUT"
  echo "--- stderr:"; cat "$WORK/stderr" 2>/dev/null
  echo "--- calls:"; cat "$STUB_LOG" 2>/dev/null
  exit 1
}

# 1. Comments -> deny JSON whose reason ends with the review markdown.
cat > "$STUB_JSON" <<'EOF'
{"version":1,"note":null,"comments":[{"kind":"line","lineno":5,"end_lineno":5,"heading":"## Step","text":"Do the thing.","body":"which thing?"}],"markdown":"Plan review: plan.md\n\n## L5 (## Step)\n\n> Do the thing.\n\nwhich thing?"}
EOF
run_hook "$(input "$PLAN" "$plan_text")"
[ "$HOOK_RC" = "0" ] || fail "deny case exit $HOOK_RC"
echo "$HOOK_OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny"' >/dev/null || fail "not a deny"
echo "$HOOK_OUT" | jq -e '.hookSpecificOutput.permissionDecisionReason | startswith("Plan review: plan.md")' >/dev/null || fail "reason does not start with the markdown"
echo "$HOOK_OUT" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("which thing?")' >/dev/null || fail "reason lacks the comment"
echo "$HOOK_OUT" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("call ExitPlanMode again")' >/dev/null || fail "reason lacks the preamble"
[ "$(echo "$HOOK_OUT" | jq -c . | wc -l | tr -d ' ')" = "1" ] || fail "stdout is not exactly one JSON document"
grep -q "^start $PLAN$" "$STUB_LOG" || fail "launcher did not get the plan file"

# 2. Empty review -> no output, exit 0.
echo '{"version":1,"note":null,"comments":[],"markdown":"Plan review: plan.md\n\nNo comments."}' > "$STUB_JSON"
run_hook "$(input "$PLAN" "$plan_text")"
[ "$HOOK_RC" = "0" ] && [ -z "$HOOK_OUT" ] || fail "approve case rc=$HOOK_RC out=$HOOK_OUT"

# 3. Cancel (rc 2) and error (rc 1) -> no output, exit 0.
for rc in 2 1; do
  STUB_RC=$rc run_hook "$(input "$PLAN" "$plan_text")"
  [ "$HOOK_RC" = "0" ] && [ -z "$HOOK_OUT" ] || fail "rc=$rc case rc=$HOOK_RC out=$HOOK_OUT"
  grep -q "standard plan dialog" "$WORK/stderr" || fail "rc=$rc case: no stderr note"
done

# 4. Opt-outs never invoke the launcher.
CLAUDE_PLAN_REVIEW=off run_hook "$(input "$PLAN" "$plan_text")"
[ "$HOOK_RC" = "0" ] && [ -z "$HOOK_OUT" ] && [ ! -e "$STUB_LOG" ] || fail "env opt-out invoked the launcher"
touch "$WORK/off"
run_hook "$(input "$PLAN" "$plan_text")"
[ "$HOOK_RC" = "0" ] && [ -z "$HOOK_OUT" ] && [ ! -e "$STUB_LOG" ] || fail "off file invoked the launcher"
rm -f "$WORK/off"

# 5. Other tools and missing plan fields are ignored.
run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
[ "$HOOK_RC" = "0" ] && [ -z "$HOOK_OUT" ] && [ ! -e "$STUB_LOG" ] || fail "other tool invoked the launcher"
run_hook '{"tool_name":"ExitPlanMode","tool_input":{}}'
[ "$HOOK_RC" = "0" ] && [ -z "$HOOK_OUT" ] && [ ! -e "$STUB_LOG" ] || fail "empty tool_input invoked the launcher"

# 6. Plan text differs from the file -> the launcher gets a temp file with the text.
echo '{"version":1,"note":null,"comments":[],"markdown":"x"}' > "$STUB_JSON"
run_hook "$(input "$PLAN" "$plan_text"$'\n\nNewer paragraph.')"
got=$(sed -n 's/^start //p' "$STUB_LOG")
[ "$got" != "$PLAN" ] || fail "stale file was reviewed"
[ -f "$got" ] || fail "temp plan file missing: $got"
grep -q "Newer paragraph." "$got" || fail "temp plan lacks the newer text"
case "$got" in "$WORK/wd/plan."*.md) ;; *) fail "temp plan not under the workdir: $got" ;; esac

# 7. No file on disk but plan text present -> temp file too.
run_hook "$(input "/nonexistent/plan.md" "$plan_text")"
got=$(sed -n 's/^start //p' "$STUB_LOG")
[ -f "$got" ] && grep -q "Do the thing." "$got" || fail "missing file case did not fall back to the text"

echo "PASS"
