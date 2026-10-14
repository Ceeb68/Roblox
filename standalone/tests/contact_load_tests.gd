extends SceneTree
## Jolt response estimates are emitted per triangle manifold. These tests
## compare actual bike support on a box, triangulated floor and material seam,
## including a bank. No body is frozen or held at an assigned orientation.
const Bike = preload("res://scripts/bike_controller.gd")
const Wheel = preload("res://scripts/wheel_body.gd")
const HZ := 240.0
var world: Node3D
var bike: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("CONTACT LOAD FAIL: " + message)

func _tick() -> void:
	await physics_frame
	await process_frame

func _sample(x: float, impulse: float, collider: int = 1, normal: Vector3 = Vector3.UP,
		velocity: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"position": Vector3(x, 0, 0), "normal": normal, "normalImpulse": impulse,
		"collider": collider, "shape": 0, "static": true, "velocity": velocity,
		"surface": "hardpack"}

func _pure_checks() -> void:
	var ordinary: Array[Dictionary] = [_sample(-0.04, 2.0), _sample(0.04, 0.8)]
	var result: Dictionary = Wheel.reduce_contact_samples(ordinary, 1.0 / HZ)
	_check(absf(float(result.normalLoad) - 2.8 * HZ) < 0.00001, "One manifold retains its complete distributed response estimate")
	_check(result.manifolds == 1 and result.patches == 1, "Two distinct support points remain one response group")
	_check((result.position as Vector3).length() < 0.00001, "Patch geometry is independent of approximate impulse point weighting")
	var seam: Array[Dictionary] = [_sample(-0.04, 1.5), _sample(0, 1.3), _sample(0, 0.4), _sample(0.04, 2.4)]
	result = Wheel.reduce_contact_samples(seam, 1.0 / HZ)
	_check(result.manifolds == 2 and result.patches == 1, "Repeated shared triangle edge reconstructs two coplanar responses")
	_check(absf(float(result.normalLoad) - 2.8 * HZ) < 0.00001, "Coplanar triangle responses average instead of doubling traction budget")
	_check((result.position as Vector3).length() < 0.00001, "Shared seam point is counted once in geometric contact centroid")
	var material_seam: Array[Dictionary] = [_sample(-0.04, 1.5, 1), _sample(0, 1.3, 1), _sample(0, 0.4, 2), _sample(0.04, 2.4, 2)]
	result = Wheel.reduce_contact_samples(material_seam, 1.0 / HZ)
	_check(result.manifolds == 2 and result.patches == 1, "Adjacent coplanar static bodies form one supporting patch")
	_check(absf(float(result.normalLoad) - 2.8 * HZ) < 0.00001, "Changing material collider does not double available grip")
	# Jolt can flush triangle manifolds in any body/hash order, with either
	# supporting-edge orientation. Every permutation must infer the same load.
	var chain: Array = [[_sample(-0.06, 1.5), _sample(-0.02, 1.3)],
		[_sample(-0.02, 0.4), _sample(0.02, 2.4)],
		[_sample(0.02, 1.9), _sample(0.06, 0.9)]]
	for order: Array in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
		for directions: int in range(8):
			var ordered: Array[Dictionary] = []
			for index: int in range(3):
				var pair: Array = chain[order[index]]
				var reverse: bool = (directions & (1 << index)) != 0
				ordered.append(pair[1 if reverse else 0])
				ordered.append(pair[0 if reverse else 1])
			result = Wheel.reduce_contact_samples(ordered, 1.0 / HZ)
			_check(result.manifolds == 3 and result.patches == 1, "Coplanar chain response count is independent of manifold and edge order")
			_check(absf(float(result.normalLoad) - 2.8 * HZ) < 0.00001, "Coplanar chain normal budget is independent of manifold ordering")
			_check((result.position as Vector3).length() < 0.00001, "Unique geometric contact centre is independent of manifold ordering")
	var overlapping: Array[Dictionary] = [_sample(-0.04, 1.5), _sample(0.04, 1.3), _sample(0.04, 0.4), _sample(-0.04, 2.4)]
	result = Wheel.reduce_contact_samples(overlapping, 1.0 / HZ)
	_check(result.manifolds == 2 and absf(float(result.normalLoad) - 2.8 * HZ) < 0.00001, "Two responses sharing both endpoints do not invent a third support group")
	var moving_support: Array[Dictionary] = [_sample(-0.04, 2.8, 1), _sample(0.04, 2.8, 2, Vector3.UP, Vector3.RIGHT)]
	result = Wheel.reduce_contact_samples(moving_support, 1.0 / HZ)
	_check(result.patches == 2 and absf(float(result.normalLoad) - 5.6 * HZ) < 0.00001, "Independent supports with different velocities are kept separate")
	var corner: Array[Dictionary] = [_sample(-0.04, 2.8), _sample(0.04, 2.8, 1, Vector3.RIGHT)]
	result = Wheel.reduce_contact_samples(corner, 1.0 / HZ)
	_check(result.patches == 2 and absf(float(result.normalLoad) - 5.6 * HZ) < 0.00001, "A distinct wall or rut normal retains its own contact response")
	var unloaded: Array[Dictionary] = [_sample(-0.04, 0.0), _sample(0.04, 0.0)]
	result = Wheel.reduce_contact_samples(unloaded, 1.0 / HZ)
	_check(result.normalLoad == 0.0 and result.patches == 1, "Geometry without a response estimate cannot fabricate tire support")
	_check((result.normal as Vector3).is_equal_approx(Vector3.UP), "Unloaded contact still retains the native support normal")
	var empty: Array[Dictionary] = []
	result = Wheel.reduce_contact_samples(empty, 1.0 / HZ)
	_check(result.normalLoad == 0.0 and result.patches == 0 and (result.position as Vector3).is_finite(), "Empty contact estimate stays finite and unsupported")

