#!/usr/bin/env bash
# boot-tmux-project-windows.sh
#
# Sample multi-session workstation boot. Starts tmux if needed, recovers missing
# registry-backed sessions, restores agents, and opens iTerm. Customize session
# lists and registry entries for your environment.
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

# Example session names — must match entries in ~/.tmux-manager/registry.json
DEMO_TABS=(
  demo-claude1
  demo-claude2
  demo-claude3
  demo-claude4
  demo-codex1
  demo-codex2
  demo-codex3
  demo-term1
  demo-term2
)

CLAUDE_SESSIONS=(
  demo-claude1
  demo-claude2
  demo-claude3
  demo-claude4
)

CODEX_SESSIONS=(
  demo-codex1
  demo-codex2
)

mkdir -p "$LOG_DIR"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$LOG_FILE"
}

require_executable() {
  local label="$1"
  local command_path="$2"

  if ! command -v "$command_path" >/dev/null 2>&1; then
    log "ERROR: missing required executable ${label}: ${command_path}"
    exit 1
  fi
}

require_file_executable() {
  local label="$1"
  local file_path="$2"

  if [[ ! -x "$file_path" ]]; then
    log "ERROR: missing or non-executable ${label}: ${file_path}"
    exit 1
  fi
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

  for session in "${DEMO_TABS[@]}"; do
    if ! session_exists "$session"; then
      missing+=("$session")
    fi
  done

  printf '%s\n' "${missing[@]}"
}

wait_for_registry_sessions() {
  local deadline=$((SECONDS + WAIT_SECONDS))
  local missing

  while (( SECONDS < deadline )); do
    missing="$(missing_sessions)"
    if [[ -z "$missing" ]]; then
      log "all configured tmux sessions exist"
      return
    fi
    sleep 1
  done

  log "ERROR: timed out waiting for sessions: $(missing_sessions | xargs)"
  exit 1
}

recover_missing_sessions() {
  local missing
  local session

  missing="$(missing_sessions)"
  if [[ -z "$missing" ]]; then
    log "all configured tmux sessions exist"
    return
  fi

  while IFS= read -r session; do
    [[ -z "$session" ]] && continue
    log "recovering missing session: $session"
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
    demo-claude*)
      [[ "$command" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
      ;;
    demo-codex*)
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
      log "known agents are running from registry resume IDs"
      return
    fi
    sleep 2
  done

  log "ERROR: timed out waiting for known agents to run"
  exit 1
}

demo_clients_attached() {
  "$TMUX_BIN" list-clients -F '#{session_name}' 2>/dev/null | grep -Eq '^demo-'
}

open_iterm_workstation_window() {
  if [[ "$MODE" != "dry-run" ]] && demo_clients_attached; then
    log "tmux clients already attached for demo sessions; skipping duplicate iTerm window"
    return
  fi

  log "opening iTerm window with workstation tabs"
  run "$OPEN_ITERM_SCRIPT" --apply --tabs "${DEMO_TABS[@]}"
}

main() {
  log "boot project windows start mode=$MODE"
  require_executable "tmux" "$TMUX_BIN"
  require_file_executable "agent restore hook" "$RESTORE_AGENTS"
  require_file_executable "managed session recover script" "$RECOVER_MANAGED_SESSION"
  require_file_executable "iTerm open script" "$OPEN_ITERM_SCRIPT"
  ensure_tmux_started
  if [[ "$MODE" != "dry-run" ]]; then
    recover_missing_sessions
    wait_for_registry_sessions
  else
    log "DRY-RUN: would recover and wait for sessions: ${DEMO_TABS[*]}"
  fi
  wait_for_known_agents
  open_iterm_workstation_window
  log "boot project windows complete"
}

main "$@"
