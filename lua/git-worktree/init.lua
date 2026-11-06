---git-worktree: create, switch and delete git worktrees, where switching
---replaces the whole editor workspace (buffers, tabs, layout and whatever the
---enabled integrations and registered participants persist).
---
---Git work is plain `git`; other plugins take part only through optional
---integrations (lua/git-worktree/integrations/) or participants registered by
---the host (see lua/git-worktree/switch.lua for the hooks).
---@class GitWorktree
local M = {}

local async = require("git-worktree.async")
local config = require("git-worktree.config")
local git = require("git-worktree.git")
local path = require("git-worktree.path")
local switch = require("git-worktree.switch")

local notify = switch.notify
local busy = false

---Repository context for `cwd` (default: the editor's working directory).
---@param cwd? string
---@return GitWorktreeContext
function M.discover(cwd)
  return git.discover(cwd)
end

---@param ctx GitWorktreeContext
---@return GitWorktreeBranch[]
function M.branches(ctx)
  return git.branches(ctx)
end

---Resolve and validate where a worktree for `branch` goes.
---@param ctx GitWorktreeContext
---@param branch string
---@param override? string
---@return string
function M.destination(ctx, branch, override)
  return path.resolve(ctx, branch, override)
end

---Run `git worktree <args>` from the invoking checkout, then tell participants.
---@param ctx GitWorktreeContext
---@param args string[]
---@param validate? fun() last-moment checks, run right before git
local function mutate(ctx, args, validate)
  switch.check_context(ctx)
  if validate then
    validate()
  end
  git.run(ctx.current, vim.list_extend({ "worktree" }, args))
  switch.each("changed", ctx)
end

---Create a worktree for an existing local branch, a remote branch (tracking
---it, or reusing an existing local counterpart as is), or a new branch at the
---invoking checkout's HEAD. Never fetches.
---@param ctx GitWorktreeContext
---@param choice GitWorktreeBranch
---@param destination string
---@return GitWorktreeTree
function M.create_checkout(ctx, choice, destination)
  switch.check_context(ctx)
  local fresh = git.discover(ctx.cwd)
  destination = path.resolve(fresh, choice.name, destination)
  local local_ref = "refs/heads/" .. choice.name
  for _, tree in ipairs(fresh.trees) do
    if tree.branch == local_ref then
      error("Branch is already checked out at " .. tree.path, 0)
    end
  end
  local args = { "add" }
  local start = choice.name
  local exists = false
  for _, branch in ipairs(git.branches(fresh)) do
    if branch.ref == local_ref then
      exists = true
    end
  end
  if choice.kind == "new" then
    if exists then
      error("Local branch already exists: " .. choice.name, 0)
    end
    vim.list_extend(args, { "-b", choice.name })
    start = ctx.head
  elseif choice.kind == "remote" and not exists then
    vim.list_extend(args, { "--track", "-b", choice.name })
    start = choice.ref
  elseif not exists then
    error("Local branch no longer exists: " .. choice.name, 0)
  end
  vim.list_extend(args, { destination, start })
  mutate(fresh, args)
  local tree = git.registered(git.discover(ctx.cwd), destination)
  vim.api.nvim_exec_autocmds(
    "User",
    { pattern = "GitWorktreeCreated", data = { path = tree.path }, modeline = false }
  )
  return tree
end

---Remove an inactive linked worktree. Refuses the main or active checkout,
---locked worktrees, and any modified, staged, untracked or ignored content;
---never forces and never deletes the branch.
---@param ctx GitWorktreeContext
---@param target string
function M.remove_checkout(ctx, target)
  switch.check_context(ctx)
  local tree = git.registered(git.discover(ctx.cwd), target)
  mutate(ctx, { "remove", tree.path }, function()
    local fresh = git.discover(ctx.cwd)
    tree = git.registered(fresh, target)
    local id = git.identity(tree.path)
    if id == git.identity(fresh.main) or id == git.identity(fresh.current) then
      error("Cannot remove the main or active checkout", 0)
    end
    if tree.locked then
      error("Worktree is locked: " .. tree.path, 0)
    end
    if not git.is_pristine(tree.path) then
      error("Worktree contains modified, untracked, or ignored files: " .. tree.path, 0)
    end
  end)
  vim.api.nvim_exec_autocmds(
    "User",
    { pattern = "GitWorktreeRemoved", data = { path = tree.path }, modeline = false }
  )
end

---@return boolean proceed
function M.preflight()
  return switch.preflight()
end

---@param ctx GitWorktreeContext
---@param target string
---@return boolean switched
function M.switch_to(ctx, target)
  return switch.switch_to(ctx, target)
end

---@param tree GitWorktreeTree
---@return string
local function tree_label(tree)
  return ("%s  %s"):format(tree.branch and tree.branch:gsub("^refs/heads/", "") or "(detached)", tree.path)
end

---@param ctx GitWorktreeContext
local function choose_switch(ctx)
  local tree = async.select(ctx.trees, { prompt = "Switch worktree workspace:", format_item = tree_label })
  if tree then
    M.switch_to(ctx, tree.path)
  end
end

---@param ctx GitWorktreeContext
local function choose_create(ctx)
  local choices = M.branches(ctx)
  table.insert(choices, 1, { name = "Create new branch...", ref = "", kind = "new" })
  local choice = async.select(choices, {
    prompt = "Branch for new worktree:",
    format_item = function(branch)
      return branch.kind == "remote" and branch.ref:gsub("^refs/remotes/", "") .. " (remote)" or branch.name
    end,
  })
  if not choice then
    return
  end
  if choice.kind == "new" then
    local name = async.input({ prompt = "New branch name: " })
    if name == nil then
      return
    end
    choice.name = name
  end
  local default = path.default(ctx, choice.name)
  local destination =
    async.input({ prompt = "Worktree destination: ", default = default, completion = "dir" })
  if destination == nil then
    return
  end
  destination = M.destination(ctx, choice.name, destination)
  switch.check_context(ctx)
  if not M.preflight() then
    return
  end
  local tree = M.create_checkout(ctx, choice, destination)
  local ok, switched = pcall(M.switch_to, ctx, tree.path)
  if not ok or not switched then
    notify("Created worktree, but did not open it: " .. tree.path, vim.log.levels.WARN)
    if not ok then
      error(switched, 0)
    end
  end
end

---@param ctx GitWorktreeContext
local function choose_delete(ctx)
  local tree = async.select(ctx.trees, { prompt = "Delete inactive worktree:", format_item = tree_label })
  if not tree then
    return
  end
  local answer = async.select({ "Cancel", "Delete" }, { prompt = "Remove " .. tree_label(tree) .. "?" })
  if answer == "Delete" then
    M.remove_checkout(ctx, tree.path)
    notify("Removed worktree: " .. tree.path)
  end
end

---Run one managed action at a time, as a coroutine; errors are reported.
---@param fn fun(ctx: GitWorktreeContext)
local function action(fn)
  if busy then
    notify("A worktree action is already in progress", vim.log.levels.WARN)
    return
  end
  busy = true
  async.run(function()
    local ok, err = xpcall(function()
      switch.each("prepare")
      fn(M.discover())
    end, debug.traceback)
    busy = false
    if not ok then
      notify(tostring(err), vim.log.levels.ERROR)
    end
  end)
end

---Pick a branch and destination, create the worktree and switch to it.
function M.create()
  action(choose_create)
end

---Pick a registered checkout and switch the workspace to it.
function M.switch()
  action(choose_switch)
end

---Pick an inactive worktree and remove it after confirmation.
function M.delete()
  action(choose_delete)
end

---Pick switch, create or delete.
function M.menu()
  action(function(ctx)
    local choice = async.select({ "Switch workspace", "Create worktree", "Delete worktree" }, {
      prompt = "Worktrees:",
    })
    if choice == "Switch workspace" then
      choose_switch(ctx)
    elseif choice == "Create worktree" then
      choose_create(ctx)
    elseif choice == "Delete worktree" then
      choose_delete(ctx)
    end
  end)
end

---Add a participant to every switch (see lua/git-worktree/switch.lua).
---@param participant GitWorktreeParticipant
function M.register(participant)
  switch.register(participant)
end

---@param name string
function M.unregister(name)
  switch.unregister(name)
end

---@param opts? GitWorktreeOpts
function M.setup(opts)
  config.setup(opts)
  for _, name in ipairs(config.options.integrations) do
    local ok, integration = pcall(require, "git-worktree.integrations." .. name)
    if not ok then
      notify(("unknown integration %q"):format(name), vim.log.levels.ERROR)
    elseif integration.available and not integration.available() then
      notify(
        ("%s integration skipped: %s is not installed"):format(name, integration.requires),
        vim.log.levels.WARN
      )
    else
      switch.register(integration)
    end
  end
end

return M
