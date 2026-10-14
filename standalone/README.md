# Dirtline MX standalone prototype

Windows PC is the first player target. Godot 4.6.3 with Jolt Physics replaces the Roblox runtime. This project uses metres, kilograms, seconds and 9.81 m/s² gravity throughout. The original Roblox source is retained separately; nothing under `standalone/` depends on it.

## Scope and controls

One fictional DL-MX 250F four-stroke, a larger handling laboratory, local session laps, suspension setup, PC/controller controls, procedural scenery and original synthesized engine audio. Version 0.5 focuses on responsive partial-stick steering, independent rider counterbalance, airborne push/pull control, physical landing catches and automatic feet. The 873 m circuit, larger tabletops, first-person helmet view and saved controller rebinding are retained. It is an early development build. No manufacturer branding, commercial motorcycle data or commercial simulator assets are included.

The bike starts in neutral, clutch pulled, feet down. Select first with **E**, build revs with **W**, and meter clutch release with **B**. Feet lift automatically during an engaged launch and riding, then plant at a grounded stop. **V** pulls the lever; **Shift** pulls it quickly. The keyboard lever holds its position when you release V/B. Dumping the clutch can stall the engine; **T** starts it when neutral or the clutch is pulled.

| Action | Keyboard | Xbox-style controller |
| --- | --- | --- |
| Progressive throttle | W | RT |
| Front / rear brake | Space / S | LT / RB |
| Clutch | V pull, B release, Shift quick pull | LB pull, progressive release |
| Shift down / up | Q / E | D-pad down / up |
| Bike lean command; bars in manual mode | A / D | Left stick X |
| Rider lean articulation | Z / X | D-pad left / right |
| Rider forward / back | I / K | Right stick Y |
| Rider side | J / L | Right stick X |
| Standing / seated | C | A |
| Recovery | R | Y |
| Starter | T | Left stick click |
| Help | H | Right stick click |
| Suspension setup | U | Menu button in HUD |
| Pause | Escape | Start |
| Chase / first-person camera | M | B / Circle |

Feet lift automatically during a deliberate clutch-engaged launch, while riding or airborne. They plant after a slow grounded stop, and can dab during a loaded walking-speed loss of balance. A preferred standing posture resumes when the feet lift again. Hysteresis and a brief remount contact-cache allowance prevent contact noise from toggling them. The actual foot colliders follow this state; no F/X command is required. Throttle in neutral and blocked recovery inputs cannot remove remount support. Bike and rider remount after one unpaused second of crashing; R / mapped recover remounts immediately. Recovery prefers nearby safe ground, falls back to the lab spawn and invalidates the current lap. It restores all five native bodies, velocities and rider collision/visible pose to a seated, neutral, feet-down state. Held inputs remain suppressed individually until released/recentered. Session timing requires ordered gates; this build does not save records or provide online races.

Default **Lean control · virtual rider** uses your primary input as a desired lean. A finite human model countersteers and steers into a developing fall through the physical fork bearing; it can follow a neutral line without assigning chassis roll, yaw or position. Steering authority, available traction and suspension still limit the outcome. **Direct handlebar control · manual** remains selectable in Settings. Real upper-body movement remains separate and influences COM, reaction and the rider's visible pose. Slides can recover before the actual bike departs; traction loss alone no longer immediately shuts down the rider.

Version 0.3 introduced ground-supported steering and compliant rider improvements. Version 0.4 keeps steering feedback active when the rear unloads but the front still supports the bike, smooths requested-bank reversals, limits the rate of the requested lean, and reduces unreliable slip feedback during unloading. An unsupported front uses local handlebar grip rather than requesting curvature from a tire that cannot steer the ground. Balance response and handlebar gains are scheduled by speed with explicit bounds. Brush saturation and re-grip provide crash context rather than instantly disabling the rider before an actual dangerous attitude or landing occurs.

Bike lean now requests the bank of the combined bike/rider mass through a progressive stick response. The frame target accounts for the actual rider COM, so leaning the rider outside a turn can let the bike bank further inside it. Rider roll and side inputs no longer cancel or add a second bike-steering command. Neutral stick release lets measured bank and yaw settle before choosing a new line. Front-only loading retains bounded roll-catching steering. Tire coefficients are unchanged; tread speed uses the actual native contact lever.

The neutral heading response is slower than the inner balance response, avoiding two controllers fighting each other during acceleration. Normal handlebar effort remains limited to 45 Nm. Following sustained flight, a short loaded landing catch can use up to 75 Nm and current positive front-wheel support; it still acts only as equal/opposite fork and frame torque. Fully unsupported steering uses local grip, with no world-bank or heading target. The actual caster geometry has approximately 110 mm trail. These settings are independent prototype calibration, not MX Bikes parameters.

Unsupported right-stick body-side input also requests up to 30 degrees of rider-relative hip yaw, through the existing paired torso torques. This exchanges real angular momentum with the frame. Counter-input can unwind a whip; neither the bike pose nor its airborne trajectory is assigned. The visible rider and helmet follow the actual hip twist with hands/boots anchored to the bike.

