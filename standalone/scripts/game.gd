extends Node3D
## Native desktop simulation lab. All riding forces belong to bike_controller.gd.

const TrackBuilder = preload("res://scripts/track_builder.gd")
const BikeScript = preload("res://scripts/bike_controller.gd")
const RiderInput = preload("res://scripts/rider_input.gd")
const INK: Color = Color("101a29")
const PANEL: Color = Color("182638")
const ORANGE: Color = Color("ff9854")
const TEAL: Color = Color("73d6ca")
const WHITE: Color = Color("eff4fb")
const MUTED: Color = Color("a4b3c5")

var bike: Variant
var rider_input: RefCounted = RiderInput.new()
var track: Dictionary = {}
var cfg: Dictionary = {}
var setup_values: Dictionary = {}
var camera: Camera3D
var sun: DirectionalLight3D
var canvas: CanvasLayer
var hud: Control
var camera_hint_panel: PanelContainer
var status_panel: PanelContainer
var modal: Control
var modal_kind: String = ""
var session_started: bool = false
var focused: bool = true
var labels: Dictionary = {}
var bars: Dictionary = {}
var tuning_fields: Dictionary = {}
var audio_enabled: bool = true
var shadows_enabled: bool = true
var resolution_scale: float = 1.0
var fullscreen_enabled: bool = false
var previous_position: Vector3 = Vector3.ZERO
var lap_active: bool = false
var lap_elapsed: float = 0.0
var last_lap: float = 0.0
var best_lap: float = 0.0
var lap_count: int = 0
var next_gate: int = 0
var was_crashed: bool = false
var recovery_count: int = 0
var last_recovery_kind: String = ""
var notification: String = ""
var notification_time: float = 0.0
var camera_yaw: float = 0.0
var orbit_yaw: float = 0.0
var orbit_height: float = 1.9
var orbit_distance: float = 4.3
var camera_dragging: bool = false
var camera_snap: bool = true
var camera_mode: String = "third_person"
var third_person_fov: float = 58.0
var first_person_fov: float = 94.0
var first_person_pitch: float = -0.28
var riding_mode: String = "virtual_rider"
var binding_capture: String = ""
var binding_status: Label
var binding_buttons: Dictionary = {}
var binding_invert_buttons: Dictionary = {}
var pending_binding: Dictionary = {}
var pending_action: String = ""
var engine_audio: AudioStreamPlayer
var audio_phase: float = 0.0
var audio_frequency: float = 18.0
var audio_level: float = 0.0
var audio_noise: float = 0.0
var quitting: bool = false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	if not parsed is Dictionary:
		push_error("The 250F configuration could not be loaded.")
		return
	cfg = parsed as Dictionary
	setup_values = (cfg.get("Suspension", {}) as Dictionary).duplicate(true)
	_build_world_environment()
	track = TrackBuilder.build(self)
	bike = BikeScript.new()
	bike.name = "TestBike250F"
	bike.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(bike)
	bike.configure(cfg)
	bike.reset_bike(track.get("spawn", Transform3D.IDENTITY))
	bike.set_controls(rider_input.packet())
	previous_position = _chassis().global_position
	_build_camera()
	_build_hud()
	_load_preferences()
	_apply_preferences()
	_build_audio()
	_show_modal("welcome")

func _stop_engine_audio() -> void:
	if is_instance_valid(engine_audio):
		engine_audio.stop()
		engine_audio.stream = null
	engine_audio = null

func _exit_tree() -> void:
	_stop_engine_audio()

func _quit_game() -> void:
	if quitting:
		return
	quitting = true
	rider_input.release_controls()
	get_tree().paused = true
	var had_audio: bool = is_instance_valid(engine_audio)
	_stop_engine_audio()
	# Let the mixer release its stopped generator before engine shutdown.
	if had_audio:
		await get_tree().create_timer(0.12, true, false, true).timeout
	get_tree().quit()

func _chassis() -> RigidBody3D:
	return bike.chassis as RigidBody3D

func _build_world_environment() -> void:
	var world: WorldEnvironment = WorldEnvironment.new()
	world.name = "Daylight"
	var environment: Environment = Environment.new()
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("5789b1")
	sky_material.sky_horizon_color = Color("d6dfd8")
	sky_material.ground_bottom_color = Color("695747")
	sky_material.ground_horizon_color = Color("ddd8bf")
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("cad4c9")
	environment.fog_density = 0.0015
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-47.0, -32.0, 0.0)
	sun.light_color = Color("fff1d9")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "RiderCamera"
	camera.fov = third_person_fov
	camera.near = 0.035
	camera.far = 1200.0
	add_child(camera)
	camera.current = true
	_update_camera(1.0)

func _physics_process(delta: float) -> void:
	if bike == null:
		return
	var enabled: bool = session_started and focused and modal_kind.is_empty() and not get_tree().paused
	bike.set_controls(rider_input.tick(delta, enabled))
	if not enabled:
		return
	var telemetry: Dictionary = bike.get_telemetry()
	var crashed: bool = bool(telemetry.get("crashed", false))
	if crashed and not was_crashed:
		_invalidate_lap("Crash — lap invalidated")
	was_crashed = crashed
	if crashed and float(telemetry.get("recoveryRemaining", 0.0)) <= 0.0:
		_recover(true)
		return
	if lap_active:
		lap_elapsed += delta
	var position_now: Vector3 = _chassis().global_position
	if not crashed:
		_check_gates(previous_position, position_now)
	previous_position = position_now

func _process(delta: float) -> void:
	if bike == null:
		return
	_update_camera(delta)
	_update_hud(bike.get_telemetry())
	_update_audio(delta, bike.get_telemetry())
	if notification_time > 0.0:
		notification_time = maxf(0.0, notification_time - delta)

