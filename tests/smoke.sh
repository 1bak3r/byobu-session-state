#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
snapshot_dir=$(mktemp -d)
tmux_tmp="$snapshot_dir/tmux"

unset TMUX TMUX_PANE
mkdir -p "$tmux_tmp"
export TMUX_TMPDIR="$tmux_tmp"

cleanup() {
  tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$snapshot_dir"
}
trap cleanup EXIT

tmux kill-session -t byobu-state-test >/dev/null 2>&1 || true
tmux kill-session -t byobu-state-restored >/dev/null 2>&1 || true
tmux kill-session -t byobu-state-restarted >/dev/null 2>&1 || true

tmux new-session -d -s byobu-state-test -n editor -c /tmp
tmux split-window -h -t byobu-state-test:0 -c /var/tmp
tmux split-window -v -t byobu-state-test:0.1 -c "$HOME" 'sleep 900'
tmux select-layout -t byobu-state-test:0 tiled >/dev/null 2>&1 || true
tmux select-pane -t byobu-state-test:0.1
sleep 0.2
original_geometry=$(tmux list-panes -t byobu-state-test:0 -F '#{pane_index}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | paste -sd ';' -)
tmux new-window -t byobu-state-test: -n home -c "$HOME"
tmux select-window -t byobu-state-test:1

BYOBU_SESSION_STATE_DIR="$snapshot_dir" "$repo_root/bin/byobu-session-state" save smoke byobu-state-test
snapshot_path="$snapshot_dir/smoke.snapshot"
grep -q '^window_pane_counts\[0\]=3$' "$snapshot_path" || {
  echo "snapshot did not record three panes for the split window" >&2
  exit 1
}
grep -q '^window_layouts\[0\]=' "$snapshot_path" || {
  echo "snapshot did not record the split window layout" >&2
  exit 1
}
grep -q '^window_0_pane_restart_commands\[2\]=sleep\\ 900$' "$snapshot_path" || {
  echo "snapshot did not record the running pane command" >&2
  exit 1
}

tmux kill-session -t byobu-state-test
BYOBU_SESSION_STATE_DIR="$snapshot_dir" "$repo_root/bin/byobu-session-state" restore smoke byobu-state-restored

windows=$(tmux list-windows -t byobu-state-restored -F '#{window_index}:#{window_name}' | paste -sd ',' -)
[ "$windows" = "0:editor,1:home" ] || {
  echo "unexpected windows: $windows" >&2
  exit 1
}

pane_paths=$(tmux list-panes -t byobu-state-restored:0 -F '#{pane_current_path}' | paste -sd ',' -)
[ "$pane_paths" = "/tmp,/var/tmp,$HOME" ] || {
  echo "unexpected pane paths: $pane_paths" >&2
  exit 1
}

restored_pane_count=$(tmux list-panes -t byobu-state-restored:0 -F '#{pane_index}' | wc -l)
[ "$restored_pane_count" = "3" ] || {
  echo "unexpected restored pane count: $restored_pane_count" >&2
  exit 1
}

restored_active_pane=$(tmux display-message -p -t byobu-state-restored:0 '#{pane_index}')
[ "$restored_active_pane" = "1" ] || {
  echo "unexpected restored active pane: $restored_active_pane" >&2
  exit 1
}

restored_geometry=$(tmux list-panes -t byobu-state-restored:0 -F '#{pane_index}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | paste -sd ';' -)
[ "$restored_geometry" = "$original_geometry" ] || {
  echo "restored split geometry does not match original" >&2
  echo "original: $original_geometry" >&2
  echo "restored: $restored_geometry" >&2
  exit 1
}

default_commands=$(tmux list-panes -t byobu-state-restored:0 -F '#{pane_current_command}' | paste -sd ',' -)
case "$default_commands" in
  *sleep*)
    echo "restore restarted a process without opt-in: $default_commands" >&2
    exit 1
    ;;
esac

BYOBU_SESSION_STATE_DIR="$snapshot_dir" "$repo_root/bin/byobu-session-state" restore --restart-processes smoke byobu-state-restarted
sleep 1
restart_commands=$(tmux list-panes -t byobu-state-restarted:0 -F '#{pane_current_command}' | paste -sd ',' -)
case "$restart_commands" in
  *sleep*) ;;
  *)
    echo "restore --restart-processes did not restart the saved command: $restart_commands" >&2
    exit 1
    ;;
esac

if command -v byobu-tmux >/dev/null 2>&1; then
  status_left=$(tmux show-options -gqv status-left)
  case "$status_left" in
    *byobu-status*) ;;
    *)
      echo "warning: restored session does not appear to have Byobu status loaded: $status_left" >&2
      ;;
  esac
fi

echo "smoke test passed"
