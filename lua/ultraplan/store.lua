-- The in-memory comment store for one plan review: an optional whole-plan
-- note plus anchored comments keyed by their start line. A second comment
-- on the same start line replaces the first.

local Store = {}
Store.__index = Store

function Store.new()
  return setmetatable({
    note = nil,
    comments = {}, -- [lineno] = record
  }, Store)
end

-- Set (or clear, with an empty body) the whole-plan note.
function Store:set_note(body)
  body = vim.trim(body or "")
  if body == "" then
    self.note = nil
    return false
  end
  self.note = body
  return true
end

function Store:clear_note()
  self.note = nil
end

-- Add an anchored comment. `record` is
--   { kind = "line"|"range"|"section", lineno, end_lineno?, heading?, text?, body }
-- `end_lineno` defaults to `lineno`. Returns false (and stores nothing) when
-- the body is blank or the anchor is invalid.
function Store:add(record)
  local body = vim.trim(record.body or "")
  if body == "" then
    return false
  end
  local lineno = tonumber(record.lineno)
  if not lineno or lineno < 1 then
    return false
  end
  local end_lineno = tonumber(record.end_lineno) or lineno
  if end_lineno < lineno then
    end_lineno = lineno
  end
  self.comments[lineno] = {
    kind = record.kind or "line",
    lineno = lineno,
    end_lineno = end_lineno,
    heading = record.heading,
    text = record.text,
    body = body,
  }
  return true
end

function Store:get(lineno)
  return self.comments[lineno]
end

function Store:delete(lineno)
  if not self.comments[lineno] then
    return false
  end
  self.comments[lineno] = nil
  return true
end

-- All anchored comments, sorted by start line.
function Store:all()
  local out = {}
  for _, c in pairs(self.comments) do
    out[#out + 1] = c
  end
  table.sort(out, function(a, b)
    return a.lineno < b.lineno
  end)
  return out
end

-- Number of anchored comments plus one for a whole-plan note.
function Store:count()
  local n = 0
  for _ in pairs(self.comments) do
    n = n + 1
  end
  if self.note then
    n = n + 1
  end
  return n
end

function Store:is_empty()
  return self:count() == 0
end

return Store
