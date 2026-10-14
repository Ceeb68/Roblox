extends SceneTree
## Real SI module regression checks. No engine mocks or claimed riding validation.
## Run: godot --headless --path standalone --script res://tests/math_tests.gd

const Drive = preload("res://physics/drivetrain.gd")
const Tire = preload("res://physics/tire.gd")
const Suspension = preload("res://physics/suspension.gd")
const H: float = 1.0 / 240.0
const RPM: float = PI / 30.0
var bike: Dictionary
var cfg: Dictionary
var tests: int = 0
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	var file: FileAccess = FileAccess.open("res://config/bike_250f.json", FileAccess.READ)
	if file == null:
		push_error("Cannot read 250F configuration")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Invalid 250F configuration")
		quit(1)
		return
	bike = parsed
	cfg = bike.Drive
	_test("neutral idle uses finite torque and leaves wheel free", _idle)
	_test("neutral throttle revs without propulsion", _neutral_rev)
	_test("open clutch isolates wheel even in first gear", _open_clutch)
	_test("manual shift safety and bounds preserve rotor momenta", _shifts)
	_test("ignition cut expires without automatic shifting", _shift_cut)
	_test("redline cuts combustion without imposing speed", _limiter)
	_test("clutch dump can stall and throttle cannot restart", _stall)
	_test("explicit starter requires neutral or disengaged clutch", _starter)
	_test("ideal clutch conserves reflected momentum and dissipates energy", _ideal_clutch)
	_test("inefficient gearbox is passive in both power-flow directions", _inefficient)
	_test("every manual gear couples by its own ratio", _gears)
	_test("rear brake stops signed rotation without reversing", _brakes)
	_test("external signed contact torque is excluded from internal reaction", _external)
	_test("rotor and chassis reaction impulses balance", _reaction)
	_test("native wheel and virtual crank reaction partition is exact", _native_reaction)
	_test("progressive throttle changes acceleration", _throttle)
	_test("partly pulled clutch permits physical slip", _clutch)
	_test("closed throttle brakes wheel only through engaged clutch", _engine_brake)
	_test("60 Hz and 240 Hz callers share implicit clutch solution", _drive_rates)
	_test("240 Hz drivetrain converges toward 480 Hz reference", _drive_convergence)
	_test("zero-duration drivetrain observation leaves state unchanged", _zero_drive)
	_test("varying inputs stay finite without automatic gear changes", _drive_finite)
	_test("pure tire evaluation does not advance patch memory", _evaluate_pure)
	_test("free rolling has no traction and signed rolling loss", _free_roll)
	_test("wheelspin locked-wheel braking and lateral slip have correct signs", _tire_signs)
	_test("reverse rolling and reverse braking oppose motion", _reverse)
	_test("surface grip and loose-sand rolling loss are distinct", _surfaces)
	_test("combined braking and cornering share one friction budget", _friction_circle)
	_test("independent axle load transfer changes grip without shared memory", _loads)
	_test("camber thrust turns toward lean within grip capacity", _camber)
	_test("camber thrust requires tread transport and fades continuously at rest", _camber_transport)
	_test("airborne and unloaded tires produce no forces", _airborne_tire)
	_test("near-rest and nonfinite inputs remain finite without launch force", _low_speed)
	_test("contact relaxation builds over distance and converges across rates", _relaxation)
	_test("uncambered tire contact dissipates slip work", _tire_energy)
	_test("coupled wheel and chassis integration converges", _coupled_contact)
	_test("preload supports contact and ground contact never pulls", _preload)
	_test("spring and preload settings visibly change support", _spring_settings)
	_test("compression and rebound settings act independently", _damping)
	_test("progressive bottom stop and penetration guard remain finite", _bottom)
	_test("progressive rubber stop keeps its constitutive force with soft or absent main coils", _independent_rubber_stop)
	_test("legacy contact suspension is inactive without ground", _airborne_suspension)
	_test("articulated airborne spring extends and damper can pull", _articulated_airborne)
	_test("articulated directional dampers dissipate mechanical work", _articulated_passive)
	_test("hard 1D landing compresses bottoms and converges to static sag", _landing_test)
	print("SI math: %d test cases, %d checks, %d failures" % [tests, checks, failures])
	quit(0 if failures == 0 else 1)

func _test(label: String, run: Callable) -> void:
	tests += 1
	var before: int = failures
	run.call()
	print(("PASS " if failures == before else "FAIL ") + label)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_check(is_finite(actual) and absf(actual - expected) <= tolerance, "%s: expected %s, got %s" % [message, str(expected), str(actual)])

func _passive() -> Dictionary:
	var result: Dictionary = cfg.duplicate(true)
	result.FrictionTorque = 0.0
	result.EngineBrakeTorque = 0.0
	result.Efficiency = 1.0
	result.TorqueCurve = [[0.0, 0.0], [13500.0, 0.0]]
	return result

func _energy(state: Dictionary, configuration: Dictionary) -> float:
	return 0.5 * float(configuration.EngineInertia) * float(state.engineOmega) ** 2 + 0.5 * float(configuration.RearInertia) * float(state.rearOmega) ** 2

