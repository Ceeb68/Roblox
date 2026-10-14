extends Node3D
class_name DLRiderVisual

## Original procedural riding gear and articulated human proportions. This is
## presentation only: pose inputs come from the simulated rider, never drive it.
const NAVY := Color("142a3c")
const BLUE := Color("2588ac")
const ORANGE := Color("ff743e")
const WHITE := Color("e8ece8")
const BLACK := Color("182027")
const SILVER := Color("9cabb2")

var head_anchor: Node3D
var _chassis: Node3D
var _fork: Node3D
var _pelvis: MeshInstance3D
var _torso: Node3D
var _head: Node3D
var _helmet_shell: MeshInstance3D
var _neck: MeshInstance3D
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []
var _elbows: Array[MeshInstance3D] = []
var _shoulders: Array[MeshInstance3D] = []
var _gloves: Array[Node3D] = []
var _thighs: Array[MeshInstance3D] = []
var _shins: Array[MeshInstance3D] = []
var _knees: Array[Node3D] = []
var _boots: Array[Node3D] = []
var _first_person: bool = false
var _built: bool = false

func configure(chassis_body: Node3D, steering_fork: Node3D) -> void:
	if _built:
		return
	_chassis = chassis_body
	_fork = steering_fork
	name = "GearedMotocrossRider"
	_pelvis = _loft(self, Vector2(0.155, 0.112), Vector2(0.145, 0.105), 0.19, NAVY)
	_torso = Node3D.new()
	_torso.name = "JerseyAndChestProtector"
	add_child(_torso)
	_loft(_torso, Vector2(0.152, 0.115), Vector2(0.207, 0.12), 0.43, BLUE)
	# Flexible chest/back protectors and a contrast race jersey create a human
	# silhouette without turning the rider into a rectangular mannequin.
	var protector := _loft(_torso, Vector2(0.121, 0.018), Vector2(0.16, 0.025), 0.29, NAVY)
	protector.position = Vector3(0, 0.035, -0.116)
	var back := _loft(_torso, Vector2(0.12, 0.018), Vector2(0.145, 0.024), 0.28, NAVY)
	back.position = Vector3(0, 0.035, 0.118)
	for side in [-1.0, 1.0]:
		var stripe := _box(_torso, Vector3(0.065, 0.20, 0.012), Vector3(side * 0.13, -0.065, -0.126), ORANGE)
		stripe.rotation.z = side * 0.16
	var back_number := _label(_torso, "DIRTLINE\n21", Vector3(0, 0.052, 0.149), WHITE, 31, 0.0022)
	back_number.name = "OriginalTeamJersey"
	var chest_number := _label(_torso, "DL / 21", Vector3(0, 0.07, -0.151), WHITE, 23, 0.0019)
	chest_number.rotation.y = PI
	_neck = _link(self, 0.051, 0.052, WHITE)
	_head = Node3D.new()
	_head.name = "FullFaceMXHelmet"
	add_child(_head)
	_helmet_shell = _ellipsoid(_head, Vector3(0.159, 0.169, 0.155), Vector3.ZERO, WHITE)
	# Off-road helmet: extended peak, chin bar, rear shell, goggle aperture,
	# strap, lens, vents and brow accents. No face sphere protrudes through it.
	var chin := _loft(_head, Vector2(0.10, 0.055), Vector2(0.145, 0.065), 0.11, WHITE)
	chin.position = Vector3(0, -0.104, -0.129)
	chin.rotation.x = -0.22
	_box(_head, Vector3(0.125, 0.034, 0.016), Vector3(0, -0.104, -0.205), BLACK)
	var peak := _box(_head, Vector3(0.326, 0.018, 0.255), Vector3(0, 0.111, -0.117), ORANGE)
	peak.rotation.x = -0.10
	_box(_head, Vector3(0.277, 0.024, 0.087), Vector3(0, 0.108, -0.062), NAVY)
	var goggle_frame := _ellipsoid(_head, Vector3(0.143, 0.065, 0.021), Vector3(0, 0.002, -0.152), BLACK)
	goggle_frame.name = "GoggleFrame"
	var lens := _ellipsoid(_head, Vector3(0.126, 0.048, 0.013), Vector3(0, 0.003, -0.172), Color("b3894c"))
	lens.material_override = _material(Color("b3894c"), 0.18, 0.55)
	for side in [-1.0, 1.0]:
		var strap := _box(_head, Vector3(0.015, 0.033, 0.161), Vector3(side * 0.155, 0, -0.004), NAVY)
		strap.rotation.y = side * -0.11
		_box(_head, Vector3(0.012, 0.030, 0.052), Vector3(side * 0.16, -0.025, 0.013), ORANGE)
		var vent := _box(_head, Vector3(0.037, 0.013, 0.07), Vector3(side * 0.084, 0.146, 0.01), BLACK)
		vent.rotation.z = side * -0.35
		var brow := _box(_head, Vector3(0.10, 0.014, 0.01), Vector3(side * 0.088, 0.060, -0.153), ORANGE)
		brow.rotation.z = side * 0.1
	head_anchor = Node3D.new()
	head_anchor.name = "RiderEyeCameraAnchor"
	_head.add_child(head_anchor)
	# A 12 cm rear helmet-camera offset improves near-field framing. It moves
	# only the owner's camera; the rider's physical mass and pose stay unchanged.
	head_anchor.position = Vector3(0, 0.005, 0.018)
	for side in [-1.0, 1.0]:
		_upper_arms.append(_link(self, 0.071, 0.057, BLUE))
		_forearms.append(_link(self, 0.057, 0.043, BLUE))
		_elbows.append(_ellipsoid(self, Vector3(0.065, 0.072, 0.067), Vector3.ZERO, NAVY))
		_shoulders.append(_ellipsoid(self, Vector3(0.081, 0.088, 0.089), Vector3.ZERO, BLUE))
		var glove := Node3D.new()
		glove.name = "LeftGlove" if side < 0 else "RightGlove"
		add_child(glove)
		_ellipsoid(glove, Vector3(0.058, 0.035, 0.057), Vector3.ZERO, BLACK)
		_box(glove, Vector3(0.077, 0.014, 0.060), Vector3(0, 0.033, 0), ORANGE)
		_box(glove, Vector3(0.014, 0.027, 0.069), Vector3(side * -0.038, -0.02, -0.016), BLACK)
		_gloves.append(glove)
		_thighs.append(_link(self, 0.094, 0.078, NAVY))
		_shins.append(_link(self, 0.073, 0.055, NAVY))
		var knee := Node3D.new()
		knee.name = "ProtectiveKneePanel"
		add_child(knee)
		_ellipsoid(knee, Vector3(0.079, 0.092, 0.081), Vector3.ZERO, NAVY)
		_ellipsoid(knee, Vector3(0.062, 0.066, 0.021), Vector3(0, -0.005, -0.069), ORANGE)
		_knees.append(knee)
		var boot := Node3D.new()
		boot.name = "LeftMXBoot" if side < 0 else "RightMXBoot"
		add_child(boot)
		_loft(boot, Vector2(0.057, 0.052), Vector2(0.064, 0.063), 0.275, WHITE).position.y = 0.082
		var boot_toe := _ellipsoid(boot, Vector3(0.065, 0.066, 0.128), Vector3(0, -0.065, -0.067), WHITE)
		boot_toe.rotation.x = -0.06
		_box(boot, Vector3(0.134, 0.025, 0.277), Vector3(0, -0.118, -0.061), BLACK)
		_box(boot, Vector3(0.094, 0.155, 0.013), Vector3(0, 0.080, -0.068), NAVY)
		for buckle in range(3):
			_box(boot, Vector3(0.018, 0.019, 0.088), Vector3(side * 0.066, 0.142 - buckle * 0.063, -0.008), SILVER)
			_box(boot, Vector3(0.110, 0.017, 0.013), Vector3(0, 0.142 - buckle * 0.063, -0.073), BLACK)
		_boots.append(boot)
	_built = true
	update_pose(0, 0, 0, 0, true)

