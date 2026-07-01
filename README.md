# byobu-session-state

Small deterministic snapshot/restore helper for Byobu sessions using the tmux
backend.

It captures:
- tmux/Byobu windows
- pane counts
- pane layouts, which preserve split orientation and sizing
- pane current working directories
- active window and active panes
- foreground pane command lines, when detectable
- Codex tab metadata from `byobu-codex`, so Codex tabs can resume by session id

It does not capture:
- running processes
- scrollback
- command history beyond what your shell already saves

Restore uses `byobu-tmux` when available so restored sessions are initialized
with Byobu keybindings and status configuration rather than plain tmux defaults.
By default, restore opens fresh shells. Restarting saved pane commands is
available as an explicit opt-in. Codex tabs created or adopted with
`byobu-codex` are different: they resume by default with
`codex resume SESSION_ID` because that is a bounded, validated restore action
rather than replaying an arbitrary shell command.

## Install

```bash
git clone https://github.com/CochranResearchGroup/byobu-session-state.git
cd byobu-session-state
./install.sh
```

This installs:

```text
~/.local/lib/byobu-session-state/bin/byobu-session-state
~/.local/lib/byobu-session-state/bin/byobu-session-plan
~/.local/lib/byobu-session-state/bin/byobu
~/.local/lib/byobu-session-state/bin/byobu-codex
~/.local/lib/byobu-session-state/bin/byobu-remote
~/.local/lib/byobu-session-state/bin/byobu-git-sync
~/.local/bin/byobu-session-state -> ~/.local/lib/byobu-session-state/bin/byobu-session-state
~/.local/bin/byobu-session-plan -> ~/.local/lib/byobu-session-state/bin/byobu-session-plan
~/.local/bin/byobu -> ~/.local/lib/byobu-session-state/bin/byobu
~/.local/bin/byobu-codex -> ~/.local/lib/byobu-session-state/bin/byobu-codex
~/.local/bin/byobu-remote -> ~/.local/lib/byobu-session-state/bin/byobu-remote
~/.local/bin/byobu-git-sync -> ~/.local/lib/byobu-session-state/bin/byobu-git-sync
~/.config/systemd/user/byobu-session-autorestore.service
~/.config/systemd/user/byobu-session-autosave.service
~/.config/systemd/user/byobu-session-autosave.timer
~/.config/systemd/user/byobu-session-watchdog.service
~/.config/systemd/user/byobu-session-watchdog.timer
~/.config/systemd/user/byobu-session-shutdown-save.service
~/.config/systemd/user/byobu-git-sync-push.service
~/.config/systemd/user/byobu-git-sync-push.timer
~/.config/systemd/user/byobu-git-sync-pull.service
~/.config/systemd/user/byobu-git-sync-pull.timer
```

Make sure `~/.local/bin` is on your `PATH`.

The installed `~/.local/bin/byobu` wrapper restores the latest autosave snapshot
before handing off to the real Byobu binary. That makes a normal `byobu` launch
after a computer restart reopen the saved windows instead of creating an empty
session first.

When user systemd is available, the installer enables:
- a one-minute autosave timer
- a one-minute watchdog timer that diagnoses disappeared tmux sessions and
  restores them when no capacity-related cause is found
- a git checkpoint/push timer that scans live Byobu tabs every 30 minutes
- a git pull timer that scans live Byobu tabs once a day at 09:00 local time
- a save-on-user-service-start/stop hook
- a startup autorestore hook that restores the `autosave` snapshot only when no
  live tmux sessions already exist

## Usage

Check the installed version:

```bash
byobu-session-state --version
```

Save the current attached Byobu/tmux session:

```bash
byobu-session-state save
```

Save the current session with an explicit snapshot name:

```bash
byobu-session-state save work
```

Save a specific session:

```bash
byobu-session-state save work mysession
```

Autosave the attached or most recently active tmux/Byobu session:

```bash
byobu-session-state autosave
```

Restore a snapshot:

```bash
byobu-session-state restore work
```

Preview exactly what a restore would create without creating any tmux sessions:

```bash
byobu-session-state restore --dry-run work
```

Restore a snapshot but leave Codex tabs as shells:

```bash
byobu-session-state restore --no-restart-codex work
```

Restore the autosave snapshot only when no live tmux sessions exist:

```bash
byobu-session-state autorestore
```

Preview the autorestore decision and autosave manifest plan:

```bash
byobu-session-state autorestore --dry-run
```

Dry-run restore planning is parsed by the installed Python helper
`byobu-session-plan`, so preview commands do not need to source snapshot shell
files.

Record a watchdog heartbeat, or restore after all tmux sessions disappear when
no capacity evidence is present:

```bash
byobu-session-state watchdog
```

Launch Byobu and automatically restore saved windows first:

```bash
byobu
```

Restore a snapshot and restart detected foreground pane commands:

```bash
byobu-session-state restore --restart-processes work
```

You can also opt in with an environment variable:

```bash
BYOBU_SESSION_RESTART_PROCESSES=1 byobu-session-state restore work
```

Restore under a different target session name:

