extends SceneTree
## Exercise the real repeated-packet path, including packets delivered before
## deferred collision changes commit. Corner/stop cases launch through the real
## manual clutch and drivetrain; no rolling state or riding pose is assigned.
const Bike = preload("res://scripts/bike_controller.gd")
const RiderInput = preload("res://scripts/rider_input.gd")
var hz: int = 240
var world: Node3D
var bike: Node3D
var settings: Dictionary
var checks: int = 0
var failures: Array[String] = []
var results: Array[Dictionary] = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="):
			hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("_run")

func _tick() -> void:
	await physics_frame

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("GROUND LIFECYCLE FAIL: " + label)

func _fixture(bank: float = 0.0) -> Transform3D:
	if is_instance_valid(world):
		world.queue_free()
		await _tick()
	world = Node3D.new()
	root.add_child(world)
	var basis := Basis(Vector3.BACK, bank)
	var ground := StaticBody3D.new()
	ground.transform = Transform3D(basis, basis * Vector3(0.0, -0.15, 0.0))
	ground.set_meta("physics_surface", "dirt")
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	ground.physics_material_override = material
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000.0, 0.3, 1000.0)
	collision.shape = shape
	ground.add_child(collision)
	world.add_child(ground)
	bike = Bike.new()
	bike.configure(settings.duplicate(true))
	world.add_child(bike)
	var spawn := Transform3D(basis, basis * Vector3(0.0, 0.90, 0.0))
	bike.reset_bike(spawn)
	return spawn

func _mount_case(bank: float) -> void:
	var spawn: Transform3D = await _fixture(bank)
	var packet := {"clutch": 1.0, "footDown": true, "standing": false}
	for mount: int in range(2):
		if mount == 1:
			bike.reset_bike(spawn, true)
		var before: Array[Vector3] = [bike._feet[0].position, bike._feet[1].position]
		# This is the trigger missed by the old native parking bench: reset
		# queues enabled shapes, then input arrives during the same engine step.
		for _packet: int in range(4):
			bike.set_controls(packet)
		_check(bike._feet[0].position.distance_to(before[0]) < 0.000001 and
			bike._feet[1].position.distance_to(before[1]) < 0.000001,
			"bank %.0f mount %d repeated pre-solver packets preserve prepared boot geometry" % [rad_to_deg(bank), mount])
		var peak_relative_bank := 0.0
		for _i: int in range(hz * 2):
			bike.set_controls(packet)
			await _tick()
			var relative_bank := atan2(-bike.chassis.global_basis.x.dot(spawn.basis.y),
				bike.chassis.global_basis.y.dot(spawn.basis.y))
			peak_relative_bank = maxf(peak_relative_bank, absf(relative_bank))
		var state: Dictionary = bike.get_telemetry()
		_check(not bike.crashed and peak_relative_bank < deg_to_rad(5.0),
			"bank %.0f mount %d remains a supported native parked motorcycle" % [rad_to_deg(bank), mount])
		_check(not bike._feet[0].disabled and not bike._feet[1].disabled and
			bike.chassis.get_contact_count() > 0,
			"bank %.0f mount %d commits real boot collision support" % [rad_to_deg(bank), mount])
		results.append({"kind": "mount", "bank": bank, "remount": mount,
			"peakRelativeBank": peak_relative_bank, "speed": state.speedMps,
			"frontLoad": state.frontLoad, "rearLoad": state.rearLoad,
			"nativeBootContacts": bike.chassis.get_contact_count(), "crashed": bike.crashed})

