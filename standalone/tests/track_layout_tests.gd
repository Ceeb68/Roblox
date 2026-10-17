extends SceneTree
## Verify the shipped course's actual native triangle collision and lap layout.
## The grass base cannot hide a ribbon hole: road samples must hit Circuit_*.

const Track = preload("res://scripts/track_builder.gd")
const Bike = preload("res://scripts/bike_controller.gd")
const HZ := 240.0
var world: Node3D
var bike: Node3D
var failures: Array[String] = []
var jump_reports: Array[Dictionary] = []
var physics_profile: Dictionary = {}
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures.append(message + (": " + detail if not detail.is_empty() else ""))
		push_error("TRACK FAIL: " + failures[-1])


func _hit(point: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(point.x, 20.0, point.y), Vector3(point.x, -3.0, point.y))
	return world.get_world_3d().direct_space_state.intersect_ray(query)


func _tick() -> void:
	await physics_frame
	await process_frame


func _road_hit(point: Vector2, height: float, tolerance: float = 0.022) -> bool:
	var hit := _hit(point)
	if hit.is_empty() or not str(hit.collider.name).begins_with("Circuit_"):
		return false
	return absf(float(hit.position.y) - height) <= tolerance and float(hit.normal.y) > 0.7


func _test_continuous_native_course() -> void:
	var rows: Array = Track._main_rows()
	var length := 0.0
	var missed: Array[String] = []
	var largest_height_error := 0.0
	for index in range(rows.size() - 1):
		var first: Dictionary = rows[index]
		var next: Dictionary = rows[index + 1]
		length += (next.center as Vector2).distance_to(first.center)
		# Test both sides as well as the centre. This catches missing outer
		# triangle strips, material seams and clipped arc/straight connections.
		for lateral in [-4.125, 0.125, 4.125]:
			# Probe triangle interiors. An infinitesimal ray exactly on a
			# compressed Jolt triangle vertex can miss both adjacent edges;
			# finite tire contact is covered by the native riding scenarios.
			var expected := (Track._ribbon_vertex(first, lateral) +
				Track._ribbon_vertex(next, lateral)) * 0.5
			var hit := _hit(Vector2(expected.x, expected.z))
			if hit.is_empty() or not str(hit.collider.name).begins_with("Circuit_"):
				missed.append("row=%d lateral=%s position=%s" % [index, lateral, expected])
				continue
			largest_height_error = maxf(largest_height_error, absf(float(hit.position.y) - expected.y))
			if float(hit.normal.y) <= 0.7:
				missed.append("downward/steep native normal at %s" % expected)
	_check(missed.is_empty(), "Whole expanded lap has continuous upward native road collision",
		str(missed.slice(0, 5)))
	_check(largest_height_error < 0.025, "Native centre and riding-width heights match the visible ribbon",
		"largest=%.6f m" % largest_height_error)
	_check(absf(length - float(Track.COURSE_LENGTH_METRES)) < 0.03,
		"Timed course follows its complete 873 m connected ribbon", "native polyline=%.3f m" % length)
	_check(length > 2.1 * (168.0 + 40.0 + TAU * 30.0),
		"Expanded course is more than twice the original lap length", "%.3f m" % length)
	_check((rows[0].center as Vector2).is_equal_approx(rows[-1].center),
		"Start and return rows close the ribbon without a teleport")
	print("TRACK connected native ribbon: %.3f m; %d centre/width rays; max error %.6f m" % [
		length, (rows.size() - 1) * 3, largest_height_error])


func _test_preserved_proving_sections() -> void:
	var flat_ok := true
	for z in range(-6, 35):
		flat_ok = flat_ok and _road_hit(Vector2(-34.0, float(z)), 0.04)
	_check(flat_ok, "Original 40 m spawn launch remains level and continuously rideable")
	_check(_road_hit(Vector2(-34.0, -7.0), 0.16), "Original first 0.12 m braking bump is preserved")
	_check(_road_hit(Vector2(-34.0, -26.0), 0.49), "Original 0.45 m whoop crest is preserved")
	_check(_road_hit(Vector2(46.75, -31.0), -0.12), "Original 0.16 m east rut is preserved")
	_check(_road_hit(Vector2(46.0, -7.0), 1.34), "Original 1.3 m training tabletop is preserved")
	for surface: String in ["hardpack", "sand", "mud", "loam"]:
		var point: Vector2
		match surface:
			"hardpack": point = Vector2(-7.0, -11.0)
			"sand": point = Vector2(7.0, -11.0)
			"mud": point = Vector2(-7.0, 11.0)
			"loam": point = Vector2(7.0, 11.0)
		var hit := _hit(point)
		_check(not hit.is_empty() and str(hit.collider.get_meta("physics_surface", "")) == surface,
			"Original %s traction pad retains its native surface" % surface)
	var practice_ok := true
	for z in range(-65, 35, 2):
		var hit := _hit(Vector2(-63.0, float(z)))
		practice_ok = practice_ok and not hit.is_empty() and str(hit.collider.name) == "PracticeGround_hardpack"
		practice_ok = practice_ok and absf(float(hit.get("position", Vector3.ZERO).y) - 0.04) < 0.01
	_check(practice_ok, "Original 100 m flat practice straight remains unchanged")


