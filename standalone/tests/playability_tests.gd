extends SceneTree
## Native playability regression checks. Keyboard values come from the game's
## real RiderInput class; the checks never pin, freeze, or align the bike.

const BikeScript = preload("res://scripts/bike_controller.gd")
const InputScript = preload("res://scripts/rider_input.gd")
const HZ := 240.0
var world: Node3D
var bike: Node3D
var rider: RefCounted
var cfg: Dictionary
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, details: String = "") -> void:
	checks += 1
	if not condition:
		failures.append(message + (": " + details if not details.is_empty() else ""))
		push_error("PLAYABILITY FAIL: " + failures[-1])

func _tick() -> void:
	await physics_frame
	await process_frame

func _release_actions() -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("mx_"):
			Input.action_release(action)

func _new_bike() -> void:
	_release_actions()
	if is_instance_valid(bike):
		bike.queue_free()
		await _tick()
	rider = InputScript.new()
	bike = BikeScript.new()
	bike.configure(cfg.duplicate(true))
	world.add_child(bike)
	bike.reset_bike(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.82, 0.0)))
	for _i: int in range(240):
		bike.set_controls(rider.tick(1.0 / HZ, true))
		await _tick()

func _keyboard_run() -> Dictionary:
	await _new_bike()
	_check(bike.shift_gear(1), "Actual launch can select first with the clutch pulled")
	var origin: Vector3 = bike.chassis.global_position
	Input.action_press("mx_throttle")
	Input.action_press("mx_clutch_release")
	var max_roll := 0.0
	var max_speed := 0.0
	var grounded_ticks := 0
	var first_100_reached := false
	var first_100_max_lateral := 0.0
	var first_100_heading := 0.0
	var origin_heading := atan2(-bike.chassis.global_basis.z.x, -bike.chassis.global_basis.z.z)
	var snapshots: Array[Dictionary] = []
	for i: int in range(3360):
		if i == 240:
			rider.foot_down = false
		# A human can short-shift after setting the lever; use a pulled clutch
		# during each deliberate shift rather than replacing drive state.
		if i in [600, 1000, 1400, 1900]:
			Input.action_press("mx_clutch_quick")
		if i in [620, 1020, 1420, 1920]:
			bike.shift_gear(1)
			Input.action_release("mx_clutch_quick")
		bike.set_controls(rider.tick(1.0 / HZ, true))
		await _tick()
		var t: Dictionary = bike.get_telemetry()
		max_roll = maxf(max_roll, absf(float(t.roll)))
		max_speed = maxf(max_speed, float(t.speedMps))
		grounded_ticks += int(bool(t.frontContact) or bool(t.rearContact))
		if not first_100_reached:
			first_100_max_lateral = maxf(first_100_max_lateral, absf(bike.chassis.global_position.x - origin.x))
			if origin.z - bike.chassis.global_position.z >= 100.0:
				first_100_reached = true
				var heading: float = atan2(-bike.chassis.global_basis.z.x, -bike.chassis.global_basis.z.z)
				first_100_heading = absf(wrapf(heading - origin_heading, -PI, PI))
		if i % 240 == 239:
			snapshots.append({"s": float(i + 1) / HZ, "speed": t.speedMps, "roll": t.roll, "pitch": t.pitch, "gear": t.gear, "crashed": t.crashed, "reason": t.crashReason, "position": str(bike.chassis.global_position)})
	var result := {"distance": origin.distance_to(bike.chassis.global_position), "forward": origin.z - bike.chassis.global_position.z, "maxRoll": max_roll, "maxSpeed": max_speed, "groundedTicks": grounded_ticks,
		"first100Reached": first_100_reached, "first100MaxLateral": first_100_max_lateral, "first100Heading": first_100_heading, "snapshots": snapshots}
	print("PLAYABILITY keyboard: ", JSON.stringify(result))
	_check(not bool(bike.get_telemetry().crashed), "Progressive keyboard launch and four manual shifts remain rideable for 14 seconds")
	_check(int(bike.get_telemetry().gear) == 5, "Real clutch-and-shift inputs reach fifth gear")
	_check(float(result.forward) > 120.0 and max_speed > 15.0, "Keyboard rider makes substantial native forward progress", "%.1f m / %.1f m/s" % [result.forward, max_speed])
	_check(max_roll < 0.4, "Default virtual rider keeps an uncommanded long acceleration within a reasonable bank angle", "%.1f degrees" % rad_to_deg(max_roll))
	_check(grounded_ticks > 2400, "Playable launch is supported by real tire contacts rather than hovering", "%s frames" % grounded_ticks)
	_check(not bool(bike.get_telemetry().footDown), "Long keyboard launch continues with the physical feet raised")
	_check(first_100_reached and first_100_max_lateral < 3.0, "Neutral steering stays within a rideable lane over the first 100 meters", "maximum lateral drift %.2f m" % first_100_max_lateral)
	_check(first_100_reached and first_100_heading < deg_to_rad(12.0), "Neutral steering avoids a large uncommanded heading change over the first 100 meters", "heading change %.1f degrees" % rad_to_deg(first_100_heading))
	_release_actions()
	return result

