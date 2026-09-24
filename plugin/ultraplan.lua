if vim.g.loaded_ultraplan then
  return
end
vim.g.loaded_ultraplan = true

-- Run fn now from a live session, or after startup when invoked via
-- `nvim -c` (the agent launcher), where the UI is not ready yet. VimEnter
-- still fires mid-startup and window changes made then can be undone by the
-- first screen draw, so defer one more tick.
local function after_enter(fn)
  if vim.v.vim_did_enter == 1 then
    fn()
    return
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.schedule(fn)
    end,
  })
end

vim.api.nvim_create_user_command("Ultraplan", function(opts)
  -- No file completion on purpose: it would expand `%` and friends before
  -- we see the argument. init.lua normalises `~` and relative paths.
  local path = opts.args
  after_enter(function()
    require("ultraplan").start(path)
  end)
end, {
  nargs = 1,
  desc = "Review a markdown plan file and leave comments",
})
