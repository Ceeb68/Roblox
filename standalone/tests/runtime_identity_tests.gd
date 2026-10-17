extends SceneTree
## Observer-only provenance through real main-scene startup and existing menus.
## Back up every user file touched; run with a unique XDG runtime as well.
const Setup = preload("res://physics/handling_setup.gd")
const Main = preload("res://scenes/main.tscn")
const PATHS: Array[String] = ["user://handling.cfg", "user://preferences.cfg", "user://controller_bindings.cfg"]
var saved_files: Dictionary = {}
var baseline: Dictionary
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("RUNTIME IDENTITY FAIL: " + label)

func _make_game() -> Node3D:
	var game: Node3D = Main.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	return game

func _free_game(game: Node3D) -> void:
	game.queue_free()
	await process_frame
	paused = false

func _find_mode_selector(node: Node) -> OptionButton:
	if node is OptionButton and node.item_count == 2 and node.get_item_text(0) == "Lean control · virtual rider":
		return node
	for child: Node in node.get_children():
		var found := _find_mode_selector(child)
		if found != null:
			return found
	return null

func _run() -> void:
	for path: String in PATHS:
		if FileAccess.file_exists(path):
			saved_files[path] = FileAccess.get_file_as_bytes(path)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	baseline = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	var authored := Setup.snapshot(baseline)
	authored.Tire.Front.GripScale = 0.65
	authored.Tire.Rear.GripScale = 0.90
	authored.VirtualRider.IntentResponse = 0.19
	check(Setup.save_file(PATHS[0], authored) == OK, "Custom fixture handling saves through the actual serializer")
	var preferences := ConfigFile.new()
	preferences.set_value("riding", "mode", "direct")
	check(preferences.save(PATHS[1]) == OK, "Manual-mode fixture preference is a real persisted file")
	var game := await _make_game()
	var custom: Dictionary = game.get_runtime_receipt()
	check(custom.gameVersion == str(ProjectSettings.get_setting("application/config/version", "")),
		"Receipt uses the loaded project's actual game version")
	check(custom.physicsControllerPath == str(game.bike.get_script().resource_path)
		and custom.physicsControllerNode == str(game.bike.get_path()), "Receipt identifies the actual instantiated physics controller and node")
	check(custom.defaultJsonSha256 == FileAccess.get_sha256("res://config/bike_250f.json"),
		"Receipt fingerprints the packaged default JSON bytes")
	check(custom.ridingMode == "direct" and game.bike.riding_mode == "direct", "Real startup exposes persisted manual mode without resetting it")
	check(custom.savedHandlingLoadStatus == "loaded" and custom.savedHandlingLoadError.is_empty(),
		"A valid saved setup is distinguished from absent or rejected data")
	check(not bool(custom.handlingMatchesDefaults) and custom.effectiveSnapshotSha256 != custom.defaultSnapshotSha256,
		"Custom effective handling is visibly different from shipped defaults")
	check(is_equal_approx(float(custom.frontGripScale), 0.65) and is_equal_approx(float(custom.rearGripScale), 0.90)
		and is_equal_approx(float(custom.intentResponseS), 0.19), "Receipt values describe the built bike's actual independent grips and response")
	check(custom.inputPath == "keyboard" and int(custom.selectedControllerId) == int(game.rider_input.controller_id),
		"Receipt describes the active real input route independently of riding mode")
	var displayed: String = game._physics_text(game.bike.get_telemetry())
	check(displayed.contains(custom.gameVersion) and displayed.contains(custom.physicsControllerPath)
		and displayed.contains("CUSTOM #" + str(custom.effectiveSnapshotSha256).left(8)) and displayed.contains("direct"),
		"Existing F8 display contains loaded version, controller, custom fingerprint and manual mode")
	var old_hash: String = custom.effectiveSnapshotSha256
	custom.effectiveSnapshotSha256 = "tampered observer copy"
	check(game.get_runtime_receipt().effectiveSnapshotSha256 == old_hash, "Reading a receipt cannot mutate cached identity or the motorcycle")
	game._show_modal("handling")
	await process_frame
	game._restore_handling_baseline()
	check(not bool(game.get_runtime_receipt().handlingMatchesDefaults), "Loading defaults into menu fields does not falsely report a physics change before Apply")
	game._apply_handling()
	var restored: Dictionary = game.get_runtime_receipt()
	check(bool(restored.handlingMatchesDefaults) and restored.effectiveSnapshotSha256 == restored.defaultSnapshotSha256,
		"Applying restored defaults refreshes the actual effective fingerprint")
	check(restored.ridingMode == "direct", "Restoring handling values still truthfully reports the separately saved manual mode")
	check(restored.lastHandlingSaveStatus == "saved", "Successful Apply reports its real save result")
	game._show_modal("settings")
	await process_frame
	var selector := _find_mode_selector(game.modal)
	check(selector != null, "The existing riding-mode selector remains available")
	if selector != null:
		selector.select(0)
		selector.item_selected.emit(0)
	var changed_mode: Dictionary = game.get_runtime_receipt()
	check(changed_mode.ridingMode == "virtual_rider" and game.bike.riding_mode == "virtual_rider"
		and changed_mode.effectiveSnapshotSha256 == restored.effectiveSnapshotSha256,
		"Existing settings mode selection refreshes provenance without pretending the numerical handling changed")
	game._show_modal("tuning")
	await process_frame
	check(is_equal_approx((game.tuning_fields["Front.Compression"] as SpinBox).value,
		float(baseline.Suspension.Front.Compression)), "Opening suspension setup preserves the shipped 850 N.s/m coefficient")
	game._apply_tuning()
	check(bool(game.get_runtime_receipt().handlingMatchesDefaults), "Unchanged suspension Apply preserves exact shipped coefficients and effective identity")
	game._show_modal("tuning")
	await process_frame
	(game.tuning_fields["Front.SpringRate"] as SpinBox).value += 500.0
	game._apply_tuning()
	check(not bool(game.get_runtime_receipt().handlingMatchesDefaults), "Actual suspension setup is included in the effective handling fingerprint")
	game._show_modal("tuning")
	await process_frame
	game._restore_tuning_baseline()
	game._apply_tuning()
	check(bool(game.get_runtime_receipt().handlingMatchesDefaults), "Restoring and applying suspension defaults returns the identical effective handling fingerprint")
	var same_suspension := true
	for axle: String in baseline.Suspension:
		for key: String in baseline.Suspension[axle]:
			same_suspension = same_suspension and is_equal_approx(float(game.bike.config.Suspension[axle][key]), float(baseline.Suspension[axle][key]))
	check(same_suspension, "Restored front and rear suspension retain every original physical coefficient")
	var float_representation := baseline.duplicate(true)
	for axle: String in float_representation.Suspension:
		for key: String in float_representation.Suspension[axle]:
			float_representation.Suspension[axle][key] = float(float_representation.Suspension[axle][key])
	check(JSON.stringify(game._runtime_handling_snapshot(baseline)).sha256_text()
		== JSON.stringify(game._runtime_handling_snapshot(float_representation)).sha256_text(),
		"Identical physical coefficients hash identically with integer or float representations")
	await _free_game(game)
	var invalid := ConfigFile.new()
	invalid.set_value("handling", "version", Setup.FORMAT_VERSION)
	invalid.set_value("handling", "values", {"Tire": {"Front": {"GripScale": 0.65}}, "Engine": {"IdleRPM": 1}})
	invalid.save(PATHS[0])
	game = await _make_game()
	var rejected: Dictionary = game.get_runtime_receipt()
	check(rejected.savedHandlingLoadStatus == "rejected" and not str(rejected.savedHandlingLoadError).is_empty(),
		"Actual startup reports a rejected saved setup and its validation error")
	check(bool(rejected.handlingMatchesDefaults) and game.bike.config == baseline,
		"Rejected mixed data is reported as actual shipped defaults rather than partially applied custom settings")
	await _free_game(game)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATHS[0]))
	game = await _make_game()
	var absent: Dictionary = game.get_runtime_receipt()
	check(absent.savedHandlingLoadStatus == "absent" and absent.savedHandlingLoadError.is_empty()
		and bool(absent.handlingMatchesDefaults), "First-boot defaults are distinguishable from an invalid-file fallback")
	await _free_game(game)
	for path: String in PATHS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if saved_files.has(path):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(saved_files[path])
			file.close()
	print("Runtime identity: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
