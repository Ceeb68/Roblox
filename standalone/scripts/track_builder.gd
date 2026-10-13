class_name DLTrackBuilder
extends RefCounted
## Original procedural motocross proving ground. Coordinates and dimensions are metres.
## Wheel contacts use the native static triangle collision; tyre friction is supplied
## by the motorcycle model, so the terrain's native friction deliberately stays zero.

const ROAD_HALF_WIDTH := 4.0
const SHOULDER_WIDTH := 2.0
const GROUND_HEIGHT := -0.24
const ROAD_HEIGHT := 0.04
const LOOP_RADIUS := 20.0
const DIRT := Color(0.43, 0.29, 0.16)
const GRASS := Color(0.22, 0.31, 0.12)
const SAND := Color(0.69, 0.57, 0.35)
const MUD := Color(0.23, 0.18, 0.13)
const HARDPACK := Color(0.54, 0.43, 0.29)
const LOAM := Color(0.32, 0.23, 0.15)
const INK := Color(0.075, 0.105, 0.12)
const ORANGE := Color(1.0, 0.38, 0.075)
const CREAM := Color(0.92, 0.9, 0.79)


static func build(parent: Node3D) -> Dictionary:
	var world := Node3D.new()
	world.name = "DirtlineProvingGround"
	parent.add_child(world)
	_box_surface(world, "GrassBase", Vector3(0.0, GROUND_HEIGHT - 0.5, 0.0),
		Vector3(232.0, 1.0, 216.0), "grass", GRASS)
	_build_main_ribbon(world)
	_build_large_jump(world)
	_build_traction_pads(world)
	_build_pit(world)
	_build_scenery(world)
	var gates: Array = []
	gates.append(_gate(world, 0, Vector3(-22.0, ROAD_HEIGHT, 19.0), Vector3.FORWARD, "START / FINISH"))
	gates.append(_gate(world, 1, Vector3(-22.0, ROAD_HEIGHT, -24.0), Vector3.FORWARD, "NORTH STRAIGHT"))
	gates.append(_gate(world, 2, Vector3(4.0, ROAD_HEIGHT, -47.0), Vector3.RIGHT, "SAND TURN"))
	gates.append(_gate(world, 3, Vector3(30.0, ROAD_HEIGHT, -24.0), Vector3.BACK, "RUT CHANNELS"))
	gates.append(_gate(world, 4, Vector3(30.0, ROAD_HEIGHT, -8.0), Vector3.BACK, "TABLETOP APPROACH"))
	gates.append(_gate(world, 5, Vector3(30.0, ROAD_HEIGHT, 23.0), Vector3.BACK, "LANDING EXIT"))
	gates.append(_gate(world, 6, Vector3(4.0, ROAD_HEIGHT, 47.0), Vector3.LEFT, "TRACTION STRAIGHT"))
	var last_angle := deg_to_rad(157.5)
	var last_position := Vector3(-2.0 + 20.0 * cos(last_angle), ROAD_HEIGHT + _corner_bank(0.75) * 4.0,
		27.0 + 20.0 * sin(last_angle))
	gates.append(_gate(world, 7, last_position, Vector3(-sin(last_angle), 0.0, cos(last_angle)), "SOUTH BERM"))
	var stations: Array = [
		_station(world, "01 / BRAKING BUMPS", "0.12–0.22 m • independent brakes", Vector3(-30.5, 0.0, 14.0), 0.0),
		_station(world, "02 / WHOOPS", "0.45 m • 4 m spacing • rider position", Vector3(-30.5, 0.0, -7.0), 0.0),
		_station(world, "03 / BANKED BERMS", "20 m radius • progressive 15° banking", Vector3(-12.0, 0.0, -35.0), PI),
		_station(world, "04 / RUT CHANNELS", "0.16 m deep • 1.5 m separation", Vector3(20.8, 0.0, -22.0), PI),
		_station(world, "05 / TABLETOP", "1.3 m high • 10 m deck • 12 m landing", Vector3(19.0, 0.0, 4.0), PI),
		_station(world, "06 / LARGE JUMP", "2.6 m lip • 18 m run-up • 20 m landing", Vector3(47.0, 0.0, -24.0), 0.0),
		_station(world, "07 / TRACTION PADS", "HARDPACK / SAND / MUD / LOAM", Vector3(0.0, 0.0, 27.0), 0.0),
	]
	return {"spawn": Transform3D(Basis.IDENTITY, Vector3(-22.0, 0.95, 22.0)),
		"gates": gates, "stations": stations}


