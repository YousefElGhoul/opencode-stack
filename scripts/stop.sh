#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

docker compose down
printf 'OpenCode stopped. The opencode-data volume was retained.\n'
