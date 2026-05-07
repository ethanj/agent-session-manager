#!/usr/bin/env bash
# open-iterm-sessions.sh
#
# Open existing tmux sessions inside iTerm using tmux control mode.
set -euo pipefail

say() { printf '%s\n' "$*"; }

MODE="dry-run"
if [[ "${1:-}" == "--apply" ]]; then
  MODE="apply"
  shift
fi

DEFAULT_SESSION="${DEFAULT_SESSION:-demo-term1}"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux || printf /opt/homebrew/bin/tmux)}"
TABBED_MODE=false

require_executable() {
  local label="$1"
  local command_path="$2"

  if ! command -v "$command_path" >/dev/null 2>&1; then
    echo "ERROR: missing required executable ${label}: ${command_path}" >&2
    exit 1
  fi
}

if [[ "${1:-}" == "--tabs" ]]; then
  TABBED_MODE=true
  shift
fi

if [[ "$TABBED_MODE" == "true" && "$#" -eq 0 ]]; then
  echo "ERROR: --tabs requires at least one session name." >&2
  exit 1
fi

if [[ "$TABBED_MODE" == "false" && "$#" -gt 1 ]]; then
  echo "ERROR: single-session mode accepts at most one session name. Use --tabs for multiple sessions." >&2
  exit 1
fi

SESSIONS=("$@")
if [[ "$TABBED_MODE" == "false" && "${#SESSIONS[@]}" -eq 0 ]]; then
  SESSIONS=("$DEFAULT_SESSION")
fi

require_executable "tmux" "$TMUX_BIN"

validate_sessions() {
  local missing=0
  local session

  for session in "$@"; do
    if [[ ! "$session" =~ ^[A-Za-z0-9_.-]+$ ]]; then
      say "  INVALID: $session"
      missing=1
    elif "$TMUX_BIN" has-session -t "$session" 2>/dev/null; then
      say "  EXISTS: $session"
    else
      say "  MISSING: $session"
      missing=1
    fi
  done

  return "$missing"
}

if [[ "$MODE" != "apply" ]]; then
  if [[ "$TABBED_MODE" == "true" ]]; then
    say "[DRY-RUN] Would open one iTerm window with tabs for:"
  else
    say "[DRY-RUN] Would open one iTerm window for:"
  fi
  printf '  %s\n' "${SESSIONS[@]}"
  say "The script will run tmux -CC new -A -s <session> in each tab."
  say "Pre-requisite: tmux sessions must already exist."
  validate_sessions "${SESSIONS[@]}" || true
  exit 0
fi

if ! validate_sessions "${SESSIONS[@]}"; then
  say "ERROR: one or more tmux sessions are missing. Create them before opening iTerm tabs."
  exit 1
fi

require_executable "osascript" "${OSASCRIPT_BIN:-osascript}"

open_single_session() {
  export TARGET_SESSION_NAME="$1"
  export TMUX_ATTACH_BIN="$TMUX_BIN"

  "${OSASCRIPT_BIN:-osascript}" <<'APPLESCRIPT'
on run
  set sessionName to system attribute "TARGET_SESSION_NAME"
  set tmuxBin to system attribute "TMUX_ATTACH_BIN"
  set attachCommand to tmuxBin & " -CC new -A -s " & sessionName
  tell application "iTerm"
    activate
    create window with default profile command attachCommand
  end tell
end run
APPLESCRIPT
}

open_tabbed_sessions() {
  local joined_sessions=""
  local session

  for session in "$@"; do
    if [[ "$session" == *"|"* ]]; then
      say "ERROR: session names cannot contain '|': $session"
      exit 1
    fi
    if [[ -z "$joined_sessions" ]]; then
      joined_sessions="$session"
    else
      joined_sessions="${joined_sessions}|${session}"
    fi
  done

  export TARGET_SESSION_NAMES="$joined_sessions"
  export TMUX_ATTACH_BIN="$TMUX_BIN"

  "${OSASCRIPT_BIN:-osascript}" <<'APPLESCRIPT'
on run
  set sessionNamesRaw to system attribute "TARGET_SESSION_NAMES"
  set tmuxBin to system attribute "TMUX_ATTACH_BIN"
  set oldDelimiters to AppleScript's text item delimiters
  set AppleScript's text item delimiters to "|"
  set sessionNames to text items of sessionNamesRaw
  set AppleScript's text item delimiters to oldDelimiters

  tell application "iTerm"
    activate
    set firstSessionName to item 1 of sessionNames
    set firstAttachCommand to tmuxBin & " -CC new -A -s " & firstSessionName
    set createdWindow to (create window with default profile command firstAttachCommand)
    delay 0.5

    repeat with i from 2 to count of sessionNames
      set sessionName to item i of sessionNames
      set attachCommand to tmuxBin & " -CC new -A -s " & sessionName
      create tab with default profile createdWindow command attachCommand
      delay 0.5
    end repeat
  end tell
end run
APPLESCRIPT
}

if [[ "$TABBED_MODE" == "true" ]]; then
  open_tabbed_sessions "${SESSIONS[@]}"
  say "Opened one iTerm window with ${#SESSIONS[@]} tmux tabs."
else
  open_single_session "${SESSIONS[0]}"
  say "Opened iTerm for session: ${SESSIONS[0]}"
fi
