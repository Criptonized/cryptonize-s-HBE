-- CryptsHBE plugin: Engineer  (Prodier shovel build/destroy helper)
-- ============================================================================
-- The shovel (engineer + other classes) builds/destroys with Work and Destroy modes; each
-- swing adds/removes progress and buildings have a Health/progress value (e.g. the Dugout
-- at 89.58%). This helps you finish fast:
--   * Auto-Swing  -- rapid-clicks so Work/Destroy swings fire automatically (bind a key to
--     hold-swing). Universal: works wherever a swing is a click.
--   * Instant Build -- finds the building under your crosshair (or hold-picked) and writes
--     its progress/Health to max each tick, with READ-BACK so you know if the server keeps
--     it. ("It's all just changing values" -- if Health IS the build progress, this completes it.)
--   * War-Year bypass -- finds the in-game war-year value and lets you set it, to unlock
--     builds gated behind a later year. Best-effort + read-back.
--
-- NOTE: the value path is best-effort. For a guaranteed instant-build on a server-validated
-- game, capture the build remote with the Remote Sniffer during one Work swing and we can
-- replay it directly. The readouts tell you which case you're in.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

local function isNum(d)
	return d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue")
end
local BUILD_WORDS = { "buildprogress", "progress", "buildpercent", "percent", "completion", "built", "construct", "buildhealth", "health", "stage" }
local YEAR_WORDS = { "waryear", "gameyear", "currentyear", "year", "era", "date" }
local function nameHas(n, words) n = tostring(n):lower() for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end return false end

