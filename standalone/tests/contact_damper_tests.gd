extends SceneTree
## Native hydraulic decay bench: a 100 kg carrier and 5 kg axle are tested free
## and against a real Jolt cylinder/ground normal constraint. Only the hydraulic
## material law is active; no spring, engine, rider or assistance torque.
## Match --fixed-fps with -- --hz=240/480 so each await consumes one native step.
const Suspension = preload("res://physics/suspension.gd")
var hz: int = 240
var reports: Array[Dictionary] = []
var checks: int = 0
var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("CONTACT DAMPER FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _tick() -> void:
	await physics_frame
	await process_frame

func _decay_case(supported: bool, corrected: bool) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var carrier := RigidBody3D.new()
	carrier.mass = 100.0
	carrier.can_sleep = false
	carrier.gravity_scale = 0.0
	carrier.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	carrier.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	carrier.linear_damp = 0.0
	carrier.angular_damp = 0.0
	carrier.position = Vector3(0.0, 1.348, 0.0)
	carrier.collision_mask = 0
	carrier.axis_lock_angular_x = true
	carrier.axis_lock_angular_y = true
	carrier.axis_lock_angular_z = true
	var carrier_collision := CollisionShape3D.new()
	var carrier_shape := SphereShape3D.new()
	carrier_shape.radius = 0.01
	carrier_collision.shape = carrier_shape
	carrier.add_child(carrier_collision)
	world.add_child(carrier)
	var wheel := RigidBody3D.new()
	wheel.mass = 5.0
	wheel.can_sleep = false
	wheel.gravity_scale = 1.0 if supported else 0.0
	wheel.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	wheel.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	wheel.linear_damp = 0.0
	wheel.angular_damp = 0.0
	wheel.position = Vector3(0.0, 0.348, 0.0)
	wheel.contact_monitor = true
	wheel.max_contacts_reported = 8
	wheel.axis_lock_angular_x = true
	wheel.axis_lock_angular_y = true
	wheel.axis_lock_angular_z = true
	var wheel_collision := CollisionShape3D.new()
	var wheel_shape := CylinderShape3D.new()
	wheel_shape.radius = 0.348
	wheel_shape.height = 0.085
	wheel_shape.margin = 0.03825
	wheel_collision.shape = wheel_shape
	wheel_collision.rotation.z = PI * 0.5
	wheel.add_child(wheel_collision)
	world.add_child(wheel)
	if supported:
		var ground := StaticBody3D.new()
		var ground_collision := CollisionShape3D.new()
		var ground_shape := BoxShape3D.new()
		ground_shape.size = Vector3(10.0, 0.2, 10.0)
		ground_collision.shape = ground_shape
		ground_collision.position.y = -0.1
		ground.add_child(ground_collision)
		world.add_child(ground)
	for _i: int in range(20):
		await _tick()
	# A single initial perturbation. Afterwards only real native forces act.
	carrier.linear_velocity = Vector3(0.0, -0.2, 0.0)
	wheel.linear_velocity = Vector3.ZERO
	var coefficient := 1000.0 if supported else 100.0
	# The rubber-stop coefficient supplies a distant force safety bound; the
	# constant 10 cm stroke never engages it. Coil/preload are zero throughout.
	var settings := {"Travel": 0.3, "SpringRate": 0.0, "Preload": 0.0,
		"BumpRate": 400000.0, "Compression": coefficient, "Rebound": coefficient}
	var initial_rate: float = (wheel.linear_velocity - carrier.linear_velocity).y
	var free_mass := 1.0 / (1.0 / carrier.mass + 1.0 / wheel.mass)
	var duration := 0.2 if supported else 0.1
	var ticks := roundi(hz * duration)
	var contact_ticks := 0
	var initial_frame := Engine.get_physics_frames()
	for _i: int in range(ticks):
		var rate: float = (wheel.linear_velocity - carrier.linear_velocity).y
		# In this vertical compression-only bench gravity and the downward
		# damper force keep the observed native cylinder support positive.
		var support := wheel.mass * 9.81 if supported and wheel.get_contact_count() > 0 else 0.0
		var wheel_mobility := 1.0 / wheel.mass
		if corrected:
			wheel_mobility = Suspension.contact_axis_mobility(wheel.mass,
				wheel.get_inverse_inertia_tensor(), Vector3(0.0, -0.348, 0.0),
				Vector3.UP, Vector3.UP, support)
		var effective_mass := 1.0 / (1.0 / carrier.mass + wheel_mobility)
		var output: Dictionary = Suspension.step_articulated(Suspension.new_state(),
			0.1, rate, 1.0 / hz, settings, effective_mass)
		var force := Vector3.UP * float(output.force)
		carrier.apply_central_force(force)
		wheel.apply_central_force(-force)
		contact_ticks += int(wheel.get_contact_count() > 0)
		await _tick()
	var final_rate: float = (wheel.linear_velocity - carrier.linear_velocity).y
	var exact_ratio := exp(-coefficient * duration / (carrier.mass if supported else free_mass))
	var result := {"hz": hz, "supported": supported, "corrected": corrected,
		"initialRate": initial_rate, "endRate": final_rate, "ratio": final_rate / initial_rate,
		"expectedRatio": exact_ratio, "contactFrames": contact_ticks, "ticks": ticks,
		"nativeFrames": Engine.get_physics_frames() - initial_frame}
	reports.append(result)
	print("DAMPER_NATIVE ", JSON.stringify(result))
	world.queue_free()
	await _tick()
	return result

func _material_checks() -> void:
	var free_mobility := 1.0 / 5.0
	var inverse_inertia := Basis.IDENTITY
	_check(absf(Suspension.contact_axis_mobility(5.0, inverse_inertia,
		Vector3(0.0, -0.35, 0.0), Vector3.UP, Vector3.UP, 0.0) - free_mobility) < 0.000001,
		"Zero solved support retains free-axle mobility")
	_check(Suspension.contact_axis_mobility(5.0, inverse_inertia,
		Vector3(0.0, -0.35, 0.0), Vector3.UP, Vector3.UP, 50.0) < 0.000001,
		"Radial ground constraint removes normal wheel translation")
	_check(absf(Suspension.contact_axis_mobility(5.0, inverse_inertia,
		Vector3(0.0, -0.35, 0.0), Vector3.RIGHT, Vector3.UP, 50.0) - free_mobility) < 0.000001,
		"Normal constraint leaves tangential axle mobility unchanged")
	var lever := Vector3(0.1, -0.35, 0.2)
	var axis := Vector3(0.2, 0.95, 0.1).normalized()
	var mobility := Suspension.contact_axis_mobility(5.0, inverse_inertia, lever, axis, Vector3.UP, 50.0)
	_check(mobility > 0.0 and mobility < free_mobility,
		"Off-centre contact retains the wheel's available rotational compliance")
	var rotation := Basis.from_euler(Vector3(0.3, -0.2, 0.5))
	var rotated := Suspension.contact_axis_mobility(5.0,
		rotation * inverse_inertia * rotation.inverse(), rotation * lever,
		rotation * axis, rotation * Vector3.UP, 50.0)
	_check(absf(rotated - mobility) < 0.000001, "Contact-axis mobility is independent of world orientation")
	_check(Suspension.retains_normal_support(249.05, Vector3(0.0, -200.0, 0.0),
		Vector3(0.0, 150.0, 0.0), Vector3.UP), "Compression retains a real unilateral support row")
	_check(not Suspension.retains_normal_support(249.05, Vector3(0.0, -200.0, 0.0),
		Vector3(0.0, -60.0, 0.0), Vector3.UP), "Rebound requiring tensile ground support releases the constraint")
	_check(not Suspension.retains_normal_support(0.0, Vector3.ZERO,
		Vector3(0.0, 150.0, 0.0), Vector3.UP), "Geometric contact without positive support cannot constrain the damper")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="):
			hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	_material_checks()
	for supported: bool in [false, true]:
		var stock: Dictionary = await _decay_case(supported, false)
		var corrected: Dictionary = await _decay_case(supported, true)
		_check(int(corrected.nativeFrames) == int(corrected.ticks),
			"Measured native frame count matches elapsed damper integration time")
		_check(float(corrected.ratio) >= 0.0 and float(corrected.ratio) < 1.0,
			"Native hydraulic step dissipates relative motion without reversing it")
		var tolerance := 0.08 if supported else 0.15
		if hz >= 480:
			tolerance *= 0.5
		var relative_error := absf(float(corrected.ratio) - float(corrected.expectedRatio)) / float(corrected.expectedRatio)
		_check(relative_error < tolerance,
			"%dHz %s native decay agrees with physical damper time constant (error %.4f)" %
			[hz, "supported" if supported else "free", relative_error])
		if supported:
			_check(int(corrected.contactFrames) == int(corrected.ticks),
				"Ground-normal constraint is supported throughout native compression")
			_check(absf(float(corrected.ratio) - float(corrected.expectedRatio)) <
				absf(float(stock.ratio) - float(stock.expectedRatio)) * 0.2,
				"Derived constrained mobility corrects the former planted-wheel underdamping")
		else:
			_check(absf(float(corrected.endRate) - float(stock.endRate)) < 0.0000001,
				"Unsupported native damper response is unchanged")
	var report := FileAccess.open("res://build/contact-damper-native-%d-%d.json" %
		[hz, OS.get_process_id()], FileAccess.WRITE)
	report.store_string(JSON.stringify(reports, "\t"))
	print("Native contact damper: %d checks, %d failures (%dHz)" % [checks, failures.size(), hz])
	quit(0 if failures.is_empty() else 1)
