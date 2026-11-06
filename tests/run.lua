---Headless test runner for git-worktree. No framework, no dependencies.
---
---  nvim --headless -u NONE -l tests/run.lua [pattern]
---  nvim --headless -u NONE -l tests/run.lua --integration [pattern]
---
---Runs every tests/*_spec.lua, or with --integration every
---tests/integration/*_spec.lua (which load the integrated plugins from
---'packpath' and skip themselves when one is missing). `pattern` keeps only
---spec files whose name contains it. Each `it` gets a fresh temp repository
---and isolated git and XDG settings; the plugin is unloaded after every
---test. Exits non-zero when any test fails.

local script = debug.getinfo(1, "S").source:sub(2)
local test_dir = vim.fn.fnamemodify(script, ":p:h")
local repo = vim.fn.fnamemodify(test_dir, ":h")

package.path = table.concat({
  repo .. "/lua/?.lua",
  repo .. "/lua/?/init.lua",
  test_dir .. "/?.lua",
  package.path,
}, ";")
vim.opt.rtp:prepend(repo)
vim.o.swapfile = false
vim.o.shadafile = "NONE"

local args = _G.arg or {}
local integration = args[1] == "--integration"
local filter = args[integration and 2 or 1] ---@type string?

---@class TestCase
---@field name string
---@field fn fun()

---@type { name: string, cases: TestCase[], before: fun()[], after: fun()[] }[]
local suites = {}
local current

function _G.describe(name, fn)
  current = { name = name, cases = {}, before = {}, after = {} }
  table.insert(suites, current)
  fn()
  current = nil
end

function _G.it(name, fn)
  assert(current, "it() outside describe()")
  table.insert(current.cases, { name = name, fn = fn })
end

function _G.before_each(fn)
  table.insert(current.before, fn)
end

function _G.after_each(fn)
  table.insert(current.after, fn)
end

---Assertion helpers shared by every spec.
_G.eq = function(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(
      ("%sexpected:\n%s\ngot:\n%s"):format(
        msg and (msg .. "\n") or "",
        vim.inspect(expected),
        vim.inspect(actual)
      ),
      2
    )
  end
end

_G.ok = function(cond, msg)
  if not cond then
    error(msg or "assertion failed", 2)
  end
end

local files = vim.fn.glob(test_dir .. (integration and "/integration" or "") .. "/*_spec.lua", false, true)
table.sort(files)
for _, f in ipairs(files) do
  if not filter or f:find(filter, 1, true) then
    dofile(f)
  end
end

local helpers = require("helpers")

---@param s string
local function out(s)
  io.stdout:write(s, "\n")
end
local passed, failed = 0, 0
local failures = {}

for _, suite in ipairs(suites) do
  out(suite.name)
  for _, case in ipairs(suite.cases) do
    helpers.begin_test()
    local okrun, err = xpcall(function()
      for _, b in ipairs(suite.before) do
        b()
      end
      case.fn()
    end, debug.traceback)
    for _, a in ipairs(suite.after) do
      pcall(a)
    end
    local cleanup_ok, cleanup_err = pcall(helpers.end_test)
    if okrun and not cleanup_ok then
      okrun, err = false, "cleanup: " .. tostring(cleanup_err)
    end
    if okrun then
      passed = passed + 1
      out("  ✓ " .. case.name)
    else
      failed = failed + 1
      out("  ✗ " .. case.name)
      table.insert(failures, ("%s › %s\n%s"):format(suite.name, case.name, err))
    end
  end
end

if #failures > 0 then
  out("\nFailures:")
  for _, f in ipairs(failures) do
    out("\n" .. f)
  end
end
out(("\n%d passed, %d failed"):format(passed, failed))
io.stdout:flush()
os.exit(failed > 0 and 1 or 0)
