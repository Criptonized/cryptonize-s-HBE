-- FurryHBE plugin: Spectate (cycle the camera through players)
-- Self-contained; button-only so teardown is perfectly clean. See plugins/spectate.md.
return {
	name = "Spectate", tab = "Spectate", requires = {},
	load = function(ctx)
		local Players = game:GetService("Players")
		local lp = Players.LocalPlayer
		local cam = workspace.CurrentCamera
		local g = ctx:Groupbox("Spectate")
		local label = g:AddLabel("Spectating: self")
		local list, idx = {}, 0
		local function refresh()
			list = {}
			for _, p in ipairs(Players:GetPlayers()) do if p ~= lp then list[#list + 1] = p end end
		end
		local function setSubject(p)
			local ch = p and p.Character
			local hum = ch and ch:FindFirstChildWhichIsA("Humanoid")
			if hum then cam.CameraSubject = hum; label:SetText("Spectating: " .. p.Name) end
		end
		local function selfSubject()
			local hum = lp.Character and lp.Character:FindFirstChildWhichIsA("Humanoid")
			if hum then cam.CameraSubject = hum end
			idx = 0; label:SetText("Spectating: self")
		end
		g:AddButton("Next Player", function()
			refresh(); if #list == 0 then label:SetText("No other players"); return end
			idx = idx % #list + 1; setSubject(list[idx])
		end)
		g:AddButton("Previous Player", function()
			refresh(); if #list == 0 then return end
			idx = (idx - 2) % #list + 1; setSubject(list[idx])
		end)
		g:AddButton("Reset to Self", selfSubject)
		ctx:Connect(Players.PlayerRemoving, function(p) if list[idx] == p then selfSubject() end end)
	end,
	unload = function()
		local lp = game:GetService("Players").LocalPlayer
		local hum = lp.Character and lp.Character:FindFirstChildWhichIsA("Humanoid")
		if hum then workspace.CurrentCamera.CameraSubject = hum end
	end,
}
