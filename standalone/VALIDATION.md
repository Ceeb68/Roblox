# Validation and handling acceptance

The cloud machine can execute the actual Linux Godot/Jolt engine and render the native game window with software OpenGL. It cannot execute a Windows desktop or evaluate riding feel as a human rider. Keep those outcomes separate.

## Version 0.4 camera, handling and larger jumps

The chase-camera collision query now tests the world collision layer and excludes
all five native bike bodies, including the physical rider and fork. Previously,
moving the rider into that ray could retract the camera from about 4.7 m to
0.16 m even with the chassis stationary. Xbox stick input does not change the
camera orbit; terrain occlusion and deliberate mouse orbit still work.
The 93 input/camera checks also exercise selected-controller routing, remapping,
visible physical hip twist, anatomical limb lengths and fixed grip targets.
These tests do not use a physical Xbox controller.

Releasing a turn now lets measured banking and yaw settle before the virtual
rider captures the new travel line. It no longer immediately tries to undo the
last turn. After sustained unsupported flight, stale ground steering history
clears; first loaded touchdown captures the actual travel line once, then
gradually resumes heading feedback. Positive but light front-wheel load retains
finite handlebar authority. All these corrections act through bounded, paired
steering torque; tire friction and combined-force limits are unchanged. There
are still five independent native bodies, compliant rider support and separate
front/rear suspension. There is no frame pose lock or airborne landing alignment.

Unsupported body-side input now requests relative hip twist through finite
paired torso torque. The visible rider follows actual physical yaw rather than
displaying the command before the body moves. Opposite inputs can bring a whip
back; neutral input does not automatically align the bike with the landing.
The 203-check rideability suite includes twelve analog turn/release/reversal
cases at 4, 8 and 12 m/s and five unsupported whip cases. Turn response was
0.254–1.325 s; unwanted opposite bank after release stayed around 2.3° or less
in those cases. Combined airborne inputs produced about 6.5° bank and 4.8° yaw,
with counterinput ending near ±1.7° bank. These are finite test scenarios, not
universal handling guarantees. Existing 42 playability and 194 stability guards
retain their limits. The 67 recovery checks additionally require all new twist,
turn-capture and landing-reference state to clear on remount.

The course is now 872.5 m with fourteen ordered gates, original proving stations
and new 3.2 m and 4.5 m tabletops. Their road is 15 m wide with 2 m graded
shoulders on each side. The larger jump has a 42 m landing and 30 m flat runoff:
the earlier shorter curve demanded downward acceleration greater than gravity
at the test speed, unloading the wheels again after touchdown.
The 178-check track suite includes 4,584 native collision rays and eighteen
powered rides: both new jumps, 20/21/22 m/s rolling approaches and neutral or
±0.15 fore/aft body input. Initial body velocities are seeded once; timed manual
third-gear/clutch inputs, native suspension and contact govern the actual ride.
All eighteen runs landed and reached the runoff without crashes; full flight
lasted 0.933–1.125 s and maximum bank was 26.99°. Some rides used a shoulder;
minimum outer prepared-edge clearance was 1.492 m. Overspeed and aggressive
inputs can still crash. Human obstacle acceptance remains required.

The current coupled-rider diagnostic measures peak angular-momentum drift of
about 1.88% at 240 Hz and 1.15% at 480 Hz, within the existing 2% engineering
bound. Its damping-work calculation now uses the actual separate pitch/yaw/roll
damping coefficients; kinetic-work residual remains below the existing 1% limit.
No earlier conservation thresholds were weakened.

The complete workflow covers 2,895 checks: 1,635 SI math, 50 gyro, 40 rider
dynamics, 81 native mechanical, 262 contact/load, 178 track/jump, 20 handling,
30 sensor, 93 input/camera, 42 playability, 203 rideability, 194 stability and
67 recovery. [ENGINE_ASSESSMENT.md](ENGINE_ASSESSMENT.md) records 24 isolated
Jolt/Godot Physics observations. They do not establish that a backend switch
improves the complete motorcycle. Unity and Unreal were not tested. The older
release measurements below are historical baselines, not current-build results.

## Version 0.2 handling and player workflow

This section records the previous release baseline. Version 0.3 results and the
remaining rough-ground work are recorded below; the earlier measurements are
not measurements of the current build.

The default is now the user-selected virtual rider. Steering effort is physically bounded at 45 Nm and paired with the chassis; requested lean is capped by speed/geometry, surface grip and a 36° comfort limit. Neutral chosen-line corrections also act through those handlebars. Direct mode bypasses rider steering feedback. There are no chassis pose/position constraints or airborne landing corrections. The tire crown uses continuous native rounded-cylinder support, and tire slip includes non-spin patch transport. Brief sliding is recoverable; a washout requires actual departing lean rather than a single slip spike.

