# Version 0.7 motorcycle physics overhaul

This report describes the causes found in the existing standalone game and the changes made to its original motorcycle simulation. The target is responsive, learnable motocross handling with substantial physical depth. MX Bikes and MX Simulator are references for riding qualities; no proprietary code, assets or physics engine from either game is used, and their exact behavior has not been reproduced or measured here.

The numerical comparisons below are controlled development observations. The final integrated workflow passed 5,342 required assertions, exported Windows and verified the ZIP, as recorded in [VALIDATION.md](VALIDATION.md). Windows and physical-controller playtesting still follow. Passing a scripted riding recipe does not establish that the game feels good to a human rider.

## Existing architecture and retained systems

The engine is **Godot 4.6.3 with Jolt Physics**, running the motorcycle at **240 physics updates per second**. One world unit is one metre. Rendering and camera updates are separate from the fixed physics loop. This is a standalone Windows game; the repository's older Roblox implementation does not drive this motorcycle.

The bike remains an articulated assembly of five native rigid bodies: a 94 kg frame, 2 kg fork, 5.5 kg front wheel, 7.5 kg rear wheel and 78 kg physical rider. The motorcycle mass is 109 kg and the combined mass is 187 kg. Those masses and the soil tire coefficients were not reduced or inflated to conceal handling defects. Wheel radii, travel, wheelbase, caster, trail and body inertias remain explicit SI parameters.

| Responsibility | Implementation | Physical mechanism |
| --- | --- | --- |
| Simulation order, articulation, rider, steering, crash/recovery | [scripts/bike_controller.gd](scripts/bike_controller.gd) | One fixed-step force path; native bearing/slider constraints; paired rider forces and torques |
| Native wheel contact and material identity | [scripts/wheel_body.gd](scripts/wheel_body.gd) | Native collision support, patch observations, solved-load estimation and contact-phase alignment |
| Front/rear traction | [physics/tire.gd](physics/tire.gd) | Independent relaxed slip states, brush response, load sensitivity and a combined force ellipse |
| Spring, hydraulic damping and bottoming | [physics/suspension.gd](physics/suspension.gd) | Internal strut force pairs using measured travel/rate and contact-constrained mobility |
| Virtual human's lean task | [physics/lean_control.gd](physics/lean_control.gd) | Bounded desired roll rate and physical countersteering through the actual fork bearing |
| Engine, clutch, gearbox and brakes | [physics/drivetrain.gd](physics/drivetrain.gd) | RPM-dependent torque, gearing, clutch transfer, engine braking and wheel torque reactions |
| Native body gyroscopic dynamics | [physics/gyroscope.gd](physics/gyroscope.gd) | Implicit Euler rotational correction for each body's own inertia |
| Optional active airborne control | [physics/air_control.gd](physics/air_control.gd) | Consistent bar/torso requests plus an explicit torque and power limited gameplay budget |
| Physical takeoff absorption | [physics/scrub_control.gd](physics/scrub_control.gd) | Actual rider crouch and loaded-face rebound control; no airborne downward impulse |
| Input and controller routing | [scripts/rider_input.gd](scripts/rider_input.gd), [scripts/controller_bindings.gd](scripts/controller_bindings.gd) | Selected-device polling, remappable axes/buttons, automatic support-foot reflex and recovery rearming |
| Procedural rider and motorcycle | [scripts/rider_visual.gd](scripts/rider_visual.gd), [scripts/bike_visual.gd](scripts/bike_visual.gd) | One interruptible pose/IK path connected to actual body, fork, suspension and support-foot geometry |
| Track, menus, cameras and diagnostics | [scripts/track_builder.gd](scripts/track_builder.gd), [scripts/game.gd](scripts/game.gd) | Native course collision, local laps, first/chase cameras, setup persistence and optional telemetry |
| Handling schema and defaults | [physics/handling_setup.gd](physics/handling_setup.gd), [config/bike_250f.json](config/bike_250f.json) | Validated parked adjustments with independently named parameters |

