extends SceneTree
## Rolling contact must cross soil/material boundaries without encountering a
## collision edge. Stationary ray/contact checks cannot expose this failure.
const Bike = preload("res://scripts/bike_controller.gd")
const Wheel = preload("res://scripts/wheel_body.gd")
const Track = preload("res://scripts/track_builder.gd")
var hz := 240
var cfg: Dictionary
var world: Node3D
var bike: Node3D
var checks := 0
var failures: Array[String] = []
var reports: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func tick() -> void:
	await physics_frame

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("TERRAIN CONTACT FAIL: " + label)

func clear_world() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await process_frame
	world = Node3D.new()
	root.add_child(world)

func make_bike(pose: Transform3D, speed: float) -> void:
	bike = Bike.new()
	bike.configure(cfg.duplicate(true))
	world.add_child(bike)
	bike.reset_bike(pose)
	bike.set_controls({"clutch": 1.0, "footDown": true})
	for i in range(hz * 2):
		await tick()
	var velocity := -pose.basis.z * speed
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		body.linear_velocity = velocity
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
	bike.front_wheel.angular_velocity = -bike.front_wheel.global_basis.x * speed / float(cfg.FrontRadius)
	bike.rear_wheel.angular_velocity = -bike.rear_wheel.global_basis.x * speed / float(cfg.RearRadius)
	bike.front_wheel.invalidate_load_history()
	bike.rear_wheel.invalidate_load_history()
	bike.set_controls({"clutch": 1.0, "footDown": false})

func lane() -> void:
	var ground := StaticBody3D.new()
	ground.set_meta("physics_surface", "dirt")
	ground.set_meta("physics_surface_resolver", func(point: Vector3) -> String:
		return "loam" if posmod(int(floor(point.z / 10.0)), 2) == 0 else "dirt")
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	ground.physics_material_override = material
	var faces := PackedVector3Array()
	for x in range(-25, 25):
		for z in range(-80, 20):
			var a := Vector3(float(x), 0.0, float(z))
			var b := a + Vector3.RIGHT
			var c := a + Vector3.BACK
			var d := a + Vector3.RIGHT + Vector3.BACK
			faces.append_array(PackedVector3Array([a, b, c, b, d, c]))
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision.shape = shape
	ground.add_child(collision)
	world.add_child(ground)

func observe(label: String, duration: float, reverse := false) -> Dictionary:
	var min_load := [INF, INF]
	var peak_load := [0.0, 0.0]
	var missing := [0, 0]
	var zero_load := [0, 0]
	var seam_samples := [0, 0]
	var seam_unloaded := [0, 0]
	var seam_unloaded_run := [0, 0]
	var max_seam_unloaded_run := [0, 0]
	var surfaces := [{}, {}]
	var force_jump := [0.0, 0.0]
	var previous_force := [Vector2.ZERO, Vector2.ZERO]
	var frames := 0
	for i in range(roundi(duration * hz)):
		var time := float(i) / hz
		var request := 0.0
		if reverse:
			request = 0.45 * smoothstep(0.25, 0.5, time) * (1.0 - 2.0 * smoothstep(1.65, 1.85, time))
			request *= 1.0 - smoothstep(2.9, 3.2, time)
		bike.set_controls({"clutch": 1.0, "footDown": false, "steer": request})
		await tick()
		frames += 1
		# The first prescribed rolling sample invalidates native momentum history.
		# Measure once that explicit fixture initialization has cleared.
		if i >= roundi(0.1 * hz):
			for axle in range(2):
				var wheel: RigidBody3D = bike.front_wheel if axle == 0 else bike.rear_wheel
				var result: Dictionary = bike._front_result if axle == 0 else bike._rear_result
				missing[axle] += int(not wheel.contact)
				zero_load[axle] += int(wheel.contact and wheel.normal_load <= 0.0)
				var seam_distance := absf(wrapf(wheel.global_position.z, -5.0, 5.0)) if reverse else absf(wheel.global_position.z + 24.5)
				if seam_distance < 0.75:
					seam_samples[axle] += 1
					var unloaded: bool = not wheel.contact or wheel.normal_load <= 0.0
					seam_unloaded[axle] += int(unloaded)
					seam_unloaded_run[axle] = seam_unloaded_run[axle] + 1 if unloaded else 0
					max_seam_unloaded_run[axle] = maxi(max_seam_unloaded_run[axle], seam_unloaded_run[axle])
				else:
					seam_unloaded_run[axle] = 0
				min_load[axle] = minf(min_load[axle], wheel.normal_load)
				peak_load[axle] = maxf(peak_load[axle], wheel.normal_load)
				surfaces[axle][wheel.surface] = true
				var force := Vector2(float(result.longitudinalForce), float(result.lateralForce))
				force_jump[axle] = maxf(force_jump[axle], force.distance_to(previous_force[axle]))
				previous_force[axle] = force
		if bike.crashed:
			break
	var result := {"label": label, "physicsHz": hz, "frames": frames, "crash": bike.crashed,
		"minLoad": min_load, "peakLoad": peak_load, "unsupportedTicks": missing,
		"zeroLoadContactTicks": zero_load, "maxTangentForceDelta": force_jump,
		"materialBoundarySamples": seam_samples, "unloadedAtMaterialBoundary": seam_unloaded,
		"maxUnloadedBoundarySteps": max_seam_unloaded_run,
		"surfaces": [surfaces[0].keys(), surfaces[1].keys()]}
	reports.append(result)
	print("TERRAIN ROLLING ", JSON.stringify(result))
	check(frames == roundi(duration * hz) and not bike.crashed, label + " completes the native rolling ride")
	for axle in range(2):
		# Jolt can retain a speculative contact during a submillimetre wheel
		# hop. One solved zero-impulse step is legitimate; inventing a load would
		# conceal it. Protect against sustained seam unloading and impact spikes.
		check(seam_samples[axle] > hz / 20 and missing[axle] == 0 and max_seam_unloaded_run[axle] <= 1,
			label + " axle%d crosses materials without sustained grip dropout" % axle)
		check(peak_load[axle] < 2800.0, label + " axle%d has no spurious multi-kilonewton flat-ground edge impact" % axle)
		check(force_jump[axle] < 1200.0, label + " axle%d avoids the discontinuous seam traction impulse" % axle)
		check(surfaces[axle].has("dirt") and surfaces[axle].has("loam"), label + " axle%d resolves different soil grip on the same collision mesh" % axle)
	return result

