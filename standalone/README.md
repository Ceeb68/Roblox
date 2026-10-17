# Dirtline MX standalone prototype

A Windows motocross prototype built with Godot 4.6.3 and Jolt Physics. All dynamics use metres, kilograms, seconds and 9.81 m/s² gravity. Nothing under `standalone/` depends on Roblox.

Version 0.7.1 makes a focused correction after auditing the actual public build and input path: deferred foot activation now survives immediate input packets, and feasible bank vanishes with true speed during a stop. The existing F8 overlay identifies the loaded version and effective setup. [The follow-up diagnosis](HANDLING_DIAGNOSIS.md) records the controlled comparisons and remaining handling limits. Explicit, configurable low-speed/active-air/brief landing assistance provides accessibility. Centered air inputs preserve native rotation by default. This is original code and fictional engineering calibration; no proprietary MX Bikes/MX Simulator code or assets are used.

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
| Help / suspension setup | H / U | Right stick click / Start → Suspension setup |
| Pause | Escape | Start |
| Chase / helmet camera | M | B / Circle |

Open **Escape / Start → Settings + controller binds → Controller bindings** to remap buttons and directional half axes, adjust deadzones/inversion, replace conflicts or restore defaults. Selected-device routing prevents another controller from driving the bike. Preferences persist locally; disconnect/focus/menu transitions release controls. The chase camera excludes the rider and bike from its obstruction ray. Right mouse orbits the chase camera; the riding sticks do not.

Keep **Lean control · virtual rider** selected for the default handling. The primary stick requests combined bike/rider bank; rider counterbalance remains independent. **Direct handlebar control · manual** applies direct bar effort and bypasses virtual-rider game assistance. An older saved manual preference is preserved, so select Virtual rider explicitly when comparing builds.

Feet plant at grounded stops and can dab during a loaded walking-speed loss of balance. The preferred standing posture resumes when support feet lift. Inside-leg cornering is visual and does not add an extra ground-support collider. Recovery remounts bike and rider after one unpaused second; **R / mapped recover** acts immediately. It restores all five bodies, neutral, clutch pulled, seated posture and planted feet near safe ground. Held inputs stay blocked until released/recentered. Recovery cancels the current local lap.

## What changed underneath the handling

The [engineering report](PHYSICS_OVERHAUL.md) records the architecture, controlled comparisons and exact fixes. The important changes are:

- Visual soil boundaries previously split native collision bodies and caused false wheel impacts/support loss. One continuous main-road collider now resolves soil at the real contact point. Tire friction peaks and body masses remain unchanged.
- One bounded lean-rate task replaces the conflicting deliberate/neutral laws. Neutral senses travel course, removes historical position pursuit and stops feeding countersteering's initial chassis yaw back into a competing command. The finite fork/frame actuator and independent tire forces still produce every turn.
- Suspension damping now accounts for a positively supported wheel's constrained normal mobility, with unilateral release when rebound would unload it. Free-air strut forces remain an internal pair.
- Support boots deploy without penetration and keep real contact through rebound. Their intended guard friction is separate from the zero-friction native tire material. Visual legs follow the deployed support geometry through the existing continuous IK solver.
- Crash severity uses the support plane and its velocity. Vertical impact no longer becomes false sideways speed merely because the bike is banked; severe impacts, loop-outs and genuine falls still crash.
- Hip yaw now helps the requested bike yaw. Centered air axes apply zero external torque by default; active rate corrections remain bounded by real assembly inertia, torque and power. Zero assistance retains the same virtual-rider input mapping; Direct remains manual.
- Default landing assistance lasts 0.30s and damps rate, with zero pitch-return stiffness. A longer pitch-return spring is available only as an explicit tuning choice. The native suspension, tires and finite rider/bar reactions remain active throughout.
- Saved handling is configured before the physical bike is built. F8 displays actual physics observations and F9 records every native riding step to a local CSV.

Whips remain actual roll/yaw and rider/fork movement; counter-input recovers them. Scrubs remain a loaded-face physical rider/suspension absorption task with no airborne downward force. The existing manual engine, clutch, gears, brakes, wheel pitch reactions, recovery, cameras and controller bindings retain their single integrated paths.

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
| Optional neutral air damping | `AirControl.NeutralDampingStrength` (default 0), `NeutralDampingTime`, axis `Max*Torque`, `MaxTotalTorque`, `MaxPower`, `MaxDissipationPower` | Time and explicit torque/power budget, not a velocity clamp |
| Whip throw / counter | `AirControl.WhipResponse`, `WhipRecovery` | Roll/yaw command rates and deliberate opposite-input recovery |
| Air assistance amount | `AirControl.Strength` | Scale the bounded external task; zero keeps native rider/gyro/drivetrain reactions |
| Scrub | `ScrubControl.MaxCrouch`, `MaxReboundScale`, `MinFace`, `FullFace`, `CrestLookaheadTime`, `LegDampingRatio` | Metres, passive absorption scale, face angles in radians, geometric lead time in seconds and damping ratio against the actual reduced mass |
| Landing help | `Assistance.LandingStrength`, `LandingTime` (0.30s), `LandingPitchStiffness` (0), `LandingMaxTorque`; `VirtualRider.MaxLandingCatchTorque`, `LandingCatchTime` | Brief loaded rate damping and finite steering catch; nonzero pitch-return stiffness is optional assistance |
| Rider blending | `RiderAnimation.TransitionTime`, `CornerTransitionTime`, `SupportTransitionTime`, `Strength` | Seconds and visual leg-out amount; does not change grip or forces |

For more simulation, lower global/air/landing assistance while leaving tire calibration unchanged initially; keep neutral damping and landing pitch-return stiffness at zero. For more forgiveness, deliberately enable a small neutral damping strength or extend the landing damping window. Nonzero pitch-return stiffness adds an explicit attitude spring. These are tuning choices, not independently certified presets. Change one system at a time and compare F8 observations or F9 recordings before rerunning its native tests and a full lap.

F8 starts hidden. F9 starts/stops CSV capture under `user://telemetry/` and displays the saved path. Rows include simulation time/frame, applied inputs, actual loads, tire forces/slip/capacity, suspension, angular rates, assistance and crash observations. Menus and paused time are omitted. The files stay on this computer.

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
