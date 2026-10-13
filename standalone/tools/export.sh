#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
runtime_dir="${DIRTLINE_RUNTIME_DIR:-/workspace/.dirtline-runtime}"
target="${1:-windows}"
if test -f "$runtime_dir/godot-executable" && test -z "${DIRTLINE_GODOT:-}"; then
  DIRTLINE_GODOT="$(cat "$runtime_dir/godot-executable")"
  export DIRTLINE_GODOT
fi
case "$target" in
  windows) preset="Windows PC"; output="$project_dir/build/windows/DirtlineMX.exe" ;;
  linux) preset="Linux Smoke"; output="$project_dir/build/linux/DirtlineMX.x86_64" ;;
  *) printf 'Usage: bash standalone/tools/export.sh [windows|linux]\n' >&2; exit 2 ;;
esac
mkdir -p "$(dirname -- "$output")"
run_checked() {
  local log_file="$1"
  shift
  bash "$project_dir/tools/godot.sh" "$@" 2>&1 | tee "$log_file"
  # Some editor script errors are printed even when Godot exits successfully.
  python3 - "$log_file" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
text = re.sub(r'\x1b\[[0-9;]*m', '', text)
if re.search(r'^\s*(SCRIPT ERROR:|ERROR:)', text, re.MULTILINE):
    print('Godot reported an error; export stopped. See ' + sys.argv[1], file=sys.stderr)
    sys.exit(1)
PY
}
# Import first so direct GDScript preloads and JSON resources enter the export cache.
run_checked "$(dirname -- "$output")/import.log" --headless --editor --import
run_checked "$(dirname -- "$output")/export.log" --headless --export-release "$preset" "$output"
test -s "$output"
test -s "${output%.*}.pck"
cp "$project_dir/THIRD_PARTY_NOTICES.txt" "$(dirname -- "$output")/THIRD_PARTY_NOTICES.txt"
printf 'Exported %s\n' "$output"
