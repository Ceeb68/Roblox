--!strict
-- Observe physical failure; this module never applies a crash impulse, targets
-- an orientation, or modifies velocity. Tire/body forces produce the fall.
local Crash = {}

function Crash.evaluate(sample: any, cfg: any): string?
	if sample.landing then
		local roll = math.abs(sample.landingRoll or sample.roll or 0)
		local pitch = sample.landingPitch or sample.pitch or 0
		local impact = sample.normalImpactSpeed or 0
		if impact >= cfg.LandingSpeed and math.abs(pitch) >= cfg.LandingAngle then
			return if pitch < 0 then "Nose-heavy landing" else "Rear-heavy landing"
		end
		if (sample.sideLandingSpeed or 0) >= cfg.SideLandingSpeed and impact > 2 then
			return "Sideways landing"
		end
		if roll > cfg.LandingAngle and impact > 3 then
			return "Landing on the side"
		end
	end
	if sample.grounded then
		if (sample.pitch or 0) > cfg.LoopPitch and sample.rearContact then
			return "Loop-out"
		end
		if sample.rearGripRecovered and math.abs(sample.rollRate or 0) > 5 and math.abs(sample.roll or 0) > 0.5 then
			return "High-side"
		end
		if math.abs(sample.roll or 0) >= cfg.GroundRoll then
			if sample.frontSliding and (sample.frontUtilization or 0) >= 0.9 then
				return "Front-wheel washout"
			elseif sample.rearSliding then
				return "Rear-wheel low-side"
			end
			return "Lost balance"
		end
	end
	if sample.bodyContact then
		if math.abs(sample.roll or 0) >= cfg.GroundRoll then
			return "Lost balance"
		elseif math.abs(sample.pitch or 0) >= cfg.LoopPitch then
			return "Over-rotated impact"
		elseif (sample.speed or 0) > 3 then
			return "Chassis impact"
		end
	end
	return nil
end

function Crash.canRecover(crashedAt: number, now: number, cfg: any): boolean
	return now == now and crashedAt == crashedAt and math.abs(now) < math.huge
		and math.abs(crashedAt) < math.huge and now - crashedAt >= cfg.RecoveryDelay
end

return Crash
