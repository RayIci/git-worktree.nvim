---The integrations against the real plugins, loaded from 'packpath' (as
---installed by vim.pack or any manager using pack/*/opt or pack/*/start).
---Skipped with a notice when one of them is missing.
local H = require("helpers")

local needed = {
  "plenary.nvim",
  "neogit",
  "auto-session",
  "scope.nvim",
  "bufferline.nvim",
  "nvim-dap",
  "neo-tree.nvim",
  "nui.nvim",
  "nvim-web-devicons",
}
local missing = {}
for _, name in ipairs(needed) do
  local path = vim.fn.globpath(vim.o.packpath, "pack/*/*/" .. name, false, true)[1]
  if path then
    vim.opt.rtp:append(path)
  else
    missing[#missing + 1] = name
  end
end
if #missing > 0 then
  io.stdout:write("integration specs skipped, not installed: " .. table.concat(missing, ", ") .. "\n")
  return
end

local sessions = vim.fn.tempname()
vim.o.sessionoptions = "buffers,curdir,folds,globals,help,tabpages,winsize,terminal"
vim.o.swapfile = false
vim.env.AUTOSESSION_UNIT_TESTING = "1"
require("auto-session").setup({
  root_dir = sessions,
  auto_save = true,
  auto_restore = false,
  auto_create = true,
})
require("scope").setup({})
require("bufferline").setup({})
require("neo-tree").setup({ enable_git_status = false })
require("neogit").setup({})
-- What every host does: bufferline keeps wiped buffers in its groupings.
vim.api.nvim_create_autocmd("BufWipeout", {
  callback = function(ev)
    require("bufferline.groups").remove_id_from_manual_groupings(ev.buf)
  end,
})

local ALL = { "auto_session", "neogit", "dap", "scope", "bufferline", "neotree" }

---@return string
local function linked()
  local path = H.repo .. ".worktrees/b"
  H.git(H.repo, "worktree", "add", "-q", "-b", "b", path)
  vim.fn.writefile({ "in b" }, path .. "/b.txt")
  return path
end

---@param path string
local function switch(path)
  local wt = require("git-worktree")
  H.notifications(function()
    assert(wt.switch_to(wt.discover(), path))
  end)
end

local function listed()
  local names = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.api.nvim_buf_get_name(buf) ~= "" then
      names[#names + 1] = vim.fs.basename(vim.api.nvim_buf_get_name(buf))
    end
  end
  table.sort(names)
  return names
end

describe("integrations", function()
  before_each(function()
    vim.fn.delete(sessions, "rf")
    require("git-worktree").setup({ integrations = ALL })
  end)

  it("enables every integration without warnings when the plugins are installed", function()
    eq(
      ALL,
      vim.tbl_map(function(p)
        return p.name
      end, require("git-worktree.switch").participants)
    )
  end)

  it("auto_session saves the outgoing session and restores each checkout's own", function()
    local b = linked()
    vim.cmd.edit("file.txt")
    vim.cmd.vsplit()
    switch(b)
    eq({}, listed(), "a first visit starts clean")
    eq(1, #vim.api.nvim_list_wins())
    vim.cmd.edit("b.txt")
    switch(H.repo)
    eq({ "file.txt" }, listed())
    eq(2, #vim.api.nvim_list_wins(), "the layout came back")
    switch(b)
    eq({ "b.txt" }, listed())
  end)

  it("auto_session keeps the exit-autosave preference", function()
    local b = linked()
    local config = require("auto-session.config")
    config.auto_save = false
    switch(b)
    eq(false, config.auto_save)
    config.auto_save = true
    switch(H.repo)
    eq(true, config.auto_save)
  end)

  it("auto_session reports a broken destination session and recovers the source", function()
    local b = linked()
    vim.cmd.edit("file.txt")
    vim.fn.mkdir(sessions, "p")
    local file = require("auto-session").get_root_dir()
      .. require("auto-session.lib").escape_session_name(b)
      .. ".vim"
    vim.fn.writefile({ "throw 'fixture broken session'" }, file)
    local wt = require("git-worktree")
    H.rejects("destination session", function()
      wt.switch_to(wt.discover(), b)
    end)
    eq(H.repo, vim.fn.getcwd())
    eq({ "file.txt" }, listed())
    eq({ "throw 'fixture broken session'" }, vim.fn.readfile(file), "the broken session is not overwritten")
  end)

  it("bufferline pins and scope's tab lists do not follow into another checkout", function()
    local b = linked()
    vim.cmd.edit("file.txt")
    vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true })
    vim.cmd("BufferLineTogglePin")
    ok(vim.g.BufferlinePinnedBuffers ~= "", "pinned")
    vim.cmd.tabnew()
    switch(b)
    eq("", vim.g.BufferlinePinnedBuffers)
    eq(nil, vim.g.ScopeState)
    local core = require("scope.core")
    local tabs = 0
    for _ in pairs(core.cache) do
      tabs = tabs + 1
    end
    ok(tabs <= 1, "scope tracks only the new workspace's tab")
  end)

  it("neotree closes the explorer of the old workspace", function()
    local b = linked()
    require("neo-tree.command").execute({ action = "show" })
    ok(
      vim.wait(5000, function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
            return true
          end
        end
      end, 10),
      "explorer opened"
    )
    -- let neo-tree finish the render it queued while opening
    vim.wait(500, function() end, 10)
    switch(b)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      ok(vim.bo[buf].filetype ~= "neo-tree", "explorer closed: " .. vim.api.nvim_buf_get_name(buf))
    end
  end)

  it("dap refuses to switch during a debug session and clears breakpoints", function()
    local b = linked()
    local dap = require("dap")
    vim.cmd.edit("file.txt")
    require("dap.breakpoints").set({}, vim.api.nvim_get_current_buf(), 2)
    H.with(dap, "sessions", function()
      return { [1] = {} }
    end, function()
      local wt = require("git-worktree")
      H.rejects("debugging", function()
        wt.switch_to(wt.discover(), b)
      end)
    end)
    eq(H.repo, vim.fn.getcwd())
    switch(b)
    eq({}, require("dap.breakpoints").get())
  end)

  it("neogit is refreshed after creation and follows the active checkout", function()
    local wt = require("git-worktree")
    local ctx = wt.discover()
    local path = wt.destination(ctx, "via-plain-git")
    wt.create_checkout(ctx, { kind = "new", name = "via-plain-git", ref = "" }, path)
    local repository = require("neogit.lib.git.repository")
    switch(path)
    eq(path, repository.instance().worktree_root)
    switch(H.repo)
    eq(H.repo, repository.instance().worktree_root)
  end)
end)
