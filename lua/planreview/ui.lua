-- Floating windows: the comment editor and the submit summary.

local config = require("planreview.config")

local M = {}

-- Detach every LSP client attached to bufnr and keep later ones off too.
function M._detach_any_lsp(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local clients = (vim.lsp.get_clients or vim.lsp.get_active_clients)({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    pcall(vim.lsp.buf_detach_client, bufnr, client.id)
  end
  vim.api.nvim_create_autocmd("LspAttach", {
    buffer = bufnr,
    callback = function(args)
      pcall(vim.lsp.buf_detach_client, bufnr, args.data.client_id)
    end,
  })
end

local function scratch_markdown_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  -- A private filetype so markdown LSPs and linters do not attach to the
  -- transient buffer; syntax highlighting is applied by hand.
  vim.bo[buf].filetype = "planreview-edit"
  M._detach_any_lsp(buf)
  pcall(vim.api.nvim_buf_call, buf, function()
    vim.cmd("setlocal syntax=markdown")
  end)
  M._detach_any_lsp(buf)
  return buf
end

-- opts = { prefill, kind = "line"|"range"|"section"|"plan", label, on_confirm, on_cancel }
-- Confirming with an empty body counts as cancel.
function M.open_comment_float(opts)
  opts = opts or {}
  local prefill = opts.prefill or ""
  local on_confirm = opts.on_confirm
  local on_cancel = opts.on_cancel

  local buf = scratch_markdown_buf()
  if prefill ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(prefill, "\n", { plain = true }))
  end

  local width = math.min(100, math.floor(vim.o.columns * 0.7))
  local height = math.max(6, math.min(15, #vim.split(prefill, "\n") + 3))

  local keys = config.values.keymaps.confirm_comment
  local kind_label = ({
    line = "Line comment",
    range = "Range comment",
    section = "Section comment",
    plan = "Whole-plan note",
  })[opts.kind] or "Comment"
  local title = " " .. kind_label
  if opts.label and opts.label ~= "" then
    local budget = math.max(8, width - #kind_label - 30)
    local label = opts.label
    if #label > budget then
      label = label:sub(1, budget - 1) .. "…"
    end
    title = title .. " " .. label
  end
  title = title .. string.format(" — %s save · q cancel ", tostring(keys))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })

  vim.cmd("startinsert!")

  local finished = false

  local function close()
    finished = true
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local function confirm()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = vim.trim(table.concat(lines, "\n"))
    close()
    if text == "" then
      if on_cancel then
        on_cancel()
      end
      return
    end
    if on_confirm then
      on_confirm(text)
    end
  end

  local function cancel()
    close()
    if on_cancel then
      on_cancel()
    end
  end

  if keys then
    local list = type(keys) == "table" and keys or { keys }
    for _, k in ipairs(list) do
      vim.keymap.set({ "n", "i" }, k, confirm, {
        buffer = buf, nowait = true, desc = "PlanReview: confirm comment",
      })
    end
  end
  vim.keymap.set("n", "q", cancel, {
    buffer = buf, nowait = true, desc = "PlanReview: cancel comment",
  })

  -- Any other close (:q, <C-w>c) is a cancel, so nothing leaks.
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if finished then
        return
      end
      finished = true
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
      if on_cancel then
        on_cancel()
      end
    end,
  })
end

-- Read-only preview of the review with <CR> to confirm and q to go back.
function M.open_summary_float(lines, title, on_confirm, on_cancel)
  local buf = scratch_markdown_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.min(100, math.floor(vim.o.columns * 0.8))
  local height = math.max(3, math.min(#lines + 2, math.floor(vim.o.lines * 0.8)))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })
  vim.wo[win].wrap = true

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  vim.keymap.set("n", "<CR>", function()
    close()
    if on_confirm then
      on_confirm()
    end
  end, { buffer = buf, nowait = true, desc = "PlanReview: confirm submit" })

  vim.keymap.set("n", "q", function()
    close()
    if on_cancel then
      on_cancel()
    end
  end, { buffer = buf, nowait = true, desc = "PlanReview: back to the plan" })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })
end

return M
