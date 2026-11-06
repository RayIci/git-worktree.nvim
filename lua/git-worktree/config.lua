---Merged options. `setup()` writes here once; everything else reads.
---@class GitWorktreeConfig
local M = {}

---@class GitWorktreeOpts
---@field integrations string[] integration modules to enable, in order
---@field destination? fun(ctx: GitWorktreeContext, branch: string): string default destination for a new worktree

---@type GitWorktreeOpts
local defaults = {
  integrations = {},
  destination = nil,
}

---@type GitWorktreeOpts
M.options = vim.deepcopy(defaults)

---@param opts? GitWorktreeOpts
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

return M