Bike-local axes are right `+X`, up `+Y`, forward `-Z`. Projected bank/heading rates are calculated for their actual angle definitions; local angular-rate telemetry is labelled separately. Riding does not assign the chassis transform or rotate it directly to follow an input. Spawn/remount is the intentional reset path. Visual limb transforms and camera transforms are presentation, while force/torque application and native constraints determine riding motion.

The wheels use zero native tangential friction so the custom tire patch is the sole tire-force source. Native collisions supply ground-normal support. Suspension does not add a second ground-support force, and the tire's patch force supplies its own wheel torque through the actual lever arm. Boot/guard friction is a separate collision role.

## Ground traction: the road itself was disturbing tire support

The previous main track built separate native static colliders for each visual soil type. Adjacent coplanar materials therefore had independent collision edges. Rolling wheels could strike those boundaries as physical edges even though the surface looked continuous. This changed normal load abruptly, briefly removed tire support, and then returned it with an impact. Increasing the tire coefficient would not remove that collision defect.

The main course now keeps its visual material meshes but uses **one continuous native collision mesh**. Soil identity is resolved from the actual contact position in the road's local coordinates. Dirt, sand, mud, hardpack and loam retain distinct tire properties. Rotated/translated tracks and ordinary colliders with material metadata remain supported.

In the controlled shipped-track seam comparison:

| Native observation | Separate soil colliders | Continuous road collider |
| --- | ---: | ---: |
| Front peak load | 4,244 N | 1,143 N |
| Rear peak load | 7,454 N | 1,305 N |
| Front support gap | about 17 ms | no dropout in the 240 Hz comparison |
| Rear support gap | about 25 ms | no dropout in the 240 Hz comparison |

[tests/terrain_contact_tests.gd](tests/terrain_contact_tests.gd) now rolls the actual articulated bike across real material boundaries, including a reversal sequence, and checks material identity, sustained unloading, native load spikes and tangential-force discontinuities. It permits a legitimate single zero-impulse speculative contact; it does not invent normal load to keep grip alive.

The existing front/rear brush tire model was retained. Each patch derives longitudinal and lateral force from its own actual load, rolling transport, wheel speed, slip ratio, slip angle, camber and soil. Slip relaxes over distance rather than changing instantly. Load sensitivity reduces normalized grip under heavy load, and acceleration/braking/cornering share the same combined budget. Full wheel-point velocity and the phase-aligned contact lever remain important: counting wheel spin twice or applying it through a stale patch can fabricate sideways slip.

The new shared `Tire.force_limits()` capability query is used by both the tire force law and the virtual rider's feasible lean request. Previously the rider consulted only nominal soil friction, ignoring the independently tunable axle/lateral capacities used by the actual tire. Sharing the budget prevents tuning changes from making the controller request a bank inconsistent with the tires. Nominal axle load is used for the requested-bank envelope so every small unloading event does not become a new steering command; actual load and combined slip still decide the force that can be produced.

The normal soil coefficients remain dirt 0.85, hardpack 1.02, sand 0.62, mud 0.40 and loam 0.90. A rear slide remains possible when drive/brake/corner demand exceeds its physical budget. Brush saturation alone does not automatically dismount the rider.

## Steering and balance: competing control tasks were producing unwanted turns

The virtual rider previously mixed neutral position pursuit, instantaneous chassis-yaw feedback and different roll control laws for deliberate turns versus neutral riding. Countersteering intentionally moves the front end and chassis heading before the full vehicle follows its new course. Treating that immediate chassis movement as a new directional error made the outer task oppose the maneuver that the inner task was trying to initiate. Pursuing an old lateral position could also request a fresh corner after the player released the stick.

