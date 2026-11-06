---scope.nvim: the per-tab buffer lists of the old workspace are dropped.
---@type GitWorktreeParticipant|{ available: fun(): boolean, requires: string }
local M = { name = "scope", requires = "scope.nvim" }

function M.available()
  return (pcall(require, "scope.core"))
end

function M.cleanup()
  local core = require("scope.core")
  core.cache = {}
  core.last_tab = vim.api.nvim_get_current_tabpage()
  vim.g.ScopeState = nil
end

return M
