-- CryptsHBE plugin: Spectate (cycle the camera through players)
-- Self-contained. Searchable player dropdown (shows team + a snapshot distance) plus
-- Next/Previous cycling, and a live readout of the spectated player's team + distance.
return {
	name = "Spectate", tab = "Spectate", requires = {},
	load = function(ctx)
		local Players = game:GetService("Players")
		local RunService = game:GetService("RunService")
		local lp = Players.LocalPlayer
		local g = ctx:Groupbox("Spectate")
		local label = g:AddLabel("Spectating: self", true)

		-- Searchable picker: the dropdown lists "Name [Team] ~Dm" so you can see each
		-- player's team and roughly how far they are; the Search box filters by name.
		-- (LinoriaLib has no native search, so we drive the dropdown Values directly.)
		g:AddInput("spectateSearch", { Text = "Search", Default = "", Tooltip = "Filter the player list by name/display name. Empty = everyone." }); ctx:Control("spectateSearch")
		g:AddDropdown("spectatePlayer", { Text = "Player", Values = {}, Multi = false, AllowNull = true, Tooltip = "Pick a player to spectate. Shows [Team] and a snapshot distance." }); ctx:Control("spectatePlayer")

		local entryToPlayer = {}   -- "Name [Team] ~Dm" -> Player
		local subject = nil        -- currently spectated Player (nil = self)
		local list, idx = {}, 0    -- list backs Next/Previous cycling

		local function nodeOf(p)
			local c = p and p.Character
			return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
		end
		local function distTo(p)
			local me = nodeOf(lp)
			local them = nodeOf(p)
			if me and them then return math.floor((me.Position - them.Position).Magnitude) end
			return nil
		end
		local function teamTag(p)
			local ok, t = pcall(function() return p.Team and p.Team.Name end)
			return (ok and t) and (" [" .. t .. "]") or " [no team]"
		end

		local function rebuild()
			local q = (Options.spectateSearch and Options.spectateSearch.Value or ""):lower()
			entryToPlayer, list = {}, {}
			local entries = {}
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= lp and (q == "" or p.Name:lower():find(q, 1, true) or p.DisplayName:lower():find(q, 1, true)) then
					list[#list + 1] = p
					local d = distTo(p)
					local key = p.Name .. teamTag(p) .. (d and ("  ~" .. d .. "m") or "")
					entries[#entries + 1] = key
					entryToPlayer[key] = p
				end
			end
			table.sort(entries)
			Options.spectatePlayer.Values = entries
			pcall(function() Options.spectatePlayer:SetValues() end)
		end

		-- StreamingEnabled games pause gameplay ("please wait while the game content
		-- loads") when the camera sits in an un-streamed region. Spectating a far player
		-- moves the camera there, so force-stream that area; and force-stream YOUR OWN
		-- area on reset so you aren't left stuck in the pause after you stop spectating.
		local function streamAround(p)
			if not workspace.StreamingEnabled then return end
			local node = nodeOf(p)
			if node then task.spawn(function() pcall(function() lp:RequestStreamAroundAsync(node.Position) end) end) end
		end
		local function setSubject(p)
			local ch = p and p.Character
			local hum = ch and ch:FindFirstChildWhichIsA("Humanoid")
			-- Read the camera LIVE (Roblox swaps it on respawn; a captured ref goes stale).
			if hum then workspace.CurrentCamera.CameraSubject = hum; subject = p; streamAround(p) end
		end
		local function selfSubject()
			local hum = lp.Character and lp.Character:FindFirstChildWhichIsA("Humanoid")
			if hum then workspace.CurrentCamera.CameraSubject = hum end
			subject = nil; idx = 0; label:SetText("Spectating: self")
			streamAround(lp)
		end

		Options.spectateSearch:OnChanged(rebuild)
		Options.spectatePlayer:OnChanged(function()
			local key = Options.spectatePlayer.Value
			local p = key and entryToPlayer[key]
			if p then
				setSubject(p)
				idx = table.find(list, p) or idx
			end
		end)

		g:AddButton("Refresh List", rebuild):AddToolTip("Re-list players and re-snapshot their distances.")
		g:AddButton("Next Player", function()
			rebuild(); if #list == 0 then label:SetText("No other players"); return end
			idx = idx % #list + 1; setSubject(list[idx])
		end)
		g:AddButton("Previous Player", function()
			rebuild(); if #list == 0 then return end
			idx = (idx - 2) % #list + 1; setSubject(list[idx])
		end)
		g:AddButton("Reset to Self", selfSubject)

		-- Live readout: the spectated player's team + current distance (updates ~3/s).
		local lastUpd = 0
		ctx:Connect(RunService.Heartbeat, function()
			local now = tick(); if now - lastUpd < 0.3 then return end; lastUpd = now
			if subject then
				if subject.Parent then
					local d = distTo(subject)
					label:SetText("Spectating: " .. subject.Name .. teamTag(subject) .. (d and ("  " .. d .. "m") or ""))
				else
					selfSubject()  -- they left; snap back to self
				end
			end
		end)
		ctx:Connect(Players.PlayerRemoving, function(p) if subject == p then selfSubject() end end)
		ctx:Connect(Players.PlayerAdded, function() task.defer(rebuild) end)
		rebuild()
	end,
	unload = function()
		local lp = game:GetService("Players").LocalPlayer
		local hum = lp.Character and lp.Character:FindFirstChildWhichIsA("Humanoid")
		if hum then workspace.CurrentCamera.CameraSubject = hum end
	end,
}