func _floor_material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	return material

func _mesh_floor(start_x: float, finish_x: float, basis: Basis, surface: String) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.basis = basis
	floor_body.set_meta("physics_surface", surface)
	floor_body.physics_material_override = _floor_material()
	var faces := PackedVector3Array()
	var columns := roundi((finish_x - start_x) / 0.25)
	for column: int in range(columns):
		var x0 := start_x + float(column) * 0.25
		var x1 := x0 + 0.25
		for row: int in range(16):
			var z0 := -8.0 + float(row)
			var z1 := z0 + 1.0
			var a := Vector3(x0, 0, z0)
			var b := Vector3(x1, 0, z0)
			var c := Vector3(x0, 0, z1)
			var d := Vector3(x1, 0, z1)
			# Godot/Jolt triangle front faces use clockwise winding.
			faces.append_array(PackedVector3Array([a, b, c, b, d, c]))
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision.shape = shape
	floor_body.add_child(collision)
	world.add_child(floor_body)

func _native_case(kind: String, bank: float = 0.0, solved_load: bool = false) -> Dictionary:
	if is_instance_valid(world):
		world.queue_free()
		await _tick()
	world = Node3D.new()
	root.add_child(world)
	var basis := Basis(Vector3.BACK, bank)
	if kind == "box":
		var floor_body := StaticBody3D.new()
		floor_body.transform = Transform3D(basis, basis * Vector3(0, -0.15, 0))
		floor_body.set_meta("physics_surface", "hardpack")
		floor_body.physics_material_override = _floor_material()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(8, 0.3, 16)
		collision.shape = shape
		floor_body.add_child(collision)
		world.add_child(floor_body)
	elif kind == "seam":
		_mesh_floor(-4.0, 0.0, basis, "hardpack")
		_mesh_floor(0.0, 4.0, basis, "dirt")
	else:
		_mesh_floor(-4.0, 4.0, basis, "hardpack")
	bike = Bike.new()
	world.add_child(bike)
	bike.reset_bike(Transform3D(basis, basis * Vector3(0, 0.90, 0)))
	var end_stop_observations := 0
	var end_stop_fallback_valid := true
	for _i: int in range(480):
		await _tick()
		for wheel: Wheel in [bike.front_wheel, bike.rear_wheel]:
			if wheel.load_method == "mechanical_end_stop":
				end_stop_observations += 1
				end_stop_fallback_valid = end_stop_fallback_valid and is_equal_approx(wheel.normal_load, wheel.previous_contact_estimate) and wheel.momentum_load_raw == 0.0
	bike.set_controls({"footDown": false})
	var front_sum := 0.0
	var rear_sum := 0.0
	var raw_front_sum := 0.0
	var raw_rear_sum := 0.0
	var front_contact_ticks := 0
	var rear_contact_ticks := 0
	var max_contact_count := 0
	var max_manifolds := 0
	var normal_error := 0.0
	var com_displacement := 0.0
	var samples := 0
	for i: int in range(120):
		await _tick()
		if i >= 60:
			front_sum += float(bike.front_wheel.normal_load if solved_load else bike.front_wheel.previous_contact_estimate)
			rear_sum += float(bike.rear_wheel.normal_load if solved_load else bike.rear_wheel.previous_contact_estimate)
			raw_front_sum += float(bike.front_wheel.reported_normal_load)
			raw_rear_sum += float(bike.rear_wheel.reported_normal_load)
			front_contact_ticks += int(bike.front_wheel.contact)
			rear_contact_ticks += int(bike.rear_wheel.contact)
			max_contact_count = maxi(max_contact_count, bike.front_wheel.native_contact_count)
			max_manifolds = maxi(max_manifolds, bike.front_wheel.estimated_manifold_count)
			normal_error = maxf(normal_error, acos(clampf(bike.front_wheel.contact_normal.dot(basis.y), -1, 1)))
			samples += 1
		com_displacement = maxf(com_displacement, absf(bike.chassis.global_position.dot(basis.x)))
	var result := {"kind": kind, "bank": rad_to_deg(bank),
		"front": front_sum / samples, "rear": rear_sum / samples,
		"rawFront": raw_front_sum / samples, "rawRear": raw_rear_sum / samples,
		"frontContactTicks": front_contact_ticks, "rearContactTicks": rear_contact_ticks,
		"maxContacts": max_contact_count, "maxManifolds": max_manifolds,
		"normalError": normal_error, "lateralDisplacement": com_displacement,
		"crashed": bike.crashed, "solvedLoad": solved_load,
		"frontMethods": bike.front_wheel.method_counts.duplicate(),
		"rearMethods": bike.rear_wheel.method_counts.duplicate()}
	print("CONTACT native: ", JSON.stringify(result))
	_check(front_contact_ticks >= 55 and rear_contact_ticks >= 55, "%s bank %.0f has native support on both tires" % [kind, rad_to_deg(bank)])
	_check(float(result.front) > 100.0 and float(result.rear) > 100.0, "%s bank %.0f preserves loaded brush contacts" % [kind, rad_to_deg(bank)])
	_check(normal_error < deg_to_rad(2.0), "%s bank %.0f retains terrain normal instead of world up" % [kind, rad_to_deg(bank)])
	_check(not bike.crashed and bike.chassis.global_position.is_finite(), "%s bank %.0f remains a free native supported body during measurement" % [kind, rad_to_deg(bank)])
	if solved_load:
		_check(end_stop_observations > 0, "%s native landing reaches a slider end-stop load-observation guard" % kind)
		_check(end_stop_fallback_valid, "%s native end-stop guard retains the explicit geometry estimate and rejects free-axis inference" % kind)
	if not is_zero_approx(bank):
		_check(com_displacement > 0.01, "%s banked fixture permits actual downhill motion under gravity" % kind)
	return result