The ground rider now uses **one bounded roll-rate task** for entry, reversal, neutral recovery and straight riding. Its directional reference is actual horizontal travel course. Neutral control holds a chosen direction through finite bars; it does not pull the motorcycle back to a historical lane. After a deliberate turn, balance recovers before a stable exit course is captured with a calmer direction response. A neutral jump preserves the chosen approach course; a deliberate whip can choose the actual exit direction. Capturing every small landing drift as a new straight reference was tested and rejected because it compounded lateral departure. The old position-pursuit and alternate neutral angle-spring path have been removed.

The stick requests the bank of the combined frame/rider mass. The rider's real torso position changes the combined centre of mass, so leaning the torso outside a corner permits more motorcycle bank for a similar combined turning request. Body lean is not cancelled by a separate frame-upright target. The virtual human generates countersteer/steer targets from speed, height, wheelbase, gravity, bank and bank rate; a bounded torque pair then acts across the real fork/frame bearing. Tire forces produce the trajectory. Low speed blends toward maneuverable bar behavior, while speed and available tire capacity constrain the requested bank.

A development straight-launch run measured **1.33 m maximum lateral deviation and 0.20° heading change over the first 100 m**. That is one measured run, not a universal bound. An additional real main-scene keyboard probe accelerated from rest, shifted through third, held a right turn, released it, reversed left, and released again at 60 Hz rendering/240 Hz physics. At that intermediate source it reached 5° bank in 0.308 s, used actual tire contact, and had no crash or recovery. Its recorded neutral bar/bank oscillations also showed why simply checking mean bank or completing a lap was insufficient; final behavior must be judged with the new recordings and final tests.

Low-speed assistance remains explicitly configurable. It is bounded by actual support and acts toward the requested riding task. It does not replace the physical bar/tire path, and it is not described as a natural self-stabilizing force. Direct mode supplies manual bars; reducing gameplay assistance does not silently reinterpret the virtual rider's input directions.

## Suspension and stopping: contact constraints changed the effective damper mass

The suspension already had real front/rear sliders, spring/preload forces, separate compression/rebound damping, digressive high-speed damping, progressive rubber bottoming and a hydraulic bottoming cone. Its analytic hydraulic substep prevents an explicitly applied high damper force from reversing a light axle and adding energy. Those working mechanisms were preserved.

The remaining defect was the mass used by that hydraulic substep. It treated a planted wheel as a freely translating light axle. Once the ground constrains wheel-normal motion, the damper moves a much larger effective body/constraint combination. Using free-wheel mobility silently weakened the damper despite a seemingly adequate configured coefficient.

The fix removes the supported normal constraint row from wheel mobility, including the patch lever and inverse inertia, before calculating the strut's effective mass. Support is unilateral: a candidate rebound force that would require the ground to pull the tire down rejects the constrained case and returns to free mobility. Suspension remains an internal force pair in flight.

The isolated native 100 kg/5 kg damper bench has an expected velocity ratio of **0.1353 after 0.2 s**:

| Step rate | Former planted-wheel result | Contact-aware result |
| --- | ---: | ---: |
| 240 Hz | 0.256 | 0.129 |
| 480 Hz | 0.193 | 0.132 |

[tests/contact_damper_tests.gd](tests/contact_damper_tests.gd) checks the actual constrained and unsupported native systems against the physical time constant. Unsupported behavior is retained. The local constrained-mobility model is still an approximation to the complete multi-body solver, not a full replacement solver.

Stopping exposed a separate physical issue. Full 3D chassis speed had been used to decide whether the rider was traveling: a vertical boot/suspension kick could retract stopped support feet. Automatic feet now use horizontal `groundSpeedMps`, while contact/air dwell still raises the feet on genuine takeoff. More fundamentally, the old support capsules could be enabled several centimetres inside the ground, creating a large depenetration impulse. Boots now deploy at finite leg-extension speed using ground-plane queries and shape sweeps, then retain an actual planted leg length. Their visual targets follow the physical support geometry. The native boot/guard material explicitly selects its intended 0.45 friction against the zero-friction tire-support terrain. The complete native contact suite passed 262 checks, including 12° banked parking followed by intentional support-foot removal. Guarded suspension runs passed 426 checks at both 240 and 480 Hz, including positive-clearance boot deployment and rejection of the old delayed acceleration spike. Initial remount support is swept/clipped safely before the reset commits; later plants remain progressive. Body/foot collisions retain native response rather than an assigned upright pose.