static func _build_main_ribbon(parent: Node3D) -> void:
	# Shared rows keep the collision continuous across changes of material and
	# obstacles. One indexed mesh/concave collider per surface, not stacked boxes.
	var rows: Array = []
	_add_line(rows, Vector2(-22.0, 27.0), Vector2(-22.0, -27.0), 68)
	_add_arc(rows, Vector2(-2.0, -27.0), PI, PI * 1.5, 40)
	_add_line(rows, Vector2(-2.0, -47.0), Vector2(10.0, -47.0), 16)
	_add_arc(rows, Vector2(10.0, -27.0), -PI * 0.5, 0.0, 40)
	_add_line(rows, Vector2(30.0, -27.0), Vector2(30.0, 27.0), 90)
	_add_arc(rows, Vector2(10.0, 27.0), 0.0, PI * 0.5, 40)
	_add_line(rows, Vector2(10.0, 47.0), Vector2(-2.0, 47.0), 16)
	_add_arc(rows, Vector2(-2.0, 27.0), PI * 0.5, PI, 40)
	rows.append(rows[0])
	var builders: Dictionary = {}
	for surface in ["dirt", "sand", "mud", "hardpack", "loam"]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_smooth_group(0)
		builders[surface] = tool
	# Quarter-metre columns include both 0.75 m rut centres. Coarser sampling
	# would silently flatten the 0.16 m grooves before native collision.
	const COLUMNS := 48
	for row_index in range(rows.size() - 1):
		var first: Dictionary = rows[row_index]
		var second: Dictionary = rows[row_index + 1]
		var midpoint: Vector2 = (first.center + second.center) * 0.5
		var surface := _main_surface(midpoint)
		var tool: SurfaceTool = builders[surface]
		for column in range(COLUMNS):
			var u0 := lerpf(-6.0, 6.0, float(column) / COLUMNS)
			var u1 := lerpf(-6.0, 6.0, float(column + 1) / COLUMNS)
			var a := _ribbon_vertex(first, u0)
			var b := _ribbon_vertex(first, u1)
			var c := _ribbon_vertex(second, u0)
			var d := _ribbon_vertex(second, u1)
			# _triangle emits clockwise front faces for Godot's native triangle shape.
			_triangle(tool, a, b, c, surface, u0, u1, u0)
			_triangle(tool, b, d, c, surface, u1, u1, u0)
	for surface: String in builders:
		_finish_surface(parent, "Circuit_" + surface, builders[surface], surface)


static func _add_line(rows: Array, start: Vector2, finish: Vector2, steps: int) -> void:
	var direction := (finish - start).normalized()
	for index in range(steps):
		rows.append({"center": start.lerp(finish, float(index) / steps), "direction": direction, "bank": 0.0})


static func _add_arc(rows: Array, center: Vector2, start: float, finish: float, steps: int) -> void:
	for index in range(steps):
		var t := float(index) / steps
		var angle := lerpf(start, finish, t)
		rows.append({"center": center + Vector2(cos(angle), sin(angle)) * LOOP_RADIUS,
			"direction": Vector2(-sin(angle), cos(angle)), "bank": _corner_bank(t)})


static func _corner_bank(t: float) -> float:
	# Banking grows smoothly from zero at each tangent joint. It is geometry,
	# never a force or scripted steering assistance.
	return tan(deg_to_rad(15.0)) * pow(sin(PI * t), 2.0)


static func _ribbon_vertex(row: Dictionary, lateral: float) -> Vector3:
	var center: Vector2 = row.center
	var forward: Vector2 = row.direction
	var right := Vector2(-forward.y, forward.x)
	var position := center + right * lateral
	var shoulder := _smoothstep(ROAD_HALF_WIDTH, ROAD_HALF_WIDTH + SHOULDER_WIDTH, absf(lateral))
	var height := ROAD_HEIGHT + float(row.bank) * (ROAD_HALF_WIDTH - lateral)
	if is_equal_approx(center.x, -22.0):
		height += _west_obstacle(center.y)
	elif is_equal_approx(center.x, 30.0):
		height += _tabletop_height(center.y)
		var rut_envelope := _window(center.y, -26.0, -17.0, 1.0)
		height -= 0.16 * rut_envelope * maxf(_rut(lateral - 0.75), _rut(lateral + 0.75))
	return Vector3(position.x, lerpf(height, GROUND_HEIGHT, shoulder), position.y)


