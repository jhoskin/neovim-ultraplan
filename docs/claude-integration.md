# Claude Code integration

How the plugin, the launcher and the hook fit together, and what each side
promises the other.

## Pieces

- `scripts/plan-review-hook`: a Claude Code PreToolUse hook matched on
  `ExitPlanMode`. Runs the launcher, waits, and turns the review into a
  hook decision.
- `scripts/plan-review-launch`: starts Neovim on a plan inside a detached zmx
  session, surfaces it as a focused kitty tab, and reports the outcome.
- The plugin: `:PlanReview <file>` plus the `NVIM_PLAN_REVIEW_RESULT` handshake.

`claude/install.sh` symlinks the two scripts into `~/.claude/hooks` and
`~/.claude/scripts`. The hook entry in `~/.claude/settings.json` is added by
hand (the installer prints it).

## The hook

Claude Code runs the hook with this on stdin (Claude Code 2.1.281):

```json
{
  "session_id": "...",
  "cwd": "/path/to/project",
  "tool_name": "ExitPlanMode",
  "tool_input": {
    "plan": "# Title\n\n...",
    "planFilePath": "/Users/me/.claude/plans/slug.md"
  }
}
```

The hook stands down, printing nothing and exiting 0, when:

- `CLAUDE_PLAN_REVIEW=off` is set or `~/.claude/plan-review.off` exists;
- `tool_name` is not `ExitPlanMode`;
- neither `planFilePath` nor `plan` is present;
- no kitty socket (`/tmp/kitty-<pid>`) exists, so there is nowhere to show
  the review;
- the launcher is missing or its work directory cannot be created.

Otherwise it decides which text to review. When the file at `planFilePath`
exists and its content matches `plan` (compared without trailing newlines),
the file is reviewed. When they differ, or the file is missing, `plan` is
written to `/tmp/plan-review-launch/plan.XXXXXX.md` and that is reviewed, so
you never read a stale file.

It then runs `plan-review-launch start <file>` and `plan-review-launch wait
<handle>` with stdin and stdout detached from the hook's own, so nothing
but the final decision can reach stdout. The wait runs in the background
with a trap on TERM, HUP and INT that cancels the review, so Claude Code's
hook timeout tears the kitty tab down instead of leaving it open.

The outcome maps to:

| Review result | Hook output | Effect in Claude Code |
|---|---|---|
| Submitted with comments | deny JSON on stdout, exit 0 | `ExitPlanMode` is refused; Claude reads the reason, revises the plan file, and calls `ExitPlanMode` again |
| Submitted with no comments | nothing, exit 0 | The normal approval dialog appears |
| Cancelled (exit 2) or aborted | a note on stderr, exit 0 | The normal approval dialog appears |
| Launcher or Neovim error | a note on stderr, exit 0 | The normal approval dialog appears |

The deny JSON:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "<review markdown>\n\n<follow-up>"
  }
}
```

The review markdown is the `markdown` field of the JSON the plugin wrote:
it opens with a preamble saying the user reviewed the plan in Neovim, which
file and revision, and how the `L12-15 (## Heading)` anchors, section
comments, quotes and the whole-plan note read. The summary you saw before
submitting is exactly that text. The hook appends one follow-up line
telling Claude to revise the plan file and call `ExitPlanMode` again.

Test overrides: `PLAN_REVIEW_LAUNCHER` (path to a stub launcher),
`PLAN_REVIEW_REQUIRE_KITTY=0`, `PLAN_REVIEW_WORKDIR`, `PLAN_REVIEW_OFF_FILE`.
`tests/e2e/test_07_hook.sh` drives the hook with a stub and covers every
row of the table above.

## The launcher

```text
plan-review-launch start <plan.md>       print a handle, exit 0
plan-review-launch status <handle>       3 running, 0 done (JSON), 2 cancelled/aborted, 1 error
plan-review-launch wait <handle> [secs]  block until done; same codes
plan-review-launch cancel <handle>       kill the review, remove its files
plan-review-launch gc                    reap reviews older than 6 hours
```

`start` resolves the path, refuses `'`, `"`, `|`, `\` and newlines (the
path is interpolated into a shell string and an Ex command), and requires
the file to exist. It creates a handle under `/tmp/plan-review-launch`,
writes `<handle>.state` (start time, zmx session, plan path), then runs

```sh
NVIM_PLAN_REVIEW_RESULT='<handle>' nvim -c 'PlanReview <plan>'; echo $? > '<handle>.done'
```

inside `zmx run plan-review-<id> -d`, and opens a focused kitty tab running
`zmx attach`. The zmx session is the source of truth: closing the tab only
detaches; the review ends when Neovim exits. `wait` polls the `.done`
sentinel; a session that vanishes without one is reported as aborted (2).
Every terminal state kills the session and removes the files.

Environment: `PLAN_REVIEW_ZMX_BIN`, `PLAN_REVIEW_KITTEN_BIN`, `PLAN_REVIEW_NVIM_BIN` (may carry
arguments, e.g. `nvim -u tests/minimal_init.lua`), `PLAN_REVIEW_WORKDIR`,
`PLAN_REVIEW_GC_MAX_AGE`, `PLAN_REVIEW_TAB_TITLE`.

## The plugin's side of the handshake

With `NVIM_PLAN_REVIEW_RESULT` set, `:PlanReview <file>`:

- exits 1 with `plan-review: <type>: <message>` on stderr when the file is
  unreadable (`plan_not_found`), Neovim is too old (`version_error`), no UI
  is attached (`no_ui`), or the review cannot be saved (`storage_error`);
- on submit, saves `~/.local/share/nvim/plan-review/<id>.json`, writes that
  path (no trailing newline) to the result file, and exits 0;
- on cancel exits 2 with no result file; quitting Neovim with the review
  still open also exits 2.

The JSON is described in the README and `schema/plan-review.v1.json`.

## Troubleshooting

- The tab opens on the LazyVim dashboard, or `E492: Not an editor command:
  PlanReview`: the plugin is not loading for the command. Add `"PlanReview"`
  to the lazy.nvim `cmd` list.
- The review opens but Claude Code shows the dialog anyway: the hook's
  stdout was not a single JSON document. Run
  `echo '<payload>' | ~/.claude/hooks/plan-review-hook` by hand and check
  that nothing else prints.
- `Press ENTER` on startup inside the tab: startup messages stacked past
  `cmdheight`. Whatever prints during your init needs to go.
- Reviews piling up in `zmx list`: `plan-review-launch gc`, or `cancel` a
  specific handle from `/tmp/plan-review-launch`.
- Claude Code has a 600 second default hook timeout. The installer's entry
  raises it to 7200; without that, a long review is cut short and the
  dialog appears while the tab is still open.
