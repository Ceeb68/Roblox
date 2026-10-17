# Version 0.6 validation archive

Historical measurements and limitations for version 0.6. The current release is documented in [VALIDATION.md](VALIDATION.md).


This project is a standalone Godot 4.6.3/Jolt game, not a Roblox vehicle. The cloud machine executes the actual Linux native engine and can render the game with software OpenGL. It cannot execute the Windows desktop, poll a physical Xbox controller or judge riding feel as a human. A native automated pass proves its stated recipe, not a match to either reference game's feel.

## Why the old checks missed the reported handling problems

The version 0.5 release passed 3,493 checks, but many were mathematical assertions or small-angle/mechanical regressions. Its air maneuver required only a few degrees of bank/yaw, and it did not establish a complete controls-only motocross lap or a functional scrub. Those checks were useful diagnostics but were insufficient acceptance criteria for the user's intended ride.

A new baseline on ordinary flat dirt found front/rear mean tire slip of roughly 0.92°/0.66° and trajectory sideslip 0.16° at 12 m/s, so globally increasing peak friction would not address the main failures. The same corner took 0.60s to reach 5° bank, standing 0.67s and a 20 m/s sweep 0.82s. A normal 8s launch drifted 6.65° in heading and peaked 10.64° bank. Real-track driving then exposed steering/traction failures over bumps and down jump landings that steady flat turns had not revealed.

The most concrete traction defect was a contact-phase mismatch. The completed-step native pressure patch was combined with a later hub pose, leaving a false trailing tire-force lever and phantom lateral tread strain. Controlled probes first exposed the problem by omitting that inconsistent term. The production correction transports the pressure patch by measured hub translation, then uses the same phase-consistent point for full patch velocity, effective rolling radius and force/torque. Wheel spin, rounded-shoulder contact and camber remain represented. A 62-check native adapter suite measures the real 24 m/s lag as 20/10/5 cm at 120/240/480 Hz and checks that phase transport removes it to micrometre scale, including reverse rolling and reset/history cases. Independent tire stiffness/relaxation improves small-slip response without raising the default surface-friction peak.

The earlier lean-angle spring was strongly damped and interacted with neutral heading feedback, making initiation/reversal sluggish. The revised controller gives deliberate lean a bounded rate/acceleration task through the same finite fork bearing and retains calmer neutral line following. It does not change body mass to imitate lightness. Grounded balance and landing helpers are explicit, bounded game assistance under the user's newer 75% simulation / 25% forgiveness design request.

Native rider/bar momentum exchange alone produced too little independently controllable air roll/yaw. The new airborne task adds bounded external rate-control torque, with axis/vector/power budgets and physical inertia. It is not falsely described as a free rider conserving the entire system's angular momentum. Native gyros, rider counter-motion, clutch/engine reactions and gravity remain; no heading/world-up target or translational flight force is added. Native-only mechanics/conservation tests remain separate from assisted riding tests.

## Required A–M scenarios

| User test | Native implementation exercised | What remains for a human |
| --- | --- | --- |
| A—Straight acceleration | Actual from-rest launch, timed real clutch/gear shifts, useful speed/distance and tight heading/bank bounds | Throttle/clutch feel on an actual Xbox controller |
| B—Normal corners | Both directions at 12 m/s; useful heading change, sub-second 5° bank response, separate axle slip, trajectory sideslip and neutral release | Line choice, feel near the limit and controller deadzone preference |
| C—Tight corners | Both directions at 4 m/s; useful speed, actual trajectory radius below 8 m and supported tire slip | Walking turn confidence and feet presentation |
| D—Fast sweepers | Both directions at 20 m/s; response, real turning, axle grip and neutral recovery | Fast corner confidence on varied human lines |
| E—Hard exits | Powered corner exits, increased but bounded rear spin, retained front line and acceleration | Progressive throttle technique and controllable slide feel |
| F—Braking | Independent progressive lever inputs from 15 m/s, deceleration, front load transfer and bank control | Trail braking, lockup feel and lever mapping |
| G—Takeoff | Native ramps, 18 prepared approaches, four from-rest two-tabletop replays and full-lap jump faces | Unscripted approaches and technique variation |
| H—Air controls | Signed independent pitch/roll/yaw response, bounded torque/power, neutral decay, speed scheduling and 240/480 Hz comparison | Responsiveness versus inertia on real hardware |
| I—Whips | Both-direction real big-jump throws beyond 30° yaw, counter-input, positively loaded aligned touchdown and runout | Timing, style and repeated human recovery |
| J—Scrubs | Matched neutral/lean-only/lean+scrub takeoffs; whole five-body COM momentum, ballistic rise/airtime and no hidden downward flight force | Technique breadth, different jump profiles and visual feel |
| K—Landings | Real positive loads, independent suspension travel, grip budgets, bounded catch and actual runout | Repeated imperfect landings beyond the scripted recipes |
| L—Rider transitions | Interruptible left/right leg changes, actual bank/support/posture selection, anchored limbs and native OpenGL pose inspection | Naturalness during an actual riding session |
| M—Full lap | An automated rider uses actual controls after one ordinary spawn reset, crosses 14 gates+START, travels >820 m, clears both large jumps and stays in the prepared corridor without recovery | Full human lap at varied pace and input mistakes |

