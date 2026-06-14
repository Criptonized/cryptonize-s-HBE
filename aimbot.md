# Aimbot plugin (`aimbot.lua`)

## What it is
Hook-free gun assist: a **camera aimbot** (pulls the camera toward the target — not silent aim), a **triggerbot** (raycast the crosshair, auto-click on an enemy), and **no-recoil** (zeroes detected recoil/spread values on the held gun). Includes a **ballistic resolver** (lead by velocity × bullet-travel-time + gravity drop).

## How to use
Plugins tab → set the **Plugin Base URL** to your raw GitHub folder → **Enable Aimbot**. An "Aimbot" tab appears:
- **Aimbot:** Enable, Activate (Hold Right Mouse / Hold Key / Always), Aim Key, Target Part, FOV, Smoothness, Visible Only, Ballistic Prediction + Bullet Speed + Gravity Drop, Ignore Team/Whitelisted, Show FOV Circle.
- **Triggerbot:** Enable, Activate, Trigger Key, Delay, Ignore Team.
- **No-Recoil:** Enable (+ a detected-value count).

## How it works
- Aimbot/triggerbot: `Camera:WorldToViewportPoint`, `ViewportPointToRay`, `Workspace:Raycast`, `mouse1click`, `UserInputService:IsKeyDown/IsMouseButtonPressed`. Aim = `cam.CFrame:Lerp(CFrame.lookAt(...), smooth)`.
- No-recoil: scans the held Tool for NumberValues named recoil/spread/kick/bloom/sway, stores originals, zeroes them; restores on unload.
- **No hooks** (honors core rule #3). It moves the camera; true silent aim would need a namecall hook.

## Dependencies / requires
Globals: `Toggles`, `Options`, `Library`, `getgenv().DrawingFallback`. Optional executor: `mouse1click` (triggerbot). The `ctx` sandbox (Connect/Groupbox/Control/Track) from the core.

## Teardown
`ctx` auto-disconnects the RenderStepped/Heartbeat loops and destroys the FOV ring; `unload()` restores any zeroed recoil values. Control keys are cleared.

## Confidence / limits
Camera aimbot + triggerbot: high (reliable APIs). No-recoil: medium — game-specific (only works if recoil is a client-side value; the count + F10's gun line tell you). Untested in any specific game.
