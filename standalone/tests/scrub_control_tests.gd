extends SceneTree
## Scrub task/state regressions. Real trajectory changes must separately be
## proven by matched native jump approaches; these scalar tests cannot do so.
const Scrub = preload("res://physics/scrub_control.gd")
# Authored unit recipe keeps state/transition guards independent of later
# production calibration; actual release defaults have a separate contract.
const UNIT_TUNE := {"MaxCrouch": 0.16, "MaxReboundScale": 2.2}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (": " + detail if not detail.is_empty() else ""))
		push_error("SCRUB CONTROL FAIL: " + failures[-1])

func _face() -> Dictionary:
	return {"grounded": true, "bank": deg_to_rad(16.0), "speed": 18.0,
		"facePitch": deg_to_rad(15.0), "enabled": true}

func _prepare(task: RefCounted, frame: Dictionary, controls: Dictionary, hz := 240) -> Dictionary:
	var output: Dictionary = {}
	for _i: int in range(roundi(hz * 0.3)):
		output = task.update(frame, controls, 1.0 / hz, UNIT_TUNE)
	return output

func _eligibility() -> void:
	var controls := {"scrub": 1.0, "standing": true}
	for name: String in ["unsupported", "flat", "descending", "upright", "walking", "released", "disabled", "zero-strength"]:
		var task: RefCounted = Scrub.new()
		var frame := _face()
		var input := controls.duplicate()
		var tune: Dictionary = UNIT_TUNE.duplicate()
		match name:
			"unsupported": frame.grounded = false
			"flat": frame.facePitch = 0.0
			"descending": frame.facePitch = deg_to_rad(-15.0)
			"upright": frame.bank = 0.0
			"walking": frame.speed = 3.0
			"released": input.scrub = 0.0
			"disabled": frame.enabled = false
			"zero-strength": tune.Strength = 0.0
		var output: Dictionary
		for _i in range(120):
			output = task.update(frame, input, 1.0 / 240.0, tune)
		_check(not bool(output.active) and float(output.crouch) == 0.0 and float(output.reboundScale) == 1.0,
			name + " cannot create a scrub or add rebound resistance")
	for bank: float in [-16.0, 16.0]:
		var task: RefCounted = Scrub.new()
		var frame := _face()
		frame.bank = deg_to_rad(bank)
		var output := _prepare(task, frame, controls)
		_check(bool(output.active) and float(output.crouch) > 0.155 and float(output.crouch) <= 0.16,
			"Either physical bank direction can prepare the actual rider crouch", str(output))
		_check(float(output.reboundScale) > 2.19 and float(output.reboundScale) <= 2.2,
			"Supported preparation requests bounded passive rebound absorption")

func _air_hold_and_release() -> void:
	var task: RefCounted = Scrub.new()
	var frame := _face()
	var controls := {"scrub": 1.0, "standing": true}
	var prepared := _prepare(task, frame, controls)
	var held_crouch := float(prepared.crouch)
	frame.grounded = false
	controls.scrub = 0.0
	var output: Dictionary
	var held := true
	for _i in range(480):
		output = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
		held = held and float(output.crouch) == held_crouch and float(output.reboundScale) == 1.0 \
			and not bool(output.active) and bool(output.airborneHold)
	_check(held, "Unsupported release holds the existing crouch without a reactive leg extension or extra damping")
	frame.grounded = true
	frame.facePitch = 0.0
	for _i in range(18):
		output = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
	_check(float(output.crouch) == held_crouch,
		"A loaded landing first absorbs the impact before the crouch extends")
	var previous := held_crouch
	var smooth := true
	for _i in range(240):
		output = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
		var current := float(output.crouch)
		smooth = smooth and current <= previous + 0.0000001 and previous - current < 0.004
		previous = current
	_check(smooth and previous < 0.002 and float(output.reboundScale) == 1.0,
		"Loaded flat ground releases the crouch smoothly and monotonically")
	task.reset()
	frame.grounded = false
	output = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
	_check(float(output.crouch) == 0.0 and not bool(output.airborneHold),
		"Reset clears airborne scrub posture and phase history")