`handling_overhaul_tests.gd` contains 34 focused A–F guards. It measures useful trajectory, grip and response, rather than counting a tiny attitude change as a playable turn. Response needs both 5° requested-side bank and 5° change from input-onset bank, preventing a pre-existing wobble from counting as steering. The mirrored directions and standing case remain explicit.

`air_control_tests.gd` includes isolated 240/480 Hz maneuvers and actual shipped big-jump whips. It checks rate signs, reversal, finite axis/vector/power budgets, unsupported tire-force absence, native-only/direct bypass and covariance under rotated world frames. The real-track recipe throws early, countersteers/body-countermoves before landing, then uses real corrective inputs. No frame pose or angular velocity is prescribed after the initial rolling fixture.

`scrub_takeoff_tests.gd` uses the real 4.5 m table, matched once-initialized rolling speed, real third gear/clutch/throttle and identical bank inputs for lean-only versus scrub. It observes mass-weighted position/velocity of all five bodies. The timing regression exposed an early crouch settling and rebounding before the lip; geometric terrain/crest lookahead now schedules the same internal leg task near takeoff, with a 0.6 critical-damping ratio based on actual frame/rider reduced mass. Scrub acceptance requires actual bank/crouch and lower takeoff vertical velocity, ballistic rise and loaded-to-loaded airtime while preserving forward speed. An independent whole-assembly momentum balance accounts for gravity and the actual COM drag; unsupported tires must supply zero force. A lower rendered rider alone cannot pass.

`lap_ride_tests.gd` is a reproducible automated rider, not an in-game autopilot. It uses a path lookahead for real lean commands, progressive brakes, timed clutch shifts and actual pitch/roll/yaw inputs in flight. Landing preparation limits a deep new bank during initial suspension compression/rebound. It never teleports, replaces velocity, locks attitude, bypasses gates or invokes recovery after the ordinary spawn. All 14 real gate planes and widths match the game. The eight lap guards require the full route, both large flights, prepared-road clearance, real shifts and finite bodies.

## Version 0.6 measured results

The final required release run passed **5,002 assertions across 32 suite invocations**, followed by a main-scene startup and successful Windows export. This total includes the stronger A–M riding scenarios below; it excludes the disclosed failing optional counter-rotation diagnostic and unsupported 120 Hz experiment.

These observations use the shipped default setup at 240 Hz. Rolling fixtures initialize compatible motion once, then use real riding inputs; the straight launch and full lap start at rest. They establish repeatable native scenarios rather than human handling approval.

| Scenario | Measured result |
| --- | --- |
| Straight launch, 8s | 58.26 m traveled, 17.33 m/s final speed, 0.71° heading deviation, 7.60° maximum bank; three real shifts |
| Normal corners, left/right | 5° bank response in 0.317/0.463s; mean front slip 0.371/0.379°, rear slip 0.476/0.487°; 33.77/38.38° heading change |
| Standing normal corner | 0.458s response; mean front/rear slip 0.431/0.546° |
| Tight corners, left/right | Actual trajectory radius 6.209/6.206 m; mean speed 3.60 m/s, no crash |
| Fast sweepers, left/right | 0.396/0.504s response at a 20 m/s approach; front/rear mean slip below 0.33° |
| Powered exits, left/right | 22.50 m/s final speed, rear peak slip ratio approximately 0.291 versus approximately 0.010 in ordinary corners; front line retained |
| Progressive braking | 15→2.03 m/s in 5s, front load share 0.469→0.696, maximum bank 4.80° |
| Actual big-jump whips, both directions | 35.10–36.40° peak yaw and 14.78–17.69° bank; counter-input returns loaded touchdown to 3.08–4.21° yaw and 2.26–4.12° bank; both continue beyond z=265 without crashing |
| Complete controls-only lap | 73.513s, 891.174 m actual travel, all 14 gates plus finish; maximum bank 26.49°, minimum prepared-road clearance 2.798 m; progression/big-table flight 1.146/1.467s; six shifts, none rejected, no crash or recovery |

