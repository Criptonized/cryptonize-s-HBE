-- CryptsHBE plugin: DeepDive  (extended reverse-engineering)
-- ============================================================================
-- The heavy companion to the core's Deep-Dump buttons. The basic dump writes the tree +
-- string constants; this goes deeper:
--   * REQUIRES config/tune/stat modules and dumps their real values (+ probes GetValue-
--     style accessors like TREK), and dumps script UPVALUES (where cached stat tables live).
--   * VEHICLE: profiles weapon system / ammo / tracked-vs-wheeled (core does the quick
--     version), correlates OPERATOR TOOLS in your taskbar that drive the turret via the
--     vehicle's remotes, and lists the vehicle's remotes.
--   * INVENTORY: dumps custom (non-Tool) inventories -- the Bleeding Blades case where the
--     weapon reader sees nothing -- by walking your Character/Player + ReplicatedStorage
--     templates and flagging the equipped weapon, plus combat-related remotes.
--   * REMOTES: dumps every RemoteEvent/Function in the game with paths (+ combat filter).
-- Registers Bridge.ExtendedDump { vehicle, weapon, inventory, remotes } so the core's
-- "Extended Deep Dive" sub-button drives it. All output -> workspace/CryptsHBE/. Pure read.
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

local WEAPON_WORDS = { "blade", "sword", "shield", "bow", "crossbow", "arrow", "spear", "pike",
	"axe", "mace", "hilt", "handle", "dagger", "halberd", "javelin", "helmet", "armor", "armour",
	"composite", "buttspike", "woodshaft", "metalblade", "projectile", "quiver", "sling", "gun",
	"rifle", "pistol", "knife", "club", "hammer", "staff", "wand", "katana", "scimitar" }
local COMBAT_REMOTE_WORDS = { "hit", "damage", "dmg", "swing", "attack", "block", "parry", "shoot",
	"fire", "bow", "draw", "melee", "stab", "slash", "hurt", "combat", "weapon", "strike", "wound", "kill" }
local CFG_NAMES = { "config", "setting", "stat", "data", "tune", "value", "info", "properties", "props", "balance" }
local STAT_KEYS = { "WindUp", "WindDown", "Charged", "BurstAmount", "RaysPerShot", "baseSpread",
	"ReloadSpeed", "RecoilX", "RecoilY", "RecoilZ", "ProjectileVelocity", "Damage", "MagCapacity",
	"ReservedAmmo", "FireRate", "RPM", "Cooldown", "FireDelay", "Rate", "Range", "Ammo", "Reload" }

local function hasWord(n, words) n = tostring(n):lower() for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end return false end
local function looksCfg(n) return hasWord(n, CFG_NAMES) end

local function writeOut(fname, lines)
	local text = table.concat(lines, "\n")
	local b = getgenv().CryptsHBE
	if b and b.SessionName then pcall(function() fname = b:SessionName(fname) end) end   -- _S<N> session tag
	pcall(function()
		if makefolder and not (isfolder and isfolder("CryptsHBE")) then makefolder("CryptsHBE") end
		if writefile then writefile("CryptsHBE/" .. fname, text) end
	end)
	if Library then Library:Notify("Saved -> workspace/CryptsHBE/" .. fname) end
end

