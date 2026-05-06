#!/usr/bin/env bash
# boot-tmux-project-windows.sh
#
# AtomicMemory-style boot example. Starts tmux if needed, recovers missing
# project sessions from the registry, restores known agents, and opens iTerm.
set -euo pipefail

MODE="apply"
if [[ "${1:-}" == "--dry-run" ]]; then
  MODE="dry-run"
  shift
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux || printf /opt/homebrew/bin/tmux)}"
OPEN_ITERM_SCRIPT="${OPEN_ITERM_SCRIPT:-$REPO_ROOT/scripts/open-iterm-sessions.sh}"
RESTORE_AGENTS="${RESTORE_AGENTS:-$REPO_ROOT/scripts/restore-agent-sessions.sh}"
RECOVER_MANAGED_SESSION="${RECOVER_MANAGED_SESSION:-$REPO_ROOT/scripts/recover-managed-session.sh}"
LOG_DIR="${LOG_DIR:-$HOME/.tmux/restore-logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/project-window-boot.log}"
BOOTSTRAP_SESSION="${BOOTSTRAP_SESSION:-0}"
WAIT_SECONDS="${WAIT_SECONDS:-90}"

ATOMIC_TABS=(
  atomic-claude1
  atomic-claude2
  atomic-claude3
  atomic-claude4
  atomic-codex1
  atomic-codex2
  atomic-codex3
  atomic-term1
  atomic-term2
)

CLAUDE_SESSIONS=(
  atomic-claude1
  atomic-claude2
  atomic-claude3
  atomic-claude4
)

CODEX_SESSIONS=(
  atomic-codex1
  atomic-codex2
)

mkdir -p "$LOG_DIR"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$LOG_FILE"
}

run() {
  if [[ "$MODE" == "dry-run" ]]; then
    log "DRY-RUN: $*"
  else
    "$@"
  fi
}

tmux_server_running() {
  "$TMUX_BIN" list-sessions >/dev/null 2>&1
}

session_exists() {
  "$TMUX_BIN" has-session -t "$1" 2>/dev/null
}

current_command() {
  "$TMUX_BIN" display-message -pt "$1:0.0" -F '#{pane_current_command}' 2>/dev/null || true
}

is_shell_command() {
  case "$1" in
    bash|dash|fish|sh|zsh|"")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_tmux_started() {
  if tmux_server_running; then
    log "tmux server already running"
    return
  fi

  log "starting tmux bootstrap session"
  run "$TMUX_BIN" new-session -d -s "$BOOTSTRAP_SESSION" -c "$HOME"
}

missing_sessions() {
  local missing=()
  local session

  for session in "${ATOMIC_TABS[@]}"; do
    if ! session_exists "$session"; then
      missing+=("$session")
    fi
  done

  printf '%s\n' "${missing[@]}"
}

wait_for_atomic_sessions() {
  local deadline=$((SECONDS + WAIT_SECONDS))
  local missing

  while (( SECONDS < deadline )); do
    missing="$(missing_sessions)"
    if [[ -z "$missing" ]]; then
      log "all Atomic tmux sessions exist"
      return
    fi
    sleep 1
  done

  log "ERROR: timed out waiting for Atomic sessions: $(missing_sessions | xargs)"
  exit 1
}

recover_missing_atomic_sessions() {
  local missing
  local session

  missing="$(missing_sessions)"
  if [[ -z "$missing" ]]; then
    log "all Atomic tmux sessions exist"
    return
  fi

  while IFS= read -r session; do
    [[ -z "$session" ]] && continue
    log "recovering missing Atomic session: $session"
    run "$RECOVER_MANAGED_SESSION" "$session"
  done <<< "$missing"
}

agent_is_ready() {
  local session="$1"
  local command

  command="$(current_command "$session")"
  if is_shell_command "$command"; then
    return 1
  fi

  case "$session" in
    atomic-claude*)
      [[ "$command" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
      ;;
    atomic-codex*)
      [[ "$command" == codex* ]]
      ;;
    *)
      return 1
      ;;
  esac
}

all_known_agents_ready() {
  local session

  for session in "${CLAUDE_SESSIONS[@]}" "${CODEX_SESSIONS[@]}"; do
    if ! agent_is_ready "$session"; then
      return 1
    fi
  done
}

wait_for_known_agents() {
  local deadline=$((SECONDS + WAIT_SECONDS))

  while (( SECONDS < deadline )); do
    run "$RESTORE_AGENTS"
    if [[ "$MODE" == "dry-run" ]]; then
      log "DRY-RUN: would wait for Claude/Codex resume commands to become live"
      return
    fi
    if all_known_agents_ready; then
      log "known Atomic agents are running from registry resume IDs"
      return
    fi
    sleep 2
  done

  log "ERROR: timed out waiting for known Atomic agents to run"
  exit 1
}

atomic_clients_attached() {
  "$TMUX_BIN" list-clients -F '#{session_name}' 2>/dev/null | grep -Eq '^atomic-'
}

open_atomic_window() {
  if [[ "$MODE" != "dry-run" ]] && atomic_clients_attached; then
    log "Atomic tmux clients already attached; skipping duplicate iTerm window"
    return
  fi

  log "opening Atomic iTerm project window"
  run "$OPEN_ITERM_SCRIPT" --apply --tabs "${ATOMIC_TABS[@]}"
}

main() {
  log "boot project windows start mode=$MODE"
  ensure_tmux_started
  if [[ "$MODE" != "dry-run" ]]; then
    recover_missing_atomic_sessions
    wait_for_atomic_sessions
  else
    log "DRY-RUN: would recover and wait for Atomic sessions: ${ATOMIC_TABS[*]}"
  fi
  wait_for_known_agents
  open_atomic_window
  log "boot project windows complete"
}

main "$@"
