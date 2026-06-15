-- CryptsHBE plugin: Economy  (currency detection + point-farm)
-- ============================================================================
-- "It's all just changing values" applied to points/currency, but currency is usually
-- server-granted -- so this works the WAY POINTS ARE EARNED instead of writing the total:
--   1. Detect currency values (cash/points/score/kills/time-alive/... on you + leaderstats).
--   2. WATCH one: it logs every increase and says whether it was AUTOMATIC (server granted it
--      on a kill / time alive -- you didn't fire anything) or came from YOUR fire -- so you
--      can see how the game generates points.
--   3. Detect the REMOTE(s) that grant points (award/grant/reward/score/kill/earn/...), pick
--      one + its args, and FIRE it (once or auto-farm a rate) to duplicate the earn request.
--   4. Read-back the watched currency proves whether firing actually pays out (client-
--      grantable) or does nothing (server-authoritative -- can't farm that way).
-- Tip: use the Remote Sniffer during a real kill/point gain to get the EXACT remote + args,
-- then plug them in here. Best-effort; the verdict tells you which case you're in.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

local CURRENCY = { "cash", "money", "coin", "credit", "point", "gold", "gem", "token", "score",
	"kills", "kill", "xp", "exp", "level", "rank", "wipe", "soldier", "frag", "bounty", "funds", "wealth" }
local GRANT = { "award", "grant", "point", "reward", "score", "kill", "earn", "give", "add", "coin",
	"cash", "money", "gain", "bounty", "bonus", "claim", "redeem", "credit", "payout", "xp", "frag", "wipe" }
local function isNum(d) return d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue") end
local function nameHas(n, words) n = tostring(n):lower() for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end return false end
local function numFromText(t) local s = tostring(t):gsub(",", ""); return tonumber(s:match("%-?%d+%.?%d*")) end
local function parseArgs(s)
	local t = {}
	for part in tostring(s):gmatch("[^,]+") do
		part = part:gsub("^%s+", ""):gsub("%s+$", "")
		if part ~= "" then
			if part == "true" then t[#t + 1] = true
			elseif part == "false" then t[#t + 1] = false
			elseif tonumber(part) then t[#t + 1] = tonumber(part)
			else t[#t + 1] = part end
		end
	end
	return t
end

return {
	name = "Economy", tab = "Economy", requires = {},
	load = function(ctx)
		local function C(k) ctx:Control(k) end
		local curMap, remMap = {}, {}
		local watched, prevVal, earned, lastFire, autoCount, pendingCheck = nil, nil, 0, 0, 0, nil

		local gCur = ctx:Groupbox("Currency", "left")
		gCur:AddDropdown("ecoCurrency", { Text = "Currency value", Values = {}, Multi = false, AllowNull = true, Tooltip = "Scan, then pick the value to watch/farm (cash/points/score/kills...)." }); C("ecoCurrency")
		gCur:AddButton("Scan Currency", function()
			curMap = {}; local entries = {}
			local function addEntry(key, fld)
				local k2, i = key, 2; while curMap[k2] do k2 = key .. " #" .. i; i = i + 1 end
				curMap[k2] = fld; entries[#entries + 1] = k2
			end
			pcall(function()
				for _, d in ipairs(lPlayer:GetDescendants()) do
					if isNum(d) and nameHas(d.Name, CURRENCY) then
						addEntry(d.Name .. " = " .. tostring(d.Value), { read = function() return d.Value end, path = d:GetFullName() })
					end
				end
			end)
			-- Points are often a HUD TextLabel, NOT a leaderstat (Pordier's 122/585), so also
			-- scan PlayerGui for currency-named text and watch the displayed number directly.
			pcall(function()
				local pg = lPlayer:FindFirstChildOfClass("PlayerGui")
				if pg then
					for _, d in ipairs(pg:GetDescendants()) do
						if (d:IsA("TextLabel") or d:IsA("TextButton")) and numFromText(d.Text) and nameHas(d.Name, CURRENCY) then
							addEntry("[HUD] " .. d.Name .. " = " .. tostring(numFromText(d.Text)), { read = function() return numFromText(d.Text) end, path = d:GetFullName() })
						end
					end
				end
			end)
			Options.ecoCurrency.Values = entries; pcall(function() Options.ecoCurrency:SetValues() end)
			Library:Notify("Currency: " .. #entries .. " value(s) found")
		end):AddToolTip("Find currency/score/kill values on you + leaderstats.")
		local lblWatch = gCur:AddLabel("Watch: pick a currency.", true)
		Options.ecoCurrency:OnChanged(function()
			watched = curMap[Options.ecoCurrency.Value]
			prevVal = watched and watched.read() or nil
			earned, autoCount = 0, 0
		end)

		local gGen = ctx:Groupbox("Point Generators (remotes)", "left")
		gGen:AddDropdown("ecoRemote", { Text = "Grant remote", Values = {}, Multi = false, AllowNull = true, Tooltip = "Scan, then pick the remote that grants points (award/reward/kill/score...)." }); C("ecoRemote")
		gGen:AddButton("Scan Grant Remotes", function()
			remMap = {}; local entries, n = {}, 0
			pcall(function()
				for _, d in ipairs(game:GetDescendants()) do
					if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and nameHas(d.Name, GRANT) and n < 250 then
						n = n + 1
						local key = d.ClassName .. " " .. d.Name
						local k2, i = key, 2; while remMap[k2] do k2 = key .. " #" .. i; i = i + 1 end
						remMap[k2] = d; entries[#entries + 1] = k2
					end
				end
			end)
			table.sort(entries)
			Options.ecoRemote.Values = entries; pcall(function() Options.ecoRemote:SetValues() end)
			Library:Notify("Grant remotes: " .. #entries .. " found")
		end):AddToolTip("Find RemoteEvents/Functions named like award/grant/reward/kill/score/earn.")
		gGen:AddInput("ecoArgs", { Text = "Args (comma)", Default = "", Tooltip = "Optional args to send, comma-separated (numbers/true/false/strings). Empty = no args.\nSniff a real point gain with the Remote Sniffer to get the exact args." }); C("ecoArgs")

		local gFarm = ctx:Groupbox("Farm", "right")
		local lblFarm = gFarm:AddLabel("Fire result: -", true)
		local function fireRemote()
			local r = remMap[Options.ecoRemote.Value]
			if not r then Library:Notify("Pick a grant remote (Scan first)"); return end
			local args = parseArgs(Options.ecoArgs.Value or "")
			lastFire = tick()
			if watched then pendingCheck = { before = watched.read(), at = tick() + 0.4 } end
			pcall(function()
				if r:IsA("RemoteEvent") then r:FireServer(table.unpack(args))
				elseif r:IsA("RemoteFunction") then r:InvokeServer(table.unpack(args)) end
			end)
		end
		gFarm:AddButton("Fire Once", fireRemote):AddToolTip("Fire the chosen grant remote once; watch the currency read-back to see if it paid out.")
		gFarm:AddToggle("ecoAutoFarm", { Text = "Auto-Farm", Default = false, Tooltip = "Fire the grant remote repeatedly at the rate below. (Default: OFF)" }); C("ecoAutoFarm")
		gFarm:AddSlider("ecoRate", { Text = "Fires / sec", Min = 1, Max = 30, Default = 5, Rounding = 0 }); C("ecoRate")

		-- ===== Rank remotes by points-per-fire =====
		-- "Which remote makes the most points": fire EACH scanned grant remote once, measure the
		-- watched currency's delta, rank them, auto-select the winner. Honest about noise:
		-- automatic server grants (kills/time) during the test can inflate a result, and all +0
		-- means none are client-grantable (server-authoritative) or the args are wrong.
		local gRank = ctx:Groupbox("Rank Remotes", "right")
		local lblRank = gRank:AddLabel("Rank: pick a currency + Scan remotes,\nthen test which one pays the most.", true)
		local ranking, rankBusy = {}, false
		local function rankRemotes()
			if rankBusy then return end
			if not watched then Library:Notify("Pick a currency to watch first"); return end
			local keys = {}
			for k in pairs(remMap) do keys[#keys + 1] = k end
			if #keys == 0 then Library:Notify("Scan Grant Remotes first"); return end
			table.sort(keys)
			rankBusy = true
			local args = parseArgs(Options.ecoArgs.Value or "")
			task.spawn(function()
				local results = {}
				for idx, k in ipairs(keys) do
					local r = remMap[k]
					local before = watched.read()
					pcall(function() lblRank:SetText(("Ranking %d/%d:\n%s"):format(idx, #keys, k)) end)
					pcall(function()
						if r:IsA("RemoteEvent") then r:FireServer(table.unpack(args))
						elseif r:IsA("RemoteFunction") then r:InvokeServer(table.unpack(args)) end
					end)
					task.wait(0.35)
					local after = watched.read()
					local gain = (type(after) == "number" and type(before) == "number") and (after - before) or 0
					results[#results + 1] = { key = k, gain = gain }
				end
				table.sort(results, function(a, b) return a.gain > b.gain end)
				ranking = results
				local lines = {}
				for i = 1, math.min(5, #results) do lines[#lines + 1] = ("%d) +%s  %s"):format(i, tostring(results[i].gain), results[i].key) end
				local best = results[1]
				if best and best.gain > 0 then
					pcall(function() Options.ecoRemote:SetValue(best.key) end)
					pcall(function() lblRank:SetText("Best -> selected:\n" .. table.concat(lines, "\n")) end)
					Library:Notify("Best grant remote: " .. best.key .. " (+" .. best.gain .. ")")
				else
					pcall(function() lblRank:SetText("No remote paid out (all +0).\nLikely server-side, or wrong args --\nsniff a real gain for the exact args.") end)
					Library:Notify("No remote paid out -- server-side or wrong args")
				end
				rankBusy = false
			end)
		end
		gRank:AddButton("Rank by Points (fires each)", rankRemotes):AddToolTip("Fires EACH scanned grant remote once and measures how much the watched currency changed, then ranks them + auto-selects the best. It really does fire every candidate -- use sniffed args. Server grants during the test add noise.")
		gRank:AddButton("Farm Best", function()
			local best = ranking[1]
			if best and best.gain > 0 then
				pcall(function() Options.ecoRemote:SetValue(best.key) end)
				if Toggles.ecoAutoFarm then pcall(function() Toggles.ecoAutoFarm:SetValue(true) end) end
				Library:Notify("Auto-Farming best: " .. best.key)
			else
				Library:Notify("Rank first (no paying remote found)")
			end
		end):AddToolTip("Select the top-ranked remote and turn on Auto-Farm.")

		local gWatch = ctx:Groupbox("Detection / Read-back", "right")
		local lblGen = gWatch:AddLabel("Generation: watching...", true)

		local lastFarm = 0
		ctx:Connect(RunService.Heartbeat, function()
			local now = tick()
			-- auto-farm
			if Toggles.ecoAutoFarm and Toggles.ecoAutoFarm.Value then
				if now - lastFarm >= 1 / math.max(1, Options.ecoRate.Value) then lastFarm = now; pcall(fireRemote) end
			end
			-- watch currency for increases (and classify auto vs your-fire)
			if watched then
				local v = watched.read()
				if type(v) == "number" then
					if prevVal and v > prevVal then
						local d = v - prevVal
						earned = earned + d
						local viaFire = (now - lastFire) < 1.0
						pcall(function() lblGen:SetText(("Generation: %s  +%d (%s)\nTotal gained: +%d"):format(
							watched.path:match("[^.]+$") or "?", d, viaFire and "via YOUR fire" or "AUTOMATIC (server: kill/time)", earned)) end)
					end
					prevVal = v
					pcall(function() lblWatch:SetText("Watch: " .. (watched.path:match("[^.]+$") or "?") .. " = " .. tostring(v)) end)
				end
			end
			-- Fire Once read-back verdict
			if pendingCheck and now >= pendingCheck.at then
				local after = watched and watched.read()
				if type(after) == "number" then
					local d = after - pendingCheck.before
					pcall(function() lblFarm:SetText(d > 0 and ("Fire result: +" .. d .. " (WORKS -- client-grantable)") or "Fire result: no change (server-authoritative or wrong remote/args)") end)
				end
				pendingCheck = nil
			end
		end)

		local howG = ctx:Groupbox("How to Use", "right")
		howG:AddLabel(
			"FIND THE PAYOUT:\n" ..
			"1. Scan Currency, pick your points value.\n" ..
			"2. Play normally (get a kill / survive) and\n" ..
			"   watch 'Generation' -- it shows +N and\n" ..
			"   says AUTOMATIC (server) when it pays out\n" ..
			"   on its own.\n\n" ..
			"FARM IT:\n" ..
            "3. Scan Grant Remotes, pick the one that\n" ..
			"   matches (sniff a real gain for the exact\n" ..
			"   remote + args -> put args in the box).\n" ..
			"4. Fire Once -> read-back says WORKS or\n" ..
			"   'no change'. If it works, Auto-Farm.\n\n" ..
			"No-change usually = the server grants points\n" ..
			"itself and ignores your fire (can't farm).",
			true)

		pluginCleanup = function() end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
