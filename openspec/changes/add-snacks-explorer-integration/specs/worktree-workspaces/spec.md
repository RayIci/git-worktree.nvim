# Spec Delta

## MODIFIED Requirements

### Requirement: Optional integrations
`setup()` SHALL accept a list of integrations to enable, each a participant shipped with the plugin for one other plugin: `auto_session` (session backend), `neogit`, `dap`, `scope`, `bufferline`, `neotree` and `snacks_explorer`. An integration whose plugin is not installed SHALL be skipped with one warning; an unknown name SHALL be reported.

#### Scenario: Missing plugin
- **WHEN** `setup()` enables `neotree` and neo-tree is not installed
- **THEN** one warning names the skipped integration and switching works without it

#### Scenario: Exit autosave preference kept
- **WHEN** the auto-session integration is enabled, exit autosave is disabled, and the user switches
- **THEN** the outgoing session is still saved for the switch and exit autosave remains disabled afterwards

#### Scenario: Neogit follows the active checkout
- **WHEN** the neogit integration is enabled and the user creates a worktree and switches to it
- **THEN** Neogit's status float is closed before the action, its repository is refreshed after creation, and it shows the new checkout after the switch, while git itself did the creation

#### Scenario: Old workspace state cleared
- **WHEN** the scope, bufferline, neotree and dap integrations are enabled and the user switches
- **THEN** the old workspace's per-tab buffer lists, pins, explorer and breakpoints are gone in the destination

#### Scenario: Snacks explorer closed and forgotten
- **WHEN** the snacks_explorer integration is enabled, the snacks explorer is open with folders expanded, and the user switches
- **THEN** the explorer is closed before the old workspace's buffers go, and no folder of the old workspace is still marked expanded