The virtual rider braces through finite body articulation under acceleration and impacts. Manual ground body input controls weight position with monotonic remaining-travel bracing. In sustained flight, forward/back input becomes physical push-down/pull-up effort through relative torso counter-motion; neutral keeps the takeoff posture. Brief whoop gaps retain the ground riding task. Gentler closed-throttle engine braking reduces rear-wheel back-drive shocks on touchdown while retaining real clutch, engine and wheel reactions. World-bank/line feedback is inactive while unsupported. Hands still hold a commanded fork angle through bounded, paired bearing torque, so real wheel gyroscopic reactions remain possible. Direct mode retains literal body positioning and manual handlebar effort.

Press **M / controller B** for helmet view. The camera follows the physical rider's head, hides nearby head/torso meshes, retains real arms/bars/fender, and smooths only camera motion. The chase occlusion ray checks world obstacles and excludes all five motorcycle bodies, so rider-stick motion cannot retract the camera into its own capsule. Chase distance and both fields of view are adjustable. Close chase framing and full human gear proportions increase screen presence while retaining real motorcycle dimensions and masses.

The rider uses a relaxed seated hip hinge, naturally bent elbows and a higher standing stance. Two-bone arm and leg articulation keeps gloves on the actual fork grips and boots on the pegs. The visible torso and helmet follow the independently moving native rider, while anatomical reach limits preserve hand/foot contact without stretching limbs. The physical rider uses compliant leg and posture forces, with weight compensation restricted to supported conditions. Aerodynamic drag is shared between the frame and real rider COMs instead of putting their entire drag below the combined COM. These are explicit prototype muscle/aerodynamic assumptions, not measured production motorcycle data. Remount resets the physical body and visible pose immediately.

Read [research notes](MX_BIKES_RESEARCH.md) for the published control principles and their limits. The official MX Bikes sites were blocked by cloud network policy; no proprietary steering gains, filters or animation behavior are attributed to them.

In **Escape / Start → Settings + controller binds → Controller bindings**, click an action's binding and press a button or move an axis fully in the desired direction. Every riding/menu/camera action is remappable. Directional half axes support independent assignment, coherent axis inversion and conflict replacement; deadzones, clear/reset and selected-device routing are included. Bindings persist in `user://controller_bindings.cfg`; camera/riding/display preferences persist separately. Disconnecting a controller releases controls. Hardware controller polling still needs a real controller playtest.

## Physics architecture

- `config/bike_250f.json`: fictional engineering calibration in SI units; 109 kg bike plus 78 kg rider, five gears and neutral.
- `physics/drivetrain.gd`: crank inertia, torque curve, ignition cut/limiter, passive dry-clutch impulses, transmission losses, signed braking, engine braking, stall and explicit starter.
- `physics/tire.gd`: independent axle slip relaxation, load sensitivity, camber thrust, combined longitudinal/lateral force limit and surface-dependent rolling resistance.
- `physics/suspension.gd`: spring/preload, independent compression/rebound damping, progressive bottom stop and signed force for airborne articulation.
- `physics/gyroscope.gd`: implicit midpoint Euler dynamics using actual native principal inertia; supplies the gyroscopic precession missing from this engine configuration.
- `scripts/wheel_body.gd`: native rounded-cylinder contact geometry, ground velocity, surface tags and contact-load estimates.
- `scripts/bike_controller.gd`: five native rigid bodies (94 kg frame, 78 kg rider, steering fork, two wheels), caster steering hinge, two suspension sliders with free axle spin, finite rider reach limits, paired suspension/drivetrain/rider forces and physical crash observation.
- `scripts/track_builder.gd`: continuous triangle-collision track with berms, ruts, bumps, whoops, tabletop, large jump and grip pads.
- `scripts/rider_input.gd`, `game.gd`: manual controls, original procedural presentation, camera, telemetry, menus, setup and ordered local laps.
- `scripts/controller_bindings.gd`: persisted, device-specific button/axis routing and conflict handling.
- `scripts/rider_visual.gd`, `bike_visual.gd`: original full-face MX helmet/goggles, jersey/protection/boots, jointed limbs anchored to real grips/pegs, detailed plastics/engine/frame, spokes and knobbies.

Native contacts provide normal support and collision response; the custom tire model provides tangential traction once. Tire collision materials have zero native friction. Rounded cylinder shoulders use Jolt's convex margin with collision-margin fraction 0.9, preserving smooth rolling and outer dimensions. Tire patch velocity includes non-spin angular transport, avoiding false lateral slip during roll. Motor/brake impulses are paired with chassis/fork reactions and use bearing-relative rotation; wheel angular momentum is not counted twice. Gyroscope integration follows physical Euler equations using actual principal inertia. Virtual-rider steering uses bounded bearing torque, and bracing uses the same finite rider articulation/reaction as manual body movement. There is no direct upright, heading, position or landing-orientation constraint on the chassis. Fully manual mode bypasses virtual-rider feedback.