The matched scrub test passed twice with identical results on the frozen default setup. Relative to the same lean inputs without scrub, left/right scrub reduced whole-assembly vertical takeoff speed by **4.90/5.61%**, ballistic rise by **9.50/10.84%**, and airtime by **4.81/5.99%**. Forward takeoff speed was retained and slightly increased. Actual rider crouch at departure was 0.184/0.228 m, with downward rider-relative motion still occurring at the lip. All six takeoffs and their runouts remained crash-free. Unsupported tire force/load stayed zero; the independent airborne whole-assembly momentum residual stayed below 0.44 N after accounting for gravity and actual drag. This is a physically changed departure, not an airborne downward push or a visual-only crouch.

Frozen source SHA-256:

```text
scripts/bike_controller.gd  3432e5353db6869d2282d7210ceb75cfb82706816c1024da7b4dad3a5aad904c
config/bike_250f.json      f9fcc30f9dae6cd6c953dfa904fd463272f008fa913808d37ff1540fe810813c
```

The runtime's parsed-configuration hash is `92a09b0279dac7afe23f536f365d90759a939a2bf3d81607811be34badda85b4`; it differs from the raw JSON file hash because it hashes the parsed serialization.

## Reproduce the checks

```bash
bash standalone/tools/check.sh
```

The script imports resources and runs every tracked mathematical/native suite plus a main-scene startup. It treats engine SCRIPT ERROR/ERROR output as failure even if the process returns zero. Per-scenario JSON reports go to ignored `standalone/build/`; reports record actual script/config hashes where applicable. To inspect individual handling/lap/scrub suites:

```bash
bash standalone/tools/godot.sh --headless --fixed-fps 240 --script res://tests/handling_overhaul_tests.gd
bash standalone/tools/godot.sh --headless --fixed-fps 240 --script res://tests/air_control_tests.gd
bash standalone/tools/godot.sh --headless --fixed-fps 240 --script res://tests/scrub_takeoff_tests.gd
bash standalone/tools/godot.sh --headless --fixed-fps 240 --script res://tests/lap_ride_tests.gd
```

The handling suite also accepts `-- --hz=120` or `-- --hz=480` with matching `--fixed-fps`. These are separate physics-step experiments, not a promise that the supported runtime can silently change its 240 Hz physics budget. The suspension and air suites separately test hydraulic/air behavior across step sizes. The 418-check suspension suite passed at 240/480 Hz. The final phase-corrected 120 Hz rerun passed 409/418. Its nine failures include four impact-comfort comparisons, some 0.9 m drop balance/crash guards, and standing rough-ground balance. That lower physics rate remains unsupported. These bounds were not relaxed. The supported runtime remains 240 Hz. The actual main-game render-cadence suite independently exercises 30/60/144/240 render Hz while retaining 3,360 native physics steps over 14s, without skipped input/physics updates. Renderer frame rate and physics rate are different. Performance and overload need measurement on Windows.

`rider_animation_tests.gd` exercises continuous transitions at multiple presentation rates, mid-transition reversal and live tuning without reset. `handling_setup_tests.gd` exercises the real parked menu, independent physics changes, atomic invalid-value rejection and persistence while preserving existing user files. Input/camera tests cover selected-controller routing, deadzones, inversion, saved bindings, scrub input/conflict migration and camera separation. Hardware polling remains untested without a controller.

## Native-mechanics limits

The game still uses rigid cylinder tires, inferred contact loads, static terrain, an approximate rear suspension slider and an independently massive rigid torso with compliant muscles. No deformable soil, pneumatic tire carcass or complete biomechanical skeleton is claimed. Force pairing and passive damper checks constrain implementation errors; finite-step native constraints remain approximate.

### Coupled-rider fixture correction and remaining numerical limit

The old isolated fixture gave all bodies the same linear velocity while assigning
an assembly angular velocity. That omitted each body's `omega cross COM offset`
velocity, making native joint anchors initially incompatible. It also omitted
the production rider's airborne handlebar grip, permitting fork impacts against
hard steering stops outside the muscle-work ledger. The revised fixture seeds
coherent rigid-assembly velocities once, measures initial momentum afterward,
includes actual local handlebar torque/work, and progresses the airborne rider
task. Its passive-damping case starts with real relative vertical motion rather
than depending on the removed constant airborne leg preload.