## Air control, whips and takeoff momentum

The engine, clutch, wheel inertias, rear-brake reaction, actual fork travel, physical rider body, gravity and native gyroscopic dynamics remain active in the air. Throttle/rear brake act through the rotating drivetrain/wheel system; no speed boost or direct midair position command was added.

Two air-control causes were corrected:

1. Torso yaw and the desired bike yaw used a conflicting sign. A paired hip torque must rotate the torso in the opposite angular direction to help yaw the bike. The corrected native reaction test measured opposite yaw impulses of approximately **±1.472 N·m·s** for opposite inputs.
2. Centred controls previously requested zero angular rate through an external damping budget. That erased takeoff momentum even without a player correction. The default `AirControl.NeutralDampingStrength` is now **0**. In the controlled comparison, the old neutral assistance removed about **25.52 N·m·s**; the new default adds **zero external neutral impulse**. The same control mapping now remains in force when external assistance strength is zero.

Active input can still request bounded pitch/roll/yaw rates through the explicit gameplay-assistance budget. It uses the actual five-body assembly inertia tensor, finite response times, torque limits and positive/dissipative power limits. This extra external torque is an accessibility choice; a real unsupported rider cannot generate external angular momentum. It does not target world-up, a stored heading, a landing angle or a ballistic position. Neutral releases the task, and a counter-input deliberately changes the requested rate.

Whips combine actual fork movement, physical torso/hip reaction, spinning-wheel dynamics and the optional active budget. They are not a model animation or an instantaneous yaw assignment. Development large-jump runs produced approximately **34–40° yaw whips**, recovered through real counter-input, and also landed with landing assistance switched off. These show deliberate yaw/recovery capability; they do not establish an arbitrary stunt envelope or human-controller feel.

The existing functional scrub uses lean on a loaded rising jump face, actual rider crouch and controlled rebound absorption. Crest preparation queries terrain ahead in the real travel direction; it is not tied to a named jump. Its trajectory effect occurs while supported. It adds no midair downforce. Adjustable takeoff rebound is an approximation to rider suspension absorption rather than a claim to a measured motocross shock/rider model. Matched whole-assembly takeoff comparisons remain part of the required integrated suite; their final measurements are recorded in VALIDATION.md.

## Landings and crashes: use the contact plane, not misleading world components

The old sideways-landing calculation projected impact velocity onto the motorcycle's banked right axis. That axis contains a vertical component while leaned, so an ordinary vertical impact could be misread as lateral sliding. Ground-fall and loop-out checks also used world attitude in situations where the terrain itself was banked or uphill.

Crash observation now uses the load-weighted support normal/velocity. Sideways speed is measured along the bike's right direction projected into the contact plane; normal impact remains a separate severity measure. Bank/pitch are evaluated relative to support where available. Chassis/rider-only falls retain a conservative gravity frame. A rear slide or momentary tire saturation remains recoverable until real attitude/impact conditions justify a crash.

Controlled native examples in [tests/crash_contact_tests.gd](tests/crash_contact_tests.gd):

- At approximately 65° motorcycle bank, a 7.24 m/s normal impact formerly appeared to contain about 6.6 m/s sideways speed. The corrected tangential value was about 0.147 m/s; it no longer falsely triggers the sideways-landing condition.
- A genuine approximately 7.47 m/s tangential sideways landing still crashes.
- A 40° berm plus approximately 28° relative motorcycle bank is not incorrectly classified as a fall merely because world bank exceeds the old 67° threshold.
- Hard tilted impacts and genuine severe native falls still start crash/recovery behavior.

