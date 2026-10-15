class_name DLLeanControl
extends RefCounted
## A bounded roll-rate task for the existing finite handlebar actuator.
## The stopping-distance rate envelope brakes the requested bank before it
## crosses its target. This replaces an overdamped angle spring, not native
## roll, contact, inertia, gyroscopes, or the fork bearing.

static func target(lean: float, target_lean: float, bank_rate: float,
		speed: float, height: float, wheelbase: float, max_angle: float,
		recovering: bool, tune: Dictionary) -> Dictionary:
	# Predict the bank reached while finite bars and tire relaxation respond.
	# Feedback using only current angle countersteers too long, then tries to
	# stop angular momentum after the tire/handlebar actuator is already late.
	var predicted_bank := lean + bank_rate * float(tune.get("LeanPredictionTime", 0.18))
	var error := target_lean - predicted_bank
	var acceleration_limit := maxf(0.2, float(tune.get("LeanAcceleration", 6.0)))
	# Strong initial countersteering does not imply equally strong stopping
	# authority after the tires are already carrying a loaded corner. Keep
	# the approach-rate envelope inside the smaller reserve available to
	# arrest roll; the finite actuator may still react quickly to a command.
	var stopping_acceleration := clampf(float(tune.get("LeanStoppingAcceleration", 1.5)), 0.2, acceleration_limit)
	var speed_blend := smoothstep(1.0, 6.0, absf(speed))
	var rate_limit := float(tune.get("LeanRecoveryRate", 1.65) if recovering else tune.get("LeanRate", 1.8))
	rate_limit *= lerpf(0.5, 1.0, speed_blend)
	var stop_rate := sqrt(2.0 * stopping_acceleration * absf(error))
	var desired_rate := signf(error) * minf(rate_limit, minf(stop_rate,
		absf(error) / maxf(0.03, float(tune.get("LeanPositionTime", 0.16)))))
	var acceleration := clampf((desired_rate - bank_rate) /
		maxf(0.03, float(tune.get("LeanRateResponse", 0.12))), -acceleration_limit, acceleration_limit)
	var speed_squared := maxf(speed * speed, 2.0)
	# Inverted-pendulum feed-forward plus the desired measured roll acceleration.
	# A right bank begins with real countersteering, then steers into the corner.
	var equilibrium := 9.81 * wheelbase * tan(clampf(lean, -1.1, 1.1)) / speed_squared
	var steer := equilibrium - height * wheelbase / speed_squared * acceleration
	return {"steer": clampf(steer, -max_angle, max_angle),
		"rate": desired_rate, "acceleration": acceleration}
