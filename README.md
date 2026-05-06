# Agent Session Manager

Deterministic tmux session recovery for long-running AI agent panes.

The manager treats `~/.tmux-manager/registry.json` as the only source of truth for:

- managed tmux session names
- project working directories
- agent kind (`codex` or `claude-code`)
- startup command
- resume token

It does not discover, infer, or search for resume tokens. Real local registry files should stay outside this repo.

## Install

Keep this repo as the editable source, then symlink the scripts used by local launch/boot hooks:

```bash
ln -sf /Users/ethan/projects/supernet/agent-session-manager/scripts/recover-managed-session.sh ~/.tmux/recover-managed-session.sh
ln -sf /Users/ethan/projects/supernet/agent-session-manager/scripts/restore-agent-sessions.sh ~/.tmux/restore-agent-sessions.sh
ln -sf /Users/ethan/projects/supernet/agent-session-manager/scripts/open-iterm-sessions.sh ~/.claws/shared/open-atomic-iterm.sh
```

The generic scripts require `bash`, `tmux`, and `jq`. Opening iTerm tabs additionally requires macOS `osascript` and iTerm.

## Recovery Contract

Recover one managed session:

```bash
scripts/recover-managed-session.sh atomic-codex2
```

Recover and attach in iTerm:

```bash
scripts/recover-managed-session.sh --open-iterm atomic-codex2
```

Dry run:

```bash
scripts/recover-managed-session.sh --dry-run atomic-codex2
```

The command is re-entrant. If the tmux session exists and pane `0.0` is already running a non-shell agent command, it does not call the restore hook. It only verifies:

```text
exists session=atomic-codex2
healthy session=atomic-codex2 command=codex-aarch64-a
restore hook skipped; sessions already healthy
verified session=atomic-codex2 pane=codex-aarch64-a /path/to/workspace
```

If a managed session is missing, recovery reads the registry entry, resolves its cwd in deterministic order, creates the tmux session, restores only that target when needed, and verifies the final pane state.

## Scripts

- `scripts/recover-managed-session.sh` recreates missing managed tmux sessions, restores only sessions that need agent resume, and verifies final pane state.
- `scripts/restore-agent-sessions.sh` starts registry-declared agent resume commands only when pane `0.0` is still a shell.
- `scripts/open-iterm-sessions.sh` opens existing tmux sessions in iTerm control mode.
- `examples/atomic/boot-tmux-project-windows.sh` is the current AtomicMemory-style boot orchestration example.

The scripts are configurable through environment variables:

- `TMUX_BIN`
- `JQ_BIN`
- `REGISTRY_FILE`
- `RESTORE_AGENTS`
- `OPEN_ITERM_SCRIPT`
- `OSASCRIPT_BIN`
- `LOG_DIR`
- `LOG_FILE`

## Registry Shape

See `examples/registry.example.json` and `docs/registry.md`. Do not commit real resume tokens.

## Operations

Operator procedures and failure modes are documented in `docs/operations.md`.

Run deterministic checks before committing:

```bash
make test
```
