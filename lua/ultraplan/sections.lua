-- Pure functions over a plan's lines: heading structure, section lookup,
-- comment span lookup, and quoted-text capping. No Neovim UI state, so all
-- of this runs headless in the unit tests.

local M = {}

-- Scan the lines for ATX headings, ignoring anything inside a fenced code
-- block (``` or ~~~), where a leading `#` is a shell comment, not a heading.
-- Returns an ordered list of
--   { lineno, level, title, heading, end_lineno }
-- where `heading` is the normalised "## Title" form and `end_lineno` is the
-- last line of the section: the line before the next heading of equal or
-- higher level, else the last line of the plan.
function M.sections(lines)
  local out = {}
  local fence = nil -- the fence character ("`" or "~") while inside a fence

  for i, line in ipairs(lines) do
    local f = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if f then
      local ch = f:sub(1, 1)
      if fence == nil then
        fence = ch
      elseif ch == fence then
        fence = nil
      end
    elseif fence == nil then
      local hashes, title = line:match("^(#+)%s+(.-)%s*$")
      if hashes and #hashes <= 6 and title ~= "" then
        -- Strip optional closing hashes ("## Title ##").
        title = title:gsub("%s+#+$", "")
        out[#out + 1] = {
          lineno = i,
          level = #hashes,
          title = title,
          heading = hashes .. " " .. title,
        }
      end
    end
  end

  for idx, s in ipairs(out) do
    s.end_lineno = #lines
    for j = idx + 1, #out do
      if out[j].level <= s.level then
        s.end_lineno = out[j].lineno - 1
        break
      end
    end
  end

  return out
end

-- The innermost section containing `lineno`, or nil when the line sits above
-- the first heading. Because sections nest, the innermost one is the section
-- with the latest heading that still covers the line.
function M.section_for(sections, lineno)
  local best = nil
  for _, s in ipairs(sections) do
    if s.lineno <= lineno and lineno <= s.end_lineno then
      if not best or s.lineno > best.lineno then
        best = s
      end
    end
  end
  return best
end

-- The nearest enclosing heading text for a line, or nil.
function M.heading_for(sections, lineno)
  local s = M.section_for(sections, lineno)
  return s and s.heading or nil
end

-- First heading strictly after `lineno`, or nil.
function M.next_heading(sections, lineno)
  for _, s in ipairs(sections) do
    if s.lineno > lineno then
      return s
    end
  end
  return nil
end

-- Last heading strictly before `lineno`, or nil.
function M.prev_heading(sections, lineno)
  local found = nil
  for _, s in ipairs(sections) do
    if s.lineno < lineno then
      found = s
    else
      break
    end
  end
  return found
end

-- The narrowest comment whose span covers `lineno`, or nil. Comments are
-- records with `lineno` and `end_lineno`. On equal width the later start
-- wins, so a nested comment beats the one wrapping it.
function M.covering(comments, lineno)
  local best = nil
  for _, c in ipairs(comments) do
    local last = c.end_lineno or c.lineno
    if c.lineno <= lineno and lineno <= last then
      if not best then
        best = c
      else
        local bw = (best.end_lineno or best.lineno) - best.lineno
        local cw = last - c.lineno
        if cw < bw or (cw == bw and c.lineno > best.lineno) then
          best = c
        end
      end
    end
  end
  return best
end

-- Back off a byte offset so it does not split a UTF-8 sequence.
local function utf8_safe_cut(s, n)
  while n > 0 do
    local b = s:byte(n + 1)
    if not b or b < 0x80 or b > 0xBF then
      break
    end
    n = n - 1
  end
  return n
end

M.ELLIPSIS = "…"

-- Join `lines` for quoting in the review JSON, capped at `max_lines` lines
-- and `max_bytes` bytes so a long selection does not bloat the feedback
-- Claude reads. A cap appends M.ELLIPSIS on its own line (line cap) or
-- inline (byte cap).
function M.cap_text(lines, max_lines, max_bytes)
  max_lines = max_lines or 12
  max_bytes = max_bytes or 1500

  local kept = {}
  local capped = false
  for i, l in ipairs(lines) do
    if i > max_lines then
      capped = true
      break
    end
    kept[#kept + 1] = l
  end

  local text = table.concat(kept, "\n")
  if #text > max_bytes then
    text = text:sub(1, utf8_safe_cut(text, max_bytes))
    return text .. M.ELLIPSIS
  end
  if capped then
    return text .. "\n" .. M.ELLIPSIS
  end
  return text
end

return M
