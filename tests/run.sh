#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say() {
  printf '%s\n' "$*"
}

scripts=(
  "$ROOT_DIR/scripts/recover-managed-session.sh"
  "$ROOT_DIR/scripts/restore-agent-sessions.sh"
  "$ROOT_DIR/scripts/open-iterm-sessions.sh"
  "$ROOT_DIR/examples/atomic/boot-tmux-project-windows.sh"
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
  printf '    "startCommand": "codex",\n'
  printf '    "resumeToken": "TEST_RESUME_TOKEN"\n'
  printf '  }]\n'
  printf '}\n'
} > "$registry_file"

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

say "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${scripts[@]}"
  say "  ok shellcheck"
else
  say "  skip shellcheck not installed"
fi
