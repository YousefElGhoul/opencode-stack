#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

docker compose config --quiet
if ! docker compose up --detach --pull missing --wait; then
  "$root/scripts/doctor.sh" || true
  exit 1
fi
image=$(docker compose config --images | grep '^ghcr.io/anomalyco/opencode:')
version=${image%%@*}
version=${version##*:}
docker image tag "$image" "opencode-stack/opencode:$version"
image=$(docker compose config --images | grep '^mcr.microsoft.com/playwright/mcp:')
version=${image%%@*}
version=${version##*:}
docker image tag "$image" "opencode-stack/playwright-mcp:$version"
"$root/scripts/doctor.sh"
printf 'OpenCode is available at http://127.0.0.1:4096\n'