```bash
byobu-session-state restore work work-restored
```

List snapshots:

```bash
byobu-session-state list
```

Show snapshots and live sessions/windows:

```bash
byobu-session-state status
```

Validate the default autosave snapshot, manifest, and referenced per-session
snapshots:

```bash
byobu-session-state validate
```

Validate a named snapshot:

```bash
byobu-session-state validate work
```

Run a full health check for installed commands, timers, lock state, autosave
restore plan, stale per-session autosave snapshots, watchdog state, and live
tmux sessions:

```bash
byobu-session-state doctor
```

Preview cleanup of unreferenced per-session autosave snapshots:

```bash
byobu-session-state prune
```

Delete only those unreferenced per-session autosave snapshot artifacts:

```bash
byobu-session-state prune --delete
```

Show the last watchdog recovery decision:

```bash
byobu-session-state incidents
```

## Codex Tabs

Use `byobu-codex` to create Codex tabs that can come back after tmux, Byobu,
WSL, or the machine restarts.

Add a new Codex tab to the current or most recent Byobu session:

```bash
byobu-codex add --name "Lab Notebook" --cd ~/projects/lab-notebook-agent
```

Start a new Codex tab with an initial prompt:

```bash
byobu-codex add --name "New Goal" -- "work on the next goal"
```

Open a new tab for a known Codex session id:

```bash
byobu-codex resume --name "Illustrator" 019f1075-142d-7ff1-b822-a1a07395d955
```

Adopt already-running Codex tabs so future autosaves can restore them by thread
id:

```bash
byobu-codex adopt --dry-run
byobu-codex adopt
```

List tagged tabs and recent Codex threads:

```bash
byobu-codex list
```

`byobu-codex` tags each tab with tmux window metadata. `byobu-session-state`
saves that metadata and, on restore, starts the tab with:

```bash
codex --sandbox danger-full-access --ask-for-approval never resume SESSION_ID
```

New Codex tabs use the same permission policy. This is intentional: Byobu
Codex tabs are treated as operator-owned long-running local agents, so they
start with unrestricted filesystem access and no approval prompts. The launch
policy lives in `bin/byobu-codex` in `codex_permission_args`; run `./install.sh`
after editing it so `~/.local/lib/byobu-session-state/bin/byobu-codex` stays in
sync with the source tree.

To roll this back, remove or change `codex_permission_args`, remove
`approval_policy = "never"` and `sandbox_mode = "danger-full-access"` from
`~/.codex/config.toml` if those defaults are not wanted globally, then run
`./install.sh`.

The wrapper also supervises the Codex process inside the tab. If Codex exits
with a nonzero status and the wrapper knows the session id, it restarts the tab
with the same full-permission `codex resume` command. If Codex exits normally,
the Byobu tab remains open as a shell instead of disappearing.

When restoring multiple autosaved sessions, each Codex thread id is started at
most once by default. If duplicate tabs point at the same thread, the preferred
primary session gets the running Codex process and the duplicate tabs are
restored as tagged shells. Set `BYOBU_SESSION_DEDUP_CODEX_RESTORE=0` for a
one-off restore that intentionally starts every tagged Codex tab.

## Git Autosync

`byobu-git-sync` keeps a dedicated git mirror of all live Byobu/tmux tabs and
also syncs any git repositories visible in pane working directories. The default
tab mirror target is:

```text
https://github.com/1bak3r/byobu-tabs.git
```

The installer enables:

- `byobu-git-sync-push.timer`, which runs every 30 minutes
- `byobu-git-sync-pull.timer`, which runs daily at 09:00 local time

Push runs write the live tab manifest and per-session `byobu-session-state`
snapshots into `~/.local/state/byobu-git-sync/byobu-tabs-repo`, commit them, and
push them to `1bak3r/byobu-tabs`. They also create a checkpoint commit when a
visible repository has uncommitted or untracked changes, then push that
repository's current branch.

Pull runs fast-forward the local `byobu-tabs` checkout, then also checkpoint and
fast-forward any visible git repositories when that can be done without a merge
conflict. Repositories in the middle of a merge, rebase, cherry-pick, or revert
are skipped.

By default, only remotes on `github.com` are touched. To allow other remotes for
one run:

```bash
BYOBU_GIT_SYNC_ALLOW_NON_GITHUB=1 byobu-git-sync push
```

Useful manual commands:

```bash
byobu-git-sync repos
byobu-git-sync status
byobu-git-sync tabs --dry-run
byobu-git-sync push --dry-run
byobu-git-sync pull --dry-run
```

Logs are stored in:

```text
~/.local/state/byobu-git-sync/byobu-git-sync.log
```

## Exit Watchdog

`byobu-session-state watchdog` is designed for a user-systemd timer. While tmux
sessions exist, it records a small heartbeat in:

```text
~/.local/state/byobu-session-state/autosave.watchdog.state
~/.local/state/byobu-session-state/autosave.watchdog.sessions.tsv
```

If a later watchdog run finds no live tmux sessions after a prior live
heartbeat, it writes a diagnostic log to:

```text
~/.local/state/byobu-session-state/autosave.watchdog.log
```

