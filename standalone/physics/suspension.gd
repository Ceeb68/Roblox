class_name DLSuspension
extends RefCounted
## Passive wheel-rate spring, hydraulic damper and progressive rubber stop.
## Geometry supplies measured axial compression/rate. Settings and outputs use
## SI units: metres, seconds, newtons, joules and watts. Native joints supply
## mechanical extension/travel stops; this law never adds a ground force.

static func _finite(value: float, fallback: float) -> float:
	return fallback if is_nan(value) or is_inf(value) else value

static func new_state() -> Dictionary:
	return {"compression": 0.0, "velocity": 0.0, "force": 0.0,
		"bottomed": false, "contact": false, "springForce": 0.0,
		"bumpForce": 0.0, "elasticForce": 0.0, "damperForce": 0.0,
		"damperPower": 0.0, "elasticEnergy": 0.0, "unlimitedForce": 0.0,
		"forceLimit": 0.0, "limited": false, "damperVelocity": 0.0,
		"effectiveMass": 0.0, "bottomingDamperCoefficient": 0.0}

static func _force_limit(cfg: Dictionary, spring_rate: float, travel: float, preload_length: float) -> float:
	# The rubber stop remains independent of the main coil. This bound guards
	# pathological penetration; it does not clip the ordinary working stroke.
	var bump_scale := maxf(_finite(float(cfg.BumpRate), 0.0), 0.0) * travel * 0.15 * 4.0
	return maxf(maxf(spring_rate * (travel + preload_length) * 6.0, bump_scale), 1.0)

static func _damper_force(velocity: float, cfg: Dictionary, dt: float,
		effective_mass: float, bottom_damping: float) -> float:
	var compressing := velocity >= 0.0
	var low_key := "Compression" if compressing else "Rebound"
	var high_key := "HighSpeedCompression" if compressing else "HighSpeedRebound"
	var knee_key := "CompressionKneeSpeed" if compressing else "ReboundKneeSpeed"
	var low := maxf(_finite(float(cfg.get(low_key, 0.0)), 0.0), 0.0)
	# Low/high coefficients are slopes in N.s/m, not force multipliers. Above
	# the knee, a shim-stack-like second slope limits sharp shaft-speed forces
	# while preserving slow weight-transfer control. Force stays continuous.
	# Old setups without these fields retain the original linear damper.
	var high := maxf(_finite(float(cfg.get(high_key, low)), low), 0.0)
	var knee := maxf(_finite(float(cfg.get(knee_key, 0.5)), 0.5), 0.001)
	# A hydraulic bottoming cone only restricts compression oil flow near full
	# stroke. Its coefficient is independent of the elastic rubber bump stop.
	if compressing:
		low += bottom_damping
		high += bottom_damping
	var speed := absf(velocity)
	if effective_mass > 0.0 and dt > 0.0:
		# Integrate dv/dt=-F(v)/m analytically through this hydraulic step.
		# Applying C*v explicitly can reverse a light axle's relative velocity
		# and ADD energy when dt*C/m exceeds two. The averaged exact impulse
		# remains passive at any step size, with the same physical coefficients.
		var remaining := dt / effective_mass
		var end_speed := speed
		if speed > knee:
			var boundary_force := low * knee
			if high > 0.000001:
				var shift := (low - high) * knee / high
				var crossing := log((speed + shift) / maxf(knee + shift, 0.00000001)) / high if boundary_force > 0.0 else INF
				if remaining <= crossing:
					end_speed = maxf((speed + shift) * exp(-high * remaining) - shift, 0.0)
					remaining = 0.0
				else:
					end_speed = knee
					remaining -= crossing
			elif boundary_force > 0.0:
				var crossing := (speed - knee) / boundary_force
				if remaining <= crossing:
					end_speed = speed - boundary_force * remaining
					remaining = 0.0
				else:
					end_speed = knee
					remaining -= crossing
		if remaining > 0.0:
			end_speed *= exp(-low * remaining)
		return signf(velocity) * (speed - end_speed) * effective_mass / dt
	return signf(velocity) * (low * minf(speed, knee) + high * maxf(speed - knee, 0.0))