func update_pose(body_forward: float, body_side: float, lean: float, standing: float, feet_down: bool) -> void:
	if not _built:
		return
	var stand := clampf(standing, 0, 1)
	var lateral := body_side * 0.20 + lean * 0.115
	var fore_aft := body_forward * -0.23
	var hip := Vector3(lateral * 0.60, lerpf(0.335, 0.575, stand), 0.20 + fore_aft * 0.42)
	var shoulder_center := Vector3(lateral, lerpf(0.804, 0.992, stand), lerpf(-0.052, -0.154, stand) + fore_aft)
	var spine := shoulder_center - hip
	_pelvis.position = hip
	_pelvis.rotation = Vector3(-body_forward * 0.13, 0, -lean * 0.15)
	_torso.position = hip + spine * 0.50
	_torso.basis = _basis_along(spine)
	# The torso has a fixed anatomical length; hip and shoulder movement use
	# human posture, with hands/feet solved separately to physical contact points.
	var neck_base := shoulder_center + Vector3(0, 0.032, 0.012)
	var neck_top := shoulder_center + Vector3(0, 0.095, -0.008)
	_set_link(_neck, neck_base, neck_top)
	_head.position = shoulder_center + Vector3(0, 0.224, -0.036)
	_head.rotation = Vector3(-body_forward * 0.10, 0, -lean * 0.11)
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var shoulder := shoulder_center + _torso.basis.x * side * 0.196
		var hand_world := _fork.global_transform * Vector3(side * 0.355, 0.140, -0.025)
		var hand := _chassis.global_transform.affine_inverse() * hand_world
		var elbow := _two_bone(shoulder, hand, 0.303, 0.289, Vector3(side * 0.70, -0.25, 0.55))
		_shoulders[i].position = shoulder
		_set_link(_upper_arms[i], shoulder, elbow)
		_set_link(_forearms[i], elbow, hand)
		_elbows[i].position = elbow
		_gloves[i].position = hand
		_gloves[i].basis = _chassis.global_basis.inverse() * _fork.global_basis
		var hip_side := hip + Vector3(side * 0.124, -0.005, 0)
		var boot_position := Vector3(side * 0.245, -0.202, 0.087)
		if feet_down:
			boot_position = Vector3(side * 0.340, -0.635, 0.020)
		var ankle := boot_position + Vector3(0, 0.022, 0.014)
		var knee := _two_bone(hip_side, ankle, 0.450, 0.443, Vector3(side * 0.40, 0.01, -1.0))
		_set_link(_thighs[i], hip_side, knee)
		_set_link(_shins[i], knee, ankle)
		_knees[i].position = knee
		_knees[i].rotation.x = 0.08 - stand * 0.2
		_boots[i].position = boot_position
		_boots[i].rotation = Vector3(0, side * -0.065, side * -0.06 if feet_down else 0.0)

