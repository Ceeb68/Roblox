extends SceneTree
## User-authored setups are untrusted persistent data. Exercise atomic rejection,
## preservation of native bike parameters, a real reload, and the parked menu/API.
const Setup = preload("res://physics/handling_setup.gd")
const Tire = preload("res://physics/tire.gd")

var checks := 0
var failures: Array[String] = []
var baseline: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("HANDLING SETUP FAIL: " + message)

func _run() -> void:
	baseline = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	_validation()
	_persistence()
	await _native_menu()
	print("Handling setup: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _validation() -> void:
	var original := baseline.duplicate(true)
	var result := Setup.apply(baseline, {"Tire": {"Front": {"GripScale": 0.9}},
		"AirControl": {"PitchRate": 1.25}, "Assistance": {"Strength": 0.65}})
	check(bool(result.ok), "Supported independent setup values are accepted")
	check(baseline == original, "Applying a setup never mutates the original motorcycle configuration")
	if bool(result.ok):
		check(is_equal_approx(result.config.Tire.Front.GripScale, 0.9), "Front setup reaches its axle override")
		check(result.config.Suspension == baseline.Suspension and result.config.Drive == baseline.Drive,
			"Handling changes preserve engine and suspension parameters")
		check(result.config.Tire.Rear == baseline.Tire.Rear, "Changing front grip preserves independent rear configuration")
		var front_before := Tire.axle_settings(baseline.Tire, "Front")
		var front_after := Tire.axle_settings(result.config.Tire, "Front")
		var rear_before := Tire.axle_settings(baseline.Tire, "Rear")
		var rear_after := Tire.axle_settings(result.config.Tire, "Rear")
		var input := {"normalLoad": 920.0, "contact": true, "longitudinalVelocity": 12.0,
			"lateralVelocity": 2.0, "wheelOmega": 12.0 / 0.335, "radius": 0.335, "camber": 0.0}
		var state := Tire.new_state()
		state.slipAngle = 0.16
		var surface := {"Grip": 0.85, "Rolling": 0.025}
		var f0 := Tire.evaluate(state, input, front_before, surface)
		var f1 := Tire.evaluate(state, input, front_after, surface)
		var r0 := Tire.evaluate(state, input, rear_before, surface)
		var r1 := Tire.evaluate(state, input, rear_after, surface)
		check(absf(f1.capacityY / f0.capacityY - 0.9) < 0.000001,
			"Front setup changes the production tire's force budget by the requested amount")
		check(is_equal_approx(r0.capacityY, r1.capacityY), "Front tuning leaves actual rear tire capacity unchanged")
	var malformed: Array = [null, [], true, "1.0", {"Unknown": {"Strength": 1.0}},
		{"Tire": {"TyreGrip": 1.0}}, {"Tire": {"Front": {"GripScale": INF}}},
		{"AirControl": {"PitchRate": NAN}}, {"Assistance": {"Strength": true}},
		{"AirControl": {"PitchRate": "1.2"}}, {"AirControl": {"PitchRate": 100.0}},
		{"Tire": {"Front": {"GripScale": -0.5}}}, {"Tire": {}},
		{"Tire.Front.GripScale": 0.8}, {5: 1.0}, {"Tire": {"Front": [0.8]}},
		{"AirControl": {"PitchRate": 1.2}, "Engine": {"IdleRPM": 2000.0}}]
	var rejected := true
	var unchanged := true
	for candidate: Variant in malformed:
		var trial := Setup.apply(baseline, candidate)
		rejected = rejected and not bool(trial.ok) and not trial.has("config")
		unchanged = unchanged and baseline == original
	check(rejected, "Malformed, nonfinite, out-of-range and unknown values reject the entire setup")
	check(unchanged, "Invalid mixed setups cannot partially alter valid fields or source data")
	var snapshot := Setup.snapshot(baseline)
	check(bool(Setup.apply(baseline, snapshot).ok), "The shipped defaults are within every supported tuning range")
	check(is_equal_approx(Setup.value_at(Setup.snapshot({}), "AirControl.YawRate", 0.0), 1.3),
		"Older configuration files receive useful defaults for newly supported controls")
	var cloned: Dictionary = result.config if bool(result.ok) else {}
	if not cloned.is_empty():
		cloned.Tire.Front.GripScale = 0.6
	check(baseline == original, "Changing a returned nested config cannot alias the original")

func _persistence() -> void:
	var path := "user://handling-setup-regression-%d.cfg" % OS.get_process_id()
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.remove_absolute(absolute)
	var absent := Setup.load_file(path, baseline)
	check(bool(absent.ok) and not bool(absent.loaded) and absent.config == baseline,
		"First boot keeps the shipped setup when no local file exists")
	var values := Setup.snapshot(baseline)
	values.AirControl.RollRate = 1.6
	values.Tire.Rear.GripScale = 0.85
	check(Setup.save_file(path, values) == OK, "An authored setup saves to a real local config file")
	var loaded := Setup.load_file(path, baseline)
	check(bool(loaded.ok) and bool(loaded.loaded) and is_equal_approx(loaded.config.AirControl.RollRate, 1.6)
		and is_equal_approx(loaded.config.Tire.Rear.GripScale, 0.85), "Independent tuning values survive an actual file reload")
	check(baseline.Drive == loaded.config.Drive and baseline.Suspension == loaded.config.Suspension,
		"Persisted handling does not replace unrelated native physics configuration")
	var previous := FileAccess.get_file_as_bytes(path)
	check(Setup.save_file(path, {"AirControl": {"RollRate": INF}}) == ERR_INVALID_DATA
		and FileAccess.get_file_as_bytes(path) == previous, "Rejected save preserves the user's previous valid file")
	var file := ConfigFile.new()
	file.set_value("handling", "version", Setup.FORMAT_VERSION)
	file.set_value("handling", "values", {"AirControl": {"RollRate": 1.6}, "Engine": {"IdleRPM": 1}})
	file.save(path)
	var rejected := Setup.load_file(path, baseline)
	check(not bool(rejected.ok) and not rejected.has("config"), "Unknown fields in a saved file cannot silently change the engine")
	file.set_value("handling", "version", Setup.FORMAT_VERSION + 1)
	file.save(path)
	check(not bool(Setup.load_file(path, baseline).ok), "Unsupported saved format versions are rejected")
	var raw := FileAccess.open(path, FileAccess.WRITE)
	raw.store_string("this is not a config file")
	raw.close()
	check(not bool(Setup.load_file(path, baseline).ok), "Malformed local config fails safely without partial settings")
	DirAccess.remove_absolute(absolute)

func _native_menu() -> void:
	var saved_files: Dictionary = {}
	var paths: Array[String] = ["user://handling.cfg", "user://preferences.cfg", "user://controller_bindings.cfg"]
	for path: String in paths:
		if FileAccess.file_exists(path):
			saved_files[path] = FileAccess.get_file_as_bytes(path)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game: Node3D = packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.start_session()
	paused = true
	var original: Dictionary = game.bike.config.duplicate(true)
	game.bike.chassis.linear_velocity = Vector3(0.0, 0.0, -2.0)
	check(not game.bike.apply_handling_setup({"Assistance": {"Strength": 0.5}})
		and game.bike.config == original, "Native API rejects setup changes while riding")
	game.bike.chassis.linear_velocity = Vector3.ZERO
	game.bike.crashed = true
	check(not game.bike.apply_handling_setup({"Assistance": {"Strength": 0.5}})
		and not game._handling_available(), "A crashed bike cannot change handling before recovery")
	game.bike.crashed = false
	game.rider_input.throttle = 1.0
	game._open_handling_setup()
	await process_frame
	await process_frame
	check(game.modal_kind == "handling" and paused and game.rider_input.throttle == 0.0,
		"Opening Handling setup pauses the native game and releases riding inputs")
	check(game.handling_fields.size() == Setup.FIELDS.size(), "Every supported setting has an editable menu field")
	check(game.get_viewport().gui_get_focus_owner() is Button,
		"Handling menu provides an initial keyboard / controller focus target")
	var scroll := game.handling_fields["AirControl.PitchRate"].get_parent().get_parent().get_parent() as ScrollContainer
	check(scroll != null and scroll.size.y <= root.get_visible_rect().size.y - 80.0,
		"The complete handling menu scrolls within the window height")
	(game.handling_fields["Assistance.Strength"] as SpinBox).value = 0.65
	(game.handling_fields["RiderAnimation.CornerTransitionTime"] as SpinBox).value = 0.2
	game._apply_handling()
	check(game.modal_kind.is_empty() and not paused and is_equal_approx(game.bike.config.Assistance.Strength, 0.65),
		"Apply reaches the actual bike configuration and resumes riding")
	check(is_equal_approx(game.bike._rider_visual._animation_settings.CornerTransitionTime, 0.2),
		"Applied animation timing reaches the live rider rig")
	var persisted := Setup.load_file("user://handling.cfg", baseline)
	check(bool(persisted.ok) and is_equal_approx(persisted.config.Assistance.Strength, 0.65),
		"The native menu saves the applied setup for the next launch")
	game._open_handling_setup()
	game._restore_handling_baseline()
	check(is_equal_approx(game.handling_fields["Assistance.Strength"].value,
		Setup.value_at(baseline, "Assistance.Strength", 1.0)), "Restore defaults loads the shipped value into the menu")
	check(is_equal_approx(game.bike.config.Assistance.Strength, 0.65),
		"Restoring menu fields waits for Apply before altering live physics")
	game._apply_handling()
	check(is_equal_approx(game.bike.config.Assistance.Strength,
		Setup.value_at(baseline, "Assistance.Strength", 1.0)), "Applying restored defaults reaches the native bike")
	game.queue_free()
	paused = false
	await process_frame
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if saved_files.has(path):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(saved_files[path])
			file.close()
