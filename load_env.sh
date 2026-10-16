#!/usr/bin/env bash

# Source the project-local configuration and export it to child processes.
# Existing environment variables remain usable when no .env file exists.
load_project_env() {
  local env_file="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/.env"
  local autoexport_was_set=false
  [[ $- == *a* ]] && autoexport_was_set=true
  if [[ -f "$env_file" ]]; then
    set -a
    source "$env_file"
    if ! "$autoexport_was_set"; then
      set +a
    fi
  fi
}

load_project_env
unset -f load_project_env