func _input(event: InputEvent) -> void:
	if quitting:
		return
	rider_input.note_event(event)
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if not binding_capture.is_empty():
		if event is InputEventKey and event.is_action_pressed("mx_pause"):
			binding_capture = ""
			binding_status.text = "Capture cancelled."
		else:
			var candidate: Dictionary = rider_input.controller_bindings.capture(event)
			if not candidate.is_empty() and event.device == rider_input.controller_id:
				_capture_binding(candidate)
		get_viewport().set_input_as_handled()
		return
	var command: String = rider_input.command(event)
	if command == "pause":
		if not session_started:
			_show_modal("welcome")
		elif modal_kind.is_empty():
			_show_modal("pause")
		else:
			_resume()
		get_viewport().set_input_as_handled()
		return
	if command == "help":
		if modal_kind == "help":
			_resume() if session_started else _show_modal("welcome")
		else:
			_show_modal("help")
		get_viewport().set_input_as_handled()
		return
	if command == "setup" and session_started:
		if modal_kind == "tuning":
			_resume()
		elif absf(float(bike.get_telemetry().get("speedMps", 0.0))) < 1.0:
			_show_modal("tuning")
		else:
			_notice("Stop the motorcycle before changing suspension settings.", 4.0)
		get_viewport().set_input_as_handled()
		return
	if not modal_kind.is_empty() or not session_started:
		return
	if command == "camera":
		set_camera_mode("first_person" if camera_mode == "third_person" else "third_person")
		_notice("Helmet view" if camera_mode == "first_person" else "Chase view", 2.0)
		get_viewport().set_input_as_handled()
		return
	rider_input.apply_command(command)
	match command:
		"upshift": bike.shift_gear(1)
		"downshift": bike.shift_gear(-1)
		"engine":
			if not bool(bike.get_telemetry().get("stalled", false)):
				_notice("Engine already running.", 2.0)
			elif not bike.start_engine():
				_notice("Engine start: use neutral or pull the clutch, then press T.", 4.0)
		"recover": _recover()
	if command in ["upshift", "downshift", "stand", "feet", "recover", "engine"]:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			camera_dragging = mouse.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if camera_dragging else Input.MOUSE_MODE_VISIBLE
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(2.8, orbit_distance - 0.3)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(10.0, orbit_distance + 0.3)
	elif event is InputEventMouseMotion and camera_dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		orbit_yaw -= motion.relative.x * 0.004
		if camera_mode == "first_person":
			first_person_pitch = clampf(first_person_pitch - motion.relative.y * 0.003, -0.75, 0.45)
		else:
			orbit_height = clampf(orbit_height + motion.relative.y * 0.01, 0.7, 4.5)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		camera_dragging = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		rider_input.release_controls()
		if bike != null:
			bike.set_controls(rider_input.packet())
		if session_started and modal_kind.is_empty():
			_show_modal("pause")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()

func start_session() -> void:
	session_started = true
	focused = true
	_resume()
	_notice("E: first gear · W: throttle · hold B: release clutch · F: raise feet", 8.0)

func _resume() -> void:
	if not session_started:
		_show_modal("welcome")
		return
	if modal != null:
		modal.queue_free()
		modal = null
	modal_kind = ""
	get_tree().paused = false
	get_viewport().gui_release_focus()
	previous_position = _chassis().global_position

func _recover(automatic: bool = false) -> bool:
	if bike == null:
		return false
	var telemetry: Dictionary = bike.get_telemetry()
	var remaining: float = float(telemetry.get("recoveryRemaining", 0.0))
	if automatic and (not bool(telemetry.get("crashed", false)) or remaining > 0.0):
		return false
	# Manual R can remount immediately. Automatic recovery waits one second.
	# Check the physics reset before changing any rider/UI bookkeeping.
	if not bike.reset_bike(_recovery_transform(), not automatic):
		return false
	_invalidate_lap("Recovery — cross START to begin a fresh lap")
	rider_input.reset_for_recovery()
	bike.set_controls(rider_input.packet())
	previous_position = _chassis().global_position
	was_crashed = false
	recovery_count += 1
	last_recovery_kind = "automatic" if automatic else "manual"
	camera_snap = true
	_notice("Back on the bike · release held controls, then select first gear", 4.0)
	return true

func _recovery_transform() -> Transform3D:
	var fallback: Transform3D = track.get("spawn", Transform3D.IDENTITY)
	var position_now: Vector3 = _chassis().global_position
	if not position_now.is_finite():
		return fallback
	var forward: Vector3 = -_chassis().global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = -fallback.basis.z
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	# Prefer the crash site, then nearby flat ground; otherwise use the lab.
	for offset: Vector3 in [Vector3.ZERO, right * 3.0, -right * 3.0, forward * 3.0, -forward * 3.0]:
		var point := position_now + offset
		var hit := _recovery_ground(point)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.normal
		var tangent: Vector3 = forward - normal * forward.dot(normal)
		if tangent.length_squared() < 0.001:
			continue
		var basis := Basis.looking_at(tangent.normalized(), normal)
		var ground: Vector3 = hit.position
		var extra_height := 0.0
		var safe := true
		for probe: Vector3 in [basis * Vector3(0, 0, -0.74), basis * Vector3(0, 0, 0.74), basis * Vector3(0.34, 0, 0), basis * Vector3(-0.34, 0, 0)]:
			var support := _recovery_ground(ground + probe)
			if support.is_empty():
				safe = false
				break
			var plane_height := ground.y - normal.dot(Vector3(probe.x, 0, probe.z)) / normal.y
			var difference: float = float(support.position.y) - plane_height
			if absf(difference) > 0.35:
				safe = false
				break
			extra_height = maxf(extra_height, difference)
		if safe:
			return Transform3D(basis, ground + normal * 0.86 + Vector3.UP * extra_height)
	return fallback

func _recovery_ground(point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 6.0, point - Vector3.UP * 12.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP) < 0.8:
		return {}
	return hit