func _interruptible_and_adjustable() -> void:
	var task: RefCounted = Scrub.new()
	var frame := _face()
	var controls := {"scrub": 1.0, "standing": true}
	var first: Dictionary = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
	_check(float(first.crouch) > 0.0 and float(first.crouch) < 0.02,
		"New preparation begins immediately with a finite smooth crouch step")
	var midway: Dictionary
	for _i in range(12):
		midway = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
	controls.scrub = 0.0
	var released: Dictionary = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
	_check(float(released.crouch) < float(midway.crouch) and float(released.crouch) > 0.0,
		"A released scrub reverses continuously from its current physical pose target")
	controls.scrub = 1.0
	var resumed: Dictionary = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
	_check(float(resumed.crouch) > float(released.crouch) and float(resumed.crouch) - float(released.crouch) < 0.02,
		"A repeated scrub resumes without restarting or snapping")
	var standing_task: RefCounted = Scrub.new()
	var seated_task: RefCounted = Scrub.new()
	var standing := _prepare(standing_task, frame, controls)
	controls.standing = false
	var seated := _prepare(seated_task, frame, controls)
	_check(absf(float(seated.crouch) / float(standing.crouch) - 0.5) < 0.001,
		"Seated preparation respects its independently bounded leg travel")
	var adjusted_task: RefCounted = Scrub.new()
	var adjusted: Dictionary
	for _i in range(120):
		adjusted = adjusted_task.update(frame, {"scrub": 1.0, "standing": true}, 1.0 / 240.0,
			{"MaxCrouch": 0.10, "MaxReboundScale": 1.6})
	_check(float(adjusted.crouch) > 0.099 and float(adjusted.crouch) <= 0.10 \
		and float(adjusted.reboundScale) > 1.599 and float(adjusted.reboundScale) <= 1.6,
		"Crouch travel and passive rebound scale tune independently without source edits")
	var malformed_task: RefCounted = Scrub.new()
	var malformed: Dictionary = malformed_task.update({"grounded": true, "bank": NAN, "speed": INF,
		"facePitch": NAN, "enabled": true}, {"scrub": NAN}, 1.0 / 240.0, UNIT_TUNE)
	_check(is_finite(float(malformed.crouch)) and float(malformed.reboundScale) == 1.0 and not bool(malformed.active),
		"Invalid sensor/input numbers cannot start a scrub or propagate non-finite output")

func _convergence() -> void:
	var observations: Array[Vector3] = []
	for hz: int in [120, 240, 480]:
		var task: RefCounted = Scrub.new()
		var frame := _face()
		var controls := {"scrub": 1.0, "standing": true}
		var prepared := _prepare(task, frame, controls, hz)
		frame.grounded = false
		for _i: int in range(roundi(0.5 * hz)):
			task.update(frame, controls, 1.0 / hz, UNIT_TUNE)
		frame.grounded = true
		frame.facePitch = 0.0
		controls.scrub = 0.0
		var released: Dictionary
		for _i: int in range(roundi(0.4 * hz)):
			released = task.update(frame, controls, 1.0 / hz, UNIT_TUNE)
		observations.append(Vector3(float(prepared.crouch), float(prepared.reboundScale), float(released.crouch)))
	_check(observations[0].distance_to(observations[1]) < 0.00001 \
		and observations[1].distance_to(observations[2]) < 0.00001,
		"Preparation, unsupported hold and loaded release converge at120/240/480Hz", str(observations))

