#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
runtime_dir="${DIRTLINE_RUNTIME_DIR:-/workspace/.dirtline-runtime}"
mkdir -p "$runtime_dir/data" "$runtime_dir/config" "$runtime_dir/cache"
engine="${DIRTLINE_GODOT:-}"
if [[ -z "$engine" && -f "$runtime_dir/godot-executable" ]]; then
  IFS= read -r engine < "$runtime_dir/godot-executable"
fi
engine="${engine:-godot}"
exec env XDG_DATA_HOME="$runtime_dir/data" XDG_CONFIG_HOME="$runtime_dir/config" XDG_CACHE_HOME="$runtime_dir/cache" \
  "$engine" --path "$project_dir" "$@"
