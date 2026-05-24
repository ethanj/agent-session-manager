#!/usr/bin/env bash
# tmux-snapshot-selector.sh
#
# List, preview, and select tmux-resurrect snapshots. Preview output avoids full
# pane command lines because those can contain resume tokens or private args.
set -euo pipefail

MODE="list"
SELECTOR=""
ASSUME_YES=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --list)
      MODE="list"
      shift
      ;;
    --preview)
      MODE="preview"
      SELECTOR="${2:-}"
      if [[ -z "$SELECTOR" ]]; then
        echo "ERROR: --preview requires a snapshot selector" >&2
        exit 1
      fi
      shift 2
      ;;
    --select)
      MODE="select"
      SELECTOR="${2:-}"
      if [[ -z "$SELECTOR" ]]; then
        echo "ERROR: --select requires a snapshot selector" >&2
        exit 1
      fi
      shift 2
      ;;
    --yes|-y)
      ASSUME_YES=true
      shift
      ;;
    --help|-h)
      sed -n '1,120p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unexpected argument: $1" >&2
      exit 1
      ;;
  esac
done

RESURRECT_DIR="${RESURRECT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect}"
LAST_LINK="${RESURRECT_DIR}/last"
LAST_KNOWN_GOOD_LINK="${RESURRECT_DIR}/last-known-good"

snapshot_files() {
  find "$RESURRECT_DIR" -type f -name 'tmux_resurrect_*.txt' -print 2>/dev/null |
    while IFS= read -r file_path; do
      printf '%s\t%s\n' "$(stat -f '%m' "$file_path")" "$file_path"
    done |
    sort -rn |
    cut -f2-
}

snapshot_counts() {
  local file_path="$1"
  awk -F '\t' '
    /^pane\t/ { panes++; sessions[$2] = 1 }
    /^window\t/ { windows++ }
    /^state\t/ { states++ }
    END {
      for (session in sessions) unique_sessions++
      printf "%d\t%d\t%d\t%d\n", panes + 0, windows + 0, states + 0, unique_sessions + 0
    }
  ' "$file_path"
}

snapshot_validity() {
  local panes="$1"
  local windows="$2"
  local states="$3"

  if [[ "$panes" -gt 0 && "$windows" -gt 0 && "$states" -gt 0 ]]; then
    printf 'good'
  else
    printf 'bad'
  fi
}

link_marker() {
  local file_path="$1"
  local base_name
  local markers=()

  base_name="$(basename "$file_path")"
  if [[ "$(readlink "$LAST_LINK" 2>/dev/null || true)" == "$base_name" ]]; then
    markers+=("last")
  fi
  if [[ "$(readlink "$LAST_KNOWN_GOOD_LINK" 2>/dev/null || true)" == "$base_name" ]]; then
    markers+=("last-known-good")
  fi

  if [[ "${#markers[@]}" -eq 0 ]]; then
    printf '-'
  else
    local IFS=','
    printf '%s' "${markers[*]}"
  fi
}

list_snapshots() {
  local index=1
  local file_path panes windows states unique_sessions validity marker mtime

  printf 'index\tvalidity\tpanes\twindows\tstate\tunique_sessions\tmtime\tmarker\tfile\n'
  while IFS= read -r file_path; do
    [[ -n "$file_path" ]] || continue
    IFS=$'\t' read -r panes windows states unique_sessions < <(snapshot_counts "$file_path")
    validity="$(snapshot_validity "$panes" "$windows" "$states")"
    marker="$(link_marker "$file_path")"
    mtime="$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$file_path")"
    printf '%d\t%s\t%d\t%d\t%d\t%d\t%s\t%s\t%s\n' \
      "$index" "$validity" "$panes" "$windows" "$states" "$unique_sessions" "$mtime" "$marker" "$file_path"
    index=$((index + 1))
  done < <(snapshot_files)
}

