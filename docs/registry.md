# Registry Contract

`~/.tmux-manager/registry.json` is the source of truth for managed tmux sessions. Scripts in this repo only act on data declared in that file. Agent labels and durable resume IDs are intentionally separate fields.

## Top-Level Collections

- `instances`: workspace-level metadata. `workspaceRoot` is the final cwd fallback.
- `projects`: project metadata. `repoRoots[0]` is the project cwd fallback.
- `sessions`: tmux sessions managed by the recovery scripts.

## Managed Session Fields

- `sessionName`: tmux session name. Recovery accepts only `A-Z`, `a-z`, `0-9`, `_`, `.`, and `-`.
- `managed`: must be `true` for recovery and restore scripts to act on the session.
- `projectId`: links the session to a project for cwd fallback.
- `cwd`: optional session-specific working directory. This wins over all fallback roots.
- `agentKind`: optional. Only `codex` and `claude-code` are restored as agent panes.
- `agentThreadName`: required for agent sessions. Human-readable thread label used for audit and operator matching. This may match the tmux session name.
- `startCommand`: command prefix used to build the resume command.
- `resumeToken`: required for agent sessions. This must be the durable CLI resume identifier, not the tmux session name or human thread label. Leave it empty when unknown so dry-run blocks recovery.

## cwd Resolution

When `recover-managed-session.sh` creates a missing session, cwd is resolved in this order:

1. `session.cwd`
2. `project.repoRoots[0]`
3. `instance.workspaceRoot`
4. `HOME`

The resolved directory must exist. Missing directories are treated as operator errors.

## Resume Rules

Resume tokens are never discovered or guessed. The restore script only resumes registry-declared sessions where:

- `managed` is `true`
- `agentKind` is `codex` or `claude-code`
- `agentThreadName` is non-empty
- `startCommand` is non-empty
- `resumeToken` is non-empty
- `resumeToken` differs from both `sessionName` and `agentThreadName`
- tmux session exists
- pane `0.0` is currently a shell

Do not commit real registry files or real resume tokens. Keep committed examples generic.

Dry-runs validate these invariants and exit non-zero on ambiguity. Apply-mode recovery runs the same dry-run preflight first and stops before creating tmux sessions if validation fails. The direct `restore-agent-sessions.sh` hook enforces the same missing-token and name-based-token checks before sending any resume command.

## Example Agent Session

```json
{
  "sessionName": "demo-codex1",
  "scope": "project",
  "projectId": "demo-project",
  "agentKind": "codex",
  "role": "agent worker",
  "managed": true,
  "agentThreadName": "demo-codex1",
  "startCommand": "codex --dangerously-bypass-approvals-and-sandbox",
  "resumeToken": "REPLACE_WITH_DURABLE_CODEX_RESUME_ID"
}
```

`agentThreadName` can be a convenient operator label. `resumeToken` must be whatever the agent CLI requires for exact resume. If those values are the same, recovery treats the entry as unsafe and fails dry-run.

## Reboot Coverage

For full reboot recovery, call `scripts/boot-managed-sessions.sh`. It enumerates all `managed: true` sessions in this registry and passes those names to `recover-managed-session.sh`. Fixed project-specific boot scripts are examples only; they restore only the sessions listed inside those scripts.

## Snapshot Safety

The restore snapshot and the registry serve different roles. Tmux-resurrect
snapshots recreate tmux topology; this registry decides which restored shell
panes may receive agent resume commands.

In practice:

- Snapshot answers: "What tmux sessions/windows/panes existed at this point in time?"
- Registry answers: "Which sessions are managed, where should missing ones start, and which exact agent resume IDs are safe?"
- Restore order is snapshot first, registry second. Restore the tmux topology, then use the registry to validate and resume only safe agent panes.
- A session in the snapshot but not in the registry can still be recreated by tmux-resurrect, but it will not receive registry-driven agent resume.
- A session in the registry but not in the snapshot can be recreated by `recover-managed-session.sh` if its cwd and agent metadata validate.
- A restored pane that is already running a non-shell process is treated as healthy; the registry is not used to send a resume command into it.
- A restored pane that is just a shell may receive a resume command only when the registry has a non-ambiguous durable `resumeToken`.

At reboot/login time, choose the snapshot before creating or saving new tmux
state. The autosave wrapper maintains a `last-known-good` symlink beside
tmux-resurrect's `last` symlink and only advances it after the current tmux
server has been marked restore-complete. Restore flows should prefer
`last-known-good`, falling back to `last` only when no valid known-good snapshot
exists.
