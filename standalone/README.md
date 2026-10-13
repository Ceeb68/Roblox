# Dirtline MX standalone prototype

Windows PC is the first player target. Godot 4.6.3 with Jolt Physics replaces the Roblox runtime. This project uses metres, kilograms, seconds and 9.81 m/s² gravity throughout. The original Roblox source is retained separately; nothing under `standalone/` depends on it.

## Scope and controls

One fictional DL-MX 250F four-stroke, a handling laboratory, local session laps, suspension setup, PC/controller controls, procedural scenery and original synthesized engine audio. It is an early development build. No manufacturer branding, commercial motorcycle data or commercial simulator assets are included.

The bike starts in neutral, clutch pulled, feet down. Select first with **E**, build revs with **W**, meter clutch release with **B**, and lift feet with **F** as you move. **V** pulls the lever; **Shift** pulls it quickly. The keyboard lever holds its position when you release V/B. Dumping the clutch can stall the engine; **T** starts it when neutral or the clutch is pulled.

| Action | Keyboard | Xbox-style controller |
| --- | --- | --- |
| Progressive throttle | W | RT |
| Front / rear brake | Space / S | LT / RB |
| Clutch | V pull, B release, Shift quick pull | LB pull, progressive release |
| Shift down / up | Q / E | D-pad down / up |
| Handlebar steering | A / D | Left stick X |
| Lean articulation | Z / X | D-pad left / right |
| Rider forward / back | I / K | Right stick Y |
| Rider side | J / L | Right stick X |
| Standing / seated | C | A |
| Feet down / up | F | X |
| Recovery | R | Y |
| Starter | T | Left stick click |
| Help | H | Right stick click |
| Suspension setup | U | Menu button in HUD |
| Pause | Escape | Start |

Feet are manually deployed physical colliders; leaving them down can contact and drag on the terrain. Recovery is manual after a 2.5-second crash delay. It resets the bike to the lab spawn and invalidates the current lap. Session lap timing requires ordered gates; this build does not save records or provide online races.

## Physics architecture

- `config/bike_250f.json`: fictional engineering calibration in SI units; 109 kg bike plus 78 kg rider, five gears and neutral.
- `physics/drivetrain.gd`: crank inertia, torque curve, ignition cut/limiter, passive dry-clutch impulses, transmission losses, signed braking, engine braking, stall and explicit starter.
- `physics/tire.gd`: independent axle slip relaxation, load sensitivity, camber thrust, combined longitudinal/lateral force limit and surface-dependent rolling resistance.
- `physics/suspension.gd`: spring/preload, independent compression/rebound damping, progressive bottom stop and signed force for airborne articulation.
- `physics/gyroscope.gd`: implicit midpoint Euler dynamics using actual native principal inertia; supplies the gyroscopic precession missing from this engine configuration.
- `scripts/wheel_body.gd`: actual native cylinder-wheel contact positions, normals, impulses, ground velocity and surface tags.
- `scripts/bike_controller.gd`: four native rigid bodies (chassis/rider, steering fork, two wheels), caster steering hinge, two suspension sliders with free axle spin, paired suspension and drivetrain forces, rider COM/inertia approximation and physical crash observation.
- `scripts/track_builder.gd`: continuous triangle-collision track with berms, ruts, bumps, whoops, tabletop, large jump and grip pads.
- `scripts/rider_input.gd`, `game.gd`: manual controls, original procedural presentation, camera, telemetry, menus, setup and ordered local laps.

Native contacts provide normal support and collision response; the custom tire model provides tangential traction once. Tire collision materials have zero native friction. Motor/brake impulses are paired with chassis/fork reactions and use rotation relative to the bearing; native wheel angular momentum is not counted twice. The gyroscope integration follows physical Euler equations using each body's principal inertia. No world-upright, yaw-direction, steering-angle or landing-orientation target drives the bike. Steering input is bearing torque; real geometry and contact forces determine the response. Camera smoothing acts only on the camera.

The project requests 240 physics steps per second and raises Jolt's angular-velocity safety limit to 250 rad/s so ordinary wheel speeds are not clipped. The worker pool is capped at two threads for this small prototype; this resolved a Jolt job-capacity warning seen with the default pool in the cloud tests. This is a CPU/performance target, not a promise of deterministic physics, frame-rate independence under overload, or competitive networking. Headless validation uses `--fixed-fps 240` to observe each native tick consistently.

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

Current approximations include rigid cylindrical tires, undeformable soil, a rear suspension slider rather than a complete swingarm/linkage, a chassis-coupled rider mass rather than a fully articulated rider, and fictional tire/engine/suspension coefficients. Changing the aggregate rider COM/inertia does not model every internal linear/orbital momentum transfer; full articulated-rider conservation is an open physics task. Finite-step gyroscopic orientation integration also has measurable numerical drift, covered by convergence checks. Production motorcycle/rider meshes, rider IK, recorded audio, pneumatic carcass/soil interaction, calibrated handlebar feel and rider dynamics remain open. Human cornering, whips, scrubs, wheelies and repeated lab obstacle acceptance are required before declaring the physics complete.

Development order: accept this bike and controls on the lab; build the first original production track; then durable time trials/racing, garage, researched motorcycle collection, career/AI, measured online synchronization, more tracks and polish. Mobile controls are later work. MX Bikes remains a target for depth and believable behavior; exact replication is not claimed.