-- deep-dump a required module table (values + nested, capped) and probe a GetValue accessor.
local function dumpModuleTable(mod, lines, indent)
	indent = indent or "  "
	local n = 0
	local function walk(t, prefix, dep, seen)
		if dep > 3 or seen[t] or n > 200 then return end
		seen[t] = true
		for k, v in pairs(t) do
			local tv = type(v)
			if tv == "number" or tv == "boolean" or tv == "string" then
				n = n + 1; lines[#lines + 1] = indent .. prefix .. tostring(k) .. " = " .. tostring(v)
			elseif tv == "table" then walk(v, prefix .. tostring(k) .. ".", dep + 1, seen)
			elseif tv == "function" and tostring(k):lower():find("getvalue") then
				lines[#lines + 1] = indent .. prefix .. tostring(k) .. " = <accessor function>"
			end
		end
	end
	walk(mod, "", 1, {})
	-- GetValue probe
	local gv = type(mod) == "table" and (rawget(mod, "GetValue") or mod.GetValue)
	if type(gv) == "function" then
		lines[#lines + 1] = indent .. "[GetValue probes]"
		for _, key in ipairs(STAT_KEYS) do
			local function pick(...) for i = 1, select("#", ...) do local a = select(i, ...) if a ~= nil then return a end end end
			local o1, v1 = pcall(gv, mod, key); local o2, v2 = pcall(gv, key)
			local vv = pick(o1 and v1, o2 and v2)
			if vv ~= nil and type(vv) ~= "table" and type(vv) ~= "function" then lines[#lines + 1] = indent .. "  GetValue(" .. key .. ") = " .. tostring(vv) end
		end
		if debug and debug.getupvalues then
			local ok, ups = pcall(debug.getupvalues, gv)
			if ok and type(ups) == "table" then
				for i, uv in pairs(ups) do
					if type(uv) == "table" then
						lines[#lines + 1] = indent .. "  upval[" .. tostring(i) .. "] {table}:"
						pcall(function() for k, v in pairs(uv) do if type(v) ~= "table" and type(v) ~= "function" then lines[#lines + 1] = indent .. "    " .. tostring(k) .. " = " .. tostring(v) end end end)
					elseif type(uv) ~= "function" then lines[#lines + 1] = indent .. "  upval[" .. tostring(i) .. "] = " .. tostring(uv) end
				end
			end
		end
	end
end

-- dump a script's upvalues (numeric/string/table) -- where stats get cached at runtime.
local function dumpScriptUpvalues(inst, lines)
	pcall(function()
		if not (getscriptclosure and debug and debug.getupvalues) then return end
		local cl = getscriptclosure(inst); if not cl then return end
		local seen = {}
		local function harvest(fn)
			local ok, ups = pcall(debug.getupvalues, fn)
			if not ok or type(ups) ~= "table" then return end
			for i, uv in pairs(ups) do
				local tv = type(uv)
				if tv == "number" or tv == "boolean" or tv == "string" then
					lines[#lines + 1] = "      uv[" .. tostring(i) .. "] = " .. tostring(uv)
				elseif tv == "table" and not seen[uv] then
					seen[uv] = true
					lines[#lines + 1] = "      uv[" .. tostring(i) .. "] {table}:"
					pcall(function() local c = 0 for k, v in pairs(uv) do if (type(v) == "number" or type(v) == "string" or type(v) == "boolean") and c < 30 then c = c + 1; lines[#lines + 1] = "        " .. tostring(k) .. " = " .. tostring(v) end end end)
				end
			end
		end
		harvest(cl)
		pcall(function() for _, p in ipairs((debug.getprotos and debug.getprotos(cl)) or {}) do harvest(p) end end)
	end)
end

local function requireAndDumpModules(root, lines, onlyConfig)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ModuleScript") and ((not onlyConfig) or looksCfg(d.Name)) then
			lines[#lines + 1] = "  ModuleScript " .. d:GetFullName()
			local ok, mod = pcall(require, d)
			if ok and type(mod) == "table" then dumpModuleTable(mod, lines, "    ")
			else lines[#lines + 1] = "    (require failed or not a table: " .. tostring(mod) .. ")" end
		end
	end
end

local function listRemotes(root, lines, filterWords)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
			if (not filterWords) or hasWord(d.Name, filterWords) then
				n = n + 1; if n <= 400 then lines[#lines + 1] = "  " .. d.ClassName .. " '" .. d.Name .. "'  @ " .. d:GetFullName() end
			end
		end
	end
	return n
end

-- ===== ExtendedDump implementations =====
local function extVehicle(model)
	if not model then if Library then Library:Notify("No vehicle") end return end
	local b = getgenv().CryptsHBE
	-- base structural dump (now includes the Vehicle Profile)
	pcall(function() b:DeepDumpModel(model, "Vehicle", "vehicle_dump_" .. tostring(game.PlaceId) .. ".txt",
		{ "speed", "velocity", "throttle", "torque", "power", "engine", "drive", "rpm", "gear", "accel", "chassis", "vehicle", "fuel", "gas", "ammo", "turret", "shell", "rocket" }) end)
	-- extended analysis
	local L = { "=== EXTENDED Vehicle Deep Dive ===", "Model: " .. model.Name, "PlaceId: " .. tostring(game.PlaceId),
		"(see vehicle_dump_*.txt for the full tree + Vehicle Profile)", "" }
	L[#L + 1] = "--- required modules (values + GetValue probes) ---"
	requireAndDumpModules(model, L, false)
	L[#L + 1] = ""
	L[#L + 1] = "--- script upvalues (cached stat tables) ---"
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LocalScript") or d:IsA("Script") then L[#L + 1] = "  " .. d:GetFullName(); dumpScriptUpvalues(d, L) end
	end
	L[#L + 1] = ""
	L[#L + 1] = "--- vehicle remotes ---"
	listRemotes(model, L, nil)
	-- operator-tool correlation: taskbar tools whose scripts reference this vehicle's remotes
	L[#L + 1] = ""
	L[#L + 1] = "--- operator tools (taskbar tools that may drive this vehicle) ---"
	local remoteNames = {}
	pcall(function() for _, d in ipairs(model:GetDescendants()) do if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then remoteNames[d.Name:lower()] = true end end end)
	local function scanToolFor(tool)
		local hit = false
		pcall(function()
			for _, s in ipairs(tool:GetDescendants()) do
				if (s:IsA("LocalScript") or s:IsA("ModuleScript")) and getscriptclosure and debug and debug.getconstants then
					local cl = getscriptclosure(s); if cl then
						for _, c in ipairs(debug.getconstants(cl) or {}) do
							if type(c) == "string" and (remoteNames[c:lower()] or hasWord(c, { "turret", "vehicle", "mount", "operate" })) then hit = true break end
						end
					end
				end
				if hit then break end
			end
		end)
		return hit
	end
	for _, where in ipairs({ lPlayer:FindFirstChild("Backpack"), lPlayer.Character }) do
		if where then for _, t in ipairs(where:GetChildren()) do if t:IsA("Tool") then
			L[#L + 1] = "  Tool '" .. t.Name .. "'  -> " .. (scanToolFor(t) and "LIKELY operates this vehicle (references its remotes)" or "no reference")
		end end end
	end
	writeOut("vehicle_extended_" .. tostring(game.PlaceId) .. ".txt", L)
end

local function extWeapon(tool)
	tool = tool or (lPlayer.Character and lPlayer.Character:FindFirstChildWhichIsA("Tool"))
	if not tool then if Library then Library:Notify("Hold a weapon first") end return end
	local b = getgenv().CryptsHBE
	pcall(function() b:DeepDumpModel(tool, "Weapon", "weapon_dump_" .. tostring(game.PlaceId) .. ".txt",
		{ "fire", "shoot", "hit", "damage", "reload", "weapon", "gun", "bullet", "swing", "melee", "bow", "arrow" }) end)
	local L = { "=== EXTENDED Weapon Deep Dive ===", "Tool: " .. tool.Name, "PlaceId: " .. tostring(game.PlaceId), "" }
	L[#L + 1] = "--- required modules (values + GetValue probes) ---"
	requireAndDumpModules(tool, L, false)
	L[#L + 1] = ""
	L[#L + 1] = "--- script upvalues ---"
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("LocalScript") or d:IsA("Script") then L[#L + 1] = "  " .. d:GetFullName(); dumpScriptUpvalues(d, L) end
	end
	writeOut("weapon_extended_" .. tostring(game.PlaceId) .. ".txt", L)
end

-- Bleeding-Blades-style custom inventory (weapons aren't Tools): walk Character + Player +
-- ReplicatedStorage templates, flag the equipped weapon, list combat remotes.
local function extInventory()
	local L = { "=== Inventory Deep Dive (custom / non-Tool) ===", "PlaceId: " .. tostring(game.PlaceId), "" }
	local char = lPlayer.Character
	-- equipped weapon: Models welded into the character, or weapon-named parts
	L[#L + 1] = "--- equipped / character weapon parts ---"
	if char then
		pcall(function()
			for _, d in ipairs(char:GetChildren()) do
				if d:IsA("Model") or d:IsA("Tool") then L[#L + 1] = "  " .. d.ClassName .. " '" .. d.Name .. "'" end
			end
			local n = 0
			for _, d in ipairs(char:GetDescendants()) do
				if (d:IsA("BasePart") or d:IsA("Model")) and hasWord(d.Name, WEAPON_WORDS) and n < 60 then
					n = n + 1; L[#L + 1] = "    weapon-part: " .. d.ClassName .. " '" .. d.Name .. "' @ " .. d:GetFullName()
				end
			end
		end)
	else L[#L + 1] = "  (no character)" end
	-- player-side inventory state (folders / ObjectValues / string slots)
	L[#L + 1] = ""
	L[#L + 1] = "--- player inventory state (folders/values under Player) ---"
	pcall(function()
		for _, d in ipairs(lPlayer:GetDescendants()) do
			if d:IsA("Folder") or d:IsA("ObjectValue") or d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue") then
				if hasWord(d.Name, { "inventory", "equip", "slot", "hotbar", "weapon", "item", "loadout", "selected", "current" }) then
					local val = ""; pcall(function() if d:IsA("ValueBase") then val = " = " .. tostring(d.Value) end end)
					L[#L + 1] = "  " .. d.ClassName .. " '" .. d.Name .. "'" .. val .. "  @ " .. d:GetFullName()
				end
			end
		end
	end)
	-- ReplicatedStorage weapon templates
	L[#L + 1] = ""
	L[#L + 1] = "--- ReplicatedStorage weapon/item templates ---"
	pcall(function()
		local n = 0
		for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
			if (d:IsA("Model") or d:IsA("Tool") or d:IsA("Folder")) and hasWord(d.Name, WEAPON_WORDS) and n < 120 then
				n = n + 1; L[#L + 1] = "  " .. d.ClassName .. " '" .. d.Name .. "' @ " .. d:GetFullName()
			end
		end
	end)
	-- combat remotes (the Invalid-Attack workaround needs the real damage remote)
	L[#L + 1] = ""
	L[#L + 1] = "--- combat remotes (the hit/damage path to replicate) ---"
	local n = listRemotes(game, L, COMBAT_REMOTE_WORDS)
	L[#L + 1] = "(" .. n .. " combat-named remotes; full list via 'All Remotes Dump')"
	writeOut("inventory_dump_" .. tostring(game.PlaceId) .. ".txt", L)
end

local function extRemotes()
	local L = { "=== All Remotes Dump ===", "PlaceId: " .. tostring(game.PlaceId), "" }
	local n = listRemotes(game, L, nil)
	L[#L + 1] = ""
	L[#L + 1] = "Total listed: " .. n
	writeOut("remotes_dump_" .. tostring(game.PlaceId) .. ".txt", L)
end

return {
	name = "DeepDive", tab = "DeepDive", requires = {},
	load = function(ctx)
		local b = getgenv().CryptsHBE
		b.ExtendedDump = { vehicle = extVehicle, weapon = extWeapon, inventory = extInventory, remotes = extRemotes }

		local function seatedVehicle()
			local c = lPlayer.Character
			local hum = c and c:FindFirstChildWhichIsA("Humanoid")
			local seat = hum and hum.SeatPart
			return (seat and seat.Parent) and (seat:FindFirstAncestorWhichIsA("Model") or seat) or nil
		end

		local g = ctx:Groupbox("Extended Deep Dive", "left")
		g:AddButton("Extended Held Weapon", function() extWeapon() end):AddToolTip("Deep dump the held tool: required module values + GetValue probes + script upvalues.")
		g:AddButton("Extended Seated Vehicle", function()
			local m = seatedVehicle()
			if not m then Library:Notify("Sit in a vehicle first (or use the core's Extended Deep Dive for hold-pick)"); return end
			extVehicle(m)
		end):AddToolTip("Deep dump the vehicle you're seated in: modules, upvalues, remotes, operator-tool correlation.")
		g:AddButton("Inventory Dump (custom)", function() extInventory() end):AddToolTip("For games whose weapons aren't Tools (e.g. Bleeding Blades): dumps character/player\ninventory + ReplicatedStorage templates + combat remotes -- the data for the Invalid-Attack fix.")
		g:AddButton("All Remotes Dump", function() extRemotes() end):AddToolTip("List every RemoteEvent/RemoteFunction in the game with full paths.")

		local gInfo = ctx:Groupbox("About", "right")
		gInfo:AddLabel(
			"Heavier reverse-engineering than the core\n" ..
			"Deep-Dump buttons. Outputs go to\n" ..
			"workspace/CryptsHBE/:\n" ..
			"  weapon_extended_*  vehicle_extended_*\n" ..
			"  inventory_dump_*   remotes_dump_*\n\n" ..
			"It REQUIRES config modules + reads script\n" ..
			"UPVALUES, so it surfaces values the static\n" ..
			"dump can't (TREK-style GetValue stats,\n" ..
			"cached tables).\n\n" ..
			"The core's 'Extended Deep Dive' button\n" ..
			"(Calibrate) drives this plugin's vehicle\n" ..
			"dump when it's enabled.\n\n" ..
			"Send the saved files back to add tailored\n" ..
			"hacks for that game.",
			true)

		pluginCleanup = function() if b.ExtendedDump then b.ExtendedDump = nil end end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
