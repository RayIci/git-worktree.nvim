---auto-session as the session backend: the outgoing session is saved
---explicitly (even with exit autosave off, which is left as it was), and the
---destination's session is restored with restore errors turned into failures.
---@type GitWorktreeParticipant|{ available: fun(): boolean, requires: string }
local M = { name = "auto_session", requires = "auto-session" }

function M.available()
  return (pcall(require, "auto-session"))
end

---@type boolean?
local held

---Restore a session with auto-session's error handling switched to raising,
---so a broken session file is reported instead of half-applied.
---@param file? string
---@return boolean
local function restore(file)
  local session = require("auto-session")
  local config = require("auto-session.config")
  local handler, continue_on_error = config.restore_error_handler, config.continue_restore_on_error
  config.continue_restore_on_error = false
  config.restore_error_handler = function(message)
    error("Session restore failed: " .. message, 0)
  end
  local ok, result = pcall(function()
    if file then
      return session.restore_session_file(file, { show_message = false })
    end
    return session.restore_session(nil, { show_message = false })
  end)
  config.restore_error_handler = handler
  config.continue_restore_on_error = continue_on_error
  if not ok then
    error(tostring(result), 0)
  end
  return result
end

---@type GitWorktreeSessionBackend
M.session = {
  hold = function()
    local config = require("auto-session.config")
    held = config.auto_save
    config.auto_save = false
  end,
  release = function()
    require("auto-session.config").auto_save = held
  end,
  stop = function()
    require("auto-session.config").auto_save = false
  end,
  save = function(cwd)
    if not require("auto-session").save_session(cwd, { show_message = false }) then
      error("Could not save the outgoing session", 0)
    end
    return vim.v.this_session
  end,
  exists = function()
    local session = require("auto-session")
    session.manually_named_session = false
    return session.session_exists_for_cwd()
  end,
  restore = restore,
}

return M
