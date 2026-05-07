# Operations

Use these scripts for deterministic recovery of managed tmux agent sessions. The intended operator loop is inspect, dry-run, apply, then verify.

## Recover One Session

```bash
scripts/recover-managed-session.sh --dry-run demo-codex1
scripts/recover-managed-session.sh demo-codex1
```

Expected healthy no-op output (commands and paths depend on your registry):

```text
exists session=demo-codex1
healthy session=demo-codex1 command=codex
restore hook skipped; sessions already healthy
verified session=demo-codex1 pane=codex /path/to/your/workspace
```

The healthy path is intentionally re-entrant. If pane `0.0` is already running a non-shell command, the restore hook is skipped.

## Recover Then Attach

```bash
scripts/recover-managed-session.sh --open-iterm demo-codex1
scripts/recover-managed-session.sh --open-iterm demo-codex1 demo-codex2
```

`open-iterm-sessions.sh` never creates tmux sessions. It only attaches existing sessions with:

```text
tmux -CC new -A -s <session>
```

## Restore Agents Directly

```bash
scripts/restore-agent-sessions.sh demo-codex1
scripts/restore-agent-sessions.sh
```

With no session arguments, the restore script scans all managed registry sessions. With arguments, it limits scope to those session names.

## Sample Workstation Example

`examples/sample-workstation/boot-tmux-project-windows.sh` is an optional orchestration example, not core library behavior. It starts tmux if needed, recovers missing sessions listed in the script, waits for those sessions, restores agents from the registry, and opens one iTerm window with tabs when clients are not already attached. Edit the session lists and your registry to match your setup.

## Failure Modes

- Missing `~/.tmux-manager/registry.json`: recovery fails, restore logs a skip.
- Missing `tmux` or `jq`: scripts fail before changing sessions.
- Missing managed registry entry: recovery fails for that session.
- Unsafe session name: recovery fails before invoking tmux.
- Missing cwd: recovery fails before creating a session.
- Missing resume token: the agent pane is left as-is.
- Existing non-shell pane: restore is skipped because the agent is considered already running.
- Existing shell pane with token: restore sends the resume command into pane `0.0`.
- Missing iTerm dependency: iTerm attach fails before opening windows.

## Validation

```bash
make test
bash -n scripts/recover-managed-session.sh
bash -n scripts/restore-agent-sessions.sh
bash -n scripts/open-iterm-sessions.sh
bash -n examples/sample-workstation/boot-tmux-project-windows.sh
scripts/recover-managed-session.sh --dry-run demo-codex1
examples/sample-workstation/boot-tmux-project-windows.sh --dry-run
```
