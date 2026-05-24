#!/usr/bin/env bash
# boot-managed-sessions.sh
#
# Recreate every managed tmux session declared in the registry, resume agent
# panes that have registry tokens, and optionally attach the sessions in iTerm.
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
      echo "ERROR: unexpected argument: $1" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux || printf /opt/homebrew/bin/tmux)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || printf /usr/bin/jq)}"
REGISTRY_FILE="${REGISTRY_FILE:-$HOME/.tmux-manager/registry.json}"
RECOVER_MANAGED_SESSION="${RECOVER_MANAGED_SESSION:-$SCRIPT_DIR/recover-managed-session.sh}"
LOG_DIR="${LOG_DIR:-$HOME/.tmux/restore-logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/managed-session-boot.log}"
BOOTSTRAP_SESSION="${BOOTSTRAP_SESSION:-0}"
MANAGED_SESSIONS=()

mkdir -p "$LOG_DIR"

log() {
  local message="$*"
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$message" | tee -a "$LOG_FILE"
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

ensure_tmux_started() {
  if tmux_server_running; then
    log "tmux server already running"
    return
  fi

  log "starting tmux bootstrap session=${BOOTSTRAP_SESSION}"
  run "$TMUX_BIN" new-session -d -s "$BOOTSTRAP_SESSION" -c "$HOME"
}

load_managed_sessions() {
  local session_name

  if [[ ! -f "$REGISTRY_FILE" ]]; then
    log "ERROR: missing registry file: $REGISTRY_FILE"
    exit 1
  fi

  while IFS= read -r session_name; do
    [[ -z "$session_name" ]] && continue
    if [[ ! "$session_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
      log "ERROR: unsafe session name from registry: $session_name"
      exit 1
    fi
    MANAGED_SESSIONS+=("$session_name")
  done < <("$JQ_BIN" -r '.sessions[]? | select(.managed == true) | .sessionName' "$REGISTRY_FILE")

  if [[ "${#MANAGED_SESSIONS[@]}" -eq 0 ]]; then
    log "no managed sessions declared in registry"
    exit 0
  fi
}

recover_managed_sessions() {
  local recover_args=()

  if [[ "$MODE" == "dry-run" ]]; then
    recover_args+=(--dry-run)
  fi

  if [[ "$OPEN_ITERM" == "true" ]]; then
    recover_args+=(--open-iterm)
  fi

  log "recovering managed sessions: ${MANAGED_SESSIONS[*]}"
  if [[ "$MODE" == "dry-run" ]]; then
    "$RECOVER_MANAGED_SESSION" "${recover_args[@]}" "${MANAGED_SESSIONS[@]}"
  else
    ASM_SKIP_PREFLIGHT=1 "$RECOVER_MANAGED_SESSION" "${recover_args[@]}" "${MANAGED_SESSIONS[@]}"
  fi
}

preflight_managed_sessions() {
  if [[ "$MODE" == "dry-run" ]]; then
    return
  fi

  log "preflight dry-run for managed sessions"
  "$RECOVER_MANAGED_SESSION" --dry-run "${MANAGED_SESSIONS[@]}"
  log "preflight dry-run passed"
}

main() {
  log "boot managed sessions start mode=$MODE open_iterm=$OPEN_ITERM"
  require_executable "tmux" "$TMUX_BIN"
  require_executable "jq" "$JQ_BIN"
  require_file_executable "managed session recover script" "$RECOVER_MANAGED_SESSION"
  load_managed_sessions
  preflight_managed_sessions
  ensure_tmux_started
  recover_managed_sessions
  log "boot managed sessions complete count=${#MANAGED_SESSIONS[@]}"
}

main "$@"
