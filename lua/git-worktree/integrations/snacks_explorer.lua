---snacks.nvim explorer: every open explorer is closed and its expanded folders
---are forgotten before the old workspace's buffers go, so nothing of the old
---tree shows in the destination (whose own explorer state, if any, is the
---host's to restore).
---@type GitWorktreeParticipant|{ available: fun(): boolean, requires: string }
local M = { name = "snacks_explorer", requires = "snacks.nvim" }

function M.available()
  return (pcall(require, "snacks")) and (pcall(require, "snacks.explorer.tree"))
end

function M.reset()
  local snacks = rawget(_G, "Snacks")
  if snacks and package.loaded["snacks.picker"] then
    for _, picker in ipairs(snacks.picker.get({ source = "explorer", tab = false })) do
      -- Closing while its finder still runs makes snacks index the closed
      -- picker's matcher; let a running scan finish first (bounded).
      vim.wait(1000, function()
        return not picker.finder:running()
      end, 10)
      picker:close()
    end
  end
  local tree = require("snacks.explorer.tree")
  for _, node in pairs(tree.nodes) do
    node.open = false
  end
end

return M
