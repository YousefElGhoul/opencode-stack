#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

. "$root/scripts/host-user.sh"
resolve_host_user
command -v python3 >/dev/null 2>&1 || {
  printf 'Host Python 3 is required to generate dependency mounts.\n' >&2
  exit 1
}
docker compose -f compose.yaml config --quiet
docker compose -f compose.yaml build opencode
python3 "$root/scripts/dependencies.py"
docker compose config --quiet
if ! docker compose up --detach --wait; then
  "$root/scripts/doctor.sh" || true
  exit 1
fi
image=$(docker compose config --images | grep '^mcr.microsoft.com/playwright/mcp:')
version=${image%%@*}
version=${version##*:}
docker image tag "$image" "opencode-stack/playwright-mcp:$version"
"$root/scripts/doctor.sh"
printf 'OpenCode is available at http://127.0.0.1:4096\n'
