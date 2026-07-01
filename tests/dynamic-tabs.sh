#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
snapshot_dir="$tmp_dir/snapshots"
tmux_tmp="$tmp_dir/tmux"
session_name="byobu-dynamic-tabs-$$"
out="$tmp_dir/out"

cleanup() {
  env -u TMUX TMUX_TMPDIR="$tmux_tmp" tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$snapshot_dir" "$tmux_tmp"

tmux_i() {
  env -u TMUX TMUX_TMPDIR="$tmux_tmp" tmux "$@"
}

state_i() {
  env \
    -u TMUX \
    TMUX_TMPDIR="$tmux_tmp" \
    BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
    "$repo_root/bin/byobu-session-state" "$@"
}

tmux_i new-session -d -s "$session_name" -n base -c "$HOME"
state_i autosave autosave >"$out"

tmux_i kill-session -t "$session_name"
state_i autorestore --no-restart-codex autosave >"$out"

windows=$(tmux_i list-windows -t "$session_name" -F '#{window_index}:#{window_name}:#{pane_current_path}' | paste -sd ',' -)
[ "$windows" = "0:base:$HOME" ] || {
  echo "initial autorestore did not restore the base tab: $windows" >&2
  exit 1
}

tmux_i new-window -t "$session_name:" -n added-tab -c /tmp
tmux_i select-window -t "$session_name:1"
state_i autosave autosave >"$out"

grep -q '^window_count=2$' "$snapshot_dir/autosave.snapshot" || {
  echo "autosave did not capture the added tab" >&2
  exit 1
}

tmux_i kill-session -t "$session_name"
state_i autorestore --no-restart-codex autosave >"$out"

windows=$(tmux_i list-windows -t "$session_name" -F '#{window_index}:#{window_name}:#{pane_current_path}' | paste -sd ',' -)
[ "$windows" = "0:base:$HOME,1:added-tab:/tmp" ] || {
  echo "second autorestore did not restore the added tab: $windows" >&2
  exit 1
}

active_window=$(tmux_i display-message -p -t "$session_name" '#I')
[ "$active_window" = "1" ] || {
  echo "second autorestore did not restore the active added tab: $active_window" >&2
  exit 1
}

echo "dynamic tabs test passed"
