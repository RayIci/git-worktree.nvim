---bufferline.nvim: pins of the old workspace are dropped.
---@type GitWorktreeParticipant|{ available: fun(): boolean, requires: string }
local M = { name = "bufferline", requires = "bufferline.nvim" }

function M.available()
  return (pcall(require, "bufferline.groups"))
end

function M.reset()
  local groups = require("bufferline.groups")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    groups.remove_id_from_manual_groupings(buf)
  end
  vim.g.BufferlinePinnedBuffers = ""
end

function M.cleanup()
  vim.g.BufferlinePinnedBuffers = ""
end

return M
