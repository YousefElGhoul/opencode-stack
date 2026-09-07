#!/bin/bash
set -euo pipefail

export MISE_MINIMUM_RELEASE_AGE=0

run_local() {
  exec mise x opencode -- opencode "$@"
}

# Omarchy's c alias puts --auto before the project or subcommand.
while [[ ${1:-} == --auto ]]; do
  shift
done

case "${1:-}" in
  local)
    shift
    run_local "$@"
    ;;
  completion|acp|mcp|attach|run|debug|providers|auth|agent|upgrade|uninstall|serve|web|models|stats|export|import|github|pr|session|plugin|plug|db)
    run_local "$@"
    ;;
  -h|--help|-v|--version)
    run_local "$@"
    ;;
esac

config_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/opencode-stack
workspace_file=$config_dir/workspace
password_file=$config_dir/password

if [[ -r $workspace_file ]]; then
  IFS= read -r workspace < "$workspace_file"
else
  workspace=$HOME/Projects
fi
workspace=$(realpath -e -- "$workspace")

directory=$(pwd -P)
explicit_directory=false
if [[ $# -gt 0 && $1 != -* ]]; then
  directory=$(realpath -e -- "$1")
  explicit_directory=true
  shift
fi

if [[ ! -d $directory ]]; then
  printf 'Not a directory: %s\n' "$directory" >&2
  exit 2
fi

case "$directory" in
  "$workspace"|"$workspace"/*) ;;
  *)
    if [[ $explicit_directory == false ]]; then
      directory=$workspace
    else
      printf 'Directory is outside the mounted workspace %s: %s\n' "$workspace" "$directory" >&2
      printf 'Use "opencode local ..." to run the local CLI instead.\n' >&2
      exit 2
    fi
    ;;
esac

if [[ -z ${OPENCODE_SERVER_PASSWORD:-} ]]; then
  if [[ ! -r $password_file ]]; then
    printf 'OpenCode client credentials are missing. Rerun opencode-stack/scripts/setup.sh.\n' >&2
    exit 1
  fi
  IFS= read -r OPENCODE_SERVER_PASSWORD < "$password_file"
  export OPENCODE_SERVER_PASSWORD
fi

args=()
for arg in "$@"; do
  # attach does not expose the local TUI's --auto option; server permissions apply.
  [[ $arg == --auto ]] || args+=("$arg")
done

exec mise x opencode -- opencode attach http://127.0.0.1:4096 --dir "$directory" "${args[@]}"
