# 250F simulation architecture

This replaces target-speed arcade control with contact forces and an unrestricted chassis. It is an experimental motorcycle model, not a verified MX Bikes physics port.

## Units and mass

Configuration is in metres, seconds, kilograms, newtons, newton-metres and radians. Convert positions/velocities with `metres = studs × 0.28`. Set Roblox gravity to `9.81 / 0.28 = 35.035714...` studs/s². The former 196.2 gravity would be approximately 5.6 g at this scale.

The adapter calibrates native assembly mass to the bike's 109 mass units plus 78 rider mass units. A force impulse is `N × dt / 0.28`; an angular impulse is `Nm × dt / 0.28²`. Force application at actual contact positions supplies roll, pitch, yaw and weight transfer through the rigid body instead of a prescribed heading.

## Wheel contacts and suspension

Each axle has its own raycast contact, spring compression, rate, rotor speed, contact normal, camber, surface, longitudinal slip and lateral slip. Contact geometry is measured from the bike, not from a flat-ground assumption. Springs support the chassis only when the wheel touches a surface.

Supporting force is `k × (compression + preload) + damping × compressionVelocity`, with separate compression/rebound coefficients and a progressive final-travel bump stop. Forces cannot pull the bike toward the road. Landing speed and geometry change compression/load, then tire force and body rotation. The collider handles chassis/terrain contact after the suspension runs out of travel.

The massless virtual wheel balances its full contact force along the suspension axis: `springForce = (N × normal + Fx × forward + Fy × right) · suspensionUp`. A bounded contact solve includes braking/cornering force in that balance. Simply dividing spring force by the normal-axis cosine would exaggerate axial support in a lean. Tire memory advances once; trial loads use a pure force evaluator. Unresolved axial load is reported rather than hidden by a balancing constraint.

The ray model currently rejects axis/normal projections below 0.20. On a flat rear-wheel wheelie this can lose support near 78.5° before the 82° loop-out classification condition. Body contact still produces a physical failure, but correct near-vertical wheel-volume/linkage support is unresolved. This is a required Phase 1 investigation, not accepted wheelie fidelity.

Front/rear setup values are independent and adjustable while parked in the lab. Edits reject unknown keys, nonfinite values and invalid ranges. Edits invalidate the unfinished development lap. Racing mode does not accept lab setup overrides.

## Tires

Slip ratio compares rolling speed `wheelOmega × radius` to actual longitudinal velocity. Slip angle comes from wheel-local lateral velocity. Distance-based relaxation prevents instant full-force direction changes. Camber contributes lateral thrust toward the physical lean.

A brush force law saturates the combined demand inside a load-sensitive `μ × normalLoad` force circle. Braking uses the same grip budget as cornering. Each contact reads a `PhysicsSurface` attribute, falling back to its Roblox material. Factory surface ordering is hardpack/concrete, loam/dirt, sand, mud. These are calibration values, not measured tire/soil data. Tire carcass deformation and dynamic soil deformation remain future work.

## Engine and drivetrain

The fictional 250F uses an RPM/torque curve, crank inertia, neutral plus five ratios, primary/final reductions, friction and pumping losses, a limiter, and a bounded idle-air governor. There is no automatic gear selection or commanded road speed.

Clutch engagement solves an angular impulse between the crank and reflected rear-wheel inertia. Its impulse is limited by clutch capacity and lever engagement. Ideal coupling cannot add kinetic energy; gearbox efficiency removes energy during either power-flow direction. Under load a clutch dump can stall the engine. An explicit starter action requires neutral or a pulled clutch.

Front and rear brakes are separate. Wheel brake impulses oppose rotation and cannot create reverse wheel motion. Tires can lock or spin because their wheel states are not set to road speed.

## Steering, leaning, rider and air

Handlebar input acts on steering dynamics with inertia, damping and trail aligning torque. Tire forces, camber and gyro terms act on the unconstrained chassis. The controller never asks the chassis to face a target yaw or match an upright/landing angle.

Rider fore/aft and side movement relocate a non-massless ballast. Standing raises it. Bounded rider angular articulation produces finite reaction impulses; holding a posture is not a source of unlimited airborne torque. Keyboard lean and handlebar controls are separate.

Virtual wheel/crank rotors contribute reaction and gyroscopic angular impulses because the cosmetic wheels have no native rotor inertia. With forces applied at ground contact, the adapter accounts for the total change in rotor angular momentum, including tire torque. Revving the driven wheel can raise the nose in air; rear braking can lower it. Steering and rider articulation can change real bike rotation; a whip/scrub is not a scripted animation or heading change.

Manual feet provide physical stationary support. They are not an invisible upright constraint. Raise them before riding. There are no default beginner balance, automatic steering, landing correction, or traction-control assists.

## Crashes and recovery

Crash classification observes actual body angle, wheel grip, ground contact and landing impact. Classification does not generate an artificial low-side/high-side impulse. The rider is detached after a failure; the bike continues under gravity, contacts and collisions. Manual recovery has a 2.5-second delay and abandons the unfinished lap.

A sliding tire alone is not a crash. A wheelie below the loop-out condition and a controlled airborne rotation are not automatically rejected. High-side identification requires regrip plus actual rapid body roll; a low-side requires actual loss of balance.

## Timing and networking

The server owns the bike. Input packets contain a monotonic sequence and bounded axes/booleans; client poses, velocities, lap results and arbitrary setup fields are never accepted. Controls arrive at 30 Hz and telemetry at 10 Hz.

`PreSimulation` supplies impulses before the native Roblox step. Pure rotor/contact calculations target 1/240 s with at most 12 contact subdivisions per native frame. The whole native interval must be integrated: discarding elapsed time would let gravity advance while halving support. Frames above the 50 ms contact budget use coarser contact subdivisions, remain explicitly flagged, and invalidate unfinished lab laps. The drivetrain internally subdivides stiff rotor coupling. Contacts and native body pose are sampled on Roblox's schedule; this is not a deterministic custom 240 Hz rigid-body solver. Measure frame overruns and obstacle stability in Studio; mathematical convergence does not prove the native engine will behave identically.

Server ownership can feel delayed at network latency. A predicted controller is deliberately deferred until this single-bike model is accepted and an authoritative reconciliation design can be benchmarked. The same factory model is required for eventual competitive sessions; optional assists would need separate rules and records.

## Evidence and limits

Pure tests check force signs, surface limits, combined grip, load sensitivity, clutch momentum/energy, shifting, stalling, wheel braking, rotor reactions, bounded input, setup isolation, recovery and lap order. A one-dimensional sprung-mass impact converges toward a smaller timestep reference and settles near analytical sag. These tests exercise real numerical laws but do not run Roblox, drive a full 3D bike, or validate whips/berms/landings in the engine.

See `STUDIO_VALIDATION.md` for the required engine acceptance loop. Do not label Phase 1 complete until that evidence is recorded.