-- find the build/progress value on a model + its max target
local function buildValue(model)
	if not model then return nil end
	local best, bestMax
	pcall(function()
		for _, d in ipairs(model:GetDescendants()) do
			if isNum(d) and nameHas(d.Name, BUILD_WORDS) then
				-- prefer a Max sibling; else MaxValue (constrained); else 100
				local mx
				local sib = d.Parent and (d.Parent:FindFirstChild("Max" .. d.Name) or d.Parent:FindFirstChild("MaxHealth"))
				if sib and isNum(sib) then mx = sib.Value end
				if not mx then pcall(function() if d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue") then mx = d.MaxValue end end) end
				if not mx then mx = (d.Name:lower():find("percent") or d.Name:lower():find("progress")) and 100 or 100000 end
				-- pick the one furthest from done (most useful) or the first
				if not best then best, bestMax = d, mx end
			end
		end
	end)
	if best then return { v = best, max = bestMax, path = best:GetFullName() } end
	return nil
end

return {
	name = "Engineer", tab = "Engineer", requires = {},
	load = function(ctx)
		local Bridge = getgenv().CryptsHBE
		local function C(k) ctx:Control(k) end

		local g = ctx:Groupbox("Build / Destroy", "left")
		g:AddToggle("engAutoSwing", { Text = "Auto-Swing", Default = false, Tooltip = "Rapid-clicks so Work/Destroy swings fire automatically. Bind the key to hold-swing. (Default: OFF)" })
			:AddKeyPicker("engAutoSwingKey", { Default = "G", Mode = "Hold", Text = "Auto-Swing", SyncToggleState = true, Tooltip = "Hold to auto-swing the shovel (Work or Destroy mode)." })
		C("engAutoSwing")
		g:AddSlider("engSwingRPM", { Text = "Swings / min", Min = 60, Max = 1200, Default = 400, Rounding = 0, Tooltip = "How fast Auto-Swing clicks." }); C("engSwingRPM")
		g:AddToggle("engInstantBuild", { Text = "Instant Build (crosshair)", Default = false, Tooltip = "Find the building under your crosshair and hold its progress/Health at max. Read-back shows if it sticks. (Default: OFF)" }); C("engInstantBuild")
		g:AddButton("Pick Building (hold)", function()
			if not (Bridge and Bridge.StartHoldPick) then Library:Notify("Hold-pick unavailable"); return end
			Bridge:StartHoldPick({ color = Color3.fromRGB(255, 200, 80), onPick = function(part)
				local m = part and part:FindFirstAncestorWhichIsA("Model")
				getgenv().CryptsHBE._engPicked = m
				Library:Notify(m and ("Picked building: " .. m.Name) or "No model")
			end })
		end):AddToolTip("Aim at a building + hold click to target it for Instant Build (instead of the crosshair one).")

		local gYear = ctx:Groupbox("War-Year Bypass (best-effort)", "left")
		gYear:AddInput("engYear", { Text = "Set Year", Default = "1945", Numeric = true, Finished = true, Tooltip = "Value to write to the detected war-year value(s)." }); C("engYear")
		gYear:AddButton("Find + Set War Year", function()
			local target = tonumber(Options.engYear.Value)
			if not target then Library:Notify("Year isn't a number"); return end
			local hits = 0
			for _, root in ipairs({ Workspace, ReplicatedStorage, lPlayer }) do
				pcall(function()
					local n = 0
					for _, d in ipairs(root:GetDescendants()) do
						n = n + 1; if n > 20000 then break end
						if isNum(d) and nameHas(d.Name, YEAR_WORDS) then pcall(function() d.Value = target; hits = hits + 1 end) end
					end
				end)
			end
			Library:Notify("War-year: wrote " .. hits .. " value(s) -> " .. target)
		end):AddToolTip("Scan Workspace/ReplicatedStorage/Player for a year value and set it (to unlock year-gated builds).")

		local gInfo = ctx:Groupbox("Readout", "right")
		local lblTarget = gInfo:AddLabel("Target: -", true)
		local lblBuild = gInfo:AddLabel("Build: -", true)

		-- Auto-Swing loop
		local lastSwing = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.engAutoSwing and Toggles.engAutoSwing.Value) then return end
			local rpm = (Options.engSwingRPM and Options.engSwingRPM.Value) or 400
			local now = tick(); if now - lastSwing < 60 / math.max(60, rpm) then return end; lastSwing = now
			pcall(function() if mouse1click then mouse1click() elseif mouse1press and mouse1release then mouse1press(); mouse1release() end end)
		end)

		-- Instant Build loop (crosshair raycast or picked model) + read-back
		local cur, lastResolve, lastApply = nil, 0, 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.engInstantBuild and Toggles.engInstantBuild.Value) then
				pcall(function() lblTarget:SetText("Target: (instant build off)"); lblBuild:SetText("Build: -") end)
				return
			end
			local now = tick()
			if now - lastResolve > 0.3 then
				lastResolve = now
				local model = getgenv().CryptsHBE._engPicked
				if not (model and model.Parent) then
					-- crosshair raycast
					local cam = Workspace.CurrentCamera
					local ray = cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
					local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
					pcall(function() rp.FilterDescendantsInstances = { lPlayer.Character } end)
					local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, rp)
					model = hit and hit.Instance and hit.Instance:FindFirstAncestorWhichIsA("Model") or nil
				end
				cur = buildValue(model)
				pcall(function() lblTarget:SetText("Target: " .. (model and model.Name or "(aim at a building)")) end)
			end
			-- Throttle the WRITE to ~5Hz. Writing the build/Health value every frame was the
			-- lag (and on a server-validated build it just gets reverted -- the read-back says so,
			-- and that means value-write can't bypass it; Auto-Swing is the only client lever).
			if cur and cur.v and cur.v.Parent then
				if now - lastApply > 0.2 then
					lastApply = now
					local before = cur.v.Value
					pcall(function() cur.v.Value = cur.max end)
					local after = cur.v.Value
					pcall(function()
						local verdict = (math.abs(after - cur.max) < 0.5) and "stuck" or (math.abs(after - before) < 0.5 and "REVERTED -- server-side build (use Auto-Swing)" or ("-> " .. tostring(after)))
						lblBuild:SetText(("Build: %s = %s / %s  [%s]"):format(cur.v.Name, tostring(after), tostring(cur.max), verdict))
					end)
				end
			else
				pcall(function() lblBuild:SetText("Build: no progress/Health value on target") end)
			end
		end)

		-- mirror Auto-Swing into the central Keybinds tab too
		pcall(function()
			if Bridge.AddKeybind then
				Bridge:AddKeybind("engAutoSwingCentral", "Engineer Auto-Swing", "G", "Hold", function(state)
					if Toggles.engAutoSwing then Toggles.engAutoSwing:SetValue(state and true or false) end
				end)
			end
		end)

		local howG = ctx:Groupbox("How to Use", "right")
		howG:AddLabel(
			"For the Prodier shovel (engineer + other\n" ..
			"classes). Work = build, Destroy = remove.\n\n" ..
			"FAST BUILD/DESTROY: hold the Auto-Swing\n" ..
			"key (default G) to swing rapidly, OR turn\n" ..
			"on Instant Build and aim at the structure\n" ..
			"-- it maxes the build progress/Health.\n" ..
			"Watch Build read-back: stuck = done,\n" ..
			"REVERTED = server-validated (then we need\n" ..
			"the build remote -- Sniff a Work swing).\n\n" ..
			"YEAR-GATE: type a later year + 'Find + Set\n" ..
			"War Year' to unlock builds locked behind\n" ..
			"the war year (best-effort).",
			true)

		pluginCleanup = function()
			pcall(function() if Bridge.ClearKeybind then Bridge:ClearKeybind("engAutoSwingCentral") end end)
			if getgenv().CryptsHBE then getgenv().CryptsHBE._engPicked = nil end
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