func _run_drive(state: Dictionary, input: Dictionary, torque: float, seconds: float, h: float = H, configuration: Dictionary = {}) -> void:
	var settings: Dictionary = cfg if configuration.is_empty() else configuration
	for _step: int in range(roundi(seconds / h)):
		Drive.step(state, input, torque, h, settings)

func _idle() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	_check(int(state.gear) == 0 and not bool(state.stalled), "Starts neutral and running")
	_run_drive(state, {}, 0.0, 10.0)
	_near(float(state.engineOmega), float(cfg.IdleRPM) * RPM, 1e-9, "Idle crank")
	_near(float(state.rearOmega), 0.0, 0.0, "Free neutral wheel")

func _neutral_rev() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	_run_drive(state, {"throttle": 1.0}, 0.0, 1.0)
	_check(float(state.engineOmega) > float(cfg.IdleRPM) * RPM * 2.0, "Throttle revs crank")
	_near(float(state.rearOmega), 0.0, 0.0, "Neutral does not propel")

func _open_clutch() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	state.gear = 1
	_run_drive(state, {"throttle": 1.0, "clutch": 1.0}, 0.0, 0.4)
	_check(float(state.engineOmega) > float(cfg.IdleRPM) * RPM, "Open clutch permits revs")
	_near(float(state.rearOmega), 0.0, 0.0, "Open clutch isolates wheel")

func _shifts() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	var initial: float = float(state.engineOmega)
	_check(not Drive.shift(state, 1, {"throttle": 1.0}, cfg), "Loaded shift rejected")
	_check(Drive.shift(state, 1, {"throttle": 1.0, "clutch": 1.0}, cfg), "Pulled-clutch shift accepted")
	_near(float(state.engineOmega), initial, 0.0, "Shift preserves crank momentum")
	_near(float(state.rearOmega), 0.0, 0.0, "Shift preserves rear momentum")
	_check(not Drive.shift(state, 1, {"clutch": 1.0}, cfg), "Cannot double shift during ignition cut")
	state.shiftTimer = 0.0
	_check(Drive.shift(state, 1, {}, cfg), "Unloaded shift accepted")
	state.shiftTimer = 0.0
	_check(not Drive.shift(state, 2, {}, cfg), "Cannot skip a gear event")
	state.gear = 5
	_check(not Drive.shift(state, 1, {}, cfg), "Top gear bounded")
	state.gear = 0
	_check(not Drive.shift(state, -1, {}, cfg), "No artificial reverse gear")

func _shift_cut() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	Drive.shift(state, 1, {"clutch": 1.0, "throttle": 1.0}, cfg)
	var before: float = float(state.engineOmega)
	Drive.step(state, {"clutch": 1.0, "throttle": 1.0}, 0.0, float(cfg.ShiftCutTime) / 2.0, cfg)
	_check(float(state.engineOmega) < before and float(state.shiftTimer) > 0.0, "Ignition cut loses speed to friction")
	_run_drive(state, {"clutch": 1.0, "throttle": 1.0}, 0.0, 0.2)
	_check(float(state.engineOmega) > before and float(state.shiftTimer) == 0.0 and int(state.gear) == 1, "Ignition resumes in selected gear")

func _limiter() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	state.engineOmega = (float(cfg.RedlineRPM) + 200.0) * RPM
	var before: float = float(state.engineOmega)
	Drive.step(state, {"throttle": 1.0, "clutch": 1.0}, 0.0, H, cfg)
	_check(bool(state.limiter) and float(state.engineOmega) < before, "Limiter cuts combustion")
	_check(float(state.engineOmega) > float(cfg.RedlineRPM) * RPM, "Limiter does not snap to speed target")
	_run_drive(state, {"throttle": 1.0, "clutch": 1.0}, 0.0, 10.0)
	_check(float(state.engineOmega) / RPM < float(cfg.RedlineRPM) + 100.0 and int(state.gear) == 0, "Finite redline without auto shift")

func _stall() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	# This isolated rear rotor has no ground or vehicle/front-brake load.
	# A high-gear clutch dump makes the real 190 Nm rear brake exceed the
	# bounded idle governor: 190 / (3.35 * 1.06 * 3.85) = 13.9 Nm at the
	# crank versus 10 Nm maximum idle combustion. First gear's larger ratio
	# reflects less braking and can spin this free rotor beyond one second.
	state.gear = cfg.GearRatios.size()
	_run_drive(state, {"rearBrake": 1.0}, 0.0, 1.0)
	_check(bool(state.stalled) and float(state.engineOmega) < float(cfg.StallRPM) * RPM, "High-gear clutch overload physically stalls")
	_run_drive(state, {"throttle": 1.0, "clutch": 1.0}, 0.0, 0.5)
	_check(bool(state.stalled), "Throttle does not silently restart")

func _starter() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	_check(not Drive.start(state, {"clutch": 1.0}, cfg), "Live engine cannot gain starter energy")
	state.stalled = true
	state.engineOmega = 0.0
	state.gear = 1
	_check(not Drive.start(state, {"clutch": 0.8}, cfg), "In-gear start clutch threshold")
	_check(Drive.start(state, {"clutch": 1.0}, cfg), "Explicit pulled-clutch start")
	_near(float(state.engineOmega), float(cfg.IdleRPM) * RPM, 1e-12, "Starter supplies idle energy")
	state.stalled = true
	state.gear = 0
	_check(Drive.start(state, {}, cfg), "Neutral start allowed")

