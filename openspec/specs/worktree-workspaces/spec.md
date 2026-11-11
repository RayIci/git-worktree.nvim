# worktree-workspaces Specification

## Purpose
Managed git worktrees for Neovim: creating, switching and deleting checkouts of one repository, where a switch replaces the whole editor workspace and the plugins and state that take part in it do so through optional integrations and registered participants.

## Requirements

### Requirement: No required plugins
The plugin SHALL depend only on Neovim and `git`, running git with argument arrays and never through a shell string. Its `setup(opts)` SHALL register no keymaps; hosts map the actions themselves.

#### Scenario: Installed on its own
- **WHEN** the plugin is installed with no other plugins and `setup({})` is called
- **THEN** creating, switching and deleting worktrees work and no keymaps were added

### Requirement: Worktree actions
The plugin SHALL offer create, switch and delete actions and a menu offering all three, using `vim.ui.select` and `vim.ui.input` for every choice. The switch and delete selectors SHALL list every registered checkout by path and branch, or as detached.

#### Scenario: Include all registered checkouts
- **WHEN** the user opens the worktree selector in a repository with a main checkout, linked branches, and a detached linked checkout
- **THEN** the selector identifies the registered checkouts by path and branch or detached status, without omitting the detached checkout

#### Scenario: Menu reaches the same flows
- **WHEN** the user picks creation or switching from the menu
- **THEN** the same prompts and workspace safeguards apply as through the corresponding action

### Requirement: Main-checkout-based destination default
Creation SHALL prefill an absolute destination of `<main-checkout>.worktrees/<local-branch-name>`, derived from the repository's registered main checkout rather than the invoking cwd. No parent folder name SHALL receive special treatment. Slashes in branch names SHALL remain path separators.

#### Scenario: Arbitrary parent directory
- **WHEN** the main checkout is `/work/client/backend` and the selected branch is `fix-auth`
- **THEN** the suggested destination is `/work/client/backend.worktrees/fix-auth`

#### Scenario: Hierarchical branch name
- **WHEN** the main checkout is `/work/client/backend` and the selected branch is `feature/login`
- **THEN** the suggested destination is `/work/client/backend.worktrees/feature/login`, distinct from the destination for `feature-login`

#### Scenario: Creation from another worktree
- **WHEN** the user creates `feature-b` from `/work/client/backend.worktrees/feature-a`
- **THEN** the suggested destination is `/work/client/backend.worktrees/feature-b`, with no additional `.worktrees` suffix or nesting under `feature-a`

#### Scenario: Creation from an unrelated linked-checkout location
- **WHEN** the user invokes creation from `/tmp/review-backend` or a subdirectory within it, and Git registers its main checkout as `/work/client/backend`
- **THEN** the suggested destination still uses `/work/client/backend.worktrees/<local-branch-name>`

#### Scenario: Unavailable main checkout
- **WHEN** a valid main checkout cannot be established, including a bare-only repository
- **THEN** creation reports that context explicitly without guessing a destination or mutating the repository

### Requirement: Branch-aware creation
Creation SHALL support an existing local branch, an available remote-tracking branch, or an explicitly named new branch. Remote selections SHALL derive the local name by removing only the selected remote's prefix, reusing a matching local branch or creating a tracking branch when absent. An explicitly named new branch SHALL start at the invoking checkout's HEAD.

#### Scenario: Existing local branch
- **WHEN** the user selects an available local branch `feature/login`
- **THEN** the new checkout uses that branch and its full local name determines the default path

#### Scenario: Remote branch without a local counterpart
- **WHEN** the user selects `upstream/feature/login` and no local `feature/login` branch exists
- **THEN** creation uses a local `feature/login` tracking the selected remote ref and suggests `<main-checkout>.worktrees/feature/login`, without an `upstream` path prefix

#### Scenario: Remote branch with a local counterpart
- **WHEN** the user selects `origin/feature/login` and a local `feature/login` branch already exists
- **THEN** creation uses the existing local branch without resetting it to the remote ref

#### Scenario: Explicit new branch
- **WHEN** the user chooses to create `experiment/new-flow` from a linked checkout
- **THEN** the new branch starts at that linked checkout's HEAD and its name determines the prefilled destination

#### Scenario: Branch already checked out
- **WHEN** the chosen local branch is already checked out in another worktree
- **THEN** creation reports the conflict without forcing duplicate checkout or changing the active workspace

### Requirement: Editable destination confirmation
The destination prompt SHALL contain the actual editable default after branch selection. Absolute and home-relative overrides SHALL be accepted; relative overrides SHALL resolve against the main checkout. Empty or existing destinations SHALL be rejected without overwriting content. Cancelling branch or destination selection SHALL create no branch, directory, or worktree and SHALL leave the active workspace unchanged.

#### Scenario: Accept the prefilled path
- **WHEN** the user confirms the destination without editing its prefilled value
- **THEN** creation targets exactly the displayed absolute path

