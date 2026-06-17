-- CryptsHBE plugin: Dot ESP (tab "Dots")
-- Small filled dots floating above players' heads -- like the team-awareness ping some
-- games put on a keybind (e.g. hold "V" to see your squad). Team-coloured, distance-
-- limited, toggleable on a hotkey. Pure read-only screen projection (DrawingFallback),
-- independent of the HBE filters (its OWN distance), and it honours Streamer hide + the
-- menu auto-hide like the core ESP does.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = workspace
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE
local DrawingFallback = getgenv().DrawingFallback
local pluginCleanup = nil

local function sameTeam(plr)
	local ok, same = pcall(function()
		if lPlayer.Team ~= nil or plr.Team ~= nil then return lPlayer.Team == plr.Team end
		return lPlayer.TeamColor == plr.TeamColor
	end)
	return ok and same
end

local function headOf(char)
	return char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
end
local function aliveChar(plr)
	local char = plr.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if hum and hum.Health > 0 then return char end
	return nil
end

return {
	name = "DotESP", tab = "Dots", requires = {},
	load = function(ctx)
		local function C(k) ctx:Control(k) end
		local g = ctx:Groupbox("Dot ESP", "left")
		g:AddToggle("dotEspEnabled", { Text = "Enable", Default = false, Tooltip = "Show a dot above each shown player. (Default: OFF)" }); C("dotEspEnabled")
		g:AddToggle("dotEspAllies", { Text = "Show Teammates", Default = true, Tooltip = "Dot players on your team. (Default: ON)" }); C("dotEspAllies")
		g:AddToggle("dotEspEnemies", { Text = "Show Enemies", Default = false, Tooltip = "Dot players NOT on your team. (Default: OFF)" }); C("dotEspEnemies")
		g:AddToggle("dotEspTeamColor", { Text = "Team Colors", Default = true, Tooltip = "Colour dots by relationship (uses your ESP enemy/ally colours). Off = ally blue / enemy orange. (Default: ON)" }); C("dotEspTeamColor")
		g:AddSlider("dotEspSize", { Text = "Dot Size", Min = 2, Max = 14, Default = 5, Rounding = 0 }); C("dotEspSize")
		g:AddToggle("dotEspDynamic", { Text = "Dynamic Sizing", Default = false, Tooltip = "Scale dots by distance -- bigger up close, base size far away, so close dots stay visible instead of getting lost. (Default: OFF)" }); C("dotEspDynamic")
		g:AddSlider("dotEspMaxScale", { Text = "Close-up scale x", Min = 1, Max = 8, Default = 3, Rounding = 1, Tooltip = "With Dynamic Sizing: how much bigger a dot can get up close." }); C("dotEspMaxScale")
		g:AddSlider("dotEspHeight", { Text = "Height (studs)", Min = 0, Max = 10, Default = 3, Rounding = 1, Tooltip = "How far above the head to float the dot." }); C("dotEspHeight")
		g:AddSlider("dotEspDist", { Text = "Max Distance", Min = 0, Max = 3000, Default = 0, Rounding = 0, Tooltip = "0 = unlimited. Its OWN distance, separate from HBE." }); C("dotEspDist")

		local g2 = ctx:Groupbox("Hotkey", "right")
		g2:AddLabel("Press the bound key to toggle the dots\n(set it in the Keybinds tab). Default: V.", true)
		local lbl = g2:AddLabel("Dots: off", true)

		-- Toggle hotkey via the central Keybinds tab (mirrors the Enable toggle).
		if Bridge and Bridge.AddKeybind then
			pcall(function()
				Bridge:AddKeybind("dotEspToggle", "Dot ESP", "V", "Toggle", function(state)
					if Toggles.dotEspEnabled then pcall(function() Toggles.dotEspEnabled:SetValue(state) end) end
				end)
			end)
		end

		-- filled-dot pool (GUI fallback), tracked so unload frees them
		local POOL = 64
		local dots = {}
		for i = 1, POOL do
			local d = ctx:Track(DrawingFallback.new("Circle"))
			d.Filled = true; d.Radius = 5; d.Visible = false
			dots[i] = d
		end
		local function hideAll() for _, d in ipairs(dots) do d.Visible = false end end

		local function dotColor(plr)
			if Toggles.dotEspTeamColor and Toggles.dotEspTeamColor.Value and Bridge and Bridge.relationshipColor then
				local ok, c = pcall(Bridge.relationshipColor, plr)
				if ok and typeof(c) == "Color3" then return c end
			end
			return sameTeam(plr) and Color3.fromRGB(80, 200, 255) or Color3.fromRGB(255, 150, 40)
		end

		ctx:Connect(RunService.RenderStepped, function()
			if not (Toggles.dotEspEnabled and Toggles.dotEspEnabled.Value) then hideAll(); return end
			-- honour Streamer hide + menu auto-hide, like the core ESP
			if (Bridge and Bridge.Streamer and Bridge.Streamer.hideESP) or (Bridge and Bridge.MenuOpen) then hideAll(); return end
			local cam = Workspace.CurrentCamera
			if not cam then hideAll(); return end
			local lr = headOf(lPlayer.Character)
			local maxd = (Options.dotEspDist and Options.dotEspDist.Value) or 0
			local size = (Options.dotEspSize and Options.dotEspSize.Value) or 5
			local dynamic = Toggles.dotEspDynamic and Toggles.dotEspDynamic.Value
			local maxScale = (Options.dotEspMaxScale and Options.dotEspMaxScale.Value) or 3
			local height = (Options.dotEspHeight and Options.dotEspHeight.Value) or 3
			local showA = Toggles.dotEspAllies and Toggles.dotEspAllies.Value
			local showE = Toggles.dotEspEnemies and Toggles.dotEspEnemies.Value
			local n = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= lPlayer and n < POOL then
					local ally = sameTeam(plr)
					if (ally and showA) or ((not ally) and showE) then
						local char = aliveChar(plr)
						local h = headOf(char)
						if h then
							local wp = h.Position + Vector3.new(0, height, 0)
							local ok = true
							if maxd > 0 and lr then
								if (h.Position - lr.Position).Magnitude > maxd then ok = false end
							end
							if ok then
								local sp, onScreen = cam:WorldToViewportPoint(wp)
								if onScreen and sp.Z > 0 then
									n = n + 1
									local d = dots[n]
									-- Dynamic: scale up close (sp.Z = camera depth in studs); never below base.
									d.Radius = (dynamic and sp.Z > 1) and (size * math.clamp(120 / sp.Z, 1, maxScale)) or size
									d.Color = dotColor(plr)
									d.Position = Vector2.new(sp.X, sp.Y)
									d.Visible = true
								end
							end
						end
					end
				end
			end
			for i = n + 1, POOL do dots[i].Visible = false end
			pcall(function() lbl:SetText("Dots: " .. n .. " shown") end)
		end)

		pluginCleanup = function()
			pcall(hideAll)
			pcall(function() if Bridge and Bridge.ClearKeybind then Bridge:ClearKeybind("dotEspToggle") end end)
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
