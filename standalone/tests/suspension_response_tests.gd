extends SceneTree
## Matched native suspension tests: geometry and entry motion stay identical.
## The comparison changes only high-speed hydraulic compression; body mass,
## springs, tire forces and solver constraints remain the production system.
## Run a second physics rate with matching --fixed-fps and -- --hz=120/480.
const Bike = preload("res://scripts/bike_controller.gd")
const Suspension = preload("res://physics/suspension.gd")
const RiderInput = preload("res://scripts/rider_input.gd")
var hz := 240.0
var world: Node3D
var bike: Node3D
var results: Array[Dictionary] = []
var cfg: Dictionary
var physics_profile: Dictionary = {}
var checks := 0
var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("SUSPENSION FAIL: " + message)

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="):
			hz = float(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = int(hz)
	call_deferred("_run")

func _tick() -> void:
	await physics_frame
	await process_frame

func _ground(bumps: bool, height: float) -> void:
	var verts := PackedVector3Array()
	for i: int in range(2400):
		var za := 10.0 - float(i) * 0.05
		var zb := za - 0.05
		var ya := _height(za, height) if bumps else 0.0
		var yb := _height(zb, height) if bumps else 0.0
		var a := Vector3(-20, ya, za)
		var b := Vector3(20, ya, za)
		var c := Vector3(-20, yb, zb)
		var d := Vector3(20, yb, zb)
		verts.append_array([a, c, b, b, c, d])
	var body := StaticBody3D.new()
	body.set_meta("physics_surface", "hardpack")
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 0.0
	body.physics_material_override = mat
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(verts)
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)

func _height(z: float, height: float) -> float:
	var result := 0.0
	for center: float in [-12.0, -18.0, -24.0, -30.0, -36.0, -42.0]:
		var d := absf(z - center)
		if d < 1.0:
			result += height * 0.5 * (1.0 + cos(PI * d))
	return result