Landing support is a distinct, configurable system. Its default external torque window is now 0.30 s, with pitch-return stiffness 0: it damps rotation and never requests a pitch angle. An optional nonzero pitch spring remains explicitly adjustable. A matched frozen-source comparison found the former 1.25 s spring could disturb the first landing and compromise the next jump approach; the short rate catch passed the same powered sequences. All four seated/standing × held/chopped throttle sequences reached the big-jump runout through actual inputs. The native suspension, tires, rider and finite bar catch do the primary work. Existing one-second automatic remount and manual recovery reset all physical bodies, contact/control histories and input rearming.

## Rider motion and actual startup integration

The game retains one procedural rider pose/IK system with smooth, interruptible sitting/standing and signed inside-leg transitions. Direction changes continue from the current pose instead of restarting a competing clip. Hands follow real fork grips, ordinary riding feet follow pegs, support feet now follow actual swept/deployed boot positions, and torso movement follows the physical rider/reference transform. The physical rider's translation and torque reaction affect mass distribution; the mesh is not the source of an extra hidden force.

A separate startup integration defect made saved handling appear ineffective. `game.gd` added the bike to the scene tree before passing its loaded configuration. The bike's synchronous `_ready()` built the native assembly with defaults; the later `configure()` correctly refused to rebuild it, silently leaving the saved values unused. Tests normally configured their fixture before adding it, so they missed this real game path.

The game now configures the bike **before** entering the tree. A native main-scene probe with saved front grip 0.50 and steering response 0.25 s formerly produced actual values 1.00 and 0.07 s; it now produces 0.50 and 0.25 s. Startup tests also check rider timing, preservation of unrelated drivetrain/suspension parameters, and atomic rejection of malformed/unsupported saved setups. These changes preserve the selected controller, first/chase cameras, manual clutch/gears, customizable bindings and local lap progress behavior. Native rider inertia also now wires its separately configured yaw value to the Y axis; the default yaw/roll values are equal, so this repairs tuning without changing the default mass distribution.

## Instrumentation and repeatable testing

The existing proving area and circuit provide a flat launch, flat/banked corners, soil pads, ruts, braking bumps, whoops, smaller tabletops, larger jumps and landing runouts. Controlled native fixtures isolate one cause before returning to that circuit.

During a session:

- **F8** toggles the optional physics panel. It starts hidden and displays actual speed, bank/pitch/steer, local angular rates, support state, independent loads, slip ratio/angle, compression, grip utilization, bar effort, assistance magnitudes and crash/landing observations.
- **F9** starts/stops CSV capture. The game displays the concrete saved path; files are created under `user://telemetry/`. Debug keys are handled before device selection, so viewing diagnostics does not switch an Xbox rider to keyboard controls.

CSV rows sample the completed native step before the next input poll. Body/contact columns describe that solve; force columns describe the tire commands applied during it; input columns contain its applied control packet. Rows include completed physics-frame identity, simulation time/timestep, forces/capacities, slip work, soil/load method, local rates, world assistance/posture torque components and terrain-relative crash observations. Paused/menu frames are omitted. Recording flushes once per simulation second and on crash, and closes on stop/exit. Missing landing observations remain empty rather than looking like a zero-severity landing.

[tests/telemetry_recorder_tests.gd](tests/telemetry_recorder_tests.gd) round-trips signed forces, units, input association, vectors, flags and escaped crash text through the real CSV writer/reader. It also exercises the actual main-game F9 dispatcher and verifies one row for each of 32 consecutive native frames, real tire loads, controller ownership and exit closure. The final focused run passed **41 checks**, including actual crash-gated input snapshots and recovery. The focused startup handling suite passed **38 checks** and the automatic-feet suite passed **97 checks** before the later support-foot geometry integration; those counts are development observations rather than the final total.

