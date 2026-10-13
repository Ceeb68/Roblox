# Dirtline MX

A standalone Windows motocross simulation prototype, built with Godot 4.6.3 and Jolt Physics. Start with one fictional 250cc four-stroke and a proving ground; handling quality comes before the bike collection or career.

![Dirtline MX physics prototype](downloads/DirtlineMX-preview.png)

## Play on Windows

1. [Download Dirtline MX for Windows](https://github.com/Ceeb68/Roblox/raw/refs/heads/main/downloads/DirtlineMX-Windows.zip).
2. Right-click the ZIP and choose **Extract All**.
3. Open the extracted folder and double-click **DirtlineMX.exe**. Keep its `.pck` file beside it.
4. The bike starts in neutral with the clutch pulled and feet down. Press **E** for first, hold **W** to build revs, then hold **B** to release the clutch gradually. Raise your feet with **F** once moving.

Use **H** for controls and **U** for suspension setup. Xbox-style controllers are supported. No Roblox installation or game editor is needed to play.

## First prototype

The proving ground has flat turns, berms, ruts, braking bumps, whoops, a tabletop, a large-jump lane and surface test pads. Native wheel bodies and mechanical suspension joints provide collision and support; custom tire and drivetrain models supply grip, slip, clutch, manual gears, braking and engine reactions. Steering, lean and rider positioning are separate inputs. Balance and landing orientation have no automatic correction.

This is an early physics prototype. Numerical and native-engine tests establish specific behaviors; they do not establish MX Bikes-level riding quality. Calibration, human obstacle acceptance, tire/soil detail and production art remain work in progress. Windows desktop execution must also be checked on a Windows PC; the cloud development machine runs Linux.

| Action | Keyboard |
| --- | --- |
| Throttle / front brake / rear brake | W / Space / S |
| Pull / release clutch | V / B; Shift quick pull |
| Shift down / up | Q / E |
| Steer / lean | A–D / Z–X |
| Rider forward–back / side | I–K / J–L |
| Standing / feet | C / F |
| Recover / engine starter | R / T |
| Help / suspension setup | H / U |

## Develop

```bash
cd /workspace/Roblox
bash standalone/tools/setup.sh
bash standalone/tools/check.sh
bash standalone/tools/export.sh
```

Open `standalone/project.godot` in Godot 4.6.3 to edit or ride. See [standalone documentation](standalone/README.md) for the physics architecture, controller mapping, build instructions and current validation.

The GitHub repository retains its original name. The new game lives entirely in `standalone/` and has no Roblox dependency. The earlier Roblox prototype is preserved in history and [legacy documentation](docs/ROBLOX_LEGACY.md).
