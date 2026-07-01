#!/usr/bin/env bash
set -euo pipefail

install_root="${INSTALL_ROOT:-$HOME/.local/lib/byobu-session-state}"
bin_root="$install_root/bin"
user_bin="${USER_BIN_DIR:-$HOME/.local/bin}"
user_systemd_dir="${USER_SYSTEMD_DIR:-$HOME/.config/systemd/user}"

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user disable --now byobu-session-autosave.timer >/dev/null 2>&1 || true
  systemctl --user disable --now byobu-session-watchdog.timer >/dev/null 2>&1 || true
  systemctl --user disable --now byobu-session-shutdown-save.service >/dev/null 2>&1 || true
  systemctl --user disable --now byobu-session-autorestore.service >/dev/null 2>&1 || true
  systemctl --user disable --now byobu-git-sync-push.timer >/dev/null 2>&1 || true
  systemctl --user disable --now byobu-git-sync-pull.timer >/dev/null 2>&1 || true
fi

rm -f "$user_bin/byobu-session-state"
rm -f "$user_bin/byobu"
rm -f "$user_bin/byobu-codex"
rm -f "$user_bin/byobu-remote"
rm -f "$user_bin/byobu-git-sync"
rm -f "$bin_root/byobu-session-state"
rm -f "$bin_root/byobu"
rm -f "$bin_root/byobu-codex"
rm -f "$bin_root/byobu-remote"
rm -f "$bin_root/byobu-git-sync"
rm -f "$user_systemd_dir/byobu-session-autorestore.service"
rm -f "$user_systemd_dir/byobu-session-autosave.service"
rm -f "$user_systemd_dir/byobu-session-autosave.timer"
rm -f "$user_systemd_dir/byobu-session-watchdog.service"
rm -f "$user_systemd_dir/byobu-session-watchdog.timer"
rm -f "$user_systemd_dir/byobu-session-shutdown-save.service"
rm -f "$user_systemd_dir/byobu-git-sync-push.service"
rm -f "$user_systemd_dir/byobu-git-sync-push.timer"
rm -f "$user_systemd_dir/byobu-git-sync-pull.service"
rm -f "$user_systemd_dir/byobu-git-sync-pull.timer"
rmdir "$bin_root" 2>/dev/null || true
rmdir "$install_root" 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload
fi

cat <<EOF
Removed byobu-session-state.

Saved snapshots were not removed. Default snapshot directory:
  $HOME/.local/state/byobu-session-state
EOF
