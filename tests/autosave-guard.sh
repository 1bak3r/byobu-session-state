#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
snapshot_dir=$(mktemp -d)
good_session="byobu-autosave-good-$$"
bad_session="byobu-autosave-bad-$$"
restore_session="byobu-autosave-restore-$$"
multi_tmux="$snapshot_dir/tmux"

unset TMUX TMUX_PANE
mkdir -p "$multi_tmux"
export TMUX_TMPDIR="$multi_tmux"

cleanup() {
  tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$snapshot_dir"
}
trap cleanup EXIT

tmux new-session -d -s "$good_session" -n editor -c /tmp
tmux new-window -t "$good_session:" -n agent -c "$HOME"

BYOBU_SESSION_STATE_DIR="$snapshot_dir" "$repo_root/bin/byobu-session-state" autosave autosave "$good_session" >/tmp/byobu-autosave-guard.out
grep -q '^window_count=2$' "$snapshot_dir/autosave.snapshot"
test -f "$snapshot_dir/autosave.last-good.snapshot"

tmux new-session -d -s "$bad_session" -n - -c "$HOME"
BYOBU_SESSION_STATE_DIR="$snapshot_dir" "$repo_root/bin/byobu-session-state" autosave autosave "$bad_session" >/tmp/byobu-autosave-guard.out
grep -q 'Skipped degraded autosave' /tmp/byobu-autosave-guard.out
grep -q '^window_count=2$' "$snapshot_dir/autosave.snapshot"
test -d "$snapshot_dir/rejected"

tmux kill-session -t "$good_session"
tmux kill-session -t "$bad_session"
BYOBU_SESSION_STATE_DIR="$snapshot_dir" "$repo_root/bin/byobu-session-state" restore --no-restart-codex autosave "$restore_session" >/tmp/byobu-autosave-guard.out

windows=$(tmux list-windows -t "$restore_session" -F '#{window_index}:#{window_name}' | paste -sd ',' -)
[ "$windows" = "0:editor,1:agent" ] || {
  echo "restore did not use the preserved good autosave: $windows" >&2
  exit 1
}
tmux kill-session -t "$restore_session"

multi_snapshot_dir="$snapshot_dir/multi"
multi_old="byobu-multi-old-$$"
multi_current="byobu-multi-current-$$"
multi_thread="019f1667-3d93-7f92-8e50-be25fd83c46d"
mkdir -p "$multi_snapshot_dir"

env TMUX_TMPDIR="$multi_tmux" tmux new-session -d -s "$multi_old" -n old0 -c /tmp
env TMUX_TMPDIR="$multi_tmux" tmux new-window -t "$multi_old:" -n old1 -c "$HOME"
sleep 0.2
env TMUX_TMPDIR="$multi_tmux" tmux new-session -d -s "$multi_current" -n node -c "$HOME"
env TMUX_TMPDIR="$multi_tmux" tmux set-option -wq -t "$multi_current:0" '@byobu-codex' '1'
env TMUX_TMPDIR="$multi_tmux" tmux set-option -wq -t "$multi_current:0" '@byobu-codex-thread-id' "$multi_thread"
env TMUX_TMPDIR="$multi_tmux" tmux set-option -wq -t "$multi_current:0" '@byobu-codex-cwd' "$HOME"

env \
  TMUX_TMPDIR="$multi_tmux" \
  BYOBU_SESSION_STATE_DIR="$multi_snapshot_dir" \
  BYOBU_SESSION_SKIP_CODEX_ADOPT=1 \
  "$repo_root/bin/byobu-session-state" autosave autosave >/tmp/byobu-autosave-guard.out

test -f "$multi_snapshot_dir/autosave.sessions.tsv"
grep -Fq "primary	$multi_old" "$multi_snapshot_dir/autosave.sessions.tsv"
grep -Fq "snapshot	$multi_old	autosave.session.$multi_old" "$multi_snapshot_dir/autosave.sessions.tsv"
grep -Fq "snapshot	$multi_current	autosave.session.$multi_current" "$multi_snapshot_dir/autosave.sessions.tsv"
grep -Fq "window_codex_thread_ids[0]=$multi_thread" "$multi_snapshot_dir/autosave.session.$multi_current.snapshot"

env TMUX_TMPDIR="$multi_tmux" tmux kill-session -t "$multi_old"
env TMUX_TMPDIR="$multi_tmux" tmux kill-session -t "$multi_current"

env \
  TMUX_TMPDIR="$multi_tmux" \
  BYOBU_SESSION_STATE_DIR="$multi_snapshot_dir" \
  "$repo_root/bin/byobu-session-state" autorestore --no-restart-codex autosave >/tmp/byobu-autosave-guard.out

env TMUX_TMPDIR="$multi_tmux" tmux has-session -t "$multi_old"
env TMUX_TMPDIR="$multi_tmux" tmux has-session -t "$multi_current"
multi_old_windows=$(env TMUX_TMPDIR="$multi_tmux" tmux list-windows -t "$multi_old" -F '#{window_index}:#{window_name}' | paste -sd ',' -)
[ "$multi_old_windows" = "0:old0,1:old1" ] || {
  echo "multi-session autorestore did not restore older tab session: $multi_old_windows" >&2
  exit 1
}
[ "$(env TMUX_TMPDIR="$multi_tmux" tmux show-options -wqv -t "$multi_current:0" '@byobu-codex-thread-id')" = "$multi_thread" ] || {
  echo "multi-session autorestore did not preserve Codex thread metadata" >&2
  exit 1
}

