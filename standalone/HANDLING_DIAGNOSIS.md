# v0.7.1: active-runtime diagnosis and focused ground correction

The player's report that v0.7 felt unchanged was not disproved by the earlier automated results. This follow-up audited the actual public download, proved a handling change through the real main scene, and repaired two reproduced low-speed failures. It does not establish that general cornering or airborne feel now matches MX Bikes, nor that the existing tire calibration is satisfactory to a human rider.

## What the previous release actually changed

The v0.6→v0.7 comparison is commit `8789895`→`04aaf63`. Its modified production physics files were `scripts/bike_controller.gd`, `scripts/wheel_body.gd`, `scripts/track_builder.gd`, `scripts/rider_input.gd`, `scripts/rider_visual.gd`, `physics/air_control.gd`, `physics/lean_control.gd`, `physics/suspension.gd`, `physics/tire.gd`, `physics/handling_setup.gd`, and `config/bike_250f.json`; `scripts/game.gd` connected saved settings and new diagnostics, and `scripts/telemetry_recorder.gd` was added. The other changes were regression tests, checks, version/build settings, documentation and Windows archives. `git show --stat 04aaf63` provides the complete 43-file list.

The meaningful changes were continuous road collision across materials, neutral steering/reference feedback, loaded-wheel damper mobility, boot deployment, terrain-relative crash observation, air hip-reaction sign and neutral air damping. However, the normal tire coefficients, brush/slip force curves, masses, suspension coefficients, drivetrain and held-input `LeanControl.target()` law remained the same. The earlier description overstated the evidence for a broad improvement in ordinary held-stick cornering. Passing the previous fixtures did not measure the player's experience.

## Confirmed runtime and possible masking paths

The public v0.7 versioned ZIP and generic alias were independently downloaded in full. Both matched the published 36,164,662-byte archive and SHA-256 `b090692fbf57c20a605a5c507ecd1826c9546c9218572ae73a26e457bc5240b8`. Its exact compiled project pack ran through the native Linux engine from an isolated directory, without using checkout source as a replacement. It reported v0.7.0, `virtual_rider`, the new crash helper, 0.30 s landing damping, zero landing pitch spring and zero neutral air damping. Real main-scene throttle/clutch input produced drivetrain torque, rear tire force and native acceleration. The public pack was current.

The Windows EXE is the official Godot runtime and is byte-identical in v0.6 and v0.7. Changed gameplay resides in the adjacent `DirtlineMX.pck`: v0.6 pack SHA-256 `dcdba82c…`, v0.7 `f3a6ed81…`. Updating only the EXE or opening an older extracted folder would retain the old game. The player's confirmation that the opening screen says v0.7.0 establishes their loaded game version, so an old v0.6 pack is not the explanation for this report.

The player kept saved settings. Two persistence paths matter:

- `game._load_preferences()` restores the separately saved riding mode; `_apply_preferences()` selects it on the real bike. Direct mode bypasses virtual lean steering and ground/air/landing assistance. Restoring handling defaults does not change that mode.
- `HandlingSetup.load_file()` overlays valid `handling.cfg` settings before bike construction. v0.6 accidentally ignored those saved values; v0.7 correctly applies them. Actual compiled-pack tests confirmed that an old custom lateral grip of 0.5 and assistance of 0 become active in v0.7. This is a possible difference in the player's effective setup, not proof of their particular values. All 28 persisted v0.6 **default** values match v0.7 defaults, so an old default setup alone does not undo the v0.7 corrections.

The existing F8 display now reports loaded game version, controller resource, riding mode, active input route, DEFAULTS/CUSTOM handling fingerprint, saved-load status, actual front/rear grip scales and input response. Startup prints a structured `PHYSICS_RUNTIME` receipt with the shipped JSON hash and default/effective setup hashes. Invalid saved data is explicitly distinguishable from absent settings. No saved bindings, camera choices or handling files are automatically erased or migrated.

Opening and applying the suspension menu also exposed a real setup mismatch: its 100 N·s/m compression step rounded the shipped 850 coefficient to 900. The step is now 50, representing the existing value exactly. An unchanged Apply and Restore→Apply retain every shipped front/rear coefficient and the same effective fingerprint. The physical damping defaults themselves were not changed.

## Exact active force path

`project.godot` selects `scenes/main.tscn`, whose script is `scripts/game.gd`. That script preloads one `scripts/bike_controller.gd` and constructs one `TestBike250F`. No alternate riding controller or duplicate steering/traction/suspension force loop was found.

1. `game._input()` dispatches command edges; `RiderInput.tick()` polls keyboard or the selected controller and builds `packet()`.
2. `game._physics_process()` sends that packet through `bike.set_controls()`.
3. `bike._physics_process()` creates the sanitized effective packet and calls rider, suspension, steering, assistance, drivetrain and tire functions once per native fixed step.
4. `_apply_steering()` applies equal/opposite torques across the actual fork/frame bearing. `_apply_drivetrain()` applies paired wheel/carrier impulses. `_apply_suspension()` applies internal strut force pairs. `_apply_tire()` calls `Tire.step()` and applies each patch force at its measured contact lever. Native Jolt contacts and joints then determine motion.
5. Wheel `_integrate_forces()` observes native contacts and solved support; native-body integration supplies the existing gyroscopic solve. Transform/velocity assignments belong to deliberate spawn/remount; visual and camera transforms do not drive the motorcycle.

