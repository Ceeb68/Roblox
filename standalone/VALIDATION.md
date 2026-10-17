# Version 0.7 native validation

Dirtline MX runs Godot 4.6.3/Jolt at 240 physics updates per second. The cloud executes the actual Linux engine, native contacts and compiled project pack. It can render through software OpenGL; it cannot execute Windows or poll a physically connected Xbox controller. Automated trajectories establish their stated riding recipes, rather than subjective riding quality or an exact match to MX Bikes/MX Simulator.

The [engineering report](PHYSICS_OVERHAUL.md) maps the implementation and explains the controlled root-cause comparisons. [Version 0.6 results](VALIDATION_V0_6.md) are archived separately so old neutral damping and landing-assistance behavior are not mistaken for current defaults.

## Release workflow and source

The release workflow is `bash standalone/tools/package_windows.sh`. It imports the project, runs the complete required check suite and a main-scene startup, exports Windows, verifies all four ZIP payloads byte-for-byte, checks ZIP CRC and records SHA-256. Engine SCRIPT ERROR/ERROR output fails the workflow even if exit status is zero. Development tests/tools/build are excluded from the project pack.

The final release workflow passed **5,342 required assertions across 39 suite invocations**, followed by main-scene startup, successful Windows export and ZIP integrity/payload verification on 2026-10-17. A preceding complete run passed 5,328; final review then corrected an observer-only CSV crash-gating mismatch and added 14 assertions before rerunning the full workflow. The legacy repository Luau tests/analyzer/compiler and place verification also passed; the active game remains standalone.

```text
scripts/bike_controller.gd cec280b7ac691920fa7445a83f10ebb04dc485d284c9b8589a0cd4cd60b97666
config/bike_250f.json     a12c90e11cc5384e3ace001ad9893962b28b5be6f73e74604b16a7d64db144e0
```

The late controller change only stores the effective control packet for observation; removing its declaration/reset/copy reproduces the previously tested controller's exact `b3e33f64…` hash. It does not alter force calculations or their order. Two unused virtual-rider JSON keys were removed. The complete final workflow was rerun rather than assuming those changes were harmless.

Windows archive: **36,164,662 bytes**, four verified payloads (executable, matching project pack, player guide and notices). The Windows PE is x86_64; the unsigned official engine template retains its engine metadata, while the project/player guide identify game version 0.7.0. The exact shipped configuration JSON is present in the pack.

```text
Windows ZIP SHA-256 b090692fbf57c20a605a5c507ecd1826c9546c9218572ae73a26e457bc5240b8
Project pack SHA-256 f3a6ed81c217d690b84b7918bd0d8313b22d1f5c67769f85f4d5a235aa1a5adc
```

The exact shipped Windows project pack also ran beside the matching official Linux release template, with no source-project fallback. Both headless startup and the rendered software-OpenGL session exited successfully without engine/script errors. Native window inspection covered welcome/help, chase and helmet cameras, manual recovery, handling fields and customizable controller-binding menus. The visible defaults were a 0.30 s landing damping window, zero pitch-return stiffness and zero neutral air damping. F9 recorded 1,760 consecutive 240 Hz steps over 7.333 s during a real clutch launch, reaching 16.122 m/s with both axle loads and effective controls recorded and no crash during capture. Recording stopped and closed correctly. Screenshots, CSV and the release receipt are generated under ignored `standalone/build/pack-smoke-v7/`; this Linux pack smoke does not execute the Windows PE or test a physical controller.

## What was actually exercised

