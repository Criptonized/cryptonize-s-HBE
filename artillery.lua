-- CryptsHBE plugin: Artillery  (Pordier at War siege-gun assist)
-- ============================================================================
-- For the WW1 framework whose artillery/siege-mortar emplacements expose an
-- ArtilleryStats folder (Angle, Elevation, ShootDelay, ServerLastShotTime,
-- TargetPos) + an ArtilleryEvents folder (Mount/Rotate/Elevate/Shoot/Rope).
-- (Deep-dump confirmed: Workspace...Artillery / Trenches...SiegeMortar.)
--
-- THE WIN -- the game itself computes ArtilleryStats.TargetPos (the shell's
-- landing point), so we can draw the impact marker + a white scatter-radius
-- circle + an overhead "view target" camera PURELY READ-ONLY -- no writes, no
-- remotes, nothing detectable. You see exactly where the shell lands and can
-- walk the radius onto a target.
--
-- BEST-EFFORT (server-gated, labelled) -- ShootDelay (=8.5s) + ServerLastShotTime
-- are owned by the server-side ArtilleryServer Script, so faster fire is NOT
-- guaranteed. Auto-Shoot fires the emplacement's own Shoot remote at your chosen
-- rate and the readout watches ServerLastShotTime to tell you if the server
-- ACTUALLY accepted the extra shots (accepted/sec). If it stays at ~1 per 8.5s,
-- the server is enforcing the cooldown and nothing client-side will change it.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local lPlayer = Players.LocalPlayer
local DrawingFallback = getgenv().DrawingFallback

local pluginCleanup = nil

-- Climb from the seat we're sitting on to the emplacement model.
local function findControlledArtillery()
	local char = lPlayer.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat then return nil end
	local node = seat.Parent
	while node and node ~= Workspace do
		if node:FindFirstChild("ArtilleryStats") and node:FindFirstChild("ArtilleryEvents") then return node end
		node = node.Parent
	end
	return nil
end

local function numVal(folder, name)
	local v = folder and folder:FindFirstChild(name)
	if v then local ok, n = pcall(function() return v.Value end) if ok and type(n) == "number" then return n end end
	return nil
end