func _case(kind: String, height: float, standing: bool, linear: bool) -> Dictionary:
	if is_instance_valid(world):
		world.queue_free()
		await _tick()
	world = Node3D.new()
	root.add_child(world)
	var bumps := kind == "bumps"
	_ground(bumps, height)
	var settings := cfg.duplicate(true)
	for axle: String in ["Front", "Rear"]:
		if linear:
			settings.Suspension[axle]["HighSpeedCompression"] = settings.Suspension[axle].Compression
			settings.Suspension[axle]["HighSpeedRebound"] = settings.Suspension[axle].Rebound
	bike = Bike.new()
	bike.configure(settings)
	world.add_child(bike)
	bike.reset_bike(Transform3D(Basis.IDENTITY, Vector3(0, 0.82 if bumps else 0.82 + height, 0)))
	bike.set_controls({"footDown": false, "clutch": 1.0, "standing": standing})
	await _tick()
	await _tick()
	if bumps:
		bike.set_controls({"footDown": true})
		for _i: int in range(int(hz)):
			await _tick()
		for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
			body.linear_velocity = Vector3(0, 0, -12)
			body.angular_velocity = Vector3.ZERO
		bike.front_wheel.angular_velocity = Vector3(-12.0 / float(cfg.FrontRadius), 0, 0)
		bike.rear_wheel.angular_velocity = Vector3(-12.0 / float(cfg.RearRadius), 0, 0)
		bike.front_wheel.invalidate_load_history()
		bike.rear_wheel.invalidate_load_history()
		bike.set_controls({"footDown": false})
	var peak_front := 0.0
	var peak_rear := 0.0
	var peak_rate := 0.0
	var peak_force := 0.0
	var peak_accel := 0.0
	var peak_impact_accel := 0.0
	var peak_pitch := 0.0
	var peak_roll := 0.0
	var peak_load := 0.0
	var compression_work := 0.0
	var rebound_work := 0.0
	var airborne_ticks := 0
	var loaded_ticks := 0
	var first_touch := -1
	var settled_at := -1.0
	var bounce_height := -INF
	var minimum_damper_power := 0.0
	var native_contact_ticks := 0
	var previous_v: Vector3 = bike.chassis.linear_velocity
	var samples: Array[Dictionary] = []
	# A stationary bike eventually needs the same automatic support feet as
	# the actual player. Keep them raised through the drop/first impact; after
	# settling, the production stop lifecycle avoids testing an unrelated
	# feet-up parking balance failure instead of suspension absorption.
	var feet_driver: RefCounted = RiderInput.new() if not bumps else null
	if feet_driver != null:
		feet_driver.standing = standing
		feet_driver.foot_down = false
	var first_touch_feet_down := false
	var boot_enables := 0
	var boot_enable_clearance := INF
	var previous_boot_disabled: Array[bool] = [bike._feet[0].disabled, bike._feet[1].disabled]
	for i: int in range(int((5.0 if bumps else 4.0) * hz)):
		if feet_driver != null:
			feet_driver.update_auto_feet(1.0 / hz, bike.get_telemetry())
			bike.set_controls(feet_driver.packet())
		await _tick()
		var t: Dictionary = bike.get_telemetry()
		if feet_driver != null:
			for index: int in range(2):
				var foot: CollisionShape3D = bike._feet[index]
				if previous_boot_disabled[index] and not foot.disabled:
					var capsule := foot.shape as CapsuleShape3D
					var world_extent := capsule.radius + (capsule.height * 0.5 - capsule.radius) * absf(foot.global_basis.y.y)
					boot_enable_clearance = minf(boot_enable_clearance, foot.global_position.y - world_extent)
					boot_enables += 1
				previous_boot_disabled[index] = foot.disabled
		var f: Dictionary = bike.front_suspension_state
		var r: Dictionary = bike.rear_suspension_state
		peak_front = maxf(peak_front, float(f.compression))
		peak_rear = maxf(peak_rear, float(r.compression))
		peak_rate = maxf(peak_rate, maxf(absf(float(f.velocity)), absf(float(r.velocity))))
		peak_force = maxf(peak_force, maxf(absf(float(f.force)), absf(float(r.force))))
		var acceleration: float = (bike.chassis.linear_velocity - previous_v).length() * hz
		peak_accel = maxf(peak_accel, acceleration)
		# The stationary stop-foot task begins after landing absorption. Keep
		# its rigid boot contact in whole-ride telemetry, while comparing the
		# suspension's impact over the first half-second of native tire support.
		# Moving bump rides retain the complete five-second comfort window.
		if bumps or first_touch < 0 or i <= first_touch + roundi(hz * 0.5):
			peak_impact_accel = maxf(peak_impact_accel, acceleration)
		peak_pitch = maxf(peak_pitch, absf(float(t.pitch)))
		peak_roll = maxf(peak_roll, absf(float(t.roll)))
		peak_load = maxf(peak_load, float(t.frontLoad) + float(t.rearLoad))
		previous_v = bike.chassis.linear_velocity
		var loaded := float(t.frontLoad) + float(t.rearLoad) > 100.0
		if loaded:
			loaded_ticks += 1
			if first_touch < 0:
				first_touch = i
				first_touch_feet_down = bool(t.footDown)
		else:
			airborne_ticks += 1
		if first_touch >= 0 and i > first_touch + int(hz * .2):
			bounce_height = maxf(bounce_height, bike.chassis.global_position.y)
		if first_touch >= 0 and settled_at < 0.0 and i > first_touch + int(hz) and absf(bike.chassis.linear_velocity.y) < .1 and absf(float(f.velocity)) < .1 and absf(float(r.velocity)) < .1:
			settled_at = float(i - first_touch) / hz
		for axle: String in ["Front", "Rear"]:
			var state: Dictionary = f if axle == "Front" else r
			var rate := float(state.velocity)
			var power := float(state.damperForce) * rate
			minimum_damper_power = minf(minimum_damper_power, power)
			if rate >= 0:
				compression_work += power / hz
			else:
				rebound_work += power / hz
		native_contact_ticks += int(bike.front_wheel.native_contact_count > 0 or bike.rear_wheel.native_contact_count > 0)
		if i % int(hz * .05) == 0:
			samples.append({"t": float(i)/hz,"y":bike.chassis.global_position.y,"z":bike.chassis.global_position.z,"vy":bike.chassis.linear_velocity.y,"front":f.duplicate(),"rear":r.duplicate(),"pitch":t.pitch,"roll":t.roll,"load":float(t.frontLoad)+float(t.rearLoad)})
	var result := {"profile":physics_profile,"kind":kind,"height":height,"standing":standing,"linearDamping":linear,"hz":hz,"frontTravel":peak_front,"rearTravel":peak_rear,"peakShaftSpeed":peak_rate,"peakForce":peak_force,"peakChassisAccel":peak_accel,"peakImpactAccel":peak_impact_accel,"peakPitchDeg":rad_to_deg(peak_pitch),"peakRollDeg":rad_to_deg(peak_roll),"peakLoad":peak_load,"compressionDissipation":compression_work,"reboundDissipation":rebound_work,"airborneTicks":airborne_ticks,"loadedTicks":loaded_ticks,"bounceHeight":bounce_height,"settledAfter":settled_at,"finalSpeed":bike.chassis.linear_velocity.length(),"crashed":bike.crashed,"reason":bike.crash_reason,"minimumDamperPower":minimum_damper_power,"nativeContactTicks":native_contact_ticks,"samples":samples,"automaticFeet":feet_driver!=null,"firstTouchFootDown":first_touch_feet_down,"finalFootDown":bool(bike.controls.footDown),"bootEnables":boot_enables,"bootEnableClearance":boot_enable_clearance if boot_enables>0 else 0.0}
	results.append(result)
	var summary := result.duplicate()
	summary.erase("samples")
	print("SUSPENSION %s %.2fm %s %s: impact/whole accel %.2f/%.2f m/s2, stroke %.1f/%.1fcm, bank %.2fdeg" % [kind,height,"standing" if standing else "seated","linear" if linear else "digressive",peak_impact_accel,peak_accel,100.0*peak_front,100.0*peak_rear,rad_to_deg(peak_roll)])
	return result


