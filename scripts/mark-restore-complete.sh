#!/usr/bin/env bash
# mark-restore-complete.sh
#
# Mark the current tmux server as safe for timer-driven autosaves. Use this at
# the end of a successful restore/login boot flow.
set -euo pipefail

MODE="apply"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --help|-h)
      sed -n '1,80p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unexpected argument: $1" >&2
      exit 1
      ;;
  esac
done

TMUX_BIN="${TMUX_BIN:-$(command -v tmux || printf /opt/homebrew/bin/tmux)}"
RESTORE_GUARD_DIR="${RESTORE_GUARD_DIR:-$HOME/.tmux/restore-guard}"
READY_FILE="${RESTORE_GUARD_DIR}/save-ready-server-pid"

if ! command -v "$TMUX_BIN" >/dev/null 2>&1; then
  echo "ERROR: missing tmux: $TMUX_BIN" >&2
  exit 1
fi

server_pid="$("$TMUX_BIN" display-message -p '#{pid}' 2>/dev/null || true)"
if [[ -z "$server_pid" ]]; then
  echo "ERROR: tmux server is not available" >&2
  exit 1
fi

if [[ "$MODE" == "dry-run" ]]; then
  echo "DRY-RUN: would mark tmux server safe for autosave pid=${server_pid}"
  exit 0
fi

mkdir -p "$RESTORE_GUARD_DIR"
printf '%s\n' "$server_pid" > "$READY_FILE"
echo "marked tmux server safe for autosave pid=${server_pid}"
