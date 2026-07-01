#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
snapshot_dir="$tmp_dir/snapshots"
tmux_tmp="$tmp_dir/tmux"
fake_bin="$tmp_dir/bin"
out="$tmp_dir/out"

unset TMUX TMUX_PANE
mkdir -p "$snapshot_dir" "$tmux_tmp" "$fake_bin"

cleanup() {
  env -u TMUX TMUX_TMPDIR="$tmux_tmp" tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

tmux_i() {
  env -u TMUX TMUX_TMPDIR="$tmux_tmp" tmux "$@"
}

state_i() {
  env \
    -u TMUX \
    PATH="$fake_bin:$PATH" \
    TMUX_TMPDIR="$tmux_tmp" \
    BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
    "$repo_root/bin/byobu-session-state" "$@"
}

state_i watchdog autosave >"$out"
grep -q 'no prior live heartbeat' "$out"

session_name="byobu-watchdog-$$"
tmux_i new-session -d -s "$session_name" -n alive -c /tmp
state_i autosave autosave "$session_name" >"$out"
state_i watchdog autosave >"$out"
grep -q 'heartbeat recorded' "$out"
test -f "$snapshot_dir/autosave.watchdog.state"
test -f "$snapshot_dir/autosave.watchdog.sessions.tsv"

tmux_i kill-session -t "$session_name"
state_i watchdog --no-restart-codex autosave >"$out"
grep -q 'no capacity evidence found, restoring autosave' "$out"
tmux_i has-session -t "$session_name"
grep -q 'diagnostic: last live tmux sessions before disappearance' "$snapshot_dir/autosave.watchdog.log"
grep -q "session=$session_name" "$snapshot_dir/autosave.watchdog.log"
grep -q 'restore completed and heartbeat refreshed' "$snapshot_dir/autosave.watchdog.log"
state_i incidents autosave >"$out"
grep -q 'action: restore' "$out"
grep -q 'capacity_found: 0' "$out"

tmux_i kill-server >/dev/null 2>&1 || true

capacity_session="byobu-watchdog-capacity-$$"
tmux_i new-session -d -s "$capacity_session" -n capacity -c /tmp
state_i autosave autosave "$capacity_session" >"$out"
state_i watchdog autosave >"$out"
tmux_i kill-session -t "$capacity_session"

cat > "$fake_bin/journalctl" <<'EOF'
#!/usr/bin/env bash
printf 'Jun 30 10:00:00 host kernel: Out of memory: Killed process 12345 (tmux) total-vm:1kB\n'
EOF
chmod +x "$fake_bin/journalctl"

state_i watchdog --no-restart-codex autosave >"$out"
grep -q 'capacity evidence found, restore skipped' "$out"
grep -q "session=$capacity_session" "$snapshot_dir/autosave.watchdog.log"
grep -q 'Out of memory: Killed process' "$snapshot_dir/autosave.watchdog.log"
state_i incidents autosave >"$out"
grep -q 'action: skip_capacity' "$out"
grep -q 'capacity_found: 1' "$out"
if tmux_i has-session -t "$capacity_session" >/dev/null 2>&1; then
  echo "watchdog restored despite capacity evidence" >&2
  exit 1
fi

echo "watchdog test passed"
