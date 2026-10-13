#!/usr/bin/env bash
set -euo pipefail
tools_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
log_file="$(mktemp)"
trap 'rm -f -- "$log_file"' EXIT
run_check() {
  local status=0
  bash "$tools_dir/godot.sh" "$@" > "$log_file" 2>&1 || status=$?
  cat "$log_file"
  if [[ "$status" != 0 ]]; then return "$status"; fi
  if rg -q 'SCRIPT ERROR:|^ERROR:' "$log_file"; then return 1; fi
}
run_check --headless --editor --import --quit
run_check --headless --script res://tests/math_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/gyro_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/native_scenarios.gd
run_check --headless --fixed-fps 240 --quit-after 480