func _held_turn_stop(direction: float) -> void:
	await _fixture()
	var input: RefCounted = RiderInput.new()
	for _i: int in range(hz * 2):
		input.update_auto_feet(1.0 / hz, bike.get_telemetry())
		bike.set_controls(input.packet())
		await _tick()
	_check(bike.shift_gear(1), "Held-turn stop selects first with its real clutch pulled")
	var initial_heading: Vector3 = -bike.chassis.global_basis.z
	var brake_speed := 0.0
	var brake_bank := 0.0
	var turn_heading := 0.0
	var max_bank := 0.0
	var max_torque := 0.0
	var stopped_samples := 0
	var completed := 0
	for i: int in range(hz * 13):
		var time := float(i) / hz
		input.throttle = minf(time * 0.35, 0.35) if time < 5.0 else 0.0
		input.clutch = maxf(1.0 - time, 0.0) if time < 5.0 else 1.0
		input.steer = direction * 0.35 if time >= 3.0 else 0.0
		input.front_brake = 0.15 if time >= 5.0 else 0.0
		input.rear_brake = 0.075 if time >= 5.0 else 0.0
		input.update_auto_feet(1.0 / hz, bike.get_telemetry())
		bike.set_controls(input.packet())
		await _tick()
		completed += 1
		var state: Dictionary = bike.get_telemetry()
		max_bank = maxf(max_bank, absf(float(state.roll)))
		max_torque = maxf(max_torque, absf(float(state.riderSteeringTorque)))
		if i == hz * 5:
			brake_speed = float(state.speedMps)
			brake_bank = float(state.roll)
			var heading: Vector3 = -bike.chassis.global_basis.z
			heading.y = 0.0
			turn_heading = initial_heading.signed_angle_to(heading.normalized(), Vector3.UP)
		if time > 10.0 and float(state.groundSpeedMps) < 0.10:
			stopped_samples += 1
		if bike.crashed:
			break
	var final: Dictionary = bike.get_telemetry()
	var label := "left" if direction < 0.0 else "right"
	_check(brake_speed > 2.0 and brake_bank * direction > deg_to_rad(5.0) and
		absf(turn_heading) > deg_to_rad(5.0), label + " fixture actually launches and turns before braking")
	_check(completed == hz * 13 and not bike.crashed,
		label + " gentle braking through a held turn reaches a supported stop without recovery")
	_check(stopped_samples > hz and bool(final.footDown) and bike.chassis.get_contact_count() > 0,
		label + " held turn reaches a real stationary stop on physical boot support")
	_check(max_bank < deg_to_rad(25.0) and absf(float(final.bankRate)) < 0.05,
		label + " stop settles without an accelerating low-side")
	_check(max_torque <= float(settings.VirtualRider.MaxTorque) + 0.001,
		label + " stopping uses the existing finite handlebar torque budget")
	var result := {"kind": "heldTurnStop", "direction": direction, "hz": hz,
		"brakeSpeed": brake_speed, "brakeBank": brake_bank, "turnHeading": turn_heading,
		"maxBank": max_bank, "finalBank": final.roll, "finalSpeed": final.speedMps,
		"stoppedSamples": stopped_samples, "completed": completed, "crashed": bike.crashed,
		"crashReason": bike.crash_reason, "maxTorque": max_torque}
	results.append(result)
	print("HELD TURN STOP ", JSON.stringify(result))

func _run() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	for bank: float in [0.0, deg_to_rad(-12.0), deg_to_rad(12.0)]:
		await _mount_case(bank)
	for direction: float in [-1.0, 1.0]:
		await _held_turn_stop(direction)
	DirAccess.make_dir_recursive_absolute("res://build/v8-ground-lifecycle")
	var report := FileAccess.open("res://build/v8-ground-lifecycle/lifecycle-%d-%d.json" %
		[hz, OS.get_process_id()], FileAccess.WRITE)
	report.store_string(JSON.stringify({"hz": hz, "checks": checks, "failures": failures,
		"controllerHash": String(bike.get_script().source_code).sha256_text(), "results": results}, "\t"))
	print("Native ground lifecycle: %d passed, %d failed (%dHz)" % [checks - failures.size(), failures.size(), hz])
	quit(0 if failures.is_empty() else 1)