Each disappearance record includes the last live tmux sessions, whether the WSL
boot id changed, and matching journal lines for tmux, Byobu, crashes, signals,
shutdowns, and OOM events when the journal has them.

The latest decision is also summarized as structured fields in:

```text
~/.local/state/byobu-session-state/autosave.watchdog.incident.tsv
```

Print it with:

```bash
byobu-session-state incidents
```

The watchdog skips restore when it finds capacity-related evidence, including
kernel OOM log lines, very low current memory, or very low disk space for the
snapshot directory. The memory and disk thresholds can be adjusted:

```bash
BYOBU_SESSION_CAPACITY_MIN_MEM_MB=1024 byobu-session-state watchdog
BYOBU_SESSION_CAPACITY_MIN_DISK_MB=512 byobu-session-state watchdog
```

When no capacity evidence is found, the watchdog runs the same safe restore path
as `autorestore --restart-codex autosave`, which rebuilds saved Byobu windows
and resumes tagged Codex tabs by session id.

## Tailscale Remote Attach

This helper is meant for picking up the same live Byobu/tmux windows from
another computer on your tailnet:

```bash
ssh -t -p 2222 bak3r@desktop-gdjcaft ~/.local/bin/byobu-remote
```

`byobu-remote` runs a safe autorestore first, then attaches to the attached or
most recently active live Byobu/tmux session. It does not ask Byobu to create a
second sibling session when the workspace is already attached somewhere else. It
will not replace or restore over an existing live tmux session. Codex tabs are
resumed when autorestore runs.

To force a specific session name:

```bash
ssh -t -p 2222 bak3r@desktop-gdjcaft 'BYOBU_REMOTE_SESSION=byobu ~/.local/bin/byobu-remote'
```

To inspect the current state without attaching:

```bash
ssh -p 2222 bak3r@desktop-gdjcaft ~/.local/bin/byobu-remote status
```

Snapshots are stored in:

```text
~/.local/state/byobu-session-state/
```

Override that location with:

```bash
BYOBU_SESSION_STATE_DIR=/path/to/snapshots byobu-session-state save work
```

## Limitations

This tool restores a session shape, not a live process tree. Restored panes open
fresh shells in the saved working directories unless the pane is a tagged
`byobu-codex` tab or `--restart-processes` is used. It does not restore shell
variables, scrollback, command output, or unsaved editor state.

Live processes do remain visible from another computer when that computer SSHes
into the original host over Tailscale and attaches to the same tmux server. A
reboot still stops those processes; after reboot, the saved window layout and
working directories can be restored.

Pane layouts are captured with tmux's `window_layout` value. The smoke test
verifies split orientation, sizing, and pane paths on current tmux/Byobu, but
small differences can still occur across tmux versions or very different
terminal sizes.

Process restart is best-effort. The tool saves the deepest detectable child
process command line for each pane, or the pane process command line when tmux
started the pane with a direct command. That works for simple foreground
commands such as `vim file.txt` or `npm run dev`, but it may miss commands
launched through wrappers, nested shells, job control, or process supervisors.

## Snapshot Safety

Snapshot files are shell files that `restore` sources. Only restore snapshots
you created or reviewed. The tool writes snapshots with mode `0600` and refuses
to restore group- or world-writable snapshots.

Snapshot writes and restores are serialized with an atomic state lock at
`~/.local/state/byobu-session-state/.state.lock`. This prevents the autosave
timer, watchdog timer, manual saves, and restore commands from interleaving
updates to the same snapshot set. Set `BYOBU_SESSION_LOCK_TIMEOUT_SECONDS` to
adjust the wait time, or `BYOBU_SESSION_DISABLE_LOCK=1` for one-off debugging.

`doctor` is read-only and shows the current autosave restore plan. `prune`
defaults to dry-run and only targets per-session autosave artifacts such as
`autosave.session.NAME.snapshot`, `.last-good.snapshot`, and
`.previous.snapshot` when they are no longer referenced by the current autosave
manifest. It does not remove named snapshots, history, or rejected snapshots.

`validate` is also read-only. It checks snapshot ownership and mode, shell
syntax, schema version, required window and pane fields, active indexes, Codex
thread-id shape and duplicates, manifest references, and missing current working
directories. Missing cwd paths are warnings because restore falls back to
`$HOME`; structural snapshot and manifest problems are errors.

`--restart-processes` sends saved command lines into restored panes as keyboard
input. Review a snapshot before using it if there is any chance it was edited or
came from another machine.

Codex resume is constrained to UUID-like session ids saved from tmux window
metadata. Use `--no-restart-codex` if you want a structural restore without
starting Codex.

## Uninstall

```bash
./uninstall.sh
```

The uninstall script removes the installed helper and symlink. It does not remove
saved snapshots.

## Dependencies

Required:
- `bash`
- `tmux`

Recommended:
- `byobu`

On Ubuntu:

```bash
sudo apt-get install -y byobu tmux
```

## Development

Run the local checks:

```bash
make test
```

The test suite creates temporary tmux sessions and removes them when it exits.