dedupe_snapshot_dir="$snapshot_dir/dedupe"
dedupe_tmux="$snapshot_dir/dedupe-tmux"
dedupe_primary="byobu-dedupe-primary-$$"
dedupe_secondary="byobu-dedupe-secondary-$$"
dedupe_thread="019f1667-3d93-7f92-8e50-be25fd83c46d"
fake_codex="$snapshot_dir/fake-codex"
codex_log="$snapshot_dir/fake-codex.log"
mkdir -p "$dedupe_snapshot_dir" "$dedupe_tmux"

cat > "$fake_codex" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$codex_log"
exit 0
EOF
chmod +x "$fake_codex"

env BYOBU_CODEX_BIN="$fake_codex" TMUX_TMPDIR="$dedupe_tmux" tmux new-session -d -s "$dedupe_primary" -n primary -c "$HOME"
env BYOBU_CODEX_BIN="$fake_codex" TMUX_TMPDIR="$dedupe_tmux" tmux set-option -wq -t "$dedupe_primary:0" '@byobu-codex' '1'
env BYOBU_CODEX_BIN="$fake_codex" TMUX_TMPDIR="$dedupe_tmux" tmux set-option -wq -t "$dedupe_primary:0" '@byobu-codex-thread-id' "$dedupe_thread"
env BYOBU_CODEX_BIN="$fake_codex" TMUX_TMPDIR="$dedupe_tmux" tmux set-option -wq -t "$dedupe_primary:0" '@byobu-codex-cwd' "$HOME"
env BYOBU_CODEX_BIN="$fake_codex" TMUX_TMPDIR="$dedupe_tmux" tmux new-session -d -s "$dedupe_secondary" -n secondary -c "$HOME"
env BYOBU_CODEX_BIN="$fake_codex" TMUX_TMPDIR="$dedupe_tmux" tmux set-option -wq -t "$dedupe_secondary:0" '@byobu-codex' '1'
env BYOBU_CODEX_BIN="$fake_codex" TMUX_TMPDIR="$dedupe_tmux" tmux set-option -wq -t "$dedupe_secondary:0" '@byobu-codex-thread-id' "$dedupe_thread"
env BYOBU_CODEX_BIN="$fake_codex" TMUX_TMPDIR="$dedupe_tmux" tmux set-option -wq -t "$dedupe_secondary:0" '@byobu-codex-cwd' "$HOME"

env \
  BYOBU_CODEX_BIN="$fake_codex" \
  TMUX_TMPDIR="$dedupe_tmux" \
  BYOBU_SESSION_STATE_DIR="$dedupe_snapshot_dir" \
  BYOBU_SESSION_SKIP_CODEX_ADOPT=1 \
  "$repo_root/bin/byobu-session-state" autosave autosave >/tmp/byobu-autosave-guard.out

env TMUX_TMPDIR="$dedupe_tmux" tmux kill-session -t "$dedupe_primary"
env TMUX_TMPDIR="$dedupe_tmux" tmux kill-session -t "$dedupe_secondary"

env \
  BYOBU_CODEX_BIN="$fake_codex" \
  TMUX_TMPDIR="$dedupe_tmux" \
  BYOBU_SESSION_STATE_DIR="$dedupe_snapshot_dir" \
  "$repo_root/bin/byobu-session-state" autorestore --restart-codex autosave >/tmp/byobu-autosave-guard.out

for _ in $(seq 1 30); do
  [ -f "$codex_log" ] && break
  sleep 0.1
done
codex_invocations=$(wc -l < "$codex_log")
[ "$codex_invocations" = "1" ] || {
  echo "duplicate Codex thread was resumed $codex_invocations times" >&2
  cat "$codex_log" >&2
  exit 1
}
suppressed_count=$(env TMUX_TMPDIR="$dedupe_tmux" tmux list-windows -a -F '#{@byobu-codex-dedup-suppressed}' | awk 'NF { count++ } END { print count + 0 }')
[ "$suppressed_count" = "1" ] || {
  echo "expected one duplicate Codex tab to be suppressed, saw $suppressed_count" >&2
  exit 1
}

group_snapshot_dir="$snapshot_dir/grouped"
group_primary="byobu-group-primary-$$"
group_link="byobu-group-link-$$"
mkdir -p "$group_snapshot_dir"

env TMUX_TMPDIR="$multi_tmux" tmux new-session -d -s "$group_primary" -n grouped -c /tmp
env TMUX_TMPDIR="$multi_tmux" tmux new-session -d -t "$group_primary" -s "$group_link"

env \
  TMUX_TMPDIR="$multi_tmux" \
  BYOBU_SESSION_STATE_DIR="$group_snapshot_dir" \
  BYOBU_SESSION_SKIP_CODEX_ADOPT=1 \
  "$repo_root/bin/byobu-session-state" autosave autosave >/tmp/byobu-autosave-guard.out

group_manifest_matches=$(grep -Ec "^snapshot	($group_primary|$group_link)	" "$group_snapshot_dir/autosave.sessions.tsv")
[ "$group_manifest_matches" = "1" ] || {
  echo "grouped sessions should be saved once, not duplicated: $group_manifest_matches" >&2
  cat "$group_snapshot_dir/autosave.sessions.tsv" >&2
  exit 1
}

echo "autosave guard test passed"
