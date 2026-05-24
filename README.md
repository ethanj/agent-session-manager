# Agent Session Manager

Deterministic tmux session recovery for long-running AI agent panes, with a
fail-closed registry preflight before apply-mode recovery.

The manager treats `~/.tmux-manager/registry.json` as the only source of truth for:

- managed tmux session names
- project working directories
- agent kind (`codex` or `claude-code`)
- agent thread name for operator/audit matching
- startup command
- durable resume token

It does not discover, infer, or search for resume tokens. `agentThreadName` is a
label; `resumeToken` must be the durable CLI resume identifier accepted by the
agent CLI. Keep real registry files and tokens out of version control.

## Install

Clone or unpack this repository, then symlink the scripts used by your local launch or boot hooks (adjust paths to match your machine):

```bash
REPO_ROOT="/path/to/agent-session-manager"

ln -sf "$REPO_ROOT/scripts/recover-managed-session.sh" ~/.tmux/recover-managed-session.sh
ln -sf "$REPO_ROOT/scripts/restore-agent-sessions.sh" ~/.tmux/restore-agent-sessions.sh
ln -sf "$REPO_ROOT/scripts/open-iterm-sessions.sh" ~/.tmux/open-iterm-sessions.sh
ln -sf "$REPO_ROOT/scripts/boot-managed-sessions.sh" ~/.tmux/boot-managed-sessions.sh
```

The generic scripts require `bash`, `tmux`, and `jq`. Opening iTerm tabs additionally requires macOS `osascript` and iTerm.

`recover-managed-session.sh` defaults `OPEN_ITERM_SCRIPT` to `~/.tmux/open-iterm-sessions.sh`, which matches the symlink above. Override `OPEN_ITERM_SCRIPT` if you store the opener elsewhere.

## Safety Contract

Run dry-run first whenever the registry changes:

```bash
scripts/boot-managed-sessions.sh --dry-run
```

Apply-mode recovery runs the same dry-run preflight before creating tmux
sessions, sending resume commands, or opening iTerm tabs. If any managed agent
session is missing `agentThreadName`, missing `resumeToken`, or uses a
session/thread name as the resume token, recovery exits non-zero and does not
continue.

This matters because tmux session names and human thread names are not durable
agent conversation IDs. Using names as resume values can resume stale or
unrelated agent threads.

## Recovery Contract

Recover one managed session:

```bash
scripts/recover-managed-session.sh demo-codex1
```

Recover and attach in iTerm:

```bash
scripts/recover-managed-session.sh --open-iterm demo-codex1
```

Recover every managed registry session after a reboot:

```bash
scripts/boot-managed-sessions.sh
scripts/boot-managed-sessions.sh --open-iterm
```

Dry run one session or the full registry:

```bash
scripts/recover-managed-session.sh --dry-run demo-codex1
scripts/boot-managed-sessions.sh --dry-run
```

The command is re-entrant. If the tmux session exists and pane `0.0` is already running a non-shell agent command, it does not call the restore hook. It only verifies:

```text
exists session=demo-codex1
healthy session=demo-codex1 command=codex
restore hook skipped; sessions already healthy
verified session=demo-codex1 pane=codex /path/to/workspace
```

If a managed session is missing, recovery reads the registry entry, resolves its cwd in deterministic order, creates the tmux session, restores only that target when needed, and verifies the final pane state.

## Scripts

- `scripts/boot-managed-sessions.sh` enumerates every `managed: true` registry session, starts tmux if needed, and delegates recovery for the full set.
- `scripts/recover-managed-session.sh` recreates missing managed tmux sessions, restores only sessions that need agent resume, and verifies final pane state.
- `scripts/restore-agent-sessions.sh` starts registry-declared agent resume commands only when pane `0.0` is still a shell, and refuses unsafe missing or name-based resume IDs.
- `scripts/open-iterm-sessions.sh` opens existing tmux sessions in iTerm control mode.
- `examples/sample-workstation/boot-tmux-project-windows.sh` is an optional orchestration example that wires the above together for a multi-session layout.

The scripts are configurable through environment variables:

- `TMUX_BIN`
- `JQ_BIN`
- `REGISTRY_FILE`
- `RESTORE_AGENTS`
- `OPEN_ITERM_SCRIPT`
- `OSASCRIPT_BIN`
- `LOG_DIR`
- `LOG_FILE`
- `BOOTSTRAP_SESSION`

## Registry Shape

See `examples/registry.example.json` and `docs/registry.md`. Do not commit real resume tokens.

## Operations

Operator procedures and failure modes are documented in `docs/operations.md`.

Run deterministic checks before committing:

```bash
make test
```

## License

MIT — see `LICENSE`.