func _rider_corner_run(direction: float, command_kind: String = "lean", amount: float = 0.4, hold_seconds: float = 5.0, verify: bool = true) -> Dictionary:
	await _new_bike()
	bike.shift_gear(1)
	var origin: Vector3 = bike.chassis.global_position
	var corner_started := false
	var corner_start_heading := 0.0
	var corner_start_position := Vector3.ZERO
	var corner_ticks := 0
	var corner_max_roll := 0.0
	var final_roll_sum := 0.0
	var final_roll_ticks := 0
	var wrong_bank_ticks := 0
	var corner_path_distance := 0.0
	var previous_position := Vector3.ZERO
	var previous_heading := 0.0
	var accumulated_heading := 0.0
	var max_speed := 0.0
	var feet_raised := false
	var snapshots: Array[Dictionary] = []
	var target_corner_ticks := roundi(hold_seconds * HZ)
	for i: int in range(roundi((12.0 + hold_seconds) * HZ)):
		var t: Dictionary = bike.get_telemetry()
		var speed: float = float(t.speedMps)
		var time: float = float(i) / HZ
		if speed > 1.6:
			feet_raised = true
		if not corner_started and speed > 5.0 and time > 3.0:
			corner_started = true
			corner_start_heading = atan2(-bike.chassis.global_basis.z.x, -bike.chassis.global_basis.z.z)
			corner_start_position = bike.chassis.global_position
			previous_position = corner_start_position
			previous_heading = corner_start_heading
		var request: float = direction * amount * minf(1.0, float(corner_ticks) / 180.0) if corner_started else 0.0
		# This analog rider modulates throttle to remain near a modest corner
		# entry pace, using only a genuine drivetrain input. No balance targets
		# or velocity changes are made by the fixture.
		var throttle_value: float = clampf(0.66 + (8.0 - speed) * 0.15, 0.2, 0.85) if corner_started else 0.8
		bike.set_controls({"throttle": throttle_value,
			"clutch": clampf(1.0 - time / 1.2, 0.0, 1.0), "footDown": not feet_raised,
			"steer": request if command_kind == "steer" else 0.0,
			"lean": request if command_kind == "lean" else 0.0, "bodySide": 0.0})
		await _tick()
		t = bike.get_telemetry()
		max_speed = maxf(max_speed, float(t.speedMps))
		if corner_started:
			corner_ticks += 1
			corner_max_roll = maxf(corner_max_roll, absf(float(t.roll)))
			var current_position: Vector3 = bike.chassis.global_position
			var heading: float = atan2(-bike.chassis.global_basis.z.x, -bike.chassis.global_basis.z.z)
			corner_path_distance += current_position.distance_to(previous_position)
			accumulated_heading += wrapf(heading - previous_heading, -PI, PI)
			previous_position = current_position
			previous_heading = heading
			if corner_ticks > 360 and float(t.roll) * direction < -0.06:
				wrong_bank_ticks += 1
			if corner_ticks > target_corner_ticks - 240:
				final_roll_sum += float(t.roll)
				final_roll_ticks += 1
		if i % 240 == 239:
			snapshots.append({"s": time, "speed": t.speedMps, "roll": t.roll, "target": t.get("riderTargetLean", 0.0), "steerTorque": t.get("riderSteeringTorque", 0.0), "crashed": t.crashed, "position": str(bike.chassis.global_position)})
		if bool(t.crashed) or corner_ticks >= target_corner_ticks:
			break
	var end_heading := atan2(-bike.chassis.global_basis.z.x, -bike.chassis.global_basis.z.z)
	var result := {"direction": direction, "command": command_kind, "amount": amount, "duration": hold_seconds, "cornerStarted": corner_started, "cornerTicks": corner_ticks,
		"headingChange": wrapf(end_heading - corner_start_heading, -PI, PI), "accumulatedHeading": accumulated_heading,
		"cornerDisplacement": corner_start_position.distance_to(bike.chassis.global_position),
		"cornerPathDistance": corner_path_distance, "wrongBankTicks": wrong_bank_ticks,
		"distance": origin.distance_to(bike.chassis.global_position), "maxSpeed": max_speed,
		"maxRoll": corner_max_roll, "finalMeanRoll": final_roll_sum / maxf(1.0, final_roll_ticks),
		"crashed": bike.get_telemetry().crashed, "snapshots": snapshots}
	print("PLAYABILITY corner: ", JSON.stringify(result))
	if verify:
		var label := ("Left" if direction < 0.0 else "Right") + " " + command_kind
		_check(corner_started and corner_ticks >= target_corner_ticks, "%s request sustains %.0f seconds of actual cornering" % [label, hold_seconds], str(corner_ticks))
		_check(not bool(result.crashed), "%s corner remains rideable with both feet raised" % label)
		_check(float(result.finalMeanRoll) * direction > 0.06, "%s input produces a sustained native bank in the requested direction" % label, "%.1f degrees" % rad_to_deg(float(result.finalMeanRoll)))
		_check(float(result.accumulatedHeading) * direction < -0.12, "%s native bank produces a real turn in the requested direction" % label, "%.1f degrees" % rad_to_deg(float(result.accumulatedHeading)))
		_check(float(result.cornerPathDistance) > 20.0 and max_speed > 5.0, "%s corner covers real ground at riding speed" % label)
		_check(wrong_bank_ticks < 90, "%s captured lean does not develop sustained bank into the wrong side" % label, "%.2f seconds of opposite bank" % (float(wrong_bank_ticks) / HZ))
	return result