static func _west_obstacle(z: float) -> float:
	if z >= 10.0 and z <= 18.0:
		var distance := 18.0 - z
		var bump := mini(int(distance / 2.0), 3)
		var heights := [0.12, 0.22, 0.16, 0.18]
		return float(heights[bump]) * (0.5 - 0.5 * cos(TAU * fmod(distance, 2.0) / 2.0))
	if z >= -18.0 and z <= -2.0:
		return 0.45 * (0.5 - 0.5 * cos(TAU * (-2.0 - z) / 4.0))
	return 0.0


static func _tabletop_height(z: float) -> float:
	if z >= -7.0 and z < -1.0:
		# Convex takeoff preserves an upward contact normal/tangent at the lip.
		return 1.3 * pow((z + 7.0) / 6.0, 1.6)
	if z >= -1.0 and z <= 9.0:
		return 1.3
	if z > 9.0 and z < 21.0:
		return 1.3 * (1.0 - _smoothstep(9.0, 21.0, z))
	return 0.0


static func _rut(distance: float) -> float:
	return 0.5 + 0.5 * cos(PI * clampf(absf(distance) / 0.35, 0.0, 1.0))


static func _main_surface(point: Vector2) -> String:
	if point.y < -46.9:
		return "sand"
	if point.y > 46.9:
		return "mud" if point.x > 4.0 else "hardpack"
	if point.x > 29.9 and point.y < -16.5:
		return "loam"
	return "dirt"


static func _build_large_jump(parent: Node3D) -> void:
	# Separate proving lane: 18 m flat run-up, 7 m curved launch, 8 m gap,
	# 20 m landing and 20 m flat runoff. The gap exposes the grass below.
	for section in [{"name": "RunupAndLip", "start": -45.0, "finish": -20.0},
		{"name": "LandingAndRunoff", "start": -12.0, "finish": 28.0}]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_smooth_group(0)
		var steps := int(ceil((float(section.finish) - float(section.start)) / 0.4))
		for index in range(steps):
			var z0 := lerpf(float(section.start), float(section.finish), float(index) / steps)
			var z1 := lerpf(float(section.start), float(section.finish), float(index + 1) / steps)
			for column in range(16):
				var x0 := lerpf(-4.0, 4.0, float(column) / 16.0)
				var x1 := lerpf(-4.0, 4.0, float(column + 1) / 16.0)
				var a := _jump_vertex(x0, z0)
				var b := _jump_vertex(x1, z0)
				var c := _jump_vertex(x0, z1)
				var d := _jump_vertex(x1, z1)
				_triangle(tool, a, c, b, "dirt", x0, x0, x1)
				_triangle(tool, b, c, d, "dirt", x1, x0, x1)
		_finish_surface(parent, "LargeJump_" + str(section.name), tool, "dirt")
	_pole(parent, Vector3(35.8, 0.0, -27.0), 1.0, ORANGE)
	_pole(parent, Vector3(42.2, 0.0, -27.0), 1.0, ORANGE)
	_pole(parent, Vector3(35.8, 0.0, 28.0), 1.0, CREAM)
	_pole(parent, Vector3(42.2, 0.0, 28.0), 1.0, CREAM)
	_label(parent, "LARGE JUMP →", Vector3(39.0, 1.7, -43.0), 0.0, 32, ORANGE)
	_label(parent, "20 m RUNOFF", Vector3(44.0, 1.0, 18.0), 0.0, 25, CREAM)


static func _jump_vertex(lateral: float, z: float) -> Vector3:
	var height := ROAD_HEIGHT
	if z >= -27.0 and z <= -20.0:
		height += 2.6 * pow((z + 27.0) / 7.0, 1.8)
	elif z >= -12.0 and z < 8.0:
		height += 2.1 * (1.0 - _smoothstep(-12.0, 8.0, z))
	var shoulder := _smoothstep(3.0, 4.0, absf(lateral))
	return Vector3(39.0 + lateral, lerpf(height, GROUND_HEIGHT, shoulder), z)


