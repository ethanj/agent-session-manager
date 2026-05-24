#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say() {
  printf '%s\n' "$*"
}

scripts=(
  "$ROOT_DIR/scripts/boot-managed-sessions.sh"
  "$ROOT_DIR/scripts/mark-restore-complete.sh"
  "$ROOT_DIR/scripts/recover-managed-session.sh"
  "$ROOT_DIR/scripts/restore-agent-sessions.sh"
  "$ROOT_DIR/scripts/run-continuum-save.sh"
  "$ROOT_DIR/scripts/tmux-snapshot-selector.sh"
  "$ROOT_DIR/scripts/open-iterm-sessions.sh"
  "$ROOT_DIR/examples/sample-workstation/boot-tmux-project-windows.sh"
)

say "bash syntax"
for script in "${scripts[@]}"; do
  bash -n "$script"
  say "  ok ${script#$ROOT_DIR/}"
done

say "json examples"
jq -e . "$ROOT_DIR/examples/registry.example.json" >/dev/null
say "  ok examples/registry.example.json"

say "secret scan"
secret_pattern='"resumeToken"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"'
secret_found=0
while IFS= read -r -d '' file_path; do
  [[ -f "$ROOT_DIR/$file_path" ]] || continue
  if grep -nE "$secret_pattern" "$ROOT_DIR/$file_path"; then
    secret_found=1
  fi
done < <(git -C "$ROOT_DIR" ls-files -z --cached --others --exclude-standard)
if [[ "$secret_found" -ne 0 ]]; then
  say "ERROR: registry-like resume token found in committed files"
  exit 1
fi
say "  ok no UUID-shaped resumeToken values"

say "dry-run integration"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

registry_file="$tmp_dir/registry.json"
{
  printf '{\n'
  printf '  "instances": [{"id": "workspace", "workspaceRoot": %s}],\n' "$(jq -Rn --arg v "$ROOT_DIR" '$v')"
  printf '  "projects": [{"id": "project", "instanceId": "workspace", "repoRoots": [%s]}],\n' "$(jq -Rn --arg v "$ROOT_DIR" '$v')"
  printf '  "sessions": [{\n'
  printf '    "sessionName": "test-codex",\n'
  printf '    "projectId": "project",\n'
  printf '    "managed": true,\n'
  printf '    "agentKind": "codex",\n'
  printf '    "agentThreadName": "demo test codex",\n'
  printf '    "startCommand": "codex",\n'
  printf '    "resumeToken": "TEST_RESUME_TOKEN"\n'
  printf '  }, {\n'
  printf '    "sessionName": "test-term",\n'
  printf '    "projectId": "project",\n'
  printf '    "managed": true\n'
  printf '  }]\n'
  printf '}\n'
} > "$registry_file"

boot_output="$(
  REGISTRY_FILE="$registry_file" \
    TMUX_BIN=/usr/bin/false \
    LOG_DIR="$tmp_dir/logs" \
    "$ROOT_DIR/scripts/boot-managed-sessions.sh" --dry-run
)"

case "$boot_output" in
  *"boot managed sessions start mode=dry-run"*"starting tmux bootstrap session=0"*"recovering managed sessions: test-codex test-term"*"DRY-RUN:"*"boot managed sessions complete count=2"*)
    say "  ok boot dry-run"
    ;;
  *)
    say "ERROR: unexpected boot dry-run output"
    printf '%s\n' "$boot_output"
    exit 1
    ;;
esac

recover_output="$(
  REGISTRY_FILE="$registry_file" \
    TMUX_BIN=/usr/bin/false \
    RESTORE_AGENTS="$tmp_dir/no-restore-hook" \
    LOG_DIR="$tmp_dir/logs" \
    "$ROOT_DIR/scripts/recover-managed-session.sh" --dry-run test-codex
)"

