# Dirtline MX

A Roblox arcade motocross starter: ride an orange dirt bike around a winding dirt circuit, jump the tabletops, clear numbered gates, and beat your lap time. The track and motorcycles are built from Roblox parts, with no paid assets or external game services.

## Play in Roblox Studio

1. On this GitHub repository, choose **Code → Download ZIP** and extract the ZIP on your Windows PC or Mac.
2. Install **Roblox Studio** from [Roblox Creator Hub](https://create.roblox.com/) if needed.
3. In Studio, choose **File → Open from File** and open `DirtlineMX.rbxlx` from the extracted folder.
4. Press **Play**.

You spawn on your own bike behind the start line. Cross START / FINISH to start a timed lap, pass every gate in order, then cross the finish to complete it. Riding backward through a gate does not count.

The root `DirtlineMX.rbxlx` is the downloadable starter build. Source changes are rebuilt into `build/DirtlineMX.rbxlx` by the development checks below; open that generated file when testing changes.

| Control | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- |
| Accelerate / reverse | W / S or up / down | Right trigger / X | Onscreen controls |
| Steer | A / D or left / right | Left stick | Onscreen controls |
| Brake | Space | Left trigger | Onscreen brake |
| Return to start | R | Y | Reset button |

Brake before tight bends. Resetting abandons the current lap but retains your best completed lap and lap count for this server session. Times are not saved after leaving the server.

## Cloud development

The cloud machine supports source editing, race-rule tests, place builds, and Rojo synchronization. Roblox Studio and the Roblox engine do not run in this Linux environment; bike handling and multiplayer behavior still need the Studio checks below.

```bash
cd /workspace/Roblox
bash scripts/setup-tools.sh
bash scripts/check.sh
```

The setup pins Rojo **7.7.1** and Luau **0.742**, installs them in `/workspace/.roblox-tools/bin`, and verifies official release archive SHA-256 digests. Run `bash scripts/check.sh` after changing the source. It tests lap/checkpoint rules, analyzes the pure rules module, compiles all Luau, builds the place, and checks that the actual game scripts are included. Generated files live in ignored `build/`.

For live editing, run `bash scripts/dev.sh`, then connect the matching Rojo plugin in Studio to port **34872** through a supported connection to the development machine. Opening the built place directly works without the plugin. This cloud onboarding interface does not provide a browser game preview.

## Studio playtest checklist

1. Play once; confirm the player is seated on an upright bike and W/A/S/D steer, accelerate, reverse, and brake.
2. Cross the starting gate, complete the numbered circuit, and check that the lap counter and best time update. Skip a gate and verify the lap does not complete.
3. Ride over all jumps and confirm landing stays controllable. Test R after dismounting or getting stuck.
4. Use Studio's two-player server test. Each rider should control only their own bike and receive their own lap times. Check the server and client Output for errors.
5. Use the device emulator and a gamepad to check HUD sizing and touch/gamepad controls.

## Source layout

- `src/server/Bikes.luau`: bike construction, rider ownership and arcade physics.
- `src/server/Track.luau`: circuit, jumps, checkpoint gates and scenery.
- `src/server/main.server.luau`: player lifecycle, authoritative racing and snapshots.
- `src/client/main.client.luau`: race HUD and controls.
- `src/shared/RaceRules.luau`: engine-independent lap and gate rules.

The server owns bike physics and computes gate crossings and lap times. Clients send bounded control requests, not checkpoint progress or lap results. This is a starter, with no monetization or persistent player data. To publish, open the built place in Studio and use **File → Publish to Roblox** after playtesting.
