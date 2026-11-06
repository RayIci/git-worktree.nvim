---Per-test fixtures: a temp git repository (main checkout under a parent
---directory with a space), isolated git and XDG settings, and a clean plugin.
local H = {}

---@type string? temp root of the running test
H.root = nil
---@type string? main checkout of the running test
H.repo = nil

local saved = {} ---@type table<string, string|false>
local env = {
  GIT_CONFIG_GLOBAL = "/dev/null",
  GIT_CONFIG_NOSYSTEM = "1",
  GIT_TERMINAL_PROMPT = "0",
  GIT_AUTHOR_NAME = "Worktree tests",
  GIT_AUTHOR_EMAIL = "test@example.invalid",
  GIT_COMMITTER_NAME = "Worktree tests",
  GIT_COMMITTER_EMAIL = "test@example.invalid",
}

local function unload()
  for name in pairs(package.loaded) do
    if name == "git-worktree" or name:find("^git%-worktree%.") then
      package.loaded[name] = nil
    end
  end
end

---Run git in `cwd` and return trimmed stdout; fail the test on error.
---@param cwd string
---@param ... string
---@return string
function H.git(cwd, ...)
  local result = vim.system({ "git", "-C", cwd, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end

function H.begin_test()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  -- Resolve symlinks once so paths compare equal to what git reports.
  H.root = assert(vim.uv.fs_realpath(root))
  for key, value in pairs(env) do
    saved[key] = vim.env[key] or false
    vim.env[key] = value
  end
  for _, key in ipairs({ "XDG_STATE_HOME", "XDG_DATA_HOME" }) do
    saved[key] = vim.env[key] or false
    vim.env[key] = H.root .. "/" .. key:lower()
  end
  H.repo = H.root .. "/arbitrary parent/backend"
  vim.fn.mkdir(H.repo, "p")
  H.git(H.repo, "init", "-q", "-b", "main")
  vim.fn.writefile({ "first", "second", "third" }, H.repo .. "/file.txt")
  H.git(H.repo, "add", ".")
  H.git(H.repo, "commit", "-q", "-m", "initial")
  vim.api.nvim_set_current_dir(H.repo)
  unload()
end

function H.end_test()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.cmd("silent! %bwipeout!")
  vim.api.nvim_set_current_dir(vim.fn.stdpath("cache") --[[@as string]])
  unload()
  for key, value in pairs(saved) do
    vim.env[key] = value or nil
  end
  vim.fn.delete(H.root, "rf")
  H.root, H.repo = nil, nil
end

---Expect `fn` to raise an error matching `pattern`.
---@param pattern string
---@param fn fun()
function H.rejects(pattern, fn)
  local success, err = pcall(fn)
  assert(not success, "expected an error matching " .. pattern)
  assert(tostring(err):match(pattern), ("error %q does not match %q"):format(tostring(err), pattern))
end

---Capture vim.notify messages for the duration of `fn`.
---@param fn fun()
---@return string[]
function H.notifications(fn)
  local seen = {}
  local notify = vim.notify
  vim.notify = function(msg) ---@diagnostic disable-line: duplicate-set-field
    seen[#seen + 1] = tostring(msg)
  end
  local ok, err = pcall(fn)
  vim.notify = notify
  if not ok then
    error(err, 0)
  end
  return seen
end

---Replace a function for the duration of `fn`.
---@param tbl table
---@param key string
---@param value any
---@param fn fun()
function H.with(tbl, key, value, fn)
  local original = tbl[key]
  tbl[key] = value
  local ok, err = pcall(fn)
  tbl[key] = original
  if not ok then
    error(err, 0)
  end
end

return H