The canonical coherent co-rotating fixture retains the original raw 2% angular-
momentum and 1% work-residual bounds. An additional coherent counter-rotating
diagnostic remains available with the same bounds:

```bash
bash standalone/tools/godot.sh --headless --fixed-fps 240 \
  --script res://tests/rider_dynamics_tests.gd -- --counter-rotation
```

This optional counter-rotation case still exceeds the raw 2% angular-momentum
bound. Counter-rotating assembly and wheel angular momentum partly cancel,
making its smaller net-momentum denominator more sensitive, but the absolute
integration error is real. Finite-step coupled gyroscope/joint integration needs
further work; passing the canonical fixture is not universal conservation.
The individual free-rotor limits and tire-force budgets are unchanged.

| Version 0.6 coherent active rider fixture | 240 Hz | 480 Hz |
| --- | ---: | ---: |
| Canonical co-rotation, peak raw angular drift | 1.092% | 0.580% |
| Canonical kinetic/work residual | 0.492% | 0.263% |
| Optional counter-rotation, peak raw angular drift | 6.318% | 3.403% |
| Optional counter-rotation, absolute angular error | 0.739 N·m·s | 0.398 N·m·s |
| Optional counter-rotation, kinetic/work residual | 0.359% | 0.257% |

The optional diagnostic exits with three failed angular guards; it is not
silently counted as a passing release check. Halving its timestep reduces the
absolute error, but does not meet the raw 2% bound.


The numerical table records version 0.6 native-only observations, not a universal bound for arbitrary riding. The passive 240 Hz counter-rotation case also fails the raw bound at 4.372% drift. The optional diagnostic reports 40 passes / 3 failures; the unchanged 43 canonical co-rotation checks pass. The optional counter-rotation diagnostic remains a disclosed failure against the raw 2% goal; it is not silently included in a passing release total. Default assisted riding intentionally adds a bounded external angular task, so it must not be used as a conservation experiment.

## Packaging and hardware acceptance

Build with `bash standalone/tools/package_windows.sh` only after the current source passes the required release checks. Packaging verifies all four shipped files against the export, tests ZIP integrity and records the SHA-256. The exact Windows project pack can also be loaded by the matching Linux release template to catch missing resources and inspect real menus/gameplay under native OpenGL. This validates packaged game resources; it does not execute the Windows PE executable.

The version 0.6.0 package completed that process: **36,147,752 bytes**, with ZIP integrity and all four shipped files verified against their sources. Both `DirtlineMX-Windows.zip` and `DirtlineMX-Windows-v0.6.0.zip` have SHA-256 `77502fddfa67284ffcd2877ade963fcdbf8ce7f35014e660ecb3ef4bc10a72ae`.

Before calling the handling complete, ride the release on Windows with the actual Xbox-compatible controller. Record build hash, handling/suspension setup, controls, approach speed, loads/slip, angles, crash reason and repeatability. Complete ordinary/tight/fast corners, both brakes, bumps, ruts, whoops, both large tables, whip/unwhip, scrub, imperfect landings and a full human lap. Check first-person/chase camera, remapping, automatic legs/recovery, audio and performance. The loaded landing aid is independently tested for its 100 N·m/1.25s budget, player-rate roll damping, terrain-pitch deadband, manual endpoints, no yaw/unsupported torque, finite expiration and reset/disable paths. The default mixed assistance must remain explicit; native-only mode must not quietly receive those external aids.


The final 47-check rider suite covers full 0.28 m target-only and actual crouch in seated and standing postures, including saddle clearance, anchored limbs and continuous reference/physical composition. This caught and corrected an older 0.22 m visual limit before publication. The full 5,002-check release pipeline was rerun after that correction.

The exact final Windows PCK (`dcdba82cedcb66780edc8a4c45bea04f7b7e62ac21ad280b426bf3af7943d5ab`, 212,376 bytes) was copied beside the verified matching Linux release template and loaded headless for 480 frames, then under native software OpenGL. Both exited cleanly. Native inspection covered the v0.6.0 welcome, F/X scrub help, 0.28 m / 3.5 rebound setup, helmet/chase views and a real E/W/B launch with automatic feet. No body-state setters were used for that launch. The external-script fixture path is unsupported by the release template and was stopped; it is not counted as a passing packaged test. The 47 pose checks run in the pinned native development engine.

The Windows executable remains the official unmodified 4.6.3 release template (PE resource modification is disabled); the project/PCK and archive identify game version 0.6.0. Package checks verify the x64 PE format and all four exact payloads, without claiming Windows desktop execution. Windows/Xbox human riding and performance acceptance remain outstanding.
