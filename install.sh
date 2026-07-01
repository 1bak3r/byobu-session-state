#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")" && pwd)
install_root="${INSTALL_ROOT:-$HOME/.local/lib/byobu-session-state}"
bin_root="$install_root/bin"
user_bin="${USER_BIN_DIR:-$HOME/.local/bin}"
user_systemd_dir="${USER_SYSTEMD_DIR:-$HOME/.config/systemd/user}"

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mkdir -p "$bin_root" "$user_bin" "$user_systemd_dir"

install -m 0755 "$repo_root/bin/byobu-session-state" "$bin_root/byobu-session-state"
install -m 0755 "$repo_root/bin/byobu-session-plan" "$bin_root/byobu-session-plan"
install -m 0755 "$repo_root/bin/byobu" "$bin_root/byobu"
install -m 0755 "$repo_root/bin/byobu-codex" "$bin_root/byobu-codex"
install -m 0755 "$repo_root/bin/byobu-remote" "$bin_root/byobu-remote"
install -m 0755 "$repo_root/bin/byobu-git-sync" "$bin_root/byobu-git-sync"
ln -sfn "$bin_root/byobu-session-state" "$user_bin/byobu-session-state"
ln -sfn "$bin_root/byobu-session-plan" "$user_bin/byobu-session-plan"
ln -sfn "$bin_root/byobu" "$user_bin/byobu"
ln -sfn "$bin_root/byobu-codex" "$user_bin/byobu-codex"
ln -sfn "$bin_root/byobu-remote" "$user_bin/byobu-remote"
ln -sfn "$bin_root/byobu-git-sync" "$user_bin/byobu-git-sync"

if [ -d "$repo_root/systemd/user" ]; then
  install -m 0644 "$repo_root/systemd/user/"*.service "$user_systemd_dir/"
  install -m 0644 "$repo_root/systemd/user/"*.timer "$user_systemd_dir/"
fi

systemd_status="not enabled"
if ! truthy "${BYOBU_SESSION_STATE_SKIP_SYSTEMD:-0}" && command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable --now byobu-session-autosave.timer >/dev/null
  systemctl --user enable --now byobu-session-watchdog.timer >/dev/null
  systemctl --user enable --now byobu-session-shutdown-save.service >/dev/null
  systemctl --user enable --now byobu-session-autorestore.service >/dev/null
  systemctl --user enable --now byobu-git-sync-push.timer >/dev/null
  systemctl --user enable --now byobu-git-sync-pull.timer >/dev/null
  systemd_status="enabled"
fi

cat <<EOF
Installed byobu-session-state.

Commands:
  $user_bin/byobu-session-state
  $user_bin/byobu-session-plan
  $user_bin/byobu
  $user_bin/byobu-codex
  $user_bin/byobu-remote
  $user_bin/byobu-git-sync

User systemd autosave/autosync units: $systemd_status

If ~/.local/bin is not already on PATH, add:
  export PATH="\$HOME/.local/bin:\$PATH"
EOF
