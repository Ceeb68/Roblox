# Dirtline MX standalone prototype

A Windows motocross prototype built with Godot 4.6.3 and Jolt Physics. All dynamics use metres, kilograms, seconds and 9.81 m/s² gravity. Nothing under `standalone/` depends on Roblox.

Version 0.6 targets responsive, planted riding with approximately 75% simulation and 25% forgiveness. That is a handling philosophy, not a numerical blend. The five-body motorcycle, independent tires, manual drivetrain and suspension remain physical; explicitly bounded gameplay assistance makes balance and airborne correction more accessible. This is original code and fictional engineering calibration, with no proprietary MX Bikes/MX Simulator code or assets.

## Ride and configure controls

The bike starts in neutral with clutch pulled and feet planted. Select first with **E**, build revs with **W**, and meter clutch release with **B**. Feet lift automatically during a deliberate launch and riding. **V** pulls the lever; **Shift** pulls it quickly. Keyboard V/B preserve the lever position when released. If you stall, pull the clutch and press **T**.

| Action | Keyboard | Xbox-style controller |
| --- | --- | --- |
| Progressive throttle | W | RT |
| Front / rear brake | Space / S | LT / RB |
| Clutch | V pull, B release, Shift quick pull | LB pull, progressive release |
| Shift down / up | Q / E | D-pad down / up |
| Bike lean; direct bars in manual mode | A / D | Left stick X |
| Rider upper-body lean | Z / X | D-pad left / right |
| Rider forward / back; air pitch | I / K | Right stick Y |
| Rider side; air yaw | J / L | Right stick X |
| Standing / seated | C | A |
| Scrub while leaning on a rising face | Hold F | Hold X |
| Recover / starter | R / T | Y / left stick click |
| Help / suspension setup | H / U | Right stick click / HUD setup button |
| Pause | Escape | Start |
| Chase / helmet camera | M | B / Circle |

Open **Escape / Start → Settings + controller binds → Controller bindings** to remap buttons and directional half axes, adjust deadzones/inversion, replace conflicts or restore defaults. Selected-device routing prevents another controller from driving the bike. Preferences persist locally; disconnect/focus/menu transitions release controls. The chase camera excludes the rider and bike from its obstruction ray. Right mouse orbits the chase camera; the riding sticks do not.

Keep **Lean control · virtual rider** selected for the default handling. The primary stick requests combined bike/rider bank; rider counterbalance remains independent. **Direct handlebar control · manual** applies direct bar effort and bypasses virtual-rider game assistance. An older saved manual preference is preserved, so select Virtual rider explicitly when comparing builds.

Feet plant at grounded stops and can dab during a loaded walking-speed loss of balance. The preferred standing posture resumes when support feet lift. Inside-leg cornering is visual and does not add an extra ground-support collider. Recovery remounts bike and rider after one unpaused second; **R / mapped recover** acts immediately. It restores all five bodies, neutral, clutch pulled, seated posture and planted feet near safe ground. Held inputs stay blocked until released/recentered. Recovery cancels the current local lap.

## What changed underneath the handling

The most serious traction defect was a contact-phase mismatch: the native engine's completed-step pressure patch was combined with the next wheel pose. At riding speed that created a false trailing lever and phantom lateral tread motion when wheel spin was evaluated. The adapter now transports the pressure patch by the measured hub translation before using it consistently for tread velocity, effective radius and applied force/torque. A pressure patch is not a rotating rubber point, so it is not spun around the axle. Missing/reset history invalidates the phase correction. This removes the artificial slip source instead of disguising it with more friction.

The earlier shared tire calibration also needed excessive small-slip displacement to establish a line. Front and rear now have their own lateral/longitudinal stiffness and relaxation distances. Increasing small-slip stiffness changes how quickly a tire develops force; it does not increase the unchanged surface-friction peak. Drive and braking share a progressive traction ellipse with lateral force, so ordinary corners stay planted while hard exits can spin the rear. Surface, normal load, camber and the two axle states remain independent.

