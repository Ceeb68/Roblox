extends SceneTree
## Actual Jolt contact/control regression benches. No body is pinned upright.
const Bike = preload("res://scripts/bike_controller.gd")
var world: Node3D
var bike: Node3D
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
 call_deferred("run")
func check(value: bool, message: String) -> void:
 checks += 1
 if not value:
  failures.append(message)
  push_error("HANDLING FAIL: " + message)
func tick() -> void:
 await physics_frame
 await process_frame
func advance(seconds: float) -> void:
 for i in range(roundi(seconds * 240.0)):
  await tick()
func make_bike(position: Vector3, basis: Basis = Basis.IDENTITY) -> void:
 if is_instance_valid(bike):
  bike.queue_free()
  await tick()
 bike = Bike.new()
 world.add_child(bike)
 bike.reset_bike(Transform3D(basis, position))
 await tick()
func run() -> void:
 world = Node3D.new()
 root.add_child(world)
 var floor := StaticBody3D.new()
 floor.position.y = -0.5
 floor.set_meta("physics_surface", "hardpack")
 var material := PhysicsMaterial.new()
 material.friction = 0.0
 floor.physics_material_override = material
 var collision := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = Vector3(200, 1, 200)
 collision.shape = box
 floor.add_child(collision)
 world.add_child(floor)
 await make_bike(Vector3(0, 0.82, 0))
 check(bike.riding_mode == "virtual_rider", "Virtual human is the default input interpretation")
 check(not bike.set_riding_mode("upright_rail"), "Unknown riding modes are rejected")
 var shape: CylinderShape3D = bike.front_wheel.get_child(0).shape
 check(absf(shape.radius - float(bike.config.FrontRadius)) < 0.00001, "Rounded native tire preserves real outer radius")
 check(shape.margin > 0.03, "Tire has a real smooth native shoulder instead of a sharp side edge")
 await advance(2.0)
 check(not bike.crashed and absf(bike.get_telemetry().roll) < deg_to_rad(3.0), "Deployed physical feet support a stationary bike")
 # Strength and desired lean are bounded while real traction steers a bike.
 bike.shift_gear(1)
 var max_torque := 0.0
 var max_intent := 0.0
 for i in range(1200):
  var t: float = float(i) / 240.0
  bike.set_controls({"throttle": minf(t, 0.8), "clutch": maxf(0.0, 1.0 - t / 1.4),
   "footDown": t < 1.6, "steer": 1.0 if t > 3.0 else 0.0})
  await tick()
  var sample: Dictionary = bike.get_telemetry()
  max_torque = maxf(max_torque, absf(sample.riderSteeringTorque))
  max_intent = maxf(max_intent, absf(sample.riderTargetLean))
 check(max_torque <= 45.001, "Virtual rider handlebar actuation remains within 45 Nm human strength")
 check(max_intent <= deg_to_rad(36.001), "Full digital lean intent stays within a conservative surface-aware envelope")
 # Put an unsupported rider on a genuinely inclined motorcycle at rest.
 # Walking steering has finite torque but cannot pin the body to world-up.
 await make_bike(Vector3(0, 0.88, 0), Basis(Vector3.BACK, deg_to_rad(9.0)))
 bike.set_controls({"footDown": false, "clutch": 1.0})
 await advance(5.0)
 var stopped: Dictionary = bike.get_telemetry()
 check(stopped.crashed and absf(stopped.roll) > deg_to_rad(60.0), "Unsupported stationary bike still falls and crashes under actual gravity")
 print("HANDLING unsupported stationary: roll=%.1f deg, crashed=%s" % [rad_to_deg(stopped.roll), stopped.crashed])
 # Airborne attitude is deliberately free, even with the optional human.
 await make_bike(Vector3(0, 30.0, 0), Basis(Vector3.BACK, deg_to_rad(28.0)))
 bike.set_controls({"footDown": false, "clutch": 1.0})
 var start_roll: float = bike.get_telemetry().roll
 await advance(0.5)
 var flight: Dictionary = bike.get_telemetry()
 check(not flight.frontContact and not flight.rearContact, "Air bench has no tire contacts")
 check(absf(flight.riderTargetLean) < 0.00001 and absf(flight.headingCorrection) < 0.00001, "Virtual balancing and line intent are inactive airborne")
 check(absf(flight.roll - start_roll) < deg_to_rad(2.0), "No automatic airborne roll/landing correction changes a free attitude")
 check(absf(bike.chassis.linear_velocity.y + 4.905) < 0.35, "Airborne native centre accelerates under gravity")
 var old_com: Vector3 = bike.chassis.center_of_mass
 bike.set_controls({"bodySide": 0.8, "lean": 0.7, "standing": true})
 await advance(0.8)
 check(bike.chassis.center_of_mass.x - old_com.x > 0.07, "Rider body input actually moves the combined physical COM")
 check(bike.chassis.center_of_mass.y - old_com.y > 0.07, "Standing posture actually raises the physical COM")
 check(absf(bike.get_telemetry().roll - start_roll) > 0.01, "Finite rider articulation reacts on airborne native chassis")
 check(bike.set_riding_mode("direct"), "Strict direct handlebar mode remains selectable")
 check(absf(bike._steering_integral) < 0.000001, "Mode change clears learned steering torque state")
 bike.set_first_person(true)
 var eyes: Transform3D = bike.get_rider_camera_transform()
 check(eyes.origin.is_finite() and eyes.origin.distance_to(bike.chassis.global_position) < 2.0, "First-person eyes follow an anatomical rider anchor")
 print("Handling native checks: %s passed, %s failed" % [checks - failures.size(), failures.size()])
 quit(0 if failures.is_empty() else 1)
