#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ]; then
  printf 'OpenCode must run as the configured non-root host UID/GID.\n' >&2
  exit 1
fi
for dir in "$HOME" "$HOME/.config" "$HOME/.config/opencode" "$HOME/.cache" \
  "$HOME/.local/share/opencode" "$HOME/.local/state/opencode" /tmp/opencode; do
  mkdir -p "$dir"
  if [ ! -w "$dir" ]; then
    printf 'Runtime directory is not writable: %s (uid=%s gid=%s). See README.md.\n' "$dir" "$(id -u)" "$(id -g)" >&2
    exit 1
  fi
done
exec opencode "$@"
