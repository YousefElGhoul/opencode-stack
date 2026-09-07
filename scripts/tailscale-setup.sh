#!/bin/sh
set -eu

command -v tailscale >/dev/null 2>&1 || {
  printf 'Tailscale is not installed or is not on PATH.\n' >&2
  exit 1
}

sudo systemctl enable --now tailscaled
sudo tailscale up
sudo tailscale serve --bg http://127.0.0.1:4096

printf '\nOpen this tailnet-only URL on your phone:\n'
sudo tailscale serve status
