#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
failed=0

ok() { printf 'ok: %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; failed=1; }

if command -v docker >/dev/null 2>&1; then
  ok 'Docker command found'
else
  fail 'Docker is not installed or is not on PATH'
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  ok 'Docker Compose plugin found'
else
  fail 'Docker Compose plugin is unavailable'
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  ok 'Docker daemon is reachable'
else
  fail 'Docker daemon is not reachable by this user'
fi

if [ -f .env ]; then
  ok '.env exists'
  mode=$(stat -c '%a' .env 2>/dev/null || true)
  if [ "$mode" = 600 ]; then
    ok '.env permissions are 0600'
  else
    fail ".env permissions are ${mode:-unknown}; run: chmod 600 .env"
  fi
  if grep -q '^OPENCODE_SERVER_PASSWORD=replace-' .env; then
    fail 'OPENCODE_SERVER_PASSWORD still contains the example value'
  fi
  workspace=$(awk -F= '$1 == "WORKSPACE_DIR" { sub(/^[^=]*=/, ""); print; exit }' .env)
  case "$workspace" in
    /*)
      if [ -d "$workspace" ]; then
        ok "Workspace path exists: $workspace"
      else
        fail "Workspace path does not exist: $workspace"
      fi
      ;;
    *) fail 'WORKSPACE_DIR must be an absolute path' ;;
  esac
else
  fail '.env is missing; run ./scripts/setup.sh /absolute/path/to/workspace'
fi

if [ -f .env ] && docker compose config --quiet >/dev/null 2>&1; then
  ok 'Compose configuration is valid'
else
  fail 'Compose configuration is invalid'
fi

if [ -f opencode/opencode.json ] && [ ! -w opencode/opencode.json ]; then
  ok 'OpenCode config is not host-writable'
elif [ -f opencode/opencode.json ]; then
  ok 'OpenCode config exists (Compose mounts it read-only)'
else
  fail 'opencode/opencode.json is missing'
fi

if command -v tailscale >/dev/null 2>&1; then
  ok 'Tailscale command found on host (not managed by Compose)'
else
  printf 'info: Tailscale is not installed; local access is unaffected.\n'
fi

if command -v docker >/dev/null 2>&1 && docker compose ps --status running --services 2>/dev/null | grep -qx playwright; then
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$(docker compose ps -q playwright)")
  if [ "$health" = healthy ]; then
    ok 'Playwright MCP container is healthy'
  else
    fail "Playwright MCP container health is $health"
  fi
else
  printf 'info: Playwright MCP container is not running.\n'
fi

if command -v docker >/dev/null 2>&1 && docker compose ps --status running --services 2>/dev/null | grep -qx opencode; then
  container=$(docker compose ps -q opencode)
  if docker inspect --format '{{range .Mounts}}{{printf "%s|%s\n" .Source .Destination}}{{end}}' "$container" 2>/dev/null | grep -Fqx "$workspace|$workspace"; then
    ok 'Workspace source and container target are the same absolute path'
  else
    fail 'Running container does not use the configured same-path workspace mount'
  fi
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container")
  if [ "$health" = healthy ]; then
    ok 'OpenCode container is healthy'
  else
    fail "OpenCode container health is $health"
    health_log=$(docker inspect --format '{{range .State.Health.Log}}{{.Output}}{{end}}' "$(docker compose ps -q opencode)" 2>/dev/null || true)
    if [ -n "$health_log" ]; then
      printf '%s\n' "$health_log" >&2
    fi
  fi

  published=$(docker compose port opencode 4096 2>/dev/null || true)
  if [ "$published" = '127.0.0.1:4096' ]; then
    ok 'Port 4096 is published on IPv4 loopback only'
  else
    fail "Unexpected port publication: ${published:-none}"
  fi
else
  printf 'info: OpenCode container is not running.\n'
fi

[ "$failed" -eq 0 ]
