#!/bin/sh
# Sourced by setup and doctor. Root must identify the intended non-root user.
resolve_host_user() {
  host_user=$(id -un)
  if [ "$(id -u)" -eq 0 ]; then
    host_user=${SUDO_USER:-}
    if [ -z "$host_user" ] || [ "$host_user" = root ]; then
      printf 'Run as your normal user or through sudo (with SUDO_USER set).\n' >&2
      return 1
    fi
  fi
  host_uid=$(id -u "$host_user") || return 1
  host_gid=$(id -g "$host_user") || return 1
  if [ "$host_uid" -eq 0 ] || [ "$host_gid" -eq 0 ]; then
    printf 'The intended host UID and primary GID must both be non-root.\n' >&2
    return 1
  fi
}
