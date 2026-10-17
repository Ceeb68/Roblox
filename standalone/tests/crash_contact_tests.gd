extends SceneTree
## Regression checks for crash coordinates using the actual free native bike.
## Fixtures assign initial conditions once; support and subsequent motion are
## always observed from Jolt. No mocked wheel contact or normal load is used.
const Bike = preload("res://scripts/bike_controller.gd")
const HZ := 240.0
var checks := 0
var failures: Array[String] = []
var world: Node3D
var bike: Node3D
var observations: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _tick() -> void:
	await physics_frame
	await process_frame

func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (": " + detail if not detail.is_empty() else ""))
		push_error("CRASH CONTACT FAIL: " + failures[-1])

func _analytic_checks() -> void:
	var banked := Basis(Vector3.FORWARD, deg_to_rad(45.0))
	var vertical: Dictionary = Bike.landing_observation(Vector3(0, -9, -14), banked, Vector3.UP)
	_check(absf(float(vertical.sideSpeed)) < 0.000001,
		"Banking 45 degrees does not turn vertical impact into sideways slip")
	_check(absf(float(vertical.impactSpeed) - 9.0) < 0.000001,
		"The same vertical impact retains its actual 9 m/s normal severity")
	var lateral: Dictionary = Bike.landing_observation(Vector3(7, -5, -14), banked, Vector3.UP)
	_check(absf(float(lateral.sideSpeed) - 7.0) < 0.000001,
		"Real 7 m/s lateral travel remains a sideways landing at 45 degrees bank")
	var platform := Vector3(4, 0, -3)
	var transported: Dictionary = Bike.landing_observation(platform + Vector3(0, -5, -10), banked, Vector3.UP, platform)
	_check(absf(float(transported.sideSpeed)) < 0.000001 and absf(float(transported.impactSpeed) - 5.0) < 0.000001,
		"Moving support velocity is removed before evaluating landing slip")
	var berm := Basis(Vector3.FORWARD, deg_to_rad(40.0))
	var aligned: Dictionary = Bike.landing_observation(berm * Vector3(0, -4, -12), berm, berm.y)
	_check(absf(float(aligned.sideSpeed)) < 0.000001 and absf(float(aligned.tilt)) < 0.000001,
		"An aligned banked landing uses the actual terrain frame")

func _fixture(terrain_bank: float, bike_bank: float, height: float, velocity: Vector3,
		terrain_pitch: float = 0.0, bike_pitch: float = 0.0) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await _tick()
	world = Node3D.new()
	root.add_child(world)
	var terrain := Basis(Vector3.FORWARD, terrain_bank) * Basis(Vector3.RIGHT, terrain_pitch)
	var floor_body := StaticBody3D.new()
	floor_body.transform = Transform3D(terrain, terrain * Vector3(0, -0.15, 0))
	floor_body.set_meta("physics_surface", "hardpack")
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	floor_body.physics_material_override = material
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40, 0.3, 80)
	collision.shape = shape
	floor_body.add_child(collision)
	world.add_child(floor_body)
	bike = Bike.new()
	world.add_child(bike)
	var orientation := Basis(Vector3.FORWARD, bike_bank) * Basis(Vector3.RIGHT, bike_pitch)
	bike.reset_bike(Transform3D(orientation, terrain * Vector3(0, height, 0)))
	bike.set_controls({"footDown": false})
	# Finish the intentional reset before supplying each body's ONE initial
	# velocity. The runtime may then change it only through native dynamics.
	await _tick()
	await _tick()
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		body.linear_velocity = velocity
	bike.front_wheel.invalidate_load_history()
	bike.rear_wheel.invalidate_load_history()

func _berm_case() -> void:
	await _fixture(deg_to_rad(40.0), deg_to_rad(68.0), 0.77, Vector3.ZERO)
	var witnessed := false
	var measured: Dictionary = {}
	for _i: int in range(120):
		await _tick()
		var telemetry: Dictionary = bike.get_telemetry()
		var observation: Dictionary = telemetry.crashObservation
		if bool(observation.get("loadedSupport", false)) and absf(float(telemetry.roll)) > float(bike.config.Crash.GroundRoll):
			measured = telemetry
			witnessed = true
			break
		if bike.crashed:
			break
	_check(witnessed, "Native 40 degree berm carries the bike beyond 67 degree WORLD bank", str(measured))
	if witnessed:
		var relative := absf(float(measured.crashObservation.supportBank))
		_check(relative < deg_to_rad(35.0), "Its real support-relative lean remains below 35 degrees", str(rad_to_deg(relative)))
		_check(not bool(measured.crashed), "Supported berm lean does not trigger a false world-angle low-side", str(measured.crashReason))
	observations.append({"case": "berm", "witnessed": witnessed, "telemetry": _serializable(measured)})

