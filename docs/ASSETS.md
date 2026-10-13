# Motorcycle and rider asset pipeline

> This pipeline was written for the earlier Roblox prototype. Active source is now under [standalone](../standalone/README.md); the need for original production models, rider work and properly licensed audio remains.

The current DL-MX 250F uses procedural parts as a physics prototype. No production motorcycle mesh, licensed manufacturer branding, engine recording or finished rider animation has been imported.

For the first production bike, commission or license one coherent 250F mesh set with documented ownership/export rights. Original fictional branding avoids implying authorization from a motorcycle manufacturer. Keep a per-asset source/license record before upload to Roblox.

## Authoring contract

- Author at metre scale, with local forward -Z and up +Y, then export through a recorded metre-to-stud conversion of 1/0.28.
- Separate chassis, plastics, engine, tank, exhaust, bars, upper/lower fork, swingarm, wheels, number plates and cockpit pieces. Preserve pivots at each axle, steering axis, fork slide and swingarm hinge.
- Use named attachment positions for CG reference, wheel rays, rider seat/pegs/grips and suspension endpoints. Visual geometry must not silently alter configured mass or collision inertia.
- Cosmetic MeshParts are massless/noncolliding. Low-complexity collision geometry and explicitly calibrated chassis/ballast supply physics.
- Provide multiple detail levels and inspect texture memory/draw calls in Studio. Do not substitute a recolor for a distinct motorcycle model.
- Rider visuals need standing/seated transitions, hand/foot IK, body movement, crash/dismount and recovery; connect them to real simulation state. Whips/scrubs remain actual bike movement.

## Audio contract

Provide properly licensed original 250F idle, low/mid/high load and overrun loops, limiter/shift transients, brake/tire surface loops and impact sounds. Record sample metadata, loop points and attribution. Roblox asset IDs must be real uploaded/authorized values. Do not invent IDs or treat a missing sound as implemented.

The 125cc two-stroke and 450cc variants require independently verified geometry, rotor/torque data and appropriate recordings after the first bike passes handling acceptance. Research the current model catalog in Phase 5 with authoritative sources; no catalog has been verified during this physics phase.