static func _build_traction_pads(parent: Node3D) -> void:
	var pads := [
		{"surface": "hardpack", "position": Vector3(-7.0, 0.0, -11.0), "color": HARDPACK},
		{"surface": "sand", "position": Vector3(7.0, 0.0, -11.0), "color": SAND},
		{"surface": "mud", "position": Vector3(-7.0, 0.0, 11.0), "color": MUD},
		{"surface": "loam", "position": Vector3(7.0, 0.0, 11.0), "color": LOAM},
	]
	for pad in pads:
		var center: Vector3 = pad.position
		var surface: String = pad.surface
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_smooth_group(0)
		for row in range(20):
			for column in range(14):
				var x0 := lerpf(-6.0, 6.0, float(column) / 14.0)
				var x1 := lerpf(-6.0, 6.0, float(column + 1) / 14.0)
				var z0 := lerpf(-9.0, 9.0, float(row) / 20.0)
				var z1 := lerpf(-9.0, 9.0, float(row + 1) / 20.0)
				var a := _pad_vertex(center, x0, z0)
				var b := _pad_vertex(center, x1, z0)
				var c := _pad_vertex(center, x0, z1)
				var d := _pad_vertex(center, x1, z1)
				_triangle(tool, a, c, b, surface, 0.0, 0.0, 0.0)
				_triangle(tool, b, c, d, surface, 0.0, 0.0, 0.0)
		_finish_surface(parent, "TractionPad_" + surface, tool, surface)
		_label(parent, surface.to_upper(), center + Vector3(0.0, 0.45, 8.0), 0.0, 28, CREAM)
		for sign in [-1.0, 1.0]:
			_pole(parent, center + Vector3(sign * 5.0, 0.0, 7.0), 0.65, pad.color)


static func _pad_vertex(center: Vector3, x: float, z: float) -> Vector3:
	var fade := maxf(_smoothstep(4.5, 6.0, absf(x)), _smoothstep(7.5, 9.0, absf(z)))
	return center + Vector3(x, lerpf(0.025, GROUND_HEIGHT, fade), z)


static func _build_pit(parent: Node3D) -> void:
	# Visual service canopy and a small concrete tuning pad. All routes out of
	# the start pad remain clear; native contact is never hidden by scenery.
	_box_surface(parent, "ServicePad", Vector3(-43.0, GROUND_HEIGHT - 0.015, 24.0),
		Vector3(12.0, 0.07, 14.0), "concrete", Color(0.39, 0.42, 0.39))
	for x in [-48.0, -38.0]:
		for z in [19.0, 29.0]:
			_visual_box(parent, Vector3(x, 1.2, z), Vector3(0.1, 3.0, 0.1), INK)
	_visual_box(parent, Vector3(-43.0, 2.8, 24.0), Vector3(12.0, 0.18, 12.0), ORANGE)
	_visual_box(parent, Vector3(-43.0, 0.36, 29.0), Vector3(6.0, 0.65, 0.6), INK)
	_label(parent, "DIRTLINE / MX", Vector3(-43.0, 3.5, 18.0), 0.0, 58, CREAM)
	_label(parent, "250F • PHYSICS LAB", Vector3(-43.0, 2.1, 18.0), 0.0, 29, CREAM)
	_label(parent, "MANUAL CONTROLS · NO RIDING ASSISTS", Vector3(-22.0, 0.6, 25.7), 0.0, 23, CREAM)
	# Start grid paint stays visual; no coplanar physics bodies.
	for index in range(8):
		for row in range(2):
			var stripe_color := CREAM if (index + row) % 2 == 0 else INK
			_visual_box(parent, Vector3(-25.5 + index, ROAD_HEIGHT + 0.005, 19.0 + row * 0.45),
				Vector3(1.0, 0.008, 0.45), stripe_color)
	for z in [22.0, 24.0, 26.0]:
		_visual_box(parent, Vector3(-22.0, ROAD_HEIGHT + 0.005, z), Vector3(2.2, 0.008, 0.08), CREAM)


