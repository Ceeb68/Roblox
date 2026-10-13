# Required Roblox Studio physics acceptance

Status: **not run**. This cloud task does not have Roblox Studio or its physics engine. Record actual observations and Output errors here; do not check a row because a script compiled.

## Repeatable setup

Open the latest `DirtlineMX.rbxlx`, start one-player Play, and use the physics lab. Use the factory suspension setup first. The HUD exposes RPM, gear, clutch, slip and suspension travel. Keep frame rate, control device, surface and setup identical across comparisons. For diagnosis, read the owned bike's server telemetry from `Bikes:getTelemetry(player)` or add temporary Studio logging at 10 Hz. Logs should include timestamp, speed, throttle, front/rear brake, clutch, gear, RPM, contact state, axle load, compression/rate, slips, roll/pitch, angular rates and crash reason.

Start in neutral with feet down. Pull the clutch, select first, open throttle and release the clutch progressively. Raise feet using F once moving. Do not tune springs to compensate for a unit, force-sign or geometry error.

## Engine and obstacle matrix

| Test | Procedure and acceptance | Status |
| --- | --- | --- |
| Units/mass/settling | Inspect gravity 35.035714, chassis/ballast masses and contact normals. Stationary sag should match configured load and preload without a jittering body. Feet are physical support. | Not run |
| Manual launch | Neutral throttle does not drive; pulled clutch isolates rear tire; first-gear launch responds progressively; dumping clutch with rear brake stalls. T restarts only with clutch/neutral. | Not run |
| Manual shifts | Q/E or D-pad changes one gear; gear/RPM ratios change without snapping vehicle speed; loaded shifts reject; limiter cuts ignition and does not force wheel speed. | Not run |
| Independent brakes | Front-only braking transfers load forward and can wash the front while cornering; rear-only braking unloads/slides the rear. Brakes never propel in reverse. | Not run |
| Flat pad/turn | Straight run does not need an invisible heading lock. Countersteering and rider weight produce physical lean. Excess lean/slip causes a fall; reducing input can recover modest slip. | Not run |
| Surface patches | Repeat a fixed-speed braking/turning exercise on hardpack, dirt, sand and mud. Confirm separate contact tags/coefficients and plausibly different grip/rolling loss. | Not run |
| Berms | Tire normals and lean follow actual bank geometry. Banking alone must not trigger a crash. Turn forces build through contacts rather than instant yaw changes. | Not run |
| Ruts | Front/rear loads and steering react at different times; a wheel leaving a rut must have a physical consequence without jitter or exploding impulses. | Not run |
| Braking bumps | Axle compression/rebound oscillates independently. Repeated bumps can alter braking grip. No body teleport or automatic leveling occurs. | Not run |
| Whoops | Compare seated vs standing and forward/back rider position. Compression, rebound and preload visibly change pitch/ride outcome. No discontinuity at surface seams. | Not run |
| Small tabletop | At repeated approach speeds, takeoff matches slope/suspension motion. Air torque from rev/rear brake and rider articulation changes actual attitude. Controlled landings remain possible. | Not run |
| Large-jump lane | Record launch speed, takeoff pitch, flight time, airborne rates and impact. Verify ballistic flight; no landing snap/upright force. Increase size only after the easy jump passes. | Not run |
| Whip/scrub | Input before takeoff and bounded rider/steering movement produces actual yaw/roll. Holding an articulated posture cannot supply unlimited air torque. | Not run |
| Poor landings | Deliberately land nose-heavy, sideways and excessively rolled. Normal impact, slip/angle and collision produce believable failures, followed by detached rider and manual recovery. | Not run |
| Wheelie/loop-out | Throttle/load transfer can unload front contact. Rear brake can bring it down physically. Test the known near-vertical ray-support cutoff explicitly (about 78.5° on a flat rear axis). Qualify or improve contact geometry before accepting loop-outs; never add a pitch cap/upright force. | Not run; known contact limitation |
| High-side | Induce rear slip, then regrip. Any launch/roll must come from changed tire force; the crash label must not be an injected kick. | Not run |
| Setup effects | One setting at a time: spring/preload changes sag; compression changes impact stroke; rebound changes packing/bounce. Compare repeatable runs and record values. Tune only stationary in lab. | Not run |
| Crash/recovery | Crash invalidates current lap, keeps completed session records, detaches rider, and does not freeze the bike. R is rejected for the 2.5 s cooldown. | Not run |
| PC/controller | Full axes work independently. Chat, menu, focus loss and dismount clear controls. Controller trigger inputs remain progressive and right-stick body controls do not move camera. | Not run |
| Networking/performance | Two clients: ownership, stale/duplicate/invalid input, collision behavior and per-rider timing. Measure server physics cost and lost substep budget at 60/30 fps and representative latency. | Not run |
| Regression course | Switch Config.Mode to Racing in a separate Studio test and run the preserved course; lab tuning must reject and all factory bikes must share calibration. | Not run |

## Iterate instead of hiding defects

Investigate the first broken prerequisite: units, static load, ray contacts, tire force direction, brake direction, inertial reactions, then steering and rider motion. Save traces and exact setup before adjusting values. A stable one-dimensional test does not rule out a 3D contact or networking defect. Never add an upright constraint, landing alignment, speed target or a forced high-side animation to conceal the failure.

After each fix, rerun the affected station and the automated regressions. Phase 1 remains open until all required handling stations have convincing recorded passes. Production animation, meshes and sounds have their own asset acceptance.
