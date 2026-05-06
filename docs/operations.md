# Operations

Use these scripts for deterministic recovery of managed tmux agent sessions. The intended operator loop is inspect, dry-run, apply, then verify.

## Recover One Session

```bash
scripts/recover-managed-session.sh --dry-run atomic-codex2
scripts/recover-managed-session.sh atomic-codex2
```

Expected healthy no-op output:

```text
exists session=atomic-codex2
healthy session=atomic-codex2 command=codex-aarch64-a
restore hook skipped; sessions already healthy
verified session=atomic-codex2 pane=codex-aarch64-a /Users/ethan/projects/supernet/atomicmemory
```

The healthy path is intentionally re-entrant. If pane `0.0` is already running a non-shell command, the restore hook is skipped.

## Recover Then Attach

```bash
scripts/recover-managed-session.sh --open-iterm atomic-codex2
scripts/recover-managed-session.sh --open-iterm atomic-codex1 atomic-codex2
```

`open-iterm-sessions.sh` never creates tmux sessions. It only attaches existing sessions with:

```text
tmux -CC new -A -s <session>
```

## Restore Agents Directly

```bash
scripts/restore-agent-sessions.sh atomic-codex2
scripts/restore-agent-sessions.sh
```

With no session arguments, the restore script scans all managed registry sessions. With arguments, it limits scope to those session names.

## Atomic Example

`examples/atomic/boot-tmux-project-windows.sh` is an AtomicMemory-style orchestration example, not generic product behavior. It starts tmux if needed, recovers missing Atomic sessions, waits for known Atomic sessions, restores known agents, and opens one iTerm window with Atomic tabs when clients are not already attached.

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
bash -n examples/atomic/boot-tmux-project-windows.sh
scripts/recover-managed-session.sh --dry-run atomic-codex2
examples/atomic/boot-tmux-project-windows.sh --dry-run
```
