--!strict
-- SI-unit spring/damper contact law. Compression and velocity come from the
-- suspension geometry; this module never invents suspension movement.
local Suspension = {}

export type State = {
	compression: number,
	velocity: number,
	force: number,
	bottomed: boolean,
	contact: boolean,
}

export type Config = {
	RestLength: number,
	Travel: number,
	SpringRate: number,
	Compression: number,
	Rebound: number,
	Preload: number,
	BumpRate: number,
}

export type Output = {
	force: number,
	compression: number,
	velocity: number,
	bottomed: boolean,
}

local function finite(value: number, fallback: number): number
	return if value == value and math.abs(value) < math.huge then value else fallback
end

function Suspension.new(): State
	return { compression = 0, velocity = 0, force = 0, bottomed = false, contact = false }
end

function Suspension.step(state: State, compression: number, compressionVelocity: number, contact: boolean, _dt: number, cfg: Config): Output
	local travel = math.max(finite(cfg.Travel, 0.3), 0.001)
	local springRate = math.max(finite(cfg.SpringRate, 0), 0)
	local preload = math.max(finite(cfg.Preload, 0), 0)
	-- A geometry bug or penetration must not generate an unbounded impulse.
	-- Actual movement inside/just beyond travel still reaches the bump stop.
	local displacement = math.clamp(finite(compression, 0), 0, travel * 2)
	local velocity = finite(compressionVelocity, 0)
	local force = 0
	local bottomed = contact and displacement >= travel
	if contact then
		local damping = if velocity >= 0 then cfg.Compression else cfg.Rebound
		damping = math.max(finite(damping, 0), 0)
		local bumpBand = travel * 0.15
		local bumpCompression = math.max(displacement - (travel - bumpBand), 0)
		local bump = math.max(finite(cfg.BumpRate, 0), 0) * bumpCompression * bumpCompression / bumpBand
		local spring = springRate * (displacement + preload)
		-- Six times the fully compressed spring load is a numerical guard, not
		-- an adjustable landing assist. Contact cannot pull the chassis down.
		local forceLimit = math.max(springRate * (travel + preload) * 6, 1)
		force = math.clamp(finite(spring + damping * velocity + bump, forceLimit), 0, forceLimit)
	end
	state.compression = displacement
	state.velocity = velocity
	state.force = force
	state.bottomed = bottomed
	state.contact = contact
	return { force = force, compression = displacement, velocity = velocity, bottomed = bottomed }
end

return Suspension
