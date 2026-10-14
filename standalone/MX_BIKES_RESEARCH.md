# MX Bikes reference and balance research

MX Bikes is the experience target: a player commands the motorcycle and moves
the rider, while tire forces, weight transfer, steering and suspension determine
the result. Our gains, tire model, crash rules and procedural rider are our own
work. We have not obtained MX Bikes' proprietary simulation or animation code,
and do not claim to reproduce it exactly.

## What could actually be studied

Requests to the official [MX Bikes about page](https://www.mx-bikes.com/?page=about),
[downloads page](https://www.mx-bikes.com/?page=downloads),
[PiBoSo MX Bikes wiki](https://docs.piboso.com/wiki/index.php/MX_Bikes) and
[official forum](https://forum.mx-bikes.com/) failed at the cloud proxy's HTTPS
CONNECT step with `403 Forbidden`. A later wiki retry returned the same result.
These pages were **not read**. Therefore this revision does not attribute specific
default input filters, automatic rider movement, steering gains, low-speed
behavior or crash thresholds to MX Bikes. Official-domain additions were saved
to the environment draft for future access; a draft save does not apply them to
the running machine.

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

## Handling choices and validation

The user explicitly selected lean control with a virtual rider. That authorizes
a physical rider controller; the direct handlebar mode remains separate.

The revision targets abrupt input reversals, short front/rear contact losses and
small disturbances. Contact confidence and bank-intent filtering are engineering
choices for our native Jolt model. They must not create tire traction when a wheel
has no contact. Fully airborne motion must remain ballistic, without an automatic
landing or upright torque. Grip limits must still permit slides and genuine falls.

Our native traces also exposed an invalid use of the two-patch steering model
while only the rear wheel supported the bike. Steering an unsupported front wheel
cannot generate the assumed ground curvature, but it can generate real gyroscopic
reactions. The revision uses bounded joint-local bar grip in that situation and
in flight. Its inputs are fork angle/rate and the player's bar request, without
world-attitude feedback. Front-loaded bracing moves the existing simulated rider
through finite articulation; manual positioning remains the posture baseline.
These are our model choices, not verified MX Bikes behavior. Native comparisons
then showed that the aggregate rider approximation was too rigid over whoops.
The revision gives the rider its own 78 kg rigid body, with bounded compliant
leg forces and torso torque paired at the same world contact point with the
frame. Frame/rider inertias stay fixed; body motion now exchanges real momentum.
This is a rigid torso and muscle/leg approximation, not a complete human skeleton.

Steady turns alone cannot validate these choices. Useful native scenarios include
short steer pulses and reversals, release from moderate lean, braking while
banked, small rough-ground disturbances, one-wheel unloading, and grip changes.
Existing unsupported-balance, airborne and real crash checks must continue to
pass. Native automated checks cannot establish that the riding feel matches MX
Bikes; Windows playtesting with a real controller remains necessary.

The normal steady-turn relationship `tan(bank) = speed² / (gravity × radius)`
is a basic force-balance check, not a complete motorcycle model. Transients,
steering geometry, rider inertia, independent tire load and suspension response
need separate checks. Our empirical tires, inferred contact loads, simplified
physical rider and static terrain remain material limits. Tire loads are inferred
from completed native wheel momentum along the free suspension axis; explicit
collision-estimate fallbacks cover mechanical stops and missing/singular samples.
