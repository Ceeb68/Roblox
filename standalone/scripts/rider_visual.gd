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
var _compression_pose: float = 0.0
var _acceleration_pose: float = 0.0

const SEATED_HIP := Vector3(0.0, 0.408, 0.170)
const SUPPORT_HIP := Vector3(0.0, 0.325, 0.165)
const TORSO_LENGTH := 0.445

func configure(chassis_body: Node3D, steering_fork: Node3D) -> void:
	if _built:
		return
	_chassis = chassis_body
	_fork = steering_fork
	name = "GearedMotocrossRider"
	_pelvis = _garment(self, [Vector2(0.142, 0.096), Vector2(0.158, 0.116),
		Vector2(0.153, 0.111), Vector2(0.145, 0.104)], 0.19, NAVY)
	_torso = Node3D.new()
	_torso.name = "JerseyAndChestProtector"
	add_child(_torso)
	_garment(_torso, [Vector2(0.145, 0.103), Vector2(0.156, 0.112),
		Vector2(0.183, 0.126), Vector2(0.208, 0.123), Vector2(0.182, 0.099)], TORSO_LENGTH, BLUE)
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
	_neck = _link(self, 0.051, 0.052, NAVY)
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
	_helmet_peak(_head)
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
		_upper_arms.append(_limb(self, 0.073, 0.051, BLUE))
		_forearms.append(_limb(self, 0.054, 0.036, BLUE))
		_elbows.append(_ellipsoid(self, Vector3(0.056, 0.061, 0.060), Vector3.ZERO, NAVY))
		_shoulders.append(_ellipsoid(self, Vector3(0.078, 0.077, 0.080), Vector3.ZERO, BLUE))
		var glove := Node3D.new()
		glove.name = "LeftGlove" if side < 0 else "RightGlove"
		add_child(glove)
		_ellipsoid(glove, Vector3(0.058, 0.035, 0.057), Vector3.ZERO, BLACK)
		_box(glove, Vector3(0.077, 0.014, 0.060), Vector3(0, 0.033, 0), ORANGE)
		_box(glove, Vector3(0.014, 0.027, 0.069), Vector3(side * -0.038, -0.02, -0.016), BLACK)
		_gloves.append(glove)
		_thighs.append(_limb(self, 0.096, 0.069, NAVY, 1.13))
		_shins.append(_limb(self, 0.075, 0.048, NAVY, 1.08))
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

