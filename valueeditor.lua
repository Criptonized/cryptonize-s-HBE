-- CryptsHBE plugin: Value Editor
-- ============================================================================
-- "It's all just changing values." A universal value picker: scan a scope (or CLICK a
-- number on your HUD -- ammo, speed, currency -- and it finds the value(s) behind it),
-- pick one, and Set or Hold it to anything. No per-stat feature needed; works for ammo,
-- vehicle speed caps, money, etc. -- anything stored as a (constrained) Value or numeric
-- attribute. CLIENT-SIDE: a held value only "wins" if the game reads it live and trusts
-- the client (it can't beat a server that overwrites it).
-- ============================================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = workspace
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

local function isNum(d)
	return d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue")
end

return {
	name = "Values", tab = "Values", requires = {},
	load = function(ctx)
		local scanG = ctx:Groupbox("Value Editor", "left")
		local setG  = ctx:Groupbox("Set / Hold", "left")
		local pickG = ctx:Groupbox("Pick from HUD", "right")

		local found = {}        -- "entry string" -> { fld, rate, reason }
		local selField = nil    -- currently selected field
		local lastHold = 0

		local Bridge = getgenv().CryptsHBE
		-- ---- detectability rating: green = likely works + safe, yellow = test it, red =
		-- server-validated or watched by the anti-cheat (the deep probe feeds this). ----
		local RATE_COLOR = { green = Color3.fromRGB(70, 220, 90), yellow = Color3.fromRGB(245, 215, 60), red = Color3.fromRGB(235, 70, 70) }
		local RATE_SYM   = { green = "+ ", yellow = "? ", red = "! " }
		-- humanoid/movement/health props the engine + most ACs sanity-check server-side
		local AC_PROPS = { "walkspeed", "jumppower", "jumpheight", "hipheight", "gravity", "maxhealth", "health" }
		local function rateField(name, inst)
			local ok, watched = pcall(function() return Bridge and Bridge.isWatched and Bridge.isWatched(name) end)
			if ok and watched then return "red", "anti-cheat watches this name (deep probe)" end
			local ln = tostring(name):lower()
			for _, w in ipairs(AC_PROPS) do if ln:find(w, 1, true) then return "red", "server-validated stat" end end
			local path = ""; pcall(function() path = inst:GetFullName():lower() end)
			if path:find("leaderstats", 1, true) then return "yellow", "leaderstats -- server-replicated" end
			local mine = false
			pcall(function() mine = (lPlayer.Character ~= nil and inst:IsDescendantOf(lPlayer.Character)) or inst:IsDescendantOf(lPlayer) end)
			if mine then return "green", "client-side (yours)" end
			return "yellow", "shared/server-side -- may revert"
		end
		-- tint a LinoriaLib label (probe its TextLabel; same trick the core status light uses)
		local function tint(lbl, rate)
			local color = RATE_COLOR[rate] or Color3.fromRGB(235, 235, 235)
			pcall(function()
				local direct = rawget(lbl, "TextLabel") or rawget(lbl, "Label") or rawget(lbl, "Instance")
				if typeof(direct) == "Instance" and direct:IsA("TextLabel") then direct.TextColor3 = color; return end
				for _, k in ipairs({ "Holder", "Container", "TextLabel", "Instance" }) do
					local h = rawget(lbl, k)
					if typeof(h) == "Instance" then
						if h:IsA("TextLabel") then h.TextColor3 = color end
						for _, d in ipairs(h:GetDescendants()) do if d:IsA("TextLabel") then d.TextColor3 = color end end
					end
				end
			end)
		end

		-- field abstractions (read/write/alive so a held value survives object churn)
		local function fVal(v) return { read = function() return v.Value end, write = function(n) pcall(function() v.Value = n end) end, alive = function() return v.Parent ~= nil end, path = v:GetFullName() } end
		local function fAttr(i, a) return { read = function() return i:GetAttribute(a) end, write = function(n) pcall(function() i:SetAttribute(a, n) end) end, alive = function() return i.Parent ~= nil end, path = i:GetFullName() .. " @" .. a } end

		-- collect numeric values + attributes from a root; optional name filter + value match
		local function collect(root, q, matchNum, out, capN)
			if not root then return end
			pcall(function()
				local n = 0
				for _, d in ipairs(root:GetDescendants()) do
					n = n + 1; if n > capN then break end
					if isNum(d) then
						local ok = (q == "" or d.Name:lower():find(q, 1, true)) and (not matchNum or math.abs((d.Value or 0) - matchNum) < 1.0)
						if ok then out[#out + 1] = { name = d.Name, fld = fVal(d), inst = d } end
					end
					pcall(function()
						for an, av in pairs(d:GetAttributes()) do
							if type(av) == "number" and (q == "" or an:lower():find(q, 1, true)) and (not matchNum or math.abs(av - matchNum) < 1.0) then
								out[#out + 1] = { name = d.Name .. "@" .. an, fld = fAttr(d, an), inst = d }
							end
						end
					end)
				end
			end)
		end

		local function seatedVehicle()
			local c = lPlayer.Character
			local hum = c and c:FindFirstChildWhichIsA("Humanoid")
			local seat = hum and hum.SeatPart
			return (seat and seat.Parent) and (seat:FindFirstAncestorWhichIsA("Model") or seat) or nil
		end
		local function rootsForScope()
			local s = (Options.veScope and Options.veScope.Value) or "Held Tool"
			local c = lPlayer.Character
			if s == "Held Tool" then return { c and c:FindFirstChildWhichIsA("Tool") } end
			if s == "Character" then return { c } end
			if s == "Backpack" then return { lPlayer:FindFirstChild("Backpack") } end
			if s == "Player + leaderstats" then return { lPlayer:FindFirstChild("Backpack"), lPlayer:FindFirstChild("leaderstats"), lPlayer:FindFirstChildOfClass("PlayerGui"), c } end
			if s == "Seated Vehicle" then return { seatedVehicle() } end
			if s == "Workspace (heavy)" then return { Workspace } end
			return { c }
		end

		scanG:AddDropdown("veScope", { Text = "Scope", Values = { "Held Tool", "Character", "Backpack", "Player + leaderstats", "Seated Vehicle", "Workspace (heavy)" }, Default = "Held Tool", Multi = false, AllowNull = false }); ctx:Control("veScope")
		scanG:AddInput("veSearch", { Text = "Name contains", Default = "", Tooltip = "Filter found values by name (e.g. ammo, speed). Empty = all." }); ctx:Control("veSearch")
		scanG:AddDropdown("veFound", { Text = "Found values", Values = {}, Multi = false, AllowNull = true, Tooltip = "Scan or Pick first, then choose a value to edit." }); ctx:Control("veFound")
		local veInfo = scanG:AddLabel("Scan, or use Pick from HUD.", true)

		local function buildList(items)
			found = {}
			local entries = {}
			local cg, cy, cr = 0, 0, 0
			for _, it in ipairs(items) do
				local cur = it.fld.read()
				local rate, reason = rateField(it.name, it.inst)
				if rate == "green" then cg = cg + 1 elseif rate == "red" then cr = cr + 1 else cy = cy + 1 end
				-- prefix with a +/?/! symbol (dropdowns can't colour per row); the selected
				-- value's info label below shows the actual green/yellow/red colour.
				local base = (RATE_SYM[rate] or "") .. it.name .. " = " .. tostring(cur)
				local key, i2 = base, 2
				while found[key] do key = base .. " #" .. i2; i2 = i2 + 1 end
				found[key] = { fld = it.fld, rate = rate, reason = reason }; entries[#entries + 1] = key
			end
			table.sort(entries)
			Options.veFound.Values = entries
			pcall(function() Options.veFound:SetValues() end)
			pcall(function() tint(veInfo, nil) end)
			pcall(function() veInfo:SetText(("%d found:  +%d safe   ?%d test   !%d watched/server\nPick one -- colour shows how likely it works/is safe."):format(#entries, cg, cy, cr)) end)
		end

		scanG:AddButton("Scan Values", function()
			local items, q = {}, (Options.veSearch.Value or ""):lower()
			local cap = ((Options.veScope.Value or "") == "Workspace (heavy)") and 40000 or 8000
			for _, r in ipairs(rootsForScope()) do collect(r, q, nil, items, cap) end
			buildList(items)
		end):AddToolTip("List numeric values in the chosen scope (filtered by the name box).")

		Options.veFound:OnChanged(function()
			local k = Options.veFound.Value
			local entry = k and found[k] or nil
			selField = entry and entry.fld or nil
			if entry then
				pcall(function() veInfo:SetText(("Selected: %s\nCurrent: %s\nRating: %s -- %s"):format(selField.path, tostring(selField.read()), entry.rate:upper(), entry.reason)) end)
				pcall(function() tint(veInfo, entry.rate) end)
			end
		end)

		-- ---- Pick from HUD: click a number on screen -> find the value(s) behind it ----
		pickG:AddLabel("Click a NUMBER on your screen (ammo, speed, money)\nand this finds every value currently equal to it.", true)
		pickG:AddButton("Pick HUD Number (click)", function()
			local pg = lPlayer:FindFirstChildOfClass("PlayerGui")
			if not pg then Library:Notify("No PlayerGui"); return end
			Library:Notify("Click the number on your screen...")
			local conn
			conn = UserInputService.InputBegan:Connect(function(i)
				if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
				if conn then conn:Disconnect(); conn = nil end
				local pos = UserInputService:GetMouseLocation()
				local num
				pcall(function()
					for _, dy in ipairs({ 0, -36 }) do  -- try with + without the 36px GUI inset
						for _, o in ipairs(pg:GetGuiObjectsAtPosition(pos.X, pos.Y + dy)) do
							if o:IsA("TextLabel") or o:IsA("TextButton") then
								local m = tostring(o.Text):match("%-?%d+%.?%d*")
								if m then num = tonumber(m); break end
							end
						end
						if num then break end
					end
				end)
				if not num then Library:Notify("No number under the cursor"); return end
				local items = {}
				collect(lPlayer.Character, "", num, items, 8000)
				collect(lPlayer:FindFirstChild("Backpack"), "", num, items, 8000)
				collect(lPlayer:FindFirstChild("leaderstats"), "", num, items, 4000)
				collect(lPlayer:FindFirstChildOfClass("PlayerGui"), "", num, items, 8000)
				collect(seatedVehicle(), "", num, items, 8000)
				collect(Workspace, "", num, items, 40000)
				buildList(items)
				Library:Notify("HUD number " .. num .. " -> " .. #items .. " matching value(s)")
			end)
		end):AddToolTip("Arm, then click a HUD number. Finds every value currently equal to it\n(narrow it down with the name box / by changing the number in-game).")

		-- ---- Set / Hold ----
		setG:AddInput("veSetValue", { Text = "New Value", Default = "999", Tooltip = "Number to write to the selected value." }); ctx:Control("veSetValue")
		local function newVal() return tonumber(Options.veSetValue.Value) end
		setG:AddButton("Set Once", function()
			local v = newVal()
			if not selField then Library:Notify("Pick a value first") elseif not v then Library:Notify("New Value isn't a number")
			else selField.write(v); Library:Notify("Set " .. selField.path .. " -> " .. v) end
		end):AddToolTip("Write New Value to the selected value once.")
		setG:AddToggle("veHold", { Text = "Hold Value", Default = false, Tooltip = "Keep writing New Value to the selected value every tick, so the\ngame can't reset it. (Default: OFF)" }); ctx:Control("veHold")
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.veHold and Toggles.veHold.Value and selField) then return end
			local now = tick(); if now - lastHold < 0.1 then return end; lastHold = now
			if selField.alive and not selField.alive() then return end
			local v = newVal(); if v then selField.write(v) end
		end)

		-- ---- tutorial ----
		local howG = ctx:Groupbox("How to Use", "right")
		howG:AddLabel(
			"Change ANY value -- ammo, speed cap, money...\n\n" ..
			"EASY WAY (Pick from HUD):\n" ..
			"  1. 'Pick HUD Number', then click the number\n" ..
			"     on your screen (e.g. ammo or speed).\n" ..
			"  2. Open 'Found values', pick the match.\n" ..
			"  3. Type New Value, hit Set Once or Hold.\n\n" ..
			"MANUAL WAY: set Scope (Held Tool / Seated\n" ..
			"Vehicle / etc.), type a name in the box, Scan,\n" ..
			"pick, Set/Hold.\n\n" ..
			"Too many matches? Change the number in-game\n" ..
			"(fire / drive) and Pick again -- only the real\n" ..
			"one keeps matching.\n\n" ..
			"COLOUR = detectability:\n" ..
			"  +  green = client-side (yours) -- best bet\n" ..
			"  ?  yellow = shared/leaderstats -- test it\n" ..
			"  !  red = server-validated or anti-cheat\n" ..
			"     watches it -- may not stick / may flag.\n" ..
			"Run Phantom Probe (Calibrate Tier 4) first so\n" ..
			"red can flag values the AC actually watches.",
			true)

		pluginCleanup = function() end  -- ctx clears keys/connections/groupboxes
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