func get_camera_transform() -> Transform3D:
	return head_anchor.global_transform if _built else global_transform

func set_first_person(enabled: bool) -> void:
	_first_person = enabled
	if not _built:
		return
	# The owner sees the real forearms, gloves and handlebar without intersecting
	# the inside of their own helmet/chest. Other rider views retain all gear.
	_head.visible = not enabled
	_torso.visible = not enabled
	_neck.visible = not enabled
	for shoulder in _shoulders:
		shoulder.visible = not enabled
	for upper_arm in _upper_arms:
		upper_arm.visible = not enabled

func _two_bone(root: Vector3, target: Vector3, upper: float, lower: float, bend: Vector3) -> Vector3:
	var delta := target - root
	var distance := clampf(delta.length(), 0.005, upper + lower - 0.0005)
	var direction := delta.normalized()
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var outward := bend - direction * bend.dot(direction)
	if outward.length_squared() < 0.00001:
		outward = Vector3.RIGHT - direction * direction.x
	var offset := sqrt(maxf(0, upper * upper - along * along))
	return root + direction * along + outward.normalized() * offset

func _basis_along(delta: Vector3) -> Basis:
	var up := delta.normalized()
	var forward := Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	if forward.length_squared() < 0.00001:
		forward = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	var right := up.cross(-forward.normalized()).normalized()
	return Basis(right, up, right.cross(up)).orthonormalized()

func _set_link(mesh: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	mesh.position = (a + b) * 0.5
	mesh.basis = _basis_along(b - a)
	# Reuse one metre cylinder meshes. Rebuilding their surfaces at 240 Hz
	# would spend simulation time on a purely visual articulation.
	mesh.scale.y = maxf(0.001, a.distance_to(b))

func _material(color: Color, roughness: float = 0.74, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _mesh(parent: Node3D, mesh: Mesh, origin: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = origin
	node.material_override = _material(color)
	parent.add_child(node)
	return node

func _box(parent: Node3D, size: Vector3, origin: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, origin, color)

func _ellipsoid(parent: Node3D, size: Vector3, origin: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var node := _mesh(parent, mesh, origin, color)
	node.scale = size
	return node

func _link(parent: Node3D, upper_radius: float, lower_radius: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = lower_radius
	mesh.bottom_radius = upper_radius
	mesh.height = 1.0
	mesh.radial_segments = 16
	return _mesh(parent, mesh, Vector3.ZERO, color)

func _loft(parent: Node3D, bottom: Vector2, top: Vector2, height: float, color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 20
	for n in range(segments):
		var angle_a := TAU * n / float(segments)
		var angle_b := TAU * (n + 1) / float(segments)
		var a := Vector3(sin(angle_a) * bottom.x, -height * 0.5, cos(angle_a) * bottom.y)
		var b := Vector3(sin(angle_b) * bottom.x, -height * 0.5, cos(angle_b) * bottom.y)
		var c := Vector3(sin(angle_a) * top.x, height * 0.5, cos(angle_a) * top.y)
		var d := Vector3(sin(angle_b) * top.x, height * 0.5, cos(angle_b) * top.y)
		for vertex in [a, c, b, b, c, d]:
			surface.add_vertex(vertex)
		for vertex in [Vector3(0, -height * 0.5, 0), a, b,
			Vector3(0, height * 0.5, 0), d, c]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	return _mesh(parent, surface.commit(), Vector3.ZERO, color)

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