| Riding requirement | Native evidence | Remaining playtesting |
| --- | --- | --- |
| Straight acceleration | Real from-rest clutch/gear launches; 100 m lane/heading guard; actual main-loop input at 30 and 240 render FPS | Windows throttle/clutch feel, real Xbox trigger range and frame pacing |
| Ordinary and tight turns | Both directions, seated/standing, actual trajectory, independent axle slip, physical countersteer and neutral recovery | Human line choice and confidence near grip limits |
| Rapid corrections | Eight unseeded launches with abrupt partial-stick steps, releases and direction reversals | Controller deadzone and sensitivity preference |
| Fast sweeps and powered exits | 20 m/s approaches, progressive rear spin, retained front line and combined force budgets | Varied human trail braking and slide recovery |
| Braking/weight transfer | Independent brake inputs, useful deceleration and increased front load share | Hardware lever/trigger modulation |
| Terrain/material transitions | Actual rolling soil seams at 240/480 Hz, load/force continuity, transformed-track soil identity | Broader terrain/soil calibration |
| Suspension/rough terrain | Native constrained/free damper decay, drops, bumps, whoops, ruts and rebound; no delayed boot catapult | Repeated human pace/line variations |
| Takeoff and landing | 18 physical jump/runout combinations plus four from-rest powered two-tabletop approaches | Unscripted approach and recovery techniques |
| Air control and whips | Signed physical hip reaction, wheel/brake pitch behavior, 240/480 Hz three-axis correction, both actual big-jump whips and runout | Whip timing/style and control comfort |
| Scrubs | Matched neutral/lean-only/scrub whole-five-body COM takeoffs and ballistic momentum balance | Technique breadth on other jump profiles |
| Fair crashes | Actual berm/uphill support, banked vertical impacts, real sideways impacts, hard tilted impacts and body-only falls | Recovery from varied imperfect human landings |
| Rider/feet | Interruptible leg/posture changes, anchored hands/pegs, swept physical support endpoints and native rendering | Naturalness during a full riding session |
| Recovery/settings | Real crash/remount; held-input rearming; actual main-scene saved handling startup and malformed-file rejection | Windows save locations/device reconnect behavior |
| Full lap | Native controls-only bot from rest: all 14 gates plus finish, both big jumps, real manual shifts, no recovery | A human full lap and subjective riding acceptance |

Many controlled corner/air fixtures seed one coherent rolling state once. The main launch, new steering transitions, powered jump approaches and lap start from rest. No riding fixture continuously sets chassis transforms, replaces velocity, locks attitude or adds test-only grip. External test disturbances are identified separately.

The lap pilot has track-aware speed/line planning and high-frequency corrective inputs. Its pass is useful evidence of the available dynamics, not proof that an ordinary player can reproduce its skill. Synthetic controller events also do not create a connected hardware device; real selected-device polling still requires an Xbox controller.

## Measured riding results

These measurements come from the integrated 240 Hz release-physics run. Default neutral air damping and landing pitch-return stiffness are zero; landing rate assistance lasts 0.30 s. Tire coefficients and the 109 kg bike/78 kg rider masses were preserved.

| Scenario | Observation |
| --- | --- |
| Normal corners, left/right | 5° bank response 0.333/0.421 s; mean front slip 0.369/0.379°, rear 0.475/0.487°; no crash |
| Tight corners | Actual measured radius 6.18–6.22 m; controlled useful-speed turns in both directions |
| Fast sweeps | 5° bank response 0.383/0.488 s from 20 m/s approaches; mean axle slip below 0.33° |
| Hard corner exits | Final speed about 22.50 m/s; rear slip ratio about 0.285 versus about 0.010 in ordinary corners |
| Progressive brakes | 15→2.04 m/s in 5 s; front load share 0.470→0.687; maximum bank 5.15° |
| Unseeded abrupt transitions | 80 guards passed; response 0.142–0.288 s; final neutral mean bank 0.97–1.23°, late roll rate at most 0.030 rad/s |
| Actual big-jump whips | 33.9–40.6° peak yaw; loaded touchdown within 5.4° yaw and 1.5° bank; both ride beyond z=265 without crash |
| Full lap | 73.754 s, 891.119 m actual travel, all 14 gates plus finish; maximum bank 25.84°, minimum prepared-road clearance 2.868 m; 1.146/1.463 s large flights, six accepted manual shifts, no crash/recovery |

