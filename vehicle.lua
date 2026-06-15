-- CryptsHBE plugin: Vehicle  (extracted from the core Vehicle/Misc tab)
-- ============================================================================
-- The whole Vehicle/Misc tab, lifted out of mainscript to shrink the core. Contains:
-- Vehicle Assist (jolt / accelerator / limiter / auto-stabilizer + detection + manual
-- pick), Combat Tool Expander / Scanner / Weapon List, Manual Vehicle HBE, Vehicle Modify
-- / Tuning (incl. physics detection + Wheel Motor Boost) and Vehicle ESP. Behaviour is
-- UNCHANGED -- the three original pcall blocks run verbatim; only the tab handle comes from
-- the plugin context now. Builds once (Bridge._vehBuilt) so re-enabling just re-shows the
-- cached tab (no duplicate groupboxes); its connections persist like the always-on core
-- feature it replaces.
-- ============================================================================
local Players = game:GetService("Players")
local Workspace = workspace
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local DrawingFallback = getgenv().DrawingFallback
local function safeRemoveDrawing(obj)
	if not obj then return end
	if type(obj.Destroy) == "function" then pcall(function() obj:Destroy() end)
	elseif type(obj.Remove) == "function" then pcall(function() obj:Remove() end) end
end
local function isNumericValue(d)
	return d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue")
end

