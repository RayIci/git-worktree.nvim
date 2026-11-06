---neo-tree.nvim: the explorer is closed and its per-tab source state dropped
---before the old workspace's buffers go.
---@type GitWorktreeParticipant|{ available: fun(): boolean, requires: string }
local M = { name = "neotree", requires = "neo-tree.nvim" }

function M.available()
  return (pcall(require, "neo-tree.sources.manager"))
end

function M.reset()
  local manager = require("neo-tree.sources.manager")
  manager.close_all()
  manager.dispose_invalid_tabs()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, source in ipairs({ "filesystem", "buffers", "git_status" }) do
      manager.dispose(source, tab)
    end
  end
end

return M
