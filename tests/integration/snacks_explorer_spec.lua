---The snacks_explorer integration against the installed snacks.nvim (from
---'packpath'). Skipped with a notice when snacks.nvim is missing.
local H = require("helpers")

local path = vim.fn.globpath(vim.o.packpath, "pack/*/*/snacks.nvim", false, true)[1]
if not path then
  io.stdout:write("snacks_explorer spec skipped, not installed: snacks.nvim\n")
  return
end
vim.opt.rtp:append(path)
vim.o.swapfile = false
require("snacks").setup({ picker = { enabled = true }, explorer = { enabled = true } })

---@return string
local function linked()
  local dest = H.repo .. ".worktrees/b"
  H.git(H.repo, "worktree", "add", "-q", "-b", "b", dest)
  return dest
end

local function explorers()
  return Snacks.picker.get({ source = "explorer", tab = false })
end

describe("snacks_explorer integration", function()
  before_each(function()
    require("git-worktree").setup({ integrations = { "snacks_explorer" } })
  end)

  it("is enabled without warnings when snacks.nvim is installed", function()
    eq(
      { "snacks_explorer" },
      vim.tbl_map(function(p)
        return p.name
      end, require("git-worktree.switch").participants)
    )
  end)

  it("closes the explorer and forgets its expanded folders (Snacks explorer closed and forgotten)", function()
    local b = linked()
    vim.fn.mkdir(H.repo .. "/sub", "p")
    vim.fn.writefile({ "x" }, H.repo .. "/sub/x.txt")
    local tree = require("snacks.explorer.tree")
    tree:open(H.repo .. "/sub")
    Snacks.explorer({ cwd = H.repo })
    ok(
      vim.wait(5000, function()
        return #explorers() > 0
      end, 10),
      "explorer opened"
    )
    local wt = require("git-worktree")
    H.notifications(function()
      assert(wt.switch_to(wt.discover(), b))
    end)
    eq(0, #explorers())
    for p, node in pairs(tree.nodes) do
      ok(not node.open, "still expanded: " .. p)
    end
  end)
end)
