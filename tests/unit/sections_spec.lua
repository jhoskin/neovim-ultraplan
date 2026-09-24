-- Covers: TST-PLN-0001 TST-PLN-0002 TST-PLN-0003 TST-PLN-0004
local H = ...
local S = require("ultraplan.sections")

local plan = {
  "# Title", -- 1
  "", -- 2
  "intro", -- 3
  "## A", -- 4
  "a text", -- 5
  "```bash", -- 6
  "# not a heading", -- 7
  "```", -- 8
  "### A.1", -- 9
  "a1 text", -- 10
  "~~~", -- 11
  "## also not a heading", -- 12
  "~~~", -- 13
  "## B", -- 14
  "b text", -- 15
  "#hashtag is not a heading", -- 16
}

H.describe("sections", function()
  H.it("ignores headings inside ``` and ~~~ fences", function()
    local s = S.sections(plan)
    local titles = {}
    for _, x in ipairs(s) do
      titles[#titles + 1] = x.heading
    end
    H.assert.eq(table.concat(titles, "|"), "# Title|## A|### A.1|## B")
  end)

  H.it("ends a section before the next heading of equal or higher level", function()
    local s = S.sections(plan)
    H.assert.eq(s[1].end_lineno, #plan, "title spans the whole plan")
    H.assert.eq(s[2].end_lineno, 13, "## A ends before ## B")
    H.assert.eq(s[3].end_lineno, 13, "### A.1 ends before ## B")
    H.assert.eq(s[4].end_lineno, #plan, "last section runs to EOF")
  end)

  H.it("normalises the heading text and strips closing hashes", function()
    local s = S.sections({ "##   Spaced   ##", "x" })
    H.assert.eq(s[1].heading, "## Spaced")
    H.assert.eq(s[1].title, "Spaced")
  end)

  H.it("section_for picks the innermost section", function()
    local s = S.sections(plan)
    H.assert.eq(S.section_for(s, 10).heading, "### A.1")
    H.assert.eq(S.section_for(s, 5).heading, "## A")
    H.assert.eq(S.section_for(s, 15).heading, "## B")
    H.assert.eq(S.section_for(s, 9).heading, "### A.1", "cursor on the heading itself")
  end)

  H.it("section_for is nil above the first heading", function()
    local s = S.sections({ "preamble", "", "# H", "x" })
    H.assert.is_nil(S.section_for(s, 1))
    H.assert.eq(S.heading_for(s, 4), "# H")
  end)

  H.it("next_heading / prev_heading walk the heading list", function()
    local s = S.sections(plan)
    H.assert.eq(S.next_heading(s, 1).lineno, 4)
    H.assert.eq(S.next_heading(s, 9).lineno, 14)
    H.assert.is_nil(S.next_heading(s, 14))
    H.assert.eq(S.prev_heading(s, 14).lineno, 9)
    H.assert.is_nil(S.prev_heading(s, 1))
  end)
end)

H.describe("covering", function()
  local comments = {
    { lineno = 2, end_lineno = 20, body = "wide" },
    { lineno = 5, end_lineno = 8, body = "narrow" },
    { lineno = 7, end_lineno = 7, body = "point" },
  }

  H.it("returns the narrowest comment covering the line", function()
    H.assert.eq(S.covering(comments, 7).body, "point")
    H.assert.eq(S.covering(comments, 6).body, "narrow")
    H.assert.eq(S.covering(comments, 15).body, "wide")
  end)

  H.it("returns nil when nothing covers the line", function()
    H.assert.is_nil(S.covering(comments, 1))
    H.assert.is_nil(S.covering(comments, 21))
  end)

  H.it("on equal width the later start wins", function()
    local c = { { lineno = 1, end_lineno = 3 }, { lineno = 2, end_lineno = 4 } }
    H.assert.eq(S.covering(c, 3).lineno, 2)
  end)
end)

H.describe("cap_text", function()
  H.it("returns the joined text when under both caps", function()
    H.assert.eq(S.cap_text({ "a", "b" }, 12, 1500), "a\nb")
  end)

  H.it("caps by line count with a trailing ellipsis line", function()
    local lines = {}
    for i = 1, 20 do
      lines[i] = "l" .. i
    end
    local t = S.cap_text(lines, 3, 1500)
    H.assert.eq(t, "l1\nl2\nl3\n" .. S.ELLIPSIS)
  end)

  H.it("caps by bytes without splitting a UTF-8 sequence", function()
    local t = S.cap_text({ "ééééé" }, 12, 5)
    H.assert.eq(t, "éé" .. S.ELLIPSIS)
  end)
end)
