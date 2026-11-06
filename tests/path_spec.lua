local H = require("helpers")

describe("destination", function()
  it("defaults to <main>.worktrees/<branch>, keeping branch slashes", function()
    local wt = require("git-worktree")
    local ctx = wt.discover()
    eq(H.repo .. ".worktrees/feature/login", wt.destination(ctx, "feature/login"))
  end)

  it("anchors the default on the main checkout from a linked checkout", function()
    local wt = require("git-worktree")
    local linked = H.repo .. ".worktrees/a"
    H.git(H.repo, "worktree", "add", "-q", "-b", "a", linked)
    vim.api.nvim_set_current_dir(linked)
    eq(H.repo .. ".worktrees/next", wt.destination(wt.discover(), "next"))
  end)

  it("resolves relative overrides against the main checkout and expands ~", function()
    local wt = require("git-worktree")
    local ctx = wt.discover()
    eq(H.root .. "/arbitrary parent/review", wt.destination(ctx, "fix", "../review"))
    eq(
      vim.fn.expand("~") .. "/unused-worktree-fixture",
      wt.destination(ctx, "home", "~/unused-worktree-fixture")
    )
    eq(H.root .. "/abs path", wt.destination(ctx, "abs", H.root .. "/abs path"))
  end)

  it(
    "rejects empty input, existing paths, dangling symlinks and bad names without creating anything",
    function()
      local wt = require("git-worktree")
      local ctx = wt.discover()
      H.rejects("cannot be empty", function()
        wt.destination(ctx, "valid", "")
      end)
      H.rejects("already exists", function()
        wt.destination(ctx, "valid", H.repo)
      end)
      assert(vim.uv.fs_symlink(H.root .. "/missing", H.root .. "/dangling"))
      H.rejects("already exists", function()
        wt.destination(ctx, "valid", H.root .. "/dangling")
      end)
      H.rejects("not a valid branch name", function()
        wt.destination(ctx, "../bad")
      end)
      eq(nil, vim.uv.fs_stat(H.repo .. ".worktrees"))
    end
  )

  it("uses a configured destination function", function()
    local wt = require("git-worktree")
    wt.setup({
      destination = function(ctx, branch)
        return ctx.main .. "/../trees/" .. branch
      end,
    })
    eq(H.root .. "/arbitrary parent/trees/x", wt.destination(wt.discover(), "x"))
  end)
end)