func _ideal_clutch() -> void:
	var passive: Dictionary = _passive()
	var ratio: float = Drive.ratio_for(1, passive)
	for speeds: Array in [[900.0, 0.0], [100.0, 80.0], [0.0, -40.0], [-100.0, 40.0]]:
		var state: Dictionary = Drive.new_state(passive)
		state.gear = 1
		state.stalled = true
		state.engineOmega = speeds[0]
		state.rearOmega = speeds[1]
		var energy: float = _energy(state, passive)
		var momentum: float = float(passive.EngineInertia) * float(state.engineOmega) + float(passive.RearInertia) * float(state.rearOmega) / ratio
		Drive.step(state, {}, 0.0, 0.05, passive)
		_near(float(passive.EngineInertia) * float(state.engineOmega) + float(passive.RearInertia) * float(state.rearOmega) / ratio, momentum, 1e-10, "Reflected momentum")
		_check(_energy(state, passive) <= energy + 1e-9, "Clutch cannot generate kinetic energy")

func _inefficient() -> void:
	var passive: Dictionary = _passive()
	passive.Efficiency = 0.5
	for engine: int in range(-400, 801, 200):
		for wheel: int in range(-60, 61, 20):
			var state: Dictionary = Drive.new_state(passive)
			state.gear = 3
			state.stalled = true
			state.engineOmega = float(engine)
			state.rearOmega = float(wheel)
			var previous: float = _energy(state, passive)
			for _tick: int in range(30):
				Drive.step(state, {}, 0.0, H, passive)
				var current: float = _energy(state, passive)
				_check(current <= previous + 1e-9, "Transmission loss remains passive during back-drive")
				previous = current

func _gears() -> void:
	var passive: Dictionary = _passive()
	for gear: int in range(1, 6):
		var state: Dictionary = Drive.new_state(passive)
		state.gear = gear
		state.stalled = true
		state.engineOmega = 400.0
		state.rearOmega = 20.0
		Drive.step(state, {}, 0.0, 0.1, passive)
		_near(float(state.engineOmega), float(state.rearOmega) * Drive.ratio_for(gear, passive), 1e-8, "Gear-coupled speed")

func _brakes() -> void:
	var passive: Dictionary = _passive()
	for speed: float in [-100.0, -0.1, 0.0, 0.1, 100.0]:
		var state: Dictionary = Drive.new_state(passive)
		state.stalled = true
		state.engineOmega = 0.0
		state.rearOmega = speed
		Drive.step(state, {"clutch": 1.0, "rearBrake": 1.0}, 0.0, 0.5, passive)
		_check(float(state.rearOmega) * speed >= 0.0, "Brake cannot reverse wheel")
		_near(float(state.rearOmega), 0.0, 1e-10, "Brake stops wheel")
	_near(Drive.retard(0.0, 100.0, float(cfg.RearInertia)), 0.0, 0.0, "Brake at rest produces no spin")

func _external() -> void:
	var passive: Dictionary = _passive()
	var state: Dictionary = Drive.new_state(passive)
	state.stalled = true
	state.engineOmega = 0.0
	var output: Dictionary = Drive.step(state, {"clutch": 1.0}, -72.0, 0.1, passive)
	_near(float(state.rearOmega), -10.0, 1e-10, "Signed rollback torque")
	_near(float(output.engineReaction), 0.0, 1e-10, "External torque excluded from body reaction")

func _reaction() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	state.gear = 2
	state.engineOmega = 8000.0 * RPM
	state.rearOmega = 40.0
	var before: float = float(cfg.EngineInertia) * float(state.engineOmega) + float(cfg.RearInertia) * float(state.rearOmega)
	var dt: float = 1.0 / 60.0
	var output: Dictionary = Drive.step(state, {"throttle": 0.4, "clutch": 0.2, "rearBrake": 0.1}, -25.0, dt, cfg)
	var after: float = float(cfg.EngineInertia) * float(state.engineOmega) + float(cfg.RearInertia) * float(state.rearOmega)
	_near((float(output.engineReaction) - 25.0) * dt, after - before, 1e-10, "Reaction momentum accounting")

func _native_reaction() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	state.gear = 1
	state.engineOmega = 9000.0 * RPM
	state.rearOmega = 15.0
	var initial: float = float(state.rearOmega)
	var output: Dictionary = Drive.step(state, {"throttle": 0.5, "rearBrake": 0.2}, 0.0, H, cfg)
	var native_spin: float = float(cfg.RearInertia) * (float(state.rearOmega) - initial) / H
	_near(float(output.engineOnlyReaction) + native_spin, float(output.engineReaction), 1e-9, "Native-wheel paired reaction plus virtual crank equals full reaction")

func _throttle() -> void:
	var half: Dictionary = Drive.new_state(cfg)
	var full: Dictionary = Drive.new_state(cfg)
	for state: Dictionary in [half, full]:
		state.gear = 3
		state.engineOmega = 6500.0 * RPM
		state.rearOmega = float(state.engineOmega) / Drive.ratio_for(3, cfg)
	_run_drive(half, {"throttle": 0.5}, 0.0, 0.5)
	_run_drive(full, {"throttle": 1.0}, 0.0, 0.5)
	_check(float(full.rearOmega) > float(half.rearOmega) + 1.0, "Full throttle accelerates more than half")

