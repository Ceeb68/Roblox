# Development assessment and roadmap

> Archived Roblox prototype notes. Active development moved to the standalone Godot game; see [standalone documentation](../standalone/README.md) and [native validation](../standalone/VALIDATION.md). The Roblox evidence below describes the earlier version.

## What existed before the simulation update

The initial `5fcc106` commit contains a procedural dirt circuit, an original orange/teal part-built bike, arcade force controls, automatic upright orientation, a race HUD, ordered checkpoint and lap validation, session best times, input ownership checks, a Rojo build, and 19 race-rule tests. It has no measured motorcycle data, production meshes or sounds, persistent progression, career, economy, purchases, AI, lobbies, or professional track collection. Its source/build checks passed; Roblox engine behavior was never verified here.

Retain the original circuit (`Track.luau`), lap rules, player lifecycle, ownership checks, visual identity, and reproducible toolchain. Replace the arcade controller and controls. The previous game remains recoverable from Git history; the new default is the physics lab.

## Current Phase 1 scope

One fictional **DL-MX 250F** four-stroke, one physics laboratory, and PC/controller controls. No bike catalog, monetization, or career systems are being added before handling is accepted.

| Area | Implementation | Validation status |
| --- | --- | --- |
| Units | SI configuration; 1 stud = 0.28 m; gravity = 9.81 m/s² | Numerical/build check |
| Chassis | Unrestrained Roblox rigid body; no upright or landing target | Studio acceptance pending |
| Tires | Independent axle loads, slip relaxation, camber thrust, combined force limit, surface coefficients | Pure model regressions |
| Suspension | Independent springs, preload, compression/rebound damping and progressive bump stops | Pure sprung-mass landing regression; Studio obstacles pending |
| Drivetrain | Neutral, five manual gears, clutch slip, torque curve, losses, engine braking, limiter, stall and starter | Pure momentum/energy and timestep regressions |
| Rider | Movable rider mass, standing/seated COM, bounded articulation reactions; procedural visual pose | Studio handling and pose acceptance pending |
| Air | Gravity and native angular momentum; rotor and rider reaction impulses | Rotor sign tests; full jump acceptance pending |
| Crashes | Observe physical pose/landing/traction failures; ejection and delayed manual recovery | Classification tests; physical fall behavior pending |
| Networking | Server-owned physics and ordered bounded input packets | Packet tests; latency/load tests pending |
| Physics lab | Flat pad, turns, berms, ruts, bumps, whoops, jumps and four grip patches | Source/geometry checks; ride acceptance pending |
| Assets | Procedural prototype parts and rider poses | Production meshes/audio/IK not supplied |

**Phase 1 is not complete.** Numerical tests do not prove convincing riding. Every required obstacle must pass the Studio matrix in `STUDIO_VALIDATION.md`; feedback and telemetry should drive calibration iterations before Phase 2.

Current automated evidence: **101 tests / 89,155 assertions passed** across contact physics, drivetrain, input/setup/crash boundaries, preserved lap rules, native-frame time budgeting, and suspension-axis contact equilibrium. Strict analysis of all pure modules/tests, compilation of all Luau, and the place build passed. All 16 embedded scripts match the source; live Rojo synchronization served those same scripts. None of these checks executes Roblox physics.

## Modular script and asset architecture