func update_pose(body_forward: float, body_side: float, lean: float, standing: float,
		feet_down: bool, riding_state: Dictionary = {}) -> void:
	if not _built:
		return
	# Deployed boots are a relaxed seated support stance. A rider cannot stand
	# on the pegs and place both feet on the ground at the same time. The manual
	# control remains untouched; this is the presentation of that support state.
	var stand := 0.0 if feet_down else clampf(standing, 0, 1)
	var physical_motion = _physical_rider_motion(riding_state)
	var follows_physical_body := physical_motion is Transform3D
	var dt := clampf(float(riding_state.get("dt", 1.0 / 240.0)), 0.0, 0.1)
	var compression := clampf(float(riding_state.get("suspension_compression", 0.18)), 0, 1)
	var acceleration := clampf(float(riding_state.get("forward_acceleration", 0.0)), -10, 10)
	if bool(riding_state.get("pose_reset", false)) or follows_physical_body:
		# Native rider compliance already supplies this relative movement.
		# Adding an animated suspension/inertial displacement would count it twice.
		_compression_pose = 0.0
		_acceleration_pose = 0.0
	else:
		# Flexible knees and elbows absorb chassis movement; the visual posture
		# never supplies a chassis force or overrides the player's body inputs.
		_compression_pose = lerpf(_compression_pose, clampf((compression - 0.18) * 0.15,
			-0.027, 0.10), 1.0 - exp(-dt / 0.085))
		_acceleration_pose = lerpf(_acceleration_pose, acceleration, 1.0 - exp(-dt / 0.18))
	var lateral := clampf(body_side, -1, 1) * 0.19 + clampf(lean, -1, 1) * 0.105
	var fore_aft := clampf(body_forward, -1, 1) * -0.22
	var flexion := _compression_pose * lerpf(0.25, 1.0, stand)
	var reaction_shift := -_acceleration_pose * 0.0045
	var hip_origin := SUPPORT_HIP if feet_down else SEATED_HIP
	var hip := hip_origin + Vector3(lateral * 0.57, stand * 0.225 - flexion,
		-stand * 0.027 + fore_aft * 0.34 + reaction_shift * 0.40)
	if feet_down:
		# Both planted boots constrain pelvis height. Let the support stance
		# crouch a little during body movement instead of lengthening a shin.
		for side in [-1.0, 1.0]:
			var hip_joint := hip + Vector3(side * 0.124, -0.005, 0)
			var ankle := Vector3(side * 0.340, -0.613, 0.034)
			var horizontal_distance_squared := Vector2(hip_joint.x - ankle.x,
				hip_joint.z - ankle.z).length_squared()
			var available_height := sqrt(maxf(0.0, 0.951 * 0.951 - horizontal_distance_squared))
			hip.y = minf(hip.y, ankle.y + available_height + 0.005)
	# A motocross attack stance hinges at the hips instead of raising an erect
	# torso above the seat. The spine retains its anatomical length in every pose.
	var hip_hinge := (deg_to_rad(38.0 + stand * 10.0) + body_forward * 0.13
		+ flexion * 0.65 + _acceleration_pose * 0.003)
	var spine := Vector3(lateral * 0.43, cos(hip_hinge), -sin(hip_hinge)).normalized() * TORSO_LENGTH
	var shoulder_center := hip + spine + Vector3(0, 0, fore_aft * 0.38 + reaction_shift)
	# Body inputs shift the whole articulated pose while hands and feet continue
	# to touch the moving motorcycle. Small dynamic bracing remains visual only.
	spine = (shoulder_center - hip).normalized() * TORSO_LENGTH
	shoulder_center = hip + spine
	var anatomy_frame := Basis.IDENTITY
	var spine_reference := _basis_along(spine)
	if follows_physical_body:
		# Keep the anatomical input posture, then add the actual body's deviation
		# from its requested COM/orientation. Hands and boots remain bike contacts.
		anatomy_frame = physical_motion.basis
		hip = physical_motion * hip
		shoulder_center = physical_motion * shoulder_center
		spine_reference = anatomy_frame * spine_reference
		# The simulated body is an aggregate human mass. Its capsule can briefly
		# move beyond a planted leg's reach, so crouch the visual pelvis rather
		# than lengthening a shin or making a supporting boot float off the ground.
		for side in [-1.0, 1.0]:
			var hip_offset := anatomy_frame * Vector3(side * 0.124, -0.005, 0)
			var ankle := Vector3(side * 0.245, -0.079, 0.101)
			if feet_down:
				ankle = Vector3(side * 0.340, -0.613, 0.034)
			var horizontal_distance_squared := Vector2(hip.x + hip_offset.x - ankle.x,
				hip.z + hip_offset.z - ankle.z).length_squared()
			var available_height := sqrt(maxf(0.0, 0.951 * 0.951 - horizontal_distance_squared))
			hip.y = minf(hip.y, ankle.y + available_height - hip_offset.y)
		spine = (shoulder_center - hip).normalized() * TORSO_LENGTH
		shoulder_center = hip + spine
	var hands: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		hands.append(_chassis.global_transform.affine_inverse() *
			(_fork.global_transform * Vector3(side * 0.355, 0.140, -0.025)))
	# At extreme side/back inputs the torso flexes toward the bars rather than
	# stretching the far arm. This is a constrained anatomical visual solve.
	for iteration in range(8):
		var shoulder_basis := _spine_basis(spine, spine_reference)
		var reach_adjustment := Vector3.ZERO
		for i in range(2):
			var side := -1.0 if i == 0 else 1.0
			var shoulder := shoulder_center + shoulder_basis.x * side * 0.194
			var reach := shoulder.distance_to(hands[i])
			if reach > 0.586:
				reach_adjustment += (hands[i] - shoulder).normalized() * (reach - 0.586)
		if reach_adjustment.length_squared() < 0.0000001:
			break
		spine = (shoulder_center + reach_adjustment - hip).normalized() * TORSO_LENGTH
		shoulder_center = hip + spine
	_pelvis.position = hip
	_pelvis.basis = anatomy_frame * Basis.from_euler(Vector3(-body_forward * 0.13, 0, -lean * 0.15))
	_torso.position = hip + spine * 0.50
	_torso.basis = _spine_basis(spine, spine_reference)
	# The torso has a fixed anatomical length; hip and shoulder movement use
	# human posture, with hands/feet solved separately to physical contact points.
	var neck_base := shoulder_center + anatomy_frame * Vector3(0, 0.025, 0.009)
	var neck_top := shoulder_center + anatomy_frame * Vector3(0, 0.096, -0.025)
	_set_link(_neck, neck_base, neck_top)
	_head.position = shoulder_center + anatomy_frame * Vector3(0, 0.211, -0.049)
	_head.basis = anatomy_frame * Basis.from_euler(Vector3(-body_forward * 0.12
		- _acceleration_pose * 0.002, 0, -lean * 0.11))
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var shoulder := shoulder_center + _torso.basis.x * side * 0.194
		var hand: Vector3 = hands[i]
		# Raised elbows, relaxed forearms and a wide grip produce the recognisable
		# attack stance. The pole points out/up; it never pulls an elbow behind the rider.
		var elbow := _two_bone(shoulder, hand, 0.303, 0.289,
			anatomy_frame * Vector3(side * 0.95, 0.70 + stand * 0.15, -0.06))
		_shoulders[i].position = shoulder
		_set_link(_upper_arms[i], shoulder, elbow)
		_set_link(_forearms[i], elbow, hand)
		_elbows[i].position = elbow
		_gloves[i].position = hand
		_gloves[i].basis = _chassis.global_basis.inverse() * _fork.global_basis
		var hip_side := hip + anatomy_frame * Vector3(side * 0.124, -0.005, 0)
		# Boot origins are at the ankle; the sole extends 13 cm below the origin.
		# Align the sole with the real peg top, not the ankle with the peg itself.
		var boot_position := Vector3(side * 0.245, -0.101, 0.087)
		if feet_down:
			boot_position = Vector3(side * 0.340, -0.635, 0.020)
		var ankle := boot_position + Vector3(0, 0.022, 0.014)
		# Knees point toward the shrouds and grip the bike rather than spreading
		# outside the ankles. In standing poses the remaining leg bend takes bumps.
		var knee := _two_bone(hip_side, ankle, 0.480, 0.475,
			anatomy_frame * Vector3(side * 0.07, 0.01, -1.0))
		_set_link(_thighs[i], hip_side, knee)
		# Riding pants tuck into the tall protective boot. Extending the trouser
		# mesh to the ankle hides the cuff and makes an MX boot read like a sneaker.
		var boot_cuff := boot_position + Vector3(0, 0.193, -0.012)
		_set_link(_shins[i], knee, boot_cuff)
		_knees[i].position = knee
		_knees[i].basis = _basis_along(hip_side - knee)
		_boots[i].position = boot_position
		_boots[i].rotation = Vector3(0, side * -0.065, side * -0.06 if feet_down else 0.0)

