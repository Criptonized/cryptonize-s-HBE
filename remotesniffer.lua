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
			if e then e.count = e.count + 1
			else
				e = { name = name, method = method, args = argStr, count = 1, order = nextOrder, inst = self }
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
			"so only the new call shows.",
			true)

		pluginCleanup = function() active = false end   -- hook (if installed) becomes inert
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