func _uphill_case() -> void:
	await _fixture(0.0, 0.0, 1.20, Vector3.ZERO, deg_to_rad(33.0), deg_to_rad(83.0))
	var measured: Dictionary = {}
	for _i: int in range(180):
		await _tick()
		var telemetry: Dictionary = bike.get_telemetry()
		if float(telemetry.rearLoad) > 1.0 and not bool(telemetry.frontContact):
			measured = telemetry
			break
		if bike.crashed:
			break
	_check(not measured.is_empty(), "Native 33 degree uphill carries a rear-wheel-only wheelie")
	if not measured.is_empty():
		_check(float(measured.pitch) > float(bike.config.Crash.LoopPitch) and float(measured.crashObservation.supportPitch) < deg_to_rad(60.0),
			"World pitch exceeds 82 degrees while actual terrain-relative pitch stays recoverable", str(measured.crashObservation))
		_check(not bool(measured.crashed), "Terrain slope does not falsely turn a moderate wheelie into a loop-out", str(measured.crashReason))
	observations.append({"case": "uphill", "telemetry": _serializable(measured)})

func _landing_case(label: String, bank: float, height: float, velocity: Vector3) -> Dictionary:
	await _fixture(0.0, bank, height, velocity)
	var first: Dictionary = {}
	for _i: int in range(480):
		await _tick()
		var telemetry: Dictionary = bike.get_telemetry()
		if (telemetry.crashObservation as Dictionary).has("impactSpeed"):
			first = telemetry
			break
		if bike.crashed:
			first = telemetry
			break
	_check(not first.is_empty() and (first.get("crashObservation", {}) as Dictionary).has("impactSpeed"),
		label + " reaches a native contact after meaningful free flight", str(first.get("crashReason", "no impact")))
	observations.append({"case": label, "telemetry": _serializable(first)})
	return first

func _serializable(telemetry: Dictionary) -> Dictionary:
	return {"rollDeg": rad_to_deg(float(telemetry.get("roll", 0.0))),
		"frontLoad": telemetry.get("frontLoad", 0.0), "rearLoad": telemetry.get("rearLoad", 0.0),
		"crashed": telemetry.get("crashed", false), "reason": telemetry.get("crashReason", ""),
		"observation": telemetry.get("crashObservation", {})}

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	_analytic_checks()
	await _berm_case()
	await _uphill_case()
	var vertical: Dictionary = await _landing_case("Vertical banked landing", deg_to_rad(65.0), 1.5, Vector3(0, -5.5, -8))
	var observation: Dictionary = vertical.get("crashObservation", {})
	_check(float(observation.get("sideSpeed", INF)) < 0.5,
		"Native vertical impact does not acquire false lateral speed from bank", str(observation))
	_check(str(vertical.get("crashReason", "")) != "Sideways landing",
		"Banked vertical impact is not incorrectly classified as a sideways landing")
	var sideways: Dictionary = await _landing_case("True sideways landing", 0.0, 2.0, Vector3(7.5, -4, -8))
	_check(bool(sideways.get("crashed", false)) and str(sideways.get("crashReason", "")) == "Sideways landing",
		"Actual fast tangential sideways impact still crashes", str(sideways.get("crashObservation", {})))
	var severe: Dictionary = await _landing_case("Severe tilted impact", deg_to_rad(45.0), 2.0, Vector3(0, -8, -8))
	_check(bool(severe.get("crashed", false)) and str(severe.get("crashReason", "")) == "Poor landing: impact angle",
		"A hard misaligned native impact retains the existing severity crash", str(severe.get("crashObservation", {})))
	await _fixture(0.0, deg_to_rad(85.0), 0.85, Vector3(0, -1, 0))
	var fallen := false
	for _i: int in range(480):
		await _tick()
		if bike.crashed:
			fallen = true
			break
	_check(fallen, "A genuine native severe fall still triggers crash and recovery timing", bike.crash_reason)
	_check(bike._crash_elapsed < float(bike.config.Crash.RecoveryDelay), "Severe fall starts the existing one-second recovery timer")
	observations.append({"case": "severe fall", "telemetry": _serializable(bike.get_telemetry())})
	var report := {"checks": checks, "failures": failures, "observations": observations,
		"controllerHash": String(bike.get_script().source_code).sha256_text()}
	var output := FileAccess.open("res://build/crash-contact-report-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("CRASH CONTACT ", JSON.stringify(report))
	print("Crash contact coordinates: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
