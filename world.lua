-- CryptsHBE plugin: World (Fullbright, No Fog, Custom FOV, Infinite Stamina)
-- All GENERIC / game-agnostic client visuals + a best-effort stamina holder. No game
-- knowledge needed, so these work broadly (unlike the gun hacks, which are per-game).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = workspace
local lPlayer = Players.LocalPlayer
local DrawingFallback = getgenv().DrawingFallback
local pluginCleanup = nil
local OBJ_W = { "flag", "objective", "capture", "zone", "control", "base", "cap", "point", "spawnpoint", "hardpoint", "intel", "bomb", "hill" }
local LOOT_W = { "crate", "ammo", "supply", "loot", "cache", "pickup", "resupply", "kit", "box", "medkit", "health", "armor", "refill", "arrow", "bolt", "quiver" }
local function hasW(n, words) n = tostring(n):lower() for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end return false end

return {
	name = "World", tab = "World", requires = {},
	load = function(ctx)
		local visGroup  = ctx:Groupbox("Visuals", "left")
		local camGroup  = ctx:Groupbox("Camera", "left")
		local utilGroup = ctx:Groupbox("Utility", "right")

		-- Snapshot originals so toggling off restores the game's own look.
		local orig = {
			Brightness = Lighting.Brightness, GlobalShadows = Lighting.GlobalShadows,
			Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
			FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
		}
		local origFOV = (Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView) or 70

		visGroup:AddToggle("fullbright", { Text = "Fullbright", Default = false, Tooltip = "Remove darkness/shadows for full visibility. (Default: OFF)" }); ctx:Control("fullbright")
		visGroup:AddToggle("noFog", { Text = "No Fog", Default = false, Tooltip = "Remove fog + atmospheric haze. (Default: OFF)" }); ctx:Control("noFog")

		-- One function handles BOTH directions: bright/clear when on, restore when off.
		local function applyLighting()
			if Toggles.fullbright and Toggles.fullbright.Value then
				Lighting.Brightness = 2; Lighting.GlobalShadows = false
				Lighting.Ambient = Color3.fromRGB(178, 178, 178); Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
			else
				Lighting.Brightness = orig.Brightness; Lighting.GlobalShadows = orig.GlobalShadows
				Lighting.Ambient = orig.Ambient; Lighting.OutdoorAmbient = orig.OutdoorAmbient
			end
			if Toggles.noFog and Toggles.noFog.Value then
				Lighting.FogEnd = 1e9; Lighting.FogStart = 1e9
				pcall(function() local a = Lighting:FindFirstChildOfClass("Atmosphere"); if a then a.Density = 0; a.Haze = 0 end end)
			else
				Lighting.FogEnd = orig.FogEnd; Lighting.FogStart = orig.FogStart
			end
		end
		-- Re-assert while on (games continuously rewrite lighting); idle when both off.
		ctx:Connect(RunService.Heartbeat, function()
			if (Toggles.fullbright and Toggles.fullbright.Value) or (Toggles.noFog and Toggles.noFog.Value) then applyLighting() end
		end)
		Toggles.fullbright:OnChanged(applyLighting)
		Toggles.noFog:OnChanged(applyLighting)

		camGroup:AddToggle("customFovEnabled", { Text = "Custom FOV", Default = false, Tooltip = "Override the camera field of view. (Default: OFF)" }); ctx:Control("customFovEnabled")
		camGroup:AddSlider("customFov", { Text = "FOV", Min = 30, Max = 120, Default = 70, Rounding = 0 }); ctx:Control("customFov")
		ctx:Connect(RunService.RenderStepped, function()
			local c = Workspace.CurrentCamera
			if c and Toggles.customFovEnabled and Toggles.customFovEnabled.Value then c.FieldOfView = Options.customFov.Value end
		end)
		Toggles.customFovEnabled:OnChanged(function()
			if not Toggles.customFovEnabled.Value then local c = Workspace.CurrentCamera; if c then pcall(function() c.FieldOfView = origFOV end) end end
		end)

		-- Infinite Stamina: best-effort. Holds any client-side stamina/energy value at the
		-- max it's been seen at. Won't help if stamina is enforced server-side.
		utilGroup:AddToggle("infStamina", { Text = "Infinite Stamina", Default = false, Tooltip = "Hold a stamina/energy value full. Client-side only; won't work\nif the game validates stamina on the server. (Default: OFF)" }); ctx:Control("infStamina")
		local STAM_WORDS = { "stamina", "sprint", "energy", "breath", "endurance", "fatigue", "exhaust", "oxygen" }
		local stamMax = setmetatable({}, { __mode = "k" })
		local lastStam = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.infStamina and Toggles.infStamina.Value) then return end
			local now = tick(); if now - lastStam < 0.15 then return end; lastStam = now
			pcall(function()
				for _, root in ipairs({ lPlayer.Character, lPlayer:FindFirstChild("Backpack"), lPlayer:FindFirstChild("leaderstats") }) do
					if root then
						for _, d in ipairs(root:GetDescendants()) do
							if d:IsA("NumberValue") or d:IsA("IntValue") then
								local n = d.Name:lower()
								for _, w in ipairs(STAM_WORDS) do
									if n:find(w) then
										stamMax[d] = math.max(stamMax[d] or d.Value, d.Value)
										if d.Value < stamMax[d] then pcall(function() d.Value = stamMax[d] end) end
										break
									end
								end
							end
						end
					end
				end
			end)
		end)

		-- ===== World Markers: objective + loot/ammo ESP + teleport =====
		local mkGroup = ctx:Groupbox("World Markers", "right")
		mkGroup:AddToggle("worldMarkers", { Text = "Objective + Loot ESP", Default = false, Tooltip = "Draw name + distance markers on objectives (flag/capture/zone) and loot/ammo crates. (Default: OFF)" }); ctx:Control("worldMarkers")
		mkGroup:AddSlider("worldMarkerDist", { Text = "Marker Distance", Min = 50, Max = 3000, Default = 800, Rounding = 0 }); ctx:Control("worldMarkerDist")
		local lblMk = mkGroup:AddLabel("Markers: off", true)
		local function localRoot() local c = lPlayer.Character return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")) end
		local function nearestMatch(words)
			local lr = localRoot(); if not lr then return nil end
			local best, bd
			local n = 0
			for _, d in ipairs(Workspace:GetDescendants()) do
				n = n + 1; if n > 20000 then break end
				if (d:IsA("BasePart") or d:IsA("Model")) and hasW(d.Name, words) then
					local ok, pos = pcall(function() return d:IsA("Model") and d:GetPivot().Position or d.Position end)
					if ok and pos then local m = (pos - lr.Position).Magnitude; if not bd or m < bd then best, bd = pos, m end end
				end
			end
			return best
		end
		mkGroup:AddButton("Teleport: Nearest Loot", function()
			local p = nearestMatch(LOOT_W); local lr = localRoot()
			if p and lr then pcall(function() lr.CFrame = CFrame.new(p + Vector3.new(0, 5, 0)) end); Library:Notify("TP to nearest loot") else Library:Notify("No loot found") end
		end)
		mkGroup:AddButton("Teleport: Nearest Objective", function()
			local p = nearestMatch(OBJ_W); local lr = localRoot()
			if p and lr then pcall(function() lr.CFrame = CFrame.new(p + Vector3.new(0, 5, 0)) end); Library:Notify("TP to nearest objective") else Library:Notify("No objective found") end
		end)
		-- marker pool (GUI-fallback text), recompute world list ~2Hz, project every frame
		local POOL = 24
		local texts = {}
		for i = 1, POOL do local t = ctx:Track(DrawingFallback.new("Text")); t.Center = true; t.Outline = true; t.Size = 14; t.Visible = false; texts[i] = t end
		local cache, lastScan = {}, 0
		local function scanMarkers()
			cache = {}
			local lr = localRoot(); if not lr then return end
			local maxd = Options.worldMarkerDist.Value
			local n = 0
			for _, d in ipairs(Workspace:GetDescendants()) do
				n = n + 1; if n > 20000 or #cache >= POOL then break end
				if (d:IsA("BasePart") or d:IsA("Model")) then
					local isLoot, isObj = hasW(d.Name, LOOT_W), hasW(d.Name, OBJ_W)
					if isLoot or isObj then
						local ok, pos = pcall(function() return d:IsA("Model") and d:GetPivot().Position or d.Position end)
						if ok and pos and (pos - lr.Position).Magnitude <= maxd then
							cache[#cache + 1] = { pos = pos, label = d.Name, color = isLoot and Color3.fromRGB(120, 230, 120) or Color3.fromRGB(255, 210, 80) }
						end
					end
				end
			end
		end
		ctx:Connect(RunService.RenderStepped, function()
			if not (Toggles.worldMarkers and Toggles.worldMarkers.Value) then
				for _, t in ipairs(texts) do t.Visible = false end
				return
			end
			local now = tick(); if now - lastScan > 0.5 then lastScan = now; pcall(scanMarkers) end
			local cam = Workspace.CurrentCamera
			local lr = localRoot()
			for i, t in ipairs(texts) do
				local e = cache[i]
				if e and cam then
					local sp = cam:WorldToViewportPoint(e.pos)
					if sp.Z > 0 then
						local dist = lr and math.floor((e.pos - lr.Position).Magnitude) or 0
						t.Text = e.label .. " [" .. dist .. "m]"; t.Color = e.color
						t.Position = Vector2.new(sp.X, sp.Y); t.Visible = true
					else t.Visible = false end
				else t.Visible = false end
			end
			pcall(function() lblMk:SetText("Markers: " .. #cache .. " in range") end)
		end)

		pluginCleanup = function()
			pcall(function() for _, t in ipairs(texts) do t.Visible = false end end)
			-- restore everything we may have changed
			pcall(function()
				Lighting.Brightness = orig.Brightness; Lighting.GlobalShadows = orig.GlobalShadows
				Lighting.Ambient = orig.Ambient; Lighting.OutdoorAmbient = orig.OutdoorAmbient
				Lighting.FogEnd = orig.FogEnd; Lighting.FogStart = orig.FogStart
			end)
			pcall(function() local c = Workspace.CurrentCamera; if c then c.FieldOfView = origFOV end end)
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