Ground steering uses the existing finite fork/frame actuator. Deliberate bank changes use a bounded roll-rate task rather than relying solely on a heavily damped angle spring. Actual rider COM determines counterbalance; speed, available grip and wheel support determine feasible lean and steering. Neutral line following has separate, calmer response. The bars still countersteer to initiate lean and steer into the corner; neither the chassis transform nor travel direction is assigned. A separately bounded low-speed balance torque is the explicit walking-speed gameplay allowance, and requires actual loaded support.

The previous airborne rider/bar reactions were too weak and coupled to provide useful independent roll/yaw control. `air_control.gd` now requests pitch, roll and yaw **rates** using the measured five-body inertia. It preserves native wheel spin, gyroscopic reactions, rider counter-motion and drivetrain pitch reactions. The added external gameplay torque has separate axis, total-torque and power limits, smooth activation, speed-dependent authority, neutral rotational damping and stronger deliberate counter-input. This is assistance, not a claim that a free rider can create external angular momentum. It never chooses a world-up attitude, takeoff heading or landing orientation, and never applies a flight-direction force. Strength zero and direct mode disable it.

A whip combines actual roll and yaw from steering/body inputs; reversing those inputs unwinds the native bodies. A scrub combines real bike lean with the held scrub input on a positively loaded ascending face. The virtual rider looks ahead at actual terrain geometry for the crest, then physically crouches while the suspension absorbs extension through passive damping. This keeps absorption active near takeoff instead of crouching so early that the body rebounds before the lip. It uses the observed face/crest and travel speed, not hardcoded jump coordinates. The compressed takeoff posture carries into flight without adding downward airborne force. During absorption the existing paired rider support blends toward 0.6 of critical damping, calculated from actual vertical stiffness and frame/rider reduced mass. This controls torso recoil while allowing a quick downward absorption stroke. The maximum crouch target is 0.28 m, with a 0.24s terrain lookahead and passive rebound scale 3.5; observed takeoff movement is smaller than the full target. The matched whole-assembly COM tests distinguish trajectory change from merely lowering the rider mesh.

Suspension now separates low/high shaft-speed hydraulic response and progressive bottoming damping. Analytical damper impulses use the actual axial effective mass, avoiding the energy injection possible when an explicit high damping force reverses a light axle within one step. Slow weight-transfer control, spring/preload, rebound and elastic bottom stops stay independent. These are effective wheel rates: the rear is a slider approximation, not a modeled production linkage.

Landing regains tire force through actual native load and tread relaxation. The finite handlebar catch still uses positive front support. A separate explicit landing aid lasts at most 1.25s after a genuine flight and loaded return, with a 100 N·m combined torque cap. It damps excess roll rate relative to the player's requested lean rate and catches terrain-relative pitch beyond an 8° deadband; full manual pitch endpoints bypass the pitch catch. It supplies no yaw correction, unsupported torque, extra friction or normal force. Global and landing strengths scale the budget. This is declared gameplay assistance through torque, not an assigned pose. The same suspension/rider/drivetrain remain active throughout.

Rider presentation now has interruptible continuous filters for posture, physical support and cornering legs. Leg selection follows actual bank, speed, supported riding and seating. A reversal blends from the current leg positions rather than restarting an animation. Arm/leg inverse kinematics keep hands at real fork grips and boots at peg or leg-out targets. The torso/helmet follow the independent massive rider. One pose solver owns each limb, avoiding competing animations.

## Physics architecture

