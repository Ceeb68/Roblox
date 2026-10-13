#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
tools_dir="${ROBLOX_TOOLS_DIR:-/workspace/.roblox-tools}"
export PATH="$tools_dir/bin:$PATH"
exec rojo serve default.project.json --address 127.0.0.1 --port 34872
