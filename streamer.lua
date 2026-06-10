-- FurryHBE plugin: Streamer Mode (hide visuals, panic key, UI hide, update-rate jitter)
local RunService = game:GetService("RunService")
local Bridge = getgenv().FurryHBE
local pluginCleanup = nil

return {
	name = "Streamer", tab = "Streamer", requires = {},
	load = function(ctx)
		local mainGui = Library.ScreenGui
		local streamTab    = ctx.tab
		local visualsGroup = streamTab:AddLeftGroupbox("Visual Overrides")
		local uiGroup      = streamTab:AddLeftGroupbox("UI Control")
		local panicGroup   = streamTab:AddRightGroupbox("Panic")
		local miscGroup    = streamTab:AddRightGroupbox("Extra")

		visualsGroup:AddToggle("streamerMaster", { Text = "Streamer Mode", Default = false, Tooltip = "Hide all visual indicators while keeping hitbox functionality active. (Default: OFF)" })
		visualsGroup:AddToggle("hideFOVCircle",  { Text = "Hide FOV Circle",  Default = true })
		visualsGroup:AddToggle("hidePlayerESP",  { Text = "Hide Player ESP",  Default = true })
		visualsGroup:AddToggle("hideChams",      { Text = "Hide Chams",       Default = true })
		visualsGroup:AddToggle("hideHitboxGlow", { Text = "Hide Hitbox Glow", Default = true, Tooltip = "Force extended hitboxes fully transparent\n(without touching your Transparency slider). (Default: ON)" })
		uiGroup:AddToggle("hideUIOnToggle", { Text = "Hide UI with Streamer Mode", Default = false, Tooltip = "Also hide the HBE window itself whenever Streamer Mode is on. (Default: OFF)" })
		uiGroup:AddLabel("Hide/Show UI"):AddKeyPicker("hideUIKey", { Default = "F8", NoUI = true, Text = "Toggle UI visibility" })
		panicGroup:AddLabel("Emergency Key"):AddKeyPicker("streamerPanicKey", { Default = "End", NoUI = true, Text = "Instant clean state" })
		miscGroup:AddToggle("randomizeUpdateRate", { Text = "Jitter Update Rate", Default = false, Tooltip = "Add small random variation to the Update Rate\n(light anti-pattern; throttled). (Default: OFF)" })
		for _, k in ipairs({ "streamerMaster","hideFOVCircle","hidePlayerESP","hideChams","hideHitboxGlow","hideUIOnToggle","hideUIKey","streamerPanicKey","randomizeUpdateRate" }) do ctx:Control(k) end

		local menuVisible = true
		local hiddenByStreamer = false
		local function setMenu(visible)
			menuVisible = visible
			if mainGui then pcall(function() mainGui.Enabled = visible end)
			else pcall(function() Library:SetVisible(visible) end) end
		end
		local function syncStreamerFlags()
			local master = Toggles.streamerMaster.Value
			local S = Bridge.Streamer
			S.hideFOV    = master and Toggles.hideFOVCircle.Value or false
			S.hideESP    = master and Toggles.hidePlayerESP.Value or false
			S.hideChams  = master and Toggles.hideChams.Value or false
			S.hideHitbox = master and Toggles.hideHitboxGlow.Value or false
			if master and Toggles.hideUIOnToggle.Value then
				if menuVisible then setMenu(false); hiddenByStreamer = true end
			elseif hiddenByStreamer and (not master or not Toggles.hideUIOnToggle.Value) then
				setMenu(true); hiddenByStreamer = false
			end
		end
		local jitterConn, lastJitter, originalUpdateRate = nil, 0, nil
		local function startJitter()
			if not Options.updateRate then return end
			originalUpdateRate = originalUpdateRate or Options.updateRate.Value
			if jitterConn then jitterConn:Disconnect() end
			jitterConn = RunService.Heartbeat:Connect(function()
				if not Toggles.randomizeUpdateRate.Value then return end
				local now = tick(); if now - lastJitter < 0.4 then return end; lastJitter = now
				local base = originalUpdateRate or 30
				Options.updateRate:SetValue(math.clamp(base + math.random(-5, 5), 1, 60))
			end)
		end
		local function stopJitter()
			if jitterConn then jitterConn:Disconnect(); jitterConn = nil end
			if originalUpdateRate and Options.updateRate then Options.updateRate:SetValue(originalUpdateRate); originalUpdateRate = nil end
		end
		Options.hideUIKey:OnClick(function() setMenu(not menuVisible); hiddenByStreamer = false end)
		Options.streamerPanicKey:OnClick(function()
			if Toggles.MasterToggle then Toggles.MasterToggle:SetValue(false) end
			if Toggles.streamerMaster then Toggles.streamerMaster:SetValue(false) end
			local S = Bridge.Streamer
			S.hideESP, S.hideChams, S.hideFOV, S.hideHitbox = false, false, false, false
			stopJitter(); setMenu(false); hiddenByStreamer = false
		end)
		for _, name in ipairs({ "streamerMaster","hideFOVCircle","hidePlayerESP","hideChams","hideHitboxGlow","hideUIOnToggle" }) do
			Toggles[name]:OnChanged(syncStreamerFlags)
		end
		Toggles.randomizeUpdateRate:OnChanged(function() if Toggles.randomizeUpdateRate.Value then startJitter() else stopJitter() end end)

		pluginCleanup = function()
			stopJitter()
			local S = Bridge.Streamer
			S.hideESP, S.hideChams, S.hideFOV, S.hideHitbox = false, false, false, false
			setMenu(true)
		end
		syncStreamerFlags()
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
