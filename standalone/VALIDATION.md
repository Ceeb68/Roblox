# Validation and handling acceptance

The cloud machine can execute the actual Linux Godot/Jolt engine and render the native game window with software OpenGL. It cannot execute a Windows desktop or evaluate riding feel as a human rider. Keep those outcomes separate.

## Automated workflow

Run `bash standalone/tools/check.sh`. Preserve command failures and engine error output. Export and package only the current passing revision with `bash standalone/tools/package_windows.sh`. The package verifies every shipped file against the current export and records its SHA-256 in `downloads/SHA256SUMS`.

The SI math suite contains 43 regression cases and 1,610 checks for drivetrain momentum/energy, clutch/manual gears, losses, brakes, surface grip, the shared traction budget, tire relaxation, suspension damping and a one-dimensional hard-landing convergence scenario. These run the mathematical modules rather than a mock engine.

The native scenario suite passes 78 checks using real rigid bodies, cylinder tires, joints and floor/ramp/track colliders. It tests mass, normal loads, static sag and tuning, neutral/clutch isolation, actual chassis acceleration, independent brakes, stall/restart, actual wheelspin, high-speed rotor limits, unassisted loss of balance, manual recovery, near-vertical wheel contact, ballistic flight, rider reactions, ramp takeoff and landing, and material tags on the shipped track. Moving-bearing brake benches require correct relative-spin reduction and declining native mechanical energy. A spinning front wheel must produce real steering/roll coupling in the assembled bike.

The gyroscope suite passes 10 cases and 50 checks. It measures actual Jolt rigid bodies with explicit inertia. The uncorrected native baseline exhibits about 15.4% peak world-angular-momentum drift over 0.5 seconds. Implicit midpoint Euler correction limits peak drift to about 0.98% at 240 Hz for 30 and 100 rad/s rotors, falling to about 0.49% at 480 Hz. Maximum relative energy error stays below 0.001%. These are bounded test scenarios, not universal error guarantees. Constraint/contact integration and changing aggregate rider inertia still introduce additional approximation.

Track geometry was also checked with 1,070 native profile/continuity rays and eight wheel-sized cylinder drops at the spawn, whoop crest, tabletop, rut bottom, jump runoff and grip pads. The lab has 13 static surface bodies, eight ordered gates and seven stations. Exact triangle-edge ray queries can miss because of floating-point rounding; the riding model uses native wheel volume contact.

Native graphical checks exercise the main scene, welcome/help/setup screens and gameplay HUD at 1280×720. A parked U-input test changes front spring stiffness through the displayed SpinBox and verifies the bike receives the setup; an H-input test opens help. Audio synthesis is implemented, but the cloud machine has no physical sound output or controller hardware.

An actual keyboard-input launch through the main game's E/W/B/F bindings selects first, progressively opens throttle, releases the clutch and raises feet. The native bike reached about 3.4 m/s (12.2 km/h) with clutch engaged and no crash. This verifies the player launch instructions, not complete obstacle handling. A Jolt job-capacity warning seen with the default worker pool disappeared in the repeated gyro/native checks after capping the pool at two threads.

The Windows export is an x86_64 PE executable plus its project pack. A Linux release export is exercised separately to check packaged resources. A successful Windows export does not establish that the Windows executable was played or that driver/hardware behavior was verified.

## Required human riding acceptance

Record the build hash, PC/controller, setup, inputs, speed, suspension compression, axle loads/slip, angles, crash reason and repeatability for each station. Use recordings and telemetry to tune one failure at a time. Do not add automatic alignment or invisible support to conceal a failed station.

| Station | Required observation |
| --- | --- |
| Flat start and stop | Progressive clutch launches; stall/restart; separate brakes; feet raised; no hidden balance correction |
| Flat turns | Steering, speed, lean and rider positioning produce believable cornering; excessive lean/grip demand can wash out |
| Berms | Terrain banking and wheel forces support the bike; entry/exit responses are physically plausible |
| Ruts | Both wheels follow/escape the profile; contact and steering remain stable |
| Braking bumps | Front/rear compression and rebound respond independently under braking |
| Whoops | Setup and rider posture materially change motion; no tunneling or exploding constraints |
| Tabletop | Approach speed and suspension determine takeoff; throttle/brake/body reactions alter air motion; correct landing survives |
| Large jump | Repeatable flight, meaningful pitch/roll inputs, believable nose-heavy/sideways/over-rotated consequences |
| Grip pads | Wheelspin, slides, braking and washouts vary consistently on hardpack, sand, mud and loam |
| Wheelies and loop-outs | Rear wheel keeps real support at extreme pitch; balance and throttle determine outcome |
| Crash and recovery | Actual body motion causes the fall; no forced landing; 2.5-second delay and manual recovery |
| Performance | Measure 240 Hz workload on representative Windows PCs; expose/record overload rather than silently changing competitive rules |

Phase 1 remains open until a rider can handle every required obstacle convincingly and the recorded failures are resolved. The current lab, procedural visuals and tests form a development baseline, not a production simulator qualification. No exact MX Bikes physics replication is claimed.
