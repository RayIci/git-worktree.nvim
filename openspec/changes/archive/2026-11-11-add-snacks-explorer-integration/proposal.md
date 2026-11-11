# Proposal

## Why

Hosts are moving their file explorer from neo-tree to the snacks.nvim explorer. Like neo-tree, an open snacks explorer and its expanded folders belong to the outgoing workspace and must not leak into the destination.

## What Changes

- New integration `snacks_explorer`, enabled by name in `setup({ integrations = { ... } })`: it closes every open snacks explorer and forgets its expanded folders before the old workspace's buffers are deleted.
- The `neotree` integration is unchanged.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `worktree-workspaces`: the list of optional integrations gains `snacks_explorer`.

## Impact

- New file `lua/git-worktree/integrations/snacks_explorer.lua`, a real-plugin test in `tests/integration/`, and a row in the README and help integration tables.