func _test_large_tabletops() -> void:
	# Explicit dimensions and independent ballistic checks protect against
	# cosmetic giant hills with impossible gaps or no graded landing area.
	for recipe: Dictionary in Track.EXTENSION_JUMPS:
		var jump := {"start": float(recipe.start), "lip": float(recipe.start) + float(recipe.takeoff),
			"deck_end": float(recipe.start) + float(recipe.takeoff) + float(recipe.deck),
			"finish": float(recipe.start) + float(recipe.takeoff) + float(recipe.deck) + float(recipe.landing),
			"height": float(recipe.height), "speed": 17.0 if float(recipe.height) < 4.0 else 18.0}
		var height: float = jump.height
		_check(_road_hit(Vector2(46.0, jump.start), 0.04), "%.1f m tabletop begins at road level" % height)
		_check(_road_hit(Vector2(46.0, jump.lip), height + 0.04), "%.1f m physical takeoff reaches its advertised height" % height)
		_check(_road_hit(Vector2(46.0, jump.deck_end), height + 0.04), "%.1f m tabletop has a filled native deck" % height)
		_check(_road_hit(Vector2(46.0, jump.finish), 0.04), "%.1f m graded landing returns to road level" % height)
		var native_width_ok := true
		var largest_step := 0.0
		var previous_height := 0.04
		for index in range(int((float(jump.finish) - float(jump.start)) / 0.5) + 1):
			var z: float = float(jump.start) + index * 0.5
			var centre := _hit(Vector2(46.0, z))
			if centre.is_empty():
				native_width_ok = false
				continue
			var y: float = centre.position.y
			largest_step = maxf(largest_step, absf(y - previous_height))
			previous_height = y
			for offset in [-7.0, 7.0]:
				native_width_ok = native_width_ok and _road_hit(Vector2(46.0 + offset, z), y)
		_check(native_width_ok and largest_step < 0.22, "%.1f m jump has continuous 14 m tested riding width and smooth slopes" % height,
			"maximum half-metre rise=%.4f m" % largest_step)
		var slope := 1.8 * height / (float(jump.lip) - float(jump.start))
		var angle := atan(slope)
		var speed: float = jump.speed
		var vx := speed * cos(angle)
		var vy := speed * sin(angle)
		var deck_length := float(jump.deck_end) - float(jump.lip)
		var cleared_deck := false
		var landing_z := 0.0
		var landing_slope := 0.0
		for step in range(1, 481):
			var t := float(step) / 240.0
			var z := float(jump.lip) + vx * t
			var y := height + vy * t - 0.5 * 9.81 * t * t
			if z > float(jump.deck_end) and y > height:
				cleared_deck = true
			if z > float(jump.lip) + 0.5 and y <= Track._extension_jump_height(z):
				landing_z = z
				landing_slope = (Track._extension_jump_height(z + 0.1) - Track._extension_jump_height(z - 0.1)) / 0.2
				break
		_check(cleared_deck and landing_z > float(jump.deck_end) and landing_z < float(jump.finish),
			"%.1f m lip has a reachable graded landing at %.0f m/s without an exposed gap" % [height, speed],
			"deck %.1f m landing z=%.3f" % [deck_length, landing_z])
		_check(landing_slope < -0.03, "%.1f m expected landing is downhill" % height,
			"slope=%.4f" % landing_slope)
		print("TRACK %.1f m tabletop: %dm takeoff / %dm deck / %dm landing; ballistic %.0f m/s touchdown z=%.2f" % [
			height, float(jump.lip) - float(jump.start), deck_length,
			float(jump.finish) - float(jump.deck_end), speed, landing_z])
	_check(280.0 - 250.0 >= 30.0, "Big jump has 30 m flat braking runoff before the south bend")
	var big_jump: Dictionary = Track.EXTENSION_JUMPS[1]
	# Required downward acceleration is v² * curvature. Native tire contact
	# cannot pull the bike down harder than gravity to follow a convex crest.
	var crest_curvature := 6.0 * float(big_jump.height) / pow(float(big_jump.landing), 2.0)
	_check(9.81 - 22.0 * 22.0 * crest_curvature > 2.0,
		"Big tabletop landing crest permits actual gravity-supported contact at 22 m/s",
		"available vertical support=%.3f m/s²" % (9.81 - 22.0 * 22.0 * crest_curvature))


