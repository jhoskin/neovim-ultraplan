-- Session lifecycle, comment actions, keymaps, submit and cancel.

local config = require("ultraplan.config")
local Store = require("ultraplan.store")
local sections = require("ultraplan.sections")
local render = require("ultraplan.render")
local ui = require("ultraplan.ui")
local result = require("ultraplan.result")
local export = require("ultraplan.export")

local M = {}

M._session = nil

function M.setup(opts)
  config.setup(opts)
end

local function notify(msg, level)
  vim.notify("ultraplan: " .. msg, level or vim.log.levels.INFO)
end

local function first_key(v)
  if type(v) == "table" then
    return v[1]
  end
  return v
end

-- Preflight for a review. Returns an error tag after calling exit_error, or
-- nil when the review can start.
function M._preflight(path)
  if vim.fn.has("nvim-0.10") ~= 1 then
    result.exit_error("version_error", "requires Neovim >= 0.10")
    return "version"
  end
  -- The review is interactive; a headless Neovim cannot take comment input.
  if #vim.api.nvim_list_uis() == 0 then
    result.exit_error("no_ui", "no interactive UI (running headless)")
    return "no_ui"
  end
  if not path or path == "" or vim.fn.filereadable(path) ~= 1 then
    result.exit_error("plan_not_found", "cannot read plan file: " .. tostring(path))
    return "plan"
  end
  return nil
end

function M.start(path)
  if M._session then
    notify("a plan review is already active", vim.log.levels.WARN)
    return
  end

  path = vim.fn.fnamemodify(vim.fs.normalize(path or ""), ":p")
  if M._preflight(path) then
    return
  end

  local lines = vim.fn.readfile(path)
  M._session = {
    store = Store.new(),
    plan_info = { path = path, lines = lines },
    submitted = false,
  }

  M._register_autocmds()
  M._register_commands()
  render.open(M._session.plan_info, M._session.store, { keymaps = M._set_keymaps })
  M._notify_started()
end

function M._notify_started()
  local km = config.values.keymaps
  notify(string.format(
    "%s line · %s section · %s whole plan · %s submit · %s cancel",
    tostring(first_key(km.comment_line)),
    tostring(first_key(km.comment_section)),
    tostring(first_key(km.comment_plan)),
    tostring(first_key(km.submit)),
    tostring(first_key(km.cancel))
  ))
end

-- Comment actions ----------------------------------------------------------

-- Open the editor for an anchor { kind, lineno, end_lineno, heading? } and
-- store the result. Editing an existing comment passes its body as prefill.
function M._edit_anchor(anchor, prefill)
  local s = M._session
  if not s then
    return
  end
  local label
  if anchor.kind == "section" then
    label = anchor.heading or ""
  elseif anchor.end_lineno ~= anchor.lineno then
    label = string.format("L%d-%d", anchor.lineno, anchor.end_lineno)
  else
    label = string.format("L%d", anchor.lineno)
  end

  ui.open_comment_float({
    prefill = prefill or "",
    kind = anchor.kind,
    label = label,
    on_confirm = function(body)
      local rec = {
        kind = anchor.kind,
        lineno = anchor.lineno,
        end_lineno = anchor.end_lineno,
        body = body,
      }
      if anchor.kind == "section" then
        rec.heading = anchor.heading
      else
        rec.heading = sections.heading_for_span(render.sections(), anchor.lineno, anchor.end_lineno)
        local cap = config.values.text_cap
        rec.text = sections.cap_text(render.slice(anchor.lineno, anchor.end_lineno), cap.lines, cap.bytes)
      end
      s.store:add(rec)
      render.repaint()
    end,
  })
end

-- Comment on the cursor line, or edit the comment covering it.
function M.comment_line()
  if not M._session then
    return
  end
  local ln = render.cursor_line()
  if not ln then
    return
  end
  local existing = render.comment_at_cursor()
  if existing then
    M._edit_anchor(existing, existing.body)
    return
  end
  M._edit_anchor({ kind = "line", lineno = ln, end_lineno = ln })
end

-- Comment on the visual selection (bound in visual mode).
function M.comment_range()
  if not M._session or not render.cursor_line() then
    return
  end
  local a, b = render.visual_range()
  -- Blank lines at either end of a selection carry nothing; drop them so
  -- the span and the quoted text start on real content.
  a, b = sections.trim_blank(render.lines(), a, b)
  local anchor = { kind = a == b and "line" or "range", lineno = a, end_lineno = b }
  local existing = M._session.store:get(a)
  M._edit_anchor(anchor, existing and existing.body or "")
end

-- Comment on the markdown section under the cursor.
function M.comment_section()
  if not M._session then
    return
  end
  local sec = render.section_at_cursor()
  if not sec then
    if render.cursor_line() then
      notify("no section under the cursor (above the first heading)", vim.log.levels.WARN)
    end
    return
  end
  local anchor = { kind = "section", lineno = sec.lineno, end_lineno = sec.end_lineno, heading = sec.heading }
  local existing = M._session.store:get(sec.lineno)
  M._edit_anchor(anchor, existing and existing.kind == "section" and existing.body or "")
end

