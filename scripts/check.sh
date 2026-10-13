#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
tools_dir="${ROBLOX_TOOLS_DIR:-/workspace/.roblox-tools}"
export PATH="$tools_dir/bin:$PATH"

for suite in tests/*.spec.luau; do
  luau "$suite"
done
mapfile -d '' pure_sources < <(rg --files --null src/shared tests -g '*.luau')
luau-analyze "${pure_sources[@]}"
while IFS= read -r -d '' source; do
  luau-compile "$source" > /dev/null
done < <(rg --files --null src tests -g '*.luau')
echo "All Luau sources compile."
mkdir -p build
rojo build default.project.json --output build/DirtlineMX.rbxlx
python3 scripts/verify-place.py build/DirtlineMX.rbxlx