The active tire load budget was independently checked against whole-five-body vertical momentum during actual launches and turns: maximum observed error was below 0.0034 N in those controlled flat-ground runs. Ordinary flat 2–6 m/s brake-in-turn probes had axle slip below 1.05°. These results do not justify increasing friction, and no tire coefficient or tire-force formula was changed in this patch.

## Proof that a handling parameter changes the running motorcycle

`tests/runtime_handling_path_tests.gd` instantiates the actual main scene and uses normal input actions, keyboard gear events and the real parked handling menu. It compares sensitivity 1.0→0.5→1.0 from repeated ordinary resets, recording effective controls, native bank, finite bar torque, independent axle forces and actual trajectory. It does not set riding velocity/orientation, drive a second controller, or substitute a tire model. The unsupported zero-sensitivity request is rejected without changing configuration. The restored comparison must recover the same effective configuration and repeat its measured response.

The 45-check native experiment passed. Each case observes exactly 2,160 completed physics steps over 9 s and reaches about 15.62 m/s, with no crash/recovery:

| Active sensitivity | Mean bank | Heading change | Mean front lateral force | Lateral travel |
| --- | ---: | ---: | ---: | ---: |
| Baseline 1.0 | 31.28° | 38.59° | 491 N | 14.43 m |
| Temporary 0.5 | 22.62° | 23.38° | 312 N | 9.82 m |
| Restored 1.0 | 31.42° | 38.68° | 494 N | 14.45 m |

The temporary menu parameter therefore changes actual motorcycle motion, beyond a displayed target or animation. Baseline/restored configuration hashes match. The temporary sensitivity change is confined to the fixture; shipped sensitivity remains 1.0, and fixture-owned saved data is restored. Reports are generated at `build/runtime-handling-path-*.json`.

## Two reproduced low-speed defects and their repairs

**Deferred boot activation was not idempotent.** `reset_bike()` safely placed support capsules at −0.62 m and queued their collision activation. Before the deferred change committed, the actual main input loop immediately called `set_controls()`, which called `_update_feet()` again. Reading the still-disabled shape incorrectly started a new deployment and retracted both boots to −0.10 m. The earlier banked parking fixture did not send that initial packet, so it missed this integration failure.

`_update_feet()` now tracks each foot's intended enabled state separately from delayed engine readback. Repeated packets retain the safe placement; an enable followed by a disable before commit queues the final intended state correctly. Reset clears this intent. On the identical 12° bank, the old immediate packet caused a fall and 1.466 m drift; the corrected packet preserves −0.62 m placement and approximately 814.7/983.8 N axle support without crashing. No upright constraint or extra balancing force was added.

An independent native review also passed six same-frame activation-flip/reset checks, confirming both collision shapes commit the last requested state rather than an earlier deferred enable.

**The feasible-bank envelope used a numerical speed floor as real motion.** `_apply_steering()` used `max(v², 2)` to calculate the lean sustainable at maximum steering. Near a stop, held input therefore still requested a nonzero bank even though centripetal support vanishes with speed. That same floor is useful in a feedback denominator to prevent division by zero, but is physically wrong in the feasible-bank calculation.

Only that feasible-bank numerator now uses actual forward speed squared. The separate feedback denominator remains bounded. Requested bank tends to zero naturally while braking; no new controller, stronger assist, additional tire force or transform correction was introduced. In a matched frozen-source comparison, both ±0.35-stick gentle braking stops previously low-sided around 8.3–8.5 s; the corrected envelope alone completed the 13 s observations at approximately ±1.5° bank without crashing. The final combined boot/envelope regression also reaches actual supported stops without crashing at 240 and 480 Hz. At 240 Hz the boots catch and retain approximately −9.2/+13.3° stopped bank; at 480 Hz the same recipes settle near ±0.02°. This difference is documented rather than described as an exact frame-rate match or automatic upright correction. Harder/brisker and larger-bank stops are not all rescued by the isolated envelope change; their final combined-patch behavior remains unverified.

A separate Xbox-reproducible protocol uses only light front brake (0.15), rear brake fully released, clutch pulled and ±0.35 steering through the stop. With the frozen v0.7 controller, the right case low-sides at 8.92 s and the left settles at −20.7° bank. The corrected controller completes both 13 s runs without crashing, at −2.78/+5.92° stopped bank and below 0.00025 m/s; all 12 physical guards pass. This makes a directly testable, limited handling improvement rather than relying on a grip multiplier or a controller parameter deliberately changed for the earlier reachability test. The separate diagnostic receipts are under `build/v8-human-stop/`.

## Release validation

