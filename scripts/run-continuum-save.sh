#!/usr/bin/env bash
# run-continuum-save.sh
#
# Timer-safe tmux save wrapper. It refuses to write snapshots until the current
# tmux server has been marked restore-complete, preventing login/reboot races
# from overwriting the last good pre-crash snapshot with a partial bootstrap.
set -u

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# tmux 3.6a strips TAB bytes out of -F format strings when the process has no
# locale set (the launchd default). tmux-resurrect's save.sh depends on tabs as
# field delimiters, so under launchd it silently writes an unparseable file
# that valid_resurrect_file then deletes. Force a UTF-8 locale here so the
# wrapper's child save scripts produce real snapshots.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

TMUX_BIN="${TMUX_BIN:-$(command -v tmux || printf /opt/homebrew/bin/tmux)}"
LOG_DIR="${LOG_DIR:-$HOME/.tmux/restore-logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/continuum-save-agent.log}"
CONTINUUM_SAVE_SCRIPT="${CONTINUUM_SAVE_SCRIPT:-$HOME/.tmux/plugins/tmux-continuum/scripts/continuum_save.sh}"
RESURRECT_SAVE_SCRIPT="${RESURRECT_SAVE_SCRIPT:-$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh}"
RESURRECT_DIR="${RESURRECT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect}"
RESTORE_GUARD_DIR="${RESTORE_GUARD_DIR:-$HOME/.tmux/restore-guard}"
READY_FILE="${RESTORE_GUARD_DIR}/save-ready-server-pid"
LAST_KNOWN_GOOD_LINK="${RESURRECT_DIR}/last-known-good"
STALE_GRACE_SECONDS="${STALE_GRACE_SECONDS:-120}"

mkdir -p "$LOG_DIR"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG_FILE"
}

latest_name() {
  readlink "${RESURRECT_DIR}/last" 2>/dev/null || true
}

latest_age_seconds() {
  local latest="$1"
  if [[ -n "$latest" && -f "${RESURRECT_DIR}/${latest}" ]]; then
    printf '%s\n' "$(($(date +%s) - $(stat -f %m "${RESURRECT_DIR}/${latest}")))"
  else
    printf '%s\n' 999999999
  fi
}

# Newest tmux_resurrect_*.txt file on disk, by mtime. Used to recover when a
# save script created a fresh file but failed to advance the `last` symlink.
newest_snapshot_name() {
  local newest
  newest="$(ls -t "${RESURRECT_DIR}"/tmux_resurrect_*.txt 2>/dev/null | head -1)"
  [[ -n "$newest" ]] && basename "$newest"
}

snapshot_mtime() {
  local name="$1"
  if [[ -n "$name" && -f "${RESURRECT_DIR}/${name}" ]]; then
    stat -f %m "${RESURRECT_DIR}/${name}"
  else
    printf '0\n'
  fi
}

valid_snapshot_name() {
  local latest="$1"
  local path="${RESURRECT_DIR}/${latest}"
  [[ -n "$latest" && -s "$path" ]] &&
    grep -q $'^pane\t' "$path" &&
    grep -q $'^window\t' "$path" &&
    grep -q $'^state\t' "$path"
}

update_last_known_good() {
  local snapshot_name="$1"
  local tmp_link="${LAST_KNOWN_GOOD_LINK}.tmp.$$"

  rm -f "$tmp_link"
  ln -s "$snapshot_name" "$tmp_link" &&
    mv -f "$tmp_link" "$LAST_KNOWN_GOOD_LINK"
}

autosave_allowed_for_current_server() {
  local server_pid ready_pid

  server_pid="$("$TMUX_BIN" display-message -p '#{pid}' 2>/dev/null || true)"
  if [[ -z "$server_pid" ]]; then
    log "skip unreadable-tmux-server-pid"
    return 1
  fi

  ready_pid="$(cat "$READY_FILE" 2>/dev/null || true)"
  if [[ "$ready_pid" != "$server_pid" ]]; then
    log "skip restore-not-complete server_pid=${server_pid} ready_pid=${ready_pid:-none}"
    return 1
  fi
}

