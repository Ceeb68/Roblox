class_name DLHandlingSetup
extends RefCounted
## One allowlist for parked handling adjustments, persistence and menu ranges.
## Values retain their physical units. Applying an invalid setup changes nothing.

const FORMAT_VERSION := 1
# path, menu group, label, minimum, maximum, step, fallback for older configs
const FIELDS: Array = [
	["Tire.Front.GripScale", "TIRES", "Front tire grip · scale", 0.5, 1.3, 0.05, 1.0],
	["Tire.Rear.GripScale", "TIRES", "Rear tire grip · scale", 0.5, 1.3, 0.05, 1.0],
	["Tire.LateralGrip", "TIRES", "Lateral grip · scale", 0.5, 1.3, 0.05, 1.0],
	["Tire.AccelerationGrip", "TIRES", "Acceleration traction · scale", 0.5, 1.3, 0.05, 1.0],
	["Tire.BrakingGrip", "TIRES", "Braking traction · scale", 0.5, 1.3, 0.05, 1.0],
	["VirtualRider.SteeringSensitivity", "STEERING + LEAN", "Steering sensitivity · scale", 0.5, 1.5, 0.05, 1.0],
	["VirtualRider.IntentResponse", "STEERING + LEAN", "Steering input response · s", 0.025, 0.25, 0.005, 0.07],
	["VirtualRider.LeanRate", "STEERING + LEAN", "Lean initiation limit · rad/s", 0.6, 3.0, 0.05, 1.8],
	["VirtualRider.LeanRecoveryRate", "STEERING + LEAN", "Lean recovery limit · rad/s", 0.6, 3.0, 0.05, 1.65],
	["VirtualRider.LeanPredictionTime", "STEERING + LEAN", "Lean prediction · s", 0.05, 0.4, 0.01, 0.18],
	["Assistance.Strength", "GAMEPLAY ASSISTANCE", "Gameplay assistance (0 = native only)", 0.0, 1.0, 0.05, 1.0],
	["Assistance.LowSpeedFull", "GAMEPLAY ASSISTANCE", "Full low-speed balance below · m/s", 1.5, 5.0, 0.25, 4.0],
	["Assistance.LowSpeedEnd", "GAMEPLAY ASSISTANCE", "Low-speed balance ends at · m/s", 5.5, 12.0, 0.25, 8.0],
	["Assistance.LowSpeedBalanceStiffness", "GAMEPLAY ASSISTANCE", "Balance stiffness · N·m/rad", 100.0, 600.0, 20.0, 380.0],
	["Assistance.LowSpeedBalanceDamping", "GAMEPLAY ASSISTANCE", "Balance damping · N·m·s/rad", 20.0, 150.0, 5.0, 85.0],
	["Assistance.LowSpeedMaxTorque", "GAMEPLAY ASSISTANCE", "Low-speed torque limit · N·m", 0.0, 70.0, 5.0, 45.0],
	["Assistance.LandingStrength", "GAMEPLAY ASSISTANCE", "Landing assistance · scale", 0.0, 1.0, 0.05, 1.0],
	["Assistance.LandingTime", "GAMEPLAY ASSISTANCE", "Landing damping window · s", 0.15, 1.25, 0.05, 0.3],
	["Assistance.LandingPitchStiffness", "GAMEPLAY ASSISTANCE", "Optional landing pitch return · N·m/rad", 0.0, 200.0, 10.0, 0.0],
	["AirControl.Strength", "AIRBORNE CONTROL", "Airborne assistance · scale", 0.0, 1.0, 0.05, 1.0],
	["AirControl.PitchRate", "AIRBORNE CONTROL", "Pitch input rate · rad/s", 0.4, 1.8, 0.05, 1.1],
	["AirControl.RollRate", "AIRBORNE CONTROL", "Roll input rate · rad/s", 0.4, 2.0, 0.05, 1.4],
	["AirControl.YawRate", "AIRBORNE CONTROL", "Yaw input rate · rad/s", 0.4, 2.0, 0.05, 1.3],
	["AirControl.NeutralDampingStrength", "AIRBORNE CONTROL", "Neutral air damping (0 = momentum)", 0.0, 1.0, 0.05, 0.0],
	["AirControl.NeutralDampingTime", "AIRBORNE CONTROL", "Optional neutral damping time · s", 0.25, 2.0, 0.05, 0.55],
	["AirControl.WhipResponse", "AIRBORNE CONTROL", "Whip response · scale", 0.4, 1.8, 0.05, 1.0],
	["AirControl.WhipRecovery", "AIRBORNE CONTROL", "Whip counter-input · scale", 0.4, 1.8, 0.05, 1.15],
	["ScrubControl.MaxCrouch", "SCRUBS", "Maximum physical crouch · m", 0.0, 0.28, 0.01, 0.28],
	["ScrubControl.MaxReboundScale", "SCRUBS", "Loaded takeoff rebound damping · scale", 1.0, 3.5, 0.1, 3.5],
	["RiderAnimation.TransitionTime", "RIDER ANIMATION", "Seated / standing transition · s", 0.06, 0.35, 0.01, 0.12],
	["RiderAnimation.CornerTransitionTime", "RIDER ANIMATION", "Inside-leg transition · s", 0.06, 0.35, 0.01, 0.13]
]