Run the complete workflow from the repository root:

```bash
bash standalone/tools/setup.sh
bash standalone/tools/check.sh
```

The check runner rejects engine script/errors even if the engine exits with status zero. Reports under ignored `standalone/build/` contain per-scenario observations; compare source/config hashes when supplied. For a different physics frequency, use both matching `--fixed-fps` and the test's `-- --hz=` option where supported. Fixed rendering tests intentionally use their separately documented render cadence and await every native physics frame.

## Tuning and remaining verification limits

Park upright and use **Pause → Handling setup**. Suspension has its existing **U** setup menu. `config/bike_250f.json` is the engineering source of defaults; the validated parked menu exposes supported subsets.

| Desired change | Parameters and practical effect |
| --- | --- |
| Less external assistance | Lower `Assistance.Strength`; tune low-speed and landing strengths separately. The virtual human still steers through real bars. |
| More native airborne behavior | Lower `AirControl.Strength`; keep `NeutralDampingStrength` at 0 to preserve neutral takeoff rotation. Direct mode also removes the virtual human task and is a different control scheme. |
| More forgiving landings | Increase `Assistance.LandingTime` or strength carefully. Nonzero `LandingPitchStiffness` explicitly adds an attitude spring and can interfere with successive jumps; default 0 preserves the rate-only task. |
| More forgiving air corrections | Raise active pitch/roll/yaw rates or response/recovery within supported ranges, or deliberately enable a small neutral damping strength. These are explicit assistance choices. |
| Quicker lean without reducing mass | Adjust `VirtualRider.IntentResponse`, `LeanRate`, `LeanRecoveryRate`, prediction and steering sensitivity. Smaller response times mean faster requests; excessive bandwidth can excite real coupled modes. |
| Change traction limits | Tune independent front/rear grip and lateral/acceleration/braking capacities. These alter limits, not road collision continuity. Preserve front/rear and soil differences. |
| Change weight transfer/landing absorption | Adjust each axle's spring, preload, compression/rebound and high-speed damping. Watch actual travel, support and force rather than judging only the visual fork. |
| Change scrub absorption | `ScrubControl.MaxCrouch` and loaded rebound control change the supported takeoff task. They do not apply a downward airborne force. |
| Change animation speed | Rider transition/corner/support timing changes continuous blending; it must remain consistent with actual support and body movement. |

There is no single setting that literally represents a simulation percentage. Start with the defaults, record one controlled change, and compare actual trajectories and forces before changing another subsystem.

The tire curves are original engineering approximations, not measured competition knobby-tire data. Soil does not deform or evolve ruts dynamically. The contact adapter estimates some joint-coupled loads because Jolt's reported impulses are not a complete final constraint solution; singular/stop/missing-history conditions retain a disclosed fallback. Contact-constrained damper mass is local rather than a complete multibody factorization. Rider anatomy/constraints and active air assistance approximate human control. Native joint angular-momentum error must remain separately measured with assistance disabled; active assistance is not a conservation experiment. No multiplayer vehicle synchronization exists to validate.

The former test suite's blind spots matter: many corner/air fixtures seed one coherent rolling/airborne state; the render-cadence main-game test uses a straight hardpack bench; synthetic controller events do not create a physically connected Xbox device; and the full-lap bot uses high-frequency feedback, track-aware speeds and deliberate landing inputs. These are useful regressions, but none is a substitute for an ordinary player riding the shipped Windows build.

The landing default, banked support and controlled riding changes are implemented. The final integrated suite and rebuilt package results are recorded in [VALIDATION.md](VALIDATION.md). Windows executable execution, an actual Xbox controller, a human full lap, the subjective feel of turn initiation and whip recovery, and real Windows frame pacing require in-engine playtesting on that hardware. Compilation and automated movement alone are not the completion criterion.
