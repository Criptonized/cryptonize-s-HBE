-- CryptsHBE plugin: Bleeding Blades toolkit (tab "Blades")
-- ============================================================================
-- Game-specific tools for Bleeding Blades (7006496598), built from the S4 dumps.
-- The combat system lives in ReplicatedStorage.Combat.* with named remotes:
--   PHit (melee hit), CreateProjectile (arrows/bolts), Mount/MountCombat/MountSmash
--   (horses), WaistRotation (directional aim), Kick, ItemThrow, Feedback(RF), ...
-- Melee = NO touch connections (remote/raycast, server-validated) -> HBE is harmful
-- here; the lever is the PHit remote. Currency/economy: none. Directional combat UI:
-- PlayerGui.DirectionUI (the left/down/right/up panel) -> needed for auto-parry.
-- HONEST: hits/arrows go through PHit/CreateProjectile -> replayable ONLY if the
-- server doesn't re-validate; the "Server:" messages (Invalid Attack / Fall damage)
-- are the server-side validator talking. Capture PHit/CreateProjectile args with the
-- RemoteSniffer (filter OFF) to wire the bypass precisely.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = workspace
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE
local pluginCleanup = nil

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
local function writeOut(fname, lines)
	if Bridge and Bridge.SessionName then pcall(function() fname = Bridge:SessionName(fname) end) end
	pcall(function()
		if makefolder and not (isfolder and isfolder("CryptsHBE")) then makefolder("CryptsHBE") end
		if writefile then writefile("CryptsHBE/" .. fname, table.concat(lines, "\n")) end
	end)
	return fname
end

