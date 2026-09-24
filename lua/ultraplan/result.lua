-- Serialize a review, save it, and end the Neovim process with the exit
-- code the launcher expects:
--   0  submitted (the audit file path is written to $NVIM_ULTRAPLAN_RESULT)
--   2  cancelled
--   1  error ("ultraplan: <type>: <message>" on stderr)

local export = require("ultraplan.export")

local M = {}

-- Set once an explicit submit/cancel/error exit has run, so the VimLeavePre
-- safety net in init.lua does not turn a storage error (1) into a cancel (2).
M._exit_initiated = false

local function nullable(v)
  if v == nil or v == "" then
    return vim.NIL
  end
  return v
end

-- Build the review document. `plan_info` is
--   { path, lines }   (lines: the plan as displayed, no trailing newline)
-- Nullable fields become vim.NIL here and only here, so the store never
-- holds a sentinel and vim.json.encode emits `null` instead of dropping the
-- key. An empty comment list encodes as `[]`.
function M.serialize(store, plan_info)
  local comments = {}
  for _, c in ipairs(store:all()) do
    comments[#comments + 1] = {
      kind = c.kind,
      lineno = c.lineno,
      end_lineno = c.end_lineno,
      heading = nullable(c.heading),
      text = nullable(c.text),
      body = c.body,
    }
  end

  local data = {
    version = 1,
    id = os.date("!%Y%m%dT%H%M%S"),
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    plan = {
      path = plan_info.path,
      sha256 = vim.fn.sha256(table.concat(plan_info.lines, "\n")),
      line_count = #plan_info.lines,
    },
    note = nullable(store.note),
    comments = comments,
  }
  data.markdown = export.to_markdown(data)
  return data
end

function M.is_approval(data)
  return (data.note == nil or data.note == vim.NIL) and #(data.comments or {}) == 0
end

function M.save_dir()
  return vim.fn.stdpath("data") .. "/ultraplan"
end

-- Write the document as JSON into the audit directory. Returns the path, or
-- nil plus an error message.
function M.save(data, dir)
  dir = dir or M.save_dir()
  -- mkdir raises when a parent is unwritable; io.open below is the real gate.
  pcall(vim.fn.mkdir, dir, "p")

  local filepath = dir .. "/" .. data.id .. ".json"
  local file, err = io.open(filepath, "w")
  if not file then
    return nil, "cannot write review file: " .. (err or "unknown error")
  end
  file:write(vim.json.encode(data))
  file:close()
  return filepath
end

function M.result_file_path()
  local env = vim.env.NVIM_ULTRAPLAN_RESULT
  if env and env ~= "" then
    return env
  end
  return nil
end

function M.agent_mode()
  return M.result_file_path() ~= nil
end

function M.write_result(review_path)
  local result_path = M.result_file_path()
  if not result_path then
    return true
  end
  local file, err = io.open(result_path, "w")
  if not file then
    return false, "cannot write result file: " .. (err or "unknown error")
  end
  file:write(review_path)
  file:close()
  return true
end

function M.exit_submit(review_path)
  M._exit_initiated = true
  local ok, err = M.write_result(review_path)
  if not ok then
    M.exit_error("storage_error", err)
    return
  end
  vim.cmd("quitall!")
end

function M.exit_cancel()
  M._exit_initiated = true
  vim.cmd("cquit 2")
end

function M.exit_error(error_type, message)
  M._exit_initiated = true
  io.stderr:write("ultraplan: " .. error_type .. ": " .. (message or "") .. "\n")
  vim.cmd("cquit 1")
end

return M
