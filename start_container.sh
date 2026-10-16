#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/load_env.sh"

mkdir -p "$SCRIPT_DIR/build"
rm -f "$SCRIPT_DIR/build/install.log"
bash "$SCRIPT_DIR/maak_container_free" 2>&1 | tee "$SCRIPT_DIR/build/install.log"
