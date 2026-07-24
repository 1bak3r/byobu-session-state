#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
snapshot_dir="$tmp_dir/snapshots"
tmux_tmp="$tmp_dir/tmux"
session_name="byobu-codex-test-$$"
restored_session="byobu-codex-restored-$$"
adopt_session="byobu-codex-adopt-$$"
thread_id="019f1075-142d-7ff1-b822-a1a07395d955"
adopt_thread_id="019f9999-0000-7000-8000-000000000001"
rollout_thread_id="019f9999-0000-7000-8000-000000000002"
resume_thread_id="019f9999-0000-7000-8000-000000000003"
stale_thread_id="019f9999-0000-7000-8000-000000000099"
fake_codex="$tmp_dir/fake-codex"
crashy_codex="$tmp_dir/crashy-codex"
plain_codex="$tmp_dir/codex"
rollout_codex="$tmp_dir/codex-rollout"
rollout_path="$tmp_dir/rollout-2026-07-23T21-26-00-$rollout_thread_id.jsonl"
exit_codex="$tmp_dir/exit-codex"
codex_home="$tmp_dir/codex-home"
codex_log="$tmp_dir/codex.log"
crashy_log="$tmp_dir/crashy.log"
crashy_count="$tmp_dir/crashy-count"

unset TMUX TMUX_PANE CODEX_THREAD_ID
for inherited_fd_path in /proc/$$/fd/*; do
  inherited_fd=${inherited_fd_path##*/}
  case "$inherited_fd" in
    0|1|2|255) continue ;;
  esac
  eval "exec ${inherited_fd}>&-"
done

cleanup() {
  tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
  tmux kill-session -t "$restored_session" >/dev/null 2>&1 || true
  tmux kill-session -t "$adopt_session" >/dev/null 2>&1 || true
  tmux set-environment -gu BYOBU_CODEX_BIN >/dev/null 2>&1 || true
  tmux set-environment -gu BYOBU_CODEX_TEST_LOG >/dev/null 2>&1 || true
  tmux set-environment -gu BYOBU_CODEX_MONITOR_SECONDS >/dev/null 2>&1 || true
  tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$snapshot_dir" "$tmux_tmp" "$codex_home"
export TMUX_TMPDIR="$tmux_tmp"
cat > "$fake_codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BYOBU_CODEX_TEST_LOG"
sleep 900
EOF
chmod +x "$fake_codex"
: > "$codex_log"

cat > "$crashy_codex" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$crashy_log"
if [ ! -f "$crashy_count" ]; then
  touch "$crashy_count"
  exit 7
fi
sleep 900
EOF
chmod +x "$crashy_codex"
: > "$crashy_log"

cat > "$plain_codex" <<'EOF'
#!/usr/bin/env bash
sleep 900
EOF
chmod +x "$plain_codex"

cat > "$rollout_codex" <<'EOF'
#!/usr/bin/env bash
for fd_path in /proc/$$/fd/*; do
  fd=${fd_path##*/}
  case "$fd" in
    0|1|2|255) continue ;;
  esac
  eval "exec ${fd}>&-"
done
exec 33<"$BYOBU_CODEX_ROLLOUT"
sleep 900 &
wait
EOF
chmod +x "$rollout_codex"
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$rollout_thread_id\",\"session_id\":\"$rollout_thread_id\"}}" \
  >"$rollout_path"

cat > "$exit_codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$exit_codex"

tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
tmux kill-session -t "$restored_session" >/dev/null 2>&1 || true
tmux kill-session -t "$adopt_session" >/dev/null 2>&1 || true
tmux new-session -d -s "$session_name" -n shell -c "$tmp_dir"
tmux set-environment -t "$session_name" BYOBU_CODEX_BIN "$fake_codex"
tmux set-environment -t "$session_name" BYOBU_CODEX_TEST_LOG "$codex_log"
tmux set-environment -t "$session_name" BYOBU_CODEX_MONITOR_SECONDS "2"
tmux set-environment -t "$session_name" CODEX_HOME "$codex_home"

env \
  PATH="$repo_root/bin:$PATH" \
  CODEX_HOME="$codex_home" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$repo_root/bin/byobu-codex" add --session "$session_name" --name "New Codex" --cd "$tmp_dir" -- "hello"

