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
run_check --headless --script res://tests/tire_response_tests.gd
run_check --headless --script res://tests/scrub_control_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/gyro_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/rider_dynamics_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/native_scenarios.gd
run_check --headless --fixed-fps 240 --script res://tests/contact_load_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/tire_patch_phase_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/suspension_response_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/track_layout_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/air_control_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/landing_assistance_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/scrub_takeoff_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/landing_control_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/landing_control_tests.gd -- --chop
run_check --headless --fixed-fps 240 --script res://tests/landing_control_tests.gd -- --standing
run_check --headless --fixed-fps 240 --script res://tests/landing_control_tests.gd -- --standing --chop
run_check --headless --fixed-fps 240 --script res://tests/handling_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/handling_overhaul_tests.gd
run_check --headless --script res://tests/rider_sensor_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/input_camera_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/handling_setup_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/rider_animation_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/automated_feet_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/playability_tests.gd
run_check --headless --fixed-fps 30 --script res://tests/render_cadence_tests.gd -- --render-hz=30
run_check --headless --fixed-fps 240 --script res://tests/render_cadence_tests.gd -- --render-hz=240
run_check --headless --fixed-fps 240 --script res://tests/controllability_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/rideability_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/stability_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/lap_ride_tests.gd
run_check --headless --fixed-fps 240 --script res://tests/recovery_tests.gd
run_check --headless --fixed-fps 240 --quit-after 480