static func value_at(config: Dictionary, path: String, fallback: float) -> float:
	var cursor: Variant = config
	for part: String in path.split("."):
		if not cursor is Dictionary or not (cursor as Dictionary).has(part):
			return fallback
		cursor = cursor[part]
	if (typeof(cursor) != TYPE_FLOAT and typeof(cursor) != TYPE_INT) or not is_finite(float(cursor)):
		return fallback
	return float(cursor)

static func _write_path(config: Dictionary, path: String, value: float) -> void:
	var parts := path.split(".")
	var cursor: Dictionary = config
	for index in range(parts.size() - 1):
		if not cursor.get(parts[index]) is Dictionary:
			cursor[parts[index]] = {}
		cursor = cursor[parts[index]]
	cursor[parts[-1]] = value

static func snapshot(config: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field: Array in FIELDS:
		_write_path(result, str(field[0]), value_at(config, str(field[0]), float(field[6])))
	return result

static func _flatten(changes: Dictionary, prefix: String, leaves: Dictionary) -> String:
	for key: Variant in changes:
		if not key is String or str(key).is_empty() or "." in str(key):
			return "Handling setting names must be supported text keys."
		var path := str(key) if prefix.is_empty() else prefix + "." + str(key)
		var value: Variant = changes[key]
		if value is Dictionary:
			# Empty or unknown subtrees must not silently pass validation.
			var known_branch := false
			for field: Array in FIELDS:
				if str(field[0]).begins_with(path + "."):
					known_branch = true
					break
			if not known_branch or (value as Dictionary).is_empty():
				return "Unknown or empty handling section: " + path
			var error := _flatten(value, path, leaves)
			if not error.is_empty():
				return error
		else:
			leaves[path] = value
	return ""

static func apply(config: Dictionary, changes: Variant) -> Dictionary:
	if not changes is Dictionary:
		return {"ok": false, "error": "Handling setup must contain named settings."}
	var leaves: Dictionary = {}
	var error := _flatten(changes, "", leaves)
	if not error.is_empty():
		return {"ok": false, "error": error}
	var known: Dictionary = {}
	for field: Array in FIELDS:
		known[str(field[0])] = field
	for path: String in leaves:
		if not known.has(path):
			return {"ok": false, "error": "Unsupported handling setting: " + path}
		var value: Variant = leaves[path]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return {"ok": false, "error": "Handling values must be finite numbers: " + path}
		var field: Array = known[path]
		if not is_finite(float(value)) or float(value) < float(field[3]) or float(value) > float(field[4]):
			return {"ok": false, "error": "Handling setting outside its supported range: " + path}
	var result := config.duplicate(true)
	for path: String in leaves:
		_write_path(result, path, float(leaves[path]))
	# Defaults resolve absent fields without copying unrelated configuration.
	if value_at(result, "Assistance.LowSpeedEnd", 8.0) <= value_at(result, "Assistance.LowSpeedFull", 4.0):
		return {"ok": false, "error": "Low-speed assistance must fade out above its full-strength speed."}
	return {"ok": true, "config": result, "error": ""}

static func load_file(path: String, base: Dictionary) -> Dictionary:
	var file := ConfigFile.new()
	var status := file.load(path)
	if status == ERR_FILE_NOT_FOUND:
		return {"ok": true, "config": base.duplicate(true), "loaded": false, "error": ""}
	if status != OK or file.get_value("handling", "version", -1) != FORMAT_VERSION:
		return {"ok": false, "error": "Saved handling setup could not be read."}
	var result := apply(base, file.get_value("handling", "values", null))
	result["loaded"] = bool(result.ok)
	return result

static func save_file(path: String, values: Dictionary) -> Error:
	var checked := apply({}, values)
	if not bool(checked.ok):
		return ERR_INVALID_DATA
	var file := ConfigFile.new()
	file.set_value("handling", "version", FORMAT_VERSION)
	file.set_value("handling", "values", snapshot(checked.config))
	return file.save(path)
