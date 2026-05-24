# Operations

Use these scripts for deterministic recovery of managed tmux agent sessions. The intended operator loop is inspect, dry-run, apply, then verify. Apply-mode recovery runs the same dry-run validation before mutating tmux state.

## Recover All Managed Sessions

```bash
scripts/boot-managed-sessions.sh --dry-run
scripts/boot-managed-sessions.sh
scripts/boot-managed-sessions.sh --open-iterm
```

This is the reboot-oriented entrypoint. It reads every `managed: true` session from `~/.tmux-manager/registry.json`, runs a dry-run preflight for the full registry set, starts a bootstrap tmux server if needed, calls `recover-managed-session.sh`, and lets the recover script invoke agent resume only where needed. If the preflight reports any registry issue, apply mode stops before creating sessions.

Agent sessions must declare both `agentThreadName` and `resumeToken`. `agentThreadName` is the human label; `resumeToken` is the durable CLI resume identifier. Dry-run fails if `resumeToken` is missing or is just the session/thread name, because that can resume an older or unrelated agent thread.

Expected preflight failure shape:

```text
ERROR: agent session=demo-codex1 missing resumeToken
ERROR: agent session=demo-codex2 resumeToken must be durable id, not session/thread name
dry-run validation failed errors=2
```

Fix the registry before rerunning apply mode. Do not temporarily replace a missing durable ID with the tmux session name; that hides the error and can resume the wrong thread.

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

This hook is intentionally strict. It exits non-zero when a targeted agent is missing `agentThreadName`, missing `resumeToken`, or has a name-based `resumeToken`. That keeps tmux-resurrect post-restore hooks from silently sending unsafe resume commands into shell panes.

## Sample Workstation Example

`examples/sample-workstation/boot-tmux-project-windows.sh` is an optional orchestration example, not core library behavior. It starts tmux if needed, recovers missing sessions listed in the script, waits for those sessions, restores agents from the registry, and opens one iTerm window with tabs when clients are not already attached. Edit the session lists and your registry to match your setup.

## Failure Modes

- Missing `~/.tmux-manager/registry.json`: recovery fails, restore logs a skip.
- Missing `tmux` or `jq`: scripts fail before changing sessions.
- Missing managed registry entry: recovery fails for that session.
- Unsafe session name: recovery fails before invoking tmux.
- Missing cwd: recovery fails before creating a session.
- Missing `agentThreadName` or `resumeToken`: dry-run fails before recovery.
- Ambiguous resume token equal to the session or thread name: dry-run fails before recovery.
- Direct restore hook with unsafe agent registry data: restore exits non-zero and logs the specific session.
- Existing non-shell pane: restore is skipped because the agent is considered already running.
- Existing shell pane with token: restore sends the resume command into pane `0.0`.
- Missing iTerm dependency: iTerm attach fails before opening windows.

## Updating Resume IDs

When a user renames a tmux session or agent thread, update `agentThreadName` as the label and keep `resumeToken` as the durable CLI resume ID. If the durable ID is unknown, leave `resumeToken` empty and let dry-run fail until the real ID is known. The scripts do not search local agent stores or guess IDs from names.

## Validation

```bash
make test
bash -n scripts/recover-managed-session.sh
bash -n scripts/restore-agent-sessions.sh
bash -n scripts/open-iterm-sessions.sh
bash -n examples/sample-workstation/boot-tmux-project-windows.sh
scripts/recover-managed-session.sh --dry-run demo-codex1
scripts/boot-managed-sessions.sh --dry-run
examples/sample-workstation/boot-tmux-project-windows.sh --dry-run
```