func _physical_rider_motion(riding_state: Dictionary) -> Variant:
	var actual = riding_state.get("rider_transform")
	var reference = riding_state.get("rider_reference_transform")
	if not actual is Transform3D or not reference is Transform3D:
		return null
	if (not actual.origin.is_finite() or not actual.basis.is_finite()
			or not reference.origin.is_finite() or not reference.basis.is_finite()
			or absf(actual.basis.determinant()) < 0.00001
			or absf(reference.basis.determinant()) < 0.00001):
		return null
	var motion: Transform3D = actual * reference.affine_inverse()
	if not motion.origin.is_finite() or not motion.basis.is_finite():
		return null
	motion.basis = motion.basis.orthonormalized()
	return motion

func _spine_basis(spine: Vector3, reference: Basis) -> Basis:
	# Preserve actual rider yaw/twist as the spine flexes toward the handlebars.
	var up := spine.normalized()
	var right := reference.x - up * reference.x.dot(up)
	if right.length_squared() < 0.000001:
		return _basis_along(spine)
	right = right.normalized()
	return Basis(right, up, right.cross(up)).orthonormalized()

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

func _limb(parent: Node3D, upper_radius: float, lower_radius: float,
		color: Color, depth_ratio: float = 1.0) -> MeshInstance3D:
	# Soft fabric follows muscles and narrows into gloves/boots; cylinders with
	# constant-radius ends make an articulated rider read like a wooden mannequin.
	var profile: Array[Vector2] = []
	var roundness := [0.54, 0.88, 1.03, 1.00, 0.93, 0.73, 0.44]
	for i in range(roundness.size()):
		var radius := lerpf(upper_radius, lower_radius, float(i) / (roundness.size() - 1)) * float(roundness[i])
		profile.append(Vector2(radius, radius * depth_ratio))
	return _garment(parent, profile, 1.0, color)