#### Scenario: Edit the destination
- **WHEN** the user replaces the default with a different valid absolute path
- **THEN** creation uses that path without moving or renaming the main checkout

#### Scenario: Relative override from a linked checkout
- **WHEN** the main checkout is `/work/client/backend` and the user enters `../review-checkout` while working in a linked checkout
- **THEN** the destination resolves to `/work/client/review-checkout`

#### Scenario: Paths containing spaces
- **WHEN** a valid main checkout or destination contains spaces
- **THEN** the displayed path, created checkout, and subsequent workspace switch preserve the exact path

#### Scenario: Destination occupied or empty input
- **WHEN** the destination names an existing filesystem entry, including a symlink, or the submitted input is empty
- **THEN** creation reports the invalid destination and leaves existing content untouched

#### Scenario: Cancel before creation
- **WHEN** the user cancels either the branch selector or destination prompt
- **THEN** no branch or worktree is created, and cwd, buffers, and saved workspace state remain unchanged

### Requirement: Local-only worktree creation
Managed creation SHALL use available local Git refs and SHALL NOT implicitly fetch, rebase, push, rewrite an existing branch, copy untracked or ignored files, or install project dependencies. Fetching and project setup SHALL remain explicit user actions.

#### Scenario: Repository with a remote
- **WHEN** the user creates a worktree in a repository with an `origin` remote
- **THEN** creation performs no automatic network operation or rebase and does not alter existing branch histories

#### Scenario: Local project setup stays separate
- **WHEN** the source checkout contains an ignored `.env`, virtual environment, or dependency directory
- **THEN** creation does not copy or install it into the new checkout

### Requirement: Worktree operation failure reporting
Managed actions SHALL report invalid repository contexts and failed Git operations explicitly. Creation SHALL enter the workspace transition only after the target is verified as a registered checkout of the same repository. If creation succeeds but switching is cancelled or fails, the new checkout SHALL remain available and its path SHALL be reported without claiming the switch succeeded.

#### Scenario: Outside a repository
- **WHEN** the user invokes a worktree action outside a supported Git checkout
- **THEN** a visible explanation is shown without changing cwd, buffers, or creating a destination

#### Scenario: Git rejects creation
- **WHEN** Git rejects worktree creation
- **THEN** the failure is shown, no target workspace is opened, and any partial Git changes are not hidden or destructively cleaned up

#### Scenario: Checkout exists but transition is cancelled
- **WHEN** creation succeeds and a subsequent workspace preflight is cancelled
- **THEN** the current workspace remains active and the notification identifies the created checkout as available but not opened

### Requirement: Conservative linked-worktree deletion
Managed deletion SHALL require confirmation showing the exact checkout path and branch or detached status. It SHALL protect the main checkout, active checkout, and locked checkouts, and refuse modified, staged, or untracked content, including ignored local files. It SHALL NOT force removal, delete branches, or delete saved editor state.

#### Scenario: Remove a clean inactive checkout
- **WHEN** the user confirms removal of a clean, unlocked, inactive linked checkout
- **THEN** it is removed and the selector refreshes without switching the active workspace or deleting its retained editor state

#### Scenario: Protect the main or active checkout
- **WHEN** the requested removal identifies the main or active checkout, including through a filesystem alias
- **THEN** removal is refused and the checkout remains intact

#### Scenario: Protect local work and locks
- **WHEN** the selected checkout is locked or contains staged, modified, untracked, or ignored local files
- **THEN** removal is refused with a visible explanation and no force attempt is made

#### Scenario: Cancel deletion
- **WHEN** the user declines deletion confirmation
- **THEN** neither the checkout nor any saved editor state is removed

### Requirement: Whole-workspace worktree switching
A switch SHALL replace the whole workspace in the current Neovim instance: it SHALL save the outgoing session through the session backend, if one is enabled, and let every participant flush its state before changing directory, then leave one clean buffer in one window, restore the destination's session and let every participant restore its state. Listed buffers and tabs from the outgoing workspace SHALL NOT leak into the destination.

#### Scenario: Switch between saved workspaces
- **WHEN** checkouts A and B have different saved sessions and the user switches from A to B and back
- **THEN** B's session is restored, A's buffers are no longer listed, and switching back restores A's session

#### Scenario: Select the active checkout
- **WHEN** the user selects the already active checkout
- **THEN** no session save, directory change, buffer teardown or participant hook occurs

#### Scenario: First visit
- **WHEN** the user switches to a checkout with no saved session
- **THEN** the checkout becomes cwd with one clean editing buffer, and participants are still asked to restore their state for it

#### Scenario: No session backend
- **WHEN** no session backend is enabled
- **THEN** a switch still tears down the outgoing workspace and lets participants restore the destination

