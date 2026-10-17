extends RefCounted
## Optional completed-physics-frame capture. Recording never changes controls,
## poses or simulation state. The game samples before polling the next input:
## body/contact observations describe the completed solve, force columns are
## the tire commands applied during it, and input columns are that step's
## applied packet. CSV units are in the header; torques are world XYZ.
const SCALARS: Array = [
	["speed_mps", "speedMps", 0.0], ["ground_speed_mps", "groundSpeedMps", 0.0],
	["bank_rad", "roll", 0.0], ["pitch_rad", "pitch", 0.0], ["steer_rad", "steerAngle", 0.0],
	["pitch_rate_radps", "pitchRate", 0.0], ["yaw_rate_radps", "yawRate", 0.0], ["roll_rate_radps", "rollRate", 0.0],
	["front_contact", "frontContact", false], ["rear_contact", "rearContact", false],
	["front_load_n", "frontLoad", 0.0], ["rear_load_n", "rearLoad", 0.0],
	["front_slip_ratio", "frontSlip", 0.0], ["rear_slip_ratio", "rearSlip", 0.0],
	["front_slip_angle_rad", "frontSlipAngle", 0.0], ["rear_slip_angle_rad", "rearSlipAngle", 0.0],
	["front_compression_m", "frontCompression", 0.0], ["rear_compression_m", "rearCompression", 0.0],
	["front_longitudinal_force_n", "frontLongitudinalForce", 0.0], ["front_lateral_force_n", "frontLateralForce", 0.0],
	["rear_longitudinal_force_n", "rearLongitudinalForce", 0.0], ["rear_lateral_force_n", "rearLateralForce", 0.0],
	["front_longitudinal_capacity_n", "frontCapacityX", 0.0], ["front_lateral_capacity_n", "frontCapacityY", 0.0],
	["rear_longitudinal_capacity_n", "rearCapacityX", 0.0], ["rear_lateral_capacity_n", "rearCapacityY", 0.0],
	["front_utilization", "frontUtilization", 0.0], ["rear_utilization", "rearUtilization", 0.0],
	["front_slip_power_w", "frontSlipPower", 0.0], ["rear_slip_power_w", "rearSlipPower", 0.0],
	["front_wheel_radps", "frontOmega", 0.0], ["rear_wheel_radps", "rearOmega", 0.0],
	["gear", "gear", 0], ["rpm", "rpm", 0.0], ["stalled", "stalled", false],
	["front_surface", "frontSurface", ""], ["rear_surface", "rearSurface", ""],
	["front_load_method", "frontLoadMethod", ""], ["rear_load_method", "rearLoadMethod", ""],
	["riding_mode", "ridingMode", ""], ["bar_torque_nm", "riderSteeringTorque", 0.0],
	["target_bank_rad", "riderTargetLean", 0.0], ["target_steer_rad", "steeringTarget", 0.0],
	["heading_correction_rad", "headingCorrection", 0.0],
	["front_support_confidence", "frontSupport", 0.0], ["rear_support_confidence", "rearSupport", 0.0],
	["scrub_crouch_m", "scrubCrouch", 0.0], ["scrub_rebound_scale", "scrubReboundScale", 1.0],
	["air_assist_power_w", "airAssistPower", 0.0], ["crashed", "crashed", false],
	["crash_reason", "crashReason", ""], ["tire_loss_context", "tireLossContext", ""]
]
const INPUTS: Array = [
	["input_throttle", "throttle", 0.0], ["input_front_brake", "frontBrake", 0.0],
	["input_rear_brake", "rearBrake", 0.0], ["input_clutch", "clutch", 1.0],
	["input_steer", "steer", 0.0], ["input_lean", "lean", 0.0],
	["input_body_forward", "bodyForward", 0.0], ["input_body_side", "bodySide", 0.0],
	["input_scrub", "scrub", 0.0], ["input_standing", "standing", false], ["input_foot_down", "footDown", true]
]
const VECTORS: Array = [
	["ground_assist_nm", "groundAssistTorque"], ["air_assist_nm", "airAssistTorque"],
	["landing_assist_nm", "landingAssistTorque"], ["rider_posture_nm", "riderPostureTorque"]
]
const CRASH_SCALARS: Array = [
	["support_bank_rad", "supportBank", 0.0], ["support_pitch_rad", "supportPitch", 0.0],
	["loaded_support", "loadedSupport", false], ["last_landing_impact_mps", "impactSpeed", ""],
	["last_landing_tilt_rad", "landingTilt", ""], ["last_landing_side_mps", "sideSpeed", ""]
]
var _file: FileAccess
var _elapsed := 0.0
var _since_flush := 0.0
var path := ""
var rows := 0

static func header() -> PackedStringArray:
	var fields := PackedStringArray(["physics_frame", "time_s", "physics_dt_s"])
	for collection: Array in [SCALARS, INPUTS, CRASH_SCALARS]:
		for field: Array in collection:
			fields.append(str(field[0]))
	for field: Array in VECTORS:
		for axis: String in ["x", "y", "z"]:
			fields.append(str(field[0]) + "_" + axis)
	return fields

func active() -> bool:
	return _file != null

func start(destination: String = "") -> Error:
	if active():
		return ERR_ALREADY_IN_USE
	if destination.is_empty():
		var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
		destination = "user://telemetry/physics-%s-%d.csv" % [stamp, Time.get_ticks_usec()]
	var absolute := ProjectSettings.globalize_path(destination)
	var status := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if status != OK:
		return status
	_file = FileAccess.open(absolute, FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	path = absolute
	_elapsed = 0.0
	_since_flush = 0.0
	rows = 0
	_file.store_csv_line(header())
	_file.flush()
	return _file.get_error()

static func _cell(value: Variant) -> String:
	if value is bool:
		return "1" if value else "0"
	if value is float:
		return String.num(value, 9)
	return str(value)

func capture(frame: int, dt: float, telemetry: Dictionary, applied_inputs: Dictionary) -> bool:
	if not active():
		return false
	_elapsed += dt
	_since_flush += dt
	var values := PackedStringArray([str(frame), _cell(_elapsed), _cell(dt)])
	for field: Array in SCALARS:
		values.append(_cell(telemetry.get(str(field[1]), field[2])))
	for field: Array in INPUTS:
		values.append(_cell(applied_inputs.get(str(field[1]), field[2])))
	var crash_observation: Dictionary = telemetry.get("crashObservation", {})
	for field: Array in CRASH_SCALARS:
		values.append(_cell(crash_observation.get(str(field[1]), field[2])))
	for field: Array in VECTORS:
		var torque: Vector3 = telemetry.get(str(field[1]), Vector3.ZERO)
		for component: float in [torque.x, torque.y, torque.z]:
			values.append(_cell(component))
	_file.store_csv_line(values)
	rows += 1
	# No per-frame flush stall; retain at most one second of buffered frames.
	if _since_flush >= 1.0 or bool(telemetry.get("crashed", false)):
		_file.flush()
		_since_flush = 0.0
	return _file.get_error() == OK

func stop() -> String:
	if active():
		_file.flush()
		_file.close()
		_file = null
	return path
