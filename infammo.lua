-- FurryHBE plugin: Inf Ammo + Gun Picker (adaptive 5-strategy + learning resolver)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().FurryHBE
local pluginCleanup = nil
return {
	name = "InfAmmo", tab = "Inf Ammo", requires = {},
	load = function(ctx)
		local miscTab = ctx.tab
	local AMMO_PAT = { "ammo", "bullet", "mag", "clip", "round", "reserve", "shell", "rocket", "arrow", "grenade", "cartridge", "stockpile" }

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

	local function fieldFromValue(v)
		return { read = function() return v.Value end, write = function(n) pcall(function() v.Value = n end) end }
	end
	local function fieldFromAttr(inst, name)
		return { read = function() return inst:GetAttribute(name) or 0 end, write = function(n) pcall(function() inst:SetAttribute(name, n) end) end }
	end

	local function stratValueNames(tool)
		local out = {}
		for _, d in ipairs(tool:GetDescendants()) do
			if (d:IsA("IntValue") or d:IsA("NumberValue")) and isAmmoName(d.Name) then out[#out + 1] = fieldFromValue(d) end
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
					if c:IsA("IntValue") or c:IsA("NumberValue") then out[#out + 1] = fieldFromValue(c) end
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
					if (d:IsA("IntValue") or d:IsA("NumberValue")) and isAmmoName(d.Name) then out[#out + 1] = fieldFromValue(d) end
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
				if d:IsA("IntValue") or d:IsA("NumberValue") then snap[d] = d.Value end
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
		if cached and #cached.fields > 0 then return cached end
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
			"Refills numeric ammo values on your gun each tick. CLIENT-SIDE only.\n\n" ..
			"  1. Register your gun: 'Register Gun in Hand' or 'Register Gun (hold-pick)' -- or flip\n" ..
			"     'Apply to Any Tool'.\n" ..
			"  2. Enable Inf Ammo. The 'Detection' label shows which method found the ammo.\n\n" ..
			"STILL RUNS OUT? The game keeps ammo server-side. Confirm it: Calibrate -> Learn ->\n" ..
			"  Snapshot, fire, Analyze. If the only thing that changed is a 'HUD:...' label, the real\n" ..
			"  ammo is server-side and CANNOT be refilled from the client (no value to write).\n\n" ..
			"Manual Ammo Name = the exact name of a client ammo Value (e.g. 'Bullets') -- NOT the\n" ..
			"on-screen number and NOT the caliber.",
			true)
		pluginCleanup = function() if ammoConn then pcall(function() ammoConn:Disconnect() end) end end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}