| File | Responsibility |
| --- | --- |
| `config/bike_250f.json` | SI calibration and independently named handling/assistance settings |
| `physics/drivetrain.gd` | Crank inertia, torque curve, clutch impulses, gears, losses, brakes, engine braking, stall/starter |
| `physics/tire.gd` | Separate axle brush states, load sensitivity, relaxation, camber, drive/brake/lateral ellipse |
| `physics/suspension.gd` | Spring/preload, passive hydraulic impulse, high-speed slopes, rubber and hydraulic bottoming |
| `physics/handling_setup.gd` | Validated parked tuning fields, independent limits and local persistence |
| `physics/lean_control.gd` | Bounded grounded lean-rate task for the existing steering bearing |
| `physics/air_control.gd` | Explicit bounded, speed-dependent pitch/roll/yaw rate assistance and pose handoff |
| `physics/scrub_control.gd` | Loaded ascending-face scrub task and physical crouch/absorption envelope |
| `physics/gyroscope.gd` | Native-principal-inertia Euler integration and wheel precession |
| `scripts/wheel_body.gd` | Rounded native tire collision, surface/contact geometry and inferred normal load |
| `scripts/bike_controller.gd` | Five native bodies/joints, force pairing, integration, rider muscles and crash observation |
| `scripts/rider_visual.gd`, `bike_visual.gd` | Original rider/bike geometry, continuous pose/leg blending and anchored limb solving |
| `scripts/rider_input.gd`, `controller_bindings.gd` | Keyboard/selected-controller input, automatic feet, saved rebinding and held-input protection |
| `scripts/track_builder.gd`, `game.gd` | Native course geometry, cameras, menus, telemetry, setup and ordered local laps |

The motorcycle has a 94 kg chassis, 2 kg fork, 5.5/7.5 kg wheels and 78 kg physical rider: 109 kg bike plus rider. Mass and frame/rider inertias were not reduced to imitate responsiveness. Suspension, tire, drivetrain and rider forces have a single application path. Terrain and tire collision materials have zero native friction, so custom tangential traction is applied once; native contacts still supply normal support and collisions.

Godot/Jolt contact impulses are estimates, not final joint-coupled impulses. The adapter normally infers wheel support from completed momentum along the free suspension axis after subtracting recorded gravity/spring/tangential forces. Mechanical stops, missing history and singular geometry use a collision-estimate fallback. It never adds another normal force. Nonparallel manifolds, finite-step guide motion and limited engine contact information remain approximations.

The runtime requests 240 physics steps/s, permits wheel speeds up to the raised 250 rad/s native limit, and caps the small prototype's worker pool at two threads. This is a workload target, not deterministic networking or an overload guarantee. Multiplayer synchronization is not implemented; the shipped build has local session laps only.

## Tune simulation versus forgiveness

Park upright, then open **Escape / Start → Handling setup** to adjust independent front/rear grip, traction, steering/lean, low-speed/landing assistance, air rates/damping, whip response/recovery, scrub strength and rider transitions. **Apply and ride** validates and saves the setup locally; **Restore tested defaults** loads the shipped values into the menu for you to apply. **U** retains the separate spring/compression/rebound/preload suspension setup.

The complete engineering source calibration is `config/bike_250f.json`; editing JSON does not require rewriting physics scripts. `physics/handling_setup.gd` defines supported parked-menu ranges and atomic validation. Saved handling in `user://handling.cfg` overlays only supported fields; malformed/unknown settings cannot partially change the bike.

| Behavior | Settings | Meaning |
| --- | --- | --- |
| Front / rear planted response | `Tire.Front`, `Tire.Rear`: `LateralStiffness`, `LongitudinalStiffness`, both `*RelaxationLength` | Small-slip force slope and distance to develop/recover strain; not peak friction |
| Separate grip limits | Per-axle `GripScale`, `AccelerationGrip`, `BrakingGrip`, `LateralGrip`; `Surfaces.*.Grip` | Load-scaled surface peak and independent ellipse axes |
| Steering / bank response | `VirtualRider.SteeringSensitivity`, `LeanRate`, `LeanRecoveryRate`, `LeanAcceleration`, `LeanRateResponse` | Intent, rad/s response and bounded roll acceleration through the bars |
| Low-speed balance | `Assistance.Strength`, `LowSpeedStrength`, `LowSpeedMaxTorque`, `LowSpeedBalanceStiffness`, `LowSpeedBalanceDamping` | Global assistance scales ground, air and landing helpers; LowSpeedStrength isolates loaded walking-speed help |
| Suspension | `Suspension.Front/Rear`: `SpringRate`, `Compression`, `Rebound`, `HighSpeedCompression`, `HighSpeedRebound`, `*KneeSpeed`, `BottomOutCompression`, `BottomOutTravel`, `Preload` | Effective N/m, N·s/m, m/s and metres; the hydraulic cone occupies the last 0.075 m; independent wheel setup |
| Air pitch / roll / yaw | `AirControl.PitchRate`, `RollRate`, `YawRate`, `RateResponse` | Commanded rad/s and approach time; real inertia determines effort |
| Air rotational damping | `AirControl.NeutralDampingTime`, axis `Max*Torque`, `MaxTotalTorque`, `MaxPower`, `MaxDissipationPower` | Time and explicit torque/power budget, not a velocity clamp |
| Whip throw / counter | `AirControl.WhipResponse`, `WhipRecovery` | Roll/yaw command rates and deliberate opposite-input recovery |
| Air assistance amount | `AirControl.Strength` | Scale the bounded external task; zero keeps native rider/gyro/drivetrain reactions |
| Scrub | `ScrubControl.MaxCrouch`, `MaxReboundScale`, `MinFace`, `FullFace`, `CrestLookaheadTime`, `LegDampingRatio` | Metres, passive absorption scale, face angles in radians, geometric lead time in seconds and damping ratio against the actual reduced mass |
| Landing help | `Assistance.LandingStrength`, `LandingTime`, `LandingMaxTorque`; `VirtualRider.MaxLandingCatchTorque`, `LandingCatchTime` | Scale the loaded pitch/roll torque window and finite steering catch |
| Rider blending | `RiderAnimation.TransitionTime`, `CornerTransitionTime`, `SupportTransitionTime`, `Strength` | Seconds and visual leg-out amount; does not change grip or forces |

