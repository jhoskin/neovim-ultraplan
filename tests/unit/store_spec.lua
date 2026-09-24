-- Covers: TST-PLN-0005
local H = ...
local Store = require("ultraplan.store")

H.describe("store", function()
  H.it("starts empty", function()
    local s = Store.new()
    H.assert.ok(s:is_empty())
    H.assert.eq(s:count(), 0)
    H.assert.is_nil(s.note)
  end)

  H.it("rejects blank bodies and bad anchors", function()
    local s = Store.new()
    H.assert.eq(s:add({ lineno = 3, body = "   " }), false)
    H.assert.eq(s:add({ lineno = 0, body = "x" }), false)
    H.assert.eq(s:set_note("  "), false)
    H.assert.ok(s:is_empty())
  end)

  H.it("stores, trims, and defaults end_lineno to lineno", function()
    local s = Store.new()
    H.assert.ok(s:add({ kind = "line", lineno = 3, body = "  hi  " }))
    local c = s:get(3)
    H.assert.eq(c.body, "hi")
    H.assert.eq(c.end_lineno, 3)
    H.assert.eq(c.kind, "line")
  end)

  H.it("replaces a comment on the same start line", function()
    local s = Store.new()
    s:add({ lineno = 3, body = "first" })
    s:add({ lineno = 3, end_lineno = 6, kind = "range", body = "second" })
    H.assert.eq(s:count(), 1)
    H.assert.eq(s:get(3).body, "second")
    H.assert.eq(s:get(3).end_lineno, 6)
  end)

  H.it("all() sorts by start line", function()
    local s = Store.new()
    s:add({ lineno = 9, body = "c" })
    s:add({ lineno = 2, body = "a" })
    s:add({ lineno = 5, body = "b" })
    local order = {}
    for _, c in ipairs(s:all()) do
      order[#order + 1] = c.body
    end
    H.assert.eq(table.concat(order), "abc")
  end)

  H.it("delete removes exactly one comment", function()
    local s = Store.new()
    s:add({ lineno = 2, body = "a" })
    s:add({ lineno = 5, body = "b" })
    H.assert.ok(s:delete(2))
    H.assert.eq(s:delete(2), false)
    H.assert.eq(s:count(), 1)
    H.assert.eq(s:all()[1].lineno, 5)
  end)

  H.it("the note counts as one comment and can be cleared", function()
    local s = Store.new()
    H.assert.ok(s:set_note("overall"))
    H.assert.eq(s:count(), 1)
    s:clear_note()
    H.assert.ok(s:is_empty())
  end)
end)
