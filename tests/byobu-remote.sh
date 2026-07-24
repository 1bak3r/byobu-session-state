#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
fake_bin="$tmp_dir/bin"
log_file="$tmp_dir/remote.log"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if ! command -v script >/dev/null 2>&1; then
  echo "script command not available; skipping byobu-remote TTY test"
  exit 0
fi

mkdir -p "$fake_bin"
: > "$log_file"

cat > "$fake_bin/byobu-session-state" <<EOF
#!/usr/bin/env bash
printf 'state:%s\n' "\$*" >> "$log_file"
EOF
chmod +x "$fake_bin/byobu-session-state"

cat > "$fake_bin/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >> "$log_file"
args=("\$@")
if [ "\${args[0]:-}" = "-L" ]; then
  args=("\${args[@]:2}")
fi
if [ "\${args[0]:-}" = "list-sessions" ]; then
  printf 'old\t4\t0\t100\n'
  printf 'attached\t1\t1\t90\n'
elif [ "\${args[0]:-}" = "list-windows" ]; then
  case " \${args[*]} " in
    *' -t old '*)
      printf 'thread-a\nthread-b\nthread-c\nthread-d\n'
      ;;
    *' -t attached '*)
      printf 'thread-z\n'
      ;;
  esac
fi
EOF
chmod +x "$fake_bin/tmux"

cat > "$fake_bin/byobu-tmux" <<EOF
#!/usr/bin/env bash
printf 'byobu-tmux:%s\n' "\$*" >> "$log_file"
EOF
chmod +x "$fake_bin/byobu-tmux"

cat > "$fake_bin/byobu" <<EOF
#!/usr/bin/env bash
printf 'byobu:%s\n' "\$*" >> "$log_file"
exit 70
EOF
chmod +x "$fake_bin/byobu"

env PATH="$fake_bin:$PATH" BYOBU_REMOTE_SNAPSHOT=test \
  script -qfec "$repo_root/bin/byobu-remote" /dev/null >/dev/null

grep -Fxq "state:autorestore --restart-codex test" "$log_file" || {
  echo "byobu-remote did not run safe autorestore first" >&2
  exit 1
}

grep -Fxq "byobu-tmux:attach-session -t old" "$log_file" || {
  echo "byobu-remote did not attach to the selected live session" >&2
  cat "$log_file" >&2
  exit 1
}

if grep -q '^byobu:' "$log_file"; then
  echo "byobu-remote called byobu instead of attaching to the live tmux session" >&2
  exit 1
fi

: > "$log_file"
env PATH="$fake_bin:$PATH" BYOBU_REMOTE_SESSION=old \
  script -qfec "$repo_root/bin/byobu-remote" /dev/null >/dev/null

grep -Fxq "byobu-tmux:attach-session -t old" "$log_file" || {
  echo "byobu-remote did not honor BYOBU_REMOTE_SESSION" >&2
  exit 1
}

: > "$log_file"
env PATH="$fake_bin:$PATH" BYOBU_REMOTE_SOCKET=byobu-main \
  script -qfec "$repo_root/bin/byobu-remote" /dev/null >/dev/null

grep -Fxq "tmux:-L byobu-main list-sessions -F #{session_name}	#{session_windows}	#{session_attached}	#{session_activity}" "$log_file" || {
  echo "byobu-remote did not list sessions through the named tmux socket" >&2
  cat "$log_file" >&2
  exit 1
}

grep -Fxq "tmux:-L byobu-main attach-session -t old" "$log_file" || {
  echo "byobu-remote did not attach through the named tmux socket" >&2
  cat "$log_file" >&2
  exit 1
}

echo "byobu-remote test passed"