func _clutch() -> void:
	var pulled: Dictionary = Drive.new_state(cfg)
	var engaged: Dictionary = Drive.new_state(cfg)
	for state: Dictionary in [pulled, engaged]:
		state.gear = 1
		state.engineOmega = 8000.0 * RPM
	Drive.step(pulled, {"throttle": 1.0, "clutch": 0.9}, 0.0, H, cfg)
	Drive.step(engaged, {"throttle": 1.0}, 0.0, H, cfg)
	_check(float(pulled.rearOmega) < float(engaged.rearOmega) and float(pulled.engineOmega) > float(engaged.engineOmega), "Clutch engagement controls transmitted torque and slip")

func _engine_brake() -> void:
	var coupled: Dictionary = Drive.new_state(cfg)
	var opened: Dictionary = Drive.new_state(cfg)
	for state: Dictionary in [coupled, opened]:
		state.gear = 3
		state.engineOmega = 9000.0 * RPM
		state.rearOmega = float(state.engineOmega) / Drive.ratio_for(3, cfg)
	var before: float = float(coupled.rearOmega)
	_run_drive(coupled, {}, 0.0, 0.4)
	_run_drive(opened, {"clutch": 1.0}, 0.0, 0.4)
	_check(float(coupled.rearOmega) < before, "Engaged clutch transmits pumping loss")
	_near(float(opened.rearOmega), before, 1e-10, "Open clutch isolates pumping loss")

func _drive_rates() -> void:
	var coarse: Dictionary = Drive.new_state(cfg)
	var fine: Dictionary = Drive.new_state(cfg)
	for state: Dictionary in [coarse, fine]:
		state.gear = 3
		state.engineOmega = 6500.0 * RPM
		state.rearOmega = float(state.engineOmega) / Drive.ratio_for(3, cfg)
	var input: Dictionary = {"throttle": 0.7, "clutch": 0.3, "rearBrake": 0.1}
	_run_drive(coarse, input, -10.0, 1.0, 1.0 / 60.0)
	_run_drive(fine, input, -10.0, 1.0, H)
	_near(float(coarse.engineOmega), float(fine.engineOmega), 1e-8, "Crank rate equivalence")
	_near(float(coarse.rearOmega), float(fine.rearOmega), 1e-8, "Wheel rate equivalence")

func _drive_convergence() -> void:
	var coarse: Dictionary = Drive.new_state(cfg)
	var fine: Dictionary = Drive.new_state(cfg)
	for state: Dictionary in [coarse, fine]:
		state.gear = 3
		state.engineOmega = 6500.0 * RPM
		state.rearOmega = float(state.engineOmega) / Drive.ratio_for(3, cfg)
	_run_drive(coarse, {"throttle": 0.6}, -20.0, 1.0, H)
	_run_drive(fine, {"throttle": 0.6}, -20.0, 1.0, 1.0 / 480.0)
	_near(float(coarse.engineOmega), float(fine.engineOmega), 2.0, "Crank integration convergence rad/s")
	_near(float(coarse.rearOmega), float(fine.rearOmega), 0.1, "Wheel integration convergence rad/s")

func _zero_drive() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	var before: Dictionary = state.duplicate(true)
	var output: Dictionary = Drive.step(state, {"throttle": 1.0}, 50.0, 0.0, cfg)
	_check(state == before, "Zero dt must leave every drive state unchanged")
	_near(float(output.engineReaction), 0.0, 0.0, "Zero dt reaction")
	_near(float(output.power), 0.0, 0.0, "Zero dt power")

func _drive_finite() -> void:
	var state: Dictionary = Drive.new_state(cfg)
	state.gear = 2
	var stable: bool = true
	for index: int in range(1, 12001):
		var input: Dictionary = {"throttle": 0.5 + 0.5 * sin(index / 211.0), "clutch": 1.0 if index % 1200 < 300 else 0.2, "rearBrake": 0.5 + 0.5 * sin(index / 377.0)}
		var output: Dictionary = Drive.step(state, input, 80.0 * sin(index / 487.0), H, cfg)
		for field: String in ["rearOmega", "rpm", "clutchSlip", "engineReaction", "power"]:
			stable = stable and is_finite(float(output[field]))
		stable = stable and int(state.gear) == 2
		if bool(state.stalled) and float(input.clutch) == 1.0:
			Drive.start(state, input, cfg)
	_check(stable, "50 seconds of varied controls must stay finite in manually selected gear")

func _sample(vx: float, vy: float, omega: float, load: float = 920.0) -> Dictionary:
	return {"normalLoad": load, "longitudinalVelocity": vx, "lateralVelocity": vy, "wheelOmega": omega, "radius": float(bike.RearRadius), "camber": 0.0, "contact": true}

func _settled(input: Dictionary, surface: Dictionary = {}) -> Dictionary:
	var state: Dictionary = Tire.new_state()
	var ground: Dictionary = bike.Surfaces.dirt if surface.is_empty() else surface
	return Tire.step(state, input, 2.0, bike.Tire, ground)

