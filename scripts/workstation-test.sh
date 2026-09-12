#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
fixture="$root/tests/workstation"
scratch=
cleanup() {
  if [ -n "$scratch" ]; then
    docker compose exec -T opencode sh -eu -c '
      if [ -f "$1/pid" ]; then
        pid=$(cat "$1/pid")
        cmd=$(tr "\000" " " < "/proc/$pid/cmdline" 2>/dev/null || true)
        case "$cmd" in
          *"$2/node_modules/vite/bin/vite.js"*) kill -TERM "$pid" 2>/dev/null || true ;;
        esac
      fi
      rm -f "$1/pid" "$1/server.log"
      rmdir "$1"
    ' sh "$scratch" "$fixture"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

python3 scripts/dependencies.py --check
docker compose exec -T opencode toolchain-check
docker compose exec -T -w "$fixture" opencode sh -eu -c 'npm ci --no-audit --no-fund; npm run build'
scratch=$(docker compose exec -T opencode mktemp -d /tmp/opencode/workstation-test.XXXXXXXXXX)
docker compose exec -d -w "$fixture" opencode sh -eu -c '
  printf "%s\n" "$$" > "$1/pid"
  exec node "$2/node_modules/vite/bin/vite.js" --host 127.0.0.1 --port 4321 --strictPort > "$1/server.log" 2>&1
' sh "$scratch" "$fixture"
attempt=0
until docker compose exec -T opencode curl -fsS http://127.0.0.1:4321/ 2>/dev/null | grep -q 'Remote workstation is ready'; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 30 ]; then
    docker compose exec -T opencode cat "$scratch/server.log"
    exit 1
  fi
  sleep 1
done
docker compose exec -T opencode browser-check http://127.0.0.1:4321
printf 'PASS: clean install, native Tailwind build, and real browser rendering over shared localhost\n'