The final `bash standalone/tools/package_windows.sh` workflow passed **5,474 required assertions across 43 suite invocations**, main-scene startup, Windows export, ZIP CRC and four-payload byte comparison. The repository's legacy Luau tests/analyzer/compiler and place verification also passed. The frozen controller is `c3a3d721…`, game `cb50c6fd…`, and unchanged JSON `a12c90e1…`.

The same 45-check main-scene A/B/A then passed again against the **exact exported PCK** in Godot 4.6.3, with an explicit packed-filesystem exclusion guard proving checkout test sources were unavailable. The external observer changes only report destinations and script-identity reporting for compiled resources. The release template does not expose the external-script tool option, so this automated packed proof uses the matching editor engine with `--main-pack`; rendered inspection separately uses the official release template beside that exact pack. Native window inspection confirmed v0.7.1, `virtual_rider`, `DEFAULTS #24eaac43`, scales 1.00/1.00, 0.070 s response, compression 850, identical setup fingerprint after Apply, helmet view and clean exit. Both completed without engine/script errors. This executes Linux engine builds, not the Windows PE or a physical controller.

```text
Windows ZIP: 36,167,450 bytes
SHA-256: db32b671103d2be15692cd38aee231c349220eb0d5b5751e705d3ba70f5a8f7a
Exported PCK: 232,044 bytes
SHA-256: aa5425d34f624bd450a779b37305b36236a878bb34713709fcf298fe0fe40195
```

Release receipts/screenshots are generated under ignored `build/pack-smoke-v071/`. Exact active controls, conditions, source identities and remaining unsupported stresses are distinguished from subjective riding acceptance.

## Changed files in this follow-up

| File | Important functions/change |
| --- | --- |
| `scripts/bike_controller.gd` | `_reset_models()`, `_update_feet()`: explicit pending activation intent; `_apply_steering()`: actual-speed feasible bank |
| `scripts/game.gd` | `_ready()`, `_refresh_runtime_identity()`, `get_runtime_receipt()`, `_physics_text()`: observation of loaded setup; refresh on existing settings Apply/mode paths; `_tuning_content()`: represent 850 exactly |
| `tests/runtime_handling_path_tests.gd` | Actual main-scene parameter A/B/A, restored settings and trajectory checks |
| `tests/runtime_identity_tests.gd` | Actual saved custom/direct/default/rejected paths; exact suspension menu Apply/Restore |
| `tests/ground_lifecycle_tests.gd` | Same-frame reset/input/enable edges and actual held-turn braking stops at 240/480 Hz |
| `tests/track_layout_tests.gd` | Observes the deliberate backward overturn's actual inverted body impact instead of requiring only one crash label |
| `tools/check.sh` | Integrates the new native tests into required release checks |
| `project.godot`, `export_presets.cfg`, `PLAYER_GUIDE.txt`, readmes/downloads | v0.7.1 identity, comparison instructions and matching Windows package |

The first broad validation run stopped at one of 190 track checks: all 18 successful jump/runout cases passed, but the deliberate backward-power crash used a different label. The full-context native trace showed 87.19° peak pitch and 1.1375 s rear-only support, followed by unsupported backward inversion and a real rider impact. At impact, chassis up projected −0.683 onto world up, forward projected −0.685 along the original approach, the rider had one native contact, and both tires were unloaded. The fallback was therefore a real powered overturn. The test now accepts that specific witnessed inverted body impact or the original loop-out result; peak-pitch/rear-support checks and every positive riding guard remain. The isolated rerun passed all 190 checks without changing production crash handling or the riding recipe.

## Next Windows/Xbox playtest

1. Extract the complete v0.7.1 ZIP into a new folder. Keep its EXE and PCK together. Verify v0.7.1 on the opening screen.
2. For the baseline comparison, select **Settings → Lean control / virtual rider**. While parked, use **Handling setup → Restore tested defaults → Apply and ride**. Existing controller bindings stay intact.
3. Press **F8**. Check `virtual_rider`, `DEFAULTS`, front/rear grip scale `1.00 / 1.00`, input response `0.070 s`, and the expected input route when using the controller. A `CUSTOM` receipt means effective handling/suspension still differs; it is useful evidence, not an error by itself.
4. On the flat straight, ride a slow gentle turn, about 10–12 km/h with modest stick input (roughly one-third to halfway). Pull **LB** to hold the clutch, leave **RB released**, apply light **LT** front braking (about 15–20%) and keep that turn input through the stop. Repeat left and right. Specifically assess whether bank unwinds as speed falls and whether support feet remain planted, rather than judging a large-jump or high-speed change from this patch. The separate native front-only comparison above was chosen because a digital RB button cannot reliably meter the 7.5% rear braking used in the original controlled fixture.
5. Try ordinary corners separately. If they still feel slippery/sluggish, report that directly with the F8 mode/setup information; this patch does not claim to have changed their tire calibration. F9 can capture the actual inputs, loads and slip for that case.

Cloud native execution and a measurable active-path change cannot certify subjective steering feel, Windows frame pacing or a physical Xbox controller. General tire/soil calibration, uphill stopping with lateral creep, stronger walking falls and demanding braking recoveries remain limits. Those cases must not be represented as fixed because the gentle controlled stop passes.