func _force(output: Dictionary) -> float:
	return Vector2(float(output.longitudinalForce), float(output.lateralForce)).length()

func _evaluate_pure() -> void:
	var state: Dictionary = Tire.new_state()
	var input: Dictionary = _sample(10.0, 3.0, 50.0)
	Tire.step(state, input, H, bike.Tire, bike.Surfaces.dirt)
	var before: Dictionary = state.duplicate(true)
	Tire.evaluate(state, input, bike.Tire, bike.Surfaces.dirt)
	_check(state == before, "Trial load evaluation must not advance patch strain")

func _free_roll() -> void:
	var output: Dictionary = _settled(_sample(12.0, 0.0, 12.0 / float(bike.RearRadius)))
	_near(float(output.longitudinalForce), 0.0, 1e-8, "Pure rolling longitudinal force")
	_near(float(output.lateralForce), 0.0, 1e-8, "Pure rolling lateral force")
	_check(float(output.rollingTorque) < 0.0, "Rolling loss opposes forward spin")

func _tire_signs() -> void:
	var spin: Dictionary = _settled(_sample(8.0, 0.0, 18.0 / float(bike.RearRadius)))
	var locked: Dictionary = _settled(_sample(8.0, 0.0, 0.0))
	var slide: Dictionary = _settled(_sample(8.0, 5.0, 8.0 / float(bike.RearRadius)))
	_check(float(spin.longitudinalForce) > 0.0 and float(spin.contactTorque) < 0.0, "Drive slip propels chassis and retards wheel")
	_check(float(locked.longitudinalForce) < 0.0 and float(locked.contactTorque) > 0.0, "Locked tire brakes chassis while ground spins wheel")
	_check(float(slide.lateralForce) < 0.0, "Lateral grip opposes sideslip")

func _reverse() -> void:
	var rolling: Dictionary = _settled(_sample(-8.0, 0.0, -8.0 / float(bike.RearRadius)))
	var locked: Dictionary = _settled(_sample(-8.0, 0.0, 0.0))
	_check(float(rolling.rollingTorque) > 0.0, "Reverse spin receives positive rolling loss torque")
	_check(float(locked.longitudinalForce) > 0.0 and float(locked.contactTorque) < 0.0, "Reverse braking pushes toward rest")

func _surfaces() -> void:
	var sample: Dictionary = _sample(12.0, 8.0, 30.0 / float(bike.RearRadius))
	var hard: float = _force(_settled(sample, bike.Surfaces.hardpack))
	var dirt: float = _force(_settled(sample, bike.Surfaces.dirt))
	var sand: float = _force(_settled(sample, bike.Surfaces.sand))
	var mud: float = _force(_settled(sample, bike.Surfaces.mud))
	_check(hard > dirt and dirt > sand and sand > mud, "Grip ranking follows surface coefficients")
	var rolling: Dictionary = _sample(12.0, 0.0, 12.0 / float(bike.RearRadius))
	_check(absf(float(_settled(rolling, bike.Surfaces.sand).rollingTorque)) > absf(float(_settled(rolling, bike.Surfaces.hardpack).rollingTorque)), "Sand adds independent rolling loss")

func _friction_circle() -> void:
	var corner: Dictionary = _settled(_sample(12.0, 6.0, 12.0 / float(bike.RearRadius)))
	var input: Dictionary = _sample(12.0, 6.0, 0.0)
	var combined: Dictionary = _settled(input)
	_check(float(combined.longitudinalForce) < 0.0 and float(combined.lateralForce) < 0.0, "Both force components survive")
	_check(absf(float(combined.lateralForce)) < absf(float(corner.lateralForce)), "Braking consumes cornering capacity")
	_check(_force(combined) <= float(combined.grip) * float(input.normalLoad) + 1e-7, "Force stays inside friction circle")
	_check(bool(combined.sliding) and float(combined.utilization) > 0.999, "Saturation identifies washout/sliding condition")

func _loads() -> void:
	var front_state: Dictionary = Tire.new_state()
	var rear_state: Dictionary = Tire.new_state()
	var front: Dictionary = Tire.step(front_state, _sample(14.0, 9.0, 0.0, 1350.0), 1.0, bike.Tire, bike.Surfaces.dirt)
	var rear: Dictionary = Tire.step(rear_state, _sample(14.0, 9.0, 0.0, 450.0), 1.0, bike.Tire, bike.Surfaces.dirt)
	_check(_force(front) > _force(rear) and float(front.grip) < float(rear.grip), "Loaded front gains force but loses relative efficiency")
	_check(_force(front) + _force(rear) < 2.0 * _force(_settled(_sample(14.0, 9.0, 0.0, 900.0))), "Unequal loading reduces total grip")
	var remembered: float = float(rear_state.slipRatio)
	Tire.step(front_state, _sample(14.0, -9.0, 90.0, 1350.0), H, bike.Tire, bike.Surfaces.dirt)
	_near(float(rear_state.slipRatio), remembered, 0.0, "Front updates cannot mutate rear memory")

