-- FurryHBE plugin: World (Fullbright, No Fog, Custom FOV, Infinite Stamina)
-- All GENERIC / game-agnostic client visuals + a best-effort stamina holder. No game
-- knowledge needed, so these work broadly (unlike the gun hacks, which are per-game).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = workspace
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

return {
	name = "World", tab = "World", requires = {},
	load = function(ctx)
		local visGroup  = ctx:Groupbox("Visuals", "left")
		local camGroup  = ctx:Groupbox("Camera", "left")
		local utilGroup = ctx:Groupbox("Utility", "right")

		-- Snapshot originals so toggling off restores the game's own look.
		local orig = {
			Brightness = Lighting.Brightness, GlobalShadows = Lighting.GlobalShadows,
			Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
			FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
		}
		local origFOV = (Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView) or 70

		visGroup:AddToggle("fullbright", { Text = "Fullbright", Default = false, Tooltip = "Remove darkness/shadows for full visibility. (Default: OFF)" }); ctx:Control("fullbright")
		visGroup:AddToggle("noFog", { Text = "No Fog", Default = false, Tooltip = "Remove fog + atmospheric haze. (Default: OFF)" }); ctx:Control("noFog")

		-- One function handles BOTH directions: bright/clear when on, restore when off.
		local function applyLighting()
			if Toggles.fullbright and Toggles.fullbright.Value then
				Lighting.Brightness = 2; Lighting.GlobalShadows = false
				Lighting.Ambient = Color3.fromRGB(178, 178, 178); Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
			else
				Lighting.Brightness = orig.Brightness; Lighting.GlobalShadows = orig.GlobalShadows
				Lighting.Ambient = orig.Ambient; Lighting.OutdoorAmbient = orig.OutdoorAmbient
			end
			if Toggles.noFog and Toggles.noFog.Value then
				Lighting.FogEnd = 1e9; Lighting.FogStart = 1e9
				pcall(function() local a = Lighting:FindFirstChildOfClass("Atmosphere"); if a then a.Density = 0; a.Haze = 0 end end)
			else
				Lighting.FogEnd = orig.FogEnd; Lighting.FogStart = orig.FogStart
			end
		end
		-- Re-assert while on (games continuously rewrite lighting); idle when both off.
		ctx:Connect(RunService.Heartbeat, function()
			if (Toggles.fullbright and Toggles.fullbright.Value) or (Toggles.noFog and Toggles.noFog.Value) then applyLighting() end
		end)
		Toggles.fullbright:OnChanged(applyLighting)
		Toggles.noFog:OnChanged(applyLighting)

		camGroup:AddToggle("customFovEnabled", { Text = "Custom FOV", Default = false, Tooltip = "Override the camera field of view. (Default: OFF)" }); ctx:Control("customFovEnabled")
		camGroup:AddSlider("customFov", { Text = "FOV", Min = 30, Max = 120, Default = 70, Rounding = 0 }); ctx:Control("customFov")
		ctx:Connect(RunService.RenderStepped, function()
			local c = Workspace.CurrentCamera
			if c and Toggles.customFovEnabled and Toggles.customFovEnabled.Value then c.FieldOfView = Options.customFov.Value end
		end)
		Toggles.customFovEnabled:OnChanged(function()
			if not Toggles.customFovEnabled.Value then local c = Workspace.CurrentCamera; if c then pcall(function() c.FieldOfView = origFOV end) end end
		end)

		-- Infinite Stamina: best-effort. Holds any client-side stamina/energy value at the
		-- max it's been seen at. Won't help if stamina is enforced server-side.
		utilGroup:AddToggle("infStamina", { Text = "Infinite Stamina", Default = false, Tooltip = "Hold a stamina/energy value full. Client-side only; won't work\nif the game validates stamina on the server. (Default: OFF)" }); ctx:Control("infStamina")
		local STAM_WORDS = { "stamina", "sprint", "energy", "breath", "endurance", "fatigue", "exhaust", "oxygen" }
		local stamMax = setmetatable({}, { __mode = "k" })
		local lastStam = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.infStamina and Toggles.infStamina.Value) then return end
			local now = tick(); if now - lastStam < 0.15 then return end; lastStam = now
			pcall(function()
				for _, root in ipairs({ lPlayer.Character, lPlayer:FindFirstChild("Backpack"), lPlayer:FindFirstChild("leaderstats") }) do
					if root then
						for _, d in ipairs(root:GetDescendants()) do
							if d:IsA("NumberValue") or d:IsA("IntValue") then
								local n = d.Name:lower()
								for _, w in ipairs(STAM_WORDS) do
									if n:find(w) then
										stamMax[d] = math.max(stamMax[d] or d.Value, d.Value)
										if d.Value < stamMax[d] then pcall(function() d.Value = stamMax[d] end) end
										break
									end
								end
							end
						end
					end
				end
			end)
		end)

		pluginCleanup = function()
			-- restore everything we may have changed
			pcall(function()
				Lighting.Brightness = orig.Brightness; Lighting.GlobalShadows = orig.GlobalShadows
				Lighting.Ambient = orig.Ambient; Lighting.OutdoorAmbient = orig.OutdoorAmbient
				Lighting.FogEnd = orig.FogEnd; Lighting.FogStart = orig.FogStart
			end)
			pcall(function() local c = Workspace.CurrentCamera; if c then c.FieldOfView = origFOV end end)
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
