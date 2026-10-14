# Engine assessment

The camera occlusion query and virtual-rider steering references caused reproduced bugs in this game. The tire-load adapter also has backend-specific limitations. Changing engines does not replace these custom motorcycle systems. The isolated native benchmarks below found no evidence that Godot's built-in physics would, by itself, fix the unpredictable handling. A Unity or Unreal port has not been tested.

## Native backend comparison

Tested Godot **4.6.3-stable**, Jolt Physics and GodotPhysics3D, in separate projects at **240 Hz**, then repeated at **480 Hz**. These fixtures contain no game controller, custom tire forces, load estimator, raycast support or gyroscope correction. Both projects use identical masses, explicit inertias, force inputs, zero damping and zero surface friction. Jolt uses the game's cylinder-margin setting; Godot Physics does not implement rounded shape margins. Defaults for each backend's contact solver were retained.

The suspension fixture is an explicitly guided laboratory rig: a 50 kg frame, a 7.5 kg native cylinder wheel, a 4,500 N/m spring, a 600 Ns/m damper, and a 300 mm free suspension slider. Its mechanical linear guide isolates compression and is not a riding assistance system.

| Observation at 240 Hz | Jolt | Godot Physics |
| --- | ---: | ---: |
| Free wheel, mean resting centre above box | 335.00 mm | 325.00 mm |
| Free wheel, mean resting centre above triangulated mesh | 334.99 mm | 325.08 mm |
| Suspension, settled sag above box | 109.000 mm | 109.000 mm |
| Suspension, settled sag above mesh | 109.000 mm | 109.000 mm |
| Suspension, peak drop compression above box | 199.27 mm | 200.60 mm |
| Steering hinge, angle after 5 Nm / 0.3 s pulse | 28.250° | 28.250° |
| Steering hinge, maximum angle with 35° mechanical stop | 35.264° | 33.025° |
| Uncorrected free rotor, maximum world angular-momentum error over 0.5 s | 15.392% | 15.392% |

Analytic suspension sag is **109 mm**. Both backends reach it without imposed positions or velocities during the ride. All fixtures remain finite; the guided frame's maximum lateral error is below 0.002 mm. At 480 Hz both still settle to 109 mm, steering pulse angles converge to 28.449°, and the uncorrected rotor still has 15.393% momentum error. Consequently, the built-in backend does not remove the missing free-body precession demonstrated here.

The approximately 10 mm difference in resting wheel height is a backend contact/penetration result, not proof of a physically smaller wheel. Rounded margins, contact tolerances and joint-limit behavior need separate calibration for any backend switch. These simple fixtures do not establish which backend produces better complete motocross handling, and no full-game comparison is claimed.

### Reported impulses are a separate issue

Native support remained stable on both box and mesh, but summing the **reported** Jolt contact impulses across triangles inflated the inferred tire load:

| Reported mean normal load at 240 Hz | True static weight | Jolt box / mesh | Godot Physics box / mesh |
| --- | ---: | ---: | ---: |
| Free wheel | 73.575 N | 74.933 / 317.889 N | 73.575 / 73.575 N |
| Coupled suspension rig | 564.075 N | 574.486 / 3382.837 N | 564.075 / 564.075 N |

The Jolt mesh overcount is an observation/API limitation; these values are not additional native support forces. Official Godot documentation states that Jolt's exposed contact impulses are advance estimates and are accurate only when neither body is colliding with other bodies. The adapter source estimates responses independently per manifold with five iterations. The game therefore cannot treat an uncorrected sum as a reliable tire grip budget. Its completed-momentum load observer is intended to address this limitation, with explicit fallback near mechanical stops or invalid samples; this benchmark does not certify every fallback case.

## A targeted native improvement before a port

The bundled Jolt source has a native `mApplyGyroscopicForce` option, defaulting to false. A targeted engine-module change could enable and validate native gyroscopic integration instead of integrating it in the game's callbacks. Exposing the actual solved normal impulses would also remove the need to infer brush load from velocity changes. Jolt stores applied contact impulses internally, but Godot's public body-state API currently reports the estimate. Accessing solved data would require a deliberate engine/physics adapter change, not installing a ready-made motorcycle plugin. Neither change has been implemented or benchmarked here.

## Unity and Unreal

Unity is a plausible alternative for a later controlled prototype, but its standard `WheelCollider` is a raycast wheel with a spring/damper and slip-based friction. It does not supply motorcycle countersteering, a moving rider, physical whips or a validated two-wheel balance controller. Those systems would still need a custom implementation. NVIDIA's PhysX vehicle documentation explicitly separates vehicle modeling from the core rigid-body SDK; changing the rigid-body SDK does not automatically improve that model. The PhysX reference read here is version 4.1 and is not a claim about the exact SDK or vehicle package in a future Unity build.

Unreal/Chaos remains an untested alternative. Its official documentation was blocked by this environment's network proxy, so this assessment makes no verified claims about its current vehicle feature set or superiority. No Unity/Unreal installation, executable or EULA acceptance was attempted.

Before a complete port, build one bike and the same turn, release, rough-ground and airborne-control scenarios in the candidate engine. Compare native contact loads, joint response, angular momentum, input latency and human handling on the same Windows/controller hardware. Keep the current articulated rider and suspension requirements in that comparison.

## Sources and reproducibility

- [Godot 4.6: Jolt backend differences](https://github.com/godotengine/godot-docs/blob/4.6/tutorials/physics/using_jolt_physics.rst): joints, margins, penetration correction and estimated impulses. GitHub source read; the rendered docs host was blocked.
- [Godot 4.6.3 contact adapter](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/jolt_physics/spaces/jolt_contact_listener_3d.cpp): `EstimateCollisionResponse(..., 5)` per manifold.
- [Bundled Jolt body creation settings](https://github.com/godotengine/godot/blob/4.6.3-stable/thirdparty/jolt_physics/Jolt/Physics/Body/BodyCreationSettings.h): native gyro option.
- [Bundled Jolt contact constraint manager](https://github.com/godotengine/godot/blob/4.6.3-stable/thirdparty/jolt_physics/Jolt/Physics/Constraints/ContactConstraintManager.h): internal applied-impulse storage.
- [Unity reference source, pinned revision](https://github.com/Unity-Technologies/UnityCsReference/blob/5217f03a26ec2bffc0883fb4d2430100c5d2538c/Modules/Vehicles/Vehicles.bindings.cs): `WheelCollider` behavior and control surface. The rendered Unity docs host was blocked.
- [NVIDIA PhysX 4.1 vehicle documentation](https://github.com/NVIDIAGameWorks/PhysX/blob/4.1/physx/documentation/PhysXGuide/Manual/Vehicles.html): separate vehicle update, tire and suspension model.

Workspace-only bench scripts, complete observations and logs are in the ignored `standalone/build/engine-comparison/` directory. `jolt/` and `godot/` contain the 240 Hz projects; `jolt-480/` and `godot-480/` contain the timestep repeat. Each runs with `godot --headless --path <project> --fixed-fps <Hz> --script res://bench.gd`. These are six isolated observations per backend/timestep, not extra pass counts in the shipped game test suite.