func surface_identity() -> void:
	var road := world.find_child("Circuit_Collision", true, false)
	check(road is StaticBody3D, "Shipped road uses one continuous native collider")
	var collision_count := 0
	for child in road.get_children():
		collision_count += int(child is CollisionShape3D)
	check(collision_count == 1, "Material changes do not create independent native road shapes")
	for sample in [{"point": Vector3(-34, 0.04, 0), "surface": "dirt"},
		{"point": Vector3(6, 0.04, -72), "surface": "sand"},
		{"point": Vector3(46, 0.04, -31), "surface": "loam"},
		{"point": Vector3(15, 0.04, 310), "surface": "mud"},
		{"point": Vector3(-5, 0.04, 310), "surface": "hardpack"}]:
		check(Wheel.surface_at(road, sample.point) == sample.surface, "Continuous road preserves " + str(sample.surface) + " contact material")
	var original_pose: Transform3D = road.global_transform
	road.global_transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(110, 3, -70))
	check(Wheel.surface_at(road, road.to_global(Vector3(46, 0.04, -31))) == "loam",
		"Translated and rotated tracks resolve native world contacts in road coordinates")
	road.global_transform = original_pose
	var ordinary := StaticBody3D.new()
	ordinary.set_meta("physics_surface", "SAND")
	check(Wheel.surface_at(ordinary, Vector3.ZERO) == "sand", "Ordinary collider material metadata remains compatible")
	ordinary.set_meta("physics_surface_resolver", "invalid")
	check(Wheel.surface_at(ordinary, Vector3.ZERO) == "sand", "Invalid optional surface resolver keeps the ordinary material")
	ordinary.set_meta("physics_surface_resolver", func(_point: Vector3): return 7)
	check(Wheel.surface_at(ordinary, Vector3.ZERO) == "sand", "Invalid resolver return cannot corrupt tire surface identity")
	ordinary.free()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--hz="):
			hz = int(argument.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	await clear_world()
	lane()
	await make_bike(Transform3D(Basis.IDENTITY, Vector3(0, 0.82, 5)), 12.0)
	await observe("continuous flat mixed-soil reversal", 4.0, true)
	await clear_world()
	Track.build(world)
	await tick()
	surface_identity()
	await make_bike(Transform3D(Basis(Vector3.UP, PI), Vector3(46, 0.86, -34)), 12.0)
	await observe("shipped loam/dirt seam", 1.45)
	var output := FileAccess.open("res://build/terrain-contact-report-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	output.store_string(JSON.stringify({"physicsHz": hz, "checks": checks, "failures": failures, "results": reports,
		"controllerHash": FileAccess.get_file_as_string("res://scripts/bike_controller.gd").sha256_text(),
		"wheelHash": FileAccess.get_file_as_string("res://scripts/wheel_body.gd").sha256_text(),
		"trackHash": String((Track as GDScript).source_code).sha256_text(),
		"configHash": FileAccess.get_file_as_string("res://config/bike_250f.json").sha256_text()}, "\t"))
	print("Terrain rolling contact: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