func _check_gates(from: Vector3, to: Vector3) -> void:
	var gates: Array = track.get("gates", [])
	for index: int in range(gates.size()):
		var gate: Dictionary = gates[index] as Dictionary
		var transform_gate: Transform3D = gate.get("transform", Transform3D.IDENTITY)
		var inverse: Transform3D = transform_gate.affine_inverse()
		var old_local: Vector3 = inverse * from
		var new_local: Vector3 = inverse * to
		if old_local.z <= 0.0 or new_local.z > 0.0:
			continue
		var fraction: float = old_local.z / (old_local.z - new_local.z)
		var crossing: Vector3 = old_local.lerp(new_local, fraction)
		if absf(crossing.x) > float(gate.get("width", 8.0)) * 0.5 or crossing.y < -1.5 or crossing.y > 5.0:
			continue
		if index == 0:
			if lap_active and next_gate == 0:
				last_lap = lap_elapsed
				best_lap = last_lap if best_lap <= 0.0 else minf(best_lap, last_lap)
				lap_count += 1
				_notice("Lap %d complete · %s" % [lap_count, _time_string(last_lap)], 4.0)
			elif lap_active:
				_notice("Missing checkpoint — new lap started", 4.0)
			lap_active = true
			lap_elapsed = 0.0
			next_gate = 1 if gates.size() > 1 else 0
		elif lap_active and index == next_gate:
			next_gate = (next_gate + 1) % gates.size()
		elif lap_active:
			_invalidate_lap("Checkpoint out of order — return to START")

func _invalidate_lap(reason: String) -> void:
	lap_active = false
	lap_elapsed = 0.0
	next_gate = 0
	_notice(reason, 5.0)

func _time_string(seconds: float) -> String:
	if seconds <= 0.0:
		return "—"
	var minutes: int = int(seconds / 60.0)
	return "%d:%06.3f" % [minutes, fmod(seconds, 60.0)]

func _notice(message: String, duration: float = 4.0) -> void:
	notification = message
	notification_time = duration

func set_camera_mode(mode: String, save: bool = true) -> void:
	camera_mode = mode if mode in ["first_person", "third_person"] else "third_person"
	camera_snap = true
	orbit_yaw = 0.0
	first_person_pitch = -0.28
	if bike != null and bike.has_method("set_first_person"):
		bike.set_first_person(camera_mode == "first_person")
	if camera != null:
		camera.fov = first_person_fov if camera_mode == "first_person" else third_person_fov
	_update_camera_hud()
	if save:
		_save_preferences()

func camera_target_transform() -> Transform3D:
	var body: RigidBody3D = _chassis()
	if camera_mode == "first_person":
		var eyes: Transform3D = body.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.93, -0.09))
		if bike.has_method("get_rider_camera_transform"):
			eyes = bike.get_rider_camera_transform()
		# A small rearward helmet-view offset keeps gloves and bars in the lower frame.
		eyes.origin += eyes.basis.z * 0.08
		# The camera follows the real rider anchor; only the view rotation is softened.
		# A little horizon reference reduces nausea without turning the bike upright.
		var direction: Vector3 = -eyes.basis.z
		var rider_up: Vector3 = eyes.basis.y.normalized()
		var view_up: Vector3 = rider_up.lerp(Vector3.UP, 0.35).normalized()
		if absf(view_up.dot(direction.normalized())) > 0.94:
			view_up = eyes.basis.y
		var view_basis: Basis = Basis.looking_at(direction, view_up)
		view_basis = view_basis * Basis(Vector3.UP, orbit_yaw) * Basis(Vector3.RIGHT, first_person_pitch)
		return Transform3D(view_basis, eyes.origin)
	var target: Vector3 = body.global_position + Vector3.UP * 0.65
	var yaw: float = camera_yaw + orbit_yaw
	var wanted: Vector3 = target + Vector3(sin(yaw) * orbit_distance, orbit_height, cos(yaw) * orbit_distance)
	# Pull the chase camera forward when terrain would otherwise hide the rider.
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(target, wanted)
	query.exclude = [body.get_rid(), bike.front_wheel.get_rid(), bike.rear_wheel.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		wanted = hit.position + hit.normal * 0.22
	return Transform3D(Basis.looking_at(target - wanted, Vector3.UP), wanted)

func _update_camera(delta: float) -> void:
	var forward: Vector3 = -_chassis().global_basis.z
	if Vector2(forward.x, forward.z).length() > 0.1:
		var desired_yaw: float = atan2(-forward.x, -forward.z)
		camera_yaw = desired_yaw if camera_snap else lerp_angle(camera_yaw, desired_yaw, 1.0 - exp(-4.0 * delta))
	var wanted: Transform3D = camera_target_transform()
	if camera_snap:
		camera.global_transform = wanted
	elif camera_mode == "first_person":
		# Translation is anchored to the helmet, avoiding clipping through the rider.
		camera.global_position = wanted.origin
		camera.global_basis = camera.global_basis.slerp(wanted.basis, 1.0 - exp(-18.0 * delta)).orthonormalized()
	else:
		camera.global_transform = camera.global_transform.interpolate_with(wanted, 1.0 - exp(-9.0 * delta))
	camera.fov = first_person_fov if camera_mode == "first_person" else third_person_fov
	camera_snap = false

func _panel_style(color: Color = PANEL, border: Color = Color("304155")) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	return style

func _label(text: String, size: int = 16, color: Color = WHITE) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 43.0
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", INK if primary else WHITE)
	button.add_theme_color_override("font_hover_color", INK if primary else WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(ORANGE if primary else Color("24354a")))
	button.add_theme_stylebox_override("hover", _panel_style(Color("ffb179") if primary else Color("354b64")))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("d57438") if primary else Color("152437")))
	button.pressed.connect(callback)
	return button

func _bar(color: Color, width: float = 180.0) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 7.0)
	bar.max_value = 1.0
	bar.show_percentage = false
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color("34445a")
	background.set_corner_radius_all(3)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

