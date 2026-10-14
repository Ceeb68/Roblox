extends Node3D
class_name DLBikeVisual

## Original 250F bodywork. Visual detail never alters collision geometry,
## wheel inertia, suspension or the SI-unit simulation scale.
const ORANGE := Color("f76524")
const ORANGE_LIGHT := Color("ff9b48")
const WHITE := Color("edf0e8")
const BLACK := Color("152028")
const RUBBER := Color("242725")
const SILVER := Color("a8b4b8")
const METAL := Color("616c73")
const GOLD := Color("ad985d")
const BLUE := Color("2990ad")

var _chassis: Node3D
var _fork: Node3D
var _front: Node3D
var _rear: Node3D
var _fork_upper: Array[MeshInstance3D] = []
var _fork_lower: Array[MeshInstance3D] = []
var _swingarms: Array[MeshInstance3D] = []
var _shock: MeshInstance3D
var _shock_spring: Node3D
var _chain_upper: MeshInstance3D
var _chain_lower: MeshInstance3D
var _front_brake_hose: MeshInstance3D
var _built: bool = false

func configure(chassis_body: Node3D, steering_fork: Node3D, front_wheel: Node3D, rear_wheel: Node3D, config: Dictionary) -> void:
	if _built:
		return
	_chassis = chassis_body
	_fork = steering_fork
	_front = front_wheel
	_rear = rear_wheel
	name = "Detailed250FBodywork"
	_build_chassis()
	_build_front()
	_build_wheel(_front, float(config.get("FrontRadius", 0.348)), 0.085, true)
	_build_wheel(_rear, float(config.get("RearRadius", 0.335)), 0.115, false)
	_built = true
	update_geometry()