func _garment(parent: Node3D, profile: Array, height: float,
		color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	var segments := 24
	for ring in range(profile.size() - 1):
		var bottom: Vector2 = profile[ring]
		var top: Vector2 = profile[ring + 1]
		var bottom_y := height * (float(ring) / (profile.size() - 1) - 0.5)
		var top_y := height * (float(ring + 1) / (profile.size() - 1) - 0.5)
		for n in range(segments):
			var a_angle := TAU * n / float(segments)
			var b_angle := TAU * (n + 1) / float(segments)
			var a := Vector3(sin(a_angle) * bottom.x, bottom_y, cos(a_angle) * bottom.y)
			var b := Vector3(sin(b_angle) * bottom.x, bottom_y, cos(b_angle) * bottom.y)
			var c := Vector3(sin(a_angle) * top.x, top_y, cos(a_angle) * top.y)
			var d := Vector3(sin(b_angle) * top.x, top_y, cos(b_angle) * top.y)
			for vertex in [a, c, b, b, c, d]:
				surface.add_vertex(vertex)
	# The caps disappear beneath joints, but closing them prevents silhouettes
	# revealing hollow sleeves as the elbows and knees flex.
	surface.set_smooth_group(-1)
	for ring in [0, profile.size() - 1]:
		var size: Vector2 = profile[ring]
		var y := height * (float(ring) / (profile.size() - 1) - 0.5)
		for n in range(segments):
			var a_angle := TAU * n / float(segments)
			var b_angle := TAU * (n + 1) / float(segments)
			var a := Vector3(sin(a_angle) * size.x, y, cos(a_angle) * size.y)
			var b := Vector3(sin(b_angle) * size.x, y, cos(b_angle) * size.y)
			for vertex in [Vector3(0, y, 0), a if ring == 0 else b, b if ring == 0 else a]:
				surface.add_vertex(vertex)
	surface.index()
	surface.generate_normals()
	return _mesh(parent, surface.commit(), Vector3.ZERO, color)

func _helmet_peak(parent: Node3D) -> MeshInstance3D:
	# Tapered off-road visor with a raised brow and a dropped front lip.
	var outline := [Vector3(-0.130, 0.124, -0.014), Vector3(0.130, 0.124, -0.014),
		Vector3(0.164, 0.125, -0.114), Vector3(0.115, 0.106, -0.262),
		Vector3(-0.115, 0.106, -0.262), Vector3(-0.164, 0.125, -0.114)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.135, -0.123)
	var thickness := Vector3(0, -0.012, 0)
	for n in range(outline.size()):
		var a: Vector3 = outline[n]
		var b: Vector3 = outline[(n + 1) % outline.size()]
		for vertex in [center, a, b, center + thickness, b + thickness, a + thickness,
			a, a + thickness, b, b, a + thickness, b + thickness]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	return _mesh(parent, surface.commit(), Vector3.ZERO, ORANGE)

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
