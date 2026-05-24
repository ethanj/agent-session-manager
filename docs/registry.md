# Registry Contract

`~/.tmux-manager/registry.json` is the source of truth for managed tmux sessions. Scripts in this repo only act on data declared in that file.

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
- `agentThreadName`: required for agent sessions. Human-readable thread label used for audit and operator matching.
- `startCommand`: command prefix used to build the resume command.
- `resumeToken`: required for agent sessions. This must be the durable CLI resume identifier, not the tmux session name or human thread label.

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

Dry-runs validate these invariants and exit non-zero on ambiguity. Apply-mode recovery runs the same dry-run preflight first and stops before creating tmux sessions if validation fails.

## Reboot Coverage

For full reboot recovery, call `scripts/boot-managed-sessions.sh`. It enumerates all `managed: true` sessions in this registry and passes those names to `recover-managed-session.sh`. Fixed project-specific boot scripts are examples only; they restore only the sessions listed inside those scripts.
