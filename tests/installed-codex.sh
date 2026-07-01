#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
install_root="$tmp_dir/install"
user_bin="$tmp_dir/bin"
user_systemd_dir="$tmp_dir/systemd"
snapshot_dir="$tmp_dir/snapshots"
tmux_tmp="$tmp_dir/tmux"
session_name="byobu-installed-codex-test-$$"
restored_session="byobu-installed-codex-restored-$$"
thread_id="019f1075-142d-7ff1-b822-a1a07395d955"
fake_codex="$tmp_dir/fake-codex"
codex_log="$tmp_dir/codex.log"

tmux_i() {
  env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$tmux_tmp" tmux "$@"
}

run_i() {
  env -u TMUX -u TMUX_PANE \
    TMUX_TMPDIR="$tmux_tmp" \
    PATH="$user_bin:$PATH" \
    BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
    "$@"
}

cleanup() {
  tmux_i kill-server >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$snapshot_dir" "$tmux_tmp"

BYOBU_SESSION_STATE_SKIP_SYSTEMD=1 \
  INSTALL_ROOT="$install_root" \
  USER_BIN_DIR="$user_bin" \
  USER_SYSTEMD_DIR="$user_systemd_dir" \
  "$repo_root/install.sh" >/dev/null

[ "$(readlink -f "$user_bin/byobu-codex")" = "$install_root/bin/byobu-codex" ] || {
  echo "installed byobu-codex symlink does not point at temp install root" >&2
  exit 1
}

cat > "$fake_codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BYOBU_CODEX_TEST_LOG"
sleep 30
EOF
chmod +x "$fake_codex"
: > "$codex_log"

tmux_i new-session -d -s "$session_name" -n shell -c "$tmp_dir"
tmux_i set-environment -t "$session_name" BYOBU_CODEX_BIN "$fake_codex"
tmux_i set-environment -t "$session_name" BYOBU_CODEX_TEST_LOG "$codex_log"

run_i "$user_bin/byobu-codex" resume --session "$session_name" --name "Resume Codex" --cd "$tmp_dir" "$thread_id"

sleep 0.5
grep -Fxq -- "--sandbox danger-full-access --ask-for-approval never resume $thread_id" "$codex_log" || {
  echo "installed byobu-codex did not launch Codex with full permissions" >&2
  exit 1
}

run_i "$user_bin/byobu-session-state" save codex "$session_name" >/dev/null

tmux_i kill-session -t "$session_name"
: > "$codex_log"

env -u TMUX -u TMUX_PANE \
  TMUX_TMPDIR="$tmux_tmp" \
  PATH="$user_bin:$PATH" \
  BYOBU_CODEX_BIN="$fake_codex" \
  BYOBU_CODEX_TEST_LOG="$codex_log" \
  BYOBU_SESSION_STATE_DIR="$snapshot_dir" \
  "$user_bin/byobu-session-state" restore codex "$restored_session" >/dev/null

sleep 0.5
grep -Fxq -- "--sandbox danger-full-access --ask-for-approval never resume $thread_id" "$codex_log" || {
  echo "installed byobu-session-state restore did not relaunch Codex with full permissions" >&2
  exit 1
}

echo "installed codex test passed"