case "$recover_output" in
  *"creating session=test-codex"*"restore needed session=test-codex"*"running agent restore hook targets=test-codex"*"dry-run complete sessions=test-codex"*)
    say "  ok recover dry-run"
    ;;
  *)
    say "ERROR: unexpected recover dry-run output"
    printf '%s\n' "$recover_output"
    exit 1
    ;;
esac

bad_registry_file="$tmp_dir/bad-registry.json"
jq '.sessions[0].resumeToken = "test-codex" | .sessions[0].agentThreadName = "test-codex"' \
  "$registry_file" > "$bad_registry_file"

if bad_output="$(
  REGISTRY_FILE="$bad_registry_file" \
    TMUX_BIN=/usr/bin/false \
    LOG_DIR="$tmp_dir/logs" \
    "$ROOT_DIR/scripts/recover-managed-session.sh" --dry-run test-codex
)"; then
  say "ERROR: bad recover dry-run unexpectedly passed"
  printf '%s\n' "$bad_output"
  exit 1
fi

case "$bad_output" in
  *"resumeToken must be durable id"*"dry-run validation failed"*)
    say "  ok recover dry-run rejects ambiguous resume token"
    ;;
  *)
    say "ERROR: unexpected bad recover dry-run output"
    printf '%s\n' "$bad_output"
    exit 1
    ;;
esac

open_output="$(TMUX_BIN=/usr/bin/false "$ROOT_DIR/scripts/open-iterm-sessions.sh" --tabs test-codex)"
case "$open_output" in
  *"[DRY-RUN] Would open one iTerm window with tabs for:"*"MISSING: test-codex"*)
    say "  ok open-iterm dry-run"
    ;;
  *)
    say "ERROR: unexpected open-iterm dry-run output"
    printf '%s\n' "$open_output"
    exit 1
    ;;
esac

resurrect_dir="$tmp_dir/resurrect"
mkdir -p "$resurrect_dir"
snapshot_file="$resurrect_dir/tmux_resurrect_20260524T010203.txt"
{
  printf 'pane\tdemo-codex1\t0\t1\t:*\t0\tMac.lan\t:%s\t1\tcodex-aarch64-a\t:codex --redacted\n' "$ROOT_DIR"
  printf 'window\tdemo-codex1\t0\t:zsh\t1\t:*\tlayout\t:\n'
  printf 'state\tdemo-codex1\tdemo-codex1\n'
} > "$snapshot_file"
ln -s "$(basename "$snapshot_file")" "$resurrect_dir/last"

snapshot_list="$(RESURRECT_DIR="$resurrect_dir" "$ROOT_DIR/scripts/tmux-snapshot-selector.sh" --list)"
case "$snapshot_list" in
  *"validity"*"good"*"tmux_resurrect_20260524T010203.txt"*)
    say "  ok snapshot list"
    ;;
  *)
    say "ERROR: unexpected snapshot list output"
    printf '%s\n' "$snapshot_list"
    exit 1
    ;;
esac

snapshot_preview="$(RESURRECT_DIR="$resurrect_dir" "$ROOT_DIR/scripts/tmux-snapshot-selector.sh" --preview 1)"
case "$snapshot_preview" in
  *"validity=good panes=1 windows=1 state=1 unique_sessions=1"*"demo-codex1"*"kind=codex"*)
    say "  ok snapshot preview"
    ;;
  *)
    say "ERROR: unexpected snapshot preview output"
    printf '%s\n' "$snapshot_preview"
    exit 1
    ;;
esac

snapshot_select="$(RESURRECT_DIR="$resurrect_dir" "$ROOT_DIR/scripts/tmux-snapshot-selector.sh" --select 1 --yes)"
case "$snapshot_select" in
  *"selected snapshot=tmux_resurrect_20260524T010203.txt"*)
    say "  ok snapshot select"
    ;;
  *)
    say "ERROR: unexpected snapshot select output"
    printf '%s\n' "$snapshot_select"
    exit 1
    ;;
esac

say "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${scripts[@]}"
  say "  ok shellcheck"
else
  say "  skip shellcheck not installed"
fi
