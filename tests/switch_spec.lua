local H = require("helpers")

---A second checkout to switch to.
---@return string
local function target()
  local path = H.repo .. ".worktrees/b"
  H.git(H.repo, "worktree", "add", "-q", "-b", "b", path)
  return path
end

---A participant recording every hook it receives into `log`.
---@param log string[]
---@param overrides? table<string, function>
---@return GitWorktreeParticipant
local function recorder(log, overrides)
  local p = { name = "recorder" }
  for _, hook in ipairs({ "check", "pause", "flush", "reset", "cleanup", "resume" }) do
    p[hook] = function()
      log[#log + 1] = hook
    end
  end
  p.restore = function(info)
    log[#log + 1] = "restore " .. vim.fs.basename(info.path)
  end
  for hook, fn in pairs(overrides or {}) do
    p[hook] = fn
  end
  return p
end

---A session backend recording calls into `log`; `sessions` maps cwd -> file.
---@param log string[]
---@param opts? { exists?: boolean, restore?: fun(file?: string): boolean, save?: fun(cwd: string): string }
---@return GitWorktreeParticipant
local function backend(log, opts)
  opts = opts or {}
  return {
    name = "session",
    session = {
      hold = function()
        log[#log + 1] = "hold"
      end,
      release = function()
        log[#log + 1] = "release"
      end,
      stop = function()
        log[#log + 1] = "stop"
      end,
      save = opts.save or function(cwd)
        log[#log + 1] = "save " .. vim.fs.basename(cwd)
        return "/sessions/" .. vim.fs.basename(cwd) .. ".vim"
      end,
      exists = function()
        log[#log + 1] = "exists"
        return opts.exists ~= false
      end,
      restore = opts.restore or function(file)
        log[#log + 1] = "session " .. (file and vim.fs.basename(file) or vim.fs.basename(vim.fn.getcwd()))
        return true
      end,
    },
  }
end

local function events(log)
  return vim.api.nvim_create_autocmd("User", {
    pattern = { "GitWorktreeSwitchPre", "GitWorktreeSwitched" },
    callback = function(ev)
      log[#log + 1] = ev.match
    end,
  })
end

describe("switch", function()
  it("runs the phases in order and ends in the target", function()
    local wt = require("git-worktree")
    local b = target()
    local log = {}
    wt.register(backend(log))
    wt.register(recorder(log))
    local id = events(log)
    vim.cmd.edit("file.txt")
    local seen = H.notifications(function()
      eq(true, wt.switch_to(wt.discover(), b))
    end)
    vim.api.nvim_del_autocmd(id)
    eq({
      "check",
      "GitWorktreeSwitchPre",
      "pause",
      "hold",
      "flush",
      "save backend",
      "reset",
      "cleanup",
      "exists",
      "session b",
      "restore b",
      "release",
      "resume",
      "GitWorktreeSwitched",
    }, log)
    eq(b, vim.fn.getcwd())
    eq({ "Worktrees: Opened workspace: " .. b }, seen)
    eq(1, #vim.api.nvim_list_wins())
    eq("", vim.api.nvim_buf_get_name(0), "the source buffers are gone")
  end)

  it("does nothing when the active checkout is selected", function()
    local wt = require("git-worktree")
    local log = {}
    wt.register(recorder(log))
    eq(true, wt.switch_to(wt.discover(), H.repo))
    eq({}, log)
  end)

  it("restores participants without a session backend", function()
    local wt = require("git-worktree")
    local b = target()
    local log = {}
    wt.register(recorder(log))
    H.notifications(function()
      assert(wt.switch_to(wt.discover(), b))
    end)
    eq({ "check", "pause", "flush", "reset", "cleanup", "restore b", "resume" }, log)
  end)

  it("aborts before any teardown when a flush or the session save fails", function()
    local wt = require("git-worktree")
    local b = target()
    for _, failing in ipairs({ "flush", "save" }) do
      local log = {}
      if failing == "save" then
        wt.register(backend(log, {
          save = function()
            error("Could not save the outgoing session", 0)
          end,
        }))
        wt.register(recorder(log))
      else
        wt.unregister("session")
        wt.register(recorder(log, {
          flush = function()
            error("fixture sidecar failure", 0)
          end,
        }))
      end
      vim.cmd.edit("file.txt")
      local buf = vim.api.nvim_get_current_buf()
      H.rejects(failing == "save" and "outgoing session" or "fixture sidecar failure", function()
        wt.switch_to(wt.discover(), b)
      end)
      eq(H.repo, vim.fn.getcwd())
      eq(buf, vim.api.nvim_get_current_buf())
      ok(not vim.tbl_contains(log, "reset"), failing .. ": nothing was torn down")
      eq("resume", log[#log], failing .. ": writes resume")
    end
  end)

  it("recovers the source workspace when the destination session is broken", function()
    local wt = require("git-worktree")
    local b = target()
    local log = {}
    wt.register(backend(log, {
      restore = function(file)
        if not file then
          error("fixture broken session", 0)
        end
        log[#log + 1] = "session " .. vim.fs.basename(file)
        return true
      end,
    }))
    wt.register(recorder(log))
    H.rejects("destination session.*fixture broken session", function()
      wt.switch_to(wt.discover(), b)
    end)
    eq(H.repo, vim.fn.getcwd())
    local tail = vim.list_slice(log, #log - 5)
    eq({ "reset", "cleanup", "session backend.vim", "restore backend", "release", "resume" }, tail)
  end)

  it("keeps writes stopped and explains what is recoverable when recovery fails", function()
    local wt = require("git-worktree")
    local b = target()
    local log = {}
    wt.register(backend(log, {
      restore = function()
        return false
      end,
    }))
    wt.register(recorder(log))
    H.rejects(
      "Recovery failed.*Automatic writes stopped%. Current cwd: .*Source session: /sessions/backend%.vim",
      function()
        wt.switch_to(wt.discover(), b)
      end
    )
    eq("stop", log[#log])
    ok(not vim.tbl_contains(log, "release"), "autosave is not restored")
    eq(0, #vim.tbl_filter(function(entry)
      return entry == "resume"
    end, log), "participants are not resumed")
  end)

  it("is refused by a participant's check before anything is paused", function()
    local wt = require("git-worktree")
    local b = target()
    local log = {}
    wt.register(recorder(log, {
      check = function()
        error("Stop active debugging sessions before switching workspaces", 0)
      end,
    }))
    H.rejects("debugging", function()
      wt.switch_to(wt.discover(), b)
    end)
    eq({}, log)
  end)
end)

describe("preflight", function()
  it("cancels by default and saves every modified buffer on request", function()
    local wt = require("git-worktree")
    local b = target()
    vim.cmd.edit("file.txt")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "unsaved" })
    vim.cmd.tabnew()
    local default
    H.with(vim.fn, "confirm", function(_, _, d)
      default = d
      return 2
    end, function()
      eq(false, wt.switch_to(wt.discover(), b))
    end)
    eq(2, default, "Cancel is the default choice")
    eq(H.repo, vim.fn.getcwd())
    ok(vim.bo[buf].modified)
    H.with(vim.fn, "confirm", function()
      return 1
    end, function()
      eq(true, wt.preflight())
    end)
    ok(not vim.bo[buf].modified)
    eq("unsaved", vim.fn.readfile(H.repo .. "/file.txt")[1])
  end)

  it("refuses unnamed and unwritable modified buffers", function()
    local wt = require("git-worktree")
    vim.cmd.edit("file.txt")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "unsaved" })
    vim.bo[buf].readonly = true
    H.with(vim.fn, "confirm", function()
      return 1
    end, function()
      H.rejects("file%.txt", wt.preflight)
      vim.bo[buf].readonly = false
      vim.cmd.write()
      vim.cmd.enew()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unnamed changes" })
      H.rejects("unnamed", wt.preflight)
    end)
  end)

  it("refuses to discard a live terminal job and leaves it running", function()
    local wt = require("git-worktree")
    vim.cmd.enew()
    local job = vim.fn.jobstart({ "sleep", "30" }, { term = true })
    ok(job > 0)
    H.rejects("live terminal", wt.preflight)
    eq(-1, vim.fn.jobwait({ job }, 0)[1])
    vim.fn.jobstop(job)
    vim.fn.jobwait({ job }, 1000)
  end)
end)

describe("actions", function()
  it("serializes requests and releases the lock on cancel", function()
    local wt = require("git-worktree")
    local pending
    local seen = H.notifications(function()
      H.with(vim.ui, "select", function(_, _, cb)
        pending = cb
      end, function()
        wt.switch()
        ok(pending, "selection is open")
        wt.create()
        pending(nil)
      end)
    end)
    eq({ "Worktrees: A worktree action is already in progress" }, seen)
    local called = false
    H.with(vim.ui, "select", function(_, _, cb)
      called = true
      cb(nil)
    end, function()
      wt.switch()
    end)
    ok(called, "the lock was released")
  end)

  it("lets participants prepare before the repository is read", function()
    local wt = require("git-worktree")
    local order = {}
    wt.register({
      name = "prep",
      prepare = function()
        order[#order + 1] = "prepare"
      end,
    })
    H.with(vim.ui, "select", function(_, opts, cb)
      order[#order + 1] = opts.prompt
      cb(nil)
    end, function()
      wt.menu()
    end)
    eq({ "prepare", "Worktrees:" }, order)
  end)

  it("creates and switches, prefilling the default destination", function()
    local wt = require("git-worktree")
    local inputs = {}
    H.notifications(function()
      H.with(vim.ui, "select", function(items, _, cb)
        cb(items[1], 1) -- "Create new branch..."
      end, function()
        H.with(vim.ui, "input", function(opts, cb)
          inputs[#inputs + 1] = opts.default or opts.prompt
          cb(#inputs == 1 and "ui/default" or opts.default)
        end, function()
          wt.create()
        end)
      end)
    end)
    eq({ "New branch name: ", H.repo .. ".worktrees/ui/default" }, inputs)
    eq(H.repo .. ".worktrees/ui/default", vim.fn.getcwd())
  end)

  it("keeps and reports a created checkout that was not opened", function()
    local wt = require("git-worktree")
    vim.cmd.edit("file.txt")
    local buf = vim.api.nvim_get_current_buf()
    local create = wt.create_checkout
    wt.create_checkout = function(...)
      local tree = create(...)
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "edit during creation" })
      return tree
    end
    local seen = H.notifications(function()
      H.with(vim.fn, "confirm", function()
        return 2
      end, function()
        H.with(vim.ui, "select", function(items, _, cb)
          cb(items[1], 1)
        end, function()
          local n = 0
          H.with(vim.ui, "input", function(opts, cb)
            n = n + 1
            cb(n == 1 and "ui/not-opened" or opts.default)
          end, function()
            wt.create()
          end)
        end)
      end)
    end)
    wt.create_checkout = create
    eq(H.repo, vim.fn.getcwd())
    ok(seen[#seen]:match("Created worktree, but did not open it: .*ui/not%-opened"), vim.inspect(seen))
    eq("refs/heads/ui/not-opened", H.git(H.repo .. ".worktrees/ui/not-opened", "symbolic-ref", "HEAD"))
  end)

  it("deletes only after confirmation", function()
    local wt = require("git-worktree")
    local b = target()
    local answer = "Cancel"
    local function delete()
      H.notifications(function()
        H.with(vim.ui, "select", function(items, opts, cb)
          if opts.prompt:match("^Delete inactive") then
            for i, tree in ipairs(items) do
              if tree.path == b then
                return cb(tree, i)
              end
            end
          end
          cb(answer)
        end, function()
          wt.delete()
        end)
      end)
    end
    delete()
    ok(vim.uv.fs_stat(b), "cancel keeps the checkout")
    answer = "Delete"
    delete()
    eq(nil, vim.uv.fs_stat(b))
  end)

  it("reports failures from a managed action", function()
    local wt = require("git-worktree")
    local seen = H.notifications(function()
      H.with(vim.ui, "select", function(items, _, cb)
        cb(items[1], 1)
      end, function()
        H.with(vim.ui, "input", function(_, cb)
          cb("../invalid")
        end, function()
          wt.create()
        end)
      end)
    end)
    ok(seen[1]:match("not a valid branch name"), vim.inspect(seen))
  end)
end)