- `shared/Physics/Bike250`: fictional SI calibration and factory setup.
- `shared/Physics/Drivetrain`: crank, clutch, gearing, rear rotor and brake dynamics.
- `shared/Physics/Suspension`: measured compression/rate to supporting force.
- `shared/Physics/Tire`: independent front/rear contact state and combined traction.
- `shared/Physics/WheelContact`: suspension-axis equilibrium including normal and tangential tire forces.
- `shared/Physics/StepBudget`: preserves native elapsed time while bounding contact subdivisions and flagging overruns.
- `shared/Physics/Controls`: validated control schema and bounded setup edits.
- `shared/Physics/Crash`: observation of failures and recovery cooldown.
- `server/Bikes`: Roblox contacts, forces, mass, rider lifecycle, presentation state and telemetry.
- `server/TestTrack`: repeatable Phase 1 obstacles and surface tagging.
- `server/Track`: preserved original race course.
- `server/main`: before-simulation update, rider lifecycle, authoritative timing and action validation.
- `client/main`: PC/controller controls, telemetry, help and lab tuning.
- `client/RiderPose`: procedural presentation of actual rider control state.
- Future modules: `RaceSession`, `TimeTrialRecords`, `Garage`, `Career`, `Economy`, `ReceiptService`, `Profiles`, `Lobby`, `AI`, `BikeCatalog`, and licensed asset definitions. Create these only in their scheduled phases.

## Ordered roadmap and acceptance gates

1. **Core motorcycle gameplay (current):** iterate this 250F against all lab obstacles; establish input mappings, physical signs, stable contacts, crash/recovery, and measured frame/network budgets. Exit only after Studio handling acceptance.
2. **First professional MX track:** original Unadilla-inspired elevation/racing lines, start gates and optimized licensed scenery; validate it with the accepted bike. Existing part lab is not this production track.
3. **Racing and time trials:** build on retained lap rules; sectors, validated results, persistence of records, ghost feasibility and class records. Keep development-lab laps separate from records.
4. **Garage and currency:** versioned player profiles with retries, starter ownership, dealership and server-authoritative earn/spend transactions.
5. **Motorcycle collection:** research actual current 125/250/450 models and engine variants; record sources/licensing; author distinct geometry and measured calibration per bike. Do not infer a model from a recolor.
6. **Career:** amateur-to-pro events, seasons/standings, championship formats and physics-aware AI.
7. **Online racing:** lobbies, gate release, disconnect handling, fair authoritative results; evaluate prediction/reconciliation against the physics benchmark.
8. **Additional tracks:** separate MX/SX/AX layouts with obstacle/physics acceptance and performance budgets.
9. **Monetization and customization:** licensed graphics/rider cosmetics; Developer Products only after real IDs are configured; idempotent receipt fulfillment and fair progression.
10. **Polish:** measured optimization, professional meshes, rider IK/animations, properly licensed engine/terrain audio, accessibility, controller remapping, and an explicitly adapted mobile control scheme.

## Open risks and deliberately incomplete work

- No Roblox Studio or engine access is available in the Linux cloud task. Handling, contact ray edge behavior, actual joint poses, avatar collisions and load/latency behavior need Studio evidence.
- Ray contacts approximate pneumatic tire volume; they do not simulate deformable carcasses or deformable soil. Suspension is a force law, not a full fork/linkage mechanism.
- Extreme wheelie contact has a known modeling limitation: a rear suspension axis with ground-normal projection below 0.20 loses its ray contact before an 82° pitch threshold on flat terrain. The physical body can still fall/impact, but the early loop-out label and near-vertical rear-wheel support are not qualified. Test this explicitly and improve wheel-volume/linkage contact before accepting wheelie behavior; do not conceal it with a pitch cap or upright force.
- The native rigid body runs on Roblox's scheduler. The pure 240 Hz rotor/contact substeps do not turn Roblox into a deterministic 240 Hz custom world solver.
- Rider articulation is a bounded articulated-mass approximation. It is not a complete musculoskeletal rider simulation.
- Calibration is fictional engineering starting data; there is no claim of exact MX Bikes replication or measured production-motorcycle fidelity.
- Server ownership prioritizes one consistent physics model. Responsive prediction and competitive synchronization need later measured design work; this prototype is not a qualified competitive release.
- Professional motorcycle meshes, authorized manufacturer branding, recorded engine loops, rider IK and crash animations are outstanding asset work. See `ASSETS.md`.
- Mobile simulation controls, tuning persistence, garage, currency, career, AI and purchases remain unimplemented.
