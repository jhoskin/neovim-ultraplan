-- Render a serialized review as markdown. This is the text Claude reads as
-- the ExitPlanMode denial reason, and what the summary float previews, so
-- there is exactly one formatter.

local M = {}

local function is_set(v)
  return v ~= nil and v ~= vim.NIL and v ~= ""
end

local function blockquote(text)
  local out = {}
  for _, l in ipairs(vim.split(text, "\n", { plain = true })) do
    out[#out + 1] = "> " .. l
  end
  return out
end

-- `data` is the table from result.serialize (nullable fields may be vim.NIL).
function M.to_markdown(data)
  local lines = {}
  local function add(s)
    lines[#lines + 1] = s
  end

  local name = vim.fn.fnamemodify(data.plan.path, ":t")
  local comments = data.comments or {}

  add("# Plan review: " .. name)
  add("")
  if not is_set(data.note) and #comments == 0 then
    add("The user read this plan in Neovim and left no comments. The plan is")
    add("approved as written.")
    return table.concat(lines, "\n")
  end

  add("The user read this plan in Neovim and left the comments below. They")
  add(string.format("are anchored to the plan as it was when reviewed (%s, %d lines,",
    data.plan.path, data.plan.line_count or 0))
  add(string.format("sha256 %s):", tostring(data.plan.sha256):sub(1, 12)))
  add("")
  add("- `L12` is one line of the plan and `L12-15` a range of lines. The")
  add("  heading in parentheses is the section those lines belong to, or the")
  add("  heading the range contains.")
  add("- A section comment covers everything under that heading.")
  add("- The quoted text is the plan text at those lines; long quotes are cut")
  add("  short with " .. "…" .. ".")
  add("- A whole-plan note applies to the plan as a whole.")
  add("")

  if is_set(data.note) then
    add("## Whole plan")
    add("")
    add(data.note)
    add("")
  end

  for _, c in ipairs(comments) do
    local where
    if c.end_lineno and c.end_lineno ~= c.lineno then
      where = string.format("L%d-%d", c.lineno, c.end_lineno)
    else
      where = string.format("L%d", c.lineno)
    end
    local label = where
    if c.kind == "section" and is_set(c.heading) then
      label = string.format("%s, section %s", where, c.heading)
    elseif is_set(c.heading) then
      label = string.format("%s (%s)", where, c.heading)
    end
    add("## " .. label)
    add("")
    if is_set(c.text) then
      for _, q in ipairs(blockquote(c.text)) do
        add(q)
      end
      add("")
    end
    add(c.body)
    add("")
  end

  -- Drop the trailing blank line.
  while #lines > 0 and lines[#lines] == "" do
    lines[#lines] = nil
  end
  return table.concat(lines, "\n")
end

function M.to_clipboard(data)
  local text = M.to_markdown(data)
  pcall(vim.fn.setreg, "+", text)
  return text
end

return M