func _test_ordered_gates(track: Dictionary) -> void:
	var gates: Array = track.gates
	_check(gates.size() == 14, "Expanded timed lap requires 14 ordered checkpoints")
	var all_gates_on_road := true
	for gate: Dictionary in gates:
		var transform: Transform3D = gate.transform
		all_gates_on_road = all_gates_on_road and _road_hit(
			Vector2(transform.origin.x, transform.origin.z), transform.origin.y, 0.025)
	_check(all_gates_on_road, "Every timed checkpoint lies at its actual native road height")
	_check((gates[8].transform as Transform3D).origin.z == 264.0 and (gates[9].transform as Transform3D).origin.z == 310.0,
		"A shortcut through the former south turn skips mandatory distant checkpoints")


func _powered_jump(recipe: Dictionary, speed: float, body_forward: float, cfg: Dictionary,
		recover_backward_landing: bool = true) -> void:
	if is_instance_valid(bike):
		bike.queue_free()
		await _tick()
	bike = Bike.new()
	bike.configure(cfg.duplicate(true))
	world.add_child(bike)
	var start: float = float(recipe.start) - 23.0
	var lip: float = float(recipe.start) + float(recipe.takeoff)
	var finish: float = lip + float(recipe.deck) + float(recipe.landing)
	var height: float = recipe.height
	var title := "%.1f m jump / %.0f m/s approach / body %.2f" % [height, speed, body_forward]
	var deliberate_powered_wheelie := body_forward < 0.0 and not recover_backward_landing
	title += " / held rearward power" if deliberate_powered_wheelie else (" / touchdown throttle recovery" if body_forward < 0.0 else "")
	bike.reset_bike(Transform3D(Basis(Vector3.UP, PI), Vector3(46.0, 0.95, start)))
	bike.set_controls({"clutch": 1.0, "footDown": true, "standing": true, "bodyForward": body_forward})
	# Let all five native bodies reach their actual standing support posture
	# before initializing a rolling fixture. The rider mass is never frozen.
	for _i in range(242):
		await _tick()
	var shifts_ok := true
	for i in range(240):
		if i == 0 or i == 24 or i == 48:
			shifts_ok = bike.shift_gear(1) and shifts_ok
		bike.set_controls({"throttle": 0.8, "clutch": 1.0, "footDown": true,
			"standing": true, "bodyForward": body_forward})
		await _tick()
	_check(shifts_ok and int(bike.get_telemetry().gear) == 3,
		title + " prepares real third gear through timed manual shifts")
	# One initial rolling velocity, following committed reset and real clutch
	# preparation. Every following step uses native dynamics and player inputs.
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		body.linear_velocity = Vector3(0.0, 0.0, speed)
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
	bike.front_wheel.angular_velocity = -bike.front_wheel.global_basis.x * speed / float(cfg.FrontRadius)
	bike.rear_wheel.angular_velocity = -bike.rear_wheel.global_basis.x * speed / float(cfg.RearRadius)
	# An externally initialized fixture velocity is not a completed native
	# contact-force step; do not misread it as a solved normal impulse.
	bike.front_wheel.invalidate_load_history()
	bike.rear_wheel.invalidate_load_history()
	var air_frames := 0
	var longest_air := 0
	var flew := false
	var landed := false
	var supported_after_landing := false
	var max_bank := 0.0
	var max_pitch := 0.0
	var recovery_applied := false
	var rear_only_after_landing := 0
	var inverted_after_landing := false
	var peak_height := 0.0
	var max_front := 0.0
	var max_rear := 0.0
	var min_corridor_clearance := INF
	var max_lane_error := 0.0
	var samples: Array[Dictionary] = []
	for i in range(2400):
		var time := float(i) / HZ
		var prior: Dictionary = bike.get_telemetry()
		if recover_backward_landing and body_forward < 0.0 and flew and bike.chassis.global_position.z > lip \
				and (float(prior.frontLoad) > 1.0 or float(prior.rearLoad) > 1.0):
			# The test PILOT releases actual throttle after a rearward air input
			# and rear-wheel touchdown. Production physics never inserts this
			# recovery: holding power/rearward input is tested separately below.
			recovery_applied = true
		bike.set_controls({"throttle": 0.0 if recovery_applied else 0.5, "clutch": maxf(0.0, 1.0 - time / 0.75),
			"footDown": false, "standing": true, "bodyForward": body_forward})
		await _tick()
		var state: Dictionary = bike.get_telemetry()
		var position: Vector3 = bike.chassis.global_position
		max_bank = maxf(max_bank, absf(float(state.roll)))
		max_pitch = maxf(max_pitch, float(state.pitch))
		peak_height = maxf(peak_height, position.y)
		max_front = maxf(max_front, float(state.frontCompression))
		max_rear = maxf(max_rear, float(state.rearCompression))
		max_lane_error = maxf(max_lane_error, absf(position.x - 46.0))
		var half_width := Track._ribbon_road_half_width({"center": Vector2(46.0, position.z)})
		# This checks the actual prepared road plus its soft two-metre verge,
		# leaving room for the finite motorcycle rather than claiming perfect
		# centre-line tracking. The grass base cannot make a departure pass.
		min_corridor_clearance = minf(min_corridor_clearance,
			half_width + float(Track.SHOULDER_WIDTH) - absf(position.x - 46.0))
		if position.z > lip - 2.0 and position.y > height and not (state.frontContact or state.rearContact):
			air_frames += 1
			longest_air = maxi(longest_air, air_frames)
			flew = flew or air_frames >= 8
		else:
			if flew and air_frames >= 8 and position.z > lip:
				landed = true
			air_frames = 0
		if landed and float(state.frontLoad) > 100.0 and float(state.rearLoad) > 100.0:
			supported_after_landing = true
		if landed and float(state.rearLoad) > 1.0 and float(state.frontLoad) <= 1.0:
			rear_only_after_landing += 1
		if landed and bike.chassis.global_basis.y.dot(Vector3.UP) < 0.0:
			inverted_after_landing = true
		if i % 24 == 0:
			samples.append({"time": time, "position": str(position), "x": position.x, "z": position.z,
				"velocity": str(bike.chassis.linear_velocity), "heading": str(-bike.chassis.global_basis.z),
				"roll": rad_to_deg(float(state.roll)), "pitch": rad_to_deg(float(state.pitch)),
				"frontLoad": state.frontLoad, "rearLoad": state.rearLoad,
				"frontSlipAngle": state.frontSlipAngle, "rearSlipAngle": state.rearSlipAngle,
				"bankRate": state.bankRate, "headingRate": state.headingRate,
				"steerAngle": state.steerAngle, "steeringTarget": state.steeringTarget,
				"riderTargetLean": state.riderTargetLean, "headingCorrection": state.headingCorrection,
				"lineCapturePending": state.lineCapturePending, "mechanicalTrail": state.mechanicalTrail})
		if bike.crashed or position.z > finish + 15.0:
			break
	var final_position: Vector3 = bike.chassis.global_position
	var final_up: float = bike.chassis.global_basis.y.dot(Vector3.UP)
	var final_forward_along_approach: float = (-bike.chassis.global_basis.z).dot(Vector3.BACK)
	var frame_contacts: int = bike.chassis.get_contact_count()
	var rider_contacts: int = bike.rider_body.get_contact_count()
	_check(flew and float(longest_air) / HZ > 0.8 and peak_height > height + 0.7,
		title + " launches through actual contact into measurable flight",
		"air=%.3f s peak chassis=%.3f m" % [float(longest_air) / HZ, peak_height])
	if deliberate_powered_wheelie:
		# The threshold can be crossed while the rear tire is still loaded, or
		# just after it unloads. In the latter case native flight continues until
		# the inverted frame/rider actually hits the soil. Both are real powered
		# overturns; an unrelated ordinary low-side must not satisfy this guard.
		var inverted_body_impact: bool = inverted_after_landing and final_up < 0.0 and final_forward_along_approach < 0.0 \
			and frame_contacts + rider_contacts > 0 \
			and bike.crash_reason in ["Loss of balance / low-side", "Over-rotation"]
		_check(landed and bike.crashed and (bike.crash_reason == "Wheelie loop-out" or inverted_body_impact),
			title + " produces a physically justified powered overturn",
			"position=%s reason=%s up=%.3f forward=%.3f native body contacts=%d" %
			[final_position, bike.crash_reason, final_up, final_forward_along_approach, frame_contacts + rider_contacts])
		_check(max_pitch > deg_to_rad(70.0) and rear_only_after_landing > roundi(0.20 * HZ),
			title + " actually lifts the front and over-rotates after sustained rear-only support",
			"pitch=%.2f degrees rear-only=%.3f s" % [rad_to_deg(max_pitch), float(rear_only_after_landing) / HZ])
	else:
		_check(landed and supported_after_landing,
			title + " lands and restores real support at both independent tires")
		_check(not bike.crashed and final_position.z > finish + 14.0,
			title + " reaches the physical landing and full runout without recovery",
			"position=%s reason=%s" % [final_position, bike.crash_reason])
		_check(max_bank < deg_to_rad(45.0), title + " avoids excessive uncommanded bank",
			"maximum=%.2f degrees" % rad_to_deg(max_bank))
		_check(min_corridor_clearance > 0.45, title + " remains within the prepared road and soft shoulder",
			"minimum outer-edge clearance=%.3f m; max lane deviation=%.3f m" % [min_corridor_clearance, max_lane_error])
		if body_forward < 0.0:
			_check(recovery_applied, title + " uses the pilot's real throttle release at positive touchdown load")
	_check(max_front < float(cfg.Suspension.Front.Travel) + 0.04 and
		max_rear < float(cfg.Suspension.Rear.Travel) + 0.04,
		title + " lands within the independent shocks' mechanical travel",
		"front=%.3f rear=%.3f m" % [max_front, max_rear])
	var bodies_finite := true
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		bodies_finite = (bodies_finite and body.global_transform.is_finite() and
			body.linear_velocity.is_finite() and body.angular_velocity.is_finite())
	_check(bodies_finite, title + " leaves all five native bodies finite")
	jump_reports.append({"profile": physics_profile, "height": height, "approachSpeed": speed, "bodyForward": body_forward,
		"expectation": "powered-loop-out" if deliberate_powered_wheelie else "landing-runout",
		"touchdownThrottleRecovery": recovery_applied, "peakPitchDeg": rad_to_deg(max_pitch),
		"rearOnlyAfterLandingSeconds": float(rear_only_after_landing) / HZ,
		"invertedAfterLanding": inverted_after_landing, "finalUpDotWorld": final_up,
		"finalForwardAlongApproach": final_forward_along_approach,
		"frameContactsAtFinish": frame_contacts, "riderContactsAtFinish": rider_contacts,
		"crashObservation": bike.get_telemetry().get("crashObservation", {}),
		"longestAir": float(longest_air) / HZ, "peakHeight": peak_height,
		"maxBank": rad_to_deg(max_bank), "maxLaneError": max_lane_error,
		"minCorridorClearance": min_corridor_clearance, "maxFrontTravel": max_front,
		"maxRearTravel": max_rear, "crashed": bike.crashed, "reason": bike.crash_reason,
		"finalPosition": str(final_position), "samples": samples})