func _build_chassis() -> void:
	# Twin rails, cradle, engine cases and subframe use real motorcycle
	# proportions; wider radiator shrouds contrast the slim saddle/rear fender.
	var steering_head := _chassis.to_local(_fork.global_position)
	for side in [-1.0, 1.0]:
		var x: float = side * 0.110
		var frame_neck := Vector3(x, steering_head.y - 0.05, steering_head.z - 0.015)
		for points in [
			[frame_neck, Vector3(x, -0.27, -0.24)],
			[Vector3(x, -0.27, -0.24), Vector3(x, -0.28, 0.24)],
			[Vector3(x, -0.28, 0.24), Vector3(x, 0.18, 0.13)],
			[Vector3(x, 0.18, 0.13), frame_neck],
			[Vector3(x, 0.18, 0.13), Vector3(x, 0.22, 0.61)],
			[Vector3(x, -0.10, 0.20), Vector3(x, 0.22, 0.61)]
		]:
			var rail := _link(self, 0.020, METAL, 0.72)
			_set_link(rail, points[0], points[1])
		var radiator := _box(self, Vector3(0.048, 0.257, 0.116), Vector3(side * 0.161, 0.057, -0.233), METAL)
		radiator.rotation.x = -0.17
		for fin in range(8):
			_box(self, Vector3(0.054, 0.012, 0.111), Vector3(side * 0.165, -0.051 + fin * 0.031, -0.239), BLACK)
		# Tapered side radiator shrouds and rear number boards avoid toy blocks.
		_panel(self, side * 0.167, side * 0.191,
			[Vector2(0.335, -0.237), Vector2(0.23, 0.083), Vector2(-0.032, -0.074), Vector2(0.107, -0.374)], ORANGE)
		_panel(self, side * 0.177, side * 0.195,
			[Vector2(0.272, -0.214), Vector2(0.189, 0.018), Vector2(0.048, -0.118)], BLUE)
		_panel(self, side * 0.165, side * 0.182,
			[Vector2(0.202, 0.249), Vector2(0.191, 0.58), Vector2(0.065, 0.66), Vector2(-0.072, 0.363)], WHITE)
		_panel(self, side * 0.183, side * 0.185,
			[Vector2(0.19, 0.478), Vector2(0.166, 0.62), Vector2(0.087, 0.624), Vector2(0.080, 0.487)], ORANGE)
		var number := _label(self, "21", Vector3(side * 0.190, 0.085, 0.386), BLACK, 51, 0.0025)
		number.rotation.y = side * PI * 0.5
		var logo := _label(self, "DL", Vector3(side * 0.197, 0.180, -0.139), WHITE, 31, 0.0019)
		logo.rotation.y = side * PI * 0.5
		var peg := _box(self, Vector3(0.100, 0.026, 0.070), Vector3(side * 0.217, -0.244, 0.078), SILVER)
		for tooth in range(4):
			_box(self, Vector3(0.011, 0.010, 0.072), peg.position + Vector3(-0.039 + tooth * 0.026, 0.018, 0), BLACK)
		_swingarms.append(_link(self, 0.025, SILVER, 0.78))
	_box(self, Vector3(0.250, 0.027, 0.416), Vector3(0, -0.287, -0.030), SILVER)
	var crankcase := _cylinder(self, 0.128, 0.208, METAL)
	crankcase.position = Vector3(0, -0.135, 0.073)
	crankcase.rotation.z = PI * 0.5
	var engine_cover := _cylinder(self, 0.108, 0.215, SILVER)
	engine_cover.position = crankcase.position
	engine_cover.rotation.z = PI * 0.5
	for side in [-1.0, 1.0]:
		var cover := _cylinder(self, 0.075, 0.011, METAL)
		cover.position = Vector3(side * 0.115, -0.135, 0.073)
		cover.rotation.z = PI * 0.5
		for n in range(6):
			var angle := TAU * n / 6.0
			var bolt := _cylinder(self, 0.008, 0.008, SILVER)
			bolt.position = Vector3(side * 0.122, -0.135 + cos(angle) * 0.087, 0.073 + sin(angle) * 0.087)
			bolt.rotation.z = PI * 0.5
	var barrel := _cylinder(self, 0.083, 0.228, SILVER)
	barrel.position = Vector3(0, -0.025, -0.058)
	barrel.rotation.x = -0.23
	for fin in range(5):
		var rib := _cylinder(self, 0.087, 0.009, METAL)
		rib.position = Vector3(0, -0.113 + fin * 0.032, -0.063 - fin * 0.005)
		rib.rotation.x = -0.23
	_box(self, Vector3(0.191, 0.083, 0.171), Vector3(0, 0.087, -0.091), SILVER)
	# Tank and saddle follow the long, flat profile of a motocross seat.
	_panel(self, -0.135, 0.135,
		[Vector2(0.284, -0.233), Vector2(0.344, -0.175), Vector2(0.301, 0.139), Vector2(0.086, 0.097), Vector2(0.167, -0.237)], BLACK)
	_panel(self, -0.111, 0.111,
		[Vector2(0.328, -0.087), Vector2(0.306, 0.55), Vector2(0.256, 0.568), Vector2(0.263, -0.109)], BLACK)
	for seam in range(9):
		_box(self, Vector3(0.199, 0.008, 0.011), Vector3(0, 0.321 - seam * 0.0020, -0.043 + seam * 0.059), Color("263039"))
	var fuel_cap := _cylinder(self, 0.032, 0.018, BLACK)
	fuel_cap.position = Vector3(0, 0.352, -0.145)
	_panel(self, -0.088, 0.088,
		[Vector2(0.299, 0.509), Vector2(0.250, 0.887), Vector2(0.213, 0.872), Vector2(0.259, 0.505)], ORANGE)
	# Four-stroke exhaust header routing into a high rear silencer.
	for points in [
		[Vector3(0.074, 0.058, -0.154), Vector3(0.174, -0.026, -0.219)],
		[Vector3(0.174, -0.026, -0.219), Vector3(0.178, -0.169, -0.173)],
		[Vector3(0.178, -0.169, -0.173), Vector3(0.186, -0.175, 0.219)],
		[Vector3(0.186, -0.175, 0.219), Vector3(0.194, 0.057, 0.372)]
	]:
		var header := _link(self, 0.026, Color("9a8063"), 0.70)
		_set_link(header, points[0], points[1])
	var silencer := _link(self, 0.058, SILVER, 0.85)
	_set_link(silencer, Vector3(0.201, 0.087, 0.277), Vector3(0.201, 0.175, 0.699))
	var exhaust_tip := _link(self, 0.046, BLACK, 0.72)
	_set_link(exhaust_tip, Vector3(0.201, 0.167, 0.67), Vector3(0.201, 0.187, 0.727))
	_shock = _link(self, 0.024, SILVER, 0.8)
	_shock_spring = Node3D.new()
	_shock_spring.name = "RearShockCoils"
	add_child(_shock_spring)
	for coil in range(8):
		var ring := _torus(_shock_spring, 0.031, 0.043, ORANGE)
		ring.position.y = -0.105 + coil * 0.030
	_chain_upper = _link(self, 0.006, BLACK)
	_chain_lower = _link(self, 0.006, BLACK)