func _camber() -> void:
	var sample: Dictionary = _sample(12.0, 0.0, 12.0 / float(bike.RearRadius))
	sample.camber = deg_to_rad(30.0)
	var positive: Dictionary = _settled(sample)
	_check(float(positive.lateralForce) > 0.0, "Wheel-right lean creates wheel-right thrust")
	_check(_force(positive) <= float(positive.grip) * float(sample.normalLoad) + 1e-7, "Camber respects friction circle")
	sample.camber = -float(sample.camber)
	_near(float(_settled(sample).lateralForce), -float(positive.lateralForce), 1e-8, "Camber symmetry")

func _camber_transport() -> void:
	var sample: Dictionary = _sample(0.0, 0.0, 0.0)
	sample.camber = deg_to_rad(30.0)
	var state: Dictionary = Tire.new_state()
	_near(float(Tire.evaluate(state, sample, bike.Tire, bike.Surfaces.dirt).lateralForce), 0.0, 0.0, "An unstrained stationary inclined tire has no rolling camber thrust")
	var last_force := 0.0
	for speed: float in [0.01, 0.10, 0.50, 1.0, float(bike.Tire.MinimumSpeed)]:
		sample.longitudinalVelocity = speed
		sample.wheelOmega = speed / float(sample.radius)
		var output: Dictionary = Tire.evaluate(state, sample, bike.Tire, bike.Surfaces.dirt)
		_check(float(output.lateralForce) > last_force, "Camber builds continuously with tread transport")
		_check(_force(output) <= float(output.grip) * float(sample.normalLoad) + 1e-7, "Low-speed camber stays inside the original combined grip budget")
		last_force = float(output.lateralForce)
	var forward_force := last_force
	sample.longitudinalVelocity = -float(sample.longitudinalVelocity)
	sample.wheelOmega = -float(sample.wheelOmega)
	_near(float(Tire.evaluate(state, sample, bike.Tire, bike.Surfaces.dirt).lateralForce), forward_force, 1e-8, "Reverse rolling retains the same camber force direction")
	sample.longitudinalVelocity = 0.0
	sample.wheelOmega = 0.0
	state.slipAngle = 0.1
	var inclined: Dictionary = Tire.evaluate(state, sample, bike.Tire, bike.Surfaces.dirt)
	sample.camber = 0.0
	var uncambered: Dictionary = Tire.evaluate(state, sample, bike.Tire, bike.Surfaces.dirt)
	_near(float(inclined.lateralForce), float(uncambered.lateralForce), 1e-8, "Stopping camber transport does not erase existing lateral patch strain")

func _airborne_tire() -> void:
	var sample: Dictionary = _sample(20.0, 10.0, 100.0)
	var state: Dictionary = Tire.new_state()
	Tire.step(state, sample, 0.1, bike.Tire, bike.Surfaces.dirt)
	sample.contact = false
	var output: Dictionary = Tire.step(state, sample, H, bike.Tire, bike.Surfaces.dirt)
	_near(_force(output), 0.0, 0.0, "Airborne force")
	_near(float(output.contactTorque), 0.0, 0.0, "Airborne torque")
	sample.contact = true
	sample.normalLoad = 0.0
	_near(_force(_settled(sample)), 0.0, 0.0, "Unloaded force")

func _low_speed() -> void:
	for vx: float in [-1e-8, 0.0, 1e-8]:
		var output: Dictionary = _settled(_sample(vx, 0.0, vx / float(bike.RearRadius)))
		_near(float(output.longitudinalForce), 0.0, 1e-6, "No artificial launch force at rest")
		_check(is_finite(float(output.slipRatio)), "Finite near-zero slip")
	_check(float(_settled(_sample(0.0, 0.0, 40.0)).longitudinalForce) > 0.0, "Spinning wheel can accelerate at rest")
	var invalid: Dictionary = _sample(INF, NAN, NAN)
	invalid.normalLoad = NAN
	var safe: Dictionary = _settled(invalid)
	_check(is_finite(float(safe.contactTorque)) and _force(safe) == 0.0, "Nonfinite contact input is sanitized")

func _relaxation() -> void:
	var sample: Dictionary = _sample(8.0, 0.0, 10.0 / float(bike.RearRadius))
	var state: Dictionary = Tire.new_state()
	var first: Dictionary = Tire.step(state, sample, H, bike.Tire, bike.Surfaces.dirt)
	var second: Dictionary = Tire.step(state, sample, H, bike.Tire, bike.Surfaces.dirt)
	var final: Dictionary = _settled(sample)
	_check(float(first.slipRatio) < float(second.slipRatio) and float(second.slipRatio) < float(final.slipRatio), "Patch builds strain progressively")
	_check(float(first.longitudinalForce) < float(second.longitudinalForce), "Force follows patch relaxation")
	var a: Dictionary = Tire.new_state()
	var b: Dictionary = Tire.new_state()
	sample = _sample(3.0, 0.3, 3.3 / float(bike.RearRadius))
	for _index: int in range(12):
		Tire.step(a, sample, 1.0 / 120.0, bike.Tire, bike.Surfaces.dirt)
	for _index: int in range(48):
		Tire.step(b, sample, 1.0 / 480.0, bike.Tire, bike.Surfaces.dirt)
	_near(float(a.slipRatio), float(b.slipRatio), 1e-10, "Relaxation rate invariance")
	_near(float(a.slipAngle), float(b.slipAngle), 1e-10, "Lateral relaxation rate invariance")

