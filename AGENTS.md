# Workspace Notes (Agent Session Manager)

This repository is a small **bash** toolkit: no Node, Python app, or bundled package manager is required for the core scripts.

## Running checks

- `make test` runs `tests/run.sh` (bash syntax, JSON validation, optional shellcheck, dry-run smoke tests).

## Conventions

- Real `~/.tmux-manager/registry.json` content and resume tokens must not be committed. Examples belong in `examples/` only.
- Prefer deterministic behavior: scripts read the registry as the sole source of truth and do not guess tokens or paths.

## Filenames and layout

- `scripts/` — production shell entrypoints intended for symlinking or direct execution.
- `docs/` — operator and registry contract documentation.
- `examples/sample-workstation/` — optional multi-session boot orchestration; customize session names to match your registry.
