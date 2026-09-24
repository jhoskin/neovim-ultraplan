-- Minimal init.lua for testing plan-review in isolation.
--
-- Usage:
--   nvim -u tests/minimal_init.lua -c 'PlanReview path/to/plan.md'
--   nvim -u tests/minimal_init.lua -c 'checkhealth planreview'

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

vim.opt.runtimepath:prepend(root)

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.g.mapleader = " "

require("planreview").setup({})

if not vim.g.planreview_silent then
  print("plan-review loaded. Try :PlanReview <plan.md> or :checkhealth planreview")
end
