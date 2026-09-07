#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [absolute/path/to/workspace]\n' "$0" >&2
  exit 2
fi

command -v docker >/dev/null 2>&1 || {
  printf 'Docker is not installed or is not on PATH.\n' >&2
  exit 1
}
docker compose version >/dev/null
docker info >/dev/null

umask 077

set_env() {
  key=$1
  value=$2
  tmp=".env.tmp.$$"
  awk -v key="$key" 'index($0, key "=") != 1' .env > "$tmp"
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" .env
}

ensure_env() {
  key=$1
  value=$2
  grep -q "^${key}=" .env || set_env "$key" "$value"
}

prompt_secret() {
  label=$1
  key=$2
  required=$3
  if grep -q "^${key}=." .env; then
    suffix=' (blank keeps current value)'
  elif [ "$required" = true ]; then
    suffix=' (required)'
  else
    suffix=' (optional; blank skips)'
  fi

  printf '%s%s: ' "$label" "$suffix" > /dev/tty
  trap 'stty echo < /dev/tty 2>/dev/null || true' EXIT HUP INT TERM
  stty -echo < /dev/tty
  IFS= read -r secret < /dev/tty || secret=
  stty echo < /dev/tty
  trap - EXIT HUP INT TERM
  printf '\n' > /dev/tty

  if [ -z "$secret" ]; then
    if [ "$required" = true ] && ! grep -q "^${key}=." .env; then
      printf '%s is required.\n' "$label" >&2
      exit 1
    fi
    return
  fi
  case "$secret" in
    *[!A-Za-z0-9._-]*)
      printf '%s contains unsupported whitespace or punctuation.\n' "$label" >&2
      exit 1
      ;;
  esac
  set_env "$key" "$secret"
}

install_client() {
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    client_user=$SUDO_USER
    client_home=$(getent passwd "$client_user" | cut -d: -f6)
  else
    client_user=$(id -un)
    client_home=$HOME
  fi
  client_group=$(id -gn "$client_user")
  client_config="$client_home/.config/opencode-stack"
  client_bin="$client_home/.local/bin"

  workspace=$(awk -F= '$1 == "WORKSPACE_DIR" { sub(/^[^=]*=/, ""); print; exit }' .env)
  password=$(awk -F= '$1 == "OPENCODE_SERVER_PASSWORD" { sub(/^[^=]*=/, ""); print; exit }' .env)
  [ -n "$workspace" ] || { printf 'WORKSPACE_DIR is missing from .env.\n' >&2; exit 1; }
  [ -n "$password" ] || { printf 'OPENCODE_SERVER_PASSWORD is missing from .env.\n' >&2; exit 1; }

  install -d -m 700 -o "$client_user" -g "$client_group" "$client_config"
  printf '%s\n' "$workspace" > "$client_config/workspace"
  printf '%s\n' "$password" > "$client_config/password"
  chmod 600 "$client_config/workspace" "$client_config/password"
  chown "$client_user:$client_group" "$client_config/workspace" "$client_config/password"
  install -d -m 755 -o "$client_user" -g "$client_group" "$client_bin"
  install -m 755 -o "$client_user" -g "$client_group" scripts/opencode-client.sh "$client_bin/opencode"

  # A PATH prepend alone is undone when mise refreshes the shell environment.
  client_shell=$(getent passwd "$client_user" | cut -d: -f7)
  case "$client_shell" in
    */bash)
      shell_launcher='opencode() { "$HOME/.local/bin/opencode" "$@"; }'
      if ! grep -Fqx "$shell_launcher" "$client_home/.bashrc" 2>/dev/null; then
        printf '\n# Keep the server launcher ahead of mise tool paths.\n%s\n' "$shell_launcher" >> "$client_home/.bashrc"
        chown "$client_user:$client_group" "$client_home/.bashrc"
      fi
      ;;
  esac
}

if [ -e .env ] || [ -L .env ]; then
  [ -L .env ] && {
    printf 'Refusing to modify a symlinked .env file.\n' >&2
    exit 1
  }
  chmod 600 .env
  if [ "$#" -eq 1 ]; then
    workspace=$1
    case "$workspace" in
      /*) ;;
      *) printf 'WORKSPACE_DIR must be an absolute path.\n' >&2; exit 1 ;;
    esac
    [ -d "$workspace" ] || {
      printf 'Workspace directory does not exist: %s\n' "$workspace" >&2
      exit 1
    }
    set_env WORKSPACE_DIR "$workspace"
  fi
else
  [ "$#" -eq 1 ] || {
    printf 'Usage: %s /absolute/path/to/workspace\n' "$0" >&2
    exit 2
  }
  workspace=$1
  case "$workspace" in
    /*) ;;
    *) printf 'WORKSPACE_DIR must be an absolute path.\n' >&2; exit 1 ;;
  esac
  [ -d "$workspace" ] || {
    printf 'Workspace directory does not exist: %s\n' "$workspace" >&2
    exit 1
  }
  password=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
  : > .env
  set_env WORKSPACE_DIR "$workspace"
  set_env OPENCODE_SERVER_PASSWORD "$password"
fi

ensure_env OPENCODE_VERSION 1.18.29
ensure_env OPENCODE_IMAGE_DIGEST sha256:ecc3bf96ee55dad226d9cde50d79aaa8a1215c47860c0fcdc71570461bf438b8
ensure_env PLAYWRIGHT_MCP_VERSION v0.0.80
ensure_env PLAYWRIGHT_MCP_IMAGE_DIGEST sha256:dda1f7f9b812e22946635c8af7df9288b96d3b9e3f0f1b8576d6823e2031c1de

prompt_secret 'Exa API key' EXA_API_KEY false
prompt_secret 'Context7 API key' CONTEXT7_API_KEY false
prompt_secret 'GitHub personal access token' GITHUB_PERSONAL_ACCESS_TOKEN true
prompt_secret 'Postman API key' POSTMAN_API_KEY true

install_client

docker compose config --quiet
docker compose pull
image=$(docker compose config --images | grep '^ghcr.io/anomalyco/opencode:')
version=${image%%@*}
version=${version##*:}
docker image tag "$image" "opencode-stack/opencode:$version"
image=$(docker compose config --images | grep '^mcr.microsoft.com/playwright/mcp:')
version=${image%%@*}
version=${version##*:}
docker image tag "$image" "opencode-stack/playwright-mcp:$version"
printf 'Configured .env with mode 0600 and pulled the pinned images.\n'
printf 'Installed the authenticated client launcher in ~/.local/bin/opencode.\n'
printf 'Open a new Bash shell to load the launcher function; other shells should invoke ~/.local/bin/opencode explicitly.\n'
printf 'Run ./scripts/start.sh to start the server.\n'