func _material_tests() -> void:
	# Passivity and stored-energy checks are independent of the native benches.
	# Derivative of elastic energy must equal the conservative spring force;
	# opposing damping may dissipate but never generate relative-axis energy.
	for axle: String in ["Front", "Rear"]:
		var settings: Dictionary = cfg.Suspension[axle].duplicate(true)
		for compression: float in [0.02, 0.12, 0.26, 0.29, 0.34]:
			var state := Suspension.new_state()
			var center: Dictionary = Suspension.step_articulated(state, compression, 0.0, 1.0 / hz, settings)
			var low: Dictionary = Suspension.step_articulated(Suspension.new_state(), compression - 0.000001, 0.0, 1.0 / hz, settings)
			var high: Dictionary = Suspension.step_articulated(Suspension.new_state(), compression + 0.000001, 0.0, 1.0 / hz, settings)
			var derivative := (float(high.elasticEnergy) - float(low.elasticEnergy)) / 0.000002
			_check(absf(derivative - float(center.springForce) - float(center.bumpForce)) < 0.001,
				"%s %.2fm stored elastic energy agrees with conservative force" % [axle, compression])
			for rate: float in [-12.0,-4.0,-0.5,-0.1,0.1,0.5,4.0,12.0]:
				var output: Dictionary = Suspension.step_articulated(state, compression, rate, 1.0 / hz, settings)
				_check(float(output.damperForce) * rate >= -0.000001,
					"%s %.2fm / %.1fm/s hydraulic force is passive" % [axle,compression,rate])
				_check(absf(float(output.force)) <= float(output.forceLimit) + 0.000001,
					"%s force remains finite and bounded" % axle)
		# The knee joins continuously even when rebound/compression differ.
		for direction: float in [-1.0,1.0]:
			var key := "ReboundKneeSpeed" if direction < 0 else "CompressionKneeSpeed"
			var knee := float(settings.get(key, 0.5))
			var a: Dictionary = Suspension.step_articulated(Suspension.new_state(),0.12,direction*(knee-0.000001),1.0/hz,settings)
			var b: Dictionary = Suspension.step_articulated(Suspension.new_state(),0.12,direction*(knee+0.000001),1.0/hz,settings)
			_check(absf(float(a.force)-float(b.force)) < 0.02, axle + " damper force stays continuous across its hydraulic knee")
		# An old saved setup with no new high-speed fields keeps its law.
		var legacy := settings.duplicate()
		for key: String in ["HighSpeedCompression","CompressionKneeSpeed","HighSpeedRebound","ReboundKneeSpeed"]:
			legacy.erase(key)
		for rate: float in [-3.0,3.0]:
			var old: Dictionary = Suspension.step_articulated(Suspension.new_state(),0.1,rate,1.0/hz,legacy)
			var coefficient := float(legacy.Compression if rate > 0 else legacy.Rebound)
			_check(absf(float(old.damperForce)-coefficient*rate) < 0.000001,
				axle + " old setup retains linear hydraulic response")
		# Test the finite damper impulse independently of the production engine's
		# unknown coupled constraints. A free axial pair must lose exactly the
		# reported energy without reversing velocity, even at coarse timesteps.
		var free_settings := settings.duplicate()
		free_settings.SpringRate = 0.0
		free_settings.Preload = 0.0
		var effective_mass := 4.5 if axle == "Front" else 6.9
		for step_hz: float in [60.0,120.0,240.0,480.0]:
			var dt := 1.0 / step_hz
			for initial_rate: float in [-12.0,-4.0,-0.5,-0.1,0.1,0.5,4.0,12.0]:
				var whole: Dictionary = Suspension.step_articulated(Suspension.new_state(),0.0,initial_rate,dt,free_settings,effective_mass)
				var end_rate := initial_rate-float(whole.force)*dt/effective_mass
				var lost_energy := 0.5*effective_mass*(initial_rate**2-end_rate**2)
				_check(end_rate*initial_rate >= -0.000001,
					"%s %dHz hydraulic impulse never reverses velocity itself" % [axle,int(step_hz)])
				_check(lost_energy >= -0.000001 and absf(lost_energy-float(whole.damperPower)*dt) < 0.000001,
					"%s %dHz discrete hydraulic work matches kinetic-energy loss" % [axle,int(step_hz)])
				var half: Dictionary = Suspension.step_articulated(Suspension.new_state(),0.0,initial_rate,dt*0.5,free_settings,effective_mass)
				var middle_rate := initial_rate-float(half.force)*dt*0.5/effective_mass
				var second: Dictionary = Suspension.step_articulated(Suspension.new_state(),0.0,middle_rate,dt*0.5,free_settings,effective_mass)
				var split_end := middle_rate-float(second.force)*dt*0.5/effective_mass
				_check(absf(split_end-end_rate) < 0.000001,
					"%s hydraulic flow composes across timestep subdivisions" % axle)

