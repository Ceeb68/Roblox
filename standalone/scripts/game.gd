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
var notification: String = ""
var notification_time: float = 0.0
var camera_yaw: float = 0.0
var orbit_yaw: float = 0.0
var orbit_height: float = 3.5
var orbit_distance: float = 7.5
var camera_dragging: bool = false
var camera_snap: bool = true
var engine_audio: AudioStreamPlayer
var audio_phase: float = 0.0
var audio_frequency: float = 18.0
var audio_level: float = 0.0
var audio_noise: float = 0.0

func _ready() -> void:
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
	environment.ambient_light_energy = 0.65
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
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "RiderCamera"
	camera.fov = 68.0
	camera.near = 0.08
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
	rider_input.note_event(event)
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed("mx_pause"):
		if not session_started:
			_show_modal("welcome")
		elif modal_kind.is_empty():
			_show_modal("pause")
		else:
			_resume()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("mx_help"):
		if modal_kind == "help":
			_resume() if session_started else _show_modal("welcome")
		else:
			_show_modal("help")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("mx_setup") and session_started:
		if modal_kind == "tuning":
			_resume()
		elif absf(float(bike.get_telemetry().get("speedMps", 0.0))) < 1.0:
			_show_modal("tuning")
		else:
			_notice("Stop the motorcycle before changing suspension settings.", 4.0)
		get_viewport().set_input_as_handled()
		return
	if not modal_kind.is_empty():
		return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			camera_dragging = mouse.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if camera_dragging else Input.MOUSE_MODE_VISIBLE
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(4.0, orbit_distance - 0.5)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(13.0, orbit_distance + 0.5)
	elif event is InputEventMouseMotion and camera_dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		orbit_yaw -= motion.relative.x * 0.004
		orbit_height = clampf(orbit_height + motion.relative.y * 0.015, 1.2, 7.0)

func _unhandled_input(event: InputEvent) -> void:
	if not session_started or not modal_kind.is_empty() or bike == null:
		return
	var command: String = rider_input.command(event)
	match command:
		"upshift": bike.shift_gear(1)
		"downshift": bike.shift_gear(-1)
		"engine":
			if not bool(bike.get_telemetry().get("stalled", false)):
				_notice("Engine already running.", 2.0)
			elif not bike.start_engine():
				_notice("Engine start: use neutral or pull the clutch, then press T.", 4.0)
		"recover": _recover()
	if not command.is_empty():
		get_viewport().set_input_as_handled()

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

func _recover() -> void:
	var telemetry: Dictionary = bike.get_telemetry()
	var remaining: float = float(telemetry.get("recoveryRemaining", 0.0))
	if bool(telemetry.get("crashed", false)) and remaining > 0.0:
		_notice("Recovery available in %.1f s" % remaining, 2.0)
		return
	_invalidate_lap("Recovery — cross START to begin a fresh lap")
	rider_input.release_controls()
	bike.reset_bike(track.get("spawn", Transform3D.IDENTITY))
	bike.set_controls(rider_input.packet())
	previous_position = _chassis().global_position
	was_crashed = false
	camera_snap = true

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

func _update_camera(delta: float) -> void:
	var body: RigidBody3D = _chassis()
	var forward: Vector3 = -body.global_basis.z
	if Vector2(forward.x, forward.z).length() > 0.1:
		var desired_yaw: float = atan2(-forward.x, -forward.z)
		camera_yaw = desired_yaw if camera_snap else lerp_angle(camera_yaw, desired_yaw, 1.0 - exp(-3.0 * delta))
	var target: Vector3 = body.global_position + Vector3.UP * 0.85
	var yaw: float = camera_yaw + orbit_yaw
	var wanted: Vector3 = target + Vector3(sin(yaw) * orbit_distance, orbit_height, cos(yaw) * orbit_distance)
	camera.global_position = wanted if camera_snap else camera.global_position.lerp(wanted, 1.0 - exp(-7.0 * delta))
	camera.look_at(target, Vector3.UP)
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
	race_box.add_child(_label("SINGLEPLAYER · PHYSICS LAB", 13, TEAL))
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
	var hint: Label = _label("H  CONTROLS    U  PARKED SETUP    R  RECOVER    ESC  PAUSE    RIGHT MOUSE  CAMERA", 13, MUTED)
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
	(labels.posture as Label).text = "%s · %s" % ["STANDING" if bool(t.get("standing", false)) else "SEATED", "FEET DOWN" if bool(t.get("footDown", true)) else "FEET ON PEGS"]
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
		status = "%s · %s" % [str(t.get("crashReason", "Crash")), "R / Y: recover" if wait <= 0.0 else "recover in %.1f s" % wait]
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
	panel.custom_minimum_size.x = 640.0 if kind in ["help", "tuning"] else 550.0
	panel.add_theme_stylebox_override("panel", _panel_style(INK, Color("3b5066")))
	center.add_child(panel)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	panel.add_child(content)
	content.add_child(_label("DIRTLINE  /  MX", 15, TEAL))
	match kind:
		"welcome": _welcome_content(content)
		"pause": _pause_content(content)
		"help": _help_content(content)
		"settings": _settings_content(content)
		"tuning": _tuning_content(content)