func _tire_energy() -> void:
	for sample: Dictionary in [_sample(12.0, 4.0, 25.0 / float(bike.RearRadius)), _sample(12.0, -4.0, 0.0), _sample(-12.0, 4.0, -25.0 / float(bike.RearRadius))]:
		var output: Dictionary = _settled(sample)
		var power: float = float(output.longitudinalForce) * (float(sample.longitudinalVelocity) - float(sample.wheelOmega) * float(sample.radius)) + float(output.lateralForce) * float(sample.lateralVelocity)
		_check(power <= 1e-8, "Uncambered steady tire must dissipate slip work")

func _accelerate(h: float) -> Vector2:
	var mass: float = 94.0
	var velocity: float = 5.0
	var omega: float = 5.0 / float(bike.RearRadius)
	var state: Dictionary = Tire.new_state()
	for _index: int in range(roundi(2.0 / h)):
		var output: Dictionary = Tire.step(state, _sample(velocity, 0.0, omega, mass * float(bike.Gravity)), h, bike.Tire, bike.Surfaces.dirt)
		velocity += float(output.longitudinalForce) * h / mass
		omega += (75.0 + float(output.contactTorque)) * h / float(bike.RearInertia)
	return Vector2(velocity, omega)

func _coupled_contact() -> void:
	var coarse: Vector2 = _accelerate(1.0 / 120.0)
	var normal: Vector2 = _accelerate(H)
	var fine: Vector2 = _accelerate(1.0 / 480.0)
	_check(normal.x > 7.0 and normal.y > 5.0 / float(bike.RearRadius), "Wheel torque accelerates chassis and wheel")
	_near(coarse.x, fine.x, 0.025, "Chassis coarse convergence")
	_near(normal.x, fine.x, 0.01, "Chassis default convergence")
	_near(coarse.y, fine.y, 0.08, "Wheel coarse convergence")
	_near(normal.y, fine.y, 0.04, "Wheel default convergence")

func _preload() -> void:
	var settings: Dictionary = bike.Suspension.Front
	var preload_result: Dictionary = Suspension.step(Suspension.new_state(), 0.0, 0.0, true, H, settings)
	_near(float(preload_result.force), float(settings.SpringRate) * float(settings.Preload), 1e-9, "Preload support")
	_near(float(Suspension.step(Suspension.new_state(), 0.04, -10.0, true, H, settings).force), 0.0, 0.0, "Ground contact cannot pull")

func _spring_settings() -> void:
	var settings: Dictionary = bike.Suspension.Rear.duplicate(true)
	var base: float = float(Suspension.step(Suspension.new_state(), 0.1, 0.0, true, H, settings).force)
	settings.SpringRate = float(settings.SpringRate) * 1.4
	var stiff: float = float(Suspension.step(Suspension.new_state(), 0.1, 0.0, true, H, settings).force)
	_check(stiff > base * 1.3, "Spring setting influences support")
	settings.Preload = float(settings.Preload) + 0.02
	_check(float(Suspension.step(Suspension.new_state(), 0.1, 0.0, true, H, settings).force) > stiff, "Preload setting influences support")

func _damping() -> void:
	var settings: Dictionary = bike.Suspension.Front
	var rest: float = float(Suspension.step(Suspension.new_state(), 0.15, 0.0, true, H, settings).force)
	var compress: float = float(Suspension.step(Suspension.new_state(), 0.15, 0.5, true, H, settings).force)
	var rebound: float = float(Suspension.step(Suspension.new_state(), 0.15, -0.5, true, H, settings).force)
	_near(compress - rest, float(settings.Compression) * 0.5, 1e-8, "Compression damper")
	_near(rest - rebound, float(settings.Rebound) * 0.5, 1e-8, "Rebound damper")
	var adjusted: Dictionary = settings.duplicate(true)
	adjusted.Compression = float(adjusted.Compression) * 2.0
	_near(float(Suspension.step(Suspension.new_state(), 0.15, 0.5, true, H, adjusted).force) - rest, float(settings.Compression), 1e-8, "Compression adjustment")
	_near(float(Suspension.step(Suspension.new_state(), 0.15, -0.5, true, H, adjusted).force), rebound, 0.0, "Compression adjustment leaves rebound unchanged")
	adjusted.Rebound = float(adjusted.Rebound) * 0.5
	_check(float(Suspension.step(Suspension.new_state(), 0.15, -0.5, true, H, adjusted).force) > rebound, "Independent rebound adjustment")

func _bottom() -> void:
	var settings: Dictionary = bike.Suspension.Front
	var before: Dictionary = Suspension.step(Suspension.new_state(), float(settings.Travel) * 0.8, 0.0, true, H, settings)
	var bottom: Dictionary = Suspension.step(Suspension.new_state(), float(settings.Travel), 0.0, true, H, settings)
	var beyond: Dictionary = Suspension.step(Suspension.new_state(), float(settings.Travel) * 1.1, 0.0, true, H, settings)
	_check(not bool(before.bottomed) and bool(bottom.bottomed) and bool(beyond.bottomed), "Bottom threshold follows travel")
	_check(float(bottom.force) > float(settings.SpringRate) * (float(settings.Travel) + float(settings.Preload)), "Bump stop stiffens before end stop")
	_check(float(beyond.force) > float(bottom.force), "Overtravel stiffens progressively")
	var extreme: Dictionary = Suspension.step(Suspension.new_state(), 1e6, 1e6, true, H, settings)
	_check(is_finite(float(extreme.force)) and float(extreme.force) < 100000.0, "Penetration force bounded")

