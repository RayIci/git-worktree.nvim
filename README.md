# git-worktree.nvim

Create, switch and delete git worktrees from Neovim, where **switching replaces the whole
workspace**: the outgoing session is saved, buffers, tabs and layout are torn down, the
working directory changes, and the destination's saved session comes back. Plugins you use
take part through optional integrations; your own state takes part as a participant.

- Plain `git` only; no plugin is required.
- New worktrees go to `<main-checkout>.worktrees/<branch>` by default, with an editable
  destination prompt.
- Safe by default: unsaved buffers, live terminal jobs and debug sessions block a switch;
  deletion refuses anything that is not clean, unlocked and inactive.
- Failures are recoverable: a broken destination session puts you back in the source.

## Requirements

- Neovim ≥ 0.12 and `git`
- Optional, through integrations: auto-session, Neogit, nvim-dap, scope.nvim,
  bufferline.nvim, neo-tree.nvim

## Install

```lua
vim.pack.add({ "https://github.com/RayIci/git-worktree.nvim" })
```

## Setup

```lua
local worktree = require("git-worktree")
worktree.setup({
  -- integrations to enable; any whose plugin is missing is skipped with a warning
  integrations = { "auto_session", "neogit", "dap", "scope", "bufferline", "neotree" },
  -- optional: where a new worktree goes by default
  -- destination = function(ctx, branch) return ctx.main .. ".worktrees/" .. branch end,
})

vim.keymap.set("n", "<leader>gww", worktree.switch, { desc = "Switch worktree workspace" })
vim.keymap.set("n", "<leader>gwc", worktree.create, { desc = "Create worktree workspace" })
vim.keymap.set("n", "<leader>gwd", worktree.delete, { desc = "Delete inactive worktree" })
```

`setup()` maps no keys. `worktree.menu()` offers all three actions in one picker; it fits
Neogit's status buffer:

```lua
require("neogit").setup({
  mappings = {
    popup = { ["w"] = false },
    status = { ["w"] = function() require("git-worktree").menu() end },
  },
})
```

Pickers and prompts use `vim.ui.select` and `vim.ui.input`, so they follow whatever UI you
configured for them (Telescope, fzf-lua, snacks, …).

## Creating

Pick a local branch, a remote-tracking branch, or **Create new branch…**, then confirm or
edit the destination. For a main checkout `/work/client/backend` and branch
`feature/login`, the default is `/work/client/backend.worktrees/feature/login`, also when
you start from another worktree or a subdirectory. Relative overrides resolve against the
main checkout, `~/` expands, and an existing path (even a dangling symlink) is refused.

New branches start at the invoking checkout's HEAD. A remote branch drops its remote
prefix for the local name; an existing local counterpart is reused as is, otherwise a
tracking branch is created. Nothing is fetched, rebased or pushed, and `.env` files,
dependencies or virtual environments are not copied — set those up per checkout. A new
worktree is switched to right away; if that switch is cancelled, the checkout is kept and
its path reported.

## Switching

A switch saves outgoing state, then replaces buffers, tabs and layout with the
destination's. Selecting the active checkout does nothing. Before leaving:

- unsaved buffers in any tab, hidden or not, must all be saved ("Save all and switch") or
  the switch is cancelled, which is the default; unnamed or unwritable ones block it;
- a live Neovim terminal job blocks it (it keeps running);
- with the `dap` integration, a debug session blocks it (it is not stopped).

External terminals, tmux panes, servers and AI agents are never touched and keep their
working directories.

If the destination's session fails to restore, the source workspace is restored and the
destination's session file is left as it was. If even that fails, automatic writes stay
off and the error names the current directory and the source session file.

## Deleting

Deletion confirms the path and branch and refuses the main checkout, the active one,
locked worktrees, and any modified, staged, untracked or ignored content. It never forces
and never deletes the branch.

## Integrations

| Name | Plugin | What it does |
|---|---|---|
| `auto_session` | rmagatti/auto-session | Session backend: saves the outgoing session (even with exit autosave off, which stays as it was) and restores the destination's. Without it, switches restore participants only. |
| `neogit` | NeogitOrg/neogit | Closes the status float before an action, refreshes after create/remove, follows the active checkout. |
| `dap` | mfussenegger/nvim-dap | Blocks switching during a debug session; clears breakpoints with the old workspace. |
| `scope` | tiagovla/scope.nvim | Drops the old workspace's per-tab buffer lists. |
| `bufferline` | akinsho/bufferline.nvim | Drops the old workspace's pins. |
| `neotree` | nvim-neo-tree/neo-tree.nvim | Closes the explorer and drops its per-tab state. |
| `snacks_explorer` | folke/snacks.nvim | Closes the snacks explorer and forgets its expanded folders. |

## Participants

Anything else that should follow a switch registers a participant: a table with a `name`
and any of these hooks, called in registration order.

```lua
require("git-worktree").register({
  name = "my-state",
  check = function() end,          -- raise to refuse leaving the workspace
  pause = function() end,          -- stop automatic writes, drop pending ones
  flush = function() end,          -- save outgoing state now; raising aborts the switch
  reset = function() end,          -- before the old buffers are deleted
  cleanup = function() end,        -- after they are deleted
  restore = function(info) end,    -- info.path became the working directory
  resume = function() end,         -- automatic writes may start again
  prepare = function() end,        -- before an action reads the repository
  changed = function(ctx) end,     -- a worktree was created or removed
})
```

`User` autocommands: `GitWorktreeCreated`, `GitWorktreeRemoved` (`data.path`),
`GitWorktreeSwitchPre` (`data.from`, `data.to`) and `GitWorktreeSwitched` (`data.from`,
`data.path`).

## Lua API

`create()`, `switch()`, `delete()`, `menu()` run the pickers. For scripting:
`discover(cwd?)`, `branches(ctx)`, `destination(ctx, branch, override?)`,
`create_checkout(ctx, choice, path)`, `remove_checkout(ctx, path)`, `preflight()`,
`switch_to(ctx, path)`, `register(participant)`, `unregister(name)`. See
`:help git-worktree`.

Neogit's own `:Neogit worktree` popup is a git-only interface: it does not save or switch
workspaces.

## Development

```sh
make test               # core suite, no plugins needed
make test-integration   # integrations against the plugins on 'packpath'
make fmt-check
```

## License

MIT
