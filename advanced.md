# Advanced plugin (`advanced.lua`)

## What it is
Four utilities in one tab: a **Radar/minimap** (team-coloured dots, rotated to your view), **Movement** (bunny-hop + infinite jump), **Persistence** (re-inject the script across teleports), and an **Auto-Soften** director (dials aggressive settings into safe ranges when Phantom Recon has flagged an anti-cheat).

## How to use
Plugins tab → **Enable Advanced** → an "Advanced" tab appears:
- **Radar:** Enable + Range + Size. Dots use Enemy/Ally colours.
- **Movement:** Bunny Hop (hold Space), Infinite Jump.
- **Persistence:** set Loader URL → Re-inject on Teleport / Arm Now.
- **Auto-Soften:** Auto-Soften on AC (reads `Bridge.DeepScan.acActive`).

## How it works
- Radar: world-relative player positions rotated by camera yaw, drawn as GUI dots in a corner ScreenGui; colour via `Bridge.relationshipColor`.
- Movement: `Humanoid.Jump` on landing / `Humanoid:ChangeState(Jumping)` mid-air.
- Persistence: `queue_on_teleport("loadstring(game:HttpGet(url))()")`.
- Auto-Soften: when `Bridge.DeepScan.acActive`, sets safer Options/Toggles values.

## Dependencies / requires
Globals + `getgenv().CryptsHBE` (Bridge) for `relationshipColor`/`getSafeGuiParent`/`DeepScan`. `queue_on_teleport` optional (persistence). The `ctx` sandbox.

## Teardown
`ctx` disconnects all loops and destroys the radar ScreenGui (which removes its dots). Control keys cleared. Movement/persistence leave no residue.

## Confidence / limits
Radar/movement: high. Radar orientation (forward = up) may need a sign flip — verify in-game. Persistence needs a valid Loader URL. Auto-Soften only acts after a Phantom Probe has run with an AC detected.
