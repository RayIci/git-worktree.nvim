local H = require("helpers")

describe("worktree list parsing", function()
  it("reads branches, detached heads, locks, prunable and bare entries", function()
    local out = table.concat({
      "worktree /a b/main",
      "HEAD 1111",
      "branch refs/heads/main",
      "",
      "worktree /a b/main.worktrees/x",
      "HEAD 2222",
      "detached",
      "locked",
      "",
      "worktree /gone",
      "HEAD 3333",
      "branch refs/heads/gone",
      "locked being moved",
      "prunable gitdir file points to non-existent location",
      "",
      "worktree /bare",
      "bare",
      "",
    }, "\0")
    local trees = require("git-worktree.git").parse_worktrees(out)
    eq(4, #trees)
    eq({ path = "/a b/main", head = "1111", branch = "refs/heads/main" }, trees[1])
    eq({ path = "/a b/main.worktrees/x", head = "2222", locked = "" }, trees[2])
    eq("being moved", trees[3].locked)
    eq("gitdir file points to non-existent location", trees[3].prunable)
    eq(true, trees[4].bare)
  end)
end)

describe("discovery", function()
  it("finds the main checkout from main, linked, subdirectory and external checkouts", function()
    local wt = require("git-worktree")
    local linked = H.repo .. ".worktrees/feature/login"
    H.git(H.repo, "worktree", "add", "-q", "-b", "feature/login", linked)
    vim.fn.mkdir(linked .. "/subdir", "p")
    local external = H.root .. "/review elsewhere"
    H.git(H.repo, "worktree", "add", "-q", "--detach", external)

    eq(H.repo, wt.discover().main)
    eq(H.repo, wt.discover(linked .. "/subdir").main)
    local ctx = wt.discover(external)
    eq(H.repo, ctx.main)
    eq(external, ctx.current)
    eq(3, #ctx.trees)
    eq(nil, ctx.trees[3].branch, "detached checkout is listed without a branch")
    eq(H.git(external, "rev-parse", "HEAD"), ctx.head)
  end)

  it("treats a symlinked alias as the same checkout", function()
    local alias = H.root .. "/alias"
    assert(vim.uv.fs_symlink(H.repo, alias))
    local git = require("git-worktree.git")
    eq(H.repo, require("git-worktree").discover(alias).main)
    eq(git.identity(H.repo), git.identity(alias))
  end)

  it("rejects directories outside a repository and bare repositories", function()
    H.rejects("not a git repository", function()
      require("git-worktree").discover(H.root)
    end)
    H.git(H.root, "init", "-q", "--bare", H.root .. "/bare")
    H.rejects("fatal:", function()
      require("git-worktree").discover(H.root .. "/bare")
    end)
  end)
end)

describe("branches", function()
  it("lists local and remote branches, dropping the longest remote prefix", function()
    local wt = require("git-worktree")
    local head = H.git(H.repo, "rev-parse", "HEAD")
    H.git(H.repo, "branch", "ui/local")
    H.git(H.repo, "remote", "add", "upstream", H.root .. "/nonexistent")
    H.git(H.repo, "remote", "add", "team/upstream", H.root .. "/nonexistent-team")
    H.git(H.repo, "update-ref", "refs/remotes/upstream/remote/feature", head)
    H.git(H.repo, "update-ref", "refs/remotes/team/upstream/nested/branch", head)
    local by_ref = {}
    for _, branch in ipairs(wt.branches(wt.discover())) do
      by_ref[branch.ref] = branch
    end
    eq({ name = "ui/local", ref = "refs/heads/ui/local", kind = "local" }, by_ref["refs/heads/ui/local"])
    eq("remote/feature", by_ref["refs/remotes/upstream/remote/feature"].name)
    eq("nested/branch", by_ref["refs/remotes/team/upstream/nested/branch"].name)
    eq("remote", by_ref["refs/remotes/team/upstream/nested/branch"].kind)
  end)
end)
