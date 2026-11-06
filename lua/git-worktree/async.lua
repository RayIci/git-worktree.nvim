---Minimal coroutine helpers: run a flow as a coroutine and await
---callback-style functions such as vim.ui.select and vim.ui.input from it.
---@class GitWorktreeAsync
local M = {}

---Run `fn` as a coroutine. Errors inside `fn` propagate to the first resume
---only; long-running flows should catch their own errors.
---@param fn fun()
function M.run(fn)
  local co = coroutine.create(fn)
  local ok, err = coroutine.resume(co)
  if not ok then
    error(err, 0)
  end
end

---Call `fn` with a callback in argument position `argc` and wait for that
---callback. Works whether the callback fires later or synchronously.
---@param fn function
---@param argc integer position of the callback argument
---@param ... any arguments before the callback
---@return any ...
function M.await(fn, argc, ...)
  local co = assert(coroutine.running(), "git-worktree: await outside a coroutine")
  local args = { ... }
  local results ---@type table?
  local waiting = false
  args[argc] = function(...)
    results = { n = select("#", ...), ... }
    if waiting then
      waiting = false
      local ok, err = coroutine.resume(co)
      if not ok then
        error(err, 0)
      end
    end
  end
  fn(unpack(args, 1, argc))
  if not results then
    waiting = true
    coroutine.yield()
  end
  ---@cast results table
  return unpack(results, 1, results.n)
end

---Yield until the next event-loop tick.
function M.scheduler()
  M.await(vim.schedule, 1)
end

---`vim.ui.select`, awaited.
---@param items any[]
---@param opts table
---@return any item, integer? index
function M.select(items, opts)
  return M.await(vim.ui.select, 3, items, opts)
end

---`vim.ui.input`, awaited.
---@param opts table
---@return string?
function M.input(opts)
  return M.await(vim.ui.input, 2, opts)
end

return M
