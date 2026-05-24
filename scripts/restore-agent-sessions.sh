#!/usr/bin/env bash
# restore-agent-sessions.sh
#
# Start declared Claude and Codex agent sessions when tmux has restored a pane
# as a shell. The registry is the only source of resume IDs.
set -euo pipefail

TMUX_BIN="${TMUX_BIN:-$(command -v tmux || printf /opt/homebrew/bin/tmux)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || printf /usr/bin/jq)}"
REGISTRY_FILE="${REGISTRY_FILE:-$HOME/.tmux-manager/registry.json}"
LOG_DIR="${LOG_DIR:-$HOME/.tmux/restore-logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/agent-restore.log}"
TARGET_SESSIONS=("$@")
REGISTRY_DELIMITER=$'\037'

mkdir -p "$LOG_DIR"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG_FILE"
}

require_executable() {
  local label="$1"
  local command_path="$2"

  if ! command -v "$command_path" >/dev/null 2>&1; then
    log "ERROR: missing required executable ${label}: ${command_path}"
    exit 1
  fi
}

is_shell_command() {
  case "$1" in
    bash|dash|fish|sh|zsh)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

build_resume_command() {
  local agent_kind="$1"
  local start_command="$2"
  local resume_token="$3"

  case "$agent_kind" in
    claude-code)
      printf '%s --resume %q\n' "$start_command" "$resume_token"
      ;;
    codex)
      printf '%s resume %q\n' "$start_command" "$resume_token"
      ;;
    *)
      return 1
      ;;
  esac
}

restore_agent_session() {
  local session_name="$1"
  local agent_kind="$2"
  local start_command="$3"
  local resume_token="$4"
  local agent_thread_name="$5"
  local target="${session_name}:0.0"
  local resume_command current_command

  if [[ -z "$agent_thread_name" ]]; then
    log "ERROR missing-agent-thread-name session=${session_name}"
    return 1
  fi

  if [[ -z "$resume_token" ]]; then
    log "ERROR missing-resume-token session=${session_name}"
    return 1
  fi

  if [[ "$resume_token" == "$session_name" || "$resume_token" == "$agent_thread_name" ]]; then
    log "ERROR ambiguous-resume-token session=${session_name}"
    return 1
  fi

  resume_command="$(build_resume_command "$agent_kind" "$start_command" "$resume_token")"

  if ! "$TMUX_BIN" has-session -t "$session_name" 2>/dev/null; then
    log "skip missing session=${session_name}"
    return 0
  fi

  current_command="$("$TMUX_BIN" display-message -pt "$target" -F '#{pane_current_command}' 2>/dev/null || true)"
  if [[ -z "$current_command" ]]; then
    log "skip unreadable-pane session=${session_name}"
    return 0
  fi

  if ! is_shell_command "$current_command"; then
    log "skip already-running session=${session_name} command=${current_command}"
    return 0
  fi

  "$TMUX_BIN" send-keys -t "$target" -l -- "$resume_command"
  "$TMUX_BIN" send-keys -t "$target" Enter
  log "started session=${session_name} agentKind=${agent_kind} startCommand=${start_command}"
}

should_restore_session() {
  local session_name="$1"
  local target

  if [[ "${#TARGET_SESSIONS[@]}" -eq 0 ]]; then
    return 0
  fi

  for target in "${TARGET_SESSIONS[@]}"; do
    if [[ "$target" == "$session_name" ]]; then
      return 0
    fi
  done

  return 1
}

main() {
  if [[ ! -f "$REGISTRY_FILE" ]]; then
    log "skip missing-registry path=${REGISTRY_FILE}"
    return 0
  fi

  require_executable "tmux" "$TMUX_BIN"
  require_executable "jq" "$JQ_BIN"

  "$JQ_BIN" -r '
    .sessions[]
    | select(.managed == true)
    | select(.agentKind == "claude-code" or .agentKind == "codex")
    | select((.startCommand // "") != "")
    | [.sessionName, .agentKind, .startCommand, (.resumeToken // ""), (.agentThreadName // "")]
    | join("\u001f")
  ' "$REGISTRY_FILE" |
    while IFS="$REGISTRY_DELIMITER" read -r session_name agent_kind start_command resume_token agent_thread_name; do
      [[ -z "$session_name" || -z "$start_command" ]] && continue
      should_restore_session "$session_name" || continue
      restore_agent_session "$session_name" "$agent_kind" "$start_command" "$resume_token" "$agent_thread_name"
    done
}

main "$@"
