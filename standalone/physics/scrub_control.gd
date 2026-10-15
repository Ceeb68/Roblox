class_name DLScrubControl
extends RefCounted
## Grounded scrub preparation for the EXISTING rider and suspension actuators.
## The output lowers the actual rider's compliant leg target and increases
## passive rebound resistance while a loaded tire climbs the jump face.
## No chassis force, torque, transform or airborne downforce is produced.

# Crouch is metres, angles radians, speed m/s, and response/hold values seconds.
# ReboundScale multiplies both low- and high-speed passive rebound coefficients.
const DEFAULTS := {
	"Strength": 1.0, "MaxCrouch": 0.28, "MaxReboundScale": 3.5,
	"MinBank": 0.0523598775598299, "FullBank": 0.20943951023932,
	"MinFace": 0.0698131700797732, "FullFace": 0.20943951023932,
	"MinSpeed": 6.0, "FullSpeed": 12.0,
	"CrouchResponse": 0.045, "ReboundResponse": 0.025,
	"ReleaseResponse": 0.20, "LandingHoldTime": 0.08,
	"SeatedCrouchFraction": 0.5,
	# Applied by the existing controller to actual rider/frame leg damping,
	# using their effective mass and spring stiffness;1 is critical damping.
	"LegDampingRatio": 0.6
}

var _crouch := 0.0
var _preparation := 0.0
var _airborne := false
var _landing_hold_remaining := 0.0

func reset() -> void:
	_crouch = 0.0
	_preparation = 0.0
	_airborne = false
	_landing_hold_remaining = 0.0

static func _number(value: Variant, fallback: float) -> float:
	if not (value is float or value is int):
		return fallback
	var result := float(value)
	return result if is_finite(result) else fallback

static func _value(cfg: Dictionary, key: String) -> float:
	return _number(cfg.get(key, DEFAULTS[key]), float(DEFAULTS[key]))

static func _ramp(value: float, minimum: float, full: float) -> float:
	return smoothstep(minimum, maxf(minimum + 0.0001, full), value)

## frame: grounded(positive real tire support), bank(rad), speed(m/s),
## facePitch(rad; ascending positive), enabled(virtual rider && !crashed),
## crestApproach(optional0..1 terrain-lookahead envelope; omitted means1).
## controls: scrub(0..1), standing(bool or 0..1 posture blend).
## Apply crouch through the existing real rider support target. Apply the
## reboundScale only to passive damping, never spring force or ground load.
func update(frame: Dictionary, controls: Dictionary, dt: float, cfg: Dictionary = {}) -> Dictionary:
	var result := {"crouch": 0.0, "reboundScale": 1.0, "active": false,
		"preparation": 0.0, "airborneHold": false}
	var strength := clampf(_value(cfg, "Strength"), 0.0, 1.0)
	if not bool(frame.get("enabled", false)) or strength <= 0.0:
		reset()
		return result
	var elapsed := maxf(0.0, _number(dt, 0.0))
	if elapsed <= 0.0:
		result.crouch = _crouch
		result.airborneHold = _airborne and _crouch > 0.00001
		return result
	var max_crouch := maxf(0.0, _value(cfg, "MaxCrouch"))
	_crouch = clampf(_crouch, 0.0, max_crouch)
	if not bool(frame.get("grounded", false)):
		# Internal movement cannot reduce the unsupported assembly's ballistic
		# trajectory. Preserve the last supported crouch instead of commanding
		# a reactive leg extension that pitches the bike in the middle of a whip.
		_airborne = true
		_preparation = 0.0
		_landing_hold_remaining = 0.0
		result.crouch = _crouch
		result.airborneHold = _crouch > 0.00001
		return result
	if _airborne:
		_landing_hold_remaining = maxf(0.0, _value(cfg, "LandingHoldTime"))
	_airborne = false
	var requested := clampf(_number(controls.get("scrub", 0.0), 0.0), 0.0, 1.0)
	var bank := absf(_number(frame.get("bank", 0.0), 0.0))
	var speed := absf(_number(frame.get("speed", 0.0), 0.0))
	var face := _number(frame.get("facePitch", 0.0), 0.0)
	var crest := clampf(_number(frame.get("crestApproach", 1.0), 0.0), 0.0, 1.0)
	var preparation := requested * strength \
		* _ramp(bank, maxf(0.0, _value(cfg, "MinBank")), _value(cfg, "FullBank")) \
		* _ramp(face, maxf(0.0, _value(cfg, "MinFace")), _value(cfg, "FullFace")) \
		* _ramp(speed, maxf(0.0, _value(cfg, "MinSpeed")), _value(cfg, "FullSpeed")) * crest
	var active := preparation > 0.00001
	if active:
		_landing_hold_remaining = 0.0
	var posture: Variant = controls.get("standing", false)
	var standing := 1.0 if posture is bool and bool(posture) else 0.0
	if posture is float or posture is int:
		standing = clampf(_number(posture, 0.0), 0.0, 1.0)
	var posture_fraction := lerpf(clampf(_value(cfg, "SeatedCrouchFraction"), 0.0, 1.0), 1.0, standing)
	var target := max_crouch * preparation * posture_fraction
	var response := _value(cfg, "CrouchResponse") if target > _crouch else _value(cfg, "ReleaseResponse")
	if _landing_hold_remaining > 0.0 and not active:
		# A real supported landing absorbs the impact before the legs extend.
		# The hold is finite and does not require keeping the scrub input held.
		var held := minf(elapsed, _landing_hold_remaining)
		_landing_hold_remaining -= held
		elapsed -= held
	if elapsed > 0.0:
		_crouch += (target - _crouch) * (1.0 - exp(-elapsed / maxf(0.001, response)))
	_preparation += (preparation - _preparation) \
		* (1.0 - exp(-maxf(0.0, dt) / maxf(0.001, _value(cfg, "ReboundResponse"))))
	result.crouch = clampf(_crouch, 0.0, max_crouch)
	# Outside an ascending loaded face, no extra suspension damping remains.
	# The rider may still be returning smoothly from a crouch on flat ground.
	result.reboundScale = 1.0 + (maxf(1.0, _value(cfg, "MaxReboundScale")) - 1.0) \
		* (_preparation if active else 0.0)
	result.active = active
	result.preparation = preparation
	return result
