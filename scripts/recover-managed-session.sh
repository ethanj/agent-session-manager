#!/usr/bin/env bash
# recover-managed-session.sh
#
# Recreate one or more managed tmux sessions from the tmux-manager registry,
# restore only panes that need an agent resume command, and verify final state.
set -euo pipefail

MODE="apply"
OPEN_ITERM=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --open-iterm)
      OPEN_ITERM=true
      shift
      ;;
    --help|-h)
      sed -n '1,80p' "$0"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ "$#" -eq 0 ]]; then
  echo "ERROR: provide at least one managed tmux session name." >&2
  exit 1
fi

TMUX_BIN="${TMUX_BIN:-$(command -v tmux || printf /opt/homebrew/bin/tmux)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || printf /usr/bin/jq)}"
REGISTRY_FILE="${REGISTRY_FILE:-$HOME/.tmux-manager/registry.json}"
RESTORE_AGENTS="${RESTORE_AGENTS:-$HOME/.tmux/restore-agent-sessions.sh}"
OPEN_ITERM_SCRIPT="${OPEN_ITERM_SCRIPT:-$HOME/.claws/shared/open-atomic-iterm.sh}"
LOG_DIR="${LOG_DIR:-$HOME/.tmux/restore-logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/managed-session-recover.log}"
RESTORE_TARGETS=()

mkdir -p "$LOG_DIR"

require_executable() {
  local label="$1"
  local command_path="$2"

  if ! command -v "$command_path" >/dev/null 2>&1; then
    echo "ERROR: missing required executable ${label}: ${command_path}" >&2
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

log() {
  local message="$*"
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$message" | tee -a "$LOG_FILE"
}

run() {
  if [[ "$MODE" == "dry-run" ]]; then
    log "DRY-RUN: $*"
  else
    "$@"
  fi
}

session_exists() {
  "$TMUX_BIN" has-session -t "$1" 2>/dev/null
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

pane_current_command() {
  "$TMUX_BIN" display-message -pt "${1}:0.0" -F '#{pane_current_command}' 2>/dev/null || true
}

mark_restore_target() {
  RESTORE_TARGETS+=("$1")
}

registry_row() {
  local session_name="$1"
  "$JQ_BIN" -er --arg session_name "$session_name" '
    . as $root
    | (first($root.sessions[]? | select(.sessionName == $session_name and .managed == true)) // empty) as $session
    | (first($root.projects[]? | select(.id == ($session.projectId // ""))) // {}) as $project
    | (first($root.instances[]? | select(.id == ($project.instanceId // ""))) // {}) as $instance
    | ($session.cwd // ($project.repoRoots[0]? // null) // ($instance.workspaceRoot // null) // env.HOME) as $cwd
    | [
        $session.sessionName,
        $cwd,
        ($session.agentKind // ""),
        ($session.resumeToken // ""),
        ($session.startCommand // "")
      ]
    | @tsv
  ' "$REGISTRY_FILE"
}

recover_session() {
  local requested_name="$1"
  local row session_name cwd agent_kind resume_token start_command
  local current_command session_was_created

  if [[ ! -f "$REGISTRY_FILE" ]]; then
    log "ERROR: missing registry file: $REGISTRY_FILE"
    exit 1
  fi

  if ! row="$(registry_row "$requested_name")"; then
    log "ERROR: no managed registry entry for session=${requested_name}"
    exit 1
  fi

  IFS=$'\t' read -r session_name cwd agent_kind resume_token start_command <<< "$row"

  if [[ ! "$session_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    log "ERROR: unsafe session name from registry: $session_name"
    exit 1
  fi

  if [[ ! -d "$cwd" ]]; then
    log "ERROR: registry cwd does not exist for session=${session_name}: $cwd"
    exit 1
  fi

  session_was_created=false
  if session_exists "$session_name"; then
    log "exists session=${session_name}"
  else
    log "creating session=${session_name} cwd=${cwd}"
    run "$TMUX_BIN" new-session -d -s "$session_name" -c "$cwd"
    session_was_created=true
  fi

  if [[ -n "$agent_kind" && -z "$resume_token" ]]; then
    log "agent session=${session_name} has no resume token; leaving shell/session as-is"
  elif [[ -n "$agent_kind" && -n "$start_command" ]]; then
    if [[ "$session_was_created" == "true" ]]; then
      log "restore needed session=${session_name} kind=${agent_kind} reason=created"
      mark_restore_target "$session_name"
      return 0
    fi

    current_command="$(pane_current_command "$session_name")"
    if [[ -z "$current_command" ]]; then
      log "ERROR: unreadable pane for existing session=${session_name}"
      exit 1
    fi

    if is_shell_command "$current_command"; then
      log "restore needed session=${session_name} kind=${agent_kind} reason=shell command=${current_command}"
      mark_restore_target "$session_name"
    else
      log "healthy session=${session_name} command=${current_command}"
    fi
  fi
}

verify_recovered_sessions() {
  local session pane_state

  if [[ "$MODE" == "dry-run" ]]; then
    log "dry-run complete sessions=$*"
    return 0
  fi

  for session in "$@"; do
    if ! session_exists "$session"; then
      log "ERROR: session missing after recovery session=${session}"
      exit 1
    fi

    pane_state="$("$TMUX_BIN" display-message -pt "${session}:0.0" -F '#{pane_current_command} #{pane_current_path}')"
    log "verified session=${session} pane=${pane_state}"
  done
}

recover_all() {
  local session

  require_executable "tmux" "$TMUX_BIN"
  require_executable "jq" "$JQ_BIN"

  for session in "$@"; do
    recover_session "$session"
  done

  if [[ "${#RESTORE_TARGETS[@]}" -gt 0 ]]; then
    if [[ "$MODE" != "dry-run" ]]; then
      require_file_executable "agent restore hook" "$RESTORE_AGENTS"
    fi
    log "running agent restore hook targets=${RESTORE_TARGETS[*]}"
    run "$RESTORE_AGENTS" "${RESTORE_TARGETS[@]}"
  else
    log "restore hook skipped; sessions already healthy"
  fi

  if [[ "$OPEN_ITERM" == "true" ]]; then
    if [[ "$MODE" != "dry-run" ]]; then
      require_file_executable "iTerm open script" "$OPEN_ITERM_SCRIPT"
    fi
    if [[ "$#" -eq 1 ]]; then
      run "$OPEN_ITERM_SCRIPT" --apply "$1"
    else
      run "$OPEN_ITERM_SCRIPT" --apply --tabs "$@"
    fi
  fi

  verify_recovered_sessions "$@"
}

recover_all "$@"