The 18 jump combinations cover 3.2/4.5 m tabletops, 20/21/22 m/s approaches and neutral/forward/slightly-back body preparation. The six back-position cases explicitly release throttle at the first positively loaded return; all original runout, clearance, travel, support and attitude guards remain. Maximum bank across those successful rides was 9.62°. A separate nineteenth ride intentionally holds backward body position and half throttle through a nose-up rear-first landing: it remains rear-only for 1.04 s, reaches about 80.9° world pitch and correctly loops out. The old long pitch spring hid that physically meaningful mistake.

Matched left/right scrubs reduced whole-assembly takeoff vertical speed by about 6.1/6.3%, rise by 11.7/12.1% and airtime by 6.6/6.9% relative to identical lean-only input. Forward speed remained available, and no unsupported tire force or downward flight impulse was added. The independent COM balance accounts for gravity and actual drag. See the generated scrub report for exact numbers and source hashes.

## Instrumentation and reproducibility

F8 displays speed, lean, steer, rates, each wheel's load/slip/compression/utilization, support, assistance and terrain-relative crash observations. Independent force capacities are included in F9 CSV capture. F9 starts/stops local CSV capture and displays its saved path. It does not switch controller ownership. Missing landing data stays empty.

The recorder samples the completed native solve before polling new player input. It records the separate effective packet used by the force loop, including crash gating. Tests distinguish the crash-triggering step, the following neutralized step and remount. A test-only observer after native node callbacks retains the exact 32-consecutive-frame integration guard; relying on a render-boundary wait had admitted an extra simulation step in the test.

```bash
bash standalone/tools/setup.sh
bash standalone/tools/check.sh
bash standalone/tools/godot.sh --headless --fixed-fps 240 --script res://tests/steering_transition_tests.gd
bash standalone/tools/godot.sh --headless --fixed-fps 480 --script res://tests/terrain_contact_tests.gd -- --hz=480
bash standalone/tools/godot.sh --headless --fixed-fps 240 --script res://tests/telemetry_recorder_tests.gd
```

Reports are generated under ignored `standalone/build/`; compare their source/config hashes. Match `--fixed-fps` and `-- --hz=` when a fixture changes physics frequency. Render-cadence tests deliberately vary rendering while retaining 240 Hz physics.

## Known failures and model limits

The required default workflow and optional engineering stresses are separate, with unchanged guards:

- The optional counter-rotation momentum-cancellation bench still fails three of 43 assertions: active angular drift 6.318%/0.739 N·m·s at 240 Hz, 3.403%/0.398 at 480 Hz; relaxed 240 Hz 4.372%/0.549. Its raw net-momentum bound is 2%. External air feedback is zero. The custom free-rotor solve plus native orientation/joint integration has finite-step error, magnified when opposing rotor/body momenta nearly cancel. The required coherent fixture's 43 guards pass; that does not erase this failure.
- The optional 120 Hz suspension experiment passed 416/426; coarse-step impact, sag and standing rough-ground limits still fail. Default gameplay targets 240 Hz. The guarded 426-check suspension runs pass at 240 and 480 Hz, and 30/240 render-FPS checks preserve native steps.
- Substantial walking-speed roll momentum can outrun the automatic dab. Faster leg extension did not solve the controlled falling cases and was rejected. Ordinary stop/launch/braking, parked bank support and moderate disturbance guards pass; every low-speed fall is not guaranteed recoverable.

Rigid rounded-cylinder tires, undeformed soil, approximate rear slider/linkage, local constrained-mass estimates and an aggregate rider torso remain model limitations. The coefficients are original engineering approximations. Active air and low-speed assistance are explicit gameplay torque budgets, not claims that a free rider creates external momentum. Multiplayer synchronization is absent.

Windows executable execution, physical Xbox input, subjective steering/air feel and an unscripted human motocross lap remain unverified on this Linux cloud machine. The game is not declared an exact replica or a completed commercial simulator because it compiles or passes a bot lap.
