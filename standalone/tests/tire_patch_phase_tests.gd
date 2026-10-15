extends SceneTree
## Jolt reports last-step world contacts beside the solved wheel transform.
## Measure the actual native trailing lever at several rates/directions and
## require the tire-force patch to stay at the current geometric wheel base.
const Bike = preload("res://scripts/bike_controller.gd")
var world: Node3D
var bike: Node3D
var checks := 0
var failures: Array[String] = []
var cfg: Dictionary
func _initialize() -> void:
	call_deferred("_run")
func tick() -> void:
	await physics_frame
	await process_frame
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("TIRE PATCH PHASE FAIL: " + label)
func fixture(speed: float) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await tick()
	world=Node3D.new()
	root.add_child(world)
	var ground:=StaticBody3D.new()
	ground.position.y=-.25
	ground.set_meta("physics_surface","dirt")
	var material:=PhysicsMaterial.new()
	material.friction=0.
	material.bounce=0.
	ground.physics_material_override=material
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(1000.,.5,1000.)
	collision.shape=shape
	ground.add_child(collision)
	world.add_child(ground)
	bike=Bike.new()
	bike.configure(cfg.duplicate(true))
	bike.set_riding_mode("direct")
	world.add_child(bike)
	bike.reset_bike(Transform3D(Basis.IDENTITY,Vector3(0,.82,0)))
	bike.set_controls({"clutch":1.,"footDown":true})
	for i in range(240):await tick()
	for body: RigidBody3D in [bike.chassis,bike.fork,bike.front_wheel,bike.rear_wheel,bike.rider_body]:
		body.linear_velocity=Vector3(0.,0.,-speed)
		body.angular_velocity=Vector3.ZERO
		body.sleeping=false
	bike.front_wheel.angular_velocity=-bike.front_wheel.global_basis.x*speed/float(cfg.FrontRadius)
	bike.rear_wheel.angular_velocity=-bike.rear_wheel.global_basis.x*speed/float(cfg.RearRadius)
	bike.front_wheel.invalidate_load_history()
	bike.rear_wheel.invalidate_load_history()
	bike.set_controls({"clutch":1.,"footDown":false})
func rolling_geometry(hz: int, speed: float) -> void:
	Engine.physics_ticks_per_second=hz
	await fixture(speed)
	var raw_sum:=[0.,0.]
	var corrected_sum:=[0.,0.]
	var displacement_sum:=[0.,0.]
	var samples:=[0,0]
	for i in range(48):
		await tick()
		for axle in range(2):
			var wheel: RigidBody3D=bike.front_wheel if axle==0 else bike.rear_wheel
			if not wheel.contact or wheel.normal_load<=0. or not wheel.tire_patch_phase_valid:continue
			var forward: Vector3=wheel.contact_normal.cross(wheel.global_basis.x).normalized()
			raw_sum[axle]+=absf((wheel.contact_position-wheel.global_position).dot(forward))
			corrected_sum[axle]+=absf((wheel.tire_contact_position-wheel.global_position).dot(forward))
			displacement_sum[axle]+=absf(wheel.tire_patch_translation.dot(forward))
			samples[axle]+=1
	for axle in range(2):
		var n:=maxi(1,int(samples[axle]))
		var raw: float=raw_sum[axle]/n
		var corrected: float=corrected_sum[axle]/n
		var displacement: float=displacement_sum[axle]/n
		var label:="%dHz %.0fm/s %s"%[hz,speed,"front" if axle==0 else "rear"]
		print("PATCH PHASE %s: raw %.6fm, force patch %.6fm, solved translation %.6fm"%[label,raw,corrected,displacement])
		check(samples[axle]>30,label+" uses repeated loaded native contacts")
		check(raw>absf(speed)/float(hz)*.60,label+" reproduces the native one-step world-point lag")
		check(corrected<.010,label+" keeps tire transport and force at the actual wheel-base plane")
		check(corrected<raw*.20,label+" removes at least80% of false trailing tire lever")
func history_and_remount() -> void:
	Engine.physics_ticks_per_second=240
	await fixture(12.)
	for i in range(8):await tick()
	for wheel: RigidBody3D in [bike.front_wheel,bike.rear_wheel]:
		wheel.invalidate_load_history()
		check(not wheel.tire_patch_phase_valid and wheel.tire_patch_translation==Vector3.ZERO,"Invalidated observations cannot carry a pre-reset tire displacement")
		check(wheel.tire_contact_position==wheel.contact_position,"Missing history falls back to reported geometry")
	for i in range(4):await tick()
	for wheel: RigidBody3D in [bike.front_wheel,bike.rear_wheel]:
		check(wheel.tire_patch_phase_valid,"Consecutive native callbacks rebuild patch phase history")
	check(bike.reset_bike(Transform3D(Basis.IDENTITY,Vector3(120.,.82,0.)),true),"Native remount accepts a far-away recovery pose")
	bike.set_controls({"clutch":1.,"footDown":true})
	for wheel: RigidBody3D in [bike.front_wheel,bike.rear_wheel]:
		check(not wheel.tire_patch_phase_valid and wheel.tire_patch_translation==Vector3.ZERO,"Remount clears phase before native pose synchronization")
	var max_reset_translation:=[0.,0.]
	var max_reset_lever:=[0.,0.]
	var loaded_samples:=[0,0]
	for i in range(120):
		await tick()
		for axle in range(2):
			var wheel: RigidBody3D=bike.front_wheel if axle==0 else bike.rear_wheel
			max_reset_translation[axle]=maxf(max_reset_translation[axle],wheel.tire_patch_translation.length())
			if wheel.contact and wheel.normal_load>0.:
				loaded_samples[axle]+=1
				max_reset_lever[axle]=maxf(max_reset_lever[axle],wheel.tire_contact_position.distance_to(wheel.global_position))
	for axle in range(2):
		check(max_reset_translation[axle]<.10,"Far remount never enters the tire lever as a120m translation")
		check(loaded_samples[axle]>20,"Remount validation includes actual loaded contact after the reset cache clears")
		check(max_reset_lever[axle]<.60,"Remounted tire patch remains beside its actual native wheel")
	check(bike.reset_bike(Transform3D(Basis.IDENTITY,Vector3(120.,12.,0.)),true),"Native airborne reset accepts its new unsupported pose")
	bike.set_controls({"clutch":1.,"footDown":false})
	for i in range(8):await tick()
	for wheel: RigidBody3D in [bike.front_wheel,bike.rear_wheel]:
		check(not wheel.contact and wheel.tire_contact_position==Vector3.ZERO,"Unsupported wheel cannot reuse an old transported ground patch")
		wheel.invalidate_load_history()
		check(wheel.tire_contact_position==Vector3.ZERO,"Invalidating an unsupported observation cannot resurrect a previous ground point")
	for result: Dictionary in [bike._front_result,bike._rear_result]:
		check(absf(float(result.longitudinalForce))+absf(float(result.lateralForce))==0.,"Unsupported reset supplies no tangential tire force")
func _run() -> void:
	cfg=JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	for hz: int in [120,240,480]:await rolling_geometry(hz,24.)
	await rolling_geometry(240,6.)
	await rolling_geometry(240,-12.)
	await history_and_remount()
	print("Tire patch phase: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
