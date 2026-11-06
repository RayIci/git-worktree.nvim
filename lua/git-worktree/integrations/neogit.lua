---Neogit: its floating status buffer is closed before an action, and its
---repository is refreshed after a worktree is created or removed and rebound
---to the new checkout after a switch, so Neogit always shows the active one.
---Neogit does none of the git work. This file is the only place that touches
---Neogit's internals.
---@type GitWorktreeParticipant|{ available: fun(): boolean, requires: string }
local M = { name = "neogit", requires = "neogit" }

function M.available()
  return (pcall(require, "neogit"))
end

---@param repo table Neogit repository instance
local function settle(repo)
  if repo._refresh_task and not repo._refresh_task:wait(10000) then
    error("Neogit's repository refresh did not finish; retry the worktree action", 0)
  end
end

---Make `path` Neogit's current repository, after any refresh in flight.
---@param path string
---@return table repo
local function bind(path)
  local repository = require("neogit.lib.git.repository")
  settle(repository.instance())
  local repo = repository.instance(path)
  settle(repo)
  return repo
end

function M.prepare()
  local status = require("neogit.buffers.status")
  if status.is_open() then
    status.instance():close()
    require("git-worktree.async").scheduler()
  end
end

---@param ctx GitWorktreeContext
function M.changed(ctx)
  local refresh = bind(ctx.current):dispatch_refresh()
  if refresh and not refresh:wait(10000) then
    error(
      "Git changed the worktrees, but Neogit's refresh did not finish; inspect the registered worktrees",
      0
    )
  end
end

---@param info GitWorktreeRestoreInfo
function M.restore(info)
  bind(info.checkout)
end

return M
