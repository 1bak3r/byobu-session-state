#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
snapshot_dir=$(mktemp -d)
tmux_tmp="$snapshot_dir/tmux"
primary_session="byobu-crash-primary-$$"
secondary_session="byobu-crash-secondary-$$"
thread_id="019f1075-142d-7ff1-b822-a1a07395d955"
out="$snapshot_dir/out"

unset TMUX TMUX_PANE
mkdir -p "$tmux_tmp"
export TMUX_TMPDIR="$tmux_tmp"

cleanup() {
  tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$snapshot_dir"
}
trap cleanup EXIT

run_cli() {
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
    BYOBU_SESSION_SKIP_CODEX_ADOPT=1 \
    "$repo_root/bin/byobu-session-state" "$@"
}

tmux new-session -d -s "$primary_session" -n edit -c /tmp
tmux new-window -t "$primary_session:" -n logs -c "$HOME"
tmux new-session -d -s "$secondary_session" -n agent -c "$snapshot_dir"
tmux set-option -wq -t "$secondary_session:0" '@byobu-codex' '1'
tmux set-option -wq -t "$secondary_session:0" '@byobu-codex-mode' 'resume'
tmux set-option -wq -t "$secondary_session:0" '@byobu-codex-thread-id' "$thread_id"
tmux set-option -wq -t "$secondary_session:0" '@byobu-codex-cwd' "$snapshot_dir"

run_cli autosave autosave > "$out"
grep -Fq "snapshot	$primary_session	autosave.session.$primary_session" "$snapshot_dir/autosave.sessions.tsv"
grep -Fq "snapshot	$secondary_session	autosave.session.$secondary_session" "$snapshot_dir/autosave.sessions.tsv"

run_cli validate autosave > "$out"
grep -q 'Validation OK for autosave' "$out"

sed '/^window_layouts\[0\]=/d' "$snapshot_dir/autosave.session.$primary_session.snapshot" > "$snapshot_dir/broken.snapshot"
if run_cli validate broken > "$out" 2>&1; then
  echo "expected broken snapshot validation to fail" >&2
  exit 1
fi
grep -Fq 'missing window_layouts[0]' "$out"

tmux kill-server >/dev/null 2>&1 || true
if tmux list-sessions >/dev/null 2>&1; then
  echo "expected simulated crash to leave no tmux sessions" >&2
  exit 1
fi

run_cli autorestore --no-restart-codex autosave > "$out"

tmux has-session -t "$primary_session"
tmux has-session -t "$secondary_session"

primary_windows=$(tmux list-windows -t "$primary_session" -F '#{window_index}:#{window_name}' | paste -sd ',' -)
[ "$primary_windows" = "0:edit,1:logs" ] || {
  echo "primary session windows were not restored: $primary_windows" >&2
  exit 1
}

secondary_windows=$(tmux list-windows -t "$secondary_session" -F '#{window_index}:#{window_name}' | paste -sd ',' -)
[ "$secondary_windows" = "0:agent" ] || {
  echo "secondary session windows were not restored: $secondary_windows" >&2
  exit 1
}

restored_thread=$(tmux show-options -wqv -t "$secondary_session:0" '@byobu-codex-thread-id')
[ "$restored_thread" = "$thread_id" ] || {
  echo "restored session did not preserve Codex thread metadata" >&2
  exit 1
}

run_cli validate autosave > "$out"
grep -q 'Validation OK for autosave' "$out"

echo "validate/crash test passed"
