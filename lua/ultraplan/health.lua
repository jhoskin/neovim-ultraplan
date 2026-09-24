local M = {}

function M.check()
  local health = vim.health
  health.start("ultraplan")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim >= 0.10 is required")
  end

  local ok = pcall(vim.treesitter.language.inspect, "markdown")
  if ok then
    health.ok("treesitter markdown parser found")
  else
    health.warn("treesitter markdown parser not found; the plan shows without highlighting")
  end

  for _, tool in ipairs({ "zmx", "kitten", "jq" }) do
    if vim.fn.executable(tool) == 1 then
      health.ok(tool .. " on PATH")
    else
      health.warn(tool .. " not on PATH (needed by the launcher and the Claude Code hook, not by :Ultraplan itself)")
    end
  end

  local env = vim.env.NVIM_ULTRAPLAN_RESULT
  if env and env ~= "" then
    health.info("agent mode: results go to " .. env)
  else
    health.info("interactive mode (NVIM_ULTRAPLAN_RESULT unset)")
  end
end

return M
