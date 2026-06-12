-- CryptsHBE plugin: Remote Replay (manual RemoteEvent replay at the nearest target)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE
local pluginCleanup = nil
return {
	name = "Remote", tab = "Remote", requires = {},
	load = function(ctx)
		local miscTab = ctx.tab
	local rr = miscTab:AddRightGroupbox("Remote Replay (experimental)")
	rr:AddLabel("RemoteEvent-damage games only. Refresh, pick the\ndamage remote + an arg, then fire it at the nearest target.", true)
	local remotes = {}
	rr:AddDropdown("rrRemote", { Text = "Remote", Values = {}, Multi = false, AllowNull = true, Tooltip = "Discovered RemoteEvents (Refresh to populate)." })
	rr:AddDropdown("rrArg", { Text = "Argument", Values = { "Target Character", "Target Player", "Target HumanoidRootPart", "Target Position", "None" }, Default = "Target Character", Multi = false, AllowNull = false, Tooltip = "What to pass to FireServer. Match the game's damage remote signature." })
	rr:AddSlider("rrRange", { Text = "Range (studs)", Min = 5, Max = 120, Default = 25, Rounding = 0 })
	rr:AddToggle("rrIgnoreTeam", { Text = "Ignore Team", Default = true })

	local function refreshRemotes()
		remotes = {}
		local names, count = {}, 0
		pcall(function()
			for _, d in ipairs(game:GetDescendants()) do
				if d:IsA("RemoteEvent") then
					count = count + 1; if count > 4000 then break end
					local key, i = d.Name, 2
					while remotes[key] do key = d.Name .. " #" .. i; i = i + 1 end
					remotes[key] = d; names[#names + 1] = key
				end
			end
		end)
		table.sort(names)
		Options.rrRemote.Values = names; pcall(function() Options.rrRemote:SetValues() end)
		Library:Notify("Found " .. #names .. " RemoteEvents")
	end
	rr:AddButton("Refresh Remotes", refreshRemotes):AddToolTip("Scan the game for RemoteEvents.")

	local function nearestTarget()
		local lc = lPlayer.Character
		local lroot = lc and (lc:FindFirstChild("HumanoidRootPart") or lc:FindFirstChild("Head"))
		if not lroot then return nil end
		local best, bd = nil, Options.rrRange.Value
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lPlayer then
				local teammate = Toggles.rrIgnoreTeam.Value and plr.Team and lPlayer.Team and plr.Team == lPlayer.Team
				local c = plr.Character
				local node = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
				local hum = c and c:FindFirstChildWhichIsA("Humanoid")
				if not teammate and node and hum and hum.Health > 0 then
					local dd = (node.Position - lroot.Position).Magnitude
					if dd < bd then bd, best = dd, plr end
				end
			end
		end
		return best
	end
	local function fireAt(plr)
		local remote = remotes[Options.rrRemote.Value or ""]
		if not remote then Library:Notify("Pick a remote first"); return end
		-- Phantom Recon: never fire a mapped honeypot/AC remote.
		if Bridge.isHoneypot and Bridge.isHoneypot(remote) then Library:Notify("That remote is a honeypot - skipped"); return end
		local c, mode = plr.Character, Options.rrArg.Value
		local arg
		if mode == "Target Player" then arg = plr
		elseif mode == "Target Character" then arg = c
		elseif mode == "Target HumanoidRootPart" then arg = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
		elseif mode == "Target Position" then local n = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")); arg = n and n.Position end
		pcall(function() if mode == "None" then remote:FireServer() else remote:FireServer(arg) end end)
	end
	rr:AddButton("Fire at Nearest", function()
		local t = nearestTarget()
		if t then fireAt(t) else Library:Notify("No target in range") end
	end):AddToolTip("Fire the selected remote once at the nearest valid target.")
	rr:AddToggle("rrAuto", { Text = "Auto-Fire (aura)", Default = false, Tooltip = "Repeatedly fire the remote at the nearest target. (Default: OFF)" })
	rr:AddSlider("rrRate", { Text = "Auto Rate (/s)", Min = 1, Max = 20, Default = 5, Rounding = 0 })
	local rrLast = 0
	local rrConn = RunService.Heartbeat:Connect(function()
		if not (Toggles.rrAuto and Toggles.rrAuto.Value) then return end
		local now = tick(); if now - rrLast < (1 / math.max(1, Options.rrRate.Value)) then return end
		rrLast = now
		local t = nearestTarget(); if t then fireAt(t) end
	end)
		for _, k in ipairs({ "rrRemote","rrArg","rrRange","rrIgnoreTeam","rrAuto","rrRate" }) do ctx:Control(k) end

		-- Bottom-of-tab tutorial.
		local howG = miscTab:AddLeftGroupbox("How to Use")
		howG:AddLabel(
			"For games where SHOOTING = firing a\n" ..
			"RemoteEvent (not touch). You fire the\n" ..
			"game's damage remote at the nearest\n" ..
			"enemy -- no aiming, no hooks.\n\n" ..
			"  1. Refresh Remotes.\n" ..
			"  2. Pick the one that deals damage.\n" ..
			"     Hints: names like FireBullet / Hit\n" ..
			"     / Damage; or use Calibrate ->\n" ..
			"     Deep-Dump to see the gun's remotes.\n" ..
			"  3. Set Argument to what it expects\n" ..
			"     (Character / Player / HRP / Position).\n" ..
			"  4. Fire at Nearest, or Auto-Fire\n" ..
			"     (aura). Set Range + Rate.\n\n" ..
			"Nothing happens? Wrong remote or\n" ..
			"Argument -- try another. Honeypot\n" ..
			"remotes are skipped automatically.",
			true)
		pluginCleanup = function() if rrConn then pcall(function() rrConn:Disconnect() end) end end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}