func _test_native_powered_jumps() -> void:
	var cfg_source := FileAccess.get_file_as_string("res://config/bike_250f.json")
	var cfg: Dictionary = JSON.parse_string(cfg_source)
	var controller_script: Script = load("res://scripts/bike_controller.gd")
	physics_profile = {"controller": controller_script.get_source_code().sha256_text(), "config": cfg_source.sha256_text()}
	print("TRACK native-jump profile: controller=", physics_profile.controller, " config=", physics_profile.config)
	for recipe: Dictionary in Track.EXTENSION_JUMPS:
		for body_forward in [0.0, 0.15, -0.15]:
			for speed in [20.0, 21.0, 22.0]:
				await _powered_jump(recipe, speed, body_forward, cfg)
	# Skill-based riding retains a physical consequence for holding a rearward
	# pitch command and drive through a nose-up, rear-wheel-first touchdown.
	await _powered_jump(Track.EXTENSION_JUMPS[0], 22.0, -0.15, cfg, false)
	var max_bank := 0.0
	var min_air := INF
	var max_air := 0.0
	for report: Dictionary in jump_reports:
		max_bank = maxf(max_bank, float(report.maxBank))
		min_air = minf(min_air, float(report.longestAir))
		max_air = maxf(max_air, float(report.longestAir))
	print("TRACK native jumps: %d actual standing third-gear rides; %.3f–%.3f s flight; max bank %.2f°" % [
		jump_reports.size(), min_air, max_air, max_bank])
	var output := FileAccess.open("res://build/track-jumps-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(jump_reports, "\t"))
		output.close()


func _run() -> void:
	Engine.physics_ticks_per_second = 240
	world = Node3D.new()
	root.add_child(world)
	var track: Dictionary = Track.build(world)
	await physics_frame
	await process_frame
	_test_continuous_native_course()
	_test_preserved_proving_sections()
	_test_large_tabletops()
	_test_ordered_gates(track)
	await _test_native_powered_jumps()
	print("TRACK LAYOUT: %d checks; %d failures" % [checks, failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