func _build_front() -> void:
	for side in [-1.0, 1.0]:
		_fork_upper.append(_link(_fork, 0.025, GOLD, 0.72))
		_fork_lower.append(_link(_fork, 0.019, SILVER, 0.83))
		var clamp := _cylinder(_fork, 0.038, 0.045, SILVER)
		clamp.position = Vector3(side * 0.068, -0.07, -0.025)
		var stem := _link(_fork, 0.019, METAL, 0.7)
		_set_link(stem, Vector3(side * 0.065, 0.017, -0.025), Vector3(side * 0.116, 0.105, -0.012))
		var bar_inner := _link(_fork, 0.012, SILVER, 0.75)
		_set_link(bar_inner, Vector3(0, 0.095, -0.052), Vector3(side * 0.205, 0.126, -0.072))
		var bar_outer := _link(_fork, 0.012, SILVER, 0.75)
		_set_link(bar_outer, Vector3(side * 0.205, 0.126, -0.072), Vector3(side * 0.410, 0.140, -0.019))
		var grip := _link(_fork, 0.022, BLACK)
		_set_link(grip, Vector3(side * 0.305, 0.14, -0.023), Vector3(side * 0.414, 0.14, -0.018))
		for rib in range(6):
			var grip_rib := _torus(_fork, 0.021, 0.024, RUBBER)
			grip_rib.position = Vector3(side * (0.32 + rib * 0.016), 0.14, -0.021)
			grip_rib.rotation.z = PI * 0.5
		var lever := _link(_fork, 0.006, SILVER, 0.9)
		_set_link(lever, Vector3(side * 0.294, 0.145, -0.045), Vector3(side * 0.395, 0.143, -0.091))
		var end := _cylinder(_fork, 0.015, 0.008, SILVER)
		end.position = Vector3(side * 0.415, 0.141, -0.018)
		end.rotation.z = PI * 0.5
	var crossbar := _link(_fork, 0.015, BLACK)
	_set_link(crossbar, Vector3(-0.169, 0.125, -0.058), Vector3(0.169, 0.125, -0.058))
	var bar_pad := _cylinder(_fork, 0.032, 0.187, BLACK)
	bar_pad.position = Vector3(0, 0.125, -0.058)
	bar_pad.rotation.z = PI * 0.5
	_box(_fork, Vector3(0.143, 0.006, 0.033), Vector3(0, 0.156, -0.058), ORANGE)
	# Broad high-mounted front plate and a sharply tapered mudguard.
	_panel(_fork, -0.132, 0.132,
		[Vector2(0.104, -0.122), Vector2(0.079, -0.147), Vector2(-0.138, -0.136), Vector2(-0.146, -0.098)], WHITE)
	var front_number := _label(_fork, "21", Vector3(0, -0.011, -0.152), BLACK, 54, 0.0024)
	front_number.rotation.y = PI
	var front_name := _label(_fork, "DIRTLINE", Vector3(0, 0.082, -0.149), BLACK, 20, 0.0017)
	front_name.rotation.y = PI
	_panel(_fork, -0.083, 0.083,
		[Vector2(-0.153, 0.085), Vector2(-0.115, -0.113), Vector2(-0.159, -0.548), Vector2(-0.193, -0.542), Vector2(-0.175, 0.081)], ORANGE)
	_panel(_fork, -0.054, 0.054,
		[Vector2(-0.115, -0.129), Vector2(-0.159, -0.524), Vector2(-0.166, -0.516), Vector2(-0.124, -0.127)], ORANGE_LIGHT)
	_front_brake_hose = _link(_fork, 0.005, BLACK)

