-- CryptsHBE plugin: Recon  (the deep-dive analysis suite)
-- ============================================================================
-- One tab of read-only reverse-engineering tools (the "draft deep dives"). Each writes a
-- report to workspace/CryptsHBE/ (session-tagged) and several print a one-line verdict:
--   * Damage Model  -- per held weapon: touch / raycast / remote? -> RECOMMENDS which combat
--                      tool to use (and warns when HBE would be rejected as an invalid hit).
--   * Module API    -- require every ReplicatedStorage ModuleScript + dump its table shape.
--   * GC / Closures -- getgc scan for config/stat/ammo/anti tables + functions.
--   * Networking    -- isnetworkowner / simulation map (what you can physics-control).
--   * Animation     -- the held tool's animation IDs + tracks playing on you (+ lengths).
--   * Input / Binds -- KeyCodes referenced by LocalScripts (infer the game's hotkeys).
--   * Map / World   -- spawns, teams, objectives, loot/ammo crates, prompts, seats.
--   * Economy/Shop  -- leaderstats + currency + shop items/prices + purchase remotes.
--   * Character/Rig -- a target's rig: parts/bones/joints/hitbox names (to set HBE bones).
--   * Anti-Cheat    -- summarise Phantom Recon (watched props/honeypots) + AC-named scripts.
-- Pure read. Requiring modules shares the game's cache. Send the files back for tailored hacks.
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Teams = game:GetService("Teams")
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

local function has(n, words) n = tostring(n):lower() for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end return false end
local COMBAT = { "hit", "damage", "dmg", "swing", "attack", "shoot", "fire", "melee", "stab", "slash", "strike", "wound", "bow", "block", "parry" }
local CURRENCY = { "cash", "money", "coin", "credit", "point", "gold", "gem", "token", "currency", "xp", "level", "rank" }
local SHOP = { "buy", "purchase", "shop", "store", "spend", "unlock", "redeem", "sell", "price", "cost" }
local OBJECTIVE = { "flag", "objective", "capture", "point", "zone", "cap", "control", "base", "spawn" }
local LOOT = { "crate", "ammo", "supply", "loot", "box", "cache", "pickup", "resupply", "kit" }

local function writeOut(fname, lines)
	local b = getgenv().CryptsHBE
	if b and b.SessionName then pcall(function() fname = b:SessionName(fname) end) end
	pcall(function()
		if makefolder and not (isfolder and isfolder("CryptsHBE")) then makefolder("CryptsHBE") end
		if writefile then writefile("CryptsHBE/" .. fname, table.concat(lines, "\n")) end
	end)
	if Library then Library:Notify("Saved -> workspace/CryptsHBE/" .. fname) end
end
-- harvest a script's string constants (read-only)
local function consts(inst)
	local out = {}
	pcall(function()
		if not (getscriptclosure and debug and debug.getconstants) then return end
		local cl = getscriptclosure(inst); if not cl then return end
		local function h(fn) for _, c in ipairs(debug.getconstants(fn) or {}) do if type(c) == "string" then out[#out + 1] = c end end end
		h(cl); pcall(function() for _, p in ipairs((debug.getprotos and debug.getprotos(cl)) or {}) do h(p) end end)
	end)
	return out
end
local function heldTool() local c = lPlayer.Character return c and c:FindFirstChildWhichIsA("Tool") or nil end
local function nearestEnemy()
	local c = lPlayer.Character; local lr = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
	if not lr then return nil end
	local best, bd
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lPlayer then
			local pc = p.Character; local pr = pc and (pc:FindFirstChild("HumanoidRootPart") or pc:FindFirstChild("Head"))
			if pr then local d = (pr.Position - lr.Position).Magnitude; if not bd or d < bd then best, bd = p, d end end
		end
	end
	return best
end

-- ===== 1. Damage Model =====
local function damageModel(setLabel)
	local tool = heldTool()
	local L = { "=== Damage Model ===", "PlaceId: " .. tostring(game.PlaceId), "Tool: " .. (tool and tool.Name or "none held") }
	local touch, ray, remote = 0, false, false
	local scope = tool or lPlayer.Character
	if scope then
		pcall(function()
			for _, d in ipairs(scope:GetDescendants()) do
				if d:IsA("BasePart") then
					local ok, c = pcall(function() return getconnections and getconnections(d.Touched) end)
					if ok and type(c) == "table" then touch = touch + #c end
				elseif d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Script") then
					for _, k in ipairs(consts(d)) do
						local lk = k:lower()
						if lk:find("raycast") or lk:find("findpartonray") or lk == "raycastparams" then ray = true end
						if lk == "fireserver" or lk == "invokeserver" then remote = true end
					end
				end
			end
		end)
	end
	L[#L + 1] = ("Signals: touch-connections=%d  raycast=%s  remote=%s"):format(touch, tostring(ray), tostring(remote))
	local verdict
	if remote and not (touch > 0) then verdict = "REMOTE-based: HBE won't help (server may reject as 'invalid'). Use Remote Sniffer to capture the hit remote, then Remote Replay."
	elseif touch > 0 then verdict = "TOUCH-based: Silent Melee + Tool Hitbox / HBE work (the game's .Touched lands the hit)."
	elseif ray then verdict = "RAYCAST-based: needs aim/silent-aim; HBE won't register the hit; server may validate the ray."
	else verdict = "UNKNOWN: capture a hit with the Remote Sniffer to see the real path." end
	L[#L + 1] = "RECOMMENDATION: " .. verdict
	writeOut("damage_model_" .. tostring(game.PlaceId) .. ".txt", L)
	if setLabel then pcall(function() setLabel:SetText("Damage: " .. (tool and tool.Name or "no tool") .. "\n" .. verdict) end) end
end

-- ===== 2. Module API Mapper =====
local function moduleApi()
	local L = { "=== Module API Map (ReplicatedStorage) ===", "PlaceId: " .. tostring(game.PlaceId), "" }
	local n = 0
	pcall(function()
		for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
			if d:IsA("ModuleScript") and n < 250 then
				n = n + 1
				local ok, mod = pcall(require, d)
				L[#L + 1] = d:GetFullName() .. "  -> " .. (ok and type(mod) or ("ERR " .. tostring(mod)))
				if ok and type(mod) == "table" then
					local keys = {}
					pcall(function() for k, v in pairs(mod) do keys[#keys + 1] = tostring(k) .. ":" .. type(v); if #keys > 40 then break end end end)
					if #keys > 0 then L[#L + 1] = "    { " .. table.concat(keys, ", ") .. " }" end
				end
			end
		end
	end)
	L[#L + 1] = ""; L[#L + 1] = "Modules listed: " .. n
	writeOut("module_api_" .. tostring(game.PlaceId) .. ".txt", L)
end

-- ===== 3. GC / Closures =====
local function gcScan()
	local L = { "=== GC / Closure Scan ===", "PlaceId: " .. tostring(game.PlaceId), "" }
	local KW = { "config", "stat", "ammo", "health", "speed", "damage", "anti", "cheat", "money", "cash", "fire", "reload" }
	pcall(function()
		if not getgc then L[#L + 1] = "(getgc unavailable)"; return end
		local nt, nf = 0, 0
		for _, o in ipairs(getgc(true)) do
			if type(o) == "table" and nt < 80 then
				local keyhit, sample = false, {}
				pcall(function()
					for k, v in pairs(o) do
						if type(k) == "string" then
							if has(k, KW) then keyhit = true end
							if #sample < 6 and (type(v) == "number" or type(v) == "string" or type(v) == "boolean") then sample[#sample + 1] = k .. "=" .. tostring(v) end
						end
					end
				end)
				if keyhit and #sample > 0 then nt = nt + 1; L[#L + 1] = "table { " .. table.concat(sample, ", ") .. " }" end
			elseif type(o) == "function" and nf < 60 then
				pcall(function()
					local info = debug.getinfo and debug.getinfo(o)
					if info and info.name and has(info.name, KW) then nf = nf + 1; L[#L + 1] = "fn " .. tostring(info.name) .. " @ " .. tostring(info.source) end
				end)
			end
		end
		L[#L + 1] = ""; L[#L + 1] = ("tables hit=%d  functions hit=%d"):format(nt, nf)
	end)
	writeOut("gc_scan_" .. tostring(game.PlaceId) .. ".txt", L)
end

-- ===== 4. Networking / Ownership =====
local function networking()
	local L = { "=== Networking / Ownership ===", "PlaceId: " .. tostring(game.PlaceId), "" }
	pcall(function() L[#L + 1] = "your sim radius: " .. tostring(lPlayer.SimulationRadius) end)
	local function ownStr(part) local ok, own = pcall(function() return isnetworkowner and isnetworkowner(part) end) return ok and tostring(own) or "?" end
	local c = lPlayer.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	if hrp then L[#L + 1] = "your HRP owner: " .. ownStr(hrp) end
	-- seated vehicle
	local hum = c and c:FindFirstChildWhichIsA("Humanoid")
	local seat = hum and hum.SeatPart
	local veh = seat and (seat:FindFirstAncestorWhichIsA("Model"))
	if veh then
		L[#L + 1] = ""; L[#L + 1] = "seated vehicle: " .. veh.Name
		local n = 0
		for _, d in ipairs(veh:GetDescendants()) do
			if d:IsA("BasePart") and n < 30 then n = n + 1; L[#L + 1] = "  " .. d.Name .. " owner=" .. ownStr(d) end
		end
	else L[#L + 1] = "seated vehicle: none" end
	writeOut("networking_" .. tostring(game.PlaceId) .. ".txt", L)
end

-- ===== 5. Animation / Timing =====
local function animation()
	local L = { "=== Animation / Timing ===", "PlaceId: " .. tostring(game.PlaceId), "" }
	local tool = heldTool()
	if tool then
		L[#L + 1] = "Tool " .. tool.Name .. " animation values:"
		pcall(function()
			for _, d in ipairs(tool:GetDescendants()) do
				if d:IsA("Animation") then L[#L + 1] = "  Animation " .. d.Name .. " = " .. d.AnimationId
				elseif (d:IsA("NumberValue") or d:IsA("StringValue")) and has(d.Name, { "anim", "idle", "reload", "fire", "equip", "melee", "bolt", "aim", "run" }) then
					L[#L + 1] = "  " .. d.ClassName .. " " .. d.Name .. " = " .. tostring(d.Value)
				end
			end
		end)
	else L[#L + 1] = "(no tool held)" end
	L[#L + 1] = ""; L[#L + 1] = "Tracks playing on you:"
	pcall(function()
		local hum = lPlayer.Character and lPlayer.Character:FindFirstChildWhichIsA("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then for _, t in ipairs(animator:GetPlayingAnimationTracks()) do L[#L + 1] = ("  %s  len=%.2f speed=%.2f"):format(t.Name, t.Length, t.Speed) end end
	end)
	writeOut("animation_" .. tostring(game.PlaceId) .. ".txt", L)
end

-- ===== 6. Input / Binds =====
local function inputBinds()
	local L = { "=== Input / Binds (KeyCodes referenced by LocalScripts) ===", "PlaceId: " .. tostring(game.PlaceId), "" }
	local seen = {}
	pcall(function()
		local n = 0
		for _, d in ipairs(game:GetDescendants()) do
			if (d:IsA("LocalScript")) and n < 200 then
				local keys = {}
				for _, k in ipairs(consts(d)) do
					-- KeyCode enum names are usually single letters or known names referenced as strings
					if #k >= 1 and #k <= 14 and (k:match("^%u%l+$") or #k == 1) and Enum.KeyCode[k] ~= nil then keys[k] = true end
				end
				local list = {}; for k in pairs(keys) do list[#list + 1] = k end
				if #list > 0 then n = n + 1; L[#L + 1] = d:GetFullName() .. ": " .. table.concat(list, ", ") end
			end
		end
	end)
	writeOut("input_binds_" .. tostring(game.PlaceId) .. ".txt", L)
end

-- ===== 7. Map / World =====
local function mapWorld()
	local L = { "=== Map / World ===", "PlaceId: " .. tostring(game.PlaceId), "" }
	pcall(function() L[#L + 1] = "Teams: " .. table.concat((function() local t = {} for _, tm in ipairs(Teams:GetTeams()) do t[#t + 1] = tm.Name end return t end)(), ", ") end)
	local function dumpMatch(label, pred, cap)
		L[#L + 1] = ""; L[#L + 1] = "-- " .. label .. " --"
		local n = 0
		pcall(function() for _, d in ipairs(Workspace:GetDescendants()) do if n < cap and pred(d) then n = n + 1; L[#L + 1] = "  " .. d.ClassName .. " '" .. d.Name .. "' @ " .. d:GetFullName() end end end)
	end
	dumpMatch("spawns", function(d) return d:IsA("SpawnLocation") end, 40)
	dumpMatch("objectives", function(d) return (d:IsA("BasePart") or d:IsA("Model")) and has(d.Name, OBJECTIVE) end, 60)
	dumpMatch("loot/ammo", function(d) return (d:IsA("BasePart") or d:IsA("Model")) and has(d.Name, LOOT) end, 60)
	dumpMatch("prompts", function(d) return d:IsA("ProximityPrompt") end, 60)
	dumpMatch("seats", function(d) return d:IsA("VehicleSeat") or d:IsA("Seat") end, 40)
	writeOut("map_world_" .. tostring(game.PlaceId) .. ".txt", L)
end

-- ===== 8. Economy / Shop =====
local function economy()
	local L = { "=== Economy / Shop ===", "PlaceId: " .. tostring(game.PlaceId), "" }
	L[#L + 1] = "-- leaderstats / currency on you --"
	pcall(function()
		for _, d in ipairs(lPlayer:GetDescendants()) do
			if (d:IsA("IntValue") or d:IsA("NumberValue")) and has(d.Name, CURRENCY) then L[#L + 1] = "  " .. d.Name .. " = " .. tostring(d.Value) .. " @ " .. d:GetFullName() end
		end
	end)
	L[#L + 1] = ""; L[#L + 1] = "-- shop items / prices (ReplicatedStorage) --"
	pcall(function()
		local n = 0
		for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
			if n < 120 and ((d:IsA("Folder") or d:IsA("Configuration")) and has(d.Name, SHOP)) then n = n + 1; L[#L + 1] = "  " .. d.ClassName .. " '" .. d.Name .. "' @ " .. d:GetFullName()
			elseif n < 120 and (d:IsA("IntValue") or d:IsA("NumberValue")) and has(d.Name, { "price", "cost" }) then n = n + 1; L[#L + 1] = "  " .. d.Name .. " = " .. tostring(d.Value) .. " @ " .. d:GetFullName() end
		end
	end)
	L[#L + 1] = ""; L[#L + 1] = "-- purchase remotes --"
	pcall(function() for _, d in ipairs(game:GetDescendants()) do if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and has(d.Name, SHOP) then L[#L + 1] = "  " .. d.ClassName .. " '" .. d.Name .. "' @ " .. d:GetFullName() end end end)
	writeOut("economy_" .. tostring(game.PlaceId) .. ".txt", L)
end

-- ===== 9. Character / Rig =====
local function rigDump()
	local target = nearestEnemy()
	local L = { "=== Character / Rig ===", "PlaceId: " .. tostring(game.PlaceId), "Target: " .. (target and target.Name or "none") }
	local char = target and target.Character
	if char then
		local hum = char:FindFirstChildWhichIsA("Humanoid")
		pcall(function() if hum then L[#L + 1] = "RigType: " .. tostring(hum.RigType) end end)
		L[#L + 1] = ""; L[#L + 1] = "-- parts (potential hitbox bones) --"
		pcall(function() for _, d in ipairs(char:GetDescendants()) do if d:IsA("BasePart") then L[#L + 1] = "  " .. d.Name .. "  size=" .. tostring(d.Size) end end end)
		L[#L + 1] = ""; L[#L + 1] = "-- joints --"
		pcall(function() for _, d in ipairs(char:GetDescendants()) do if d:IsA("Motor6D") then L[#L + 1] = "  Motor6D " .. d.Name .. " (" .. (d.Part0 and d.Part0.Name or "?") .. "->" .. (d.Part1 and d.Part1.Name or "?") .. ")" end end end)
		L[#L + 1] = ""; L[#L + 1] = "-- accessories --"
		pcall(function() for _, d in ipairs(char:GetChildren()) do if d:IsA("Accessory") then L[#L + 1] = "  " .. d.Name end end end)
	else L[#L + 1] = "(no enemy character in range)" end
	writeOut("rig_" .. tostring(game.PlaceId) .. ".txt", L)
end

-- ===== 10. Anti-Cheat =====
local function antiCheat()
	local L = { "=== Anti-Cheat Recon ===", "PlaceId: " .. tostring(game.PlaceId), "" }
	local b = getgenv().CryptsHBE
	local ds = b and b.DeepScan
	if ds then
		L[#L + 1] = "Phantom Recon (Calibrate Tier 4):"
		pcall(function() L[#L + 1] = "  AC active: " .. tostring(ds.acActive) end)
		pcall(function() L[#L + 1] = "  watched: " .. table.concat(ds.watched or {}, ", ") end)
		pcall(function() L[#L + 1] = "  avoided honeypots: " .. tostring(#(ds.avoid or {})) end)
	else L[#L + 1] = "(run Calibrate -> Phantom Recon first for watched-props/honeypots)" end
	L[#L + 1] = ""; L[#L + 1] = "-- AC-named scripts --"
	pcall(function()
		local n = 0
		for _, d in ipairs(game:GetDescendants()) do
			if (d:IsA("LocalScript") or d:IsA("Script") or d:IsA("ModuleScript")) and n < 80 and has(d.Name, { "anti", "guard", "detect", "cheat", "security", "ban", "monitor", "validate" }) then
				n = n + 1; L[#L + 1] = "  " .. d.ClassName .. " '" .. d.Name .. "' @ " .. d:GetFullName()
			end
		end
	end)
	writeOut("anticheat_" .. tostring(game.PlaceId) .. ".txt", L)
end

return {
	name = "Recon", tab = "Recon", requires = {},
	load = function(ctx)
		local gCombat = ctx:Groupbox("Combat / Weapons", "left")
		local dmLabel = gCombat:AddLabel("Damage model: run it.", true)
		gCombat:AddButton("Damage Model (held)", function() damageModel(dmLabel) end):AddToolTip("Touch vs raycast vs remote -> recommends which combat tool to use (and warns if HBE = invalid).")
		gCombat:AddButton("Animation / Timing", function() animation() end):AddToolTip("Held tool's animation IDs + tracks playing on you (+ lengths) -- to time auto-fire/parry.")
		gCombat:AddButton("Character / Rig (nearest enemy)", function() rigDump() end):AddToolTip("Dump a target's rig: parts/joints/hitbox names -- to set HBE/aimbot bones for custom rigs.")

		local gWorld = ctx:Groupbox("World / Framework", "left")
		gWorld:AddButton("Module API Map", function() moduleApi() end):AddToolTip("Require every ReplicatedStorage module + dump its table shape -- the game's framework API.")
		gWorld:AddButton("Map / World", function() mapWorld() end):AddToolTip("Spawns, teams, objectives, loot/ammo crates, prompts, seats.")
		gWorld:AddButton("Economy / Shop", function() economy() end):AddToolTip("Leaderstats/currency + shop items/prices + purchase remotes.")
		gWorld:AddButton("Input / Binds", function() inputBinds() end):AddToolTip("KeyCodes referenced by LocalScripts -- infer the game's hotkeys.")

		local gAdv = ctx:Groupbox("Advanced / AC", "right")
		gAdv:AddButton("Networking / Ownership", function() networking() end):AddToolTip("isnetworkowner + sim radius -- what you can physics-control.")
		gAdv:AddButton("GC / Closures", function() gcScan() end):AddToolTip("getgc scan for config/stat/ammo/anti tables + functions (global state the tree-walk misses).")
		gAdv:AddButton("Anti-Cheat Recon", function() antiCheat() end):AddToolTip("Summarise Phantom Recon (watched props/honeypots) + list AC-named scripts.")

		local gInfo = ctx:Groupbox("About", "right")
		gInfo:AddLabel(
			"Read-only deep-dive suite. Every button\n" ..
			"writes a session-tagged report to\n" ..
			"workspace/CryptsHBE/ -- send them back.\n\n" ..
			"START HERE on a new game:\n" ..
			"  - Damage Model (which combat works)\n" ..
			"  - Module API Map (the framework)\n" ..
			"  - Map / World (what's around)\n\n" ..
			"For exact remote payloads use the\n" ..
			"Remote Sniffer; for weapon/vehicle\n" ..
			"internals use DeepDive.",
			true)

		pluginCleanup = function() end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
