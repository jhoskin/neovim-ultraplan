-- Minimal init.lua for testing ultraplan in isolation.
--
-- Usage:
--   nvim -u tests/minimal_init.lua -c 'Ultraplan path/to/plan.md'
--   nvim -u tests/minimal_init.lua -c 'checkhealth ultraplan'

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

vim.opt.runtimepath:prepend(root)

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.g.mapleader = " "

require("ultraplan").setup({})

if not vim.g.ultraplan_silent then
  print("ultraplan loaded. Try :Ultraplan <plan.md> or :checkhealth ultraplan")
end
