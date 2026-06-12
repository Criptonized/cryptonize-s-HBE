-- CryptsHBE plugin: Silent Aim (hook-free Remote mode + Extreme namecall-hook mode)
-- ============================================================================
-- Two methods share ONE targeting engine (FOV + bone + priority + LOS + lock):
--   * "Remote (hook-free)"  -- detection-safe: fires the chosen damage RemoteEvent at
--                              the target yourself (like Remote Replay, but FOV-aimed).
--   * "Hook namecall (Extreme)" -- crosses hard rule #3 (a real __namecall hook), so it
--                              is OPT-IN and OFF by default. It redirects the game's OWN
--                              FireServer of the chosen remote to the target's bone, so
--                              the game's real timing/args are used -- only the hit moves.
-- SAFETY: the hook is SCOPED to the single remote you pick (self == chosenRemote), so it
--         never touches chat/movement/other FireServer calls. checkcaller() guards against
--         our own fires. A metamethod hook can't be fully removed on most executors, so
--         unload makes it an inert pass-through (it's only ever installed if you opt in).
-- Raycast-hit games (no damage remote) can't be silent-aimed this way -- that needs a
-- raycast hook, a separate frontier. Untested in-game: best-effort, tune per game.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = workspace
local lPlayer = Players.LocalPlayer
local DrawingFallback = getgenv().DrawingFallback
local Bridge = getgenv().CryptsHBE

-- module-level so unload can reach the hook state
local hookInstalled = false
local hookActive    = false   -- the installed hook is a no-op pass-through unless this is true
local oldNamecall   = nil
local currentTarget, currentPart = nil, nil
local chosenRemote  = nil
local pluginCleanup = nil

return {
	name = "SilentAim", tab = "Silent Aim", requires = {},

	load = function(ctx)
		local cam = Workspace.CurrentCamera
		local aimGroup    = ctx:Groupbox("Silent Aim", "left")
		local remoteGroup = ctx:Groupbox("Remote (hook-free)", "right")
		local hookGroup   = ctx:Groupbox("Extreme (hooks)", "right")
		local function C(k) ctx:Control(k) end

		-- ---- shared targeting UI ----
		aimGroup:AddToggle("saEnabled", { Text = "Enable Silent Aim", Default = false, Tooltip = "Master switch. Pick a Method below. (Default: OFF)" }); C("saEnabled")
		aimGroup:AddDropdown("saMethod", { Text = "Method", Values = { "Remote (hook-free)", "Hook namecall (Extreme)" }, Default = "Remote (hook-free)", Multi = false, AllowNull = false, Tooltip = "Remote = detection-safe, you fire the damage remote.\nHook = redirects the game's own fire (more effective, detectable)." }); C("saMethod")
		aimGroup:AddDropdown("saBone", { Text = "Bone Target", Values = { "Head", "Torso", "UpperTorso", "HumanoidRootPart" }, Default = "Head", Multi = false, AllowNull = false }); C("saBone")
		aimGroup:AddDropdown("saPriority", { Text = "Priority", Values = { "Closest to Crosshair", "Closest Distance", "Lowest Health" }, Default = "Closest to Crosshair", Multi = false, AllowNull = false }); C("saPriority")
		aimGroup:AddToggle("saLock", { Text = "Target Lock", Default = false, Tooltip = "Stick to one target until it dies/leaves the FOV. (Default: OFF)" }); C("saLock")
		aimGroup:AddToggle("saFOVCircle", { Text = "FOV Circle", Default = true }); C("saFOVCircle")
		aimGroup:AddSlider("saFOV", { Text = "FOV Radius (px)", Min = 20, Max = 800, Default = 250, Rounding = 0 }); C("saFOV")
		aimGroup:AddSlider("saMaxDist", { Text = "Max Distance", Min = 50, Max = 10000, Default = 5000, Rounding = 0 }); C("saMaxDist")
		aimGroup:AddSlider("saHitChance", { Text = "Hit Chance %", Min = 1, Max = 100, Default = 100, Rounding = 0, Tooltip = "Roll per shot; below = let it miss naturally (looks legit). (Default: 100)" }); C("saHitChance")
		aimGroup:AddToggle("saLOS", { Text = "Line of Sight Check", Default = false, Tooltip = "Only target players you have a clear line to. (Default: OFF)" }); C("saLOS")
		aimGroup:AddToggle("saIgnoreTeam", { Text = "Ignore Team", Default = true }); C("saIgnoreTeam")
		aimGroup:AddToggle("saIgnoreWL", { Text = "Ignore Whitelisted", Default = true }); C("saIgnoreWL")
		local saInfo = aimGroup:AddLabel("Target: none", true)

		-- ---- damage remote (shared by both methods) ----
		remoteGroup:AddLabel("Pick the game's DAMAGE RemoteEvent (same one Remote\nReplay uses). Both methods send/redirect to it.", true)
		local remotes = {}
		remoteGroup:AddDropdown("saRemote", { Text = "Damage Remote", Values = {}, Multi = false, AllowNull = true, Tooltip = "Refresh, then pick the RemoteEvent the gun fires to deal damage." }); C("saRemote")
		remoteGroup:AddDropdown("saArg", { Text = "Argument / Redirect", Values = { "Target Character", "Target Part", "Target Position", "Aim Direction", "Target Player", "None" }, Default = "Target Character", Multi = false, AllowNull = false, Tooltip = "What the remote expects as the hit. Match the game's signature." }); C("saArg")
		remoteGroup:AddDropdown("saActivate", { Text = "Fire When (Remote mode)", Values = { "Hold Right Mouse", "Hold Left Mouse", "Always" }, Default = "Hold Left Mouse", Multi = false, AllowNull = false }); C("saActivate")
		remoteGroup:AddSlider("saRate", { Text = "Fire Rate (/s)", Min = 1, Max = 30, Default = 10, Rounding = 0 }); C("saRate")
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
			Options.saRemote.Values = names; pcall(function() Options.saRemote:SetValues() end)
			Library:Notify("Found " .. #names .. " RemoteEvents")
		end
		remoteGroup:AddButton("Refresh Remotes", refreshRemotes):AddToolTip("Scan the game for RemoteEvents.")
		local function syncChosen() chosenRemote = remotes[Options.saRemote.Value or ""] end
		Options.saRemote:OnChanged(syncChosen)

		-- ---- targeting engine ----
		local function sameTeam(plr)
			local ok, s = pcall(function()
				if lPlayer.Team ~= nil or plr.Team ~= nil then return lPlayer.Team == plr.Team end
				return lPlayer.TeamColor == plr.TeamColor
			end)
			return ok and s or false
		end
		local function boneOf(char)
			local b = (Options.saBone and Options.saBone.Value) or "Head"
			return char:FindFirstChild(b) or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
		end
		local function valid(plr)
			if plr == lPlayer then return false end
			local c = plr.Character
			local hum = c and c:FindFirstChildWhichIsA("Humanoid")
			if not (c and hum and hum.Health > 0) then return false end
			if Toggles.saIgnoreWL and Toggles.saIgnoreWL.Value and Options.whitelistPlayerList and table.find(Options.whitelistPlayerList:GetActiveValues(), plr.Name) then return false end
			if Toggles.saIgnoreTeam and Toggles.saIgnoreTeam.Value and sameTeam(plr) then return false end
			return true
		end
		local function hasLOS(part)
			local lc = lPlayer.Character
			if not lc then return true end
			local ok, clear = pcall(function()
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { lc, part.Parent }
				return Workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, rp) == nil
			end)
			return ok and clear or false
		end
		local lockedPlayer = nil
		local function pickTarget()
			cam = Workspace.CurrentCamera
			local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
			local mode = (Options.saPriority and Options.saPriority.Value) or "Closest to Crosshair"
			local fov = (Options.saFOV and Options.saFOV.Value) or 250
			local maxD = (Options.saMaxDist and Options.saMaxDist.Value) or 5000
			local bestScore, bestPlr, bestPart = math.huge, nil, nil
			for _, plr in ipairs(Players:GetPlayers()) do
				if valid(plr) then
					local c = plr.Character
					local part = c and boneOf(c)
					local hum = c and c:FindFirstChildWhichIsA("Humanoid")
					if part and hum then
						local dist = (part.Position - cam.CFrame.Position).Magnitude
						if dist <= maxD then
							local sp, on = cam:WorldToViewportPoint(part.Position)
							local sdist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
							if on and sdist <= fov and ((not Toggles.saLOS) or (not Toggles.saLOS.Value) or hasLOS(part)) then
								local score
								if mode == "Closest Distance" then score = dist
								elseif mode == "Lowest Health" then score = hum.Health
								else score = sdist end
								if score < bestScore then bestScore, bestPlr, bestPart = score, plr, part end
							end
						end
					end
				end
			end
			return bestPlr, bestPart
		end

		local fovRing = ctx:Track(DrawingFallback.new("Circle"))
		fovRing.Thickness = 1; fovRing.Filled = false; fovRing.NumSides = 48; fovRing.Color = Color3.fromRGB(255, 255, 255); fovRing.Visible = false

		-- resolve target every frame; the hook + remote loop both read currentTarget/Part
		ctx:Connect(RunService.RenderStepped, function()
			cam = Workspace.CurrentCamera
			if Toggles.saEnabled.Value and Toggles.saFOVCircle.Value then
				fovRing.Radius = Options.saFOV.Value
				fovRing.Position = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
				fovRing.Visible = true
			else
				fovRing.Visible = false
			end
			if not Toggles.saEnabled.Value then currentTarget, currentPart = nil, nil; pcall(function() saInfo:SetText("Target: none") end); return end
			local plr, part
			if Toggles.saLock and Toggles.saLock.Value and lockedPlayer and valid(lockedPlayer) and lockedPlayer.Character then
				plr, part = lockedPlayer, boneOf(lockedPlayer.Character)
			else
				plr, part = pickTarget(); lockedPlayer = plr
			end
			currentTarget, currentPart = plr, part
			pcall(function() saInfo:SetText("Target: " .. (plr and (plr.Name .. "  " .. math.floor(((part and part.Position or cam.CFrame.Position) - cam.CFrame.Position).Magnitude) .. "m") or "none")) end)
		end)

		-- ---- shared: build the args for the chosen remote pointing at the target ----
		local function buildArg(part)
			local mode = (Options.saArg and Options.saArg.Value) or "Target Character"
			if mode == "Target Player" then return currentTarget
			elseif mode == "Target Character" then return part.Parent
			elseif mode == "Target Part" then return part
			elseif mode == "Target Position" then return part.Position
			elseif mode == "Aim Direction" then return (part.Position - cam.CFrame.Position).Unit
			else return nil end
		end
		local function rollHit() return (not Options.saHitChance) or (math.random(100) <= Options.saHitChance.Value) end

		-- ---- METHOD 1: Remote (hook-free) -- we fire the chosen remote ourselves ----
		local lastFire = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.saEnabled.Value) then return end
			if (Options.saMethod.Value or ""):find("Remote") == nil then return end
			if not (chosenRemote and currentPart) then return end
			local gate = Options.saActivate.Value
			local on = (gate == "Always")
				or (gate == "Hold Right Mouse" and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
				or (gate == "Hold Left Mouse" and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
			if not on then return end
			local now = tick(); if now - lastFire < (1 / math.max(1, Options.saRate.Value)) then return end
			lastFire = now
			if Bridge.isHoneypot and Bridge.isHoneypot(chosenRemote) then return end
			if not rollHit() then return end
			local mode = Options.saArg.Value
			local arg = buildArg(currentPart)
			pcall(function() if mode == "None" then chosenRemote:FireServer() else chosenRemote:FireServer(arg) end end)
		end)

		-- ---- METHOD 2: Hook namecall (Extreme) -- redirect the game's OWN fire ----
		hookGroup:AddLabel("EXTREME / opt-in. Installs a __namecall hook (crosses\nthe no-hooks rule -> more detectable). Scoped to the\nremote above, so other remotes are untouched.", true)
		local hookInfo = hookGroup:AddLabel("Hook: not installed")
		hookGroup:AddDropdown("saRedirect", { Text = "Redirect", Values = { "Auto (parts + position)", "Hit Position", "Aim Direction", "Parts only" }, Default = "Auto (parts + position)", Multi = false, AllowNull = false, Tooltip = "What in the remote's args to swap for the target. Match the game." }); C("saRedirect")

		local function installHook()
			if hookInstalled then return true end
			if not (hookmetamethod and getnamecallmethod) then Library:Notify("Executor lacks hookmetamethod/getnamecallmethod"); return false end
			local ok = pcall(function()
				oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
					local method = getnamecallmethod and getnamecallmethod() or ""
					if hookActive and Toggles.saEnabled and Toggles.saEnabled.Value
						and Options.saMethod and (Options.saMethod.Value or ""):find("Hook")
						and self == chosenRemote
						and (method == "FireServer" or method == "InvokeServer")
						and (not checkcaller or not checkcaller()) then
						local part = currentPart
						if part and part.Parent and rollHit() then
							-- Capture args in the OUTER scope (inner {...} wouldn't see them),
							-- then rewrite under pcall so a destroyed part / odd arg can never
							-- error the namecall (which would break the game's remote call).
							local args = { ... }
							local edited = pcall(function()
								local pos = part.Position
								local camPos = Workspace.CurrentCamera.CFrame.Position  -- read LIVE (reload-safe)
								local rmode = (Options.saRedirect and Options.saRedirect.Value) or "Auto (parts + position)"
								for i, v in ipairs(args) do
									local t = typeof(v)
									if t == "Vector3" then
										if rmode:find("Direction") then args[i] = (pos - camPos).Unit
										elseif rmode:find("Position") or rmode:find("Auto") then args[i] = pos end
									elseif t == "CFrame" and (rmode:find("Position") or rmode:find("Auto")) then
										args[i] = CFrame.new(pos)
									elseif t == "Instance" and (rmode:find("Parts") or rmode:find("Auto")) then
										if v:IsA("BasePart") or v:IsA("Model") then args[i] = part end
									end
								end
							end)
							if edited then return oldNamecall(self, table.unpack(args)) end
						end
					end
					return oldNamecall(self, ...)
				end)
			end)
			if ok then hookInstalled = true; return true end
			Library:Notify("Hook install failed"); return false
		end

		hookGroup:AddToggle("saHook", { Text = "Enable Hooks (Extreme)", Default = false, Tooltip = "Install + arm the __namecall redirect for the chosen remote.\nOnly takes effect when Method = Hook. (Default: OFF)" }); C("saHook")
		Toggles.saHook:OnChanged(function()
			if Toggles.saHook.Value then
				if installHook() then hookActive = true; pcall(function() hookInfo:SetText("Hook: armed (scoped to chosen remote)") end) end
			else
				hookActive = false
				pcall(function() hookInfo:SetText(hookInstalled and "Hook: installed but DISARMED" or "Hook: not installed") end)
			end
		end)

		-- Bottom-of-tab tutorial.
		local howGroup = ctx:Groupbox("How to Use", "left")
		howGroup:AddLabel(
			"Bullets hit the target without your\n" ..
			"camera moving. BOTH methods need the\n" ..
			"game's DAMAGE remote.\n\n" ..
			"SETUP:\n" ..
			"  1. Refresh Remotes -> pick the gun's\n" ..
			"     damage RemoteEvent.\n" ..
			"  2. Set Argument/Redirect to match it\n" ..
			"     (Character/Part/Position/Direction).\n" ..
			"  3. Tune Bone, FOV, Priority, Max\n" ..
			"     Distance, Hit Chance, LOS.\n\n" ..
			"REMOTE (hook-free, safe): YOU fire that\n" ..
			"remote at the FOV target. Set 'Fire\n" ..
			"When' (Hold LMB/RMB/Always) + Fire Rate.\n\n" ..
			"HOOK (Extreme, detectable): flip 'Enable\n" ..
			"Hooks' to redirect the game's OWN shot.\n" ..
			"Set Redirect to match. Scoped to the\n" ..
			"one remote you picked.\n\n" ..
			"Don't know the remote? Calibrate ->\n" ..
			"Deep-Dump lists the gun's remotes.\n" ..
			"Wallbang = Line of Sight Check OFF.\n" ..
			"Raycast-hit games can't be done here.",
			true)

		syncChosen()
		pluginCleanup = function()
			hookActive = false  -- the installed metamethod hook becomes an inert pass-through
		end
	end,

	-- ctx auto-disconnects the loops + destroys the FOV ring/groupboxes + clears keys.
	-- The metamethod hook (if it was ever installed) can't be fully removed on most
	-- executors, so we leave it as a no-op pass-through (hookActive=false).
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