static func _build_scenery(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2502026
	# Shared MultiMeshes keep the original low-poly forest cheap to render.
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = 2.3
	trunk_mesh.radial_segments = 6
	trunk_mesh.material = _material(Color(0.25, 0.18, 0.12))
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 2.0
	crown_mesh.height = 5.4
	crown_mesh.radial_segments = 7
	crown_mesh.material = _material(Color(0.12, 0.22, 0.13))
	var trees := 100
	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.mesh = trunk_mesh
	trunks.instance_count = trees
	var crowns := MultiMesh.new()
	crowns.transform_format = MultiMesh.TRANSFORM_3D
	crowns.mesh = crown_mesh
	crowns.instance_count = trees
	for index in range(trees):
		var angle := float(index) / trees * TAU + rng.randf_range(-0.04, 0.04)
		var radius := rng.randf_range(65.0, 96.0)
		var location := Vector3(cos(angle) * radius, GROUND_HEIGHT, sin(angle) * radius)
		var scale := rng.randf_range(0.7, 1.45)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale)
		trunks.set_instance_transform(index, Transform3D(basis, location + Vector3.UP * 1.15 * scale))
		crowns.set_instance_transform(index, Transform3D(basis, location + Vector3.UP * 4.2 * scale))
	for entry in [{"name": "PineTrunks", "mesh": trunks}, {"name": "PineCrowns", "mesh": crowns}]:
		var node := MultiMeshInstance3D.new()
		node.name = entry.name
		node.multimesh = entry.mesh
		parent.add_child(node)
	for index in range(11):
		var angle := float(index) / 11.0 * TAU
		var position := Vector3(cos(angle) * 137.0, -4.0, sin(angle) * 127.0)
		_mountain(parent, position, rng.randf_range(27.0, 48.0), rng.randf_range(18.0, 32.0), index)
	# Soft-boundary stake/ribbon fence is scenery, away from the usable shoulder.
	for side in [-1.0, 1.0]:
		for index in range(12):
			var z := -48.0 + index * 9.0
			var x := -34.0 if side < 0.0 else 49.0
			_pole(parent, Vector3(x, GROUND_HEIGHT, z), 0.8, CREAM)
			if index < 11:
				_visual_box(parent, Vector3(x, 0.4, z + 4.5), Vector3(0.035, 0.08, 9.0), ORANGE)
	_visual_box(parent, Vector3(0.0, 2.0, -56.12), Vector3(16.0, 3.0, 0.1), INK)
	for sign in [-1.0, 1.0]:
		_pole(parent, Vector3(sign * 6.0, 0.0, -56.15), 3.4, INK)
	_label(parent, "DIRTLINE", Vector3(0.0, 2.55, -56.0), 0.0, 110, ORANGE)
	_label(parent, "MOTOCROSS PROVING GROUND", Vector3(0.0, 1.45, -56.0), 0.0, 30, CREAM)


static func _mountain(parent: Node3D, location: Vector3, radius: float, height: float, index: int) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in range(7):
		var angle0 := float(side) / 7.0 * TAU
		var angle1 := float(side + 1) / 7.0 * TAU
		var peak := location + Vector3(radius * 0.12, height, 0.0)
		var p0 := location + Vector3(cos(angle0) * radius, 0.0, sin(angle0) * radius)
		var p1 := location + Vector3(cos(angle1) * radius, 0.0, sin(angle1) * radius)
		var color := Color(0.29, 0.34, 0.3).lightened(float((side + index) % 3) * 0.04)
		tool.set_color(color)
		tool.add_vertex(p0)
		tool.add_vertex(p1)
		tool.add_vertex(peak)
	tool.generate_normals()
	var node := MeshInstance3D.new()
	node.name = "Ridge_%02d" % index
	node.mesh = tool.commit()
	node.material_override = _vertex_material()
	parent.add_child(node)


static func _gate(parent: Node3D, index: int, position: Vector3, direction: Vector3, title: String) -> Dictionary:
	var transform := Transform3D(Basis.looking_at(direction, Vector3.UP), position)
	var root := Node3D.new()
	root.name = "Gate_%02d" % index
	root.transform = transform
	parent.add_child(root)
	for sign in [-1.0, 1.0]:
		_pole(root, Vector3(sign * 4.9, 0.0, 0.0), 3.95 if index == 0 else 2.5, ORANGE if index == 0 else CREAM)
		_visual_box(root, Vector3(sign * 4.9, 1.85, 0.0), Vector3(0.42, 0.65, 0.08), INK)
		_label(root, "%02d" % (index + 1), Vector3(sign * 4.9, 1.88, 0.07), 0.0, 30, CREAM)
	if index == 0:
		_visual_box(root, Vector3(0.0, 3.6, 0.0), Vector3(10.1, 0.7, 0.1), INK)
		_label(root, "DIRTLINE  /  START + FINISH", Vector3(0.0, 3.65, 0.07), 0.0, 38, CREAM)
	return {"transform": transform, "width": 8.0, "name": title}


