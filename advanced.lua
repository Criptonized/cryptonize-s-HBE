-- CryptsHBE plugin: Advanced (radar/minimap + movement + persistence + auto-soften)
-- Self-contained; uses globals + Bridge.relationshipColor / Bridge.getSafeGuiParent
-- (exposed by the core for external plugins). See plugins/advanced.md.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = workspace
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE

return {
	name = "Advanced", tab = "Advanced", requires = {},

	load = function(ctx)
		local function C(k) ctx:Control(k) end

		-- ---- Radar / minimap ----
		local radarBox = ctx:Groupbox("Radar", "left")
		radarBox:AddToggle("radarEnabled", { Text = "Enable Radar", Default = false, Tooltip = "Top-right minimap of nearby players, rotated to your view,\ncoloured by Enemy/Ally relationship. (Default: OFF)" }); C("radarEnabled")
		radarBox:AddSlider("radarRange", { Text = "Range (studs)", Min = 50, Max = 2000, Default = 350, Rounding = 0 }); C("radarRange")
		radarBox:AddSlider("radarSize", { Text = "Size (px)", Min = 120, Max = 420, Default = 200, Rounding = 0 }); C("radarSize")
		local parent = (Bridge.getSafeGuiParent and Bridge.getSafeGuiParent()) or game:GetService("CoreGui")
		local rg = ctx:Track(Instance.new("ScreenGui"))
		rg.Name = "CryptsHBE_Radar"; rg.ResetOnSpawn = false; rg.IgnoreGuiInset = true; rg.DisplayOrder = 20; rg.Parent = parent
		local frame = Instance.new("Frame"); frame.AnchorPoint = Vector2.new(1, 0); frame.Position = UDim2.new(1, -12, 0, 12)
		frame.Size = UDim2.fromOffset(200, 200); frame.BackgroundColor3 = Color3.fromRGB(12, 12, 12); frame.BackgroundTransparency = 0.35; frame.BorderSizePixel = 0; frame.Visible = false; frame.Parent = rg
		Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
		local meDot = Instance.new("Frame"); meDot.Size = UDim2.fromOffset(5, 5); meDot.AnchorPoint = Vector2.new(0.5, 0.5); meDot.Position = UDim2.fromScale(0.5, 0.5); meDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255); meDot.BorderSizePixel = 0; meDot.Parent = frame
		Instance.new("UICorner", meDot).CornerRadius = UDim.new(1, 0)
		local dots = {}
		local function getDot(i)
			if not dots[i] then
				local d = Instance.new("Frame"); d.Size = UDim2.fromOffset(6, 6); d.AnchorPoint = Vector2.new(0.5, 0.5); d.BorderSizePixel = 0; d.Parent = frame
				Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0); dots[i] = d
			end
			return dots[i]
		end
		ctx:Connect(RunService.RenderStepped, function()
			if not (Toggles.radarEnabled and Toggles.radarEnabled.Value) then frame.Visible = false; return end
			local cam = Workspace.CurrentCamera
			local lc = lPlayer.Character
			local lroot = lc and (lc:FindFirstChild("HumanoidRootPart") or lc:FindFirstChild("Head"))
			if not lroot then frame.Visible = false; return end
			frame.Visible = true
			local sz = Options.radarSize.Value; frame.Size = UDim2.fromOffset(sz, sz)
			local half, range = sz / 2, Options.radarRange.Value
			local lv = cam.CFrame.LookVector
			local theta = math.atan2(lv.X, lv.Z)
			local s, c = math.sin(theta), math.cos(theta)
			local idx = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= lPlayer then
					local ch = plr.Character
					local node = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Head"))
					if node then
						local rel = node.Position - lroot.Position
						local x = rel.X * c - rel.Z * s
						local z = rel.X * s + rel.Z * c
						if math.abs(x) <= range and math.abs(z) <= range then
							idx = idx + 1
							local d = getDot(idx)
							d.Position = UDim2.fromOffset(half + (x / range) * half, half - (z / range) * half)
							local ok, col = pcall(Bridge.relationshipColor, plr)
							d.BackgroundColor3 = (ok and col) or Color3.fromRGB(255, 80, 80)
							d.Visible = true
						end
					end
				end
			end
			for j = idx + 1, #dots do dots[j].Visible = false end
		end)

		-- ---- Movement ----
		local moveBox = ctx:Groupbox("Movement", "right")
		moveBox:AddToggle("bhopEnabled", { Text = "Bunny Hop", Default = false, Tooltip = "Auto-jump the instant you land while holding Space. (Default: OFF)" }); C("bhopEnabled")
		moveBox:AddToggle("infJumpEnabled", { Text = "Infinite Jump", Default = false, Tooltip = "Jump again any time you press Space, mid-air. (Default: OFF)" }); C("infJumpEnabled")
		local function lhum() local ch = lPlayer.Character return ch and ch:FindFirstChildWhichIsA("Humanoid") end
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.bhopEnabled and Toggles.bhopEnabled.Value) then return end
			if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end
			local h = lhum(); if h and h.FloorMaterial ~= Enum.Material.Air then h.Jump = true end
		end)
		ctx:Connect(UserInputService.InputBegan, function(i, gp)
			if gp then return end
			if i.KeyCode == Enum.KeyCode.Space and Toggles.infJumpEnabled and Toggles.infJumpEnabled.Value then
				local h = lhum(); if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end
			end
		end)

		-- ---- Persistence ----
		local persBox = ctx:Groupbox("Persistence", "left")
		persBox:AddInput("persistUrl", { Text = "Loader URL", Default = "", Tooltip = "URL the script is loaded from. Required to re-inject after a teleport." }); C("persistUrl")
		local function armPersist()
			if not (Toggles.persistEnabled and Toggles.persistEnabled.Value) then return end
			local url = Options.persistUrl and Options.persistUrl.Value
			if not url or url == "" then Library:Notify("Set a Loader URL first"); return end
			if not queue_on_teleport then Library:Notify("Executor lacks queue_on_teleport"); return end
			pcall(function() queue_on_teleport("loadstring(game:HttpGet('" .. url .. "'))()") end)
			Library:Notify("Persistence armed for next teleport")
		end
		persBox:AddToggle("persistEnabled", { Text = "Re-inject on Teleport", Default = false, Tooltip = "After a place teleport, re-run the script from the Loader URL. (Default: OFF)" }):OnChanged(armPersist); C("persistEnabled")
		persBox:AddButton("Arm Now", armPersist):AddToolTip("Queue the re-inject for the next teleport.")

		-- ---- Auto-Soften (reacts to Phantom Recon) ----
		local softBox = ctx:Groupbox("Auto-Soften", "right")
		softBox:AddToggle("autoSoften", { Text = "Auto-Soften on AC", Default = false, Tooltip = "When Phantom Recon (Tier 4) detects an anti-cheat, auto-dial\naggressive settings into safer ranges. (Default: OFF)" }); C("autoSoften")
		local softLast = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.autoSoften and Toggles.autoSoften.Value) then return end
			local now = tick(); if now - softLast < 1 then return end; softLast = now
			if Bridge and Bridge.DeepScan and Bridge.DeepScan.acActive then
				pcall(function() if Options.extenderSize and Options.extenderSize.Value > 12 then Options.extenderSize:SetValue(12) end end)
				pcall(function() if Toggles.humanizationToggled and not Toggles.humanizationToggled.Value then Toggles.humanizationToggled:SetValue(true) end end)
				pcall(function() if Toggles.collisionsToggled and Toggles.collisionsToggled.Value then Toggles.collisionsToggled:SetValue(false) end end)
				pcall(function() if Options.maxPlausibleMult and Options.maxPlausibleMult.Value == 0 then Options.maxPlausibleMult:SetValue(3) end end)
			end
		end)
	end,

	unload = function() end,  -- ctx auto-cleans the connections + the radar ScreenGui
}
