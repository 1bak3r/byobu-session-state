#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
snapshot_dir=$(mktemp -d)
tmux_tmp="$snapshot_dir/tmux"
session_name="byobu-state-cli-$$"
restore_session="byobu-state-cli-restored-$$"

unset TMUX TMUX_PANE
mkdir -p "$tmux_tmp"
export TMUX_TMPDIR="$tmux_tmp"

cleanup() {
  tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$snapshot_dir"
}
trap cleanup EXIT

run_cli() {
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" "$repo_root/bin/byobu-session-state" "$@"
}

run_cli --version | grep -Eq '^byobu-session-state [0-9]+\.[0-9]+\.[0-9]+$'

if run_cli save bad/name byobu-state-cli >/tmp/byobu-state-cli.out 2>/tmp/byobu-state-cli.err; then
  echo "expected invalid snapshot name to fail" >&2
  exit 1
fi
grep -q 'snapshot name must be a simple name' /tmp/byobu-state-cli.err

if run_cli restore --unknown cli >/tmp/byobu-state-cli.out 2>/tmp/byobu-state-cli.err; then
  echo "expected unknown restore option to fail" >&2
  exit 1
fi
grep -q 'unknown restore option' /tmp/byobu-state-cli.err

if run_cli autorestore --unknown cli >/tmp/byobu-state-cli.out 2>/tmp/byobu-state-cli.err; then
  echo "expected unknown autorestore option to fail" >&2
  exit 1
fi
grep -q 'unknown autorestore option' /tmp/byobu-state-cli.err

tmux new-session -d -s "$session_name" -n cli -c /tmp
run_cli save cli "$session_name" >/tmp/byobu-state-cli.out
snapshot_path="$snapshot_dir/cli.snapshot"
[ -f "$snapshot_path" ] || {
  echo "expected snapshot to exist: $snapshot_path" >&2
  exit 1
}

run_cli autosave cli-auto "$session_name" >/tmp/byobu-state-cli.out
[ -f "$snapshot_dir/cli-auto.snapshot" ] || {
  echo "expected autosave snapshot to exist" >&2
  exit 1
}

run_cli status >/tmp/byobu-state-cli.out
grep -q 'Snapshot directory:' /tmp/byobu-state-cli.out

lock_dir="$snapshot_dir/.state.lock"
lock_marker="$snapshot_dir/lock-held"
if [ -e "$lock_dir" ]; then
  owner=$(sed -n '1p' "$lock_dir/pid" 2>/dev/null || true)
  if [ -z "$owner" ] || ! kill -0 "$owner" 2>/dev/null; then
    rm -rf "$lock_dir"
  fi
fi
(
  mkdir "$lock_dir"
  trap 'rm -f "$lock_dir/pid"; rmdir "$lock_dir" 2>/dev/null || true' EXIT
  printf '%s\n' "$BASHPID" > "$lock_dir/pid"
  touch "$lock_marker"
  sleep 3
) &
lock_pid=$!
for _ in $(seq 1 50); do
  [ -f "$lock_marker" ] && break
  sleep 0.1
done
[ -f "$lock_marker" ] || {
  kill "$lock_pid" >/dev/null 2>&1 || true
  wait "$lock_pid" >/dev/null 2>&1 || true
  echo "lock holder did not start" >&2
  exit 1
}

run_cli status >/tmp/byobu-state-cli.out
grep -q 'Snapshot directory:' /tmp/byobu-state-cli.out

if BYOBU_SESSION_LOCK_TIMEOUT_SECONDS=1 run_cli autosave cli-locked "$session_name" >/tmp/byobu-state-cli.out 2>/tmp/byobu-state-cli.err; then
  kill "$lock_pid" >/dev/null 2>&1 || true
  wait "$lock_pid" >/dev/null 2>&1 || true
  echo "expected locked autosave to time out" >&2
  exit 1
fi
grep -q 'timed out waiting for byobu-session-state lock' /tmp/byobu-state-cli.err
wait "$lock_pid"

chmod 0666 "$snapshot_path"
if run_cli restore cli "$restore_session" >/tmp/byobu-state-cli.out 2>/tmp/byobu-state-cli.err; then
  echo "expected writable snapshot restore to fail" >&2
  exit 1
fi
grep -q 'refusing to restore group/world-writable snapshot' /tmp/byobu-state-cli.err

echo "cli test passed"
