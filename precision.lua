-- FurryHBE plugin: Precision HBE (standalone single-target extender + resolver)
-- Externalized from the core. Self-contained; uses globals (Toggles/Options/Library,
-- getgenv().DrawingFallback, getgenv().FurryHBE = Bridge) + the ctx sandbox.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = workspace
local lPlayer = Players.LocalPlayer
local DrawingFallback = getgenv().DrawingFallback
local Bridge = getgenv().FurryHBE

-- reimplemented locally (the core's version is a private local)
local function isLocalSeated()
	local char = lPlayer.Character
	if not char then return false end
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hum then return false end
	if hum.SeatPart ~= nil then return true end
	if hum.Sit == true then return true end
	local ok, seated = pcall(function() return hum:GetState() == Enum.HumanoidStateType.Seated end)
	return ok and seated or false
end

local pluginCleanup = nil  -- set by load(), called by unload()

return {
	name = "Precision", tab = "Precision", requires = {},

	load = function(ctx)
		local HttpService = game:GetService("HttpService")
		local cam = Workspace.CurrentCamera
		local CFG_FILE = "FurryHBE_Precision.json"

		local hbeGroup      = ctx:Groupbox("Precision HBE", "left")
		local targetGroup   = ctx:Groupbox("Target Selection", "left")
		local antiGroup     = ctx:Groupbox("Filters / Anti-Detection", "left")
		local scalingGroup  = ctx:Groupbox("Dynamic Scaling", "right")
		local zoneGroup     = ctx:Groupbox("Visual Zone", "right")
		local debugGroup    = ctx:Groupbox("Info", "right")
		local cfgGroup      = ctx:Groupbox("Config", "right")

		hbeGroup:AddToggle("precisionEnabled", { Text = "Enable Precision HBE", Default = false, Tooltip = "Standalone single-target hitbox extender.\nWorks even with the main Master Toggle off. (Default: OFF)" })
		hbeGroup:AddToggle("precisionExclusive", { Text = "Exclusive Mode", Default = false, Tooltip = "Also switch the main mass-extender OFF while Precision is active. (Default: OFF)" })
		hbeGroup:AddSlider("precisionHitboxSize", { Text = "Base Hitbox Size", Min = 2, Max = 100, Default = 12, Rounding = 1, Tooltip = "Base size applied to the target's parts (before dynamic scaling). (Default: 12)" })
		hbeGroup:AddSlider("precisionTransparency", { Text = "Transparency", Min = 0, Max = 1, Default = 0.6, Rounding = 2, Tooltip = "Transparency of the extended hitbox (0 = solid, 1 = invisible). (Default: 0.6)" })
		hbeGroup:AddDropdown("precisionShape", { Text = "Hitbox Shape", AllowNull = false, Multi = false, Values = { "Cube", "Flat (disk)", "Tall (pillar)" }, Default = "Cube", Tooltip = "Cube = uniform; Flat = wide & short; Tall = narrow & tall. (Default: Cube)" })
		hbeGroup:AddToggle("precisionCollisions", { Text = "Keep Collisions", Default = false, Tooltip = "Leave the extended part collidable. (Default: OFF)" })
		hbeGroup:AddToggle("precisionSmooth", { Text = "Smooth Transitions", Default = false, Tooltip = "Interpolate size changes instead of snapping. (Default: OFF)" })
		hbeGroup:AddSlider("precisionSmoothSpeed", { Text = "Smooth Speed", Min = 0.05, Max = 1, Default = 0.3, Rounding = 2 })
		hbeGroup:AddDropdown("precisionParts", { Text = "Parts to Extend", AllowNull = true, Multi = true, Values = { "HumanoidRootPart", "Head", "Torso", "UpperTorso", "LowerTorso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }, Default = { "Head" }, Tooltip = "Which of the target's parts to extend.\nWARNING: HumanoidRootPart freezes the target on your screen -- prefer Head/Torso. (Default: Head)" })

		targetGroup:AddToggle("autoSelectTarget", { Text = "Auto-Select Target", Default = true, Tooltip = "Automatically lock onto a target using the Resolver below. (Default: ON)" })
		targetGroup:AddDropdown("precisionResolver", { Text = "Resolver", Values = { "Closest to Crosshair", "Closest Distance", "Lowest Health" }, Default = "Closest to Crosshair", Multi = false, AllowNull = false, Tooltip = "How Auto-Select ranks targets. (Default: Closest to Crosshair)" })
		targetGroup:AddSlider("precisionLeadTime", { Text = "Velocity Lead (s)", Min = 0, Max = 0.5, Default = 0, Rounding = 2, Tooltip = "Predict the target's position this many seconds ahead by velocity. 0 = off. (Default: 0)" })
		targetGroup:AddSlider("selectionRadius", { Text = "Selection Radius (studs)", Min = 5, Max = 1000, Default = 150, Rounding = 1 })
		targetGroup:AddLabel("Manual Target"):AddKeyPicker("targetKeybind", { Default = "T", NoUI = true, Text = "Cycle Target" })

		antiGroup:AddToggle("precisionRespectWhitelist", { Text = "Respect Whitelist", Default = true })
		antiGroup:AddToggle("precisionIgnoreTeam", { Text = "Ignore Teammates", Default = false })
		antiGroup:AddToggle("precisionAutoOffDead", { Text = "Auto-Off When Dead", Default = true })
		antiGroup:AddToggle("precisionFOVGate", { Text = "FOV Gate", Default = false })
		antiGroup:AddSlider("precisionFOVRadius", { Text = "FOV Radius (px)", Min = 20, Max = 600, Default = 150, Rounding = 0 })
		antiGroup:AddToggle("precisionRandomize", { Text = "Randomize Size", Default = false })
		antiGroup:AddSlider("precisionRandomAmount", { Text = "Random Amount", Min = 0, Max = 5, Default = 1, Rounding = 1 })

		scalingGroup:AddToggle("dynamicScalingEnabled", { Text = "Dynamic Distance Scaling", Default = true })
		scalingGroup:AddSlider("scalingCloseFactor", { Text = "Close Range Factor", Min = 0.5, Max = 3.0, Default = 1.5, Rounding = 2 })
		scalingGroup:AddSlider("scalingFarFactor", { Text = "Far Range Factor", Min = 0.1, Max = 3.0, Default = 0.6, Rounding = 2 })
		scalingGroup:AddSlider("scalingThreshold", { Text = "Close/Far Threshold (studs)", Min = 10, Max = 300, Default = 60, Rounding = 1 })

		zoneGroup:AddToggle("showVisualZone", { Text = "Show Interaction Zone", Default = true })
		zoneGroup:AddSlider("zoneRadius", { Text = "Zone Radius (studs)", Min = 5, Max = 100, Default = 15, Rounding = 1 })
		zoneGroup:AddLabel("Zone Color"):AddColorPicker("zoneColor", { Title = "Zone Color", Default = Color3.fromRGB(0, 255, 255) })

		debugGroup:AddToggle("showProximityLabel", { Text = "Show Proximity Label", Default = true })
		debugGroup:AddToggle("showDistance", { Text = "Show Target Distance", Default = true })
		local infoTargetLabel = debugGroup:AddLabel("Target: none")
		local infoSizeLabel   = debugGroup:AddLabel("Applied size: -")

		local PRECISION_KEYS = {
			"precisionEnabled","precisionExclusive","precisionHitboxSize","precisionTransparency",
			"precisionShape","precisionCollisions","precisionSmooth","precisionSmoothSpeed","precisionParts",
			"autoSelectTarget","selectionRadius","precisionResolver","precisionLeadTime",
			"precisionRespectWhitelist","precisionIgnoreTeam","precisionAutoOffDead",
			"precisionFOVGate","precisionFOVRadius","precisionRandomize","precisionRandomAmount",
			"dynamicScalingEnabled","scalingCloseFactor","scalingFarFactor","scalingThreshold",
			"showVisualZone","zoneRadius","showProximityLabel","showDistance","targetKeybind","zoneColor",
		}
		for _, k in ipairs(PRECISION_KEYS) do ctx:Control(k) end

		local function savePrecisionConfig()
			if not writefile then Library:Notify("Executor has no writefile"); return end
			local data = {}
			for _, k in ipairs(PRECISION_KEYS) do local c = Options[k] or Toggles[k]; if c ~= nil and k ~= "zoneColor" and k ~= "targetKeybind" then data[k] = c.Value end end
			local ok = pcall(function() writefile(CFG_FILE, HttpService:JSONEncode(data)) end)
			Library:Notify(ok and "Precision config saved" or "Save failed")
		end
		local function loadPrecisionConfig(notify)
			if not (isfile and readfile and isfile(CFG_FILE)) then if notify then Library:Notify("No saved Precision config") end return end
			local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CFG_FILE)) end)
			if ok and type(data) == "table" then
				for k, v in pairs(data) do local c = Options[k] or Toggles[k]; if c then pcall(function() c:SetValue(v) end) end end
				if notify then Library:Notify("Precision config loaded") end
			elseif notify then Library:Notify("Saved config was unreadable") end
		end
		cfgGroup:AddButton("Save Config", savePrecisionConfig)
		cfgGroup:AddButton("Load Config", function() loadPrecisionConfig(true) end)

		local visualZone = ctx:Track(DrawingFallback.new("Circle")); visualZone.Thickness = 1; visualZone.Filled = false; visualZone.Visible = false
		local proximityLabel = ctx:Track(DrawingFallback.new("Text")); proximityLabel.Center = true; proximityLabel.Outline = true; proximityLabel.Size = 18; proximityLabel.Visible = false
		local targetNameLabel = ctx:Track(DrawingFallback.new("Text")); targetNameLabel.Center = true; targetNameLabel.Outline = true; targetNameLabel.Size = 14; targetNameLabel.Visible = false

		local selectedTarget, lastExtendedChar, claimedPlayer, currentAppliedSize, lastInfoUpdate = nil, nil, nil, nil, 0
		local extendedParts = {}

		local function claim(plr)
			if claimedPlayer ~= plr then
				if claimedPlayer then Bridge:ReleasePlayer(claimedPlayer) end
				Bridge:ClaimPlayer(plr, "Precision"); claimedPlayer = plr
			end
		end
		local function releaseClaim() if claimedPlayer then Bridge:ReleasePlayer(claimedPlayer); claimedPlayer = nil end end
		local function restoreExtended()
			for part, orig in pairs(extendedParts) do
				if typeof(part) == "Instance" and part.Parent then
					pcall(function()
						part.Size = orig.Size; part.Transparency = orig.Transparency; part.CanCollide = orig.CanCollide
						if orig.Massless ~= nil then part.Massless = orig.Massless end
					end)
				end
				extendedParts[part] = nil
			end
		end
		local function isLocalDead()
			local char = lPlayer.Character
			if not char then return true end
			local hum = char:FindFirstChildWhichIsA("Humanoid")
			if not hum then return true end
			return hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead
		end
		local function targetDistance(char)
			local node = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
			local lChar = lPlayer.Character
			local lNode = lChar and (lChar:FindFirstChild("HumanoidRootPart") or lChar:FindFirstChild("Head"))
			if node and lNode then return (node.Position - lNode.Position).Magnitude end
			return math.huge
		end
		local function computeSize(dist)
			local base = Options.precisionHitboxSize.Value
			if not Toggles.dynamicScalingEnabled.Value then return base end
			local threshold = math.max(1, Options.scalingThreshold.Value)
			local t = math.clamp(dist / threshold, 0, 1)
			return base * (Options.scalingCloseFactor.Value + (Options.scalingFarFactor.Value - Options.scalingCloseFactor.Value) * t)
		end
		local function sizeVectorForShape(s)
			local shape = Options.precisionShape and Options.precisionShape.Value or "Cube"
			if shape == "Flat (disk)" then return Vector3.new(s, math.max(1, s * 0.25), s)
			elseif shape == "Tall (pillar)" then return Vector3.new(math.max(1, s * 0.5), s * 1.5, math.max(1, s * 0.5)) end
			return Vector3.new(s, s, s)
		end
		local function extendChar(char, scalar)
			local names = Options.precisionParts:GetActiveValues()
			local transp = Options.precisionTransparency.Value
			local keepCol = Toggles.precisionCollisions.Value
			if Toggles.precisionRandomize.Value then scalar = math.max(1, scalar + (math.random() * 2 - 1) * Options.precisionRandomAmount.Value) end
			local desired = {}
			for _, n in ipairs(names) do local p = char:FindFirstChild(n); if p and p:IsA("BasePart") then desired[p] = true end end
			for part, orig in pairs(extendedParts) do
				if not desired[part] then
					if typeof(part) == "Instance" and part.Parent then
						pcall(function() part.Size = orig.Size; part.Transparency = orig.Transparency; part.CanCollide = orig.CanCollide; if orig.Massless ~= nil then part.Massless = orig.Massless end end)
					end
					extendedParts[part] = nil
				end
			end
			for part in pairs(desired) do
				local e = extendedParts[part]
				if not e then e = { Size = part.Size, Transparency = part.Transparency, CanCollide = part.CanCollide, Massless = part.Massless, Cur = scalar }; extendedParts[part] = e end
				local applied = scalar
				if Toggles.precisionSmooth.Value then e.Cur = e.Cur + (scalar - e.Cur) * Options.precisionSmoothSpeed.Value; applied = e.Cur else e.Cur = scalar end
				pcall(function()
					part.Size = sizeVectorForShape(applied); part.Transparency = transp
					part.CanCollide = keepCol and true or e.CanCollide
					if part.Name ~= "HumanoidRootPart" then part.Massless = true end
				end)
			end
		end
		local function passesFilters(plr, char)
			if Toggles.precisionRespectWhitelist.Value and Options.whitelistPlayerList then
				if table.find(Options.whitelistPlayerList:GetActiveValues(), plr.Name) then return false end
			end
			if Toggles.precisionIgnoreTeam.Value then
				local ok, same = pcall(function() if lPlayer.Team ~= nil or plr.Team ~= nil then return lPlayer.Team == plr.Team end return lPlayer.TeamColor == plr.TeamColor end)
				if ok and same then return false end
			end
			if Toggles.precisionFOVGate.Value then
				local head = char:FindFirstChild("Head"); if not head then return false end
				local p, on = cam:WorldToViewportPoint(head.Position); if not on then return false end
				local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
				if (Vector2.new(p.X, p.Y) - center).Magnitude > Options.precisionFOVRadius.Value then return false end
			end
			return true
		end
		local function predictedPos(part)
			local lead = (Options.precisionLeadTime and Options.precisionLeadTime.Value) or 0
			if lead > 0 then local ok, v = pcall(function() return part.AssemblyLinearVelocity end); if ok and typeof(v) == "Vector3" then return part.Position + v * lead end end
			return part.Position
		end
		local function getClosestVisiblePlayer(maxDist)
			local mode = (Options.precisionResolver and Options.precisionResolver.Value) or "Closest to Crosshair"
			local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
			local bestScore, bestPlr = math.huge, nil
			for _, plr in pairs(Players:GetPlayers()) do
				if plr ~= lPlayer then
					local char = plr.Character
					local head = char and char:FindFirstChild("Head")
					local hum = char and char:FindFirstChildWhichIsA("Humanoid")
					if head and hum and hum.Health > 0 and passesFilters(plr, char) then
						local dist = (head.Position - cam.CFrame.Position).Magnitude
						if dist <= (maxDist or math.huge) then
							local score
							if mode == "Closest Distance" then score = dist
							elseif mode == "Lowest Health" then score = hum.Health
							else local sp, on = cam:WorldToViewportPoint(predictedPos(head)); score = on and (Vector2.new(sp.X, sp.Y) - center).Magnitude or math.huge end
							if score < bestScore then bestScore, bestPlr = score, plr end
						end
					end
				end
			end
			return bestPlr
		end
		local function cycleTarget()
			local alive = {}
			for _, plr in pairs(Players:GetPlayers()) do
				local char = plr.Character
				local hum = char and char:FindFirstChildWhichIsA("Humanoid")
				if plr ~= lPlayer and hum and hum.Health > 0 and passesFilters(plr, char) then table.insert(alive, plr) end
			end
			if #alive == 0 then selectedTarget = nil; return end
			if not selectedTarget or not table.find(alive, selectedTarget) then selectedTarget = alive[1]
			else local idx = table.find(alive, selectedTarget) + 1; if idx > #alive then idx = 1 end; selectedTarget = alive[idx] end
		end

		Options.targetKeybind:OnClick(function()
			if Toggles.precisionEnabled and Toggles.precisionEnabled.Value then
				if Toggles.autoSelectTarget then Toggles.autoSelectTarget:SetValue(false) end
				cycleTarget()
			end
		end)
		local function applyExclusive()
			if Toggles.precisionEnabled and Toggles.precisionEnabled.Value and Toggles.precisionExclusive and Toggles.precisionExclusive.Value then
				if Toggles.extenderToggled and Toggles.extenderToggled.Value then Toggles.extenderToggled:SetValue(false); Library:Notify("Precision exclusive: main extender disabled") end
			end
		end
		Toggles.precisionEnabled:OnChanged(function()
			if Toggles.precisionEnabled.Value then applyExclusive()
			else restoreExtended(); releaseClaim(); lastExtendedChar = nil; selectedTarget = nil end
		end)
		Toggles.precisionExclusive:OnChanged(applyExclusive)

		local function precisionTick()
			if not (Toggles.precisionEnabled and Toggles.precisionEnabled.Value) then return end
			if Toggles.precisionAutoOffDead.Value and isLocalDead() then
				if next(extendedParts) then restoreExtended() end
				releaseClaim(); lastExtendedChar = nil; currentAppliedSize = nil; return
			end
			if Toggles.seatDisableHBE and Toggles.seatDisableHBE.Value and isLocalSeated() then
				local stop = true
				if Toggles.seatRadiusMode and Toggles.seatRadiusMode.Value then
					local c = selectedTarget and selectedTarget.Character
					stop = c ~= nil and targetDistance(c) <= (Options.seatRadius and Options.seatRadius.Value or 30)
				end
				if stop then if next(extendedParts) then restoreExtended() end; releaseClaim(); lastExtendedChar = nil; currentAppliedSize = nil; return end
			end
			cam = Workspace.CurrentCamera
			if Toggles.autoSelectTarget.Value then
				local best = getClosestVisiblePlayer(Options.selectionRadius.Value)
				local keep = false
				if selectedTarget and best and selectedTarget ~= best then
					local c = selectedTarget.Character
					local h = c and c:FindFirstChildWhichIsA("Humanoid")
					if c and h and h.Health > 0 and passesFilters(selectedTarget, c) then
						local head = c:FindFirstChild("Head")
						local onScreen = false
						if head then local _, on = cam:WorldToViewportPoint(head.Position); onScreen = on end
						if onScreen then
							local curD = targetDistance(c)
							local bestD = best.Character and targetDistance(best.Character) or math.huge
							if curD <= Options.selectionRadius.Value and curD <= bestD * 1.2 then keep = true end
						end
					end
				end
				if not keep then selectedTarget = best end
			end
			local char = selectedTarget and selectedTarget.Character
			local hum = char and char:FindFirstChildWhichIsA("Humanoid")
			local alive = hum and hum.Health > 0 and passesFilters(selectedTarget, char)
			if char ~= lastExtendedChar or not alive then restoreExtended(); releaseClaim(); lastExtendedChar = (char and alive) and char or nil end
			if char and alive then claim(selectedTarget); local dist = targetDistance(char); currentAppliedSize = computeSize(dist); extendChar(char, currentAppliedSize)
			else currentAppliedSize = nil end
		end

		local function precisionVisuals()
			if not (Toggles.precisionEnabled and Toggles.precisionEnabled.Value) then visualZone.Visible = false; proximityLabel.Visible = false; targetNameLabel.Visible = false; return end
			cam = Workspace.CurrentCamera
			local now = tick()
			if now - lastInfoUpdate > 0.2 then
				lastInfoUpdate = now
				local char = selectedTarget and selectedTarget.Character
				if char then
					local frozen = ""
					pcall(function() local hrp = char:FindFirstChild("HumanoidRootPart"); if hrp and char == lastExtendedChar and hrp.AssemblyLinearVelocity.Magnitude < 0.4 then frozen = "  [FROZEN?]" end end)
					infoTargetLabel:SetText("Target: " .. selectedTarget.Name .. " (" .. math.floor(targetDistance(char)) .. "m)" .. frozen)
					infoSizeLabel:SetText("Applied size: " .. (currentAppliedSize and string.format("%.1f", currentAppliedSize) or "-"))
				else infoTargetLabel:SetText("Target: none"); infoSizeLabel:SetText("Applied size: -") end
			end
			if Toggles.showVisualZone.Value then
				local root = lPlayer.Character and lPlayer.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local pos, onScreen = cam:WorldToViewportPoint(root.Position)
					if onScreen and pos.Z > 0 then visualZone.Visible = true; local scale = 1000 / pos.Z; visualZone.Radius = Options.zoneRadius.Value * scale; visualZone.Position = Vector2.new(pos.X, pos.Y); visualZone.Color = Options.zoneColor.Value
					else visualZone.Visible = false end
				else visualZone.Visible = false end
			else visualZone.Visible = false end
			local char = selectedTarget and selectedTarget.Character
			local hum = char and char:FindFirstChildWhichIsA("Humanoid")
			if char and hum and hum.Health > 0 then
				local head = char:FindFirstChild("Head")
				if head then
					local pos, onScreen = cam:WorldToViewportPoint(head.Position)
					local d = targetDistance(char)
					if onScreen then
						if Toggles.showProximityLabel.Value then
							local category = d < 10 and "Close" or (d < 30 and "Medium" or "Far")
							proximityLabel.Text = category; proximityLabel.Position = Vector2.new(pos.X, pos.Y - 30)
							proximityLabel.Color = category == "Close" and Color3.fromRGB(0, 255, 0) or (category == "Medium" and Color3.fromRGB(255, 255, 0)) or Color3.fromRGB(255, 0, 0)
							proximityLabel.Visible = true
						else proximityLabel.Visible = false end
						local txt = selectedTarget.Name
						if Toggles.showDistance.Value then txt = txt .. " [" .. math.floor(d) .. "m]" end
						targetNameLabel.Text = txt; targetNameLabel.Position = Vector2.new(pos.X, pos.Y - 45); targetNameLabel.Color = Color3.fromRGB(255, 255, 255); targetNameLabel.Visible = true
					else proximityLabel.Visible = false; targetNameLabel.Visible = false end
				else proximityLabel.Visible = false; targetNameLabel.Visible = false end
			else proximityLabel.Visible = false; targetNameLabel.Visible = false end
		end

		ctx:Connect(RunService.Heartbeat, function() pcall(precisionTick) end)
		ctx:Connect(RunService.RenderStepped, function() pcall(precisionVisuals) end)

		pluginCleanup = function() pcall(restoreExtended); pcall(releaseClaim) end
		pcall(function() loadPrecisionConfig(false) end)
	end,

	unload = function()
		if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end
	end,
}
