# Dirtline MX

A standalone Windows motocross prototype built with Godot 4.6.3 and Jolt Physics. Version 0.7.1 fixes two reproduced low-speed defects: live input could retract pending support feet, and steering requested a nonzero bank at a stop. F8 now identifies the loaded build and effective handling setup. Air controls preserve neutral momentum, and landing assistance is a brief configurable rate catch. The 873 m circuit, physical rider, whips/scrubs, helmet view, automatic recovery and customizable controller bindings remain included.

![Dirtline MX physics prototype](downloads/DirtlineMX-preview.png)

## Play on Windows

1. [Download Dirtline MX v0.7.1 for Windows](https://github.com/Ceeb68/Roblox/raw/refs/heads/main/downloads/DirtlineMX-Windows-v0.7.1.zip).
2. Right-click the ZIP and choose **Extract All**.
3. Open the extracted folder and double-click **DirtlineMX.exe**. Keep its `.pck` file beside it.
4. The bike starts in neutral with the clutch pulled and feet down. Press **E** for first, hold **W** to build revs, then hold **B** to release the clutch gradually. Feet lift automatically during launch and plant when you stop.

Use **A/D** or the left stick to request bike lean; the virtual rider countersteers through the handlebars. **Z/X** moves the rider's upper body independently. In the air, use the left stick for roll and the right stick for pitch/yaw; counter-input returns a whip. Hold **F / controller X** while leaning on an ascending jump face to scrub. Use **M / controller B** for helmet view, **H** for help and **U** for suspension setup. Open **Escape / Start → Settings + controller binds → Controller bindings** to customize controls. No Roblox installation or game editor is needed to play.

If you previously selected manual handlebars, choose **Virtual rider** in Settings to use lean control. Park and use **Handling setup → Restore tested defaults → Apply and ride** to compare the shipped setup; saved tuning now survives restarting correctly. **F8** displays physics telemetry and **F9** records a local CSV.

For this comparison, F8 should identify **v0.7.1**, **virtual_rider**, **DEFAULTS**, front/rear grip scales **1.00 / 1.00**, and input response **0.070 s**. Extract the complete update into a new folder: the matching `.pck` contains the changed game. [The runtime diagnosis](standalone/HANDLING_DIAGNOSIS.md) explains what was proved and the limited scope of this correction.

After a crash, bike and rider remount automatically after **one second** near the crash site. **R / controller Y** remounts immediately. Recovery resets the rider's physical and visible pose, selects neutral, plants feet and clears movement; release any held controls before using them again. Unsafe ground falls back to the lab spawn.

## First prototype

![The extended Dirtline MX circuit](downloads/DirtlineMX-course.png)

The 873 m proving circuit has a 40 m flat launch, a separate 100 m practice straight, berms, ruts, bumps, whoops, and 3.2 m and 4.5 m tabletops. Five independent native bodies model the frame, rider, fork and wheels. Custom tire/drivetrain models supply grip, slip, clutch, manual gears, braking and engine reactions. Default virtual-rider handling adds bounded low-speed balance and airborne rotation assistance to the physical simulation. It never assigns the bike's pose or chooses a landing heading. Fully manual handlebars remain selectable.

This is an early physics prototype. Numerical and native-engine tests establish specific behaviors; they do not establish MX Bikes-level riding quality. Calibration, human obstacle acceptance, tire/soil detail and production art remain work in progress. Windows desktop execution must also be checked on a Windows PC; the cloud development machine runs Linux.

[Research notes](standalone/MX_BIKES_RESEARCH.md) distinguish published vehicle-dynamics findings from our original game-assistance choices. [The engineering report](standalone/PHYSICS_OVERHAUL.md) explains the measured root causes and implemented changes. [Handling validation](standalone/VALIDATION.md) records actual native riding tests and their limits. No proprietary MX Bikes or MX Simulator code, physics engine or assets are used.

| Action | Keyboard |
| --- | --- |
| Throttle / front brake / rear brake | W / Space / S |
| Pull / release clutch | V / B; Shift quick pull |
| Shift down / up | Q / E |
| Bike lean command / rider lean | A–D / Z–X |
| Rider forward–back / side | I–K / J–L |
| Standing / seated | C |
| Scrub on an ascending jump face | Hold F; controller X |
| Recover / engine starter | R / T |
| Help / suspension setup | H / U |
| Chase / first-person camera | M; controller B / Circle |

## Develop

```bash
cd /workspace/Roblox
bash standalone/tools/setup.sh
bash standalone/tools/check.sh
bash standalone/tools/export.sh
```

Open `standalone/project.godot` in Godot 4.6.3 to edit or ride. See [standalone documentation](standalone/README.md) for the physics architecture, controller mapping, build instructions and current validation.

The GitHub repository retains its original name. The new game lives entirely in `standalone/` and has no Roblox dependency. The earlier Roblox prototype is preserved in history and [legacy documentation](docs/ROBLOX_LEGACY.md).