static func _station(parent: Node3D, title: String, detail: String, position: Vector3, yaw: float) -> Dictionary:
	var root := Node3D.new()
	root.name = "Station_" + title.left(2)
	root.position = position
	root.rotation.y = yaw
	parent.add_child(root)
	_visual_box(root, Vector3(0.0, 1.1, 0.0), Vector3(4.8, 1.05, 0.08), INK)
	_visual_box(root, Vector3(0.0, 1.64, 0.0), Vector3(4.8, 0.08, 0.08), ORANGE)
	for sign in [-1.0, 1.0]:
		_visual_box(root, Vector3(sign * 1.9, 0.17, 0.0), Vector3(0.08, 0.94, 0.08), INK)
	_label(root, title, Vector3(0.0, 1.32, 0.065), 0.0, 30, CREAM)
	_label(root, detail, Vector3(0.0, 0.92, 0.065), 0.0, 19, Color(0.69, 0.75, 0.72))
	return {"name": title, "description": detail, "position": position}


static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, surface: String,
		u0: float, u1: float, u2: float) -> void:
	# Godot's clockwise face normal is the negative of the conventional cross
	# product. Reverse the mathematical +Y order for upward native contact.
	var vertices := [a, c, b]
	var laterals := [u0, u2, u1]
	for index in range(3):
		var vertex: Vector3 = vertices[index]
		var color := _surface_color(surface)
		# Deterministic vertex tint gives soil variation without a texture download.
		var variation := sin(vertex.x * 1.7 + vertex.z * 0.63) * 0.035
		color = color.lightened(variation) if variation > 0.0 else color.darkened(-variation)
		if absf(float(laterals[index])) > ROAD_HALF_WIDTH:
			color = color.lerp(GRASS, _smoothstep(4.0, 6.0, absf(float(laterals[index]))))
		tool.set_color(color)
		tool.add_vertex(vertex)


static func _finish_surface(parent: Node3D, title: String, tool: SurfaceTool, surface: String) -> void:
	tool.generate_normals()
	tool.index()
	var mesh := tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var body := StaticBody3D.new()
	body.name = title
	body.set_meta("physics_surface", surface)
	body.physics_material_override = _contact_material()
	parent.add_child(body)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _vertex_material()
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)


static func _box_surface(parent: Node3D, title: String, location: Vector3, dimensions: Vector3,
		surface: String, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = title
	body.position = location
	body.set_meta("physics_surface", surface)
	body.physics_material_override = _contact_material()
	parent.add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = _material(color)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


static func _visual_box(parent: Node3D, location: Vector3, dimensions: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = _material(color)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = location
	parent.add_child(visual)


static func _pole(parent: Node3D, location: Vector3, height: float, color: Color) -> void:
	# Bury the lower 0.3 m so verge-height changes never leave floating posts.
	_visual_box(parent, location + Vector3.UP * (height * 0.5 - 0.15), Vector3(0.12, height + 0.3, 0.12), color)


static func _label(parent: Node3D, words: String, location: Vector3, yaw: float, size: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = words
	label.position = location
	label.rotation.y = yaw
	label.font_size = size
	label.pixel_size = 0.0065
	label.modulate = color
	label.outline_modulate = INK
	label.outline_size = 5
	label.double_sided = true
	label.shaded = false
	parent.add_child(label)


static func _surface_color(surface: String) -> Color:
	match surface:
		"sand": return SAND
		"mud": return MUD
		"hardpack": return HARDPACK
		"loam": return LOAM
		_: return DIRT


static func _contact_material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.rough = false
	material.bounce = 0.0
	return material


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material


static func _vertex_material() -> StandardMaterial3D:
	var material := _material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	return material


static func _window(value: float, start: float, finish: float, blend: float) -> float:
	return _smoothstep(start, start + blend, value) * (1.0 - _smoothstep(finish - blend, finish, value))


static func _smoothstep(start: float, finish: float, value: float) -> float:
	var t := clampf((value - start) / (finish - start), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