Godot 4.6.3 Jolt's `get_contact_impulse()` exposes an estimated collision response rather than its final joint-coupled solved impulse. Version 0.3 normally infers tire load from the wheel's completed native momentum change along the free suspension axis, subtracting gravity and the recorded spring/tangent forces. The unconstrained slider direction removes unknown transverse guide forces. Completed-step force records and velocity samples must match; reset and one-time fixture velocity prescriptions invalidate that history. This estimates the brush's traction budget and does not apply a second normal force.

Mechanical suspension stops add unknown axial reactions, so near a stop, an axis singularity or a missing force/velocity sample the adapter uses an explicit collision-response fallback. It groups identifiable coplanar triangle responses (including static material seams), averages their alternative load estimates and uses unique native points for patch geometry. Distinct support normals remain separate. Simultaneous nonparallel contacts, finite-step guide motion, unexposed manifold IDs and saturated contact buffers remain approximations. Dedicated box/mesh/seam/bank tests cover both the momentum estimate and the fallback. Actual wheel collision and normal support remain entirely native.

Spring rates are effective rates at the wheel: this rear slider has no linkage ratio. Defaults are 9,000 N/m front and 9,500 N/m rear, with 300 mm travel and independent compression/rebound damping. They are fictional prototype calibration rather than manufacturer fork/coil specifications. Native feet-raised static tests measured about 68 mm front and 87 mm rear sag, compared with about 27/33 mm in version 0.2.1.

The project requests 240 physics steps per second and raises Jolt's angular-velocity safety limit to 250 rad/s so ordinary wheel speeds are not clipped. The worker pool is capped at two threads for this small prototype; this resolved a Jolt job-capacity warning seen with the default pool in the cloud tests. This is a CPU/performance target, not a promise of deterministic physics, frame-rate independence under overload, or competitive networking. Headless validation uses `--fixed-fps 240` to observe each native tick consistently.

## Expanded circuit

The timed course measures about 872.5 m, with 14 gates. The original north-half stations and separate practice/jump/grip lanes keep their coordinates. The extended east straight adds 3.2 m and 4.5 m filled tabletops, a 15 m road with graded shoulders, and a 42 m larger-jump landing. A longer, smoother descending crest avoids an unwanted second hop at the tested approach speeds. The west return has broad 0.6–1.2 m rollers.

[Engine assessment](ENGINE_ASSESSMENT.md) records isolated 240/480 Hz tests of Jolt and Godot Physics. Switching backends alone did not demonstrate better complete-bike handling; Unity/Unreal were not tested. Native solved-contact access and gyro integration are concrete future adapter options.

## Build and validate

```bash
cd /workspace/Roblox
bash standalone/tools/setup.sh
bash standalone/tools/check.sh
bash standalone/tools/export.sh windows
bash standalone/tools/export.sh linux
```

`setup.sh` reuses Godot 4.6.3 or downloads the official Linux x86_64 editor, verifies pinned SHA-256 digests, and installs the official Windows/Linux release templates. Tools and caches default to `/workspace/.dirtline-tools` and `/workspace/.dirtline-runtime`. Override `DIRTLINE_TOOLS_DIR`, `DIRTLINE_RUNTIME_DIR` or `DIRTLINE_GODOT` for another writable location or engine executable. No credentials or network service are needed to play.

Open `project.godot` in the exact editor version for interactive development. `tools/godot.sh` supplies writable XDG cache/data/config directories. The check script imports the project, runs SI math regressions, runs actual Jolt scenarios, and starts the main scene. It fails on engine error output even when Godot returns zero. Release exports go to ignored `standalone/build/` directories; do not mistake an older binary for a freshly tested source revision.

Export presets include the JSON calibration and game scripts and exclude development tests and tooling. Ship `DirtlineMX.exe`, `DirtlineMX.pck`, player instructions and `THIRD_PARTY_NOTICES.txt` together. The executable is unsigned. Engine and bundled third-party licenses are included in the notices file.

## Acceptance and remaining work

Read [native validation and handling acceptance](VALIDATION.md) before expanding the scope. Pure mathematical checks and individual native scenarios support specific behaviors, not a claim that every obstacle is convincingly rideable. The Windows export is built on Linux; Windows execution and controller hardware need a Windows PC playtest.

Current approximations include rigid cylindrical tires, undeformable soil, a rear suspension slider rather than a complete swingarm/linkage, a rigid rider torso supported by compliant muscles/legs rather than a full physical human skeleton, and fictional tire/engine/suspension coefficients. Rider forces act in equal/opposite pairs at the same world point, with separate fixed frame/rider inertias. Native joints and finite-step gyro integration still introduce measurable angular momentum/work error, covered by convergence checks. Production motorcycle/rider meshes, a complete articulated human, recorded audio, pneumatic carcass/soil interaction and calibrated handlebar feel remain open. Human cornering, whips, scrubs, wheelies and repeated lab obstacle acceptance are required before declaring the physics complete.

Development order: accept this bike and controls on the lab; build the first original production track; then durable time trials/racing, garage, researched motorcycle collection, career/AI, measured online synchronization, more tracks and polish. Mobile controls are later work. MX Bikes remains a target for depth and believable behavior; exact replication is not claimed.
