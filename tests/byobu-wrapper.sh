#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
snapshot_dir="$tmp_dir/snapshots"
tmux_tmp="$tmp_dir/tmux"
fake_bin="$tmp_dir/bin"
fake_byobu="$tmp_dir/real-byobu"
byobu_log="$tmp_dir/byobu.log"
session_name="byobu-wrapper-test-$$"
rich_session="byobu-wrapper-rich-$$"
small_session="byobu-wrapper-small-$$"

unset TMUX TMUX_PANE

cleanup() {
  TMUX_TMPDIR="$tmux_tmp" tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$snapshot_dir" "$tmux_tmp" "$fake_bin"

cat > "$fake_bin/byobu-tmux" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "attach-session" ]; then
  printf 'byobu-tmux:%s\n' "\$*" >> "$byobu_log"
  exit 0
fi
exec tmux "\$@"
EOF
chmod +x "$fake_bin/byobu-tmux"

cat > "$fake_byobu" <<EOF
#!/usr/bin/env bash
{
  printf 'args:%s\n' "\$*"
  tmux list-windows -a -F '#{session_name}:#{window_index}:#{window_name}:#{pane_current_path}'
} > "$byobu_log"
EOF
chmod +x "$fake_byobu"

env TMUX_TMPDIR="$tmux_tmp" tmux new-session -d -s "$session_name" -n first -c "$tmp_dir"
env TMUX_TMPDIR="$tmux_tmp" tmux new-window -t "$session_name:" -n second -c "$HOME"

env \
  PATH="$fake_bin:$repo_root/bin:$PATH" \
  TMUX_TMPDIR="$tmux_tmp" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$repo_root/bin/byobu-session-state" autosave autosave "$session_name" >/dev/null

env TMUX_TMPDIR="$tmux_tmp" tmux kill-session -t "$session_name"

env \
  PATH="$fake_bin:$repo_root/bin:$PATH" \
  TMUX_TMPDIR="$tmux_tmp" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  BYOBU_REAL_BIN="$fake_byobu" \
  "$repo_root/bin/byobu" --test-arg

grep -Fxq "args:--test-arg" "$byobu_log" || {
  echo "byobu wrapper did not exec the real byobu with arguments" >&2
  exit 1
}

grep -Fxq "$session_name:0:first:$tmp_dir" "$byobu_log" || {
  echo "byobu wrapper did not restore the first saved window before launch" >&2
  exit 1
}

grep -Fxq "$session_name:1:second:$HOME" "$byobu_log" || {
  echo "byobu wrapper did not restore the second saved window before launch" >&2
  exit 1
}

env TMUX_TMPDIR="$tmux_tmp" tmux kill-session -t "$session_name"
: > "$byobu_log"

env TMUX_TMPDIR="$tmux_tmp" tmux new-session -d -s "$rich_session" -n rich0 -c "$tmp_dir"
env TMUX_TMPDIR="$tmux_tmp" tmux new-window -t "$rich_session:" -n rich1 -c "$HOME"
sleep 0.2
env TMUX_TMPDIR="$tmux_tmp" tmux new-session -d -s "$small_session" -n small0 -c "$HOME"

env \
  PATH="$fake_bin:$repo_root/bin:$PATH" \
  TMUX_TMPDIR="$tmux_tmp" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$repo_root/bin/byobu-session-state" autosave autosave >/dev/null

env TMUX_TMPDIR="$tmux_tmp" tmux kill-session -t "$rich_session"
env TMUX_TMPDIR="$tmux_tmp" tmux kill-session -t "$small_session"

env \
  PATH="$fake_bin:$repo_root/bin:$PATH" \
  TMUX_TMPDIR="$tmux_tmp" \
  BYOBU_SESSION_FORCE_ATTACH=1 \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  BYOBU_REAL_BIN="$fake_byobu" \
  "$repo_root/bin/byobu"

grep -Fxq "byobu-tmux:attach-session -t $rich_session" "$byobu_log" || {
  echo "plain byobu did not attach to the richer restored session" >&2
  cat "$byobu_log" >&2
  exit 1
}

if grep -q '^args:' "$byobu_log"; then
  echo "plain byobu invoked the real byobu instead of attaching directly" >&2
  cat "$byobu_log" >&2
  exit 1
fi

echo "byobu wrapper test passed"