resolve_snapshot() {
  local selector="$1"
  local index=1
  local file_path

  case "$selector" in
    last)
      file_path="${RESURRECT_DIR}/$(readlink "$LAST_LINK" 2>/dev/null || true)"
      ;;
    last-known-good|lkg)
      file_path="${RESURRECT_DIR}/$(readlink "$LAST_KNOWN_GOOD_LINK" 2>/dev/null || true)"
      ;;
    /*|.*)
      file_path="$selector"
      ;;
    tmux_resurrect_*.txt)
      file_path="${RESURRECT_DIR}/${selector}"
      ;;
    ''|*[!0-9]*)
      file_path=""
      ;;
    *)
      while IFS= read -r file_path; do
        if [[ "$index" -eq "$selector" ]]; then
          printf '%s\n' "$file_path"
          return 0
        fi
        index=$((index + 1))
      done < <(snapshot_files)
      file_path=""
      ;;
  esac

  if [[ -n "${file_path:-}" && -f "$file_path" ]]; then
    printf '%s\n' "$file_path"
    return 0
  fi

  echo "ERROR: snapshot not found for selector: $selector" >&2
  exit 1
}

preview_snapshot() {
  local file_path="$1"
  local panes windows states unique_sessions validity marker mtime

  IFS=$'\t' read -r panes windows states unique_sessions < <(snapshot_counts "$file_path")
  validity="$(snapshot_validity "$panes" "$windows" "$states")"
  marker="$(link_marker "$file_path")"
  mtime="$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$file_path")"

  printf 'snapshot=%s\n' "$file_path"
  printf 'validity=%s panes=%d windows=%d state=%d unique_sessions=%d mtime=%s marker=%s\n' \
    "$validity" "$panes" "$windows" "$states" "$unique_sessions" "$mtime" "$marker"
  printf '\n'
  printf 'sessions:\n'
  awk -F '\t' '
    /^pane\t/ {
      session = $2
      cwd = ""
      command = ""
      for (i = 3; i <= NF; i++) {
        if ($i ~ /^:(\/|~)/) {
          cwd_index = i
          cwd = $i
          break
        }
      }
      sub(/^:/, "", cwd)
      if (cwd != "" && (cwd_index + 2) <= NF) {
        command = $(cwd_index + 2)
      }
      kind = "terminal"
      if (command ~ /^codex/) {
        kind = "codex"
      } else if (command ~ /^[0-9]+[.][0-9]+[.][0-9]+$/ || command ~ /^claude/) {
        kind = "claude-code"
      }
      if (!(session in seen)) {
        order[++count] = session
        seen[session] = kind "\t" command "\t" cwd
      }
    }
    END {
      for (i = 1; i <= count; i++) {
        session = order[i]
        split(seen[session], fields, "\t")
        printf "  %s\tkind=%s\tcommand=%s\tcwd=%s\n", session, fields[1], fields[2], fields[3]
      }
    }
  ' "$file_path"
}

select_snapshot() {
  local file_path="$1"
  local base_name response tmp_link

  preview_snapshot "$file_path"
  printf '\n'

  if [[ "$ASSUME_YES" != "true" ]]; then
    if [[ ! -t 0 ]]; then
      echo "ERROR: --select requires --yes when stdin is not interactive" >&2
      exit 1
    fi
    printf 'Set tmux-resurrect last to this snapshot? [y/N] '
    read -r response
    case "$response" in
      y|Y|yes|YES)
        ;;
      *)
        echo "selection cancelled"
        exit 1
        ;;
    esac
  fi

  base_name="$(basename "$file_path")"
  tmp_link="${LAST_LINK}.tmp.$$"
  rm -f "$tmp_link"
  ln -s "$base_name" "$tmp_link" &&
    mv -f "$tmp_link" "$LAST_LINK"
  echo "selected snapshot=${base_name}"
}

case "$MODE" in
  list)
    list_snapshots
    ;;
  preview)
    preview_snapshot "$(resolve_snapshot "$SELECTOR")"
    ;;
  select)
    select_snapshot "$(resolve_snapshot "$SELECTOR")"
    ;;
esac
