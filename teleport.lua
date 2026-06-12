-- FurryHBE plugin: Teleport (waypoints, teleport-to-player, seat teleport, anti-rubberband)
local Players = game:GetService("Players")
local Workspace = workspace
local Bridge = getgenv().FurryHBE
local pluginCleanup = nil
return {
	name = "Teleport", tab = "Teleport", requires = {},
	load = function(ctx)
	local HttpService = game:GetService("HttpService")
	local lPlayer  = Players.LocalPlayer
	-- Keep waypoints with the rest of the script's files in workspace/FurryHBE/.
	local OUT_DIR  = "FurryHBE"
	pcall(function() if makefolder and not (isfolder and isfolder(OUT_DIR)) then makefolder(OUT_DIR) end end)
	local WP_FILE  = OUT_DIR .. "/Waypoints.json"

	local teleportTab   = ctx.tab
	local waypointGroup = teleportTab:AddLeftGroupbox("Waypoints")
	local teleportGroup = teleportTab:AddLeftGroupbox("Teleport")
	local settingsGroup = teleportTab:AddRightGroupbox("Settings")

	local waypoints = {}

	waypointGroup:AddDropdown("waypointList", { Text = "Saved Waypoints", AllowNull = true, Multi = false, Values = {}, Default = nil, Tooltip = "Select a waypoint to teleport to. (Default: none)" })

	settingsGroup:AddToggle("useSitTeleport", { Text = "Sit Before Teleport", Default = true, Tooltip = "Sit on a temporary seat first to mask the teleport as a normal move. (Default: ON)" })
	settingsGroup:AddToggle("tpPreload", { Text = "Preload Destination", Default = true, Tooltip = "Before teleporting, ask the engine to stream in the area around\nyour destination (StreamingEnabled games) so you don't drop into\na 'Gameplay Paused' while it loads in around you. (Default: ON)" })
	settingsGroup:AddToggle("desyncFlash", { Text = "Desync Flash", Default = false, Tooltip = "Briefly flicker position to mask the teleport as\nnetwork lag (can fling in some games). (Default: OFF)" })
	settingsGroup:AddSlider("teleportSitTime", { Text = "Sit Settle Time", Min = 0.05, Max = 1, Default = 0.3, Rounding = 2, Tooltip = "How long to stay seated around the teleport. (Default: 0.3)" })

	local activeTempSeats = {}

	local function teleportTo(targetPosition)
		local char = lPlayer.Character
		if not char then return end
		local humanoid = char:FindFirstChildWhichIsA("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
		if not humanoid or not root then return end
		local settle = (Options.teleportSitTime and Options.teleportSitTime.Value) or 0.3
		local dest = CFrame.new(targetPosition)
		-- Pre-stream the destination so StreamingEnabled games don't drop into a
		-- "Gameplay Paused" while the area loads in around you after the hop.
		if (Toggles.tpPreload == nil) or Toggles.tpPreload.Value then
			pcall(function() lPlayer:RequestStreamAroundAsync(targetPosition, 2) end)
		end
		if Toggles.useSitTeleport.Value then
			-- OVERHAUL: Use a REAL Seat instance so the server registers the sit.
			-- The character is anchored to the seat, so moving the seat moves the
			-- player without the server's character controller fighting it.
			-- 1) Create an actual Seat at your current position
			local seat = Instance.new("Seat")
			seat.Name = "FurryHBE_TempSeat"
			seat.Size = Vector3.new(2, 1, 2)
			seat.Anchored = true
			seat.CanCollide = false
			seat.Transparency = 1
			seat.CFrame = root.CFrame + Vector3.new(0, -3, 0)
			seat.Parent = Workspace
			activeTempSeats[seat] = true

			-- 2) Force the humanoid into the seat via Seat:Sit()
			seat:Sit(humanoid)
			task.wait(settle)

			-- 3) Move the SEAT (with the player attached) to the destination.
			-- Since the player is occupying the seat, the server sees the player
			-- as seated and doesn't rubberband them back.
			seat.CFrame = dest + Vector3.new(0, -1, 0)
			task.wait(settle)

			-- 4) Unseat and cleanup — small hop to land cleanly
			humanoid.Sit = false
			humanoid.Jump = true
			task.wait(0.1)
			activeTempSeats[seat] = nil
			pcall(function() seat:Destroy() end)

			-- 5) Final position correction after unseating
			task.wait(0.05)
			if root.Parent then
				root.CFrame = dest
			end
		else
			-- Direct teleport (no seat, may rubberband in some games)
			root.CFrame = dest
		end
		-- Verify arrival: after a moment, if we got snapped back (rubberbanded), say so
		-- so you know the seat trick didn't hold in this game.
		task.spawn(function()
			task.wait(0.4)
			local r = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
			if r then
				local off = (r.Position - targetPosition).Magnitude
				if off > 25 then
					pcall(function() Library:Notify("Teleport: rubberbanded back (" .. math.floor(off) .. " studs off)") end)
				end
			end
		end)
	end

	local function rebuildDropdown(selectName)
		local list = Options.waypointList
		local names = {}
		for _, wp in ipairs(waypoints) do table.insert(names, wp.name) end
		list.Values = names
		list:SetValues()
		if selectName and table.find(names, selectName) then
			list:SetValue(selectName)
		elseif #names == 0 then
			pcall(function() list:SetValue(nil) end)
		end
	end

	local function saveWaypoints()
		if not writefile then return end
		local data = {}
		for _, wp in ipairs(waypoints) do
			table.insert(data, { name = wp.name, x = wp.position.X, y = wp.position.Y, z = wp.position.Z })
		end
		pcall(function() writefile(WP_FILE, HttpService:JSONEncode(data)) end)
	end

	local function loadWaypoints()
		if not (isfile and readfile and isfile(WP_FILE)) then return end
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(WP_FILE)) end)
		if ok and type(data) == "table" then
			waypoints = {}
			for _, wp in ipairs(data) do
				if wp.name and wp.x then
					table.insert(waypoints, { name = wp.name, position = Vector3.new(wp.x, wp.y, wp.z) })
				end
			end
			rebuildDropdown()
		end
	end

	waypointGroup:AddButton("Add Waypoint", function()
		local char = lPlayer.Character
		local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
		if not root then Library:Notify("No character to save"); return end
		local name = "Waypoint " .. (#waypoints + 1)
		table.insert(waypoints, { name = name, position = root.Position })
		rebuildDropdown(name)
		saveWaypoints()
		Library:Notify("Waypoint saved: " .. name)
	end):AddToolTip("Save current position as a waypoint")

	waypointGroup:AddButton("Delete Selected", function()
		local sel = Options.waypointList.Value
		if not sel then return end
		for i, wp in ipairs(waypoints) do
			if wp.name == sel then table.remove(waypoints, i); break end
		end
		rebuildDropdown(waypoints[#waypoints] and waypoints[#waypoints].name or nil)
		saveWaypoints()
		Library:Notify("Waypoint deleted: " .. sel)
	end):AddToolTip("Remove the selected waypoint")

	teleportGroup:AddButton("Teleport to Selected", function()
		local sel = Options.waypointList.Value
		if not sel then Library:Notify("No waypoint selected"); return end
		local targetPos
		for _, wp in ipairs(waypoints) do
			if wp.name == sel then targetPos = wp.position; break end
		end
		if not targetPos then return end
		task.spawn(function()
			local ok, err = pcall(teleportTo, targetPos)
			if not ok then Library:Notify("Teleport failed: " .. tostring(err)) end
		end)
	end):AddToolTip("Teleport to the selected waypoint using the anti-detection method")

	-- ===== Teleport to player =====
	teleportGroup:AddDropdown("tpPlayerList", { Text = "Target Player", Values = {}, Multi = false, AllowNull = true, Tooltip = "Player to teleport to. (Default: none)" })
	local function refreshTpPlayers()
		local names = {}
		for _, p in ipairs(Players:GetPlayers()) do if p ~= lPlayer then table.insert(names, p.Name) end end
		Options.tpPlayerList.Values = names
		Options.tpPlayerList:SetValues()
	end
	local function getTargetPlayer()
		local n = Options.tpPlayerList.Value
		return n and Players:FindFirstChild(n) or nil
	end
	teleportGroup:AddButton("Refresh Players", function()
		refreshTpPlayers(); Library:Notify("Player list refreshed")
	end):AddToolTip("Re-list players for the dropdown")
	teleportGroup:AddButton("Teleport to Player", function()
		local p = getTargetPlayer()
		local char = p and p.Character
		local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
		if not root then Library:Notify("Target has no character"); return end
		task.spawn(function()
			local ok, err = pcall(teleportTo, root.Position + Vector3.new(0, 0, 3))
			if not ok then Library:Notify("Teleport failed: " .. tostring(err)) end
		end)
	end):AddToolTip("Teleport right next to the selected player")
	teleportGroup:AddButton("Teleport to Nearest Seat", function()
		local p = getTargetPlayer()
		local char = p and p.Character
		local troot = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
		if not troot then Library:Notify("Target has no character"); return end
		-- nearest EMPTY seat within 60 studs of the target (e.g. a free seat in their car)
		local best, bestD = nil, math.huge
		for _, s in ipairs(Workspace:GetDescendants()) do
			if (s:IsA("VehicleSeat") or s:IsA("Seat")) and s.Occupant == nil then
				local d = (s.Position - troot.Position).Magnitude
				if d < bestD and d < 60 then bestD = d; best = s end
			end
		end
		if not best then Library:Notify("No empty seat near that player"); return end
		task.spawn(function()
			pcall(function()
				local c = lPlayer.Character
				local hum = c and c:FindFirstChildWhichIsA("Humanoid")
				local root = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
				if root then root.CFrame = best.CFrame + Vector3.new(0, 2, 0) end
				task.wait(0.12)
				if hum and best.Occupant == nil then best:Sit(hum) end
			end)
		end)
	end):AddToolTip("Teleport into the nearest empty seat next to the selected player (e.g. a seat in their car/heli)")
	refreshTpPlayers()
	ctx:Connect(Players.PlayerAdded, refreshTpPlayers)
	ctx:Connect(Players.PlayerRemoving, function() task.wait(0.2); pcall(refreshTpPlayers) end)
	for _, k in ipairs({ "waypointList","tpPlayerList","useSitTeleport","tpPreload","desyncFlash","teleportSitTime" }) do ctx:Control(k) end

	pluginCleanup = function()
		for seat in pairs(activeTempSeats) do pcall(function() seat:Destroy() end) end
		activeTempSeats = {}
	end

	pcall(loadWaypoints)
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}