func _run() -> void:
	var config_source := FileAccess.get_file_as_string("res://config/bike_250f.json")
	cfg = JSON.parse_string(config_source)
	var controller_script: Script = load("res://scripts/bike_controller.gd")
	var suspension_script: Script = load("res://physics/suspension.gd")
	physics_profile = {"controller":controller_script.get_source_code().sha256_text(),
		"suspension":suspension_script.get_source_code().sha256_text(),"config":config_source.sha256_text()}
	print("SUSPENSION profile: ",JSON.stringify(physics_profile))
	_material_tests()
	for kind: String in ["drop", "bumps"]:
		for height: float in ([0.4, 0.9] if kind == "drop" else [0.18]):
			for standing: bool in [false, true]:
				var baseline: Dictionary = await _case(kind,height,standing,true)
				var candidate: Dictionary = await _case(kind,height,standing,false)
				var label := "%s %.2fm %s" % [kind,height,"standing" if standing else "seated"]
				_check(not bool(candidate.crashed),label + " remains rideable")
				_check(float(candidate.minimumDamperPower) >= -0.000001,label + " hydraulic work remains passive throughout the native ride")
				_check(int(candidate.nativeContactTicks) > int(hz),label + " uses actual native tire contact")
				_check(float(candidate.frontTravel) < float(cfg.Suspension.Front.Travel) + 0.002 and float(candidate.rearTravel) < float(cfg.Suspension.Rear.Travel) + 0.002,label + " uses suspension travel without striking the mechanical stop")
				_check(float(candidate.peakImpactAccel) <= float(baseline.peakImpactAccel) * (0.94 if kind == "drop" else 1.02),label + " absorbs fast shaft motion without the former chassis force spike")
				_check(float(candidate.bounceHeight) <= float(baseline.bounceHeight)+0.06,label + " avoids excessive rebound after absorbing the impact")
				_check(float(candidate.peakRollDeg) < (4.0 if kind == "drop" else 12.0),label + " avoids an uncommanded suspension-induced fall")
				if kind == "drop":
					_check(not bool(candidate.firstTouchFootDown),label + " first impact is absorbed without support-foot collision")
					_check(int(candidate.bootEnables) >= 2 and float(candidate.bootEnableClearance) >= -0.01,
						label + " automatic boot deployment enables clear geometry instead of penetrating soil")
					_check(float(candidate.peakChassisAccel) <= float(candidate.peakImpactAccel) + 10.0,
						label + " stopped boot planting cannot add a delayed chassis catapult after suspension absorption")
				if kind == "bumps":
					_check(float(candidate.finalSpeed) >= float(baseline.finalSpeed)*0.97,label + " does not obtain comfort by adding rolling drag")
	var path := "res://build/suspension-response-report-%d-%d.json" % [int(hz),OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute("res://build")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	file.close()
	print("Native suspension response: %d checks, %d failures (%d Hz)" % [checks,failures.size(),int(hz)])
	print("SUSPENSION_REPORT ",path)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