-- Note on the whole plan.
function M.comment_plan()
  local s = M._session
  if not s then
    return
  end
  ui.open_comment_float({
    prefill = s.store.note or "",
    kind = "plan",
    label = vim.fn.fnamemodify(s.plan_info.path, ":t"),
    on_confirm = function(body)
      s.store:set_note(body)
      render.repaint()
    end,
  })
end

-- Delete the comment covering the cursor; with none, drop the whole-plan
-- note if there is one.
function M.delete_comment()
  local s = M._session
  if not s then
    return
  end
  local ln = render.cursor_line()
  if not ln then
    return
  end
  local c = render.comment_at_cursor()
  if c then
    s.store:delete(c.lineno)
    render.repaint()
    return
  end
  if s.store.note then
    s.store:clear_note()
    render.repaint()
    notify("whole-plan note removed")
  end
end

function M.next_comment()
  if M._session and not render.next_comment() then
    notify("no comment below")
  end
end

function M.prev_comment()
  if M._session and not render.prev_comment() then
    notify("no comment above")
  end
end

function M.next_heading()
  if M._session then
    render.next_heading()
  end
end

function M.prev_heading()
  if M._session then
    render.prev_heading()
  end
end

-- Submit / cancel ----------------------------------------------------------

function M.submit()
  local s = M._session
  if not s then
    return
  end
  local data = result.serialize(s.store, s.plan_info)
  local lines = vim.split(data.markdown, "\n", { plain = true })
  local title
  if result.is_approval(data) then
    title = " No comments: approve the plan? — <CR> approve · q back "
  else
    title = string.format(" Send %d comment%s — <CR> submit · q back ",
      s.store:count(), s.store:count() == 1 and "" or "s")
  end
  ui.open_summary_float(lines, title, M._do_submit, nil)
end

function M._do_submit()
  local s = M._session
  if not s then
    return
  end
  local data = result.serialize(s.store, s.plan_info)
  local filepath, err = result.save(data)
  if not filepath then
    result.exit_error("storage_error", err)
    return
  end

  s.submitted = true
  M._cleanup()

  if result.agent_mode() then
    result.exit_submit(filepath)
  else
    export.to_clipboard(data)
    render.close()
    notify("submitted (saved to " .. filepath .. "; markdown copied to clipboard)")
  end
end

function M.cancel()
  if not M._session then
    return
  end
  M._cleanup()
  render.close()
  if result.agent_mode() then
    result.exit_cancel()
  else
    notify("review cancelled")
  end
end

-- Plumbing -----------------------------------------------------------------

function M._register_autocmds()
  local group = vim.api.nvim_create_augroup("ultraplan_session", { clear = true })
  -- Neovim is quitting with an unsubmitted review and no explicit
  -- submit/cancel/error ran: treat it as a cancel. cquit is a no-op this late
  -- in shutdown, so force the exit code with os.exit.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if not (M._session and not M._session.submitted) then
        return
      end
      if result._exit_initiated then
        return
      end
      local agent = result.agent_mode()
      M._cleanup()
      if agent then
        result._exit_initiated = true
        os.exit(2)
      end
    end,
  })
end

function M._register_commands()
  vim.api.nvim_create_user_command("UltraplanSubmit", function()
    M.submit()
  end, { desc = "Ultraplan: review the comments and submit" })
  vim.api.nvim_create_user_command("UltraplanCancel", function()
    M.cancel()
  end, { desc = "Ultraplan: cancel the review" })
end

function M._cleanup()
  pcall(vim.api.nvim_del_augroup_by_name, "ultraplan_session")
  pcall(vim.api.nvim_del_user_command, "UltraplanSubmit")
  pcall(vim.api.nvim_del_user_command, "UltraplanCancel")
  M._session = nil
end

local function set_map(bufnr, lhs, fn, desc, modes)
  if lhs == nil or lhs == false then
    return
  end
  local keys = type(lhs) == "table" and lhs or { lhs }
  for _, key in ipairs(keys) do
    vim.keymap.set(modes or "n", key, fn, { buffer = bufnr, nowait = true, desc = desc })
  end
end

function M._set_keymaps(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local km = config.values.keymaps
  set_map(bufnr, km.comment_line, M.comment_line, "Ultraplan: comment on this line")
  set_map(bufnr, km.comment_range, M.comment_range, "Ultraplan: comment on the selection", "x")
  set_map(bufnr, km.comment_section, M.comment_section, "Ultraplan: comment on this section")
  set_map(bufnr, km.comment_plan, M.comment_plan, "Ultraplan: note on the whole plan")
  set_map(bufnr, km.delete_comment, M.delete_comment, "Ultraplan: delete the comment here")
  set_map(bufnr, km.next_comment, M.next_comment, "Ultraplan: next comment")
  set_map(bufnr, km.prev_comment, M.prev_comment, "Ultraplan: previous comment")
  set_map(bufnr, km.next_heading, M.next_heading, "Ultraplan: next heading")
  set_map(bufnr, km.prev_heading, M.prev_heading, "Ultraplan: previous heading")
  set_map(bufnr, km.submit, M.submit, "Ultraplan: submit")
  set_map(bufnr, km.cancel, M.cancel, "Ultraplan: cancel")
end

return M