func _build_wheel(wheel: Node3D, radius: float, width: float, front: bool) -> void:
	var tire := _torus(wheel, radius - width, radius, RUBBER)
	tire.rotation.z = PI * 0.5
	var rim_radius := radius - width + 0.011
	var rim := _torus(wheel, rim_radius - 0.007, rim_radius + 0.007, SILVER)
	rim.rotation.z = PI * 0.5
	for side in [-1.0, 1.0]:
		var rim_edge := _torus(wheel, rim_radius - 0.003, rim_radius + 0.003, METAL)
		rim_edge.position.x = side * width * 0.285
		rim_edge.rotation.z = PI * 0.5
	var hub := _cylinder(wheel, 0.043, width * 1.16, SILVER)
	hub.rotation.z = PI * 0.5
	for n in range(18):
		var angle := TAU * n / 18.0
		for side in [-1.0, 1.0]:
			var spoke := _link(wheel, 0.0026, SILVER, 0.72)
			_set_link(spoke,
				Vector3(side * width * 0.40, cos(angle + 0.36) * 0.044, sin(angle + 0.36) * 0.044),
				Vector3(side * width * 0.26, cos(angle) * rim_radius, sin(angle) * rim_radius))
	# Individual knobby rows make tyre rotation and scale visibly legible.
	for n in range(34):
		var angle := TAU * n / 34.0
		for row in range(3):
			var stagger := angle + (0.045 if row == 1 else 0.0)
			var tread_radius := radius - (0.012 if row != 1 else 0.001)
			var knob := _box(wheel, Vector3(width * 0.22, 0.018, 0.026 if front else 0.033),
				Vector3((row - 1) * width * 0.29, cos(stagger) * tread_radius, sin(stagger) * tread_radius), BLACK)
			knob.rotation.x = stagger
	var rotor_side := -1.0 if front else 1.0
	var rotor := _torus(wheel, 0.074, 0.108 if front else 0.098, METAL)
	rotor.position.x = rotor_side * width * 0.64
	rotor.scale.y = 0.13
	rotor.rotation.z = PI * 0.5
	for n in range(6):
		var angle := TAU * n / 6.0
		var carrier := _link(wheel, 0.009, METAL)
		_set_link(carrier, Vector3(rotor_side * width * 0.64, 0, 0),
			Vector3(rotor_side * width * 0.64, cos(angle) * 0.092, sin(angle) * 0.092))
	if not front:
		var sprocket := _torus(wheel, 0.083, 0.111, SILVER)
		sprocket.position.x = -width * 0.70
		sprocket.scale.y = 0.14
		sprocket.rotation.z = PI * 0.5
		for n in range(16):
			var angle := TAU * n / 16.0
			_box(wheel, Vector3(0.006, 0.010, 0.012), Vector3(-width * 0.70, cos(angle) * 0.111, sin(angle) * 0.111), SILVER).rotation.x = angle

