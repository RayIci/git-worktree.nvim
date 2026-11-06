local H = require("helpers")

describe("setup", function()
  it("maps no keys", function()
    local before = #vim.api.nvim_get_keymap("n")
    require("git-worktree").setup({})
    eq(before, #vim.api.nvim_get_keymap("n"))
  end)

  it("enables an integration whose plugin is installed", function()
    package.preload["dap"] = function()
      return {
        sessions = function()
          return { {} }
        end,
      }
    end
    local wt = require("git-worktree")
    wt.setup({ integrations = { "dap" } })
    package.preload["dap"] = nil
    eq(
      { "dap" },
      vim.tbl_map(function(p)
        return p.name
      end, require("git-worktree.switch").participants)
    )
    H.rejects("debugging", wt.preflight)
    package.loaded["dap"] = nil
  end)

  it("skips an integration whose plugin is missing, with one warning", function()
    local seen = H.notifications(function()
      require("git-worktree").setup({ integrations = { "neotree" } })
    end)
    eq({ "Worktrees: neotree integration skipped: neo-tree.nvim is not installed" }, seen)
    eq({}, require("git-worktree.switch").participants)
  end)

  it("reports an unknown integration", function()
    local seen = H.notifications(function()
      require("git-worktree").setup({ integrations = { "nope" } })
    end)
    eq({ 'Worktrees: unknown integration "nope"' }, seen)
  end)

  it("replaces a participant registered twice under one name", function()
    local wt = require("git-worktree")
    wt.register({ name = "x", check = function() end })
    wt.register({ name = "x" })
    eq(1, #require("git-worktree.switch").participants)
    eq(nil, require("git-worktree.switch").participants[1].check)
  end)
end)
