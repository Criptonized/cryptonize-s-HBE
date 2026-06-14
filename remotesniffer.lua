-- CryptsHBE plugin: Remote Sniffer  (opt-in, DETECTABLE)
-- ============================================================================
-- Logs the game's OUTGOING remote calls (RemoteEvent:FireServer / RemoteFunction:
-- InvokeServer) WITH their arguments, so you can see the exact payload the game sends --
-- the missing piece for replicating a legit action:
--   * Bleeding Blades "Invalid Attack": shows the real damage/hit remote + its args, so a
--     replay matches what the server expects (instead of HBE, which the server rejects).
--   * Artillery: reveals the Shoot remote's arguments.
--   * Shops/economy: reveals the purchase remote (e.g. the points buy).
--
-- HOW: it installs a scoped __namecall hook that only inspects FireServer/InvokeServer and
-- always passes the real call through unchanged (read-only -- it never blocks or alters a
-- call). checkcaller() skips the script's OWN remote calls.
--
-- *** THIS USES A HOOK -> it is DETECTABLE. *** It is OFF by default and the only thing it
-- does is observe. Hooks live only in explicit opt-in modules (rule #3); this is one, like
-- SilentAim's Extreme mode. Turn it off (or PANIC) and the hook goes inert (pass-through).
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

local COMBAT_WORDS = { "hit", "damage", "dmg", "swing", "attack", "block", "parry", "shoot",
	"fire", "bow", "draw", "melee", "stab", "slash", "hurt", "combat", "weapon", "strike",
	"wound", "kill", "buy", "purchase", "shop", "spend", "cash", "ammo", "reload" }
local function hasWord(n, words) n = tostring(n):lower() for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end return false end

-- serialize an argument for display (shallow, type-aware)
local function ser(v, depth)
	local t = typeof(v)
	if t == "Instance" then return v.ClassName .. ":" .. v.Name
	elseif t == "Vector3" then return ("V3(%.0f,%.0f,%.0f)"):format(v.X, v.Y, v.Z)
	elseif t == "CFrame" then local p = v.Position return ("CF(%.0f,%.0f,%.0f)"):format(p.X, p.Y, p.Z)
	elseif t == "Color3" then return "Color3"
	elseif t == "table" then
		if (depth or 0) >= 1 then return "{...}" end
		local parts, n = {}, 0
		for k, val in pairs(v) do n = n + 1; if n > 8 then parts[#parts + 1] = "..."; break end; parts[#parts + 1] = tostring(k) .. "=" .. ser(val, (depth or 0) + 1) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then return '"' .. (#v > 48 and (v:sub(1, 48) .. "..") or v) .. '"'
	else return tostring(v) end
end
local function serArgs(args, n)
	local parts = {}
	for i = 1, n do parts[#parts + 1] = ser(args[i], 0) end
	return table.concat(parts, ", ")
end

return {
	name = "RemoteSniffer", tab = "Sniffer", requires = {},
	load = function(ctx)
		local function C(k) ctx:Control(k) end

		-- shared log state (closure-captured by the hook)
		local active = false
		local log = {}          -- signature -> { name, method, args, count, order }
		local order = {}        -- signatures in first-seen order
		local nextOrder = 1

		local function record(self, method, args, argc)
			local ok, name = pcall(function() return self.Name end)
			name = ok and name or "?"
			if Toggles.sniffCombatOnly and Toggles.sniffCombatOnly.Value and not hasWord(name, COMBAT_WORDS) then return end
			local filt = Options.sniffFilter and Options.sniffFilter.Value or ""
			if filt ~= "" and not name:lower():find(filt:lower(), 1, true) then return end
			local argStr = serArgs(args, argc)
			local sig = name .. "|" .. method .. "|" .. argStr
			local e = log[sig]
			if e then e.count = e.count + 1; e.rawArgs = args; e.argc = argc   -- refresh latest raw args for replay
			else
				e = { name = name, method = method, args = argStr, count = 1, order = nextOrder, inst = self, rawArgs = args, argc = argc }
				nextOrder = nextOrder + 1
				log[sig] = e; order[#order + 1] = sig
				if #order > 300 then local old = table.remove(order, 1); log[old] = nil end
			end
		end

		-- install the hook ONCE (the first time the user enables); gate by `active` so
		-- toggling off / unload makes it a transparent pass-through (no real un-hook needed).
		local installed = false
		local function ensureHook()
			if installed then return true end
			if not (hookmetamethod and getnamecallmethod and checkcaller) then
				Library:Notify("Executor lacks hookmetamethod/getnamecallmethod"); return false
			end
			local ok, err = pcall(function()
				local old
				old = hookmetamethod(game, "__namecall", function(self, ...)
					if active and not checkcaller() then
						local m = getnamecallmethod()
						if m == "FireServer" or m == "InvokeServer" then
							local args = { ... }
							pcall(record, self, m, args, select("#", ...))
						end
					end
					return old(self, ...)
				end)
			end)
			if not ok then Library:Notify("Hook failed: " .. tostring(err)); return false end
			installed = true
			return true
		end

		local g = ctx:Groupbox("Remote Sniffer", "left")
		g:AddToggle("sniffActive", { Text = "Sniffer Active (DETECTABLE)", Default = false, Tooltip = "Installs a __namecall hook that LOGS outgoing FireServer/InvokeServer calls + args.\nRead-only (never alters calls) but a hook IS detectable. OFF by default. (Default: OFF)" }); C("sniffActive")
		Toggles.sniffActive:OnChanged(function()
			if Toggles.sniffActive.Value then
				if not ensureHook() then pcall(function() Toggles.sniffActive:SetValue(false) end); return end
				active = true; Library:Notify("Remote Sniffer ON (detectable)")
			else
				active = false; Library:Notify("Remote Sniffer off (hook inert)")
			end
		end)
		g:AddToggle("sniffCombatOnly", { Text = "Combat/economy only", Default = true, Tooltip = "Only log remotes whose name matches hit/damage/shoot/buy/... -- cuts noise. (Default: ON)" }); C("sniffCombatOnly")
		g:AddInput("sniffFilter", { Text = "Name contains", Default = "", Tooltip = "Extra filter: only log remotes whose name contains this. Empty = all (subject to Combat-only)." }); C("sniffFilter")
		g:AddButton("Clear Log", function() log = {}; order = {}; nextOrder = 1; Library:Notify("Sniffer log cleared") end)
		g:AddButton("Save Log to file", function()
			local lines = { "=== Remote Sniffer Log ===", "PlaceId: " .. tostring(game.PlaceId), "" }
			-- sort by count desc so the busiest remotes are on top
			local sigs = {}
			for s in pairs(log) do sigs[#sigs + 1] = s end
			table.sort(sigs, function(a, b) return log[a].count > log[b].count end)
			for _, s in ipairs(sigs) do
				local e = log[s]
				local path = e.name
				pcall(function() if e.inst then path = e.inst:GetFullName() end end)
				lines[#lines + 1] = ("[x%d] %s:%s  @ %s\n      args: %s"):format(e.count, e.name, e.method, path, e.args)
			end
			lines[#lines + 1] = ""
			lines[#lines + 1] = "Total signatures: " .. #sigs
			local fname = "remotesniff_" .. tostring(game.PlaceId) .. ".txt"
			local b = getgenv().CryptsHBE
			if b and b.SessionName then pcall(function() fname = b:SessionName(fname) end) end
			pcall(function()
				if makefolder and not (isfolder and isfolder("CryptsHBE")) then makefolder("CryptsHBE") end
				if writefile then writefile("CryptsHBE/" .. fname, table.concat(lines, "\n")) end
			end)
			Library:Notify("Saved -> workspace/CryptsHBE/" .. fname)
		end):AddToolTip("Write every captured remote + its args (busiest first) to a file to send back.")

		local gView = ctx:Groupbox("Live (last calls)", "right")
		local lblLive = gView:AddLabel("Sniffer off.", true)
		local lastUI = 0
		ctx:Connect(RunService.Heartbeat, function()
			local now = tick(); if now - lastUI < 0.33 then return end; lastUI = now
			if not active then pcall(function() lblLive:SetText("Sniffer off. Turn on 'Sniffer Active' then do the action in-game.") end); return end
			-- show the most recent 8 signatures (by order), newest first
			local recent = {}
			for i = #order, math.max(1, #order - 7), -1 do
				local e = log[order[i]]; if e then
					recent[#recent + 1] = ("%s:%s x%d%s"):format(e.name, e.method, e.count,
						(Toggles.sniffShowArgs and Toggles.sniffShowArgs.Value) and ("\n   " .. e.args) or "")
				end
			end
			pcall(function() lblLive:SetText((#order .. " unique remotes seen:\n") .. (table.concat(recent, "\n"))) end)
		end)
		gView:AddToggle("sniffShowArgs", { Text = "Show args in live view", Default = true, Tooltip = "Include argument values under each remote in the live readout. (Default: ON)" }); C("sniffShowArgs")

		-- ===== Replay (Sniffer -> Fire): re-send a captured call =====
		-- The lever for server-side stuff: capture the real call (a kill/award remote, the
		-- gun's Shoot, a legit hit) then replay its EXACT payload -- once, on a loop (farm /
		-- bolt-bypass), or retargeted to the nearest enemy (silent hit).
		local gRep = ctx:Groupbox("Replay (Sniffer -> Fire)", "left")
		local replayMap = {}
		gRep:AddDropdown("sniffReplaySel", { Text = "Captured call", Values = {}, Multi = false, AllowNull = true, Tooltip = "Pick a captured call to replay. Hit Refresh after capturing." }); C("sniffReplaySel")
		gRep:AddButton("Refresh List", function()
			replayMap = {}; local entries = {}
			for _, sig in ipairs(order) do
				local e = log[sig]
				if e and e.rawArgs then
					local key = ("%s:%s (%s)"):format(e.name, e.method, e.args)
					if #key > 70 then key = key:sub(1, 70) .. "..." end
					local k2, i = key, 2; while replayMap[k2] do k2 = key .. " #" .. i; i = i + 1 end
					replayMap[k2] = e; entries[#entries + 1] = k2
				end
			end
			Options.sniffReplaySel.Values = entries; pcall(function() Options.sniffReplaySel:SetValues() end)
			Library:Notify("Replay: " .. #entries .. " captured call(s)")
		end):AddToolTip("Populate the dropdown from the captured log.")
		gRep:AddToggle("sniffRetarget", { Text = "Retarget to nearest enemy", Default = false, Tooltip = "Swap Player args -> nearest enemy and Vector3 args -> their position (for damage/hit remotes). (Default: OFF)" }); C("sniffRetarget")
		local lblRep = gRep:AddLabel("Replay: pick a captured call", true)

		local function nearestEnemy()
			local c = lPlayer.Character; local lr = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
			if not lr then return nil end
			local best, bpos, bd
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= lPlayer then
					local ally = false
					pcall(function() if lPlayer.Team or p.Team then ally = (lPlayer.Team == p.Team) end end)
					local pc = p.Character; local pr = pc and (pc:FindFirstChild("HumanoidRootPart") or pc:FindFirstChild("Head"))
					if pr and not ally then local d = (pr.Position - lr.Position).Magnitude; if not bd or d < bd then best, bpos, bd = p, pr.Position, d end end
				end
			end
			return best, bpos
		end
		local function buildArgs(e)
			local args = {}
			for i = 1, (e.argc or 0) do args[i] = e.rawArgs[i] end
			if Toggles.sniffRetarget and Toggles.sniffRetarget.Value then
				local tgt, tpos = nearestEnemy()
				for i = 1, (e.argc or 0) do
					local a = args[i]
					if typeof(a) == "Instance" and a:IsA("Player") and tgt then args[i] = tgt
					elseif typeof(a) == "Vector3" and tpos then args[i] = tpos end
				end
			end
			return args, (e.argc or 0)
		end
		local function replaySelected()
			local e = replayMap[Options.sniffReplaySel.Value]
			if not e then Library:Notify("Pick a captured call (Refresh first)"); return false end
			if not (e.inst and e.inst.Parent) then Library:Notify("That remote is gone"); return false end
			local args, n = buildArgs(e)
			pcall(function()
				if e.inst:IsA("RemoteEvent") then e.inst:FireServer(table.unpack(args, 1, n))
				elseif e.inst:IsA("RemoteFunction") then e.inst:InvokeServer(table.unpack(args, 1, n)) end
			end)
			return true
		end
		gRep:AddButton("Replay Once", function() if replaySelected() then pcall(function() lblRep:SetText("Replayed once.") end) end end):AddToolTip("Re-send the captured call's exact payload one time.")
		gRep:AddToggle("sniffAutoReplay", { Text = "Auto-Replay", Default = false, Tooltip = "Re-send the captured call repeatedly at the rate below (farm / bolt-bypass). (Default: OFF)" }); C("sniffAutoReplay")
		gRep:AddSlider("sniffReplayRate", { Text = "Replays / sec", Min = 1, Max = 30, Default = 5, Rounding = 0 }); C("sniffReplayRate")
		local lastReplay = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.sniffAutoReplay and Toggles.sniffAutoReplay.Value) then return end
			local now = tick(); if now - lastReplay < 1 / math.max(1, Options.sniffReplayRate.Value) then return end; lastReplay = now
			replaySelected()
		end)

		local howG = ctx:Groupbox("How to Use", "right")
		howG:AddLabel(
			"Find the EXACT remote + args the game sends.\n\n" ..
			"1. Turn on 'Sniffer Active' (it's a hook --\n" ..
			"   detectable; only observes).\n" ..
			"2. Do the action in-game ONCE (swing /\n" ..
			"   shoot the artillery / buy the item).\n" ..
			"3. The busiest new remote in the live list\n" ..
			"   is it -- read its args.\n" ..
			"4. 'Save Log to file' and send it back, or\n" ..
			"   plug the remote + args into Remote Replay\n" ..
			"   to reproduce it.\n\n" ..
			"Tip: 'Combat/economy only' + Name-contains\n" ..
			"cut the noise. 'Clear Log' before the action\n" ..
			"so only the new call shows.\n\n" ..
			"REPLAY (Sniffer -> Fire):\n" ..
			"5. Refresh List, pick the captured call.\n" ..
			"6. Replay Once (test) -> Auto-Replay to farm\n" ..
			"   (points via a kill/award remote, or a\n" ..
			"   bolt gun's Shoot for full-auto).\n" ..
			"7. 'Retarget to nearest enemy' swaps the\n" ..
			"   Player/position args -> a silent hit.\n" ..
			"If the server validates it, replay won't\n" ..
			"land -- that's a server limit, not a bug.",
			true)

		pluginCleanup = function() active = false end   -- hook (if installed) becomes inert
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