sleep 0.5
[ "$(tmux show-options -wqv -t "$session_name:1" '@byobu-codex')" = "1" ] || {
  echo "new Codex tab was not tagged" >&2
  exit 1
}
[ "$(tmux show-options -wqv -t "$session_name:1" '@byobu-codex-mode')" = "new" ] || {
  echo "new Codex tab mode was not recorded" >&2
  exit 1
}
grep -Fxq -- "--sandbox danger-full-access --ask-for-approval never hello" "$codex_log" || {
  echo "fake Codex did not receive the new-tab prompt" >&2
  exit 1
}

env \
  PATH="$repo_root/bin:$PATH" \
  CODEX_HOME="$codex_home" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$repo_root/bin/byobu-codex" resume --session "$session_name" --name "Resume Codex" --cd "$tmp_dir" "$thread_id" "continue"

sleep 0.5
[ "$(tmux show-options -wqv -t "$session_name:2" '@byobu-codex-thread-id')" = "$thread_id" ] || {
  echo "resume Codex tab thread id was not recorded" >&2
  exit 1
}
grep -Fxq -- "--sandbox danger-full-access --ask-for-approval never resume $thread_id continue" "$codex_log" || {
  echo "fake Codex did not receive the resume command" >&2
  exit 1
}

tmux set-environment -t "$session_name" BYOBU_CODEX_BIN "$crashy_codex"
tmux set-environment -t "$session_name" BYOBU_CODEX_RESTART_DELAY "0"

env \
  PATH="$repo_root/bin:$PATH" \
  CODEX_HOME="$codex_home" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$repo_root/bin/byobu-codex" resume --session "$session_name" --name "Crash Resume" --cd "$tmp_dir" "$thread_id"

sleep 1
crash_resume_count=$(grep -Fxc -- "--sandbox danger-full-access --ask-for-approval never resume $thread_id" "$crashy_log")
[ "$crash_resume_count" -ge 2 ] || {
  echo "crashed Codex tab was not restarted: count=$crash_resume_count" >&2
  exit 1
}

tmux set-environment -t "$session_name" BYOBU_CODEX_BIN "$fake_codex"
tmux set-environment -t "$session_name" BYOBU_CODEX_RESTART_DELAY "3"

tmux set-environment -t "$session_name" BYOBU_CODEX_BIN "$exit_codex"
env \
  PATH="$repo_root/bin:$PATH" \
  CODEX_HOME="$codex_home" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$repo_root/bin/byobu-codex" add --session "$session_name" --name "Exit Once" --cd "$tmp_dir" -- "done"

for _ in $(seq 1 50); do
  if ! tmux list-windows -t "$session_name" -F '#{window_name}' | grep -Fxq "Exit Once"; then
    break
  fi
  sleep 0.1
done
if tmux list-windows -t "$session_name" -F '#{window_name}' | grep -Fxq "Exit Once"; then
  echo "Codex tab stayed open after normal Codex exit" >&2
  exit 1
fi

tmux set-environment -t "$session_name" BYOBU_CODEX_KEEP_SHELL_ON_EXIT "1"
env \
  PATH="$repo_root/bin:$PATH" \
  CODEX_HOME="$codex_home" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$repo_root/bin/byobu-codex" add --session "$session_name" --name "Keep Shell" --cd "$tmp_dir" -- "done"

sleep 0.5
tmux list-windows -t "$session_name" -F '#{window_name}' | grep -Fxq "Keep Shell" || {
  echo "Codex tab did not honor BYOBU_CODEX_KEEP_SHELL_ON_EXIT" >&2
  exit 1
}
tmux kill-window -t "$session_name:Keep Shell"
tmux set-environment -t "$session_name" BYOBU_CODEX_KEEP_SHELL_ON_EXIT "0"
tmux set-environment -t "$session_name" BYOBU_CODEX_BIN "$fake_codex"

env \
  CODEX_HOME="$codex_home" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$repo_root/bin/byobu-session-state" save codex "$session_name" >/dev/null

grep -Fxq "window_codex_thread_ids[2]=$thread_id" "$snapshot_dir/codex.snapshot" || {
  echo "snapshot did not record the Codex thread id" >&2
  exit 1
}

tmux kill-session -t "$session_name"
: > "$codex_log"

env \
  PATH="$repo_root/bin:$PATH" \
  CODEX_HOME="$codex_home" \
  BYOBU_CODEX_BIN="$fake_codex" \
  BYOBU_CODEX_TEST_LOG="$codex_log" \
  BYOBU_CODEX_MONITOR_SECONDS="2" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$repo_root/bin/byobu-session-state" restore codex "$restored_session" >/dev/null

