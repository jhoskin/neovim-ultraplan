# neovim-ultraplan

Review a Claude Code plan in Neovim and send your comments back. A local,
keyboard-driven version of the review loop Claude Code's Ultraplan preview
offered on the web: Claude writes a plan, you read it in Neovim, leave
comments on lines, ranges, sections or the whole plan, and Claude revises
until you approve.

The plugin opens a markdown file read-only in its own tab, records your
comments, and writes a JSON review on submit. A Claude Code hook on
`ExitPlanMode` runs it every time Claude asks for plan approval.

## How the loop works

1. Claude calls `ExitPlanMode`. The hook opens the plan in a kitty tab.
2. You comment. `<leader>Ps` submits.
3. With comments, the hook denies `ExitPlanMode` and hands Claude your
   comments as markdown. Claude revises the plan file and calls
   `ExitPlanMode` again, which reopens the review.
4. With no comments, the hook stays silent and Claude Code's usual approval
   dialog appears. Cancelling (`<leader>Pq`) does the same.

Nothing in the hook can block approval by accident: every error path falls
through to the normal dialog.

## Install

Requirements: Neovim 0.10 or newer with the markdown treesitter parser. The
Claude Code integration also needs [zmx](https://github.com/neurosnap/zmx),
kitty (for the `kitten @` remote control) and `jq`.

lazy.nvim:

```lua
{
  "jhoskin/neovim-ultraplan",
  cmd = { "Ultraplan" },
  main = "ultraplan",
  opts = {
    keymaps = {
      comment_line = { "r", "<leader>Pr" },
      comment_range = { "r", "<leader>Pr" },
      comment_section = { "S", "<leader>PS" },
      comment_plan = { "R", "<leader>PR" },
    },
  },
}
```

Keep `"Ultraplan"` in `cmd`: the launcher runs `nvim -c 'Ultraplan <file>'`,
and without the entry the command is unknown until the plugin loads.

Then wire up Claude Code:

```bash
claude/install.sh
```

It symlinks `scripts/ultraplan-hook` and `scripts/ultraplan-launch` into
`~/.claude` and prints the hook entry to add to `~/.claude/settings.json`:

```json
{
  "matcher": "ExitPlanMode",
  "hooks": [
    { "type": "command", "command": "~/.claude/hooks/ultraplan-hook", "timeout": 7200 }
  ]
}
```

The timeout is how long a review may take before Claude Code gives up on
the hook and shows the normal dialog.

## Keys

Defaults; every key takes a string, a list, or `false`.

| Action | Default | Notes |
|---|---|---|
| Comment on this line | `<leader>Pr` | On a covered line, edits the existing comment |
| Comment on the selection | `<leader>Pr` (visual) | Select lines with `V`, then the key |
| Comment on this section | `<leader>PS` | The heading above the cursor through to the next heading of equal or higher level |
| Note on the whole plan | `<leader>PR` | Shown under the title |
| Delete the comment here | `<leader>Pd` | With nothing under the cursor, drops the whole-plan note |
| Next / previous comment | `]c` / `[c` | |
| Next / previous heading | `]]` / `[[` | |
| Submit | `<leader>Ps` | Shows the review first; `<CR>` sends, `q` goes back |
| Cancel | `<leader>Pq` | |
| Save a comment | `<C-s>` | Inside the comment float; `q` discards |

Comments show as a gutter sign, a tinted span, and the note below the span.
Headings inside fenced code blocks are ignored when finding sections.

## The review JSON

Written to `~/.local/share/nvim/ultraplan/<id>.json` on submit (schema in
`schema/ultraplan.v1.json`):

```json
{
  "version": 1,
  "id": "20260924T101500",
  "created_at": "2026-09-24T10:15:00Z",
  "plan": { "path": "/Users/me/.claude/plans/x.md", "sha256": "...", "line_count": 120 },
  "note": "whole-plan note, or null",
  "comments": [
    { "kind": "line",    "lineno": 12, "end_lineno": 12, "heading": "## Context",  "text": "quoted line",  "body": "..." },
    { "kind": "range",   "lineno": 30, "end_lineno": 34, "heading": "## Approach", "text": "quoted lines", "body": "..." },
    { "kind": "section", "lineno": 40, "end_lineno": 58, "heading": "## Tests",    "text": null,           "body": "..." }
  ],
  "markdown": "Plan review: x.md\n..."
}
```

`comments` is sorted by line. `text` is the quoted plan text, capped at 12
lines or 1500 bytes; section comments carry the heading instead. `markdown`
is the whole review rendered for Claude, and it is what the hook sends
back. A null `note` with no comments means the plan is approved.

## Using it without Claude Code

`:Ultraplan path/to/plan.md` opens any markdown file for review. Without
`NVIM_ULTRAPLAN_RESULT` set, submitting saves the JSON, copies the markdown
to the clipboard and closes the tab. With the variable set to a file path,
Neovim writes the JSON's path there and exits 0 on submit, 2 on cancel, 1
on error. `scripts/ultraplan-launch` wraps that for scripts:

```bash
handle=$(ultraplan-launch start plan.md)   # opens a kitty tab, returns at once
ultraplan-launch wait "$handle"            # blocks; prints the JSON, exit 0/2/1
ultraplan-launch cancel "$handle"          # tear a review down
```

## Opting out

Set `CLAUDE_ULTRAPLAN=off` in the environment, or `touch
~/.claude/ultraplan.off`. The hook also stands down when no kitty socket is
reachable (headless or remote sessions).

## Development

```bash
make unit       # headless unit tests
make test-e2e   # tmux-driven end-to-end tests (needs tmux, jq; the launcher test needs zmx)
make lint       # luacheck
make health     # :checkhealth ultraplan
```

`docs/claude-integration.md` describes the hook contract in detail.