For more simulation, try gameplay and air assistance strengths around 0.65, keeping grip calibration unchanged initially; zero disables each extra task. For slightly more forgiveness than the default, try neutral rotational decay 0.40s instead of 0.55s and whip counter-input 1.25 instead of 1.15. These are suggested experiments, not separately certified presets. Increasing grip everywhere changes the traction limit and is not a substitute for better steering. Change one system at a time and rerun its native tests plus the full lap. The intended default assistance strength is not a literal 25% physics calculation.

## Circuit, validation and builds

The 872.5 m circuit has 14 ordered gates, a 40 m flat launch, braking bumps, whoops, berms/ruts and 1.3/3.2/4.5 m tabletops. The extended jump road is 15 m wide with graded shoulders and a 42 m big-table landing. A separate 100 m practice straight, 2.6 m jump lane and grip pads remain. First establish clutch/turn/brake control on flat ground, then approach the large jumps straight.

Read [native handling validation](VALIDATION.md) for actual A–M coverage and known failures/limits, and [research notes](MX_BIKES_RESEARCH.md) for the distinction between published dynamics and our design choices. Automated riding proves particular trajectories, not human feel. Windows execution and real Xbox-controller playtesting require a Windows PC. [Engine assessment](ENGINE_ASSESSMENT.md) records the earlier actual Jolt/Godot Physics comparison; no complete Unity/Unreal port was tested.

```bash
cd /workspace/Roblox
bash standalone/tools/setup.sh
bash standalone/tools/check.sh
bash standalone/tools/package_windows.sh
```

Open `project.godot` in Godot 4.6.3 for development. `setup.sh` verifies pinned official editor/template SHA-256 hashes. `godot.sh` supplies writable XDG runtime directories; override `DIRTLINE_TOOLS_DIR`, `DIRTLINE_RUNTIME_DIR` or `DIRTLINE_GODOT` when needed. No network service is needed to play.

The check script imports the project, runs mathematical and actual native scenarios, and starts the main scene. It fails on engine errors even if the process returns zero. Packaging reruns checks, exports the Windows executable/project pack, byte-verifies the shipped files, adds the player guide and licenses, and records ZIP SHA-256. Development tests/tooling are excluded from the pack. The unsigned Windows executable must stay beside `DirtlineMX.pck`.

Remaining model limits include rigid cylindrical tires, static undeformable soil, an approximate rear slider/linkage and rigid rider torso with compliant muscles. Tire/engine/suspension coefficients are fictional. Coupled gyro/joint integration has measurable finite-step angular-momentum error even when explicit game assistance is off. Production meshes/audio, calibrated hardware feel, career/AI/garage features and online racing remain future work. The physics are not declared complete merely because automated checks pass.
