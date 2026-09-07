#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

docker compose config --quiet
docker compose stop opencode

restart_server() {
  docker compose up --detach >/dev/null 2>&1 || true
}
trap restart_server EXIT HUP INT TERM

docker compose run --rm --no-deps \
  --publish 127.0.0.1:1455:1455 \
  --entrypoint opencode \
  opencode auth login

trap - EXIT HUP INT TERM
"$root/scripts/start.sh"
