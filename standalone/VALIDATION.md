# Validation and handling acceptance

The cloud machine can execute the actual Linux Godot/Jolt engine and render the native game window with software OpenGL. It cannot execute a Windows desktop or evaluate riding feel as a human rider. Keep those outcomes separate.

## Version 0.2 handling and player workflow

The default is now the user-selected virtual rider. Steering effort is physically bounded at 45 Nm and paired with the chassis; requested lean is capped by speed/geometry, surface grip and a 36° comfort limit. Neutral chosen-line corrections also act through those handlebars. Direct mode bypasses rider steering feedback. There are no chassis pose/position constraints or airborne landing corrections. The tire crown uses continuous native rounded-cylinder support, and tire slip includes non-spin patch transport. Brief sliding is recoverable; a washout requires actual departing lean rather than a single slip spike.

New handling checks pass 18 assertions for bounded steering, unsupported stationary fall, actual rider movement, airborne gravity/attitude and camera anchoring. The independent playability suite passes 42 assertions: a 14-second keyboard/manual-shift run covers 256 m without crashing; maximum lateral drift over the first 100 m is 0.95 m with 0.28° heading change. Full steering in either direction holds about 25° bank for ten seconds at roughly 10.5 m/s, turning over 200° without wrong-side banking or falling. Separate moderate rider lean causes measurable banking in both directions, but some oscillation/asymmetry remains and needs rider feedback.

The real main-scene welcome button and E/W/B/F/Shift/E events support a five-second, 19.7 m launch. The input/camera suite passes 44 assertions for remapped commands, axis edges/inversion, persistence, selected-device isolation, mode/camera transforms and recovery. R explicitly remounts seated with feet down, clutch pulled and neutral; native physics confirms it remains upright and stationary. Menu/focus changes preserve feet and posture. Helmet and chase views, visible bars/gloves, detailed gear, and scrollable rebinding/settings menus were rendered and inspected at 1280×720.

Controller analog polling was tested through binding/routing mathematics; actual joystick hardware is unavailable. Synthetic button/axis commands exercise the game dispatcher, but do not establish controller hardware behavior. Windows execution also remains untested on Windows.

## Automated workflow

Version 0.2.1 adds 67 actual native recovery checks: genuine crash detection, one-second auto remount (paused menus freeze the timer), immediate R and mapped controller recovery, physical/visible rider pose, all body velocities, held-control protection, nearby ground/fallback, repeated crashes and reset-failure propagation. Invalid nonfinite poses are rejected without partial state changes. Chassis-only contact can record a fall even when both wheels are clear. Physics bodies apply remount poses inside their next native integration callback, and presentation/COM/inertia/collision reset immediately.

Run `bash standalone/tools/check.sh`. Preserve command failures and engine error output. Export and package only the current passing revision with `bash standalone/tools/package_windows.sh`. The package verifies every shipped file against the current export and records its SHA-256 in `downloads/SHA256SUMS`.

The SI math suite contains 43 regression cases and 1,610 checks for drivetrain momentum/energy, clutch/manual gears, losses, brakes, surface grip, the shared traction budget, tire relaxation, suspension damping and a one-dimensional hard-landing convergence scenario. These run the mathematical modules rather than a mock engine.

The native scenario suite passes 78 checks using real rigid bodies, cylinder tires, joints and floor/ramp/track colliders. It tests mass, normal loads, static sag and tuning, neutral/clutch isolation, actual chassis acceleration, independent brakes, stall/restart, actual wheelspin, high-speed rotor limits, unassisted loss of balance, manual recovery, near-vertical wheel contact, ballistic flight, rider reactions, ramp takeoff and landing, and material tags on the shipped track. Moving-bearing brake benches require correct relative-spin reduction and declining native mechanical energy. A spinning front wheel must produce real steering/roll coupling in the assembled bike.

The gyroscope suite passes 10 cases and 50 checks. It measures actual Jolt rigid bodies with explicit inertia. The uncorrected native baseline exhibits about 15.4% peak world-angular-momentum drift over 0.5 seconds. Implicit midpoint Euler correction limits peak drift to about 0.98% at 240 Hz for 30 and 100 rad/s rotors, falling to about 0.49% at 480 Hz. Maximum relative energy error stays below 0.001%. These are bounded test scenarios, not universal error guarantees. Constraint/contact integration and changing aggregate rider inertia still introduce additional approximation.

The earlier course was checked with 1,070 profile/continuity rays and eight cylinder drops. Version 0.2 expands the course to a roughly 80 × 158 m loop, 10 m road, 30 m corners, a 40 m flat start, a separate 100 m practice straight and longer jump approaches/landings. Its fresh native geometry probes pass at the spawn, flat launch, obstacles, practice surfaces and retained grip pads. It has 14 static surface bodies and about 95,640 triangles. Exact triangle-edge rays can miss because of floating-point rounding; riding uses native wheel volume contact.

Reported Jolt contact impulses are estimated collision responses rather than final joint-coupled solver impulses. Tire loads are therefore approximations; real native wheel geometry/contact supports the bike. See the [Godot 4.6.3 contact adapter](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/jolt_physics/spaces/jolt_contact_listener_3d.cpp#L209).

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
| Crash and recovery | Actual body motion causes the fall; one-second automatic remount; immediate manual remount; complete rider reset and held-input protection |
| Performance | Measure 240 Hz workload on representative Windows PCs; expose/record overload rather than silently changing competitive rules |

Phase 1 remains open until a rider can handle every required obstacle convincingly and the recorded failures are resolved. The current lab, procedural visuals and tests form a development baseline, not a production simulator qualification. No exact MX Bikes physics replication is claimed.