return {
	name = "Vehicle", tab = "Vehicle/Misc", requires = {},
	load = function(ctx)
		local Bridge = getgenv().CryptsHBE
		Bridge.MiscTab = ctx.tab
		if Bridge._vehBuilt then return end
		Bridge._vehBuilt = true
		local mainTab = ctx.tab
pcall(function()
	local miscTab = ctx.tab
	Bridge.MiscTab = miscTab  -- still exposed so future add-ons can attach here too
	local lPlayer = Players.LocalPlayer

	local conns = {}
	local function track(c) table.insert(conns, c); return c end

	-- 4 left + 4 right groupboxes, all under the single Miscellaneous tab.
	local speedGroup     = miscTab:AddLeftGroupbox("Vehicle: Speed")
	local detectGroup    = miscTab:AddLeftGroupbox("Vehicle: Detection")
	local stabilGroup    = miscTab:AddLeftGroupbox("Vehicle: Stability")
	local expanderGroup  = miscTab:AddLeftGroupbox("Combat: Tool Expander")
	local infoGroup      = miscTab:AddRightGroupbox("Vehicle: Info")
	local weaponListGroup= miscTab:AddRightGroupbox("Combat: Weapon List")
	local scannerGroup   = miscTab:AddRightGroupbox("Combat: Tool Scanner")
	local settingsGroupC = miscTab:AddRightGroupbox("Combat: Settings")

	-- Forward declarations: buttons below are created before these are defined.
	local refreshVehicleDetection, applyToolExpansion, detectSpeedSystem

	-- Manual vehicle pick (fallback if auto seat-detection fails).
	local manualVehicle = nil       -- the part you clicked (primary fallback)
	local manualVehicleModel = nil  -- the whole car that part belongs to (F4)

	-- Reject obvious world/map geometry so a hold-pick can't register the ground. (F4)
	local function looksLikeGround(part)
		if not part then return true end
		if part == Workspace.Terrain then return true end
		local n = part.Name:lower()
		if n:find("baseplate") or n:find("terrain") or n:find("ground") or n:find("floor") or n:find("map") then return true end
		if part.Anchored and part.Size.X > 150 and part.Size.Z > 150 then return true end
		return false
	end

	-- ===== Vehicle UI =====
	speedGroup:AddToggle("vehicleAssist", { Text = "Vehicle Assist", Default = false, Tooltip = "Master toggle. Enables the speed jolt + limiter. The\nauto-stabilizer (keep-upright + grip) is its OWN toggle\nunder Vehicle: Stability, so you can jolt/drive with no\nassist fighting the car. (Default: OFF)" })
	speedGroup:AddLabel("Speed Jolt Key"):AddKeyPicker("vehicleJoltKey", { Default = "G", NoUI = true, Text = "Speed Jolt" })
	speedGroup:AddSlider("vehicleJoltPower", { Text = "Jolt Power", Min = 10, Max = 500, Default = 120, Rounding = 1, Tooltip = "Burst of speed per key press. Studs/sec normally, or a %\nof the car's own top speed if 'Jolt in car's units' is on.\n(Default: 120)" })
	speedGroup:AddToggle("vehicleJoltRelative", { Text = "Jolt in car's units", Default = false, Tooltip = "Treat Jolt Power as a % of the car's OWN top speed\n(auto-detected from its VehicleSeat) so a jolt feels the\nsame on slow and fast cars. (Default: OFF)" })
	speedGroup:AddToggle("vehicleTripleTap", { Text = "Triple-tap key = toggle Assist", Default = false, Tooltip = "Tap the Jolt key 3x quickly to flip Vehicle Assist on/off.\nThose 3 taps won't jolt. (Default: OFF)" })
	speedGroup:AddToggle("vehicleAccelerator", { Text = "Speed Accelerator", Default = false, Tooltip = "While you're driving, smoothly builds your speed up to the\nTop Speed below -- a natural power boost that keeps your\nsteering and doesn't shock the suspension like the jolt. (Default: OFF)" })
	speedGroup:AddSlider("vehicleTopSpeed", { Text = "Top Speed (studs/s)", Min = 20, Max = 500, Default = 120, Rounding = 0, Tooltip = "Target speed the accelerator ramps you up to. (Default: 120)" })
	speedGroup:AddSlider("vehicleAccelRate", { Text = "Acceleration", Min = 10, Max = 400, Default = 80, Rounding = 0, Tooltip = "How quickly the accelerator builds speed (studs/sec^2).\nLower = gentler, higher = snappier. (Default: 80)" })

	detectGroup:AddDropdown("vehicleDetectionMode", { Text = "Detection Mode", Values = { "Auto", "A-Chassis", "Basic Seat", "Custom Script" }, Default = "Auto", Multi = false, AllowNull = false, Tooltip = "Leave on Auto -- it detects A-Chassis / VehicleSeat /\ncustom cars for you and shows the result in Vehicle: Info.\nThe other options only force the label if Auto guesses\nwrong; they don't change how assist behaves. (Default: Auto)" })
	detectGroup:AddButton("Refresh Detection", function()
		if refreshVehicleDetection then pcall(refreshVehicleDetection) end
	end):AddToolTip("Rescan your character for the seat/vehicle you're in")
	detectGroup:AddToggle("vehicleManualMode", { Text = "Manual Vehicle", Default = false, Tooltip = "Ignore auto seat-detection and use the vehicle\nyou pick below (use this if auto fails). (Default: OFF)" })
	detectGroup:AddButton("Pick Vehicle (hold-click)", function()
		Bridge:StartHoldPick({
			color = Color3.fromRGB(0, 170, 255),
			filter = function(part) return not looksLikeGround(part) end,
			onPick = function(part)
				if looksLikeGround(part) then Library:Notify("That looks like ground/map, not a vehicle"); return end
				-- Register the WHOLE car: walk up to the top-most Model under Workspace,
				-- so clicking any single part grabs the entire vehicle. (F4)
				local model = part:FindFirstAncestorWhichIsA("Model")
				local top = model
				while top and top.Parent and top.Parent:IsA("Model") do top = top.Parent end
				manualVehicleModel = top or model
				manualVehicle = part
				if not Toggles.vehicleManualMode.Value then Toggles.vehicleManualMode:SetValue(true) end
				if refreshVehicleDetection then pcall(refreshVehicleDetection) end
				Library:Notify("Manual vehicle: " .. ((manualVehicleModel and manualVehicleModel.Name) or part.Name))
			end,
		})
	end):AddToolTip("Aim at ANY part of a car and HOLD left-click until the ring fills -- it registers the whole vehicle (ground/map parts are rejected). Right-click cancels.")
	detectGroup:AddButton("Clear Manual Vehicle", function()
		manualVehicle = nil; manualVehicleModel = nil
		if refreshVehicleDetection then pcall(refreshVehicleDetection) end
		Library:Notify("Manual vehicle cleared")
	end):AddToolTip("Forget the manually picked vehicle")

	stabilGroup:AddToggle("vehicleStabilizer", { Text = "Auto-Stabilizer", Default = true, Tooltip = "Gentle anti-rollover: only nudges the car upright if it tips\npast ~35 degrees, with light torque -- so it never fights your\nsteering or makes the car float/skate. Turn OFF for fully raw\ndriving. (Default: ON)" })
	stabilGroup:AddToggle("vehicleSpeedLimiter", { Text = "Speed Limiter", Default = false, Tooltip = "ON = caps your speed at the limit below even if you keep\njolting. OFF = jolts uncapped (hit the jets). (Default: OFF)" })
	stabilGroup:AddSlider("vehicleSpeedCap", { Text = "Speed Limit (studs/s)", Min = 20, Max = 500, Default = 120, Rounding = 1, Tooltip = "Max horizontal speed while the limiter is on. (Default: 120)" })
	stabilGroup:AddButton("Match Car's Top Speed", function()
		if refreshVehicleDetection then pcall(refreshVehicleDetection) end
		if detectSpeedSystem then
			local sys = detectSpeedSystem()
			if sys and sys.maxSpeed and sys.maxSpeed > 0 then
				Options.vehicleSpeedCap:SetValue(math.clamp(math.floor(sys.maxSpeed), 20, 500))
				Library:Notify("Speed limit set to this car's top speed (" .. math.floor(sys.maxSpeed) .. ")")
			else
				Library:Notify("This car has no readable top speed (it's physics-driven)")
			end
		end
	end):AddToolTip("Set the limiter to the car's own detected top speed, so the cap is in the car's units. (F2)")

	local vehicleInfoLabel = infoGroup:AddLabel("Current Vehicle: None")

	-- ===== Combat UI =====
	weaponListGroup:AddDropdown("expandedWeapons", { Text = "Active Weapons", Values = {}, Multi = true, AllowNull = true, Default = {}, Tooltip = "Tools whose hitbox will be expanded. (Default: none)" })

	expanderGroup:AddToggle("toolExpanderEnabled", { Text = "Enable Tool Expander", Default = false, Tooltip = "Master toggle for tool hitbox expansion. (Default: OFF)" })
	expanderGroup:AddSlider("toolExpandSize", { Text = "Expansion Size", Min = 0.5, Max = 10, Default = 2, Rounding = 1, Tooltip = "Multiplier applied to tool part sizes. (Default: 2)" })
	expanderGroup:AddToggle("toolNonCollide", { Text = "Non-Collidable Hitbox", Default = true, Tooltip = "MELEE-COLLIDE: the enlarged hitbox is non-collidable (won't\nshove you/objects or snag on the world) but still keeps CanTouch\non, so the game's own touch-damage still lands. (Default: ON)" }):OnChanged(function()
		-- Re-apply so the change takes effect immediately on already-expanded tools.
		-- expandTool applies the on/off collision state both ways, so this is enough.
		if applyToolExpansion then pcall(applyToolExpansion) end
	end)
	expanderGroup:AddDropdown("toolPartFilter", { Text = "Parts to Expand", Values = { "Handle", "Blade", "HitBox", "Tip", "All" }, Default = { "Handle", "Blade" }, Multi = true, AllowNull = true, Tooltip = "Which tool parts get expanded (name match). (Default: Handle, Blade)" })

	scannerGroup:AddButton("Scan Tools", function()
		-- Pure read-only scan: collects tool NAMES only, never touches a tool (no
		-- resize/equip), and MERGES into the existing list instead of replacing it so
		-- a rescan can't wipe your current weapon selection. Wrapped in pcall so a bad
		-- container can't error out. (B4)
		pcall(function()
			local seen, tools = {}, {}
			for _, n in ipairs(Options.expandedWeapons.Values or {}) do
				if type(n) == "string" and not seen[n] then seen[n] = true; tools[#tools + 1] = n end
			end
			local function scan(container)
				if not container then return end
				for _, t in ipairs(container:GetChildren()) do
					if t:IsA("Tool") and t.Name ~= "" and not seen[t.Name] then
						seen[t.Name] = true; tools[#tools + 1] = t.Name
					end
				end
			end
			scan(lPlayer:FindFirstChild("Backpack"))
			scan(lPlayer.Character)
			Options.expandedWeapons.Values = tools
			Options.expandedWeapons:SetValues()
			Library:Notify("Found " .. #tools .. " tool(s) -- scan only, nothing modified")
		end)
	end):AddToolTip("Read-only: lists tool names from your backpack/character and merges them into Active Weapons. Never resizes or equips anything.")

	settingsGroupC:AddToggle("toolAutoApply", { Text = "Auto-Apply on Equip", Default = true, Tooltip = "Expand a tool automatically when equipped if it's in the active list. (Default: ON)" })
	settingsGroupC:AddToggle("toolAutoScanEquip", { Text = "Auto-Add on Equip", Default = false, Tooltip = "When you equip a tool, automatically add it to the Active\nWeapons list AND expand it (if the expander is on) -- no\nmanual scanning needed. (Default: OFF)" })
	settingsGroupC:AddButton("Apply Now", function()
		if applyToolExpansion then pcall(applyToolExpansion) end
	end):AddToolTip("Force-apply expansion to the currently equipped tool(s)")

	-- ===== Vehicle logic (combined assist: jolt + limiter + auto-stabilizer) =====
	local currentVehicle, vehicleType
	local assistConn = nil

	local function detectVehicle()
		-- Manual override: if Manual Vehicle is on, use the part you picked so assist
		-- still works when auto seat-detection fails.
		if Toggles.vehicleManualMode and Toggles.vehicleManualMode.Value then
			-- Prefer the whole picked car: hand back its primary part so assist acts on
			-- the real chassis, not the single part you happened to click. (F4)
			if manualVehicleModel and manualVehicleModel.Parent then
				return manualVehicleModel.PrimaryPart
					or (manualVehicle and manualVehicle.Parent and manualVehicle)
					or manualVehicleModel:FindFirstChildWhichIsA("BasePart")
			end
			if manualVehicle and manualVehicle.Parent then return manualVehicle end
			return nil
		end
		local char = lPlayer.Character
		if not char then return nil end
		local hum = char:FindFirstChildWhichIsA("Humanoid")
		if hum and hum.SeatPart then return hum.SeatPart end
		return nil
	end

	local function identifyVehicleType(vehicle)
		local root = vehicle:FindFirstAncestorWhichIsA("Model")
		if root and (root:FindFirstChild("A-Chassis") or root:FindFirstChild("Chassis")) then return "A-Chassis" end
		if vehicle:IsA("VehicleSeat") then return "Basic Seat" end
		return "Custom Script"
	end

	local function vehicleRootAndPrimary()
		if not currentVehicle or not currentVehicle.Parent then return nil, nil end
		local root = currentVehicle:FindFirstAncestorWhichIsA("Model") or currentVehicle
		local primary = root.PrimaryPart or (currentVehicle:IsA("BasePart") and currentVehicle) or root:FindFirstChildWhichIsA("BasePart")
		return root, primary
	end

	-- Best-effort read of the car's OWN speed system so jolt/limiter can work in its
	-- units: a VehicleSeat exposes MaxSpeed/Throttle; A-Chassis/custom cars are
	-- physics-driven so we just report that. (F2/F5)
	detectSpeedSystem = function()
		local root = vehicleRootAndPrimary()
		if not root then return nil end
		local seat = (currentVehicle and currentVehicle:IsA("VehicleSeat") and currentVehicle)
			or root:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat then
			return { kind = "VehicleSeat", maxSpeed = seat.MaxSpeed, throttle = seat.Throttle, seat = seat }
		end
		if root:FindFirstChild("A-Chassis") or root:FindFirstChild("Chassis") then
			return { kind = "A-Chassis" }
		end
		return { kind = "Physics" }
	end

	-- Track the part we last attached a gyro to so we can clean it up the moment we
	-- leave/switch vehicles (audit fix: an empty car was being left stabilized).
	local activePrimary = nil
	local function clearGyro()
		if activePrimary then
			pcall(function()
				local g = activePrimary:FindFirstChild("CryptsHBE_StabGyro")
				if g then g:Destroy() end
			end)
			activePrimary = nil
		end
	end
	local function removeVehiclePhysics() clearGyro() end

	-- Always re-validate which vehicle we're actually in; if it changed or we got
	-- out, drop the old gyro first.
	local function ensureVehicle()
		currentVehicle = detectVehicle()
		local root, primary = vehicleRootAndPrimary()
		if primary ~= activePrimary then clearGyro(); activePrimary = primary end
		return root, primary
	end

	-- Direction the car is actually travelling: follow horizontal velocity when moving
	-- (so boosts always push the way you DRIVE, never a fixed axis -- the old jolt used
	-- LookVector which threw the car off to one side), else fall back to chassis facing.
	local function drivingForward(primary, vel)
		local horiz = Vector3.new(vel.X, 0, vel.Z)
		if horiz.Magnitude > 4 then return horiz.Unit end
		local f = primary.CFrame.LookVector
		f = Vector3.new(f.X, 0, f.Z)
		if f.Magnitude < 0.05 then return nil end
		return f.Unit
	end

	-- One Heartbeat: gentle anti-rollover stabilizer + smooth accelerator + limiter.
	local lastInfoRefresh = 0
	local function assistStep(dt)
		if not Toggles.vehicleAssist.Value then clearGyro(); return end
		local _, primary = ensureVehicle()
		if not primary then clearGyro(); return end
		dt = dt or 1/60

		-- Keep the Info readout current while you're driving (throttled). (F5)
		if tick() - lastInfoRefresh > 0.5 then
			lastInfoRefresh = tick()
			if refreshVehicleDetection then pcall(refreshVehicleDetection) end
		end

		local vel = primary.AssemblyLinearVelocity
		local cf = primary.CFrame

		-- ===== Stabilizer: GENTLE anti-rollover ONLY =====
		-- Only nudges the car upright when it tips past a threshold, with light torque,
		-- so normal driving/leaning/steering is never fought. No velocity rewriting, so
		-- it can't make the car float or skate (the old grip+stiff-gyro problem).
		if (Toggles.vehicleStabilizer == nil) or Toggles.vehicleStabilizer.Value then
			local up = cf.UpVector
			local tiltDeg = math.deg(math.acos(math.clamp(up:Dot(Vector3.new(0, 1, 0)), -1, 1)))
			local gyro = primary:FindFirstChild("CryptsHBE_StabGyro")
			if tiltDeg > 35 then
				if not gyro then
					gyro = Instance.new("BodyGyro")
					gyro.Name = "CryptsHBE_StabGyro"
					gyro.Parent = primary
				end
				gyro.P = 2200          -- light: a nudge, not a clamp
				gyro.D = 500
				gyro.MaxTorque = Vector3.new(9000, 0, 9000)
				local _, yaw = cf:ToEulerAnglesYXZ()
				gyro.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, yaw, 0)
			elseif gyro then
				gyro:Destroy()        -- upright enough: stop fighting entirely
			end
		else
			local g = primary:FindFirstChild("CryptsHBE_StabGyro")
			if g then g:Destroy() end
		end

		-- ===== Accelerator: smooth ramp to Top Speed =====
		-- Adjusts only the FORWARD component of velocity, gradually, and ONLY while you
		-- are already driving -- so it feels like natural power, keeps your steering, and
		-- never shocks the suspension or auto-creeps when parked.
		if Toggles.vehicleAccelerator and Toggles.vehicleAccelerator.Value then
			local fwd = drivingForward(primary, vel)
			local horizSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if fwd and horizSpeed > 4 then
				local top = (Options.vehicleTopSpeed and Options.vehicleTopSpeed.Value) or 120
				local fSpeed = vel:Dot(fwd)
				if fSpeed >= 0 and fSpeed < top then
					local rate = (Options.vehicleAccelRate and Options.vehicleAccelRate.Value) or 80
					local newF = math.min(top, fSpeed + rate * dt)
					primary.AssemblyLinearVelocity = vel + fwd * (newF - fSpeed)
					vel = primary.AssemblyLinearVelocity
				end
			end
		end

		-- ===== Speed limiter (independent of stabilizer) =====
		if Toggles.vehicleSpeedLimiter.Value then
			local cap = Options.vehicleSpeedCap.Value
			local horiz = Vector3.new(vel.X, 0, vel.Z)
			if horiz.Magnitude > cap then
				local capped = horiz.Unit * cap
				primary.AssemblyLinearVelocity = Vector3.new(capped.X, vel.Y, capped.Z)
			end
		end
	end

	-- Speed jolt: an impulse via AssemblyLinearVelocity (no persistent BodyVelocity),
	-- so wheel physics on advanced chassis aren't fought/broken (the old tire bug).
	-- The limiter clamps it next frame; with the limiter off it's a full "jet".
	local function speedJolt()
		-- Works whenever the master toggle is on -- the auto-stabilizer is NOT required. (F2)
		if not Toggles.vehicleAssist.Value then return end
		local _, primary = ensureVehicle()
		if not primary then return end
		local power = Options.vehicleJoltPower.Value
		-- "In car's units" mode: Jolt Power is a % of the car's auto-detected top
		-- speed, so one tap feels consistent across slow and fast vehicles. (F2)
		if Toggles.vehicleJoltRelative and Toggles.vehicleJoltRelative.Value and detectSpeedSystem then
			local sys = detectSpeedSystem()
			if sys and sys.maxSpeed and sys.maxSpeed > 0 then
				power = sys.maxSpeed * (Options.vehicleJoltPower.Value / 100)
			end
		end
		-- Push along the way you're actually DRIVING (velocity-aligned when moving, else
		-- chassis facing) so the jolt never throws the car off to a fixed side. (fix)
		local vel = primary.AssemblyLinearVelocity
		local fwd = drivingForward(primary, vel) or primary.CFrame.LookVector
		local newVel = vel + fwd * power
		-- Anti-fling: a single jolt can never produce an absurd velocity.
		if newVel.Magnitude > 2000 then newVel = newVel.Unit * 2000 end
		primary.AssemblyLinearVelocity = newVel
	end

	refreshVehicleDetection = function()
		currentVehicle = detectVehicle()
		if not currentVehicle then
			vehicleInfoLabel:SetText("Current Vehicle: None")
			return
		end
		local root = currentVehicle:FindFirstAncestorWhichIsA("Model") or currentVehicle
		local _, primary = vehicleRootAndPrimary()
		local vtype = identifyVehicleType(currentVehicle)
		local src = (Toggles.vehicleManualMode and Toggles.vehicleManualMode.Value) and "manual" or "auto"
		local sys = detectSpeedSystem()
		local speedTxt = "physics"
		if sys then
			if sys.kind == "VehicleSeat" then speedTxt = "Seat top " .. math.floor(sys.maxSpeed or 0)
			else speedTxt = sys.kind end
		end
		vehicleInfoLabel:SetText(string.format("Vehicle: %s | %s (%s) | %s | part: %s",
			root.Name or "?", vtype, src, speedTxt, primary and primary.Name or "?"))
	end

	-- Triple-tap detection: 3 quick taps of the jolt key flip Vehicle Assist when the
	-- option is on; otherwise every press just jolts. (F3)
	local joltTapTimes = {}
	Options.vehicleJoltKey:OnClick(function()
		if Toggles.vehicleTripleTap and Toggles.vehicleTripleTap.Value then
			local now = tick()
			joltTapTimes[#joltTapTimes + 1] = now
			while #joltTapTimes > 0 and now - joltTapTimes[1] > 0.6 do table.remove(joltTapTimes, 1) end
			if #joltTapTimes >= 3 then
				joltTapTimes = {}
				pcall(function()
					Toggles.vehicleAssist:SetValue(not Toggles.vehicleAssist.Value)
					Library:Notify("Vehicle Assist " .. (Toggles.vehicleAssist.Value and "ON" or "OFF") .. " (triple-tap)")
				end)
				return
			end
		end
		pcall(speedJolt)
	end)

	Toggles.vehicleAssist:OnChanged(function()
		if Toggles.vehicleAssist.Value then
			refreshVehicleDetection()
			if not assistConn then assistConn = RunService.Heartbeat:Connect(function(dt) pcall(function() assistStep(dt) end) end) end
		else
			if assistConn then assistConn:Disconnect(); assistConn = nil end
			removeVehiclePhysics()
		end
	end)

	-- ===== Tool expander logic =====
	-- originalToolSizes[tool][part] now stores a RECORD { Size, CanCollide, CanTouch,
	-- Massless } captured before we touch the part, so restore returns it exactly.
	local originalToolSizes = setmetatable({}, { __mode = "k" })

	-- Restore one tool's saved parts to their captured originals (size + the collision/
	-- touch/mass props the MELEE-COLLIDE option changes). Used by every restore path.
	local function restoreToolRecord(saved)
		if not saved then return end
		for part, rec in pairs(saved) do
			if part and part.Parent then
				pcall(function()
					if typeof(rec) == "Vector3" then
						part.Size = rec  -- legacy shape (size only), just in case
					else
						part.Size = rec.Size
						if rec.CanCollide ~= nil then part.CanCollide = rec.CanCollide end
						if rec.CanTouch ~= nil then part.CanTouch = rec.CanTouch end
						if rec.Massless ~= nil then part.Massless = rec.Massless end
					end
				end)
			end
		end
	end

	local function shouldExpandPart(part)
		local filter = Options.toolPartFilter:GetActiveValues()
		if table.find(filter, "All") then return true end
		for _, pat in ipairs(filter) do
			if string.find(part.Name:lower(), pat:lower()) then return true end
		end
		return false
	end

	local function expandTool(tool, expand, force)
		if expand then
			-- `force` skips the active-list gate (used by Auto-Add on Equip, F8).
			if not force and not table.find(Options.expandedWeapons:GetActiveValues(), tool.Name) then return end
			local scale = Options.toolExpandSize.Value
			local nonCollide = Toggles.toolNonCollide and Toggles.toolNonCollide.Value
			for _, part in ipairs(tool:GetDescendants()) do
				if part:IsA("BasePart") and shouldExpandPart(part) then
					originalToolSizes[tool] = originalToolSizes[tool] or {}
					local rec = originalToolSizes[tool][part]
					if not rec then
						rec = { Size = part.Size, CanCollide = part.CanCollide, CanTouch = part.CanTouch, Massless = part.Massless }
						originalToolSizes[tool][part] = rec
					end
					part.Size = rec.Size * scale
					-- MELEE-COLLIDE: the enlarged hitbox is non-collidable (won't shove
					-- you/objects or snag) but keeps CanTouch on so the game's own
					-- Handle.Touched damage still fires, and Massless so it can't drag
					-- your character around. Applied BOTH ways so toggling the option
					-- off re-collides an already-expanded tool. Full originals are
					-- restored via restoreToolRecord on un-expand/unload.
					if nonCollide then
						part.CanCollide = false
						part.CanTouch = true
						part.Massless = true
					else
						part.CanCollide = rec.CanCollide
						part.CanTouch = rec.CanTouch
						part.Massless = rec.Massless
					end
				end
			end
		else
			restoreToolRecord(originalToolSizes[tool])
			originalToolSizes[tool] = nil
		end
	end

	applyToolExpansion = function()
		if not Toggles.toolExpanderEnabled.Value then return end
		local char = lPlayer.Character
		if not char then return end
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then expandTool(tool, true) end
		end
	end

	-- Add a tool name to Active Weapons (merge into the available values and tick it as
	-- selected) so an auto-detected tool shows up and stays selectable later. (F8)
	local function addToolToList(name)
		if not name or name == "" then return end
		local vals = Options.expandedWeapons.Values or {}
		if not table.find(vals, name) then
			table.insert(vals, name)
			Options.expandedWeapons.Values = vals
			Options.expandedWeapons:SetValues()
		end
		pcall(function()
			local sel = Options.expandedWeapons.Value
			if type(sel) == "table" and not sel[name] then
				sel[name] = true
				Options.expandedWeapons:SetValue(sel)
			end
		end)
	end

	-- TOOL-OVERHAUL: one-click "add the tool I'm holding to the list AND expand it
	-- now", so you don't have to find its name in the dropdown first.
	expanderGroup:AddButton("Add & Expand Held Weapon", function()
		local char = lPlayer.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		if not tool then Library:Notify("Equip a tool first"); return end
		addToolToList(tool.Name)
		if not Toggles.toolExpanderEnabled.Value then Toggles.toolExpanderEnabled:SetValue(true) end
		expandTool(tool, true, true)
		Library:Notify("Expanding: " .. tool.Name)
	end):AddToolTip("Add the currently-held tool to the active list and expand its hitbox immediately.")

	local function hookTool(tool)
		track(tool.Equipped:Connect(function()
			-- Auto-Add on Equip: detect & handle the equipped tool with no manual scan. (F8)
			if Toggles.toolAutoScanEquip and Toggles.toolAutoScanEquip.Value then
				addToolToList(tool.Name)
				if Toggles.toolExpanderEnabled.Value then expandTool(tool, true, true) end
			elseif Toggles.toolExpanderEnabled.Value and Toggles.toolAutoApply.Value then
				expandTool(tool, true)
			end
		end))
		track(tool.Unequipped:Connect(function() expandTool(tool, false) end))
	end
	local function scanContainer(container)
		if not container then return end
		for _, t in ipairs(container:GetChildren()) do if t:IsA("Tool") then hookTool(t) end end
		track(container.ChildAdded:Connect(function(c) if c:IsA("Tool") then hookTool(c) end end))
	end
	scanContainer(lPlayer.Character)
	scanContainer(lPlayer:FindFirstChild("Backpack"))
	track(lPlayer.CharacterAdded:Connect(function(char)
		scanContainer(char)
		scanContainer(lPlayer:FindFirstChild("Backpack"))
	end))

	Toggles.toolExpanderEnabled:OnChanged(function()
		if Toggles.toolExpanderEnabled.Value then
			applyToolExpansion()
		else
			for tool, saved in pairs(originalToolSizes) do
				restoreToolRecord(saved)
				originalToolSizes[tool] = nil
			end
		end
	end)

	-- ===== Cleanup (Bridge teardown) =====
	Bridge:RegisterAddon("Misc", {
		onUnload = function()
			for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
			if assistConn then pcall(function() assistConn:Disconnect() end) end
			pcall(removeVehiclePhysics)
			for tool, saved in pairs(originalToolSizes) do
				restoreToolRecord(saved)
			end
		end,
	})

	print("[Physics] solver warm-up complete")
end)

-- ----- Manual Vehicle HBE (Main tab) ----------------------------------------
-- A standalone hitbox extender for a vehicle/part you pick by aiming at it and
-- clicking -- separate from the player extender, the world-part scanner and the
-- Misc speed module. It re-applies an additive size each frame (storing the real
-- size once, so it never corrupts the original and restores cleanly).
pcall(function()
	local lPlayer = Players.LocalPlayer
	local mvGroup = (Bridge.MiscTab or mainTab):AddRightGroupbox("Manual Vehicle HBE")
	mvGroup:AddToggle("mvHbeEnabled", { Text = "Enable Manual Vehicle HBE", Default = false, Tooltip = "Extend the hitbox of a vehicle/part you pick manually\n(independent of every other extender). (Default: OFF)" })
	mvGroup:AddSlider("mvHbeSize", { Text = "Added Size (studs)", Min = 1, Max = 250, Default = 20, Rounding = 1, Tooltip = "Studs added to the picked part's size. (Default: 20)" })
	mvGroup:AddSlider("mvHbeTransparency", { Text = "Transparency", Min = 0, Max = 1, Default = 0.6, Rounding = 2 })
	mvGroup:AddToggle("mvHbeCollisions", { Text = "Keep Collisions", Default = false, Tooltip = "Leave the extended part collidable. (Default: OFF)" })
	mvGroup:AddToggle("mvHbeWholeModel", { Text = "Whole Model", Default = false, Tooltip = "Extend every BasePart of the picked vehicle's model,\nnot just the one part. (Default: OFF)" })
	local mvInfo = mvGroup:AddLabel("Picked: none")

	local pickedPart = nil
	local extended = {}     -- [BasePart] = { Size, Transparency, CanCollide }

	local function restore()
		for part, orig in pairs(extended) do
			if typeof(part) == "Instance" and part.Parent then
				pcall(function() part.Size = orig.Size; part.Transparency = orig.Transparency; part.CanCollide = orig.CanCollide end)
			end
			extended[part] = nil
		end
	end

	local function targetParts()
		if not pickedPart or not pickedPart.Parent then return {} end
		if Toggles.mvHbeWholeModel.Value then
			local model = pickedPart:FindFirstAncestorWhichIsA("Model") or pickedPart
			local t = {}
			for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then t[#t + 1] = d end end
			if #t == 0 and pickedPart:IsA("BasePart") then t[1] = pickedPart end
			return t
		end
		return pickedPart:IsA("BasePart") and { pickedPart } or {}
	end

	local function apply()
		local add = Options.mvHbeSize.Value
		local transp = Options.mvHbeTransparency.Value
		local keepCol = Toggles.mvHbeCollisions.Value
		local desired = {}
		for _, part in ipairs(targetParts()) do desired[part] = true end
		for part, orig in pairs(extended) do
			if not desired[part] then
				if typeof(part) == "Instance" and part.Parent then
					pcall(function() part.Size = orig.Size; part.Transparency = orig.Transparency; part.CanCollide = orig.CanCollide end)
				end
				extended[part] = nil
			end
		end
		for part in pairs(desired) do
			local e = extended[part]
			if not e then
				e = { Size = part.Size, Transparency = part.Transparency, CanCollide = part.CanCollide }
				extended[part] = e
			end
			pcall(function()
				part.Size = e.Size + Vector3.new(add, add, add)
				part.Transparency = transp
				part.CanCollide = keepCol and true or e.CanCollide
			end)
		end
	end

	mvGroup:AddButton("Pick Vehicle (hold-click)", function()
		Bridge:StartHoldPick({
			color = Color3.fromRGB(255, 170, 0),
			onPick = function(part)
				restore()                   -- drop the previous pick cleanly first
				pickedPart = part
				local model = part:FindFirstAncestorWhichIsA("Model")
				mvInfo:SetText("Picked: " .. (model and model.Name or part.Name))
				Library:Notify("Picked vehicle: " .. (model and model.Name or part.Name))
			end,
		})
	end):AddToolTip("Aim at a vehicle and HOLD left-click until the ring fills to select it (right-click cancels)")

	mvGroup:AddButton("Clear Pick", function()
		restore()
		pickedPart = nil
		mvInfo:SetText("Picked: none")
	end):AddToolTip("Restore and forget the picked vehicle")

	Toggles.mvHbeEnabled:OnChanged(function()
		if not Toggles.mvHbeEnabled.Value then restore() end
	end)

	local hbConn = RunService.Heartbeat:Connect(function()
		if pickedPart and not pickedPart.Parent then
			restore(); pickedPart = nil; mvInfo:SetText("Picked: none")
			return
		end
		if Toggles.mvHbeEnabled.Value and pickedPart then pcall(apply) end
	end)

	-- ---- VEH-MOD: gas / health / top-speed on the picked vehicle ----------
	-- Reuses the picked vehicle (above). Detects fuel/health/speed NumberValues +
	-- numeric attributes + VehicleSeat.MaxSpeed on the model and lets you pin them.
	-- "Infinite" holds each value at the highest it's ever been (auto-calibrates to
	-- full after one refuel/repair); Top Speed writes a chosen value.
	local vmGroup = (Bridge.MiscTab or mainTab):AddRightGroupbox("Vehicle Modify (picked)")
	vmGroup:AddToggle("vmInfGas",     { Text = "Infinite Gas/Fuel", Default = false, Tooltip = "Hold detected fuel/gas values at full. (Default: OFF)" })
	vmGroup:AddToggle("vmFullHealth", { Text = "Full Health/Durability", Default = false, Tooltip = "Hold detected health/durability values at full. (Default: OFF)" })
	vmGroup:AddToggle("vmSetSpeed",   { Text = "Set Top Speed", Default = false, Tooltip = "Write the speed below to detected speed values + VehicleSeat.MaxSpeed. (Default: OFF)" })
	vmGroup:AddSlider("vmTopSpeed",   { Text = "Top Speed", Min = 10, Max = 1000, Default = 200, Rounding = 0, Tooltip = "Value written when Set Top Speed is on. (Default: 200)" })
	vmGroup:AddToggle("vmSpeedMult",  { Text = "Speed Boost (multiplier)", Default = false, Tooltip = "Multiply the vehicle's ORIGINAL top speed by the factor below\n(relative to stock, captured on detect -- doesn't compound). (Default: OFF)" })
	vmGroup:AddSlider("vmSpeedMultX", { Text = "Speed Multiplier", Min = 1, Max = 5, Default = 2, Rounding = 1, Tooltip = "e.g. 5 = five times the stock top speed. (Default: 2)" })
	vmGroup:AddToggle("vehWheelBoost", { Text = "Wheel Motor Boost (physics)", Default = false, Tooltip = "For vehicles with NO speed value (driven by Cylindrical/Hinge\nwheel motors). Raises the wheel motors' spin + torque AND\namplifies the vehicle's current velocity toward Multiplierx60.\nUses the Speed Multiplier slider. EXPERIMENTAL; needs network\nownership to stick -- watch the Owner readout. (Default: OFF)" })
	-- Handling panel (screenshot-style). Writes to the detected VehicleSeat + any
	-- matching tune NumberValues/attributes on the vehicle YOU drive (you own its
	-- network, so the writes replicate). Auto-detected when you pick a vehicle.
	vmGroup:AddToggle("vehBoost",           { Text = "Speed Boost", Default = false, Tooltip = "Master switch for the handling sliders below. (Default: OFF)" })
	vmGroup:AddSlider("vehTargetSpeed",     { Text = "Target Speed", Min = 0, Max = 500, Default = 95, Rounding = 0, Tooltip = "Writes VehicleSeat.MaxSpeed + detected speed values. (Default: 95)" })
	vmGroup:AddSlider("vehAccel",           { Text = "Acceleration", Min = 0, Max = 100, Default = 1, Rounding = 0, Tooltip = "Writes VehicleSeat.Torque + detected torque/accel values. (Default: 1)" })
	vmGroup:AddSlider("vehTurnRate",        { Text = "Turn Rate", Min = 0, Max = 100, Default = 3, Rounding = 0, Tooltip = "Writes VehicleSeat.TurnSpeed + detected turn values. (Default: 3)" })
	vmGroup:AddSlider("vehTurnAngle",       { Text = "Turn Angle", Min = 0, Max = 90, Default = 16, Rounding = 0, Tooltip = "Writes detected steer-angle values (A-Chassis style). (Default: 16)" })
	vmGroup:AddSlider("vehTurnAccel",       { Text = "Turn Acceleration", Min = 0, Max = 100, Default = 3, Rounding = 0, Tooltip = "Writes detected turn-acceleration values. (Default: 3)" })
	vmGroup:AddToggle("vehStability",       { Text = "Stability Assist", Default = false, Tooltip = "Keep the vehicle upright (anti-rollover) via AlignOrientation. (Default: OFF)" })
	vmGroup:AddSlider("vehStabilityStrength", { Text = "Stability Strength", Min = 0, Max = 1, Default = 0.65, Rounding = 2, Tooltip = "How aggressively stability holds you upright. (Default: 0.65)" })
	vmGroup:AddToggle("vehKeepOwnership", { Text = "Keep Ownership (sim radius)", Default = false, Tooltip = "Raise your simulation radius (setsimulationradius) so you keep\nnetwork ownership of the vehicle -- makes the tuning writes far\nmore likely to stick. May be detectable; off by default. (Default: OFF)" })
	local vmInfo = vmGroup:AddLabel("Detected: sit in a vehicle, or hold-pick one", true)
	-- Live confidence readout: are your writes even going to stick? Shows whether
	-- YOU own the vehicle's network (writes replicate) vs the server, and whether a
	-- written value actually held (server didn't revert it).
	local vmStatus = vmGroup:AddLabel("Owner: -", true)

	local GAS_WORDS       = { "fuel", "gas", "gasoline", "petrol", "diesel" }
	local HEALTH_WORDS    = { "health", "durability", "integrity", "hp" }
	local TURNACCEL_WORDS = { "turnaccel", "turnacceleration", "steeracceleration" }
	local TURN_WORDS      = { "turnspeed", "turnrate", "steerspeed", "returnspeed" }
	local STEER_WORDS     = { "maxsteer", "steerangle", "turnangle", "steerinner", "steerouter" }
	local TORQUE_WORDS    = { "torque", "acceleration", "accel", "horsepower" }
	local SPEED_WORDS     = { "maxspeed", "topspeed", "speed", "velocity" }
	local function nameHasW(n, words) n = n:lower() for _, w in ipairs(words) do if n:find(w) then return true end end return false end
	-- Order matters: turn/steer must be checked before plain "speed" so "TurnSpeed"
	-- doesn't get mis-bucketed as top speed.
	local function classifyVal(name)
		if nameHasW(name, GAS_WORDS) then return "gas" end
		if nameHasW(name, HEALTH_WORDS) then return "health" end
		if nameHasW(name, TURNACCEL_WORDS) then return "turnaccel" end
		if nameHasW(name, TURN_WORDS) then return "turn" end
		if nameHasW(name, STEER_WORDS) then return "steer" end
		if nameHasW(name, TORQUE_WORDS) then return "torque" end
		if nameHasW(name, SPEED_WORDS) then return "speed" end
		return nil
	end
	local function fieldVal(v)  return { read = function() return v.Value end, write = function(n) pcall(function() v.Value = n end) end } end
	local function fieldAttr(i, a) return { read = function() return i:GetAttribute(a) end, write = function(n) pcall(function() i:SetAttribute(a, n) end) end } end
		local function fieldTbl(t, k) return { read = function() return t[k] end, write = function(n) pcall(function() t[k] = n end) end } end
	-- If nothing was hold-picked, fall back to the vehicle you're SITTING in -- so tuning
	-- works the moment you're in a car without a manual pick (the old flow left "Detected:
	-- pick a vehicle" / "Owner: -" and the sliders had nothing to write to).
	local function seatedVehicleModel()
		local char = lPlayer.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		local seat = hum and hum.SeatPart
		if seat and seat.Parent then return seat:FindFirstAncestorWhichIsA("Model") or seat end
		return nil
	end
	local function pickedModel()
		if pickedPart then return pickedPart:FindFirstAncestorWhichIsA("Model") or pickedPart end
		return seatedVehicleModel()
	end
	local function vmPrimary()
		local m = pickedModel(); if not m then return nil end
		return m.PrimaryPart or (pickedPart and pickedPart:IsA("BasePart") and pickedPart) or m:FindFirstChildWhichIsA("BasePart")
	end

	local vmB = { gas = {}, health = {}, speed = {}, torque = {}, turn = {}, steer = {}, turnaccel = {} }
	local vmSeats, vmMaxSeen, vmIsAChassis = {}, {}, false
	local vmSpeedBase = {}  -- [seat or speed-field] = stock top speed, captured on detect (so the multiplier is relative to stock, not compounding)
	-- Physics drive: many vehicles (TREK, constraint chassis) have NO speed Value -- they
	-- move via CylindricalConstraint/HingeConstraint wheel motors, so MaxSpeed writes do
	-- nothing. Detect those + suspension/body-movers so we can report the real drive system
	-- and boost the motors (the actual top-speed lever).
	local vmMotors, vmMotorBase = {}, {}   -- driven Cylindrical/Hinge constraints + their stock MotorMaxTorque
	local vmPhysics = { cyl = 0, hinge = 0, spring = 0, mover = 0 }
	local function detectVehMod()
		vmB = { gas = {}, health = {}, speed = {}, torque = {}, turn = {}, steer = {}, turnaccel = {} }
		vmSeats, vmMaxSeen, vmIsAChassis = {}, {}, false
		vmSpeedBase = {}; vmMotors, vmMotorBase = {}, {}
		vmPhysics = { cyl = 0, hinge = 0, spring = 0, mover = 0 }
		local m = pickedModel()
		if not m then pcall(function() vmInfo:SetText("Detected: none -- sit in a vehicle or hold-pick one") end); return end
		for _, d in ipairs(m:GetDescendants()) do
			if isNumericValue(d) then
				local b = classifyVal(d.Name); if b then table.insert(vmB[b], fieldVal(d)) end
			elseif d:IsA("VehicleSeat") then vmSeats[#vmSeats + 1] = d
			elseif d:IsA("CylindricalConstraint") then
				vmPhysics.cyl = vmPhysics.cyl + 1
				vmMotors[#vmMotors + 1] = d; pcall(function() vmMotorBase[d] = d.MotorMaxTorque end)
			elseif d:IsA("HingeConstraint") then
				vmPhysics.hinge = vmPhysics.hinge + 1
				if d.ActuatorType == Enum.ActuatorType.Motor then vmMotors[#vmMotors + 1] = d; pcall(function() vmMotorBase[d] = d.MotorMaxTorque end) end
			elseif d:IsA("SpringConstraint") then vmPhysics.spring = vmPhysics.spring + 1
			elseif d:IsA("BodyVelocity") or d:IsA("LinearVelocity") or d:IsA("VectorForce") or d:IsA("BodyThrust") then vmPhysics.mover = vmPhysics.mover + 1
				elseif d:IsA("ModuleScript") and (d.Name == "Tune" or d.Name:lower():find("chassis")) then
					-- A-Chassis: require the (pure-data) Tune module and expose numeric keys
					-- as writable fields so the handling sliders can drive its tune.
					pcall(function()
						local tune = require(d)
						if type(tune) == "table" then
							vmIsAChassis = true
							for k, val in pairs(tune) do
								if type(val) == "number" then
									local b = classifyVal(tostring(k)); if b then table.insert(vmB[b], fieldTbl(tune, k)) end
								end
							end
						end
					end)
				end
			pcall(function()
				for an, av in pairs(d:GetAttributes()) do
					if type(av) == "number" then local b = classifyVal(an); if b then table.insert(vmB[b], fieldAttr(d, an)) end end
				end
			end)
		end
		-- Capture stock top speed (seats + detected speed fields) for the multiplier.
		for _, s in ipairs(vmSeats) do pcall(function() vmSpeedBase[s] = s.MaxSpeed end) end
		for _, f in ipairs(vmB.speed) do pcall(function() local v = f.read(); if type(v) == "number" then vmSpeedBase[f] = v end end) end
		-- Diagnose how the vehicle actually moves so you know which control will work.
		local drive
		if #vmB.speed > 0 or #vmSeats > 0 then drive = "value/seat-based -> Set Top Speed works"
		elseif #vmMotors > 0 then drive = "PHYSICS (wheel motors) -> use Wheel Motor Boost"
		elseif vmPhysics.mover > 0 then drive = "force-based (body movers) -> writes may not stick"
		else drive = "unknown" end
		pcall(function() vmInfo:SetText(
			("%sGas:%d HP:%d Spd:%d Trq:%d Turn:%d Seats:%d\nPhysics: %d motors, %d springs, %d movers\nDrive: %s"):format(
				vmIsAChassis and "[A-Chassis] " or "", #vmB.gas, #vmB.health, #vmB.speed, #vmB.torque, #vmB.turn, #vmSeats,
				#vmMotors, vmPhysics.spring, vmPhysics.mover, drive)) end)
	end
	vmGroup:AddButton("Detect Values", detectVehMod):AddToolTip("Scan the picked vehicle for fuel/health/speed/handling values to modify.")
	vmGroup:AddButton("Deep-Dump Picked Vehicle", function()
		local m = pickedModel()
		if not m then Library:Notify("Sit in a vehicle or hold-pick one first"); return end
		Bridge:DeepDumpModel(m, "Vehicle", "vehicle_dump_" .. tostring(game.PlaceId) .. ".txt",
			{ "speed", "velocity", "throttle", "torque", "power", "engine", "drive", "rpm", "gear", "accel", "chassis", "vehicle", "car", "fuel", "gas" })
	end):AddToolTip("Write the picked/seated vehicle's full structure + its scripts' constants +\nvehicle remotes to workspace/CryptsHBE/ -- the data to find the real speed governor.")

		-- Extended Deep Dive is provided by the optional DeepDive plugin (heavier analysis:
		-- required-module dumps, remote-arg inference, operator-tool correlation). This
		-- sub-button drives it when loaded, else points you to enable it.
		vmGroup:AddButton("Extended Deep Dive", function()
			local b = getgenv().CryptsHBE
			local ed = b and b.ExtendedDump
			if ed and type(ed.vehicle) == "function" then
				local m = pickedModel()
				if not m then Library:Notify("Sit in a vehicle or hold-pick one first"); return end
				pcall(ed.vehicle, m)
			else
				Library:Notify("Enable the 'DeepDive' plugin first (Plugins tab)")
			end
		end):AddToolTip("Heavier reverse-engineering pass on the picked vehicle (requires the DeepDive plugin):\nrequired-module values, remote-arg inference, turret/operator-tool correlation.")

	local function holdMax(list)
		for _, f in ipairs(list) do
			local v = f.read()
			if type(v) == "number" then vmMaxSeen[f] = math.max(vmMaxSeen[f] or v, v); f.write(vmMaxSeen[f]) end
		end
	end
	local function writeAll(list, n) for _, f in ipairs(list) do f.write(n) end end

	-- Stability assist: AlignOrientation that keeps the vehicle upright (preserving
	-- yaw), responsiveness scaled by strength. Tracked so it tears down cleanly.
	local vmStabPart = nil
	local function clearStab()
		if vmStabPart then
			pcall(function()
				local ao = vmStabPart:FindFirstChild("CryptsHBE_StabAO"); if ao then ao:Destroy() end
				local att = vmStabPart:FindFirstChild("CryptsHBE_StabAtt"); if att then att:Destroy() end
			end)
			vmStabPart = nil
		end
	end
	local function applyStab(primary, strength)
		if vmStabPart and vmStabPart ~= primary then clearStab() end
		if not (primary and primary.Parent) then return end
		local att = primary:FindFirstChild("CryptsHBE_StabAtt")
		if not att then att = Instance.new("Attachment"); att.Name = "CryptsHBE_StabAtt"; att.Parent = primary end
		local ao = primary:FindFirstChild("CryptsHBE_StabAO")
		if not ao then
			ao = Instance.new("AlignOrientation"); ao.Name = "CryptsHBE_StabAO"
			ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
			ao.Attachment0 = att; ao.RigidityEnabled = false; ao.Parent = primary
		end
		ao.MaxTorque = 1e6
		ao.Responsiveness = math.clamp(strength * 200, 5, 200)
		local look = primary.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
		ao.CFrame = CFrame.lookAt(Vector3.new(0, 0, 0), flat.Unit)
		vmStabPart = primary
	end

	local vmLastModel, vmStatusT, vmWheelWasOn = nil, 0, false
	local vmConn = RunService.Heartbeat:Connect(function()
		local m = pickedModel()
		if m ~= vmLastModel then vmLastModel = m; clearStab(); detectVehMod() end  -- auto re-detect + restabilise on new pick
		if not m then clearStab(); return end
		if Toggles.vmInfGas and Toggles.vmInfGas.Value then holdMax(vmB.gas) end
		if Toggles.vmFullHealth and Toggles.vmFullHealth.Value then holdMax(vmB.health) end
		if Toggles.vmSetSpeed and Toggles.vmSetSpeed.Value then
			local sp = Options.vmTopSpeed.Value
			writeAll(vmB.speed, sp)
			for _, s in ipairs(vmSeats) do if s.Parent then pcall(function() s.MaxSpeed = sp end) end end
		end
		-- Speed Boost multiplier: stock top speed x factor (relative to the captured base).
		if Toggles.vmSpeedMult and Toggles.vmSpeedMult.Value then
			local x = Options.vmSpeedMultX.Value
			for _, s in ipairs(vmSeats) do if s.Parent and vmSpeedBase[s] then pcall(function() s.MaxSpeed = vmSpeedBase[s] * x end) end end
			for _, f in ipairs(vmB.speed) do if vmSpeedBase[f] then pcall(function() f.write(vmSpeedBase[f] * x) end) end end
		end
		-- Wheel Motor Boost: scale physics wheel-motor spin (no speed value exists). Live-
		-- multiply AngularVelocity (clamped, sign-preserving so direction holds) and raise
		-- MotorMaxTorque so the wheels can reach the higher spin. Restores torque on off.
		if Toggles.vehWheelBoost and Toggles.vehWheelBoost.Value then
			vmWheelWasOn = true
			local x = Options.vmSpeedMultX.Value
			-- 1) wheel motors: raise spin target + torque + accel so the wheels can reach it.
			for _, c in ipairs(vmMotors) do
				if c.Parent then pcall(function()
					c.MotorMaxTorque = math.max(vmMotorBase[c] or 0, (vmMotorBase[c] or 0) * x, 100000)
					pcall(function() c.MotorMaxAngularAcceleration = math.max(c.MotorMaxAngularAcceleration, 1e6) end)
					pcall(function() c.MotorMaxAcceleration = math.max(c.MotorMaxAcceleration, 1e6) end)  -- HingeConstraint variant
					c.AngularVelocity = math.clamp(c.AngularVelocity * x, -1000, 1000)
				end) end
			end
			-- 2) velocity force: amplify the vehicle's CURRENT horizontal motion toward a cap
			-- (Y preserved so gravity/suspension still work; only while already moving so it
			-- can't launch you from a standstill). This is what actually moves a server-driven
			-- chassis -- IF you own its network (watch the Owner readout).
			local prim = vmPrimary()
			if prim then pcall(function()
				local v = prim.AssemblyLinearVelocity
				local h = Vector3.new(v.X, 0, v.Z)
				if h.Magnitude > 5 then
					prim.AssemblyLinearVelocity = h.Unit * math.min(h.Magnitude * x, 60 * x) + Vector3.new(0, v.Y, 0)
				end
			end) end
		elseif vmWheelWasOn then
			vmWheelWasOn = false
			for _, c in ipairs(vmMotors) do if c.Parent and vmMotorBase[c] then pcall(function() c.MotorMaxTorque = vmMotorBase[c] end) end end
		end
		-- Handling panel (screenshot-style).
		if Toggles.vehBoost and Toggles.vehBoost.Value then
			local ts, ac, tr = Options.vehTargetSpeed.Value, Options.vehAccel.Value, Options.vehTurnRate.Value
			local ta, tac = Options.vehTurnAngle.Value, Options.vehTurnAccel.Value
			for _, s in ipairs(vmSeats) do if s.Parent then pcall(function() s.MaxSpeed = ts; s.Torque = ac; s.TurnSpeed = tr end) end end
			writeAll(vmB.speed, ts); writeAll(vmB.torque, ac); writeAll(vmB.turn, tr)
			writeAll(vmB.steer, ta); writeAll(vmB.turnaccel, tac)
		end
		if Toggles.vehStability and Toggles.vehStability.Value then
			applyStab(vmPrimary(), Options.vehStabilityStrength.Value)
		else
			clearStab()
		end
		-- Live confidence readout (throttled): network ownership + did a write hold?
		local now = tick()
		if now - vmStatusT > 0.4 then
			vmStatusT = now
			if Toggles.vehKeepOwnership and Toggles.vehKeepOwnership.Value and setsimulationradius then
				pcall(function() setsimulationradius(1e6, 1e6) end)
			end
			local own = "?"
			local prim = vmPrimary()
			if prim and isnetworkowner then
				local ok, r = pcall(function() return isnetworkowner(prim) end)
				if ok then own = r and "YOU (writes stick)" or "server (writes may not stick)" end
			end
			local applied = ""
			if Toggles.vehBoost and Toggles.vehBoost.Value and vmSeats[1] and vmSeats[1].Parent then
				local ok2, ms = pcall(function() return vmSeats[1].MaxSpeed end)
				if ok2 then applied = (math.abs((ms or 0) - Options.vehTargetSpeed.Value) < 1.5) and "  | speed applied OK" or "  | speed REVERTED" end
			end
			-- Live ACTUAL speed (assembly velocity) so you can see what it really does at
			-- speed -- and, for physics vehicles, the wheel motors' current target spin.
			local spd = 0
			if prim then pcall(function() spd = prim.AssemblyLinearVelocity.Magnitude end) end
			local motorTxt = ""
			if #vmMotors > 0 then
				local av = 0
				pcall(function() av = math.abs(vmMotors[1].AngularVelocity) end)
				motorTxt = ("  | wheel spin %.0f"):format(av)
			end
			pcall(function() vmStatus:SetText(("Owner: %s%s\nActual speed: %.0f sps%s"):format(own, applied, spd, motorTxt)) end)
		end
	end)

	Bridge:RegisterAddon("ManualVehicleHBE", {
		onUnload = function()
			if hbConn then pcall(function() hbConn:Disconnect() end) end
			if vmConn then pcall(function() vmConn:Disconnect() end) end
			pcall(clearStab)
			pcall(restore)
		end,
	})
	print("[Audio] ambient bank loaded")
end)

-- ----- Vehicle ESP (Miscellaneous tab) --------------------------------------
pcall(function()
	local miscTab = Bridge.MiscTab
	if not miscTab then return end
	local lPlayer = Players.LocalPlayer
	local HttpService = game:GetService("HttpService")
	local VE_FILE = "CryptsHBE_VehicleTypes.json"
	local TYPE_COLOR = {
		Car = Color3.fromRGB(255, 255, 255), Helicopter = Color3.fromRGB(0, 255, 255),
		Boat = Color3.fromRGB(80, 160, 255), Plane = Color3.fromRGB(255, 230, 60),
	}

	local g = miscTab:AddLeftGroupbox("Vehicle ESP")
	g:AddToggle("vehicleEspEnabled", { Text = "Enable Vehicle ESP", Default = false, Tooltip = "Draw name + type + distance on registered vehicles. (Default: OFF)" })
	g:AddToggle("vehicleEspAutoTrack", { Text = "Auto-Track Vehicles", Default = true, Tooltip = "Continuously find drivable vehicles (anything with a\nVehicleSeat) and keep the list LIVE -- new spawns are added,\ndestroyed/despawned ones are removed automatically, so it\nnever shows a car you spawned ages ago. (Default: ON)" })
	g:AddToggle("vehicleEspWheelCars", { Text = "Detect Wheel-Cars (no seat)", Default = false, Tooltip = "VEH-ESP2: also track cars that are a single model with no\nVehicleSeat (just tires + body) -- e.g. other players' cars.\nHeuristic (>=2 wheel/tire parts); may occasionally over-match. (Default: OFF)" })
	g:AddDropdown("vehicleEspList", { Text = "Registered Vehicles", Values = {}, Multi = false, AllowNull = true, Tooltip = "Vehicles currently tracked. (Default: none)" })
	g:AddDropdown("vehicleEspType", { Text = "Mark As", Values = { "Car", "Horse", "Helicopter", "Boat", "Plane" }, Default = "Car", Multi = false, AllowNull = false, Tooltip = "Type to tag the selected vehicle with (saved to disk). (Default: Car)" })

	local registered = {}     -- { { model=, name=, type= }, ... }
	local vehicleTypes = {}   -- [name] = type (persisted)
	pcall(function()
		if isfile and readfile and isfile(VE_FILE) then
			local ok, t = pcall(function() return HttpService:JSONDecode(readfile(VE_FILE)) end)
			if ok and type(t) == "table" then vehicleTypes = t end
		end
	end)
	local function saveTypes() if writefile then pcall(function() writefile(VE_FILE, HttpService:JSONEncode(vehicleTypes)) end) end end
	-- Drop registered vehicles whose model was destroyed/despawned, so the list never
	-- shows the car you spawned several respawns ago.
	local function pruneDead()
		local changed = false
		for i = #registered, 1, -1 do
			local m = registered[i].model
			if not (typeof(m) == "Instance" and m.Parent) then
				table.remove(registered, i); changed = true
			end
		end
		return changed
	end
	local function refreshList()
		pruneDead()
		local names = {}
		for _, e in ipairs(registered) do table.insert(names, e.name) end
		Options.vehicleEspList.Values = names
		Options.vehicleEspList:SetValues()
	end
	local function isRegistered(m) for _, e in ipairs(registered) do if e.model == m then return true end end return false end
	-- A mount/horse = named horse/steed/pony/mount, OR has a "Saddle" VehicleSeat, OR
	-- lives under a "Ride" folder (Bleeding Blades parks horses in Workspace.Ride.<name>).
	local function looksLikeHorse(m)
		if not (m and m:IsA("Model")) then return false end
		local n = m.Name:lower()
		if n:find("horse") or n:find("steed") or n:find("pony") or n:find("mount") then return true end
		local seat = m:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat and seat.Name:lower():find("saddle") then return true end
		if m:FindFirstChild("SaddleBase", true) then return true end
		local par = m.Parent
		if par and par.Name == "Ride" then return true end
		return false
	end
	local function registerModel(m)
		if not m or not m:IsA("Model") or isRegistered(m) then return false end
		table.insert(registered, { model = m, name = m.Name, type = vehicleTypes[m.Name] or (looksLikeHorse(m) and "Horse" or "Car") })
		return true
	end
	-- Find every model that contains a VehicleSeat (i.e. a drivable/operatable vehicle).
	local function scanVehicles()
		local added = 0
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("VehicleSeat") then
				local m = d:FindFirstAncestorWhichIsA("Model")
				if m and not isRegistered(m) and registerModel(m) then added = added + 1 end
			end
		end
		return added
	end

	-- VEH-ESP2: heuristic for cars that are ONE model with no VehicleSeat (just tires
	-- + a body), which the VehicleSeat sweep above misses for other players. A model
	-- counts as a wheel-car if it has >=2 wheel/tire-named parts and no Humanoid.
	local WHEEL_WORDS = { "wheel", "tire", "tyre" }
	local function looksLikeWheelCar(m)
		if not (m and m:IsA("Model")) then return false end
		if m:FindFirstChildWhichIsA("Humanoid", true) then return false end   -- it's a character
		if m:FindFirstChildWhichIsA("VehicleSeat", true) then return false end -- already covered
		-- Model-name shortcut for boats/planes/helis that don't have wheels.
		local mn = m.Name:lower()
		if mn:find("boat") or mn:find("ship") or mn:find("heli") or mn:find("plane") or mn:find("jet") then return true end
		local wheels, rotors = 0, 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				local n = d.Name:lower()
				for _, w in ipairs(WHEEL_WORDS) do if n:find(w) then wheels = wheels + 1; break end end
				-- heli/plane rotor or boat propeller/hull also marks a vehicle.
				if n:find("rotor") or n:find("propeller") then rotors = rotors + 1 end
				if n:find("hull") then return true end
				if wheels >= 2 or rotors >= 1 then return true end
			end
		end
		return false
	end
	-- Walk top-level models + one level into folders (where games park vehicles).
	local function eachCandidateModel(cb)
		for _, c in ipairs(Workspace:GetChildren()) do
			if c:IsA("Model") then cb(c)
			elseif c:IsA("Folder") then for _, m in ipairs(c:GetChildren()) do if m:IsA("Model") then cb(m) end end end
		end
	end
	local function scanWheelCars()
		local added = 0
		eachCandidateModel(function(m)
			if not isRegistered(m) and looksLikeWheelCar(m) and registerModel(m) then added = added + 1 end
		end)
		return added
	end

	g:AddButton("Scan Vehicles", function()
		pruneDead()
		local count = scanVehicles()
		if Toggles.vehicleEspWheelCars and Toggles.vehicleEspWheelCars.Value then count = count + scanWheelCars() end
		refreshList()
		Library:Notify("Vehicle ESP: " .. count .. " new (" .. #registered .. " tracked)")
	end):AddToolTip("Find models that contain a VehicleSeat and register them (Auto-Track keeps this live for you)")
	g:AddButton("Register (hold-pick)", function()
		Bridge:StartHoldPick({ color = Color3.fromRGB(0, 255, 170), onPick = function(part)
			local m = part:FindFirstAncestorWhichIsA("Model") or part
			registerModel(m); refreshList(); Library:Notify("Registered vehicle: " .. m.Name)
		end })
	end):AddToolTip("Aim at a vehicle and hold-click to register it")
	g:AddButton("Set Type to Selected", function()
		local sel = Options.vehicleEspList.Value
		if not sel then return end
		for _, e in ipairs(registered) do
			if e.name == sel then e.type = Options.vehicleEspType.Value; vehicleTypes[e.name] = e.type end
		end
		saveTypes(); Library:Notify(sel .. " -> " .. Options.vehicleEspType.Value)
	end):AddToolTip("Tag the selected vehicle as Car/Helicopter/Boat/Plane (saved)")
	g:AddButton("Remove Selected", function()
		local sel = Options.vehicleEspList.Value
		for i = #registered, 1, -1 do if registered[i].name == sel then table.remove(registered, i) end end
		refreshList()
	end)
	g:AddButton("Clear All", function() registered = {}; refreshList() end)

	-- Auto-track: keep the registry live without manual scanning. Throttled so it's
	-- cheap, and only refreshes the dropdown when the set actually changes (so it
	-- won't fight your selection). Prunes destroyed/despawned models too.
	local lastAutoScan = 0
	local autoScanConn = RunService.Heartbeat:Connect(function()
		if not (Toggles.vehicleEspAutoTrack and Toggles.vehicleEspAutoTrack.Value) then return end
		if tick() - lastAutoScan < 1.5 then return end
		lastAutoScan = tick()
		local changed = pruneDead()
		if scanVehicles() > 0 then changed = true end
		if Toggles.vehicleEspWheelCars and Toggles.vehicleEspWheelCars.Value and scanWheelCars() > 0 then changed = true end
		-- Also grab the car YOU are sitting in -- covers single-model cars whose seat
		-- the Workspace sweep might not have matched, so your own vehicle always shows.
		pcall(function()
			local lhum = lPlayer.Character and lPlayer.Character:FindFirstChildWhichIsA("Humanoid")
			if lhum and lhum.SeatPart then
				local m = lhum.SeatPart:FindFirstAncestorWhichIsA("Model")
				if m and not isRegistered(m) and registerModel(m) then changed = true end
			end
		end)
		if changed then refreshList() end
	end)

	local pool = {}
	local function getText(i)
		if not pool[i] then
			local t = DrawingFallback.new("Text")
			t.Center = true; t.Outline = true; t.Size = 14
			pool[i] = t
		end
		return pool[i]
	end
	local function hideFrom(i) for j = i, #pool do pool[j].Visible = false end end

	RunService:BindToRenderStep("CryptsHBE_VehicleESP", Enum.RenderPriority.Camera.Value, function()
		if not Toggles.vehicleEspEnabled.Value then hideFrom(1); return end
		local cam = Workspace.CurrentCamera
		local lchar = lPlayer.Character
		local lroot = lchar and (lchar:FindFirstChild("HumanoidRootPart") or lchar:FindFirstChild("Head"))
		local idx = 0
		for _, e in ipairs(registered) do
			local m = e.model
			if typeof(m) == "Instance" and m.Parent then
				local okp, cf = pcall(function() return m:GetPivot() end)
				if okp and cf then
					local sp, on = cam:WorldToViewportPoint(cf.Position)
					if on then
						idx = idx + 1
						local t = getText(idx)
						local dist = lroot and math.floor((cf.Position - lroot.Position).Magnitude) or 0
						local driver = ""
						pcall(function()
							local seat = m:FindFirstChildWhichIsA("VehicleSeat", true)
							if seat and seat.Occupant then
								local p = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
								driver = p and (" <" .. p.Name .. ">") or " <occupied>"
							end
						end)
						t.Text = e.name .. " [" .. e.type .. "] " .. dist .. "m" .. driver
						t.Position = Vector2.new(sp.X, sp.Y)
						t.Color = TYPE_COLOR[e.type] or Color3.fromRGB(255, 255, 255)
						t.Visible = true
					end
				end
			end
		end
		hideFrom(idx + 1)
	end)

	Bridge:RegisterAddon("VehicleESP", { onUnload = function()
		pcall(function() RunService:UnbindFromRenderStep("CryptsHBE_VehicleESP") end)
		if autoScanConn then pcall(function() autoScanConn:Disconnect() end) end
		for _, t in ipairs(pool) do safeRemoveDrawing(t) end
	end })
	print("[Content] streaming region active")
end)
	end,
	unload = function() end,
}