func _crest_timing() -> void:
	var task: RefCounted = Scrub.new()
	var frame := _face()
	var controls := {"scrub": 1.0, "standing": true}
	frame.crestApproach = 0.0
	var early := _prepare(task, frame, controls)
	_check(float(early.crouch) == 0.0 and float(early.reboundScale) == 1.0 and not bool(early.active),
		"An ascending early jump face cannot trigger the crest-timed scrub")
	frame.crestApproach = 1.0
	var first: Dictionary = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
	_check(float(first.crouch) > 0.0 and float(first.crouch) < 0.02 and bool(first.active),
		"Actual crest approach begins a responsive finite rider crouch")
	var prepared := _prepare(task, frame, controls)
	_check(float(prepared.crouch) > 0.155 and float(prepared.reboundScale) > 2.19,
		"The crest envelope can still reach the bounded full scrub preparation")
	frame.crestApproach = 0.0
	var released: Dictionary = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
	_check(float(released.crouch) < float(prepared.crouch) and float(released.crouch) > 0.15 \
		and float(released.reboundScale) == 1.0,
		"A receding loaded crest reverses preparation smoothly instead of snapping the rider")
	frame.crestApproach = 1.0
	var resumed: Dictionary = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
	_check(float(resumed.crouch) > float(released.crouch) and float(resumed.crouch) - float(released.crouch) < 0.02,
		"A renewed crest request resumes the current crouch without restarting")
	var held_crouch := float(resumed.crouch)
	frame.grounded = false
	frame.crestApproach = 0.0
	controls.scrub = 0.0
	var held: Dictionary
	for _i in range(120):
		held = task.update(frame, controls, 1.0 / 240.0, UNIT_TUNE)
	_check(float(held.crouch) == held_crouch and float(held.reboundScale) == 1.0 and bool(held.airborneHold),
		"Leaving the crest holds the prepared crouch throughout unsupported flight")
	for invalid: float in [-0.5, NAN, INF]:
		var invalid_task: RefCounted = Scrub.new()
		var invalid_frame := _face()
		invalid_frame.crestApproach = invalid
		var output := _prepare(invalid_task, invalid_frame, {"scrub": 1.0, "standing": true})
		_check(float(output.crouch) == 0.0 and not bool(output.active),
			"Invalid or negative crest observations cannot create preparation: " + str(invalid))
	var capped_task: RefCounted = Scrub.new()
	var capped_frame := _face()
	capped_frame.crestApproach = 2.0
	var capped := _prepare(capped_task, capped_frame, {"scrub": 1.0, "standing": true})
	_check(float(capped.crouch) <= 0.16 and float(capped.reboundScale) <= 2.2 \
		and absf(float(capped.crouch) - float(prepared.crouch)) < 0.0001,
		"An oversized crest observation saturates at ordinary bounded preparation")
	var partial_task: RefCounted = Scrub.new()
	var partial_frame := _face()
	partial_frame.crestApproach = 0.5
	var partial := _prepare(partial_task, partial_frame, {"scrub": 1.0, "standing": true})
	_check(absf(float(partial.crouch) / float(capped.crouch) - 0.5) < 0.001,
		"A partial terrain lookahead produces a progressive partial crouch")

func _release_default_contract() -> void:
	var task: RefCounted = Scrub.new()
	var frame := _face()
	var controls := {"scrub": 1.0, "standing": true}
	var first: Dictionary = task.update(frame, controls, 1.0 / 240.0, {})
	_check(float(first.crouch) > 0.0 and float(first.crouch) < 0.03,
		"Release default preparation begins with a bounded smooth target step")
	var settled: Dictionary
	for _i in range(72):
		settled = task.update(frame, controls, 1.0 / 240.0, {})
	_check(float(settled.crouch) > 0.275 and float(settled.crouch) <= 0.28 \
		and float(settled.reboundScale) > 3.49 and float(settled.reboundScale) <= 3.5,
		"Release defaults provide their independently validated0.24m/3.5x bounded scrub envelope")

func _run() -> void:
	_eligibility()
	_air_hold_and_release()
	_interruptible_and_adjustable()
	_convergence()
	_crest_timing()
	_release_default_contract()
	print("Scrub control: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
