class_name DLSuspension
extends RefCounted
## Spring/damper law only: geometry supplies actual compression and velocity.
## All settings and outputs are SI (metres, seconds, newtons).

static func _finite(value: float, fallback: float) -> float:
	return fallback if is_nan(value) or is_inf(value) else value

static func new_state() -> Dictionary:
	return {"compression": 0.0, "velocity": 0.0, "force": 0.0, "bottomed": false, "contact": false}

## A native articulated axle remains attached while airborne. Its damper can
## pull the bodies together during extension; ground contact is independent.
## Native joint limits provide the mechanical full-extension/end-stop limits.
static func step_articulated(state: Dictionary, compression: float, rate: float, _dt: float, cfg: Dictionary) -> Dictionary:
	var travel: float = maxf(_finite(float(cfg.Travel), 0.3), 0.001)
	var spring_rate: float = maxf(_finite(float(cfg.SpringRate), 0.0), 0.0)
	var spring_preload: float = maxf(_finite(float(cfg.Preload), 0.0), 0.0)
	var displacement: float = clampf(_finite(compression, 0.0), 0.0, travel * 2.0)
	var velocity: float = _finite(rate, 0.0)
	var damping: float = float(cfg.Compression) if velocity >= 0.0 else float(cfg.Rebound)
	damping = maxf(_finite(damping, 0.0), 0.0)
	var bump_band: float = travel * 0.15
	var bump_compression: float = maxf(displacement - (travel - bump_band), 0.0)
	var bump: float = maxf(_finite(float(cfg.BumpRate), 0.0), 0.0) * bump_compression ** 2 / bump_band
	var spring: float = spring_rate * (displacement + spring_preload)
	var force_limit: float = maxf(spring_rate * (travel + spring_preload) * 6.0, 1.0)
	var force: float = clampf(_finite(spring + damping * velocity + bump, 0.0), -force_limit, force_limit)
	state.compression = displacement
	state.velocity = velocity
	state.force = force
	state.bottomed = displacement >= travel
	return {"force": force, "compression": displacement, "velocity": velocity, "bottomed": bool(state.bottomed)}

static func step(state: Dictionary, compression: float, rate: float, contact: bool, _dt: float, cfg: Dictionary) -> Dictionary:
	var travel: float = maxf(_finite(float(cfg.Travel), 0.3), 0.001)
	var spring_rate: float = maxf(_finite(float(cfg.SpringRate), 0.0), 0.0)
	var spring_preload: float = maxf(_finite(float(cfg.Preload), 0.0), 0.0)
	var displacement: float = clampf(_finite(compression, 0.0), 0.0, travel * 2.0)
	var velocity: float = _finite(rate, 0.0)
	var force: float = 0.0
	var bottomed: bool = contact and displacement >= travel
	if contact:
		var damping: float = float(cfg.Compression) if velocity >= 0.0 else float(cfg.Rebound)
		damping = maxf(_finite(damping, 0.0), 0.0)
		var bump_band: float = travel * 0.15
		var bump_compression: float = maxf(displacement - (travel - bump_band), 0.0)
		var bump: float = maxf(_finite(float(cfg.BumpRate), 0.0), 0.0) * bump_compression ** 2 / bump_band
		var spring: float = spring_rate * (displacement + spring_preload)
		# Guard against accidental extreme penetration; never pulls on contact.
		var force_limit: float = maxf(spring_rate * (travel + spring_preload) * 6.0, 1.0)
		force = clampf(_finite(spring + damping * velocity + bump, force_limit), 0.0, force_limit)
	state.compression = displacement
	state.velocity = velocity
	state.force = force
	state.bottomed = bottomed
	state.contact = contact
	return {"force": force, "compression": displacement, "velocity": velocity, "bottomed": bottomed}
