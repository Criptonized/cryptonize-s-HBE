-- CryptsHBE plugin: Inf Ammo + Gun Picker (adaptive 5-strategy + learning resolver)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE
local pluginCleanup = nil
return {
	name = "InfAmmo", tab = "Inf Ammo", requires = {},
	load = function(ctx)
		local miscTab = ctx.tab
	local AMMO_PAT = { "ammo", "bullet", "mag", "clip", "round", "reserve", "shell", "rocket", "arrow", "grenade", "cartridge", "stockpile", "stored", "spare", "loaded" }
	-- Numeric value types. CRITICAL: many gun frameworks (TREK, older FE kits) store ammo
	-- as Double/IntConstrainedValue, NOT IntValue/NumberValue -- scanning only the latter
	-- is why ammo looked "server-side". Constrained values clamp writes to MaxValue, so
	-- writing the big Refill Amount just pins them full.
	local function isNumVal(d)
		return d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue")
	end

	local g = miscTab:AddRightGroupbox("Inf Ammo / Guns")
	g:AddToggle("infAmmoEnabled", { Text = "Enable Inf Ammo", Default = false, Tooltip = "Continuously refills numeric ammo values on your equipped gun(s).\nClient-side heuristic; some games keep ammo server-side. (Default: OFF)" })
	g:AddToggle("infAmmoAllTools", { Text = "Apply to Any Tool", Default = false, Tooltip = "Apply to every equipped tool, not just registered guns. (Default: OFF)" })
	g:AddSlider("infAmmoAmount", { Text = "Refill Amount", Min = 1, Max = 9999, Default = 999, Rounding = 0, Tooltip = "Value ammo fields are refilled to each tick. (Default: 999)" })
	g:AddDropdown("infAmmoGuns", { Text = "Registered Guns", Values = {}, Multi = true, AllowNull = true, Tooltip = "Guns this applies to (unless 'Apply to Any Tool'). (Default: none)" })

	local function addGun(name)
		if not name or name == "" then return end
		local list = Options.infAmmoGuns
		if not table.find(list.Values, name) then table.insert(list.Values, name); list:SetValues() end
		local v = list.Value
		if type(v) == "table" then v[name] = true; pcall(function() list:SetValue(v) end) end
		Library:Notify("Registered gun: " .. name)
	end
	g:AddButton("Register Gun in Hand", function()
		local char = lPlayer.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		if tool then addGun(tool.Name) else Library:Notify("No tool equipped") end
	end):AddToolTip("Register the tool you're currently holding")
	g:AddButton("Register Gun (hold-pick)", function()
		Bridge:StartHoldPick({ color = Color3.fromRGB(255, 120, 0), onPick = function(part)
			local tool = part:FindFirstAncestorWhichIsA("Tool")
			if tool then addGun(tool.Name) else Library:Notify("That isn't part of a Tool") end
		end })
	end):AddToolTip("Aim at a gun/tool and hold-click to register it")
	g:AddButton("Clear Guns", function()
		Options.infAmmoGuns.Values = {}; Options.infAmmoGuns:SetValues(); pcall(function() Options.infAmmoGuns:SetValue({}) end)
	end)

	-- Manual override: type the exact name of a value the game uses for ammo and it
	-- gets treated as ammo by every detection strategy below.
	g:AddInput("infAmmoManualName", { Text = "Manual Ammo Name", Default = "", Tooltip = "Extra name to treat as ammo (e.g. 'Bullets', 'CurrentAmmo').\nEmpty = use the built-in keywords only." })
	local function isAmmoName(n)
		n = n:lower()
		for _, p in ipairs(AMMO_PAT) do if n:find(p) then return true end end
		if Options.infAmmoManualName and Options.infAmmoManualName.Value ~= "" and n:find(Options.infAmmoManualName.Value:lower()) then return true end
		return false
	end
	local detLabel = g:AddLabel("Detection: idle", true)

	-- ===== Adaptive ammo resolver =====================================
	-- Like the attach flow: try each detection STRATEGY in order and fall through
	-- until one actually finds ammo; cache the winner per gun. If every static
	-- strategy fails, a LEARNING detector watches the gun's numbers and adopts any
	-- value that drops when you fire. So even oddly-built guns get covered.
	local fieldCache = setmetatable({}, { __mode = "k" })  -- [tool] = { fields=, how= }
	local snapshots  = setmetatable({}, { __mode = "k" })  -- [tool] = { [valueObj] = lastValue }

	-- `alive` lets the resolver detect when a cached value object was replaced (e.g. TREK
	-- re-creates the gun's LocalTAmmo folder on respawn) so it re-detects instead of
	-- writing to a dead, reparented object forever -- the "doesn't work after reset" bug.
	local function fieldFromValue(v)
		return { read = function() return v.Value end, write = function(n) pcall(function() v.Value = n end) end, alive = function() return v.Parent ~= nil end }
	end
	local function fieldFromAttr(inst, name)
		return { read = function() return inst:GetAttribute(name) or 0 end, write = function(n) pcall(function() inst:SetAttribute(name, n) end) end, alive = function() return inst.Parent ~= nil end }
	end

	local function stratValueNames(tool)
		local out = {}
		for _, d in ipairs(tool:GetDescendants()) do
			if isNumVal(d) and isAmmoName(d.Name) then out[#out + 1] = fieldFromValue(d) end
		end
		return out
	end
	local function stratAttributes(tool)
		local out = {}
		local function scan(inst) for an, av in pairs(inst:GetAttributes()) do if type(av) == "number" and isAmmoName(an) then out[#out + 1] = fieldFromAttr(inst, an) end end end
		pcall(scan, tool)
		for _, d in ipairs(tool:GetDescendants()) do pcall(scan, d) end
		return out
	end
	local function stratConfiguration(tool)
		local out = {}
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("Configuration") or (typeof(d.Name) == "string" and d.Name:lower():find("config")) then
				for _, c in ipairs(d:GetChildren()) do
					if isNumVal(c) then out[#out + 1] = fieldFromValue(c) end
				end
			end
		end
		return out
	end
	-- Player-side: covers ammo kept OUTSIDE the gun -- separate inventory items like
	-- "5.56 Ammo", reserve counts in the Backpack, leaderstats. SCOPED to safe containers
	-- ONLY (Backpack / leaderstats / Character) -- NEVER PlayerGui or PlayerScripts. The
	-- old version scanned all of lPlayer and force-wrote the refill amount into anything
	-- ammo-named, which on executors where gethui() falls back to PlayerGui meant it
	-- scribbled into the menu's own GUI state and corrupted the tabs. Bounded, too.
	local function stratPlayerSide(_)
		local out, n = {}, 0
		local roots = { lPlayer:FindFirstChild("Backpack"), lPlayer:FindFirstChild("leaderstats"), lPlayer.Character }
		for _, root in ipairs(roots) do
			if root then
				for _, d in ipairs(root:GetDescendants()) do
					n = n + 1; if n > 6000 then break end
					if isNumVal(d) and isAmmoName(d.Name) then out[#out + 1] = fieldFromValue(d) end
					pcall(function()
						for an, av in pairs(d:GetAttributes()) do
							if type(av) == "number" and isAmmoName(an) then out[#out + 1] = fieldFromAttr(d, an) end
						end
					end)
				end
			end
		end
		return out
	end
	local STRATS = {
		{ name = "ValueNames", fn = stratValueNames },
		{ name = "Attributes", fn = stratAttributes },
		{ name = "Configuration", fn = stratConfiguration },
		{ name = "PlayerSide", fn = stratPlayerSide },
	}

	local function stratLearning(tool)
		local snap = snapshots[tool]
		if not snap then
			snap = {}
			for _, d in ipairs(tool:GetDescendants()) do
				if isNumVal(d) then snap[d] = d.Value end
			end
			snapshots[tool] = snap
			return {}
		end
		local out = {}
		for v, last in pairs(snap) do
			if typeof(v) == "Instance" and v.Parent then
				if v.Value < last then out[#out + 1] = fieldFromValue(v) end  -- decreased = ammo
				snap[v] = v.Value
			else
				snap[v] = nil
			end
		end
		return out
	end

	local function resolveFields(tool)
		local cached = fieldCache[tool]
		if cached and #cached.fields > 0 then
			-- Re-detect if any cached value object was reparented/replaced (respawn/reload).
			local good = true
			for _, f in ipairs(cached.fields) do if f.alive and not f.alive() then good = false; break end end
			if good then return cached end
			fieldCache[tool] = nil
		end
		for _, s in ipairs(STRATS) do
			local fields = s.fn(tool)
			if #fields > 0 then fieldCache[tool] = { fields = fields, how = s.name }; return fieldCache[tool] end
		end
		local learned = stratLearning(tool)
		if #learned > 0 then fieldCache[tool] = { fields = learned, how = "Learned" }; return fieldCache[tool] end
		return nil
	end

	local lastHow = nil
	local function refillTool(tool)
		local res = resolveFields(tool)
		if not res then return end
		local amt = Options.infAmmoAmount.Value
		for _, f in ipairs(res.fields) do
			local cur = f.read()
			if type(cur) == "number" and cur < amt then f.write(amt) end
		end
		if res.how ~= lastHow then
			lastHow = res.how
			pcall(function() detLabel:SetText("Detection: " .. res.how) end)
		end
	end

	local lastRefill = 0
	local ammoConn = RunService.Heartbeat:Connect(function()
		if not Toggles.infAmmoEnabled.Value then return end
		local now = tick()
		if now - lastRefill < 0.15 then return end  -- light throttle
		lastRefill = now
		local char = lPlayer.Character
		if not char then return end
		local active = Options.infAmmoGuns:GetActiveValues()
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") and (Toggles.infAmmoAllTools.Value or table.find(active, tool.Name)) then
				pcall(refillTool, tool)
			end
		end
	end)
		for _, k in ipairs({ "infAmmoEnabled","infAmmoAllTools","infAmmoAmount","infAmmoGuns","infAmmoManualName" }) do ctx:Control(k) end

		-- Bottom-of-tab tutorial.
		local howG = miscTab:AddLeftGroupbox("How to Use")
		howG:AddLabel(
			"Refills numeric ammo values on your gun\n" ..
			"each tick. CLIENT-SIDE only.\n\n" ..
			"  1. Register your gun (in-hand or\n" ..
			"     hold-pick), or 'Apply to Any Tool'.\n" ..
			"  2. Enable Inf Ammo. 'Detection' shows\n" ..
			"     which method found the ammo.\n\n" ..
			"STILL RUNS OUT? Ammo is server-side.\n" ..
			"Confirm: Calibrate -> Learn -> Snapshot,\n" ..
			"fire, Analyze. If the only change is a\n" ..
			"'HUD:...' label, the real ammo is\n" ..
			"server-side and CANNOT be refilled\n" ..
			"(there's no value to write).\n\n" ..
			"Manual Ammo Name = the exact name of a\n" ..
			"client ammo Value (e.g. 'Bullets') --\n" ..
			"NOT the on-screen number or the caliber.",
			true)
		-- On respawn the gun is rebuilt with fresh value objects; clear the per-tool caches
		-- so detection runs clean on the new gun (belt-and-suspenders with the alive-check).
		local charConn = lPlayer.CharacterAdded:Connect(function()
			table.clear(fieldCache); table.clear(snapshots); lastHow = nil
		end)
		pluginCleanup = function()
			if ammoConn then pcall(function() ammoConn:Disconnect() end) end
			if charConn then pcall(function() charConn:Disconnect() end) end
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