func _compare(box: Dictionary, mesh: Dictionary, label: String) -> void:
	_check(absf(float(mesh.front) / float(box.front) - 1.0) < 0.15, "%s front grip estimate stays consistent with equivalent box support" % label)
	_check(absf(float(mesh.rear) / float(box.rear) - 1.0) < 0.15, "%s rear grip estimate stays consistent with equivalent box support" % label)

## These checks observe real native callbacks and the already-applied forces.
## They never pin a body, replace a velocity or add support to a wheel.
func _momentum_sampling_guards() -> void:
	for wheel: Wheel in [bike.front_wheel, bike.rear_wheel]:
		_check(int(wheel.method_counts.get("free_axis_momentum", 0)) > 240,
			"Banked wheel uses completed native momentum over sustained supported steps")
		_check(int(wheel.method_counts.get("force_phase_mismatch", 0)) == 0,
			"Wheel force ledger matches the immediately preceding native step")
		var pose := wheel.global_transform
		var velocity := wheel.linear_velocity
		var omega := wheel.angular_velocity
		var load := wheel.normal_load
		wheel.invalidate_load_history()
		_check(not wheel.velocity_sample_valid and wheel.callback_stamp == -1,
			"Explicit initial-condition invalidation rejects stale velocity history")
		_check(wheel.global_transform.is_equal_approx(pose) and wheel.linear_velocity == velocity and wheel.angular_velocity == omega and wheel.normal_load == load,
			"Invalidating a load observation applies no motion or supporting load")
	await _tick()
	for wheel: Wheel in [bike.front_wheel, bike.rear_wheel]:
		_check(wheel.load_method == "first_velocity_sample",
			"First native callback after invalidation uses the documented contact fallback")
	await _tick()
	for wheel: Wheel in [bike.front_wheel, bike.rear_wheel]:
		_check(wheel.load_method == "free_axis_momentum",
			"Following consecutive callback resumes force-subtracted momentum observation")
	# Miss real applied-force samples for two native steps. The body continues
	# moving under the native solver; an obsolete ledger must never be inferred
	# as a current tire reaction. Resume ordinary force application afterward.
	bike.set_physics_process(false)
	await _tick()
	await _tick()
	for wheel: Wheel in [bike.front_wheel, bike.rear_wheel]:
		_check(wheel.load_method == "force_phase_mismatch" and is_equal_approx(wheel.normal_load, wheel.previous_contact_estimate),
			"Missing force sample selects the contact fallback instead of mixing different steps")
	bike.set_physics_process(true)
	await _tick()
	await _tick()
	for wheel: Wheel in [bike.front_wheel, bike.rear_wheel]:
		_check(wheel.load_method == "free_axis_momentum",
			"Consecutive native force samples restore the ordinary momentum observation")
	# A whole-bike reset exercises the real queue/commit path, then unsupported
	# flight must erase the preceding supported load without a fictitious normal.
	bike.reset_bike(Transform3D(Basis.IDENTITY, Vector3(0, 4, 0)))
	for wheel: Wheel in [bike.front_wheel, bike.rear_wheel]:
		_check(not wheel.contact and wheel.normal_load == 0.0 and not wheel.velocity_sample_valid,
			"Queued recovery clears old support and velocity history immediately")
		_check(wheel.known_suspension_force == Vector3.ZERO and wheel.known_tire_force == Vector3.ZERO and wheel.force_stamp == -1,
			"Queued recovery rejects all old applied wheel force samples")
	for _i: int in range(4):
		await _tick()
	for wheel: Wheel in [bike.front_wheel, bike.rear_wheel]:
		_check(not wheel.contact and wheel.normal_load == 0.0 and wheel.load_method == "unsupported",
			"Native unsupported flight cannot retain or invent tire support after recovery")
		_check(int(wheel.method_counts.get("reset", 0)) == 1,
			"Queued native reset commits once before observing later free motion")

