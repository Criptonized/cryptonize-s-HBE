-- FurryHBE plugin: Aimbot (camera aimbot + triggerbot + no-recoil)
-- Loaded on demand by the core via Bridge:EnablePlugin. Self-contained: uses only
-- globals (Toggles/Options/Library set by LinoriaLib, getgenv().DrawingFallback) +
-- the ctx sandbox passed to load(). See plugins/aimbot.md.
-- Hook-free (no namecall/MT hooks). Aimbot moves the CAMERA (not silent aim).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = workspace
local lPlayer = Players.LocalPlayer
local DrawingFallback = getgenv().DrawingFallback

-- module-level state (shared by load + unload)
local nrOrig = {}
local function restoreRecoil()
	for v, o in pairs(nrOrig) do
		if typeof(v) == "Instance" and v.Parent then pcall(function() v.Value = o end) end
		nrOrig[v] = nil
	end
end

return {
	name = "Aimbot", tab = "Aimbot", requires = {},

	load = function(ctx)
		local cam = Workspace.CurrentCamera
		local aimGroup  = ctx:Groupbox("Aimbot (camera)", "left")
		local trigGroup = ctx:Groupbox("Triggerbot", "right")
		local nrGroup   = ctx:Groupbox("No-Recoil", "right")

		local function C(key) ctx:Control(key) end  -- shorthand to track a control key

		aimGroup:AddToggle("aimbotEnabled", { Text = "Enable Aimbot", Default = false, Tooltip = "Smoothly pull the camera toward the target (camera aimbot,\nnot silent aim). (Default: OFF)" }); C("aimbotEnabled")
		aimGroup:AddDropdown("aimbotTrigger", { Text = "Activate", Values = { "Hold Right Mouse", "Hold Key", "Always" }, Default = "Hold Right Mouse", Multi = false, AllowNull = false }); C("aimbotTrigger")
		aimGroup:AddLabel("Aim Key"):AddKeyPicker("aimbotKey", { Default = "E", NoUI = true, Text = "Aim Key" }); C("aimbotKey")
		aimGroup:AddDropdown("aimbotPart", { Text = "Target Part", Values = { "Head", "Torso", "HumanoidRootPart" }, Default = "Head", Multi = false, AllowNull = false }); C("aimbotPart")
		aimGroup:AddSlider("aimbotFOV", { Text = "FOV (px)", Min = 20, Max = 600, Default = 120, Rounding = 0 }); C("aimbotFOV")
		aimGroup:AddSlider("aimbotSmooth", { Text = "Smoothness", Min = 0.02, Max = 1, Default = 0.25, Rounding = 2, Tooltip = "Lower = smoother/slower, 1 = instant snap. (Default: 0.25)" }); C("aimbotSmooth")
		aimGroup:AddToggle("aimbotVisibleOnly", { Text = "Visible Only", Default = true }); C("aimbotVisibleOnly")
		aimGroup:AddToggle("aimbotPredict", { Text = "Ballistic Prediction", Default = false, Tooltip = "Lead by velocity x bullet travel time + gravity drop. (Default: OFF)" }); C("aimbotPredict")
		aimGroup:AddSlider("aimbotBulletSpeed", { Text = "Bullet Speed", Min = 50, Max = 5000, Default = 1000, Rounding = 0 }); C("aimbotBulletSpeed")
		aimGroup:AddSlider("aimbotDropComp", { Text = "Gravity Drop Comp", Min = 0, Max = 1, Default = 0, Rounding = 2 }); C("aimbotDropComp")
		aimGroup:AddToggle("aimbotIgnoreTeam", { Text = "Ignore Team", Default = true }); C("aimbotIgnoreTeam")
		aimGroup:AddToggle("aimbotIgnoreWL", { Text = "Ignore Whitelisted", Default = true }); C("aimbotIgnoreWL")
		aimGroup:AddToggle("aimbotShowFOV", { Text = "Show FOV Circle", Default = true }); C("aimbotShowFOV")
		local aimInfo = aimGroup:AddLabel("Target: none")

		trigGroup:AddToggle("triggerEnabled", { Text = "Enable Triggerbot", Default = false }); C("triggerEnabled")
		trigGroup:AddDropdown("triggerActivate", { Text = "Activate", Values = { "Always", "Hold Key" }, Default = "Always", Multi = false, AllowNull = false }); C("triggerActivate")
		trigGroup:AddLabel("Trigger Key"):AddKeyPicker("triggerKey", { Default = "C", NoUI = true, Text = "Trigger Key" }); C("triggerKey")
		trigGroup:AddSlider("triggerDelay", { Text = "Delay (ms)", Min = 0, Max = 500, Default = 50, Rounding = 0 }); C("triggerDelay")
		trigGroup:AddToggle("triggerIgnoreTeam", { Text = "Ignore Team", Default = true }); C("triggerIgnoreTeam")

		nrGroup:AddToggle("norecoilEnabled", { Text = "No-Recoil / Spread", Default = false, Tooltip = "Zero detected recoil/spread/kick values on the held gun. (Default: OFF)" }); C("norecoilEnabled")
		local nrInfo = nrGroup:AddLabel("Recoil values: -")

		local function sameTeam(plr)
			local ok, s = pcall(function()
				if lPlayer.Team ~= nil or plr.Team ~= nil then return lPlayer.Team == plr.Team end
				return lPlayer.TeamColor == plr.TeamColor
			end)
			return ok and s or false
		end
		local function aimValid(plr, ignoreTeam)
			if plr == lPlayer then return false end
			local c = plr.Character
			local hum = c and c:FindFirstChildWhichIsA("Humanoid")
			if not (c and hum and hum.Health > 0) then return false end
			if Toggles.aimbotIgnoreWL.Value and Options.whitelistPlayerList and table.find(Options.whitelistPlayerList:GetActiveValues(), plr.Name) then return false end
			if ignoreTeam and sameTeam(plr) then return false end
			return true
		end
		local function hasLOS(toPart)
			local lc = lPlayer.Character
			if not lc then return true end
			local ok, clear = pcall(function()
				local p = RaycastParams.new()
				p.FilterType = Enum.RaycastFilterType.Exclude
				p.FilterDescendantsInstances = { lc, toPart.Parent }
				return Workspace:Raycast(cam.CFrame.Position, toPart.Position - cam.CFrame.Position, p) == nil
			end)
			return ok and clear or false
		end
		local function partOf(plr)
			local c = plr.Character
			if not c then return nil end
			return c:FindFirstChild(Options.aimbotPart.Value) or c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")
		end
		local function gateActive(mode, keyOpt)
			if mode == "Always" then return true end
			if mode == "Hold Right Mouse" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
			local k = keyOpt and keyOpt.Value
			if not k then return false end
			local ok, down = pcall(function() return UserInputService:IsKeyDown(Enum.KeyCode[k]) end)
			return ok and down or false
		end

		local fovRing = ctx:Track(DrawingFallback.new("Circle"))
		fovRing.Thickness = 1; fovRing.Filled = false; fovRing.NumSides = 48; fovRing.Color = Color3.fromRGB(255, 255, 255); fovRing.Visible = false

		local function aimTarget()
			cam = Workspace.CurrentCamera
			local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
			local fov = Options.aimbotFOV.Value
			local best, bestd, bestplr = nil, fov, nil
			for _, plr in ipairs(Players:GetPlayers()) do
				if aimValid(plr, Toggles.aimbotIgnoreTeam.Value) then
					local part = partOf(plr)
					if part then
						local sp, on = cam:WorldToViewportPoint(part.Position)
						if on then
							local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
							if d < bestd and (not Toggles.aimbotVisibleOnly.Value or hasLOS(part)) then bestd, best, bestplr = d, part, plr end
						end
					end
				end
			end
			return best, bestplr
		end

		ctx:Connect(RunService.RenderStepped, function()
			cam = Workspace.CurrentCamera
			if Toggles.aimbotEnabled.Value and Toggles.aimbotShowFOV.Value then
				fovRing.Radius = Options.aimbotFOV.Value
				fovRing.Position = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
				fovRing.Visible = true
			else
				fovRing.Visible = false
			end
			if not Toggles.aimbotEnabled.Value then return end
			if not gateActive(Options.aimbotTrigger.Value, Options.aimbotKey) then pcall(function() aimInfo:SetText("Target: none") end); return end
			local part, plr = aimTarget()
			if part then
				local aimPos = part.Position
				if Toggles.aimbotPredict.Value then
					local ok, v = pcall(function() return part.AssemblyLinearVelocity end)
					v = (ok and typeof(v) == "Vector3") and v or Vector3.new(0, 0, 0)
					local bs = Options.aimbotBulletSpeed.Value
					local t = bs > 0 and ((part.Position - cam.CFrame.Position).Magnitude / bs) or 0
					aimPos = part.Position + v * t
					local dropF = Options.aimbotDropComp.Value
					if dropF > 0 then aimPos = aimPos + Vector3.new(0, 0.5 * Workspace.Gravity * t * t * dropF, 0) end
				end
				cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, aimPos), math.clamp(Options.aimbotSmooth.Value, 0.02, 1))
				pcall(function() aimInfo:SetText("Target: " .. (plr and plr.Name or "?")) end)
			else
				pcall(function() aimInfo:SetText("Target: none") end)
			end
		end)

		local lastTrig = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not Toggles.triggerEnabled.Value then return end
			if not gateActive(Options.triggerActivate.Value, Options.triggerKey) then return end
			cam = Workspace.CurrentCamera
			local lc = lPlayer.Character
			if not lc then return end
			local ray = cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
			local p = RaycastParams.new()
			p.FilterType = Enum.RaycastFilterType.Exclude
			p.FilterDescendantsInstances = { lc }
			local res = Workspace:Raycast(ray.Origin, ray.Direction * 1500, p)
			if res and res.Instance then
				local model = res.Instance:FindFirstAncestorWhichIsA("Model")
				local plr = model and Players:GetPlayerFromCharacter(model)
				if plr and aimValid(plr, Toggles.triggerIgnoreTeam.Value) then
					local now = tick()
					if now - lastTrig > (Options.triggerDelay.Value / 1000) then
						lastTrig = now
						if mouse1click then pcall(mouse1click) end
					end
				end
			end
		end)

		local RECOIL_WORDS = { "recoil", "spread", "kick", "bloom", "sway", "camkick" }
		local nrLast = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not Toggles.norecoilEnabled.Value then
				if next(nrOrig) then restoreRecoil(); pcall(function() nrInfo:SetText("Recoil values: -") end) end
				return
			end
			local now = tick(); if now - nrLast < 0.2 then return end; nrLast = now
			local lc = lPlayer.Character
			local tool = lc and lc:FindFirstChildWhichIsA("Tool")
			if not tool then return end
			local n = 0
			for _, d in ipairs(tool:GetDescendants()) do
				if d:IsA("NumberValue") or d:IsA("IntValue") then
					local nm = d.Name:lower()
					for _, w in ipairs(RECOIL_WORDS) do
						if nm:find(w) then
							if nrOrig[d] == nil then nrOrig[d] = d.Value end
							pcall(function() d.Value = 0 end); n = n + 1; break
						end
					end
				end
			end
			pcall(function() nrInfo:SetText("Recoil values: " .. n) end)
		end)

		-- Bottom-of-tab tutorial.
		local howGroup = ctx:Groupbox("How to Use", "left")
		howGroup:AddLabel(
			"AIMBOT (camera): drags your camera onto the closest enemy inside the FOV cone.\n" ..
			"  1. Pick Activate: Hold Right Mouse / Hold Key / Always.\n" ..
			"  2. Set Target Part (Head), FOV (cone size), Smoothness (low = slow/legit, 1 = snap).\n" ..
			"  3. 'Visible Only' ignores enemies behind walls. 'Ballistic Prediction' leads moving\n" ..
			"     targets -- set Bullet Speed to the gun's projectile speed.\n\n" ..
			"TRIGGERBOT: auto-fires when your crosshair is already on an enemy (raycast from screen\n" ..
			"  center). Set Activate + Delay (ms) so it isn't instant.\n\n" ..
			"NO-RECOIL: zeroes recoil/spread values on the held gun (client-side guns only; if the\n" ..
			"  'Recoil values' count stays 0, this game keeps recoil server-side).\n\n" ..
			"EXAMPLE: Activate=Hold Right Mouse, Head, FOV 120, Smooth 0.25, Visible Only ON ->\n" ..
			"  smooth, fairly legit aim that only locks visible enemies while you hold RMB.",
			true)
	end,

	unload = function() restoreRecoil() end,  -- ctx auto-disconnects the loops + destroys the ring
}
