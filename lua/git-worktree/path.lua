---Where a new worktree goes: `<main-checkout>.worktrees/<branch>` by default,
---or an override that is resolved and validated before anything is created.
---@class GitWorktreePath
local M = {}

local config = require("git-worktree.config")
local git = require("git-worktree.git")

---The suggested destination for `branch`.
---@param ctx GitWorktreeContext
---@param branch string
---@return string
function M.default(ctx, branch)
  git.check_branch_name(ctx.cwd, branch)
  local custom = config.options.destination
  if custom then
    return vim.fs.normalize(custom(ctx, branch))
  end
  return ctx.main .. ".worktrees/" .. branch
end

---Resolve and validate a destination. Relative paths resolve against the main
---checkout and `~` expands; empty input and anything that already exists
---(including a dangling symlink) are rejected.
---@param ctx GitWorktreeContext
---@param branch string
---@param override? string the user's edited destination
---@return string
function M.resolve(ctx, branch, override)
  local default = M.default(ctx, branch)
  local path = override or default
  if path == "" then
    error("The worktree destination cannot be empty", 0)
  end
  if path == "~" or path:sub(1, 2) == "~/" then
    path = vim.fn.expand("~") .. path:sub(2)
  end
  if not vim.startswith(path, "/") then
    path = vim.fs.joinpath(ctx.main, path)
  end
  path = vim.fs.normalize(path)
  if vim.uv.fs_lstat(path) then
    error("Destination already exists: " .. path, 0)
  end
  return path
end

return M