static func _evaluate(compression: float, rate: float, cfg: Dictionary,
		allow_tension: bool, dt: float, effective_mass: float) -> Dictionary:
	var travel := maxf(_finite(float(cfg.Travel), 0.3), 0.001)
	var spring_rate := maxf(_finite(float(cfg.SpringRate), 0.0), 0.0)
	var preload_length := maxf(_finite(float(cfg.Preload), 0.0), 0.0)
	var displacement := clampf(_finite(compression, 0.0), 0.0, travel * 2.0)
	var velocity := _finite(rate, 0.0)
	var bump_band := travel * 0.15
	var bump_compression := maxf(displacement - (travel - bump_band), 0.0)
	var bump_rate := maxf(_finite(float(cfg.BumpRate), 0.0), 0.0)
	var spring := spring_rate * (displacement + preload_length)
	var bump := bump_rate * bump_compression ** 2 / bump_band
	dt = maxf(_finite(dt, 0.0), 0.0)
	effective_mass = maxf(_finite(effective_mass, 0.0), 0.0)
	var bottom_coefficient := maxf(_finite(float(cfg.get("BottomOutCompression", 0.0)), 0.0), 0.0)
	# A hydraulic cone can begin earlier than the short rubber-stop contact.
	# Its physical axial length is separately tunable, without changing spring
	# energy, ordinary shaft damping or the native mechanical travel limit.
	var hydraulic_band := clampf(_finite(float(cfg.get("BottomOutTravel", bump_band)), bump_band), 0.001, travel)
	var hydraulic_compression := maxf(displacement - (travel - hydraulic_band), 0.0)
	var bottom_damping := bottom_coefficient * clampf(hydraulic_compression / hydraulic_band, 0.0, 1.0) ** 2
	var damper := _damper_force(velocity, cfg, dt, effective_mass, bottom_damping)
	var force_limit := _force_limit(cfg, spring_rate, travel, preload_length)
	var minimum := -force_limit if allow_tension else 0.0
	var unlimited := spring + damper + bump
	var elastic := clampf(spring + bump, minimum, force_limit)
	var force := clampf(_finite(unlimited, 0.0), minimum, force_limit)
	# The reported damper is the force actually available after a guard clamps
	# the result. This keeps its measured power passive even at the force bound.
	var applied_damper := force - elastic
	# The discrete average relative speed makes F*v*dt equal the damper's
	# finite kinetic-energy loss. Other native constraints/external forces are
	# handled by the engine; this is the passive hydraulic substep's work.
	var damper_velocity := velocity
	if effective_mass > 0.0:
		damper_velocity -= applied_damper * dt / (2.0 * effective_mass)
	var energy := spring_rate * (displacement ** 2 * 0.5 + preload_length * displacement)
	energy += bump_rate * bump_compression ** 3 / (3.0 * bump_band)
	return {"force": force, "compression": displacement, "velocity": velocity,
		"bottomed": displacement >= travel, "springForce": spring,
		"bumpForce": bump, "elasticForce": elastic, "damperForce": applied_damper,
		"damperPower": maxf(applied_damper * damper_velocity, 0.0),
		"elasticEnergy": energy, "unlimitedForce": unlimited,
		"forceLimit": force_limit, "limited": absf(force - unlimited) > 0.000001,
		"damperVelocity": damper_velocity, "effectiveMass": effective_mass,
		"bottomingDamperCoefficient": bottom_damping}

## An articulated axle stays attached in flight. Its hydraulic rebound may pull
## the bodies together; forces remain an equal/opposite internal strut pair.
static func step_articulated(state: Dictionary, compression: float, rate: float,
		dt: float, cfg: Dictionary, effective_mass: float = 0.0) -> Dictionary:
	var output := _evaluate(compression, rate, cfg, true, dt, effective_mass)
	state.merge(output, true)
	return output

## The isolated contact-law bench cannot pull on the ground. Native motorcycle
## suspension uses step_articulated; both paths share the same material law.
static func step(state: Dictionary, compression: float, rate: float, contact: bool,
		dt: float, cfg: Dictionary, effective_mass: float = 0.0) -> Dictionary:
	var output := _evaluate(compression, rate, cfg, false, dt, effective_mass)
	if not contact:
		for key: String in ["force", "springForce", "bumpForce", "elasticForce",
				"damperForce", "damperPower", "elasticEnergy", "unlimitedForce"]:
			output[key] = 0.0
		output.bottomed = false
		output.limited = false
	state.merge(output, true)
	state.contact = contact
	return output