func _native_momentum() -> Vector3:
	var momentum := Vector3.ZERO
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		momentum += body.linear_velocity * body.mass
	return momentum

func _settled_weight_guard() -> void:
	await _native_case("box", 0.0, true)
	# Let physical feet hold a stopped rider while vertical modes settle.
	# Then raise them before every weight observation; no body is frozen.
	bike.set_controls({"footDown": true})
	for _i: int in range(1920):
		await _tick()
	bike.set_controls({"footDown": false})
	for _i: int in range(360):
		await _tick()
	var total_mass := 0.0
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		total_mass += body.mass
	var expected_weight := total_mass * 9.81
	var initial_momentum := _native_momentum()
	var sum_load := 0.0
	var support_ticks := 0
	for _i: int in range(120):
		await _tick()
		sum_load += bike.front_wheel.normal_load + bike.rear_wheel.normal_load
		support_ticks += int(bike.front_wheel.contact and bike.rear_wheel.contact)
	var measured_weight := sum_load / 120.0
	var momentum_support := expected_weight + (_native_momentum() - initial_momentum).y / (120.0 / HZ)
	print("CONTACT settled momentum support %.3f N versus five-body weight %.3f N" % [measured_weight, expected_weight])
	_check(absf(measured_weight / momentum_support - 1.0) < 0.01,
		"Observed normal support matches weight plus actual five-body vertical momentum change")
	_check(support_ticks == 120, "Settled weight comparison uses two genuine continuous native tire contacts")
	_check(absf(measured_weight / expected_weight - 1.0) < 0.01,
		"Completed native momentum estimates account for five-body static weight within one percent")
	_check(bike.chassis.linear_velocity.length() < 0.1,
		"Weight consistency is measured after actual free native settling")
	for wheel: Wheel in [bike.front_wheel, bike.rear_wheel]:
		_check(int(wheel.method_counts.get("force_phase_mismatch", 0)) == 0,
			"Sustained settled sampling never mixes force and velocity steps")

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	_pure_checks()
	var box := await _native_case("box")
	var mesh := await _native_case("mesh")
	var seam := await _native_case("seam")
	_compare(box, mesh, "Triangulated floor")
	_compare(box, seam, "Material seam")
	_check(float(mesh.rawFront) > float(mesh.front) * 1.7 and int(mesh.maxContacts) >= 4, "Native flat mesh actually exercises duplicated response estimates")
	_check(float(seam.rawFront) > float(seam.front) * 1.7 and int(seam.maxManifolds) >= 2, "Native material seam exercises independent collider response groups")
	var bank_box := await _native_case("box", deg_to_rad(12.0))
	var bank_mesh := await _native_case("mesh", deg_to_rad(12.0))
	_compare(bank_box, bank_mesh, "Banked triangulated floor")
	# Retain all original manifold/geometry guards above. Validate the solved
	# load budget on the same native box, mesh, material seam and bank below.
	var solved_box := await _native_case("box", 0.0, true)
	var solved_mesh := await _native_case("mesh", 0.0, true)
	var solved_seam := await _native_case("seam", 0.0, true)
	_compare(solved_box, solved_mesh, "Solved-momentum triangulated floor")
	_compare(solved_box, solved_seam, "Solved-momentum material seam")
	var solved_bank_box := await _native_case("box", deg_to_rad(12.0), true)
	var solved_bank_mesh := await _native_case("mesh", deg_to_rad(12.0), true)
	_compare(solved_bank_box, solved_bank_mesh, "Solved-momentum banked triangulated floor")
	await _momentum_sampling_guards()
	await _settled_weight_guard()
	print("Contact load native checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
