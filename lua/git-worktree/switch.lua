---The workspace switch transaction and the participants that take part in it.
---
---A participant is a table with a `name` and any of these optional hooks:
---  prepare()        before an action reads the repository (in its coroutine)
---  check()          raise to refuse leaving the current workspace
---  pause()          stop automatic writes and drop pending ones
---  flush()          write outgoing state now; raising aborts before teardown
---  reset()          clear plugin UI/state before buffers are deleted
---  cleanup()        clear what remains after buffers are deleted
---  restore(info)    re-apply state for info.path (info.checkout is its top level)
---  resume()         automatic writes may start again
---  changed(ctx)     a worktree was created or removed from ctx
---  session          optional session backend (see GitWorktreeSessionBackend)
---@class GitWorktreeSwitch
local M = {}

local git = require("git-worktree.git")

---@class GitWorktreeRestoreInfo
---@field path string directory that just became the working directory
---@field checkout string top level of that checkout
---@field managed boolean always true: restored by a switch, synchronously

---@class GitWorktreeSessionBackend
---@field hold fun() suspend automatic session saving for the transition
---@field release fun() restore the automatic-saving preference
---@field stop fun() keep automatic saving off (unrecoverable failure)
---@field save fun(cwd: string): string save the outgoing session, return its file; raise on failure
---@field exists fun(): boolean whether the current directory has a saved session
---@field restore fun(file?: string): boolean restore the cwd's session (or `file`); raise on failure

---@class GitWorktreeParticipant
---@field name string
---@field prepare? fun()
---@field check? fun()
---@field pause? fun()
---@field flush? fun()
---@field reset? fun()
---@field cleanup? fun()
---@field restore? fun(info: GitWorktreeRestoreInfo)
---@field resume? fun()
---@field changed? fun(ctx: GitWorktreeContext)
---@field session? GitWorktreeSessionBackend

---@type GitWorktreeParticipant[]
M.participants = {}

---Add a participant, replacing one with the same name.
---@param participant GitWorktreeParticipant
function M.register(participant)
  assert(type(participant) == "table" and type(participant.name) == "string", "participant needs a name")
  M.unregister(participant.name)
  M.participants[#M.participants + 1] = participant
end

---@param name string
function M.unregister(name)
  for i, p in ipairs(M.participants) do
    if p.name == name then
      table.remove(M.participants, i)
      return
    end
  end
end

---Run one hook on every participant, in registration order.
---@param hook string
---@param ... any
function M.each(hook, ...)
  for _, participant in ipairs(M.participants) do
    local fn = participant[hook]
    if fn then
      fn(...)
    end
  end
end

---@return GitWorktreeSessionBackend?
local function backend()
  for _, participant in ipairs(M.participants) do
    if participant.session then
      return participant.session
    end
  end
end

---@param message string
---@param level? integer
function M.notify(message, level)
  vim.notify("Worktrees: " .. message, level or vim.log.levels.INFO)
end

---@param pattern string
---@param data table
local function event(pattern, data)
  vim.api.nvim_exec_autocmds("User", { pattern = pattern, data = data, modeline = false })
end

---Raise when the working directory moved since the action started.
---@param ctx GitWorktreeContext
function M.check_context(ctx)
  if git.identity(vim.fn.getcwd()) ~= git.identity(ctx.cwd) then
    error("Working directory changed during the action; select the worktree again", 0)
  end
end

---Refuse to leave the workspace while it holds something a switch would
---discard: participants' checks (e.g. a debug session), live terminal jobs,
---and unsaved buffers unless the user saves them all.
---@return boolean proceed false when the user cancelled
function M.preflight()
  M.each("check")
  local modified = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "terminal" then
      local job = vim.b[buf].terminal_job_id
      if job and vim.fn.jobwait({ job }, 0)[1] == -1 then
        error("Close the live terminal before switching: " .. vim.api.nvim_buf_get_name(buf), 0)
      end
    elseif vim.bo[buf].modified then
      modified[#modified + 1] = buf
    end
  end
  if #modified == 0 then
    return true
  end
  if vim.fn.confirm("Workspace has unsaved edits", "&Save all and switch\n&Cancel", 2) ~= 1 then
    return false
  end
  for _, buf in ipairs(modified) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name == "" then
      error("Save the unnamed modified buffer before switching workspaces", 0)
    end
    local written, err = pcall(vim.api.nvim_buf_call, buf, function()
      vim.cmd.write()
    end)
    if not written then
      error(("Could not save %s: %s"):format(name, tostring(err)), 0)
    end
    if vim.bo[buf].modified then
      error("Buffer still has unsaved edits: " .. name, 0)
    end
  end
  return true
end

---Leave one clean buffer in one window, with participants cleared.
local function reset_editor()
  local buffers = vim.api.nvim_list_bufs()
  local blank = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(blank)
  M.each("reset")
  vim.cmd("silent tabonly")
  vim.cmd("silent only")
  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, {})
    end
  end
  M.each("cleanup")
  vim.v.this_session = ""
end

---Replace the whole workspace with the one saved for `path`.
---@param ctx GitWorktreeContext
---@param path string a registered checkout
---@return boolean switched false when the user cancelled
function M.switch_to(ctx, path)
  M.check_context(ctx)
  local fresh = git.discover(ctx.cwd)
  local target = git.registered(fresh, path)
  if git.identity(target.path) == git.identity(fresh.current) then
    return true
  end
  if not M.preflight() then
    return false
  end
  M.check_context(ctx)

  local session = backend()
  local source = vim.fn.getcwd()
  local source_session = ""
  local changed = false
  event("GitWorktreeSwitchPre", { from = source, to = target.path })
  M.each("pause")
  if session then
    session.hold()
  end
  local ok, err = pcall(function()
    M.each("flush")
    if session then
      source_session = session.save(source)
    end
    changed = true
    reset_editor()
    vim.api.nvim_set_current_dir(target.path)
    if session and session.exists() then
      local restored, result = pcall(session.restore)
      if not restored or not result then
        error("Could not restore the destination session: " .. target.path .. "\n" .. tostring(result), 0)
      end
    end
    M.each("restore", { path = target.path, checkout = target.path, managed = true })
    vim.cmd.clearjumps()
  end)
  if not ok and changed then
    local recovered, recovery_error = pcall(function()
      M.each("pause")
      reset_editor()
      vim.api.nvim_set_current_dir(source)
      if session and (source_session == "" or not session.restore(source_session)) then
        error("Could not restore source session: " .. source_session, 0)
      end
      M.each("restore", { path = source, checkout = fresh.current, managed = true })
    end)
    if not recovered then
      if session then
        session.stop()
      end
      error(
        ("%s\nRecovery failed: %s\nAutomatic writes stopped. Current cwd: %s\nSource session: %s"):format(
          tostring(err),
          tostring(recovery_error),
          vim.fn.getcwd(),
          source_session
        ),
        0
      )
    end
  end
  if session then
    session.release()
  end
  M.each("resume")
  if not ok then
    error(tostring(err), 0)
  end
  event("GitWorktreeSwitched", { from = source, path = target.path })
  M.notify("Opened workspace: " .. target.path)
  return true
end

return M