New handling checks pass 18 assertions for bounded steering, unsupported stationary fall, actual rider movement, airborne gravity/attitude and camera anchoring. The independent playability suite passes 42 assertions: a 14-second keyboard/manual-shift run covers 256 m without crashing; maximum lateral drift over the first 100 m is 0.95 m with 0.28° heading change. Full steering in either direction holds about 25° bank for ten seconds at roughly 10.5 m/s, turning over 200° without wrong-side banking or falling. Separate moderate rider lean causes measurable banking in both directions, but some oscillation/asymmetry remains and needs rider feedback.

The real main-scene welcome button and E/W/B/F/Shift/E events support a five-second, 19.7 m launch. The input/camera suite passes 44 assertions for remapped commands, axis edges/inversion, persistence, selected-device isolation, mode/camera transforms and recovery. R explicitly remounts seated with feet down, clutch pulled and neutral; native physics confirms it remains upright and stationary. Menu/focus changes preserve feet and posture. Helmet and chase views, visible bars/gloves, detailed gear, and scrollable rebinding/settings menus were rendered and inspected at 1280×720.

Controller analog polling was tested through binding/routing mathematics; actual joystick hardware is unavailable. Synthetic button/axis commands exercise the game dispatcher, but do not establish controller hardware behavior. Windows execution also remains untested on Windows.

## Version 0.3 stability and riding posture

The virtual rider now filters requested bank without filtering the motorcycle's
actual pose. Bank and heading rates are derivatives of their measured world
angles, including pitched and yawed attitudes; a 30-check independent
finite-difference suite guards against feeding pitch/yaw motion into roll damping.
Finite steering torque remains paired between fork and chassis. Direct mode
continues to bypass virtual-rider balance control.

The softer fictional effective wheel rates are 9,000/9,500 N/m, with separately
specified progressive rubber bump stops. Settled native sag is approximately
68/87 mm. The force guard now includes the bump-stop rate, so reducing main
spring stiffness does not silently clip landing support. The existing
one-dimensional 12 m/s landing and convergence checks retain their limits.

The contact adapter no longer sums repeated coplanar triangle responses as
independent tire support. It keeps distinct normals/moving supports separate and
reduces repeated geometric contact points without impulse-biased patch locations.
The 262-check contact suite retains all 188 manifold/fallback checks and includes triangle/box comparisons, surface seams,
banked support and 48 edge/contact ordering permutations. Reported Jolt impulses
remain estimates rather than final coupled solver forces; this adapter does not
change native collision support or add normal forces. The normal brush load now
normally comes from completed wheel momentum along the free suspension axis,
after subtracting gravity and recorded spring/tangent forces. Mechanical stops,
near-axis singularities and missing samples use the explicit manifold fallback.
This remains an inference in a finite-step constrained engine, not access to
Jolt's final impulses.

The procedural rider uses a forward hip hinge, raised elbows, bent knees, boot
soles aligned to the pegs, and physical suspension/acceleration bracing. Hands and
boots retain support targets through two-bone limb solving. An ignored geometry
probe checked 108 combined input poses for limb reach. This improves the original
procedural rider; it is not a scanned rider or a production animation library.
The rider now has an independent 78 kg native body with compliant leg support,
finite reach stops and paired common-point forces/torso torque. The 94 kg frame's
COM and inertia stay fixed. The visible hip/torso/helmet follow the real body's
motion; arms and legs re-solve to real grips/pegs within anatomical reach.
Recovery compares the reset visual pose with a
fresh neutral pose rather than a coordinate from the previous rider mesh.

Standing coasting through the shipped whoops, seated/standing braking bumps,
brief lean corrections, clutch recovery at low speed, separate mild braking,
hardpack-to-mud transitions, an actual rut and a banked drop are exercised by the
new native stability suite. Independent frozen production runs passed the
original 68 checks and all 270 guards across 30 powered second-gear rides, with
five rider positions (neutral and ±0.15/±0.25 fore/aft input), three nearby lines
and two repeats. Gear two is selected through timed real shifting and verified;
neither engine nor wheel speed is replaced during the ride. All 30 survived;
maximum bank was about 10° and maximum final bank 7°. Standing coasting through the
same shipped whoops covered 19.1 m in five seconds, with 13.1° maximum/final bank.
The tracked suite retains every original guard and adds 14 representative powered
repeats, for 194 checks over 26 rides. Full human obstacle acceptance remains open.

The actual keyboard/manual-shift regression additionally verifies a fourteen-second
full-throttle launch through fifth gear. Acceleration-driven front unloading asks
the virtual rider to brace forward through the same finite native body support;
manual endpoints retain priority. Seated and standing roll response use different
gains because their compliant support differs. The target line, bank and crash
limits in the existing playability suite remain unchanged. The final release run
covered 256.4 m, reached 32.9 m/s and fifth gear, and stayed within 1.81 m of its
chosen line over the first 100 m with 0.24° heading error.

