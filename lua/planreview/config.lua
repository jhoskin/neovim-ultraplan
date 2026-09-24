local M = {}

-- Every keymap value may be a string, a list of strings, or false (unbound).
-- `comment_range` is bound in visual mode only; everything else in normal
-- mode. `confirm_comment` is bound inside the comment float (normal and
-- insert mode).
M.defaults = {
  keymaps = {
    comment_line = "<leader>Pr",
    comment_range = "<leader>Pr",
    comment_section = "<leader>PS",
    comment_plan = "<leader>PR",
    delete_comment = "<leader>Pd",
    next_comment = "]c",
    prev_comment = "[c",
    next_heading = "]]",
    prev_heading = "[[",
    submit = "<leader>Ps",
    cancel = "<leader>Pq",
    confirm_comment = "<C-s>",
  },
  highlights = {
    span = { link = "CursorLine" },
    comment = { link = "Comment" },
    sign = { link = "DiagnosticInfo" },
    note = { link = "Comment" },
  },
  sign_text = "●",
  -- Quoted plan text stored with a comment is capped so the feedback Claude
  -- reads stays short. Section comments carry the heading and no text.
  text_cap = { lines = 12, bytes = 1500 },
}

M.values = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  M._define_highlights()
end

function M._define_highlights()
  local h = M.values.highlights
  local function set(name, spec)
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", { default = true }, spec or {}))
  end
  set("PlanReviewSpan", h.span)
  set("PlanReviewComment", h.comment)
  set("PlanReviewSign", h.sign)
  set("PlanReviewNote", h.note)
end

return M