return {
	name = "BleedingBlades", tab = "Blades", requires = {},
	load = function(ctx)
		local function C(k) ctx:Control(k) end
		local mouse = lPlayer:GetMouse()

		-- ===== Model -> Remote picker =====================================
		-- Pick ANY model (humanoid / horse / object) under your cursor and dump its
		-- structure + the shared Combat remotes -- for spectating/observing battles.
		local gPick = ctx:Groupbox("Model Picker", "left")
		local lblPick = gPick:AddLabel("Picked: none. Aim at a model, press the\nPick key (default K), then Dump.", true)
		local pickedModel = nil
		local function doPick()
			local t = mouse.Target
			local m = t and t:FindFirstAncestorWhichIsA("Model")
			if m then
				pickedModel = m
				local hum = m:FindFirstChildWhichIsA("Humanoid")
				pcall(function() lblPick:SetText("Picked: " .. m.Name .. (hum and " (humanoid)" or "") .. "\n@ " .. m:GetFullName()) end)
				Library:Notify("Picked: " .. m.Name)
			else
				Library:Notify("Aim at a model first")
			end
		end
		if Bridge and Bridge.AddKeybind then
			pcall(function() Bridge:AddKeybind("bbPick", "BB Pick Model", "K", "Toggle", function() doPick() end) end)
		end
		gPick:AddButton("Pick Model Under Cursor", doPick):AddToolTip("Selects whatever model your mouse is over (any humanoid/horse/object).")
		gPick:AddButton("Dump Picked -> Remotes", function()
			if not (pickedModel and pickedModel.Parent) then Library:Notify("Pick a model first"); return end
			local lines = { "=== Picked Model Dump ===", "Model: " .. pickedModel.Name, "Path: " .. pickedModel:GetFullName(), "" }
			lines[#lines + 1] = "-- descendants (parts/values/remotes) --"
			local n = 0
			pcall(function()
				for _, d in ipairs(pickedModel:GetDescendants()) do
					n = n + 1; if n > 400 then break end
					local extra = ""
					if d:IsA("ValueBase") then extra = " = " .. tostring(d.Value) end
					if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then extra = "  <-- REMOTE" end
					lines[#lines + 1] = ("  %s '%s'%s"):format(d.ClassName, d.Name, extra)
				end
			end)
			lines[#lines + 1] = ""
			lines[#lines + 1] = "-- shared Combat remotes (act on any target) --"
			pcall(function()
				local combat = RS:FindFirstChild("Combat")
				if combat then for _, d in ipairs(combat:GetChildren()) do
					if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then lines[#lines + 1] = "  " .. d.ClassName .. " '" .. d.Name .. "'" end
				end end
			end)
			local fn = writeOut("picked_model_" .. tostring(game.PlaceId) .. ".txt", lines)
			Library:Notify("Dumped " .. pickedModel.Name .. " -> CryptsHBE/" .. fn)
		end):AddToolTip("Writes the picked model's structure + the game's Combat remotes to a file (so you can see what acts on it).")

		-- ===== Subtle walk speed =========================================
		local gMove = ctx:Groupbox("Movement", "left")
		gMove:AddToggle("bbWalkEnabled", { Text = "Walk Speed", Default = false, Tooltip = "Hold your Humanoid.WalkSpeed at the value below. Keep it SUBTLE -- the per-player\nHeightDetect scripts may flag big changes. (Default: OFF)" }); C("bbWalkEnabled")
		gMove:AddSlider("bbWalkSpeed", { Text = "Speed", Min = 16, Max = 32, Default = 19, Rounding = 0, Tooltip = "Base is ~16. A small bump (18-20) is the safe range." }); C("bbWalkSpeed")
		local origWalk = nil
		Toggles.bbWalkEnabled:OnChanged(function()
			local hum = lPlayer.Character and lPlayer.Character:FindFirstChildWhichIsA("Humanoid")
			if Toggles.bbWalkEnabled.Value then
				if hum then origWalk = origWalk or hum.WalkSpeed end
			else
				if hum and origWalk then pcall(function() hum.WalkSpeed = origWalk end) end
				origWalk = nil
			end
		end)
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.bbWalkEnabled and Toggles.bbWalkEnabled.Value) then return end
			local hum = lPlayer.Character and lPlayer.Character:FindFirstChildWhichIsA("Humanoid")
			if hum then
				origWalk = origWalk or hum.WalkSpeed
				pcall(function() hum.WalkSpeed = Options.bbWalkSpeed.Value end)
			end
		end)

		-- ===== Combat remote fire (PHit / CreateProjectile / Mount / ...) ==
		local gRem = ctx:Groupbox("Combat Remotes", "right")
		local remMap = {}
		gRem:AddDropdown("bbCombatRemote", { Text = "Remote", Values = {}, Multi = false, AllowNull = true, Tooltip = "A remote from ReplicatedStorage.Combat. Sniff its real args first (RemoteSniffer, filter OFF)." }); C("bbCombatRemote")
		gRem:AddInput("bbCombatArgs", { Text = "Args (comma)", Default = "", Tooltip = "Comma-separated args (numbers/true/false/strings). Paste the sniffed payload." }); C("bbCombatArgs")
		local lblRem = gRem:AddLabel("Scan to list Combat remotes.", true)
		local function scanCombat()
			remMap = {}; local names = {}
			pcall(function()
				local combat = RS:FindFirstChild("Combat")
				if combat then for _, d in ipairs(combat:GetChildren()) do
					if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
						remMap[d.Name] = d; names[#names + 1] = d.Name
					end
				end end
			end)
			table.sort(names)
			Options.bbCombatRemote.Values = names; pcall(function() Options.bbCombatRemote:SetValues() end)
			pcall(function() lblRem:SetText("Combat remotes: " .. #names) end)
			Library:Notify("Combat remotes: " .. #names)
		end
		gRem:AddButton("Scan Combat Remotes", scanCombat)
		gRem:AddButton("Fire Selected", function()
			local r = remMap[Options.bbCombatRemote.Value]
			if not r then Library:Notify("Pick a remote (Scan first)"); return end
			local args = parseArgs(Options.bbCombatArgs.Value or "")
			pcall(function()
				if r:IsA("RemoteEvent") then r:FireServer(table.unpack(args))
				elseif r:IsA("RemoteFunction") then r:InvokeServer(table.unpack(args)) end
			end)
			Library:Notify("Fired " .. r.Name)
		end):AddToolTip("Fires PHit (a hit) / CreateProjectile (an arrow) / Mount etc. with your args -- replays a captured combat call. Server may re-validate.")

		-- ===== Server message monitor ====================================
		-- The "Server:" messages (Invalid Attack / Fall damage / kills) come from the
		-- server through messaging remotes. Listen (read-only OnClientEvent) and surface
		-- them so you SEE when the server flags you -- the central validator the user noticed.
		local gSrv = ctx:Groupbox("Server Monitor", "right")
		gSrv:AddToggle("bbServerMonitor", { Text = "Watch Server Messages", Default = false, Tooltip = "Read-only: listens to the game's message remotes and shows server text\n(Invalid Attack / Fall damage / kills). No hook. (Default: OFF)" }); C("bbServerMonitor")
		local lblSrv = gSrv:AddLabel("Server: -", true)
		local srvLog = {}
		local function pushSrv(txt)
			txt = tostring(txt)
			table.insert(srvLog, 1, txt)
			while #srvLog > 5 do table.remove(srvLog) end
			pcall(function() lblSrv:SetText("Server msgs:\n" .. table.concat(srvLog, "\n")) end)
		end
		local function argText(...)
			local out = {}
			for _, a in ipairs({ ... }) do if type(a) == "string" or type(a) == "number" then out[#out + 1] = tostring(a) end end
			return table.concat(out, " ")
		end
		-- Hook OnClientEvent on the likely message remotes (Game.* + Combat.Feedback-style).
		pcall(function()
			local watch = {}
			local g = RS:FindFirstChild("Game")
			if g then for _, n in ipairs({ "MessageSend", "Announcer", "Signal", "Voting" }) do
				local r = g:FindFirstChild(n); if r and r:IsA("RemoteEvent") then watch[#watch + 1] = r end
			end end
			local combat = RS:FindFirstChild("Combat")
			if combat then for _, n in ipairs({ "Doll", "Replicate", "Playsound" }) do
				local r = combat:FindFirstChild(n); if r and r:IsA("RemoteEvent") then watch[#watch + 1] = r end
			end end
			for _, r in ipairs(watch) do
				ctx:Connect(r.OnClientEvent, function(...)
					if not (Toggles.bbServerMonitor and Toggles.bbServerMonitor.Value) then return end
					local s = argText(...)
					if s ~= "" and (s:lower():find("server") or s:lower():find("damage") or s:lower():find("invalid") or s:lower():find("kill") or s:lower():find("fall") or s:lower():find("block")) then
						pushSrv("[" .. r.Name .. "] " .. s:sub(1, 60))
					end
				end)
			end
		end)

		-- ===== Auto-parry (experimental) =================================
		-- Reads PlayerGui.DirectionUI (the left/down/right/up panel). Dump it to learn the
		-- exact structure, then Auto-Block holds MB2 (block) while a telegraph is active.
		-- EXPERIMENTAL until we map DirectionUI; OFF by default. Uses VirtualInputManager.
		local gPar = ctx:Groupbox("Auto-Parry (experimental)", "right")
		local lblDir = gPar:AddLabel("DirectionUI: dump it during a fight.", true)
		local function directionUI()
			local pg = lPlayer:FindFirstChildOfClass("PlayerGui")
			return pg and pg:FindFirstChild("DirectionUI")
		end
		gPar:AddButton("Dump DirectionUI", function()
			local di = directionUI()
			if not di then Library:Notify("No DirectionUI (be alive/in a fight)"); return end
			local lines = { "=== DirectionUI dump ===", "PlaceId: " .. tostring(game.PlaceId), "" }
			pcall(function()
				for _, d in ipairs(di:GetDescendants()) do
					local extra = ""
					if d:IsA("GuiObject") then extra = " Visible=" .. tostring(d.Visible) end
					if d:IsA("TextLabel") or d:IsA("TextButton") then extra = extra .. " Text='" .. tostring(d.Text) .. "'" end
					if d:IsA("ImageLabel") or d:IsA("ImageButton") then extra = extra .. " Image=" .. tostring(d.Image) end
					if d:IsA("ValueBase") then extra = extra .. " Value=" .. tostring(d.Value) end
					lines[#lines + 1] = ("  %s '%s'%s"):format(d.ClassName, d.Name, extra)
				end
			end)
			local fn = writeOut("directionui_" .. tostring(game.PlaceId) .. ".txt", lines)
			Library:Notify("DirectionUI -> CryptsHBE/" .. fn .. " (send it to wire auto-parry)")
		end):AddToolTip("Dumps the directional panel's structure + which elements are visible, so the auto-block can be wired to the real attack-direction indicator.")
		gPar:AddToggle("bbAutoBlock", { Text = "Auto-Block (MB2 on telegraph)", Default = false, Tooltip = "EXPERIMENTAL: holds MB2 (block) while a DirectionUI telegraph is showing.\nBest-effort until DirectionUI is mapped -- dump it + send so this can be exact. (Default: OFF)" }); C("bbAutoBlock")
		local VIM = nil
		pcall(function() VIM = game:GetService("VirtualInputManager") end)
		local blockHeld = false
		local TELE_W = { "in", "incoming", "attack", "warn", "alert", "indicator", "arrow", "parry", "block", "direction" }
		local function telegraphActive()
			local di = directionUI()
			if not di then return false end
			local active = false
			pcall(function()
				for _, d in ipairs(di:GetDescendants()) do
					if (d:IsA("ImageLabel") or d:IsA("Frame") or d:IsA("ImageButton")) and d.Visible then
						local n = d.Name:lower()
						for _, w in ipairs(TELE_W) do if n:find(w, 1, true) then active = true; break end end
					end
					if active then break end
				end
			end)
			return active
		end
		local function setBlock(down)
			if not VIM then return end
			pcall(function()
				local vp = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 600)
				VIM:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 1, down, game, 0)   -- button 1 = MB2 (right)
			end)
		end
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.bbAutoBlock and Toggles.bbAutoBlock.Value) then
				if blockHeld then setBlock(false); blockHeld = false end
				return
			end
			local want = telegraphActive()
			if want and not blockHeld then setBlock(true); blockHeld = true
			elseif (not want) and blockHeld then setBlock(false); blockHeld = false end
		end)
		-- live readout of currently-visible DirectionUI elements (to correlate with attacks)
		local lastDir = 0
		ctx:Connect(RunService.Heartbeat, function()
			local now = tick(); if now - lastDir < 0.3 then return end; lastDir = now
			local di = directionUI()
			if not di then pcall(function() lblDir:SetText("DirectionUI: not present right now") end); return end
			local vis = {}
			pcall(function()
				for _, d in ipairs(di:GetDescendants()) do
					if d:IsA("GuiObject") and d.Visible and d.Name ~= "DirectionUI" then vis[#vis + 1] = d.Name end
					if #vis >= 6 then break end
				end
			end)
			pcall(function() lblDir:SetText("DirectionUI visible: " .. (#vis > 0 and table.concat(vis, ", ") or "(none)")) end)
		end)

		scanCombat()

		pluginCleanup = function()
			pcall(function() if blockHeld then setBlock(false) end end)
			pcall(function()
				local hum = lPlayer.Character and lPlayer.Character:FindFirstChildWhichIsA("Humanoid")
				if hum and origWalk then hum.WalkSpeed = origWalk end
			end)
			pcall(function() if Bridge and Bridge.ClearKeybind then Bridge:ClearKeybind("bbPick") end end)
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