func _key_event(key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func _press_key(key: int) -> void:
	_key_event(key, true)
	await _tick()
	_key_event(key, false)
	await _tick()

func _find_button(node: Node, text_prefix: String) -> Button:
	if node is Button and node.text.begins_with(text_prefix):
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text_prefix)
		if found != null:
			return found
	return null

func _test_main_scene_ui() -> void:
	_release_actions()
	world.queue_free()
	await _tick()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node3D = scene.instantiate()
	root.add_child(game)
	await process_frame
	_check(game.modal_kind == "welcome" and not bool(game.session_started), "Shipped main scene starts at its welcome screen before riding")
	var ride_button: Button = _find_button(game, "LET")
	_check(ride_button != null, "Main welcome screen exposes the actual ride button")
	if ride_button == null:
		return
	ride_button.pressed.emit()
	for _i: int in range(240):
		await _tick()
	_check(bool(game.session_started) and not paused and game.modal_kind.is_empty(), "Ride button opens the real playable session")
	await _press_key(KEY_E)
	_check(int(game.bike.get_telemetry().gear) == 1, "Actual E key reaches the main game's manual gearbox")
	_key_event(KEY_W, true)
	_key_event(KEY_B, true)
	var origin: Vector3 = game.bike.chassis.global_position
	for i: int in range(1200):
		if i == 240:
			await _press_key(KEY_F)
		if i == 600:
			_key_event(KEY_SHIFT, true)
		if i == 620:
			await _press_key(KEY_E)
			_key_event(KEY_SHIFT, false)
		await _tick()
	var state: Dictionary = game.bike.get_telemetry()
	var distance: float = origin.distance_to(game.bike.chassis.global_position)
	print("PLAYABILITY main UI: distance=%.2f m, speed=%.2f m/s, gear=%d, feet=%s, crashed=%s" % [distance, state.speedMps, state.gear, state.footDown, state.crashed])
	_check(not bool(state.crashed) and distance > 15.0 and float(state.speedMps) > 5.0, "Shipped track and actual keyboard event flow support a five-second ride", "%.1f m / %.1f m/s / crash=%s" % [distance, state.speedMps, state.crashed])
	_check(not bool(state.footDown), "Main F key actually raises the rider's physical feet")
	_key_event(KEY_W, false)
	_key_event(KEY_B, false)
	await _press_key(KEY_H)
	_check(game.modal_kind == "help" and paused, "Actual help key opens the main controls screen")
	var feet_before: bool = game.rider_input.foot_down
	await _press_key(KEY_F)
	_check(game.rider_input.foot_down == feet_before, "A ride command while reading help does not change the rider's physical posture")
	await _press_key(KEY_H)
	_check(game.modal_kind.is_empty() and not paused, "Help key resumes the playable session")
	game.queue_free()
	await process_frame

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.name = "PlayabilityHardpack"
	floor_body.position.y = -0.15
	floor_body.set_meta("physics_surface", "hardpack")
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	floor_body.physics_material_override = material
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000.0, 0.3, 1000.0)
	collision.shape = shape
	floor_body.add_child(collision)
	world.add_child(floor_body)
	await _keyboard_run()
	await _rider_corner_run(-1.0)
	await _rider_corner_run(1.0)
	await _rider_corner_run(-1.0, "steer", 1.0, 10.0)
	await _rider_corner_run(1.0, "steer", 1.0, 10.0)
	await _test_main_scene_ui()
	print("Playability native checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
