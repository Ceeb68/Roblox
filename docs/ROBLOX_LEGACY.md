# Dirtline MX — 250F simulation prototype

> Archived Roblox version. The current standalone Windows game is documented in the [repository README](../README.md).

Phase 1 of a realistic Roblox motocross project: one fictional 250cc four-stroke and a dedicated handling laboratory. Physics quality comes before the motorcycle collection, career, shops, or additional production tracks.

The former arcade controller has been replaced with separate wheel-contact forces, suspension, manual drivetrain, rider mass movement and unrestricted body rotation. **This is a prototype awaiting Roblox Studio handling acceptance**, not a claim of MX Bikes-equivalent physics or a qualified competitive release.

## Download and test

1. On [Ceeb68/Roblox](https://github.com/Ceeb68/Roblox), choose **Code → Download ZIP** and extract it on a Windows PC or Mac.
2. Install [Roblox Studio](https://create.roblox.com/) if needed.
3. Choose **File → Open from File**, select the root **DirtlineMX.rbxlx**, and press **Play**.
4. Start in neutral with feet down. Press **E** to select first while clutch is pulled, hold **W** to add throttle, and hold **B** to release the clutch progressively. **V** pulls the lever back; **Shift** is a quick pull override. Raise feet with **F** when moving. Use **H** for help.
5. Work through the flat pad, braking bumps, ruts, berms, whoops, easy tabletop, grip patches, then the separate large-jump lane. These stations need recorded Studio passes before Phase 1 is complete.

Source edits build into `build/DirtlineMX.rbxlx`; the root file is the downloadable prototype snapshot. The original arcade build remains in Git commit `5fcc106`, and its circuit is preserved as `src/server/Track.luau`.

## Manual controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Progressive throttle | W | Right trigger |
| Front brake | Space | Left trigger |
| Rear brake | S | Right bumper |
| Meter clutch in / out | V / B; Shift quick pull | Left bumper pull; release over 0.6 s, re-pull/tap to meter |
| Shift down / up | Q / E | D-pad down / up |
| Handlebar steering | A / D | Left stick X |
| Bike lean articulation | Z / X | D-pad left / right |
| Rider forward / back | I / K | Right stick Y |
| Rider side movement | J / L | Right stick X |
| Standing / seated | C | A |
| Feet down / up | F | X |
| Engine starter | T | Left stick click |
| Manual recovery | R, after crash cooldown | Y |
| Help / suspension lab | H / U | Right stick click; setup via HUD |

There is no reverse gear, automatic shift, upright/landing constraint, or traction control. Manual feet are physical supports, so leaving them down causes contact and drag. Lean, steering and rider body inputs are separate. Touch simulation controls are deferred; use PC or a controller.

## Current capabilities and limitations

- Independent front/rear grip and slip, combined cornering/braking limits, camber thrust and dirt/sand/mud/hardpack coefficients.
- Front/rear spring, compression and rebound damping, preload and progressive bump stops; **U** opens independent setup edits while parked in the lab.
- Manual neutral + five gears, clutch slip, engine braking, limiter, stall and explicit restart. Throttle/rear-brake rotor reactions contribute to airborne pitch.
- Physical chassis rotation, finite rider articulation and standing/seated mass movement. No scripted whip or landing pose drives bike physics.
- Crash observation, rider ejection and 2.5-second manual recovery. Development-lab laps use preserved authoritative gate/lap rules; setup edits, crashes and timing overruns invalidate unfinished runs.
- Server-owned prototype simulation, sequence/range validated controls, live telemetry, and procedural motorcycle/rider visuals.

The tire contacts are ray-based approximations, the rider is an articulated-mass approximation, and calibration is fictional starting data. Native Roblox suspension/body stability, cornering, jumps, crash behavior, rider poses, networking latency and multiplayer performance **remain unverified until Studio playtesting**. Production meshes, rider IK, licensed sounds, mobile riding, persistence, career, AI, garage and purchases are not implemented.

## Development and verification

```bash
cd /workspace/Roblox
bash scripts/setup-tools.sh
bash scripts/check.sh
```

The setup pins verified official Rojo 7.7.1 and Luau 0.742 archives. The check runs all pure physics/race regressions, analyzes engine-independent modules/tests, compiles every Luau source, builds a place, and compares every embedded game script against the current source. The Linux cloud environment cannot run Roblox Studio or its physics engine.

For source synchronization use `bash scripts/dev.sh` and a supported Studio connection to the machine on port 34872. Opening the downloaded place does not require the Rojo plugin.

## Project documents

- [Assessment, architecture, roadmap and open work](DEVELOPMENT.md)
- [Physics equations, units, networking and limitations](PHYSICS.md)
- [Required Studio obstacle and handling acceptance](STUDIO_VALIDATION.md)
- [Production motorcycle, rider and audio asset pipeline](ASSETS.md)

Read these before expanding the collection. Record actual handling evidence and fix the first failed station; do not compensate with hidden stabilization. Best lap and lap count are server-session values only. Roblox game publication is a separate user action after playtesting.