A new 40-check native rider-dynamics suite verifies actual per-body impulses and
common-point torque pairing in three rotated configurations, fixed frame COM and
inertia, real torso movement, total COM transport and bounded muscle forces. In
its isolated coupled-system bench, peak world angular momentum drift is about
1.71% at 240 Hz and 1.03% at 480 Hz. The new engineering bound is 2%; the earlier
ignored 1% experiment remains a failed diagnostic, and the existing free-rotor
bounds are unchanged. Trapezoidal internal force/torque work accounts for kinetic
energy to within 1% in this bench. Its residual is not monotonically convergent;
native joint dissipation remains an approximation. These bounds are specific
bench results, not a claim of exact conservation in arbitrary riding.

Accessible research and the blocked official MX Bikes sources are documented in
[MX_BIKES_RESEARCH.md](MX_BIKES_RESEARCH.md). Our control gains, suspension rates,
tire model and rider motion are independently developed.

## Automated workflow

Version 0.2.1 adds 67 actual native recovery checks: genuine crash detection, one-second auto remount (paused menus freeze the timer), immediate R and mapped controller recovery, physical/visible rider pose, all body velocities, held-control protection, nearby ground/fallback, repeated crashes and reset-failure propagation. Invalid nonfinite poses are rejected without partial state changes. Chassis-only contact can record a fall even when both wheels are clear. Physics bodies apply remount poses inside their next native integration callback, and presentation/COM/inertia/collision reset immediately.

The final version 0.3 release passed all 2,465 checks: 1,635 SI math, 50 gyro,
40 rider dynamics, 81 native mechanical, 262 contact/load, 20 handling, 30 sensor,
44 input/camera, 42 playability, 194 stability and 67 five-body recovery checks.
The Windows ZIP passed integrity and current-export byte comparisons. Its exact
project pack also loaded in a Linux release template, both headless and under
software OpenGL; the native packaged Exit button shut it down cleanly. Windows
desktop execution and real controller hardware remain untested here.

Run `bash standalone/tools/check.sh`. Preserve command failures and engine error output. Export and package only the current passing revision with `bash standalone/tools/package_windows.sh`. The package verifies every shipped file against the current export and records its SHA-256 in `downloads/SHA256SUMS`.

The SI math suite contains 45 regression cases and 1,635 checks for drivetrain momentum/energy, clutch/manual gears, losses, brakes, surface grip, the shared traction budget, camber/contact transport, tire relaxation, suspension damping, independent bump-stop support and a one-dimensional hard-landing convergence scenario. These run the mathematical modules rather than a mock engine.

The native scenario suite passes 81 checks using real rigid bodies, cylinder tires, joints and floor/ramp/track colliders. It tests mass, normal loads, static sag and tuning, neutral/clutch isolation, actual chassis acceleration, independent brakes, stall/restart, actual wheelspin, high-speed rotor limits, unassisted loss of balance, manual recovery, near-vertical wheel contact, ballistic flight, rider reactions, ramp takeoff and landing, and material tags on the shipped track. Moving-bearing brake benches require correct relative-spin reduction and declining native mechanical energy. A spinning front wheel must produce real steering/roll coupling in the assembled bike.

The gyroscope suite passes 10 cases and 50 checks. It measures actual Jolt rigid bodies with explicit inertia. The uncorrected native baseline exhibits about 15.4% peak world-angular-momentum drift over 0.5 seconds. Implicit midpoint Euler correction limits peak drift to about 0.98% at 240 Hz for 30 and 100 rad/s rotors, falling to about 0.49% at 480 Hz. Maximum relative energy error stays below 0.001%. These are bounded test scenarios, not universal error guarantees. Constraint/contact integration and finite-step coupling still introduce additional approximation.

The earlier course was checked with 1,070 profile/continuity rays and eight cylinder drops. Version 0.2 expands the course to a roughly 80 × 158 m loop, 10 m road, 30 m corners, a 40 m flat start, a separate 100 m practice straight and longer jump approaches/landings. Its fresh native geometry probes pass at the spawn, flat launch, obstacles, practice surfaces and retained grip pads. It has 14 static surface bodies and about 95,640 triangles. Exact triangle-edge rays can miss because of floating-point rounding; riding uses native wheel volume contact.

Reported Jolt contact impulses are estimated collision responses rather than final joint-coupled solver impulses. The free-slider momentum observation and explicit collision fallback are approximations; real native wheel geometry/contact supports the bike. See the [Godot 4.6.3 contact adapter](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/jolt_physics/spaces/jolt_contact_listener_3d.cpp#L209).

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