func update_geometry() -> void:
	if not _built:
		return
	var front_axle := _fork.global_transform.affine_inverse() * _front.global_position
	var rear_axle := _chassis.global_transform.affine_inverse() * _rear.global_position
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var top := Vector3(side * 0.062, 0.053, -0.029)
		var bottom := front_axle + Vector3(side * 0.052, 0.012, 0)
		var middle := top.lerp(bottom, 0.60)
		_set_link(_fork_upper[i], top, middle)
		_set_link(_fork_lower[i], middle, bottom)
		_set_link(_swingarms[i], Vector3(side * 0.111, -0.110, 0.151), rear_axle + Vector3(side * 0.065, 0, 0))
	var shock_top := Vector3(0, 0.182, 0.209)
	var shock_bottom := Vector3(0, -0.139, 0.227).lerp(rear_axle, 0.33)
	_set_link(_shock, shock_top, shock_bottom)
	_shock_spring.position = shock_top.lerp(shock_bottom, 0.48)
	_shock_spring.basis = _basis_along(shock_top - shock_bottom)
	_shock_spring.scale = Vector3(1, shock_top.distance_to(shock_bottom) / 0.372, 1)
	_set_link(_chain_upper, Vector3(-0.133, -0.062, 0.143), rear_axle + Vector3(-0.091, 0.095, 0))
	_set_link(_chain_lower, Vector3(-0.133, -0.172, 0.143), rear_axle + Vector3(-0.091, -0.095, 0))
	_set_link(_front_brake_hose, Vector3(-0.098, 0.080, -0.080), front_axle + Vector3(-0.073, 0.045, 0.045))

func _basis_along(delta: Vector3) -> Basis:
	var up := delta.normalized()
	var reference := Vector3.RIGHT if absf(up.x) < 0.95 else Vector3.FORWARD
	var right := reference.cross(up).normalized()
	return Basis(right, up, right.cross(up)).orthonormalized()

func _set_link(mesh: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	mesh.position = (a + b) * 0.5
	mesh.basis = _basis_along(b - a)
	mesh.scale.y = maxf(0.001, a.distance_to(b))

func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.48 if metallic > 0.0 else 0.78
	material.metallic = metallic
	return material

func _mesh(parent: Node3D, shape: Mesh, origin: Vector3, color: Color, metallic: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.position = origin
	node.material_override = _material(color, metallic)
	parent.add_child(node)
	return node

func _box(parent: Node3D, size: Vector3, origin: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return _mesh(parent, shape, origin, color)

func _link(parent: Node3D, radius: float, color: Color, metallic: float = 0.0) -> MeshInstance3D:
	return _cylinder(parent, radius, 1.0, color, metallic)

func _cylinder(parent: Node3D, radius: float, height: float, color: Color, metallic: float = 0.0) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 16
	return _mesh(parent, shape, Vector3.ZERO, color, metallic)

func _torus(parent: Node3D, inner: float, outer: float, color: Color) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = inner
	shape.outer_radius = outer
	shape.rings = 24
	shape.ring_segments = 10
	return _mesh(parent, shape, Vector3.ZERO, color, 0.65 if color == SILVER else 0.0)

func _panel(parent: Node3D, left: float, right: float, yz: Array, color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xmin := minf(left, right)
	var xmax := maxf(left, right)
	var count := yz.size()
	for n in range(1, count - 1):
		for side in [xmin, xmax]:
			var indices := [0, n, n + 1] if side == xmin else [0, n + 1, n]
			for index in indices:
				var point: Vector2 = yz[index]
				surface.add_vertex(Vector3(side, point.x, point.y))
	for n in range(count):
		var next := (n + 1) % count
		var a: Vector2 = yz[n]
		var b: Vector2 = yz[next]
		for vertex in [Vector3(xmin, a.x, a.y), Vector3(xmax, a.x, a.y), Vector3(xmin, b.x, b.y),
			Vector3(xmin, b.x, b.y), Vector3(xmax, a.x, a.y), Vector3(xmax, b.x, b.y)]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	var node := _mesh(parent, surface.commit(), Vector3.ZERO, color)
	# Mixed side-panel outlines are intentionally double sided. Their shallow
	# prism edge still receives shadows and makes bodywork thickness readable.
	(node.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	return node

func _label(parent: Node3D, text: String, origin: Vector3, color: Color, font_size: int, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	label.position = origin
	parent.add_child(label)
	return label
