#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
failed=0
workspace=
host_uid=
host_gid=
container=
probe=

cleanup() {
  if [ -n "$probe" ]; then
    # A host fallback also works if the container stopped during the test.
    if docker exec "$container" rm -f -- "$probe" 2>/dev/null || rm -f -- "$probe"; then
      probe=
    else
      fail 'Could not remove the temporary workspace ownership probe'
      return 1
    fi
  fi
}
trap 'cleanup || exit 1' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

ok() { printf 'ok: %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; failed=1; }

. "$root/scripts/host-user.sh"
if resolve_host_user; then
  ok "Intended host user: $host_user ($host_uid:$host_gid)"
else
  fail 'Cannot resolve the intended non-root host user'
fi

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
  configured_uid=$(awk -F= '$1 == "HOST_UID" {print $2; exit}' .env)
  configured_gid=$(awk -F= '$1 == "HOST_GID" {print $2; exit}' .env)
  if [ -n "$configured_uid" ] && [ -n "$configured_gid" ]; then
    ok 'HOST_UID and HOST_GID are configured'
    if [ "$configured_uid:$configured_gid" = "$host_uid:$host_gid" ]; then
      ok "Configured UID/GID match $host_user ($host_uid:$host_gid)"
    else
      fail "Configured $configured_uid:$configured_gid does not match intended $host_uid:$host_gid"
    fi
  else
    fail 'HOST_UID and HOST_GID must be set by setup.sh'
  fi
  if [ "$(stat -c '%u:%g' .env)" = "$host_uid:$host_gid" ]; then
    ok '.env is owned by the intended host user and primary group'
  else
    fail '.env ownership does not match the intended host user'
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
  fail 'Playwright MCP container is not running'
fi

if command -v docker >/dev/null 2>&1 && docker compose ps --status running --services 2>/dev/null | grep -qx opencode; then
  container=$(docker compose ps -q opencode)
  if docker inspect --format '{{range .Mounts}}{{printf "%s|%s|%s|%t\n" .Type .Source .Destination .RW}}{{end}}' "$container" 2>/dev/null | grep -Fqx "bind|$workspace|$workspace|true"; then
    ok 'Workspace source and container target are the same absolute path'
  else
    fail 'Running container does not use the configured same-path workspace mount'
  fi
  if docker inspect --format '{{range .Mounts}}{{printf "%s|%s|%s|%t\n" .Type .Source .Destination .RW}}{{end}}' "$container" | grep -Fqx "bind|$root/opencode|/home/opencode/.config/opencode|false"; then
    ok 'OpenCode config bind mount is read-only'
  else
    fail 'OpenCode config bind mount is missing or writable'
  fi
  runtime_user=$(docker inspect --format '{{.Config.User}}' "$container")
  if [ "$runtime_user" = "$host_uid:$host_gid" ] && docker exec "$container" sh -eu -c '
    found=0
    for status in /proc/[0-9]*/status; do
      [ "$(awk '\''$1 == "Name:" {print $2}'\'' "$status" 2>/dev/null)" = opencode ] || continue
      found=1
      awk -v uid="$1" -v gid="$2" '\''
        $1 == "Uid:" { if ($2 != uid || $3 != uid || $4 != uid || $5 != uid) exit 1; u=1 }
        $1 == "Gid:" { if ($2 != gid || $3 != gid || $4 != gid || $5 != gid) exit 1; g=1 }
        END { if (!u || !g) exit 1 }
      '\'' "$status"
    done
    test "$found" = 1
  ' sh "$host_uid" "$host_gid"; then
    ok "Running OpenCode process UID/GID: $host_uid:$host_gid"
  else
    fail 'Running OpenCode process UID/GID does not match the intended user'
  fi
  if docker exec "$container" sh -eu -c '
    for dir in "$HOME/.local" "$HOME/.local/share/opencode" "$HOME/.local/state/opencode"; do
      test -w "$dir"
      file=$(mktemp "$dir/.doctor-write.XXXXXXXXXX")
      rm -f "$file"
    done
    test -w "$HOME/.local/share/opencode/opencode.db"
    if [ -e "$HOME/.local/share/opencode/auth.json" ]; then
      test -r "$HOME/.local/share/opencode/auth.json"
      test -w "$HOME/.local/share/opencode/auth.json"
    fi
  '; then
    ok 'Persistent data, state, database, and existing auth file are writable by OpenCode'
  else
    fail 'Persistent OpenCode data is not writable; see the migration instructions'
  fi
  # Reserve a unique name first so the EXIT trap knows it even if exec fails.
  if [ -d "$workspace" ] && probe=$(mktemp "$workspace/.opencode-owner.XXXXXXXXXX"); then
    rm -f -- "$probe"
    if docker exec "$container" sh -eu -c 'set -C; : > "$1"' sh "$probe"; then
      owner=$(stat -c '%u:%g' "$probe")
      if [ "$owner" = "$host_uid:$host_gid" ]; then
        ok "Container-created workspace file is owned by $host_user ($owner)"
      else
        fail "Container-created workspace file has unexpected ownership: $owner"
      fi
    else
      fail 'OpenCode cannot create a file in the workspace'
    fi
    if cleanup; then ok 'Temporary workspace ownership file cleaned up'; fi
  else
    fail 'Cannot reserve temporary workspace ownership test path'
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

  if docker exec "$container" sh -eu -c '
    auth=$(printf "opencode:%s" "$OPENCODE_SERVER_PASSWORD" | base64 | tr -d "\n")
    wget -qO- --header="Authorization: Basic $auth" http://127.0.0.1:4096/global/health
  ' | grep -q '"healthy":true'; then
    ok 'Authenticated OpenCode health endpoint is healthy'
  else
    fail 'Authenticated OpenCode health endpoint failed'
  fi

  published=$(docker compose port opencode 4096 2>/dev/null || true)
  bindings=$(docker inspect --format '{{range $port, $bindings := .HostConfig.PortBindings}}{{range $bindings}}{{printf "%s|%s:%s\n" $port .HostIp .HostPort}}{{end}}{{end}}' "$container")
  if [ "$published" = '127.0.0.1:4096' ] && [ "$bindings" = '4096/tcp|127.0.0.1:4096' ]; then
    ok 'Port 4096 is published on IPv4 loopback only'
  else
    fail "Unexpected port publication: ${bindings:-none}"
  fi
else
  fail 'OpenCode container is not running'
fi

[ "$failed" -eq 0 ]
