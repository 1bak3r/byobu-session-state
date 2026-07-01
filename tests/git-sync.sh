#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
tmux_tmp="$tmp_dir/tmux"
session_name="byobu-git-sync-test-$$"

unset TMUX TMUX_PANE
mkdir -p "$tmux_tmp"
export TMUX_TMPDIR="$tmux_tmp"

cleanup() {
  tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

remote="$tmp_dir/remote.git"
target_remote="$tmp_dir/byobu-tabs.git"
target_checkout="$tmp_dir/byobu-tabs-checkout"
work="$tmp_dir/work"
other="$tmp_dir/other"
state="$tmp_dir/state"
target_state="$tmp_dir/byobu-tabs-state"

git init --bare "$remote" >/dev/null
git init --bare "$target_remote" >/dev/null
git clone "$remote" "$work" >/dev/null 2>&1
git -C "$work" config user.name "Test User"
git -C "$work" config user.email "test@example.com"
printf 'initial\n' > "$work/file.txt"
git -C "$work" add file.txt
git -C "$work" commit -m "initial" >/dev/null
git -C "$work" push -u origin main >/dev/null 2>&1 || git -C "$work" push -u origin master >/dev/null 2>&1

tmux new-session -d -s "$session_name" -n repo -c "$work"

env \
  BYOBU_GIT_SYNC_STATE_DIR="$state" \
  BYOBU_GIT_SYNC_TMUX_TARGET="$session_name" \
  BYOBU_GIT_SYNC_TARGET_DIR="$target_state" \
  BYOBU_GIT_SYNC_TARGET_REMOTE_URL="$target_remote" \
  BYOBU_GIT_SYNC_ALLOW_NON_GITHUB=1 \
  "$repo_root/bin/byobu-git-sync" repos > "$tmp_dir/repos.out"
grep -Fxq "$work" "$tmp_dir/repos.out"

printf 'checkpoint\n' >> "$work/file.txt"
env \
  BYOBU_GIT_SYNC_STATE_DIR="$state" \
  BYOBU_GIT_SYNC_TMUX_TARGET="$session_name" \
  BYOBU_GIT_SYNC_TARGET_DIR="$target_state" \
  BYOBU_GIT_SYNC_TARGET_REMOTE_URL="$target_remote" \
  BYOBU_GIT_SYNC_ALLOW_NON_GITHUB=1 \
  "$repo_root/bin/byobu-git-sync" push > "$tmp_dir/push.out"
git --git-dir="$remote" log --oneline --all | grep -q 'byobu autosync:'
git --git-dir="$target_remote" log --oneline --all | grep -q 'byobu tabs autosync:'
git clone -b main "$target_remote" "$target_checkout" >/dev/null 2>&1
grep -q "$session_name" "$target_checkout/tabs/live.tsv"
grep -q "$session_name" "$target_checkout/metadata/session-map.tsv"
test -f "$target_checkout/snapshots/$session_name.snapshot"

git clone "$remote" "$other" >/dev/null 2>&1
git -C "$other" config user.name "Test User"
git -C "$other" config user.email "test@example.com"
printf 'remote\n' >> "$other/file.txt"
git -C "$other" commit -am "remote update" >/dev/null
git -C "$other" push >/dev/null 2>&1

env \
  BYOBU_GIT_SYNC_STATE_DIR="$state" \
  BYOBU_GIT_SYNC_TMUX_TARGET="$session_name" \
  BYOBU_GIT_SYNC_TARGET_DIR="$target_state" \
  BYOBU_GIT_SYNC_TARGET_REMOTE_URL="$target_remote" \
  BYOBU_GIT_SYNC_ALLOW_NON_GITHUB=1 \
  "$repo_root/bin/byobu-git-sync" pull > "$tmp_dir/pull.out"
grep -q 'remote' "$work/file.txt"

echo "git-sync test passed"
