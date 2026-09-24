-- The plan view: one tab, one read-only scratch buffer holding the plan,
-- comment markers painted as extmarks, and cursor helpers the actions in
-- init.lua build on.

local config = require("ultraplan.config")
local sections = require("ultraplan.sections")

local M = {}

M.NS = vim.api.nvim_create_namespace("ultraplan")

local state = {
  tab = nil,
  win = nil,
  buf = nil,
  path = nil,
  lines = nil,
  sections = nil,
  store = nil,
}

local function buf_valid()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

-- Open the plan in a new tab. `plan_info` is { path, lines }; `opts.keymaps`
-- is a function called with the buffer so the caller can bind its actions.
function M.open(plan_info, store, opts)
  opts = opts or {}

  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()
  local win = vim.api.nvim_get_current_win()
  local placeholder = vim.api.nvim_get_current_buf()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "ultraplan://" .. vim.fn.fnamemodify(plan_info.path, ":t"))
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, plan_info.lines)
  vim.bo[buf].modifiable = false
  -- A private filetype keeps markdown LSPs and linters off the scratch
  -- buffer; treesitter is started by hand for highlighting.
  vim.bo[buf].filetype = "ultraplan"

  vim.api.nvim_win_set_buf(win, buf)
  -- The empty buffer tabnew created is no longer shown; drop it so it does
  -- not linger in the buffer list.
  if vim.api.nvim_buf_is_valid(placeholder)
    and vim.api.nvim_buf_get_name(placeholder) == ""
    and not vim.bo[placeholder].modified then
    pcall(vim.api.nvim_buf_delete, placeholder, { force = true })
  end

  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = true
  vim.wo[win].breakindent = true
  vim.wo[win].linebreak = true
  vim.wo[win].signcolumn = "yes"
  vim.wo[win].cursorline = true
  vim.wo[win].foldenable = false
  vim.wo[win].spell = false
  pcall(function()
    vim.wo[win].winfixbuf = true
  end)

  pcall(vim.treesitter.start, buf, "markdown")

  state.tab = tab
  state.win = win
  state.buf = buf
  state.path = plan_info.path
  state.lines = plan_info.lines
  state.sections = sections.sections(plan_info.lines)
  state.store = store

  if type(opts.keymaps) == "function" then
    opts.keymaps(buf)
  end

  M.repaint()
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

function M.close()
  if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
    local ok = pcall(function()
      vim.api.nvim_set_current_tabpage(state.tab)
      vim.cmd("tabclose")
    end)
    if not ok and buf_valid() then
      pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
    end
  elseif buf_valid() then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state = { tab = nil, win = nil, buf = nil, path = nil, lines = nil, sections = nil, store = nil }
end

function M.is_open()
  return buf_valid()
end

function M.buf()
  return state.buf
end

function M.win()
  return state.win
end

function M.sections()
  return state.sections or {}
end

function M.lines()
  return state.lines or {}
end

-- Lines lineno..end_lineno of the plan (1-based, inclusive).
function M.slice(lineno, end_lineno)
  local out = {}
  for i = lineno, end_lineno do
    out[#out + 1] = state.lines[i]
  end
  return out
end

-- The cursor line when the cursor is in the plan window, else nil.
function M.cursor_line()
  if not buf_valid() then
    return nil
  end
  if vim.api.nvim_get_current_buf() ~= state.buf then
    return nil
  end
  return vim.api.nvim_win_get_cursor(0)[1]
end

-- Called from a visual-mode mapping: the selected line range, sorted, after
-- which visual mode is left so a float can open cleanly.
function M.visual_range()
  local a = vim.fn.getpos("v")[2]
  local b = vim.fn.getpos(".")[2]
  if a > b then
    a, b = b, a
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  return a, b
end

function M.section_at_cursor()
  local ln = M.cursor_line()
  if not ln then
    return nil
  end
  return sections.section_for(state.sections, ln)
end

function M.comment_at_cursor()
  local ln = M.cursor_line()
  if not ln or not state.store then
    return nil
  end
  return sections.covering(state.store:all(), ln)
end

local function jump_to(lineno)
  if not lineno or not buf_valid() then
    return false
  end
  local max = vim.api.nvim_buf_line_count(state.buf)
  lineno = math.max(1, math.min(lineno, max))
  vim.api.nvim_win_set_cursor(state.win, { lineno, 0 })
  return true
end

function M.next_comment()
  local ln = M.cursor_line()
  if not ln then
    return false
  end
  for _, c in ipairs(state.store:all()) do
    if c.lineno > ln then
      return jump_to(c.lineno)
    end
  end
  return false
end

function M.prev_comment()
  local ln = M.cursor_line()
  if not ln then
    return false
  end
  local found = nil
  for _, c in ipairs(state.store:all()) do
    if c.lineno < ln then
      found = c.lineno
    end
  end
  return jump_to(found)
end

function M.next_heading()
  local ln = M.cursor_line()
  if not ln then
    return false
  end
  local s = sections.next_heading(state.sections, ln)
  return jump_to(s and s.lineno)
end

function M.prev_heading()
  local ln = M.cursor_line()
  if not ln then
    return false
  end
  local s = sections.prev_heading(state.sections, ln)
  return jump_to(s and s.lineno)
end

local function virt_block(text, prefix, hl)
  local vl = {}
  for _, l in ipairs(vim.split(text, "\n", { plain = true })) do
    vl[#vl + 1] = { { prefix .. l, hl } }
  end
  return vl
end

-- Clear and redraw every comment marker from the store.
function M.repaint()
  if not buf_valid() or not state.store then
    return
  end
  local buf = state.buf
  local ns = M.NS
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count == 0 then
    return
  end

  -- The whole-plan note hangs below the first line (virtual lines above
  -- line 1 only show once the window scrolls past the top, so they would be
  -- invisible on open). A header line tells it apart from a line comment.
  if state.store.note then
    local vl = { { { "  ┃ whole plan:", "UltraplanSign" } } }
    for _, l in ipairs(virt_block(state.store.note, "  ┃ ", "UltraplanNote")) do
      vl[#vl + 1] = l
    end
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { virt_lines = vl })
  end

  for _, c in ipairs(state.store:all()) do
    local start_row = c.lineno - 1
    if start_row < line_count then
      local last = math.min(c.end_lineno, line_count)
      -- Span tint. end_row is exclusive in 0-based terms, so a 1-based
      -- inclusive end line maps to itself; end_col 0 plus hl_eol tints the
      -- whole last row. Priority stays under treesitter's 100 so syntax
      -- colours show through a background-only group.
      vim.api.nvim_buf_set_extmark(buf, ns, start_row, 0, {
        end_row = last,
        end_col = 0,
        hl_eol = true,
        hl_group = "UltraplanSpan",
        priority = 50,
      })
      vim.api.nvim_buf_set_extmark(buf, ns, start_row, 0, {
        sign_text = config.values.sign_text,
        sign_hl_group = "UltraplanSign",
      })
      -- virt_lines hang below the mark's own row, so the body goes on a
      -- mark at the last row of the span.
      vim.api.nvim_buf_set_extmark(buf, ns, last - 1, 0, {
        virt_lines = virt_block(c.body, "  ┃ ", "UltraplanComment"),
      })
    end
  end
end

return M
