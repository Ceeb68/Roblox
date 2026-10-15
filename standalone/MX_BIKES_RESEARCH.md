# MX Bikes / MX Simulator reference and original handling research

MX Bikes is the experience target: a player commands the motorcycle and moves
the rider, while tire forces, weight transfer, steering and suspension determine
the result. Our gains, tire model, crash rules and procedural rider are our own
work. We have not obtained MX Bikes' proprietary simulation or animation code,
and do not claim to reproduce it exactly.

## What was actually read

On 14 October 2026 the official [MX Bikes overview](https://www.mx-bikes.com/?page=about) became accessible and was read. It describes a custom motorcycle-dynamics engine, setup options, an automotive-industry tire model, chassis flex, terrain deformation and wet terrain, alongside online racing. This identifies the depth of its public feature target. It does **not** publish its tire equations, steering/virtual-rider gains, airborne correction model, scrub implementation or animation transitions; those cannot be inferred from that page.

The earlier revision's requests to the overview had failed with proxy `403` responses. That older blanket access statement is superseded by the successful overview read. The [official FAQ page](https://www.mx-bikes.com/?page=about&section=faq) also loaded on this revision but contained no substantive FAQ entries in the returned page. The [PiBoSo wiki](https://docs.piboso.com/wiki/index.php/MX_Bikes) remained blocked at HTTPS CONNECT with `403 Forbidden`. The [MX Simulator manual](https://mxsimulator.com/manual.html) and [home page](https://mxsimulator.com/) likewise returned CONNECT `403`; they were not read. No specific MX Simulator controller algorithm or tuning value is attributed to them.

Our target qualities come from the user's requested behavior: planted ordinary corners, responsive countersteering, independent rider motion, real takeoff/landing interaction and meaningful controllable whips/scrubs. We did not inspect or copy either game's proprietary code, assets or physics engine. Matching those qualities is a design objective; exact replication is not claimed.

The accessible research source was Jason K. Moore's *Human Control of a Bicycle*,
a 2012 UC Davis mechanical engineering dissertation, read from the author's
GitHub repository. The following links pin the inspected revision
`685b5e84ce4b366f43b8cd9ea19d6b5de0e7ae1c`:

| Read source | Relevant finding | Consequence for this game |
| --- | --- | --- |
| [Control chapter](https://github.com/moorepants/dissertation/blob/685b5e84ce4b366f43b8cd9ea19d6b5de0e7ae1c/control.rst), literature review and Basic Control | Steering torque is the primary balance actuator. Roll angle and roll rate feedback have different effects. Moore's review of Ruijs and Pacejka's robotic motorcycle describes gains scheduled with speed and steering damping. | A virtual rider should exert bounded torque at the physical steering hinge. Tuning must cover low speed and changing speed, and should damp oscillation rather than force the chassis upright. These are general control principles, not MX Bikes settings. |
| [Control chapter](https://github.com/moorepants/dissertation/blob/685b5e84ce4b366f43b8cd9ea19d6b5de0e7ae1c/control.rst), Counter Steering | Initiating a turn can require initial steering opposite the turn, followed by steering into the turn as the vehicle rolls. Torque direction and handlebar angle need not match throughout a maneuver. | Lean intent should become a steering action; directly setting roll or immediately rotating the travel direction would remove the motorcycle's transient response. |
| [Model extensions](https://github.com/moorepants/dissertation/blob/685b5e84ce4b366f43b8cd9ea19d6b5de0e7ae1c/extensions.rst), Leaning rider extension | The reviewed models give body lean substantially less authority than steering torque. Rider flexibility changes stability modes; guaranteed hands-free stability does not follow from a rigid-rider model. | Meaningful body movement and weight transfer should supplement steering. Our aggregate rider mass/COM model remains an approximation; a visible pose change alone is not a complete rider dynamics model. |
| [Motion capture](https://github.com/moorepants/dissertation/blob/685b5e84ce4b366f43b8cd9ea19d6b5de0e7ae1c/motioncapture.rst), conclusions | Observed rider motion includes lean, bend, twist, bounce and knee movement, with more steering activity at low speeds. This work studies bicycling, including pedaling. | Articulate the rider at hips, shoulders, elbows and knees, keeping hands and boots attached to their supports. Motocross attack posture and terrain absorption are our design choices, not measured MX Bikes animation or directly validated by bicycle pedaling experiments. |

## Original handling choices and validation

The user selected lean control with a virtual rider and subsequently requested a roughly 75% simulation / 25% forgiveness philosophy, including mild low-speed and airborne assistance. The current implementation follows that newer direction. It does not treat that percentage as a physical formula or claim that either reference game uses the same assistance.

Grounded lean still goes through the existing finite physical steering bearing. The combined bike/rider bank request, actual rider COM, measured roll/rate, speed and load determine the response. A bounded roll-rate task improves deliberate transitions; a separate calm neutral task avoids chasing a new direction during release. Countersteering is actual wheel/fork movement, not a rotation assigned to the chassis. The small loaded low-speed balance torque is an explicit game aid, independently adjustable and disabled in direct mode.

The airborne task adds an explicitly external, bounded **rate-control** torque as the accessible part of the design. Separate pitch/roll/yaw and power budgets use the actual assembly inertia; native wheel gyros, rider counter-motion and drivetrain reactions remain. Neutral damping slows unintended rotation. Opposite input requests a return rate, without knowing the takeoff heading, world-up attitude or landing direction. This is not physically conserved angular momentum from a free rider alone. Zero-strength/direct/native-mechanics tests retain the unassisted dynamics and conservation checks separately. No extra translational flight force is used.

The scrub task prepares only on a positively loaded rising face with actual bank. A terrain-normal/edge lookahead recognizes the approaching crest so the physical leg absorption occurs near takeoff, rather than settling/rebounding early on the face. This is geometric observation, not jump-coordinate logic. It lowers the physical rider through the existing muscle target and increases passive suspension absorption. The airborne posture holds its last prepared state; the complete COM remains ballistic under gravity and measured aerodynamic drag. Matched takeoff tests compare lean alone with the same lean plus scrub so a cosmetic crouch cannot masquerade as trajectory reduction.

The front and rear use separately calibrated brush slopes and relaxation distances with a combined drive/brake/lateral grip ellipse. Ordinary response can become more planted without raising surface friction. These empirical knobby-tire coefficients are not a claim to use MX Bikes' publicly described automotive tire model. The game does not yet implement chassis flex, deformable soil or pneumatic tire carcasses.

The rider has an independent 78 kg native torso with bounded compliant support and common-point reaction pairs. Continuous visual pose/leg filters use its real motion and loaded turn state, with one inverse-kinematics solution per limb. This is a torso/muscle and procedural-limb approximation, not a full biomechanical model or a measured animation library.

The steady-turn relationship `tan(bank) = speed² / (gravity × radius)` is a basic force-balance check, not a full motorcycle model. Transients, steering geometry, rider inertia, separate tire load and suspension require native tests. [Current validation](VALIDATION.md) records stronger trajectory/slip/response checks, actual whip return, physical scrub comparisons and a controls-only full-track lap. Automated success establishes those recipes; human riding feel, Windows execution and controller hardware still need actual PC playtesting.