return {
	name = "Artillery", tab = "Artillery", requires = {},
	load = function(ctx)
		local function C(k) ctx:Control(k) end

		local gVis = ctx:Groupbox("Trajectory", "left")
		gVis:AddToggle("artTrajectory", { Text = "Show Landing", Default = true, Tooltip = "Read-only: marks ArtilleryStats.TargetPos (where the shell lands) + a scatter circle. (Default: ON)" }); C("artTrajectory")
		gVis:AddToggle("artAimRing", { Text = "Aim Ring (where you look)", Default = false, Tooltip = "Draw the scatter ring at the terrain point your CAMERA is aimed at (raycast) instead of the game's TargetPos -- so it shows live as you turn, even with no TargetPos yet. (Default: OFF)" }); C("artAimRing")
		gVis:AddSlider("artScatterRadius", { Text = "Scatter Radius", Min = 1, Max = 120, Default = 24, Rounding = 0, Tooltip = "Studs. The shell isn't pinpoint -- set this to match the spread you observe, so the white circle = the danger zone." }); C("artScatterRadius")
		gVis:AddToggle("artArc", { Text = "Show Arc (approx)", Default = false, Tooltip = "Draws an approximate shell path from the muzzle to the landing point. Cosmetic -- the landing point is the accurate part. (Default: OFF)" }); C("artArc")

		local gCam = ctx:Groupbox("Target Camera", "left")
		gCam:AddToggle("artTargetCam", { Text = "View Target", Default = false, Tooltip = "Move the camera over the landing point so you watch the impact area while you aim (W/S/A/D still aim the gun). (Default: OFF)" }); C("artTargetCam")
		gCam:AddSlider("artCamHeight", { Text = "Cam Height", Min = 10, Max = 400, Default = 90, Rounding = 0, Tooltip = "Studs above the landing point." }); C("artCamHeight")
		gCam:AddSlider("artCamBack", { Text = "Cam Pullback", Min = 0, Max = 250, Default = 60, Rounding = 0, Tooltip = "Studs back toward the gun (0 = straight down)." }); C("artCamBack")

		local gFire = ctx:Groupbox("Rate of Fire (server-gated)", "right")
		gFire:AddToggle("artAutoShoot", { Text = "Auto-Shoot", Default = false, Tooltip = "Fires this emplacement's Shoot remote at the rate below. Works ONLY if the server doesn't enforce the cooldown -- watch 'Accepted'. (Default: OFF)" }); C("artAutoShoot")
		gFire:AddSlider("artShootRate", { Text = "Shots / sec", Min = 1, Max = 20, Default = 4, Rounding = 1 }); C("artShootRate")
		gFire:AddToggle("artDelayOverride", { Text = "Override ShootDelay", Default = false, Tooltip = "Also writes ArtilleryStats.ShootDelay low (likely server-ignored, but cheap to try). (Default: OFF)" }); C("artDelayOverride")
		gFire:AddSlider("artDelayValue", { Text = "ShootDelay", Min = 0, Max = 8, Default = 0.25, Rounding = 2 }); C("artDelayValue")

		local gRange = ctx:Groupbox("Range / Turret (best-effort)", "left")
		gRange:AddToggle("artElevOverride", { Text = "Elevation Override", Default = false, Tooltip = "Add to the gun's Elevation to push past the aim cap for more range. Server\nmay re-clamp it -- watch the readout's stuck/reverted. (Default: OFF)" }); C("artElevOverride")
		gRange:AddSlider("artElevExtra", { Text = "Extra Elevation (rad)", Min = -2, Max = 2, Default = 0.3, Rounding = 2, Tooltip = "Added to the captured Elevation. Positive usually = aim higher = more range." }); C("artElevExtra")
		gRange:AddToggle("artInfTurret", { Text = "Inf Turret Ammo", Default = false, Tooltip = "Hold any ammo/shell/round value on this emplacement at max (separate from the\ngun Inf Ammo, so it doesn't touch your working one). (Default: OFF)" }); C("artInfTurret")

		local gInfo = ctx:Groupbox("Readout", "right")
		local lblState = gInfo:AddLabel("State: not mounted", true)
		local lblStats = gInfo:AddLabel("Stats: -", true)
		local lblFire = gInfo:AddLabel("Accepted: -", true)
		local lblRange = gInfo:AddLabel("Range/Turret: -", true)

		-- drawing pools (all GUI-fallback; tracked so unload frees them)
		local RING_N = 36
		local ringLines = {}
		for i = 1, RING_N do
			local ln = ctx:Track(DrawingFallback.new("Line"))
			ln.Thickness = 2; ln.Color = Color3.fromRGB(255, 255, 255); ln.Visible = false
			ringLines[i] = ln
		end
		local ARC_N = 22
		local arcLines = {}
		for i = 1, ARC_N do
			local ln = ctx:Track(DrawingFallback.new("Line"))
			ln.Thickness = 2; ln.Color = Color3.fromRGB(255, 220, 80); ln.Visible = false
			arcLines[i] = ln
		end
		local marker = ctx:Track(DrawingFallback.new("Circle"))
		marker.Thickness = 2; marker.Filled = false; marker.Color = Color3.fromRGB(255, 70, 70); marker.Radius = 5; marker.Visible = false
		local crossH = ctx:Track(DrawingFallback.new("Line")); crossH.Thickness = 2; crossH.Color = Color3.fromRGB(255, 70, 70); crossH.Visible = false
		local crossV = ctx:Track(DrawingFallback.new("Line")); crossV.Thickness = 2; crossV.Color = Color3.fromRGB(255, 70, 70); crossV.Visible = false
		local mkText = ctx:Track(DrawingFallback.new("Text")); mkText.Color = Color3.fromRGB(255, 200, 200); mkText.Size = 14; mkText.Center = true; mkText.Outline = true; mkText.Visible = false

		local function hideAllDraw()
			for _, ln in ipairs(ringLines) do ln.Visible = false end
			for _, ln in ipairs(arcLines) do ln.Visible = false end
			marker.Visible = false; crossH.Visible = false; crossV.Visible = false; mkText.Visible = false
		end

		-- camera + fire state
		local camActive = false
		local origDelay, delayArt = nil, nil   -- captured ShootDelay + which artillery it belongs to
		local lastShootAt = 0
		local prevServerShot, accepted, lastAcceptTick, acceptRate = nil, 0, 0, 0
		-- trajectory / camera smoothing state
		local ringLastCompute, ringWorld = 0, {}
		local camSmooth = nil
		local artHpCache = {}   -- shell-impact hit-marker detection
		-- range / turret state
		local elevBase, elevArt, prevElevOv = nil, nil, false
		local turretFields, turretArt = {}, nil
		local function restoreTurret()
			for _, t in ipairs(turretFields) do pcall(function() t.v.Value = t.orig end) end
			turretFields, turretArt = {}, nil
		end
		local function findTurretAmmo(art)
			local out = {}
			pcall(function()
				for _, d in ipairs(art:GetDescendants()) do
					if (d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue")) then
						local n = d.Name:lower()
						if n:find("ammo") or n:find("shell") or n:find("round") or n:find("magazine") or n:find("rocket") or n:find("missile") then
							out[#out + 1] = { v = d, orig = d.Value }
						end
					end
				end
			end)
			return out
		end

		local function restoreCamera()
			if camActive then
				local cam = Workspace.CurrentCamera
				pcall(function()
					cam.CameraType = Enum.CameraType.Custom
					local hum = lPlayer.Character and lPlayer.Character:FindFirstChildOfClass("Humanoid")
					if hum then cam.CameraSubject = hum end
				end)
				camActive = false
			end
		end
		local function restoreDelay()
			if delayArt and origDelay ~= nil then
				local s = delayArt:FindFirstChild("ArtilleryStats")
				local sd = s and s:FindFirstChild("ShootDelay")
				if sd then pcall(function() sd.Value = origDelay end) end
			end
			origDelay, delayArt = nil, nil
		end

		local function aimOrTarget(cam, art, targetPos)
			-- "Aim Ring": raycast from the camera along where you LOOK to the terrain and use
			-- that as the ring centre, so the landing radius follows your view live (works even
			-- before the game computes TargetPos). Otherwise the real ArtilleryStats.TargetPos.
			if Toggles.artAimRing and Toggles.artAimRing.Value and cam then
				local rpAim = RaycastParams.new()
				rpAim.FilterType = Enum.RaycastFilterType.Exclude
				pcall(function() rpAim.FilterDescendantsInstances = { lPlayer.Character, art } end)
				local hitAim = Workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 6000, rpAim)
				if hitAim then return hitAim.Position end
			end
			return targetPos
		end
		local function toScreen(cam, world)
			local sp = cam:WorldToViewportPoint(world)
			return Vector2.new(sp.X, sp.Y), sp.Z > 0
		end

		ctx:Connect(RunService.RenderStepped, function()
			local tnow = tick()
			local cam = Workspace.CurrentCamera
			local art = findControlledArtillery()
			if not art then
				hideAllDraw(); restoreCamera()
				if delayArt then restoreDelay() end
				if turretArt then restoreTurret() end
				elevBase, elevArt = nil, nil
				prevServerShot = nil
				pcall(function() lblState:SetText("State: not mounted (sit at an artillery/siege mortar)") end)
				pcall(function() lblStats:SetText("Stats: -") end)
				pcall(function() lblFire:SetText("Accepted: -") end)
				pcall(function() lblRange:SetText("Range/Turret: -") end)
				return
			end
			local stats = art:FindFirstChild("ArtilleryStats")
			local events = art:FindFirstChild("ArtilleryEvents")
			local tpv = stats and stats:FindFirstChild("TargetPos")
			local targetPos = tpv and tpv.Value or nil
			local angle = numVal(stats, "Angle")
			local elevation = numVal(stats, "Elevation")
			local shootDelay = numVal(stats, "ShootDelay")

			pcall(function() lblState:SetText("State: MOUNTED -> " .. art.Name) end)
			pcall(function()
				lblStats:SetText(("Stats: Elev %.2f  Angle %.2f  Delay %.2f%s"):format(
					elevation or 0, angle or 0, shootDelay or 0,
					targetPos and ("\nTarget %d,%d,%d"):format(targetPos.X, targetPos.Y, targetPos.Z) or "\nTarget: (none yet)"))
			end)

			-- ===== trajectory visuals (read-only) =====
			local ringCenter = aimOrTarget(cam, art, targetPos)
			if Toggles.artTrajectory.Value and ringCenter then
				local R = Options.artScatterRadius.Value
				-- Recompute ground-conformed ring points at ~10Hz (raycast straight down per
				-- point so the circle sits on terrain instead of floating at the target's Y),
				-- then project every frame (cheap). Fixes the "janky, not on the ground" look.
				if tnow - ringLastCompute > 0.1 then
					ringLastCompute = tnow
					local rp = RaycastParams.new()
					rp.FilterType = Enum.RaycastFilterType.Exclude
					pcall(function() rp.FilterDescendantsInstances = { lPlayer.Character, art } end)
					for i = 0, RING_N do
						local a = (i % RING_N) / RING_N * math.pi * 2
						local x, z = ringCenter.X + math.cos(a) * R, ringCenter.Z + math.sin(a) * R
						local hit = Workspace:Raycast(Vector3.new(x, ringCenter.Y + 80, z), Vector3.new(0, -400, 0), rp)
						ringWorld[i + 1] = Vector3.new(x, (hit and hit.Position.Y or ringCenter.Y) + 0.2, z)
					end
				end
				-- scatter ring (perspective-correct ground circle)
				local pts, on = {}, {}
				for i = 0, RING_N do
					local s, vis = toScreen(cam, ringWorld[i + 1] or ringCenter)
					pts[i + 1] = s; on[i + 1] = vis
				end
				for i = 1, RING_N do
					local ln = ringLines[i]
					if on[i] and on[i + 1] then
						ln.From = pts[i]; ln.To = pts[i + 1]; ln.Visible = true
					else
						ln.Visible = false
					end
				end
				-- centre marker + cross + distance text
				local sc, visc = toScreen(cam, ringCenter)
				if visc then
					marker.Position = sc; marker.Visible = true
					crossH.From = sc - Vector2.new(9, 0); crossH.To = sc + Vector2.new(9, 0); crossH.Visible = true
					crossV.From = sc - Vector2.new(0, 9); crossV.To = sc + Vector2.new(0, 9); crossV.Visible = true
					local root = art:FindFirstChild("Root") or art:FindFirstChild("Muzzle", true)
					local dist = root and (ringCenter - root.Position).Magnitude or 0
					mkText.Text = ((Toggles.artAimRing and Toggles.artAimRing.Value) and "AIM  %dm" or "IMPACT  %dm"):format(dist)
					mkText.Position = sc + Vector2.new(0, 16); mkText.Visible = true
				else
					marker.Visible = false; crossH.Visible = false; crossV.Visible = false; mkText.Visible = false
				end
			else
				for _, ln in ipairs(ringLines) do ln.Visible = false end
				marker.Visible = false; crossH.Visible = false; crossV.Visible = false; mkText.Visible = false
			end

			-- ===== arc (approx) =====
			if Toggles.artArc.Value and targetPos then
				local muzzle = art:FindFirstChild("Muzzle", true)
				local A = muzzle and muzzle.Position or nil
				if A then
					local B = targetPos
					local dist = (B - A).Magnitude
					local h = math.clamp(dist * 0.25, 10, 250)
					local Cp = (A + B) / 2 + Vector3.new(0, h, 0)
					local pts, on = {}, {}
					for i = 0, ARC_N do
						local t = i / ARC_N
						local mt = 1 - t
						local wp = A * (mt * mt) + Cp * (2 * mt * t) + B * (t * t)
						local s, vis = toScreen(cam, wp)
						pts[i + 1] = s; on[i + 1] = vis
					end
					for i = 1, ARC_N do
						local ln = arcLines[i]
						if on[i] and on[i + 1] then ln.From = pts[i]; ln.To = pts[i + 1]; ln.Visible = true else ln.Visible = false end
					end
				end
			else
				for _, ln in ipairs(arcLines) do ln.Visible = false end
			end

			-- ===== target camera (smoothed + glitch-guarded) =====
			if Toggles.artTargetCam.Value and targetPos then
				if not camActive then camSmooth = nil end   -- recapture on (re)enter
				camActive = true
				local root = art:FindFirstChild("Root") or art:FindFirstChild("Muzzle", true)
				-- horizontal direction from the gun to the target; DEFAULT if degenerate so the
				-- look vector never collapses (that flip is what caused the up/down jitter).
				local back = Vector3.new(0, 0, Options.artCamBack.Value)
				if root then
					local dir = root.Position - targetPos
					dir = Vector3.new(dir.X, 0, dir.Z)
					if dir.Magnitude > 1 then back = dir.Unit * Options.artCamBack.Value end
				end
				local camPos = targetPos + back + Vector3.new(0, Options.artCamHeight.Value, 0)
				-- guard: keep the camera a little off straight-down so LookAt never gimbals
				if (camPos - targetPos).Magnitude < 1 then camPos = camPos + Vector3.new(0, 0, 2) end
				local goal = CFrame.lookAt(camPos, targetPos)
				-- smooth toward the goal so a jumpy TargetPos doesn't snap/oscillate the view
				camSmooth = camSmooth and camSmooth:Lerp(goal, 0.25) or goal
				pcall(function()
					cam.CameraType = Enum.CameraType.Scriptable
					cam.CFrame = camSmooth
				end)
			elseif camActive then
				restoreCamera(); camSmooth = nil
			end

			-- ===== rate of fire (best-effort) =====
			-- ShootDelay override
			if Toggles.artDelayOverride.Value then
				local sd = stats and stats:FindFirstChild("ShootDelay")
				if sd then
					if delayArt ~= art then restoreDelay(); origDelay = sd.Value; delayArt = art end
					pcall(function() sd.Value = Options.artDelayValue.Value end)
				end
			elseif delayArt then
				restoreDelay()
			end
			-- Auto-Shoot
			if Toggles.artAutoShoot.Value then
				local shoot = events and events:FindFirstChild("Shoot")
				if shoot and shoot:IsA("RemoteEvent") then
					local interval = 1 / math.max(0.1, Options.artShootRate.Value)
					local now = tick()
					if now - lastShootAt >= interval then
						lastShootAt = now
						pcall(function() shoot:FireServer() end)
					end
				end
			end
			-- acceptance detection: did the SERVER register a shot?
			local sls = numVal(stats, "ServerLastShotTime") or numVal(stats, "LastShotTime")
			if sls then
				if prevServerShot ~= nil and sls ~= prevServerShot then
					accepted = accepted + 1
					local n = tick()
					if lastAcceptTick > 0 then acceptRate = 1 / math.max(0.01, n - lastAcceptTick) end
					lastAcceptTick = n
				end
				prevServerShot = sls
			end
			pcall(function()
				lblFire:SetText(("Accepted: %d shots (server)  ~%.1f/s\n%s"):format(
					accepted, acceptRate,
					Toggles.artAutoShoot.Value and "auto-shooting -- if /s stays ~0.1 the server caps it" or "auto-shoot off"))
			end)

			-- ===== shell impact -> flash the hit marker =====
			-- Shells travel too long for the core hit-marker's 0.5s attack window, so detect
			-- an enemy losing HP NEAR the impact point and flash the marker directly.
			if targetPos then
				local b = getgenv().CryptsHBE
				local reach = Options.artScatterRadius.Value * 2 + 20
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= lPlayer then
						local pc = plr.Character
						local hum = pc and pc:FindFirstChildWhichIsA("Humanoid")
						local hrp = pc and (pc:FindFirstChild("HumanoidRootPart") or pc:FindFirstChild("Head"))
						if hum and hrp then
							local prev = artHpCache[plr]
							if prev and hum.Health < prev - 0.01 and (hrp.Position - targetPos).Magnitude < reach then
								if b and b.FlashHitMarker then b.FlashHitMarker(0.3) end
							end
							artHpCache[plr] = hum.Health
						end
					end
				end
			end

			-- ===== range (elevation) override =====
			local elNow, elVerdict = nil, "off"
			if Toggles.artElevOverride.Value then
				local el = stats and stats:FindFirstChild("Elevation")
				if el then
					if not prevElevOv or elevArt ~= art then elevBase = el.Value; elevArt = art end  -- capture base on enable / gun change
					local target = (elevBase or el.Value) + Options.artElevExtra.Value
					pcall(function() el.Value = target end)
					elNow = el.Value
					elVerdict = (math.abs(elNow - target) < 0.001) and "applied" or "server re-clamped"
				end
			end
			prevElevOv = Toggles.artElevOverride.Value and true or false

			-- ===== inf turret ammo (separate from gun Inf Ammo) =====
			local turretN = 0
			if Toggles.artInfTurret.Value then
				if turretArt ~= art then restoreTurret(); turretFields = findTurretAmmo(art); turretArt = art end
				for _, t in ipairs(turretFields) do pcall(function() t.v.Value = math.max(t.v.Value, 999) end) end
				turretN = #turretFields
			elseif turretArt then
				restoreTurret()
			end

			pcall(function()
				lblRange:SetText(("Range/Turret:\nElev %s%s   Turret ammo fields: %d"):format(
					elNow and ("%.2f"):format(elNow) or "-",
					(elVerdict ~= "off") and (" (" .. elVerdict .. ")") or "",
					turretN))
			end)
		end)

		-- our character changing (death/respawn) invalidates camera + delay state
		ctx:Connect(lPlayer.CharacterAdded, function()
			restoreCamera(); restoreDelay(); restoreTurret(); elevBase, elevArt = nil, nil; prevServerShot = nil
		end)

		local howGroup = ctx:Groupbox("How to Use", "left")
		howGroup:AddLabel(
			"Mount an artillery / siege mortar\n" ..
			"(the Z interact), then:\n\n" ..
			"LANDING (read-only, undetectable):\n" ..
			"the game tells us TargetPos, so the\n" ..
			"red marker = exact impact, the white\n" ..
			"ring = your scatter guess. Tune\n" ..
			"Scatter Radius to match real spread.\n\n" ..
			"VIEW TARGET: camera floats over the\n" ..
			"impact zone; W/S/A/D still aim, so\n" ..
			"walk the ring onto the enemy.\n\n" ..
			"RATE OF FIRE is server-gated: turn on\n" ..
			"Auto-Shoot and read 'Accepted/s'. If\n" ..
			"it won't rise past the 8.5s cooldown,\n" ..
			"the server is enforcing it and no\n" ..
			"client trick will change that.\n\n" ..
			"(Moving the gun while mounted isn't\n" ..
			"possible -- it's a fixed emplacement.)",
			true)

		pluginCleanup = function()
			pcall(hideAllDraw); pcall(restoreCamera); pcall(restoreDelay); pcall(restoreTurret)
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