run_save_script() {
  local save_path

  save_path="$("$TMUX_BIN" show-option -gqv @resurrect-save-script-path 2>/dev/null || true)"
  if [[ -z "$save_path" ]]; then
    "$TMUX_BIN" set-option -gq @resurrect-save-script-path "$RESURRECT_SAVE_SCRIPT"
  fi

  if [[ -x "$CONTINUUM_SAVE_SCRIPT" ]]; then
    "$CONTINUUM_SAVE_SCRIPT"
  fi

  local after_continuum
  after_continuum="$(latest_name)"
  if valid_snapshot_name "$after_continuum" && [[ "$(latest_age_seconds "$after_continuum")" -le "$max_age_seconds" ]]; then
    return 0
  fi

  if [[ ! -x "$RESURRECT_SAVE_SCRIPT" ]]; then
    log "ERROR missing-resurrect-save-script path=${RESURRECT_SAVE_SCRIPT}"
    return 1
  fi

  log "fallback-direct-resurrect-save"
  local direct_output direct_rc
  direct_output="$("$RESURRECT_SAVE_SCRIPT" quiet 2>&1)"
  direct_rc=$?
  if [[ $direct_rc -ne 0 || -n "$direct_output" ]]; then
    log "direct-resurrect-save rc=${direct_rc} output=${direct_output:-none}"
  fi
  return $direct_rc
}

# If save scripts produced a fresh valid snapshot but did not point `last` at
# it (rare race or a stale symlink), promote the newest file ourselves so
# downstream restores see it.
promote_newest_if_needed() {
  local current_after="$1"
  local before_mtime="$2"
  local newest newest_mtime
  newest="$(newest_snapshot_name)"
  if [[ -z "$newest" || "$newest" == "$current_after" ]]; then
    return 1
  fi
  newest_mtime="$(snapshot_mtime "$newest")"
  if [[ "$newest_mtime" -le "$before_mtime" ]]; then
    return 1
  fi
  if ! valid_snapshot_name "$newest"; then
    return 1
  fi
  local tmp_link="${RESURRECT_DIR}/last.tmp.$$"
  rm -f "$tmp_link"
  ln -s "$newest" "$tmp_link" && mv -f "$tmp_link" "${RESURRECT_DIR}/last"
  log "promoted newest=${newest} previous=${current_after:-none}"
  return 0
}

if ! command -v "$TMUX_BIN" >/dev/null 2>&1; then
  log "skip missing-tmux path=${TMUX_BIN}"
  exit 0
fi

if ! "$TMUX_BIN" list-sessions >/dev/null 2>&1; then
  log "skip no-tmux-server"
  exit 0
fi

if ! autosave_allowed_for_current_server; then
  exit 0
fi

before="$(latest_name)"
before_mtime="$(snapshot_mtime "$before")"
interval_minutes="$("$TMUX_BIN" show-option -gqv @continuum-save-interval 2>/dev/null || true)"
if [[ -z "$interval_minutes" || ! "$interval_minutes" =~ ^[0-9]+$ || "$interval_minutes" -le 0 ]]; then
  interval_minutes=15
fi
max_age_seconds=$((interval_minutes * 60 + STALE_GRACE_SECONDS))
initial_age="$(latest_age_seconds "$before")"

if [[ "$initial_age" -gt "$max_age_seconds" ]]; then
  "$TMUX_BIN" set-option -gq @continuum-save-last-timestamp 0
  log "forcing-stale-save before=${before:-none} age_seconds=${initial_age} max_age_seconds=${max_age_seconds}"
fi

save_rc=0
run_save_script || save_rc=$?

after="$(latest_name)"
if [[ "$after" == "$before" ]]; then
  if promote_newest_if_needed "$after" "$before_mtime"; then
    after="$(latest_name)"
  fi
fi
latest="${RESURRECT_DIR}/${after}"

if valid_snapshot_name "$after"; then
  final_age="$(latest_age_seconds "$after")"
  if [[ "$final_age" -le "$max_age_seconds" ]]; then
    update_last_known_good "$after"
    newest_on_disk="$(newest_snapshot_name)"
    log "saved before=${before:-none} after=${after} newest=${newest_on_disk:-none} bytes=$(stat -f %z "$latest") age_seconds=${final_age} save_rc=${save_rc}"
    exit 0
  fi
  newest_on_disk="$(newest_snapshot_name)"
  log "ERROR stale-latest before=${before:-none} after=${after} newest=${newest_on_disk:-none} age_seconds=${final_age} max_age_seconds=${max_age_seconds} save_rc=${save_rc}"
  exit 1
fi

newest_on_disk="$(newest_snapshot_name)"
if [[ "$save_rc" -ne 0 ]]; then
  log "ERROR save-script-failed before=${before:-none} after=${after:-none} newest=${newest_on_disk:-none} save_rc=${save_rc}"
else
  log "ERROR invalid-latest before=${before:-none} after=${after:-none} newest=${newest_on_disk:-none} save_rc=${save_rc}"
fi
exit 1
