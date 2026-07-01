#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
snapshot_dir=$(mktemp -d)
tmux_tmp="$snapshot_dir/tmux"
session_name="byobu-doctor-prune-$$"
restore_session="byobu-doctor-prune-restored-$$"
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
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" "$repo_root/bin/byobu-session-state" "$@"
}

tmux new-session -d -s "$session_name" -n main -c /tmp
run_cli save plan "$session_name" > "$out"

run_cli restore --dry-run --no-restart-codex plan "$restore_session" > "$out"
grep -q '^Restore plan:$' "$out"
grep -q "target_session: $restore_session" "$out"
grep -q 'window\[0\]: name=main panes=1 cwd=/tmp active_pane=0' "$out"
if tmux has-session -t "$restore_session" 2>/dev/null; then
  echo "restore --dry-run created target session" >&2
  exit 1
fi

BYOBU_SESSION_STATE_DIR="$snapshot_dir" "$repo_root/bin/byobu-session-plan" restore \
  --snapshot-root "$snapshot_dir" \
  --snapshot-name plan \
  --restart-processes 0 \
  --restart-codex 0 \
  --check-target > "$out"
grep -q '^Restore plan:$' "$out"
grep -q "target_session: $session_name" "$out"

cat > "$snapshot_dir/autosave.sessions.tsv" <<EOF
# byobu-session-state autosave sessions v1
primary	referenced
snapshot	referenced	autosave.session.referenced
EOF

cat > "$snapshot_dir/autosave.session.referenced.snapshot" <<'EOF'
session_name=referenced
window_count=1
window_names[0]=main
EOF
cp "$snapshot_dir/autosave.session.referenced.snapshot" "$snapshot_dir/autosave.session.referenced.last-good.snapshot"

cat > "$snapshot_dir/autosave.session.stale.snapshot" <<'EOF'
session_name=stale
window_count=1
window_names[0]=old
EOF
cp "$snapshot_dir/autosave.session.stale.snapshot" "$snapshot_dir/autosave.session.stale.last-good.snapshot"
cp "$snapshot_dir/autosave.session.stale.snapshot" "$snapshot_dir/autosave.session.stale.previous.snapshot"

run_cli doctor autosave > "$out"
grep -q '^Autosave restore plan for autosave:$' "$out"
grep -q '^Unreferenced autosave session snapshots for autosave:$' "$out"
grep -q 'autosave.session.stale' "$out"

"$repo_root/bin/byobu-session-plan" autosave --snapshot-root "$snapshot_dir" --snapshot-name autosave > "$out"
grep -q '^Autosave restore plan for autosave:$' "$out"
grep -q 'session: referenced snapshot=autosave.session.referenced primary=yes status=present' "$out"

run_cli prune autosave > "$out"
grep -q "Would delete $snapshot_dir/autosave.session.stale.snapshot" "$out"
test -f "$snapshot_dir/autosave.session.stale.snapshot"
test -f "$snapshot_dir/autosave.session.referenced.snapshot"

run_cli prune --delete autosave > "$out"
grep -q "Deleted $snapshot_dir/autosave.session.stale.snapshot" "$out"
test ! -e "$snapshot_dir/autosave.session.stale.snapshot"
test ! -e "$snapshot_dir/autosave.session.stale.last-good.snapshot"
test ! -e "$snapshot_dir/autosave.session.stale.previous.snapshot"
test -f "$snapshot_dir/autosave.session.referenced.snapshot"
test -f "$snapshot_dir/autosave.session.referenced.last-good.snapshot"

echo "doctor/prune test passed"
