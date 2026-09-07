#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s /absolute/path/to/workspace\n' "$0" >&2
  exit 2
fi

workspace=$1
case "$workspace" in
  /*) ;;
  *) printf 'WORKSPACE_DIR must be an absolute path.\n' >&2; exit 1 ;;
esac

if [ ! -d "$workspace" ]; then
  printf 'Workspace directory does not exist: %s\n' "$workspace" >&2
  exit 1
fi

if [ -e .env ] || [ -L .env ]; then
  printf '.env already exists; refusing to overwrite it.\n' >&2
  exit 1
fi

command -v docker >/dev/null 2>&1 || {
  printf 'Docker is not installed or is not on PATH.\n' >&2
  exit 1
}
docker compose version >/dev/null
docker info >/dev/null

password=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
umask 077
{
  printf 'OPENCODE_VERSION=1.18.29\n'
  printf 'OPENCODE_IMAGE_DIGEST=sha256:ecc3bf96ee55dad226d9cde50d79aaa8a1215c47860c0fcdc71570461bf438b8\n'
  printf 'WORKSPACE_DIR=%s\n' "$workspace"
  printf 'OPENCODE_SERVER_PASSWORD=%s\n' "$password"
} > .env

docker compose config --quiet
docker compose pull
image=$(docker compose config --images)
version=${image%%@*}
version=${version##*:}
docker image tag "$image" "opencode-stack/opencode:$version"
printf 'Created .env with mode 0600 and pulled the pinned OpenCode image.\n'
printf 'Run ./scripts/start.sh to start the server.\n'
