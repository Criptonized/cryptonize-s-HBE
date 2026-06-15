-- CryptsHBE plugin: Section Loader
-- ============================================================================
-- "I'm done configuring -- strip it down." Pick the sections (plugins) you actually use,
-- tick Config Finished, and Load Sections UNLOADS every other loaded plugin (frees its
-- memory + connections via the normal teardown), optionally cuts HBE/ESP distances back,
-- so you run lean once your setup is dialled in.
--
-- Plus an Engagement Logger: it samples the range you actually meet enemies at and reports
-- the average / most-used distance, so you can cut HBE+ESP distance to what you really need
-- (smaller reach = less work + lower detection surface) instead of guessing.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

local function isEnemy(plr)
	if plr == lPlayer then return false end
	local ok, ally = pcall(function()
		if lPlayer.Team ~= nil or plr.Team ~= nil then return lPlayer.Team == plr.Team end
		return lPlayer.TeamColor == plr.TeamColor
	end)
	return not (ok and ally)
end

return {
	name = "Sections", tab = "Sections", requires = {},
	load = function(ctx)
		local Bridge = getgenv().CryptsHBE
		local function C(k) ctx:Control(k) end

		local function registeredNames()
			local t = {}
			for n in pairs(Bridge.PluginSources or {}) do if n ~= "Sections" then t[#t + 1] = n end end
			table.sort(t); return t
		end
		local function isLoaded(n) local e = Bridge.Plugins and Bridge.Plugins[n]; return e and e.loaded end

		local gSec = ctx:Groupbox("Section Loader", "left")
		gSec:AddDropdown("secKeep", { Text = "Keep these (whitelist)", Values = registeredNames(), Multi = true, AllowNull = true, Tooltip = "Sections (plugins) to KEEP loaded. Everything else loaded gets unloaded." }); C("secKeep")
		local lblLoaded = gSec:AddLabel("Loaded: -", true)
		gSec:AddButton("Refresh List", function()
			pcall(function() Options.secKeep.Values = registeredNames(); Options.secKeep:SetValues() end)
		end):AddToolTip("Re-read the registered/loaded plugin list.")
		gSec:AddToggle("secFinished", { Text = "Config Finished", Default = false, Tooltip = "Safety gate -- tick this to confirm you're done before Load Sections unloads things. (Default: OFF)" }); C("secFinished")
		gSec:AddButton("Load Sections (unload rest)", function()
			if not (Toggles.secFinished and Toggles.secFinished.Value) then Library:Notify("Tick 'Config Finished' first"); return end
			local keep = {}
			for k, v in pairs(Options.secKeep.Value or {}) do if v then keep[k] = true end end
			keep["Sections"] = true   -- never unload ourselves
			local unloaded, kept = 0, 0
			for _, n in ipairs(registeredNames()) do
				if isLoaded(n) then
					if keep[n] then kept = kept + 1
					else pcall(function() Bridge:UnloadPlugin(n) end); unloaded = unloaded + 1 end
				end
			end
			if Toggles.secApplyDist and Toggles.secApplyDist.Value then
				pcall(function() if Options.maxDistance then Options.maxDistance:SetValue(Options.secHBEDist.Value) end end)
				pcall(function() if Options.espMaxDistance then Options.espMaxDistance:SetValue(Options.secESPDist.Value) end end)
			end
			Library:Notify(("Section Loader: kept %d, unloaded %d"):format(kept, unloaded))
		end):AddToolTip("Unload every loaded plugin not in the keep-list (+ optional distance cutback).")

		local gDist = ctx:Groupbox("Distance Cutback", "left")
		gDist:AddSlider("secHBEDist", { Text = "HBE Distance", Min = 0, Max = 1000, Default = 150, Rounding = 0, Tooltip = "Writes the core HBE Max Distance when applied." }); C("secHBEDist")
		gDist:AddSlider("secESPDist", { Text = "ESP Distance", Min = 0, Max = 1000, Default = 300, Rounding = 0, Tooltip = "Writes the core ESP Max Distance when applied." }); C("secESPDist")
		gDist:AddToggle("secApplyDist", { Text = "Apply distances on Load", Default = false, Tooltip = "When Load Sections runs, also write the HBE/ESP distances above. (Default: OFF)" }); C("secApplyDist")
		gDist:AddButton("Apply Distances Now", function()
			pcall(function() if Options.maxDistance then Options.maxDistance:SetValue(Options.secHBEDist.Value) end end)
			pcall(function() if Options.espMaxDistance then Options.espMaxDistance:SetValue(Options.secESPDist.Value) end end)
			Library:Notify(("Set HBE %d / ESP %d"):format(Options.secHBEDist.Value, Options.secESPDist.Value))
		end):AddToolTip("Write the HBE + ESP Max Distance sliders into the core right now.")

		local gLog = ctx:Groupbox("Engagement Logger", "right")
		local lblLog = gLog:AddLabel("Logging engagement range...", true)
		local lblParts = gLog:AddLabel("Per-part: no data yet", true)
		-- running stats over the distance to the NEAREST enemy (a proxy for engage range)
		local samples, sum, minD, maxD = 0, 0, math.huge, 0
		local buckets = {}   -- [floor(d/25)] = count
		-- Per-hitbox: classify which body part of the nearest enemy is closest to your aim ray
		-- (Head / Torso / Limb) + track average engagement range + most-aimed part per class, so
		-- you can size headSize/torsoSize/limbSize to where you actually fight.
		local classStats = { Head = { n = 0, sum = 0 }, Torso = { n = 0, sum = 0 }, Limb = { n = 0, sum = 0 } }
		local PART_LIMB = { "arm", "leg", "hand", "foot", "wrist", "knee", "shoulder", "elbow", "ankle", "hip" }
		local function classOfName(n)
			n = tostring(n):lower()
			if n:find("head") then return "Head" end
			for _, w in ipairs(PART_LIMB) do if n:find(w) then return "Limb" end end
			return "Torso"
		end
		local function aimedClass(plr)
			local cam = workspace.CurrentCamera
			local pc = plr.Character
			if not (cam and pc) then return nil end
			local camPos, look = cam.CFrame.Position, cam.CFrame.LookVector
			local bestPart, bestDot
			for _, d in ipairs(pc:GetDescendants()) do
				if d:IsA("BasePart") then
					local dir = d.Position - camPos
					if dir.Magnitude > 0.1 then
						local dot = look:Dot(dir.Unit)
						if not bestDot or dot > bestDot then bestDot, bestPart = dot, d end
					end
				end
			end
			return bestPart and classOfName(bestPart.Name) or nil
		end
		local function suggested()
			local bestB, bestC = nil, 0
			for b, c in pairs(buckets) do if c > bestC then bestB, bestC = b, c end end
			if not bestB then return nil end
			return math.clamp((bestB + 1) * 25 + 50, 50, 1000)
		end
		gLog:AddButton("Apply Suggested Distance", function()
			local s = suggested()
			if not s then Library:Notify("No data yet"); return end
			pcall(function() if Options.maxDistance then Options.maxDistance:SetValue(s) end end)
			pcall(function() if Options.espMaxDistance then Options.espMaxDistance:SetValue(s) end end)
			pcall(function() Options.secHBEDist:SetValue(s); Options.secESPDist:SetValue(s) end)
			Library:Notify("Applied suggested distance " .. s)
		end):AddToolTip("Set HBE + ESP distance to the most-used engagement range (+margin).")
		gLog:AddButton("Reset Log", function()
			samples, sum, minD, maxD, buckets = 0, 0, math.huge, 0, {}
			classStats = { Head = { n = 0, sum = 0 }, Torso = { n = 0, sum = 0 }, Limb = { n = 0, sum = 0 } }
			pcall(function() lblLog:SetText("Log reset.") end)
		end)

		local lastSample, lastUI = 0, 0
		ctx:Connect(RunService.Heartbeat, function()
			local now = tick()
			if now - lastSample > 0.5 then
				lastSample = now
				local c = lPlayer.Character
				local lr = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
				if lr then
					local best, bestPlr
					for _, plr in ipairs(Players:GetPlayers()) do
						if isEnemy(plr) then
							local pc = plr.Character
							local pr = pc and (pc:FindFirstChild("HumanoidRootPart") or pc:FindFirstChild("Head"))
							if pr then local d = (pr.Position - lr.Position).Magnitude; if not best or d < best then best = d; bestPlr = plr end end
						end
					end
					if best and best < 5000 then
						samples = samples + 1; sum = sum + best
						minD = math.min(minD, best); maxD = math.max(maxD, best)
						local b = math.floor(best / 25); buckets[b] = (buckets[b] or 0) + 1
						if bestPlr then
							local cls = aimedClass(bestPlr)
							if cls and classStats[cls] then classStats[cls].n = classStats[cls].n + 1; classStats[cls].sum = classStats[cls].sum + best end
						end
					end
				end
			end
			if now - lastUI > 0.5 then
				lastUI = now
				pcall(function()
					local loaded = {}
					for _, n in ipairs(registeredNames()) do if isLoaded(n) then loaded[#loaded + 1] = n end end
					lblLoaded:SetText("Loaded (" .. #loaded .. "): " .. (#loaded > 0 and table.concat(loaded, ", ") or "none"))
				end)
				pcall(function()
					if samples > 0 then
						local avg = sum / samples
						local s = suggested()
						lblLog:SetText(("Engage range over %d samples:\navg %dm  min %dm  max %dm\nMost-used ~%dm -> suggest %s"):format(
							samples, math.floor(avg), math.floor(minD), math.floor(maxD),
							(function() local bb, bc = 0, 0 for b, c in pairs(buckets) do if c > bc then bb, bc = b, c end end return bb * 25 + 12 end)(),
							s and (s .. "m") or "-"))
					else
						lblLog:SetText("Engagement Logger: no enemies sampled yet.")
					end
				end)
			end
		end)

		local howG = ctx:Groupbox("How to Use", "right")
		howG:AddLabel(
			"Once your config is dialled in:\n" ..
			"  1. Pick the sections (plugins) you use\n" ..
			"     in 'Keep these'.\n" ..
			"  2. Tick 'Config Finished'.\n" ..
			"  3. 'Load Sections' -- every other loaded\n" ..
			"     plugin is unloaded (memory freed).\n\n" ..
			"Watch the Engagement Logger: it learns the\n" ..
			"range you actually fight at. Hit 'Apply\n" ..
			"Suggested Distance' to cut HBE+ESP reach to\n" ..
			"what you need -- less work, smaller\n" ..
			"detection surface.\n\n" ..
			"(This panel never unloads itself; re-enable\n" ..
			"unloaded plugins any time from the Plugins\n" ..
			"tab.)",
			true)

		local lastParts = 0
		ctx:Connect(RunService.Heartbeat, function()
			local now = tick()
			if now - lastParts < 0.5 then return end
			lastParts = now
			local parts, topCls, topN = {}, nil, 0
			for _, cls in ipairs({ "Head", "Torso", "Limb" }) do
				local st = classStats[cls]
				if st.n > 0 then
					parts[#parts + 1] = ("%s %dm(%d)"):format(cls, math.floor(st.sum / st.n), st.n)
					if st.n > topN then topN, topCls = st.n, cls end
				end
			end
			pcall(function() lblParts:SetText(#parts > 0 and ("Per-part avg range:\n" .. table.concat(parts, "  ") .. "\nMost-aimed: " .. (topCls or "-")) or "Per-part: no data yet") end)
		end)
		pluginCleanup = function() end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