func _welcome_content(content: VBoxContainer) -> void:
	content.add_child(_label("LEARN THE RIDE.", 36))
	content.add_child(_label("250F · Native motocross simulation lab", 19, ORANGE))
	var detail: Label = _label("A single test bike. A purpose-built proving ground.\nManual clutch, separate brakes and physical rider balance.\nNo steering or landing assistance.", 16, MUTED)
	content.add_child(detail)
	content.add_child(_label("Keyboard + controller · Windows PC", 15, TEAL))
	content.add_child(_button("LET’S RIDE", start_session, true))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var help: Button = _button("Controls", func() -> void: _show_modal("help"))
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(help)
	var settings: Button = _button("Display + sound", func() -> void: _show_modal("settings"))
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(settings)
	content.add_child(_label("DEVELOPMENT PROTOTYPE · Handling still requires riding validation.", 12, MUTED))
	content.add_child(_button("Exit", func() -> void: get_tree().quit()))

func _pause_content(content: VBoxContainer) -> void:
	content.add_child(_label("RIDE PAUSED", 32))
	content.add_child(_button("Resume ride", _resume, true))
	content.add_child(_button("Controls", func() -> void: _show_modal("help")))
	content.add_child(_button("Display + sound", func() -> void: _show_modal("settings")))
	content.add_child(_button("Suspension setup", func() -> void:
		if absf(float(bike.get_telemetry().get("speedMps", 0.0))) < 1.0:
			_show_modal("tuning")
		else:
			_notice("Park before changing suspension settings.")
			_resume()))
	content.add_child(_button("Exit game", func() -> void: get_tree().quit()))

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
	keyboard.add_child(_label("A / D  Steering     Z / X  Bike lean", 15))
	keyboard.add_child(_label("I / K  Body forward / back     J / L  Body left / right", 15))
	keyboard.add_child(_label("C  Seated / standing     F  Feet down / on pegs", 15))
	keyboard.add_child(_label("R  Recover     H  Help     U  Parked setup     ESC  Pause", 15))
	keyboard.add_child(_label("Hold right mouse to orbit · Mouse wheel changes camera distance", 14, MUTED))
	keyboard.add_child(_label("Starting: E → gentle W → hold B to release the clutch → F to raise feet.\nV/B hold the lever position. Steering and lean are separate rider inputs.", 14, TEAL))
	var controller: VBoxContainer = VBoxContainer.new()
	controller.name = "Controller"
	controller.add_theme_constant_override("separation", 8)
	tabs.add_child(controller)
	controller.add_child(_label("RT  Throttle     LT  Front brake     RB  Rear brake", 15))
	controller.add_child(_label("LB  Pull clutch; release LB to engage over 0.6 seconds", 15))
	controller.add_child(_label("Left stick  Steering     Right stick  Rider body forward / sideways", 15))
	controller.add_child(_label("D-pad ← / →  Bike lean     D-pad ↓ / ↑  Shift down / up", 15))
	controller.add_child(_label("A  Seated / standing     X  Feet down / on pegs     Y  Recover", 15))
	controller.add_child(_label("Left-stick click  Engine start     Right-stick click  Help", 15))
	controller.add_child(_label("Menu / Start  Pause     Mouse / keyboard  Suspension menus", 15))
	controller.add_child(_label("Standard Xbox / SDL mappings. Connect your controller before riding.\nThe game switches input source when you use a key or controller.", 14, TEAL))
	content.add_child(_label("Ride numbered gates in order to time a lap. Recovery cancels the lap.\nTest berms, ruts, braking bumps, whoops and the separate large-jump lane.", 14, MUTED))
	content.add_child(_button("Back to ride" if session_started else "Back", _resume if session_started else func() -> void: _show_modal("welcome"), true))

func _settings_content(content: VBoxContainer) -> void:
	content.add_child(_label("DISPLAY + SOUND", 28))
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
	content.add_child(_label("More compression damping slows compression; more rebound slows extension.\nPreload shifts sag. Spring rate changes load support. There is no balance assist.", 13, MUTED))
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

func _save_preferences() -> void:
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("sound", "engine", audio_enabled)
	preferences.set_value("display", "shadows", shadows_enabled)
	preferences.set_value("display", "fullscreen", fullscreen_enabled)
	preferences.set_value("display", "resolution_scale", resolution_scale)
	preferences.save("user://preferences.cfg")

func _apply_preferences() -> void:
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