sleep 0.5
grep -Fxq -- "--sandbox danger-full-access --ask-for-approval never resume $thread_id" "$codex_log" || {
  echo "restore did not resume the saved Codex thread" >&2
  exit 1
}
[ "$(tmux show-options -wqv -t "$restored_session:2" '@byobu-codex-thread-id')" = "$thread_id" ] || {
  echo "restored Codex tab thread id was not tagged" >&2
  exit 1
}

python3 - "$codex_home/state_5.sqlite" "$adopt_thread_id" "$tmp_dir" <<'PY'
import sqlite3
import sys
import time

db, thread_id, cwd = sys.argv[1], sys.argv[2], sys.argv[3]
now_ms = int(time.time() * 1000)
conn = sqlite3.connect(db)
conn.execute(
    """
    create table threads (
      id text primary key,
      created_at integer,
      updated_at integer,
      recency_at integer,
      created_at_ms integer,
      updated_at_ms integer,
      recency_at_ms integer,
      archived integer,
      cwd text,
      title text,
      preview text,
      first_user_message text
    )
    """
)
conn.execute(
    "insert into threads values (?, ?, ?, ?, ?, ?, ?, 0, ?, '', 'fallback thread', '')",
    (thread_id, now_ms // 1000, now_ms // 1000, now_ms // 1000, now_ms, now_ms, now_ms, cwd),
)
conn.commit()
PY

tmux new-session -d -s "$adopt_session" -n node -c "$tmp_dir" "CODEX_THREAD_ID=$adopt_thread_id $plain_codex"
tmux set-option -wq -t "$adopt_session:0" '@byobu-codex-thread-id' "$stale_thread_id"
tmux new-window -d -t "$adopt_session:" -n rollout -c "$tmp_dir" \
  "CODEX_THREAD_ID=$stale_thread_id BYOBU_CODEX_ROLLOUT=$rollout_path $rollout_codex"
tmux set-option -wq -t "$adopt_session:1" '@byobu-codex-thread-id' "$stale_thread_id"
tmux set-option -wq -t "$adopt_session:1" '@byobu-codex-dedup-suppressed' "stale-test-value"
tmux new-window -d -t "$adopt_session:" -n bare -c "$tmp_dir" "$plain_codex"
tmux set-option -wq -t "$adopt_session:2" '@byobu-codex-thread-id' "$stale_thread_id"
tmux set-option -wq -t "$adopt_session:2" '@byobu-codex-dedup-suppressed' "stale-test-value"
tmux new-window -d -t "$adopt_session:" -n explicit-resume -c "$tmp_dir" \
  "$plain_codex resume $resume_thread_id"
tmux set-option -wq -t "$adopt_session:3" '@byobu-codex-thread-id' "$stale_thread_id"
sleep 0.5
env \
  PATH="$repo_root/bin:$PATH" \
  CODEX_HOME="$codex_home" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$repo_root/bin/byobu-codex" adopt --session "$adopt_session" --no-autosave --quiet

[ "$(tmux show-options -wqv -t "$adopt_session:0" '@byobu-codex-thread-id')" = "$adopt_thread_id" ] || {
  echo "adopt did not tag a generic running Codex pane from recent thread state" >&2
  exit 1
}

actual_rollout_thread_id=$(tmux show-options -wqv -t "$adopt_session:1" '@byobu-codex-thread-id')
[ "$actual_rollout_thread_id" = "$rollout_thread_id" ] || {
  echo "adopt did not correct stale metadata from the live Codex rollout file: got $actual_rollout_thread_id" >&2
  exit 1
}
[ -z "$(tmux show-options -wqv -t "$adopt_session:1" '@byobu-codex-dedup-suppressed')" ] || {
  echo "adopt did not clear stale duplicate-suppression metadata" >&2
  exit 1
}
[ -z "$(tmux show-options -wqv -t "$adopt_session:2" '@byobu-codex-thread-id')" ] || {
  echo "adopt did not clear inherited thread metadata from a bare new Codex process" >&2
  exit 1
}
[ "$(tmux show-options -wqv -t "$adopt_session:2" '@byobu-codex-mode')" = "new" ] || {
  echo "adopt did not mark the bare Codex process as a new session" >&2
  exit 1
}
[ -z "$(tmux show-options -wqv -t "$adopt_session:2" '@byobu-codex-dedup-suppressed')" ] || {
  echo "adopt did not clear duplicate suppression from the bare Codex process" >&2
  exit 1
}
[ "$(tmux show-options -wqv -t "$adopt_session:3" '@byobu-codex-thread-id')" = "$resume_thread_id" ] || {
  echo "adopt did not preserve an explicit Codex resume thread" >&2
  exit 1
}

echo "codex test passed"