func _build_hud() -> void:
	canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	hud = Control.new()
	hud.name = "TelemetryHUD"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud)
	var theme: Theme = Theme.new()
	theme.default_font_size = 16
	hud.theme = theme
	var speed_panel: PanelContainer = PanelContainer.new()
	speed_panel.position = Vector2(24.0, 24.0)
	speed_panel.custom_minimum_size = Vector2(265.0, 236.0)
	speed_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.09, 0.15, 0.92)))
	hud.add_child(speed_panel)
	var speed_box: VBoxContainer = VBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 5)
	speed_panel.add_child(speed_box)
	speed_box.add_child(_label("DIRTLINE / 250F", 15, TEAL))
	labels.speed = _label("0  km/h", 37)
	speed_box.add_child(labels.speed)
	labels.gear = _label("N   ·   2,200 rpm", 21, ORANGE)
	speed_box.add_child(labels.gear)
	bars.rpm = _bar(ORANGE)
	speed_box.add_child(bars.rpm)
	labels.clutch = _label("CLUTCH PULLED   100%", 13, MUTED)
	speed_box.add_child(labels.clutch)
	bars.clutch = _bar(TEAL)
	speed_box.add_child(bars.clutch)
	labels.posture = _label("SEATED · FEET DOWN", 13)
	speed_box.add_child(labels.posture)
	var race_panel: PanelContainer = PanelContainer.new()
	race_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	race_panel.offset_left = -304.0
	race_panel.offset_top = 24.0
	race_panel.offset_right = -24.0
	race_panel.offset_bottom = 187.0
	race_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.09, 0.15, 0.92)))
	hud.add_child(race_panel)
	var race_box: VBoxContainer = VBoxContainer.new()
	race_box.add_theme_constant_override("separation", 7)
	race_panel.add_child(race_box)
	race_box.add_child(_label("SINGLEPLAYER · TEST TRACK", 13, TEAL))
	labels.lap = _label("Cross START to begin", 18)
	race_box.add_child(labels.lap)
	labels.timer = _label("0:00.000", 29)
	race_box.add_child(labels.timer)
	labels.best = _label("BEST  —     LAST  —", 13, MUTED)
	race_box.add_child(labels.best)
	var contact_panel: PanelContainer = PanelContainer.new()
	contact_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	contact_panel.offset_left = 24.0
	contact_panel.offset_right = 319.0
	contact_panel.offset_top = -188.0
	contact_panel.offset_bottom = -67.0
	contact_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.09, 0.15, 0.92)))
	hud.add_child(contact_panel)
	var contact_box: VBoxContainer = VBoxContainer.new()
	contact_box.add_theme_constant_override("separation", 4)
	contact_panel.add_child(contact_box)
	labels.front = _label("FRONT · dirt · 0% slip", 13)
	contact_box.add_child(labels.front)
	bars.front = _bar(TEAL)
	contact_box.add_child(bars.front)
	labels.rear = _label("REAR · dirt · 0% slip", 13)
	contact_box.add_child(labels.rear)
	bars.rear = _bar(ORANGE)
	contact_box.add_child(bars.rear)
	labels.travel = _label("Suspension compression · front / rear", 11, MUTED)
	contact_box.add_child(labels.travel)
	status_panel = PanelContainer.new()
	status_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status_panel.offset_left = -310.0
	status_panel.offset_right = 310.0
	status_panel.offset_top = -114.0
	status_panel.offset_bottom = -72.0
	var status_style: StyleBoxFlat = _panel_style(Color(0.05, 0.09, 0.15, 0.92))
	status_style.content_margin_top = 10.0
	status_style.content_margin_bottom = 10.0
	status_panel.add_theme_stylebox_override("panel", status_style)
	hud.add_child(status_panel)
	labels.status = _label("", 16, ORANGE)
	(labels.status as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(labels.status as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_panel.add_child(labels.status)
	var hint_panel: PanelContainer = PanelContainer.new()
	camera_hint_panel = hint_panel
	hint_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.offset_left = -383.0
	hint_panel.offset_right = 383.0
	hint_panel.offset_top = -49.0
	hint_panel.offset_bottom = -12.0
	var hint_style: StyleBoxFlat = _panel_style(Color(0.05, 0.09, 0.15, 0.92))
	hint_style.content_margin_top = 9.0
	hint_style.content_margin_bottom = 9.0
	hint_panel.add_theme_stylebox_override("panel", hint_style)
	hud.add_child(hint_panel)
	var hint: Label = _label("H  CONTROLS   M  CAMERA   U  SETUP   R  RECOVER   ESC  MENU   RMB  LOOK", 13, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_panel.add_child(hint)

func _update_hud(t: Dictionary) -> void:
	(labels.speed as Label).text = "%3.0f  km/h" % float(t.get("speed", 0.0))
	var gear: int = int(t.get("gear", 0))
	var gear_text: String = "N" if gear == 0 else str(gear)
	(labels.gear as Label).text = "%s   ·   %s rpm" % [gear_text, str(int(t.get("rpm", 0.0)))]
	(bars.rpm as ProgressBar).value = float(t.get("rpm", 0.0)) / 13500.0
	var clutch: float = float(t.get("clutch", 1.0))
	(labels.clutch as Label).text = "CLUTCH %s   %.0f%%" % ["PULLED" if clutch > 0.95 else ("ENGAGED" if clutch < 0.05 else "SLIPPING"), clutch * 100.0]
	(bars.clutch as ProgressBar).value = clutch
	(labels.posture as Label).text = "%s · %s · %s" % ["STANDING" if bool(t.get("standing", false)) else "SEATED", "FEET DOWN" if bool(t.get("footDown", true)) else "ON PEGS", "LEAN" if riding_mode == "virtual_rider" else "BARS"]
	(labels.front as Label).text = "FRONT · %s · %.0f%% slip%s" % [str(t.get("frontSurface", "dirt")), absf(float(t.get("frontSlip", 0.0))) * 100.0, " · AIR" if not bool(t.get("frontContact", false)) else ""]
	(labels.rear as Label).text = "REAR · %s · %.0f%% slip%s" % [str(t.get("rearSurface", "dirt")), absf(float(t.get("rearSlip", 0.0))) * 100.0, " · AIR" if not bool(t.get("rearContact", false)) else ""]
	(bars.front as ProgressBar).value = float(t.get("frontCompression", 0.0)) / 0.3
	(bars.rear as ProgressBar).value = float(t.get("rearCompression", 0.0)) / 0.3
	(labels.timer as Label).text = _time_string(lap_elapsed) if lap_active else "0:00.000"
	(labels.lap as Label).text = ("LAP %d · %s" % [lap_count + 1, "START / FINISH" if next_gate == 0 else "GATE %d / %d" % [next_gate + 1, (track.get("gates", []) as Array).size()]]) if lap_active else "Cross START to begin"
	(labels.best as Label).text = "BEST  %s     LAST  %s" % [_time_string(best_lap), _time_string(last_lap)]
	var status: String = notification if notification_time > 0.0 else ""
	if bool(t.get("crashed", false)):
		var wait: float = float(t.get("recoveryRemaining", 0.0))
		status = "%s · Auto remount in %.1f s · R / mapped button: remount now" % [str(t.get("crashReason", "Crash")), wait]
	elif bool(t.get("stalled", false)):
		status = "ENGINE STALLED · Pull clutch / select neutral, then T or left-stick click"
	(labels.status as Label).text = status
	status_panel.visible = not status.is_empty()

func _show_modal(kind: String) -> void:
	if canvas == null:
		return
	rider_input.release_controls()
	if bike != null:
		bike.set_controls(rider_input.packet())
	camera_dragging = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if modal != null:
		modal.queue_free()
	binding_capture = ""
	modal_kind = kind
	get_tree().paused = session_started
	modal = Control.new()
	modal.name = "Menu_" + kind
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(modal)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.025, 0.04, 0.07, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = 750.0 if kind in ["bindings", "settings"] else (680.0 if kind in ["help", "tuning"] else 550.0)
	panel.add_theme_stylebox_override("panel", _panel_style(INK, Color("3b5066")))
	center.add_child(panel)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	if kind in ["bindings", "settings"]:
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(700.0, minf(560.0, get_viewport().get_visible_rect().size.y - 100.0))
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(scroll)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(content)
	else:
		panel.add_child(content)
	content.add_child(_label("DIRTLINE  /  MX", 15, TEAL))
	match kind:
		"welcome": _welcome_content(content)
		"pause": _pause_content(content)
		"help": _help_content(content)
		"settings": _settings_content(content)
		"bindings": _bindings_content(content)
		"tuning": _tuning_content(content)

func _welcome_content(content: VBoxContainer) -> void:
	content.add_child(_label("LEARN THE RIDE.", 36))
	content.add_child(_label("250F · Motocross test track", 19, ORANGE))
	var detail: Label = _label("One full-size 250F. A bigger motocross proving ground.\nControl your lean, move your body and learn each jump.\nManual clutch and separate brakes.", 16, MUTED)
	content.add_child(detail)
	content.add_child(_label("Keyboard + controller · Windows PC", 15, TEAL))
	content.add_child(_button("LET’S RIDE", start_session, true))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var help: Button = _button("Controls", func() -> void: _show_modal("help"))
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(help)
	var settings: Button = _button("Settings + controller binds", func() -> void: _show_modal("settings"))
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(settings)
	content.add_child(_label("DEVELOPMENT PROTOTYPE · Your riding feedback guides handling tuning.", 12, MUTED))
	content.add_child(_button("Exit", _quit_game))

func _pause_content(content: VBoxContainer) -> void:
	content.add_child(_label("RIDE PAUSED", 32))
	content.add_child(_button("Resume ride", _resume, true))
	content.add_child(_button("Controls", func() -> void: _show_modal("help")))
	content.add_child(_button("Settings + controller binds", func() -> void: _show_modal("settings")))
	content.add_child(_button("Suspension setup", func() -> void:
		if absf(float(bike.get_telemetry().get("speedMps", 0.0))) < 1.0:
			_show_modal("tuning")
		else:
			_notice("Park before changing suspension settings.")
			_resume()))
	content.add_child(_button("Exit game", _quit_game))

func _help_content(content: VBoxContainer) -> void:
	content.add_child(_label("THE RIDER IS YOU", 28))
	var tabs: TabContainer = TabContainer.new()
	tabs.custom_minimum_size = Vector2(590.0, 350.0)
	content.add_child(tabs)
	var keyboard: VBoxContainer = VBoxContainer.new()
	keyboard.name = "Keyboard"
	keyboard.add_theme_constant_override("separation", 8)
	tabs.add_child(keyboard)
	keyboard.add_child(_label("W  Progressive throttle     SPACE  Front brake     S  Rear brake", 15))
	keyboard.add_child(_label("V / B  Pull / release clutch     SHIFT  Quick clutch pull", 15))
	keyboard.add_child(_label("Q / E  Down / upshift     T  Engine start", 15))
	keyboard.add_child(_label("A / D  Lean command / direct bars     Z / X  Rider lean", 15))
	keyboard.add_child(_label("I / K  Body forward / back     J / L  Body left / right", 15))
	keyboard.add_child(_label("C  Seated / standing     F  Feet down / on pegs", 15))
	keyboard.add_child(_label("R  Recover     M  Camera     H  Help     U  Setup     ESC  Pause", 15))
	keyboard.add_child(_label("Hold right mouse to orbit · Mouse wheel changes camera distance", 14, MUTED))
	keyboard.add_child(_label("Starting: E → gentle W → hold B to release the clutch → F to raise feet.\nV/B hold the lever position. Lean-control mode: A/D asks your rider to lean. Z/X moves your upper body.", 14, TEAL))
	var controller: VBoxContainer = VBoxContainer.new()
	controller.name = "Controller"
	controller.add_theme_constant_override("separation", 8)
	tabs.add_child(controller)
	controller.add_child(_label("RT  Throttle     LT  Front brake     RB  Rear brake", 15))
	controller.add_child(_label("LB  Pull clutch; release LB to engage over 0.6 seconds", 15))
	controller.add_child(_label("Left stick  Lean command / direct bars     Right stick  Rider body position", 15))
	controller.add_child(_label("D-pad ← / →  Rider lean     D-pad ↓ / ↑  Shift down / up", 15))
	controller.add_child(_label("A  Seated / standing     X  Feet down / on pegs     Y  Recover", 15))
	controller.add_child(_label("Left-stick click  Engine start     Right-stick click  Help", 15))
	controller.add_child(_label("B / Circle  Camera mode     Menu / Start  Pause", 15))
	controller.add_child(_label("Customize every controller action in Settings → Controller bindings.\nKeyboard controls remain available. Only your selected controller drives.", 14, TEAL))
	content.add_child(_label("Ride numbered gates in order to time a lap. Recovery cancels the lap.\nTest berms, ruts, braking bumps, whoops and the separate large-jump lane.", 14, MUTED))
	content.add_child(_button("Back to ride" if session_started else "Back", _resume if session_started else func() -> void: _show_modal("welcome"), true))

func _settings_content(content: VBoxContainer) -> void:
	content.add_child(_label("RIDE + CAMERA + DISPLAY", 27))
	content.add_child(_label("RIDING CONTROLS", 16, TEAL))
	var mode_select: OptionButton = OptionButton.new()
	mode_select.add_item("Lean control · virtual rider", 0)
	mode_select.add_item("Direct handlebar control · manual", 1)
	mode_select.select(0 if riding_mode == "virtual_rider" else 1)
	mode_select.item_selected.connect(func(index: int) -> void:
		riding_mode = "virtual_rider" if index == 0 else "direct"
		if bike.has_method("set_riding_mode"):
			bike.set_riding_mode(riding_mode)
		_save_preferences())
	content.add_child(mode_select)
	var mode_info: Label = _label("Lean control: command a lean; your rider countersteers and balances.\nDirect bars: you control steering effort and balance yourself. Crashes still matter.", 14, MUTED)
	content.add_child(mode_info)
	content.add_child(_button("Customize controller bindings", func() -> void: _show_modal("bindings")))
	content.add_child(_label("CAMERA", 16, TEAL))
	var camera_select: OptionButton = OptionButton.new()
	camera_select.add_item("Chase view", 0)
	camera_select.add_item("First-person helmet view", 1)
	camera_select.select(1 if camera_mode == "first_person" else 0)
	camera_select.item_selected.connect(func(index: int) -> void: set_camera_mode("first_person" if index == 1 else "third_person"))
	content.add_child(camera_select)
	_add_preference_slider(content, "Chase distance · metres", orbit_distance, 2.8, 8.0, 0.1, func(value: float) -> void: orbit_distance = value)
	_add_preference_slider(content, "Chase field of view", third_person_fov, 45.0, 90.0, 1.0, func(value: float) -> void: third_person_fov = value)
	_add_preference_slider(content, "Helmet field of view", first_person_fov, 60.0, 110.0, 1.0, func(value: float) -> void: first_person_fov = value)
	content.add_child(_label("M / controller B toggles views. Hold right mouse to look around.", 14, MUTED))
	content.add_child(_label("DISPLAY + SOUND", 16, TEAL))
	var fullscreen_box: CheckBox = CheckBox.new()
	fullscreen_box.text = "Fullscreen"
	fullscreen_box.button_pressed = fullscreen_enabled
	fullscreen_box.toggled.connect(func(value: bool) -> void:
		fullscreen_enabled = value
		_apply_preferences()
		_save_preferences())
	content.add_child(fullscreen_box)
	var shadows_box: CheckBox = CheckBox.new()
	shadows_box.text = "Sun shadows"
	shadows_box.button_pressed = shadows_enabled
	shadows_box.toggled.connect(func(value: bool) -> void:
		shadows_enabled = value
		_apply_preferences()
		_save_preferences())
	content.add_child(shadows_box)
	var sound_box: CheckBox = CheckBox.new()
	sound_box.text = "Engine audio · original procedural prototype sound"
	sound_box.button_pressed = audio_enabled
	sound_box.toggled.connect(func(value: bool) -> void:
		audio_enabled = value
		_apply_preferences()
		_save_preferences())
	content.add_child(sound_box)
	var scale_label: Label = _label("3D resolution scale · %.0f%%" % (resolution_scale * 100.0), 16)
	content.add_child(scale_label)
	var scale_slider: HSlider = HSlider.new()
	scale_slider.min_value = 0.6
	scale_slider.max_value = 1.25
	scale_slider.step = 0.05
	scale_slider.value = resolution_scale
	scale_slider.value_changed.connect(func(value: float) -> void:
		resolution_scale = value
		scale_label.text = "3D resolution scale · %.0f%%" % (value * 100.0)
		_apply_preferences()
		_save_preferences())
	content.add_child(scale_slider)
	content.add_child(_label("Saved locally on this computer. The simulation remains at 240 Hz.", 13, MUTED))
	content.add_child(_button("Back", func() -> void: _show_modal("pause" if session_started else "welcome"), true))

func _tuning_content(content: VBoxContainer) -> void:
	content.add_child(_label("250F / SUSPENSION SETUP", 26))
	content.add_child(_label("Parked changes · physical spring and damping parameters", 15, TEAL))
	tuning_fields.clear()
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	grid.add_child(_label("", 15))
	grid.add_child(_label("FRONT", 15, ORANGE))
	grid.add_child(_label("REAR", 15, TEAL))
	var definitions: Array = [
		["SpringRate", "Spring · N/m", 8000.0, 40000.0, 500.0],
		["Compression", "Compression · N·s/m", 300.0, 5000.0, 100.0],
		["Rebound", "Rebound · N·s/m", 300.0, 6000.0, 100.0],
		["Preload", "Preload · m", 0.0, 0.035, 0.001]]
	for definition: Array in definitions:
		grid.add_child(_label(str(definition[1]), 15))
		for end_name: String in ["Front", "Rear"]:
			var spin: SpinBox = SpinBox.new()
			spin.min_value = float(definition[2])
			spin.max_value = float(definition[3])
			spin.step = float(definition[4])
			spin.value = float((setup_values.get(end_name, {}) as Dictionary).get(str(definition[0]), float(definition[2])))
			spin.custom_minimum_size.x = 125.0
			grid.add_child(spin)
			tuning_fields[end_name + "." + str(definition[0])] = spin
	content.add_child(_label("More compression damping slows compression; more rebound slows extension.\nPreload shifts sag. Spring rate changes load support.", 13, MUTED))
	content.add_child(_button("Apply and ride", _apply_tuning, true))
	content.add_child(_button("Restore 250F baseline", _restore_tuning_baseline))
	content.add_child(_button("Cancel", _resume))

func _restore_tuning_baseline() -> void:
	var baseline: Dictionary = cfg.get("Suspension", {}) as Dictionary
	for key: String in tuning_fields:
		var parts: PackedStringArray = key.split(".")
		(tuning_fields[key] as SpinBox).value = float((baseline.get(parts[0], {}) as Dictionary).get(parts[1], 0.0))

func _apply_tuning() -> void:
	if absf(float(bike.get_telemetry().get("speedMps", 0.0))) >= 1.0:
		_notice("Setup requires a parked motorcycle.")
		_resume()
		return
	var changes: Dictionary = {"Front": {}, "Rear": {}}
	for key: String in tuning_fields:
		var parts: PackedStringArray = key.split(".")
		(changes[parts[0]] as Dictionary)[parts[1]] = (tuning_fields[key] as SpinBox).value
	if not bike.tune_setup(changes):
		_resume()
		_notice("Setup rejected. Park the bike and use the supported ranges.", 4.0)
		return
	for end_name: String in ["Front", "Rear"]:
		for property_name: String in changes[end_name]:
			(setup_values[end_name] as Dictionary)[property_name] = changes[end_name][property_name]
	_resume()
	_notice("Suspension setup applied to the test bike.", 4.0)

func _load_preferences() -> void:
	var preferences: ConfigFile = ConfigFile.new()
	if preferences.load("user://preferences.cfg") != OK:
		return
	audio_enabled = bool(preferences.get_value("sound", "engine", true))
	shadows_enabled = bool(preferences.get_value("display", "shadows", true))
	fullscreen_enabled = bool(preferences.get_value("display", "fullscreen", false))
	resolution_scale = clampf(float(preferences.get_value("display", "resolution_scale", 1.0)), 0.6, 1.25)
	riding_mode = str(preferences.get_value("riding", "mode", "virtual_rider"))
	if not riding_mode in ["virtual_rider", "direct"]:
		riding_mode = "virtual_rider"
	camera_mode = str(preferences.get_value("camera", "mode", "third_person"))
	orbit_distance = clampf(float(preferences.get_value("camera", "distance", 4.3)), 2.8, 8.0)
	third_person_fov = clampf(float(preferences.get_value("camera", "chase_fov", 58.0)), 45.0, 90.0)
	first_person_fov = clampf(float(preferences.get_value("camera", "helmet_fov", 94.0)), 60.0, 110.0)

func _save_preferences() -> void:
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("sound", "engine", audio_enabled)
	preferences.set_value("display", "shadows", shadows_enabled)
	preferences.set_value("display", "fullscreen", fullscreen_enabled)
	preferences.set_value("display", "resolution_scale", resolution_scale)
	preferences.set_value("riding", "mode", riding_mode)
	preferences.set_value("camera", "mode", camera_mode)
	preferences.set_value("camera", "distance", orbit_distance)
	preferences.set_value("camera", "chase_fov", third_person_fov)
	preferences.set_value("camera", "helmet_fov", first_person_fov)
	preferences.save("user://preferences.cfg")

func _apply_preferences() -> void:
	if bike != null and bike.has_method("set_riding_mode"):
		bike.set_riding_mode(riding_mode)
	set_camera_mode(camera_mode, false)
	sun.shadow_enabled = shadows_enabled
	get_viewport().scaling_3d_scale = resolution_scale
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen_enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	if engine_audio != null:
		engine_audio.volume_db = -21.0 if audio_enabled else -80.0

func _build_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	engine_audio = AudioStreamPlayer.new()
	engine_audio.name = "OriginalEngineSynth"
	var stream: AudioStreamGenerator = AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.12
	engine_audio.stream = stream
	engine_audio.volume_db = -21.0 if audio_enabled else -80.0
	add_child(engine_audio)
	engine_audio.play()

func _update_audio(delta: float, telemetry: Dictionary) -> void:
	if engine_audio == null or not engine_audio.playing:
		return
	var playback: AudioStreamGeneratorPlayback = engine_audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	# A single-cylinder four-stroke fires once per two crank revolutions.
	var target_frequency: float = maxf(10.0, float(telemetry.get("rpm", 2200.0)) / 120.0)
	audio_frequency = lerpf(audio_frequency, target_frequency, 1.0 - exp(-15.0 * delta))
	var silent: bool = bool(telemetry.get("stalled", false)) or not session_started or not modal_kind.is_empty()
	var target_level: float = 0.0 if silent else 0.32 + 0.22 * float(rider_input.throttle)
	audio_level = lerpf(audio_level, target_level, 1.0 - exp(-10.0 * delta))
	var frames: int = mini(playback.get_frames_available(), 4096)
	for sample_index: int in range(frames):
		audio_phase = fmod(audio_phase + TAU * audio_frequency / 22050.0, TAU)
		audio_noise = lerpf(audio_noise, randf_range(-1.0, 1.0), 0.18)
		var wave: float = sin(audio_phase) * 0.43 + sin(audio_phase * 2.0) * 0.22 + sin(audio_phase * 3.0) * 0.16 + sin(audio_phase * 6.0) * 0.06 + audio_noise * 0.08
		var sample: float = wave * audio_level
		playback.push_frame(Vector2(sample, sample))

func _add_preference_slider(content: VBoxContainer, title: String, initial: float, minimum: float, maximum: float, step_size: float, changed: Callable) -> void:
	var label: Label = _label("%s · %.2f" % [title, initial], 14)
	content.add_child(label)
	var slider: HSlider = HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.value = initial
	slider.value_changed.connect(func(value: float) -> void:
		changed.call(value)
		label.text = "%s · %.2f" % [title, value]
		_save_preferences())
	content.add_child(slider)

func _bindings_content(content: VBoxContainer) -> void:
	content.add_child(_label("YOUR CONTROLLER", 27))
	content.add_child(_label("Click a binding, then press a button or move an axis fully in the desired direction.\nEach direction can use an axis or button. Escape cancels capture.", 14, MUTED))
	var device_choice: OptionButton = OptionButton.new()
	device_choice.add_item("Keyboard / waiting for controller", -1)
	var selected: int = 0
	for device: int in Input.get_connected_joypads():
		device_choice.add_item("%s · device %d" % [Input.get_joy_name(device), device], device)
		if device == rider_input.controller_id:
			selected = device_choice.item_count - 1
	device_choice.select(selected)
	device_choice.item_selected.connect(func(index: int) -> void:
		rider_input.select_controller(device_choice.get_item_id(index)))
	content.add_child(device_choice)
	var map: RefCounted = rider_input.controller_bindings
	_add_preference_slider(content, "Stick deadzone", float(map.deadzone), 0.0, 0.5, 0.01, func(value: float) -> void:
		map.deadzone = value
		map.save_file())
	_add_preference_slider(content, "Trigger deadzone", float(map.trigger_deadzone), 0.0, 0.3, 0.01, func(value: float) -> void:
		map.trigger_deadzone = value
		map.save_file())
	binding_status = _label("Bindings are saved on this computer. Only the selected controller drives.", 14, TEAL)
	binding_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(binding_status)
	var conflict_button: Button = _button("Use conflicting input here · unbind previous action", _replace_binding_conflict)
	conflict_button.name = "ReplaceBindingConflict"
	conflict_button.visible = false
	content.add_child(conflict_button)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 5)
	content.add_child(grid)
	binding_buttons.clear()
	binding_invert_buttons.clear()
	for action: String in map.ACTIONS:
		grid.add_child(_label(str(map.LABELS.get(action, action)), 14))
		var remap: Button = _button(str(map.describe(action)), func() -> void: _begin_binding_capture(action))
		remap.add_theme_font_size_override("font_size", 13)
		remap.custom_minimum_size.x = 210.0
		grid.add_child(remap)
		binding_buttons[action] = remap
		var invert_button: Button = _button("Invert", func() -> void: _invert_controller_axis(action))
		invert_button.add_theme_font_size_override("font_size", 13)
		invert_button.disabled = str((map.bindings.get(action, {}) as Dictionary).get("kind", "")) != "axis"
		binding_invert_buttons[action] = invert_button
		grid.add_child(invert_button)
		var clear_button: Button = _button("Clear", func() -> void:
			map.assign(action, {})
			map.save_file()
			_refresh_binding_labels()
			binding_status.text = "%s unbound." % str(map.LABELS[action]))
		clear_button.add_theme_font_size_override("font_size", 13)
		grid.add_child(clear_button)
	content.add_child(_label("Invert flips both stick directions, or a trigger’s pull / release range.\nUnplugging a controller releases throttle and brakes and pulls the clutch.", 13, MUTED))
	content.add_child(_button("Restore default controller layout", func() -> void:
		map.reset_defaults()
		map.save_file()
		_refresh_binding_labels()
		binding_status.text = "Default controller layout restored."))
	content.add_child(_button("Back to settings", func() -> void: _show_modal("settings"), true))

func _begin_binding_capture(action: String) -> void:
	binding_capture = action
	pending_action = ""
	pending_binding = {}
	binding_status.text = "Remapping %s: press a controller button or move an axis. Escape cancels." % str(rider_input.controller_bindings.LABELS[action])
	_refresh_binding_labels()

func _capture_binding(candidate: Dictionary) -> void:
	var action: String = binding_capture
	binding_capture = ""
	var map: RefCounted = rider_input.controller_bindings
	var conflict: Array = map.assign(action, candidate)
	if conflict.is_empty():
		map.save_file()
		binding_status.text = "%s → %s" % [str(map.LABELS[action]), str(map.describe(action))]
		pending_action = ""
		pending_binding = {}
	else:
		pending_action = action
		pending_binding = candidate
		var names: PackedStringArray = []
		for other: String in conflict:
			names.append(str(map.LABELS.get(other, other)))
		binding_status.text = "Already used by %s. Keep the current mapping or explicitly replace it below." % ", ".join(names)
	_refresh_binding_labels()

func _replace_binding_conflict() -> void:
	if pending_action.is_empty():
		return
	var map: RefCounted = rider_input.controller_bindings
	map.assign(pending_action, pending_binding, true)
	map.save_file()
	binding_status.text = "%s → %s. Previous action unbound." % [str(map.LABELS[pending_action]), str(map.describe(pending_action))]
	pending_action = ""
	pending_binding = {}
	_refresh_binding_labels()

func _invert_controller_axis(action: String) -> void:
	var map: RefCounted = rider_input.controller_bindings
	var binding: Dictionary = map.bindings.get(action, {})
	if str(binding.get("kind", "")) != "axis":
		binding_status.text = "Only an axis has a direction to invert. Click the binding to assign an axis."
		return
	var axis_index: int = int(binding.index)
	for other: String in map.ACTIONS:
		var existing: Dictionary = map.bindings.get(other, {})
		if str(existing.get("kind", "")) == "axis" and int(existing.index) == axis_index:
			existing.direction = -int(existing.direction)
	map.save_file()
	binding_status.text = "Axis inverted. Both directions changed together."
	_refresh_binding_labels()

func _refresh_binding_labels() -> void:
	for action: String in binding_buttons:
		(binding_buttons[action] as Button).text = "Listening…" if binding_capture == action else str(rider_input.controller_bindings.describe(action))
	for action: String in binding_invert_buttons:
		(binding_invert_buttons[action] as Button).disabled = str((rider_input.controller_bindings.bindings.get(action, {}) as Dictionary).get("kind", "")) != "axis"
	if modal != null:
		var replace_button: Button = modal.find_child("ReplaceBindingConflict", true, false) as Button
		if replace_button != null:
			replace_button.visible = not pending_action.is_empty()

func _update_camera_hud() -> void:
	if camera_hint_panel == null or status_panel == null:
		return
	var first_person: bool = camera_mode == "first_person"
	camera_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP if first_person else Control.PRESET_CENTER_BOTTOM)
	camera_hint_panel.offset_left = -310.0 if first_person else -383.0
	camera_hint_panel.offset_right = 310.0 if first_person else 383.0
	camera_hint_panel.offset_top = 24.0 if first_person else -49.0
	camera_hint_panel.offset_bottom = 61.0 if first_person else -12.0
	status_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP if first_person else Control.PRESET_CENTER_BOTTOM)
	status_panel.offset_left = -310.0
	status_panel.offset_right = 310.0
	status_panel.offset_top = 70.0 if first_person else -114.0
	status_panel.offset_bottom = 112.0 if first_person else -72.0
