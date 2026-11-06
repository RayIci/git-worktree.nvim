---nvim-dap: a switch is refused while a debug session runs (it is never
---stopped or retargeted), and breakpoints are cleared with the old workspace.
---@type GitWorktreeParticipant|{ available: fun(): boolean, requires: string }
local M = { name = "dap", requires = "nvim-dap" }

function M.available()
  return (pcall(require, "dap"))
end

function M.check()
  local dap = package.loaded.dap
  if dap and next(dap.sessions()) then
    error("Stop active debugging sessions before switching workspaces", 0)
  end
end

function M.cleanup()
  require("dap.breakpoints").clear()
end

return M
