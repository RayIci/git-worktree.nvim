---Git plumbing: repository discovery and the worktree/branch commands, always
---run with argument arrays (never a shell string built from paths or names).
---@class GitWorktreeGit
local M = {}

---@class GitWorktreeTree
---@field path string
---@field branch? string full local ref, nil for a detached checkout
---@field head? string
---@field locked? string reason ("" when none was given)
---@field prunable? string
---@field bare? boolean

---@class GitWorktreeContext
---@field cwd string editor working directory when the action started
---@field current string top level of the checkout containing cwd
---@field main string the registered main checkout
---@field head string commit of the current checkout
---@field trees GitWorktreeTree[] registered checkouts, main first

---@class GitWorktreeBranch
---@field name string local branch name (without any remote prefix)
---@field ref string full ref; "" for a branch to be created
---@field kind "local"|"remote"|"new"

---Run git in `cwd`; raise git's own message on failure.
---@param cwd string
---@param args string[]
---@return string stdout
function M.run(cwd, args)
  local command = { "git", "-C", cwd }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = false }):wait()
  if result.code ~= 0 then
    error(vim.trim(result.stderr or result.stdout or "Git operation failed"), 0)
  end
  return result.stdout or ""
end

---Resolved, normalized path used to compare checkouts (aliases and symlinks
---compare equal).
---@param path string
---@return string
function M.identity(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

---Parse `git worktree list --porcelain -z`.
---@param output string
---@return GitWorktreeTree[]
function M.parse_worktrees(output)
  local trees = {} ---@type GitWorktreeTree[]
  local tree ---@type GitWorktreeTree?
  for _, field in ipairs(vim.split(output, "\0")) do
    if field:sub(1, 9) == "worktree " then
      tree = { path = field:sub(10) }
      trees[#trees + 1] = tree
    elseif tree then
      local key, value = field:match("^(%S+)%s(.*)$")
      if key == "branch" then
        tree.branch = value
      elseif key == "HEAD" then
        tree.head = value
      elseif field == "bare" then
        tree.bare = true
      elseif key == "locked" or field == "locked" then
        tree.locked = value or ""
      elseif key == "prunable" or field == "prunable" then
        tree.prunable = value or ""
      end
    end
  end
  return trees
end

---Describe the repository around `cwd`.
---@param cwd? string defaults to the editor's working directory
---@return GitWorktreeContext
function M.discover(cwd)
  cwd = cwd or vim.fn.getcwd()
  local current = M.run(cwd, { "rev-parse", "--show-toplevel" }):gsub("\n$", "")
  local trees = M.parse_worktrees(M.run(cwd, { "worktree", "list", "--porcelain", "-z" }))
  local main = trees[1]
  if not main or main.bare or vim.fn.isdirectory(main.path) ~= 1 then
    error("A registered, non-bare main checkout is required", 0)
  end
  return {
    cwd = cwd,
    current = current,
    main = main.path,
    head = vim.trim(M.run(cwd, { "rev-parse", "--verify", "HEAD" })),
    trees = trees,
  }
end

---The registered, usable checkout at `path`.
---@param ctx GitWorktreeContext
---@param path string
---@return GitWorktreeTree
function M.registered(ctx, path)
  for _, tree in ipairs(ctx.trees) do
    if M.identity(tree.path) == M.identity(path) then
      if tree.bare or tree.prunable or vim.fn.isdirectory(tree.path) ~= 1 then
        error("Checkout is unavailable: " .. tree.path, 0)
      end
      return tree
    end
  end
  error("Not a registered checkout of this repository: " .. path, 0)
end

---Local branches and remote-tracking branches. A remote branch's name drops
---the longest matching remote prefix, so remotes containing slashes work.
---@param ctx GitWorktreeContext
---@return GitWorktreeBranch[]
function M.branches(ctx)
  local choices = {} ---@type GitWorktreeBranch[]
  local remotes = vim.split(vim.trim(M.run(ctx.cwd, { "remote" })), "\n", { trimempty = true })
  table.sort(remotes, function(a, b)
    return #a > #b
  end)
  local refs =
    M.run(ctx.cwd, { "for-each-ref", "--format=%(refname)%09%(symref)", "refs/heads", "refs/remotes" })
  for line in refs:gmatch("[^\n]+") do
    local ref, symbolic = line:match("^(.-)\t(.*)$")
    if ref and symbolic == "" then
      local name = ref:match("^refs/heads/(.+)$")
      if name then
        choices[#choices + 1] = { name = name, ref = ref, kind = "local" }
      else
        for _, remote in ipairs(remotes) do
          local prefix = "refs/remotes/" .. remote .. "/"
          if vim.startswith(ref, prefix) then
            choices[#choices + 1] = { name = ref:sub(#prefix + 1), ref = ref, kind = "remote" }
            break
          end
        end
      end
    end
  end
  return choices
end

---Raise git's message when `branch` is not a valid branch name.
---@param cwd string
---@param branch string
function M.check_branch_name(cwd, branch)
  M.run(cwd, { "check-ref-format", "--branch", branch })
end

---Whether a checkout has no modified, staged, untracked or ignored content.
---@param path string
---@return boolean
function M.is_pristine(path)
  return M.run(path, { "status", "--porcelain", "--untracked-files=all", "--ignored" }) == ""
end

return M