### Requirement: Unsaved-edit transition guard
Before leaving a workspace, managed creation/switching SHALL detect modified buffers across all tabs and hidden buffers and offer "Save all and switch" or "Cancel", defaulting safely to cancellation. Failed writes and modified unnamed buffers that cannot be saved SHALL prevent teardown. Saved but uncommitted Git changes SHALL NOT by themselves prevent switching.

#### Scenario: Cancel with unsaved edits
- **WHEN** any source buffer is modified and the user cancels the transition
- **THEN** cwd and all source buffers remain active with their edits intact

#### Scenario: Save all before switching
- **WHEN** modified file-backed buffers exist and the user chooses to save all
- **THEN** every modified buffer is written successfully before outgoing state is discarded or cwd changes

#### Scenario: Hidden or unwritable buffer
- **WHEN** a hidden buffer or buffer in another tab cannot be written, or a modified unnamed buffer cannot be saved
- **THEN** switching is aborted with a visible explanation, and no unsaved buffer is discarded

#### Scenario: Saved Git changes remain in their checkout
- **WHEN** the source checkout contains saved, uncommitted changes but no unsaved editor buffers
- **THEN** switching is allowed and those changes remain in the source checkout

#### Scenario: Edits during creation
- **WHEN** the user modifies a source buffer while a worktree creation operation is in progress
- **THEN** the modified-buffer guard is applied again before the subsequent workspace teardown

### Requirement: Live-resource transition guard
A managed transition SHALL refuse to discard live Neovim terminal jobs or, with the dap integration enabled, proceed while a debugging session is active. It SHALL identify the blocking resources without stopping them automatically. External terminal, tmux, server, and AI processes SHALL NOT be relocated or terminated by a workspace switch.

#### Scenario: Live terminal buffer
- **WHEN** a running terminal job would be discarded by the workspace reset
- **THEN** switching is refused with an explanation, and the job remains running in its original workspace

#### Scenario: Active debugger
- **WHEN** any debugging session is active
- **THEN** switching is refused without terminating or retargeting the debug session

#### Scenario: External process remains independent
- **WHEN** a successful switch occurs while an external process exists outside Neovim
- **THEN** the integration does not terminate it or claim its working directory has changed

### Requirement: Recoverable workspace transition failures
A managed switch SHALL abort without changing cwd or discarding source buffers when saving outgoing state fails. A destination restore failure SHALL be reported distinctly from missing state, and recovery to the saved source workspace SHALL be attempted without overwriting destination state. If recovery fails, automatic writes SHALL stop and the user SHALL be told what remains recoverable.

#### Scenario: Outgoing save fails
- **WHEN** the session save or a participant's flush fails before teardown
- **THEN** switching is aborted, the source cwd and buffers remain active, and the error is shown

#### Scenario: Existing target session is broken
- **WHEN** the destination has a session file that fails to restore
- **THEN** the integration reports failure, does not replace the saved destination with an empty success-shaped session, and attempts to recover the saved source workspace

#### Scenario: Recovery also fails
- **WHEN** restoring both the destination and saved source fails
- **THEN** automatic writes are stopped and an error identifies the current directory and recoverable source state instead of announcing successful switching

### Requirement: Serialized actions
Only one managed action SHALL run at a time; a request made while one is running SHALL be refused with a visible explanation, and a cancelled picker SHALL release the action.

#### Scenario: Rapid action requests
- **WHEN** another managed creation, switching, or deletion action is requested before the active action finishes
- **THEN** it is refused with a visible busy explanation rather than interleaving transitions

#### Scenario: Cancelled picker
- **WHEN** the user cancels a picker
- **THEN** a later action is accepted

### Requirement: Participants
Hosts SHALL be able to register named participants whose optional hooks the plugin calls in registration order: `check` (may refuse), `pause`, `flush` (may abort), `reset`, `cleanup`, `restore`, `resume`, `prepare` (before an action reads the repository) and `changed` (after a worktree is created or removed). Registering a second participant with the same name SHALL replace the first.

#### Scenario: Participant state follows the switch
- **WHEN** a participant saves its state in `flush` and re-applies it in `restore`
- **THEN** switching A to B to A brings back A's state for that participant

#### Scenario: A flush failure aborts before teardown
- **WHEN** a participant's `flush` raises
- **THEN** the switch is aborted, the source cwd and buffers remain active, participants are resumed, and the error is shown

#### Scenario: Writes stay paused after an unrecoverable failure
- **WHEN** both the destination restore and the recovery of the source fail
- **THEN** participants are not resumed

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

### Requirement: Events
The plugin SHALL fire `User` autocommands `GitWorktreeCreated` and `GitWorktreeRemoved` with the checkout's path, `GitWorktreeSwitchPre` with the source and destination, and `GitWorktreeSwitched` with the source and the new path after a successful switch.

#### Scenario: Switch events
- **WHEN** the user switches from A to B successfully
- **THEN** `GitWorktreeSwitchPre` fires with A and B before teardown and `GitWorktreeSwitched` fires with A and B afterwards
