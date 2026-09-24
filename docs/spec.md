# neovim-plan-review specification

Requirements in EARS form, each with a test id. `Auto` tests are referenced
by id in a test file header (`-- Covers:` or `# Covers:`); `Manual` tests
are checked by hand.

## 1. Purpose

Let a person review a markdown plan in Neovim, anchor comments to lines,
line ranges, sections or the whole plan, and hand the result to Claude Code
as JSON. The plan is never edited by the plugin.

Non-goals: threaded comments, editing the plan text inside the review,
pause and resume, marking what changed between rounds.

## 2. Structure (sections.lua)

**REQ-PLN-0001** (Ubiquitous): The system shall treat a line as a heading
when it matches `^#{1,6} ` outside a fenced code block (``` or ~~~).

**REQ-PLN-0002** (Ubiquitous): A section shall run from its heading to the
line before the next heading of equal or higher level, else to the last
line.

**REQ-PLN-0003** (Ubiquitous): `section_for` shall return the innermost
section containing a line, and nil above the first heading.

**REQ-PLN-0004** (Ubiquitous): Quoted text shall be capped at a configured
number of lines and bytes without splitting a UTF-8 sequence.

## 3. Store (store.lua)

**REQ-PLN-0005** (Ubiquitous): Comments shall be keyed by start line; a
later comment on the same start line replaces the earlier one; blank
bodies are rejected; `all()` is sorted by line; the whole-plan note counts
as one comment.

## 4. Output (result.lua, export.lua, schema/plan-review.v1.json)

**REQ-PLN-0006** (Event-driven): When the user submits, the system shall
write a JSON document matching `schema/plan-review.v1.json`: nullable fields
are emitted as `null`, an empty comment list as `[]`, comments sorted by
line, `end_lineno` equal to `lineno` for a line comment, and `plan.sha256`
over the displayed lines.

**REQ-PLN-0007** (Ubiquitous): The document shall embed `markdown`, the
review rendered by `export.to_markdown`: the whole-plan note first, then
each comment as `L<a>-<b> (<heading>)` with the quoted text as a block
quote and the body.

## 5. View (render.lua, ui.lua)

**REQ-PLN-0008** (Event-driven): When `:PlanReview <file>` runs, the system
shall open the plan in a new tab in a scratch buffer named
`plan-review://<basename>` with `modifiable=false`, filetype `planreview`, no
LSP client, and the cursor in that window.

**REQ-PLN-0009** (Event-driven): When the user invokes the line, range,
section or whole-plan comment key, the system shall open a floating editor
and, on `<C-s>`, store the comment with its span, enclosing heading and
capped quoted text (no text for a section comment).

**REQ-PLN-0010** (Ubiquitous): Stored comments shall be painted as a sign on
the start line, a tinted span, and the body below the span; the whole-plan
note below the first line.

**REQ-PLN-0015** (Event-driven): When the comment key is pressed on a line
covered by a comment, the system shall prefill the editor with that
comment; the delete key shall remove the covering comment, or the
whole-plan note when nothing covers the cursor; `]c`/`[c` and `]]`/`[[`
shall move between comments and headings.

## 6. Session and exit codes (init.lua, plugin/planreview.lua)

**REQ-PLN-0011** (Event-driven): When the user submits with no comments,
the summary shall say the plan is approved and the document shall carry
`note: null` and `comments: []`.

**REQ-PLN-0012** (Event-driven): In agent mode (`NVIM_PLAN_REVIEW_RESULT`
set), cancel and quitting Neovim shall exit 2 without a result file.

**REQ-PLN-0013** (Unwanted): If the plan file cannot be read, the system
shall exit 1 with `plan-review: plan_not_found: ...` on stderr.

**REQ-PLN-0014** (Ubiquitous): The system shall not depend on git; a review
started outside a repository shall save and exit 0.

## 7. Hook and launcher (scripts/)

**REQ-PLN-0016** (Event-driven): When the review is submitted with
comments, the hook shall print exactly one JSON document denying
`ExitPlanMode` whose reason ends with the review markdown, and exit 0.

**REQ-PLN-0017** (Event-driven): When the review is empty, cancelled or
fails, the hook shall print nothing and exit 0.

**REQ-PLN-0018** (Ubiquitous): The hook shall not invoke the launcher when
opted out, when the tool is not `ExitPlanMode`, or when no plan is present;
when the plan file differs from the plan text, it shall review a temp file
holding the text.

**REQ-PLN-0019** (Ubiquitous): The launcher shall refuse unsafe or missing
paths, report a running review as 3, a cancelled one as 2 with its session
torn down, and a submitted one as 0 with the JSON on stdout.

**REQ-PLN-0020** (Event-driven): When `cancel <handle>` runs, the launcher
shall kill the session and remove the handle's files.

## 8. Verification matrix

| Requirement | Test | Mode | Where |
|---|---|---|---|
| REQ-PLN-0001 | TST-PLN-0001 | Auto | tests/unit/sections_spec.lua |
| REQ-PLN-0002 | TST-PLN-0002 | Auto | tests/unit/sections_spec.lua |
| REQ-PLN-0003 | TST-PLN-0003 | Auto | tests/unit/sections_spec.lua |
| REQ-PLN-0004 | TST-PLN-0004 | Auto | tests/unit/sections_spec.lua |
| REQ-PLN-0005 | TST-PLN-0005 | Auto | tests/unit/store_spec.lua |
| REQ-PLN-0006 | TST-PLN-0006 | Auto | tests/unit/result_spec.lua |
| REQ-PLN-0007 | TST-PLN-0007 | Auto | tests/unit/result_spec.lua |
| REQ-PLN-0008 | TST-PLN-0008 | Auto | tests/e2e/test_01_open_readonly.sh |
| REQ-PLN-0009 | TST-PLN-0009 | Auto | tests/e2e/test_02_anchors_json.sh |
| REQ-PLN-0010 | TST-PLN-0010 | Auto | tests/e2e/test_02_anchors_json.sh (markers in the pane) |
| REQ-PLN-0011 | TST-PLN-0011 | Auto | tests/e2e/test_03_empty_submit.sh |
| REQ-PLN-0012 | TST-PLN-0012 | Auto | tests/e2e/test_04_cancel.sh |
| REQ-PLN-0013 | TST-PLN-0013 | Auto | tests/e2e/test_05_errors.sh |
| REQ-PLN-0014 | TST-PLN-0014 | Auto | tests/e2e/test_05_errors.sh |
| REQ-PLN-0015 | TST-PLN-0015 | Auto | tests/e2e/test_06_edit_delete.sh |
| REQ-PLN-0016 | TST-PLN-0016 | Auto | tests/e2e/test_07_hook.sh |
| REQ-PLN-0017 | TST-PLN-0017 | Auto | tests/e2e/test_07_hook.sh |
| REQ-PLN-0018 | TST-PLN-0018 | Auto | tests/e2e/test_07_hook.sh |
| REQ-PLN-0019 | TST-PLN-0019 | Auto | tests/e2e/test_08_launcher.sh |
| REQ-PLN-0020 | TST-PLN-0020 | Auto | tests/e2e/test_08_launcher.sh |
| Kitty tab opens focused, hook loop end to end in Claude Code | TST-PLN-0021 | Manual | pipe a PreToolUse payload into `~/.claude/hooks/plan-review-hook` |
