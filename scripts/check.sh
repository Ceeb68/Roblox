#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
tools_dir="${ROBLOX_TOOLS_DIR:-/workspace/.roblox-tools}"
export PATH="$tools_dir/bin:$PATH"

luau tests/RaceRules.spec.luau
luau-analyze src/shared/RaceRules.luau tests/RaceRules.spec.luau
while IFS= read -r -d '' source; do
  luau-compile "$source" > /dev/null
done < <(rg --files --null src tests -g '*.luau')
echo "All Luau sources compile."
mkdir -p build
rojo build default.project.json --output build/DirtlineMX.rbxlx
python3 scripts/verify-place.py build/DirtlineMX.rbxlx
