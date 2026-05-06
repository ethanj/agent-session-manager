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
- `startCommand`: command prefix used to build the resume command.
- `resumeToken`: required to resume an agent. Sessions without it are left as shells.

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
- `startCommand` is non-empty
- `resumeToken` is non-empty
- tmux session exists
- pane `0.0` is currently a shell

Do not commit real registry files or real resume tokens. Keep committed examples generic.