func _independent_rubber_stop() -> void:
	# The rubber end stop is independent of the main coil. A weak/broken coil
	# must not numerically clip its force while the stop is being compressed.
	for axle: String in ["Front", "Rear"]:
		var original: Dictionary = bike.Suspension[axle]
		var travel: float = float(original.Travel)
		var compression := travel + 0.01
		var bump_band := travel * 0.15
		var rubber_compression := compression - (travel - bump_band)
		var rubber_force := float(original.BumpRate) * rubber_compression ** 2 / bump_band
		for spring_rate: float in [0.0, 1000.0, float(original.SpringRate)]:
			var settings: Dictionary = original.duplicate(true)
			settings.SpringRate = spring_rate
			var expected := rubber_force + spring_rate * (compression + float(settings.Preload))
			var contact: Dictionary = Suspension.step(Suspension.new_state(), compression, 0.0, true, H, settings)
			var articulated: Dictionary = Suspension.step_articulated(Suspension.new_state(), compression, 0.0, H, settings)
			_near(float(contact.force), expected, 1e-6, "%s contact rubber law at main coil %.0f N/m" % [axle, spring_rate])
			_near(float(articulated.force), expected, 1e-6, "%s articulated rubber law at main coil %.0f N/m" % [axle, spring_rate])

func _airborne_suspension() -> void:
	var state: Dictionary = Suspension.new_state()
	var output: Dictionary = Suspension.step(state, 0.28, 8.0, false, H, bike.Suspension.Rear)
	_near(float(output.force), 0.0, 0.0, "No contact-law airborne force")
	_check(not bool(output.bottomed) and not bool(state.contact), "Absent contact telemetry")

func _articulated_airborne() -> void:
	var state: Dictionary = Suspension.new_state()
	var extended: Dictionary = Suspension.step_articulated(state, 0.1, 0.0, H, bike.Suspension.Rear)
	_check(float(extended.force) > 0.0 and not bool(state.contact), "Articulated spring extends with no ground contact")
	var damping: Dictionary = Suspension.step_articulated(state, 0.02, -2.0, H, bike.Suspension.Rear)
	_check(float(damping.force) < 0.0, "Hydraulic rebound can pull articulated axle inward")
	var nan_output: Dictionary = Suspension.step_articulated(state, NAN, INF, H, bike.Suspension.Rear)
	_check(is_finite(float(nan_output.force)), "Articulated invalid geometry is bounded")

func _articulated_passive() -> void:
	var settings: Dictionary = bike.Suspension.Rear
	var static_force: float = float(Suspension.step_articulated(Suspension.new_state(), 0.15, 0.0, H, settings).force)
	for rate: float in [-2.0, -0.5, 0.5, 2.0]:
		var output: Dictionary = Suspension.step_articulated(Suspension.new_state(), 0.15, rate, H, settings)
		var damper_power: float = -(float(output.force) - static_force) * rate
		_check(damper_power <= 0.0, "Articulated damper must dissipate in either direction")

func _landing(h: float) -> Dictionary:
	var mass: float = 94.0
	var settings: Dictionary = bike.Suspension.Rear
	var compression: float = 0.005
	var rate: float = 12.0
	var peak: float = 0.0
	var bottomed: bool = false
	var state: Dictionary = Suspension.new_state()
	for _tick: int in range(roundi(4.0 / h)):
		var output: Dictionary = Suspension.step(state, compression, rate, compression >= 0.0, h, settings)
		rate += (float(bike.Gravity) - float(output.force) / mass) * h
		compression += rate * h
		peak = maxf(peak, compression)
		bottomed = bottomed or bool(output.bottomed)
	return {"compression": compression, "peak": peak, "bottomed": bottomed}

func _landing_test() -> void:
	var coarse: Dictionary = _landing(1.0 / 120.0)
	var normal: Dictionary = _landing(H)
	var fine: Dictionary = _landing(1.0 / 480.0)
	var settings: Dictionary = bike.Suspension.Rear
	var sag: float = 94.0 * float(bike.Gravity) / float(settings.SpringRate) - float(settings.Preload)
	_near(float(normal.compression), sag, 0.0001, "Settles to physical static sag")
	_near(float(coarse.compression), float(fine.compression), 0.0001, "Landing settled convergence")
	_near(float(normal.peak), float(fine.peak), 0.006, "240 Hz landing peak convergence")
	_near(float(coarse.peak), float(fine.peak), 0.02, "Coarse landing remains bounded")
	_check(bool(coarse.bottomed) and bool(normal.bottomed) and bool(fine.bottomed), "Hard landing exercises progressive stop")
	_check(float(fine.peak) < float(settings.Travel) * 1.2, "Bump stop limits overtravel")
