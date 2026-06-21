-- CryptsHBE plugin: Threat / Early-Warning (tab "Threat")
-- ============================================================================
-- A first-person awareness system: it warns you when another player is AIMING AT YOU
-- (their facing/look-vector points at you within a cone), gated by line-of-sight, and
-- prioritises threats BEHIND you / outside your camera FOV -- the ones you can't see.
--
-- Surfaces threats four ways (all opt-in):
--   * Screen-edge direction warning -- a red marker + line at the screen edge pointing
--     toward each unseen aimer, so you snap-turn the right way.
--   * Aim-alert flash -- a red vignette frame that pulses while someone has a bead on you.
--   * Aim-alert sound -- a beep on a new threat (set the SoundId).
--   * Auto-snap camera -- optionally snaps your view toward a new behind-you aimer
--     (cooldown), plus a "Snap to Threat" keybind for on-demand.
-- It also publishes Bridge.ThreatAimers = { [player]=true } so the CORE ESP off-screen
-- markers turn that specific player's marker bold red + blinking.
--
-- Pure CLIENT-side read + camera (no remotes, no hooks). Detection is read-only; the
-- camera snap is the only thing that touches your own view, and it's OFF by default.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = workspace
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE
local DrawingFallback = getgenv().DrawingFallback
local pluginCleanup = nil

local function aliveChar(plr)
	local char = plr.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if hum and hum.Health > 0 then return char, hum end
	return char  -- some custom rigs have no Humanoid; still usable for position/facing
end
-- the part that represents where a character is "looking" (gun direction).
-- Head includes pitch (aim up/down); falls back to the root for headless custom rigs.
local function facingPart(char)
	if not char then return nil end
	return char:FindFirstChild("Head")
		or char:FindFirstChild("HumanoidRootPart")
		or char:FindFirstChild("Torso2")
		or char:FindFirstChildWhichIsA("BasePart")
end

return {
	name = "Threat", tab = "Threat", requires = {},
	load = function(ctx)
		local function C(k) ctx:Control(k) end
		local snapToNearest   -- forward-declared: used by the keybind below, assigned later

		-- ---- detection controls ----
		local gDet = ctx:Groupbox("Threat Detection", "left")
		gDet:AddToggle("threatEnabled", { Text = "Enable Early-Warning", Default = false, Tooltip = "Warn when another player is aiming at you. Read-only detection (no hooks). (Default: OFF)" }); C("threatEnabled")
		gDet:AddSlider("threatConeAngle", { Text = "Aim cone (deg)", Min = 3, Max = 45, Default = 14, Rounding = 0, Tooltip = "How closely their aim must point at you to count as a threat. Smaller = only a tight bead on you; bigger = warns earlier / more often." }); C("threatConeAngle")
		gDet:AddSlider("threatRange", { Text = "Max range (studs)", Min = 0, Max = 3000, Default = 0, Rounding = 0, Tooltip = "Only consider aimers within this distance. 0 = unlimited." }); C("threatRange")
		gDet:AddToggle("threatLOS", { Text = "Require line-of-sight", Default = true, Tooltip = "Only warn if they can actually SEE you (clear raycast) -- cuts false alarms from players aiming through walls. (Default: ON)" }); C("threatLOS")
		gDet:AddToggle("threatBehindOnly", { Text = "Only warn for threats behind me", Default = false, Tooltip = "Only warn about aimers OUTSIDE your camera view (the ones you can't already see). Off = warn about all aimers, behind ones prioritised. (Default: OFF)" }); C("threatBehindOnly")
		local lblDet = gDet:AddLabel("Off.", true)

		-- ---- warning controls ----
		local gWarn = ctx:Groupbox("Warnings", "right")
		gWarn:AddToggle("threatEdgeWarn", { Text = "Screen-edge direction warning", Default = true, Tooltip = "Draw a red marker + line at the screen edge pointing toward each unseen aimer. (Default: ON)" }); C("threatEdgeWarn")
		gWarn:AddToggle("threatFlash", { Text = "Aim-alert flash (red vignette)", Default = true, Tooltip = "Pulse a red frame around the screen while someone has a bead on you (stronger if they're behind you / close). (Default: ON)" }); C("threatFlash")
		gWarn:AddToggle("threatSound", { Text = "Aim-alert sound", Default = false, Tooltip = "Beep on a NEW threat (cooldown'd). Set a valid SoundId below. (Default: OFF)" }); C("threatSound")
		gWarn:AddInput("threatSoundId", { Text = "Alert SoundId", Default = "rbxassetid://3398620867", Tooltip = "Asset id of the beep to play. If nothing plays, paste any short beep/alarm asset id." }); C("threatSoundId")
		gWarn:AddToggle("threatAutoSnap", { Text = "Auto-snap camera to aimer", Default = false, Tooltip = "When a NEW aimer appears BEHIND you, snap your view toward them (cooldown). Intrusive -- OFF by default; in PANIC. (Default: OFF)" }); C("threatAutoSnap")
		gWarn:AddSlider("threatSnapCooldown", { Text = "Auto-snap cooldown (s)", Min = 0.3, Max = 6, Default = 1.5, Rounding = 1, Tooltip = "Minimum time between auto-snaps so it doesn't fight your aim." }); C("threatSnapCooldown")
		local lblWarn = gWarn:AddLabel("No threats.", true)

		-- ---- snap-to-threat keybind (manual, on demand) ----
		if Bridge and Bridge.AddKeybind then
			pcall(function()
				Bridge:AddKeybind("threatSnap", "Snap to Threat", "H", "Hold", function(state)
					if state then snapToNearest() end
				end)
			end)
		end

		-- ---- drawing pools (GUI fallback) ----
		local EDGE = 12
		local edgeMarks, edgeLines = {}, {}
		for i = 1, EDGE do
			local m = ctx:Track(DrawingFallback.new("Square")); m.Filled = true; m.Visible = false
			local ln = ctx:Track(DrawingFallback.new("Line")); ln.Thickness = 2; ln.Visible = false
			edgeMarks[i] = m; edgeLines[i] = ln
		end
		-- vignette frame: 4 edge bars (top/bottom/left/right)
		local bars = {}
		for i = 1, 4 do local b = ctx:Track(DrawingFallback.new("Square")); b.Filled = true; b.Visible = false; bars[i] = b end
		local function hideAll()
			for i = 1, EDGE do edgeMarks[i].Visible = false; edgeLines[i].Visible = false end
			for i = 1, 4 do bars[i].Visible = false end
		end

		-- ---- alert sound (best-effort; PlayLocalSound) ----
		local snd = Instance.new("Sound"); snd.Volume = 1; pcall(function() snd.Parent = SoundService end)
		local lastSound = 0
		local function playAlert()
			if not (Toggles.threatSound and Toggles.threatSound.Value) then return end
			if tick() - lastSound < 0.5 then return end
			local id = (Options.threatSoundId and Options.threatSoundId.Value) or ""
			if id == "" then return end
			lastSound = tick()
			pcall(function()
				snd.SoundId = id
				if SoundService.PlayLocalSound then SoundService:PlayLocalSound(snd) else snd:Play() end
			end)
		end

		-- ---- camera snap state ----
		local snapTarget, snapUntil, lastSnap = nil, 0, 0
		function snapToNearest()
			local aim = Bridge.ThreatAimers
			local best, bd
			if aim then
				for _, info in pairs(aim) do
					if type(info) == "table" and info.pos then
						local d = info.dist or 0
						if not bd or d < bd then best, bd = info.pos, d end
					end
				end
			end
			if best then snapTarget = best; snapUntil = tick() + 0.18 end
		end

		local prevAimers = {}

		ctx:Connect(RunService.RenderStepped, function()
			-- camera snap runs even when warnings are hidden, but only while armed
			local cam = Workspace.CurrentCamera
			if snapTarget and cam and tick() < snapUntil then
				pcall(function() cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, snapTarget), 0.35) end)
			elseif snapTarget and tick() >= snapUntil then
				snapTarget = nil
			end

			if not (Toggles.threatEnabled and Toggles.threatEnabled.Value) then
				Bridge.ThreatAimers = nil; prevAimers = {}; hideAll()
				pcall(function() lblDet:SetText("Off.") end)
				return
			end
			if (Bridge and Bridge.Streamer and Bridge.Streamer.hideESP) or (Bridge and Bridge.MenuOpen) then hideAll(); return end
			if not cam then hideAll(); return end
			local myChar = aliveChar(lPlayer)
			local myHead = facingPart(myChar)
			if not myHead then Bridge.ThreatAimers = {}; hideAll(); return end

			local coneCos = math.cos(math.rad((Options.threatConeAngle and Options.threatConeAngle.Value) or 14))
			local maxR = (Options.threatRange and Options.threatRange.Value) or 0
			local needLOS = Toggles.threatLOS and Toggles.threatLOS.Value
			local behindOnly = Toggles.threatBehindOnly and Toggles.threatBehindOnly.Value
			local camPos = cam.CFrame.Position
			local camLook = cam.CFrame.LookVector
			local fovCos = math.cos(math.rad((cam.FieldOfView or 70) * 0.55))  -- a touch wider than half-FOV

			local aimers = {}
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= lPlayer then
					local char = aliveChar(plr)
					local fp = facingPart(char)
					if fp then
						local toMe = myHead.Position - fp.Position
						local dist = toMe.Magnitude
						if dist > 1 and (maxR <= 0 or dist <= maxR) then
							local aligned = fp.CFrame.LookVector:Dot(toMe.Unit)
							if aligned >= coneCos then               -- they're pointing at me
								local blocked = false
								if needLOS then
									local rp = RaycastParams.new()
									rp.FilterType = Enum.RaycastFilterType.Exclude
									rp.FilterDescendantsInstances = { char, myChar }
									local res = Workspace:Raycast(fp.Position, (myHead.Position - fp.Position), rp)
									blocked = res ~= nil
								end
								if not (needLOS and blocked) then
									local toThem = fp.Position - camPos
									local inView = toThem.Magnitude > 1 and (camLook:Dot(toThem.Unit) >= fovCos)
									local behind = not inView
									if not (behindOnly and not behind) then
										aimers[plr] = { pos = fp.Position, behind = behind, dist = dist }
									end
								end
							end
						end
					end
				end
			end
			Bridge.ThreatAimers = aimers   -- publish for the core ESP off-screen markers

			-- new-threat detection (for sound + auto-snap)
			local newBehind = nil
			local count, behindCount = 0, 0
			for plr, info in pairs(aimers) do
				count = count + 1
				if info.behind then behindCount = behindCount + 1 end
				if not prevAimers[plr] then
					if (not newBehind) or info.behind then newBehind = info end
				end
			end
			if count > 0 and next(prevAimers) == nil then playAlert() end           -- 0 -> some
			if newBehind and behindCount > 0 then playAlert() end
			-- auto-snap on a NEW behind-you aimer (cooldown)
			if Toggles.threatAutoSnap and Toggles.threatAutoSnap.Value and newBehind and newBehind.behind then
				if tick() - lastSnap >= ((Options.threatSnapCooldown and Options.threatSnapCooldown.Value) or 1.5) then
					lastSnap = tick(); snapTarget = newBehind.pos; snapUntil = tick() + 0.18
				end
			end
			prevAimers = aimers

			-- ---- render edge warnings ----
			local vp = cam.ViewportSize
			local center = Vector2.new(vp.X / 2, vp.Y / 2)
			local edgeR = math.min(vp.X, vp.Y) / 2 - 34
			local n = 0
			local edgeOn = Toggles.threatEdgeWarn and Toggles.threatEdgeWarn.Value
			local maxSev = 0
			for plr, info in pairs(aimers) do
				local ref = (maxR > 0 and maxR) or 300
				local sev = math.clamp(1 - info.dist / ref, 0, 1) * (info.behind and 1 or 0.55)
				if sev > maxSev then maxSev = sev end
				if edgeOn and n < EDGE then
					local sp, onScreen = cam:WorldToViewportPoint(info.pos)
					-- only draw the edge pointer for unseen aimers (off-screen or behind)
					if (not onScreen) or sp.Z <= 0 or info.behind then
						n = n + 1
						local v = Vector2.new(sp.X, sp.Y) - center
						if sp.Z <= 0 then v = -v end
						if v.Magnitude < 1 then v = Vector2.new(0, 1) end
						v = v.Unit
						local ep = center + v * edgeR
						local blink = 0.55 + 0.45 * math.abs(math.sin(tick() * 9))
						local sz = 12 + 10 * sev * blink
						local col = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(255, 210, 0), 1 - blink)
						local m = edgeMarks[n]
						m.Size = Vector2.new(sz, sz); m.Position = Vector2.new(ep.X - sz / 2, ep.Y - sz / 2)
						m.Color = col; m.Visible = true
						local ln = edgeLines[n]
						ln.From = center + v * (edgeR - 60); ln.To = ep; ln.Color = col; ln.Thickness = 2; ln.Visible = true
					end
				end
			end
			for i = n + 1, EDGE do edgeMarks[i].Visible = false; edgeLines[i].Visible = false end

			-- ---- vignette flash ----
			if (Toggles.threatFlash and Toggles.threatFlash.Value) and count > 0 then
				local pulse = 0.5 + 0.5 * math.abs(math.sin(tick() * 7))
				local thick = 6 + 16 * maxSev * pulse
				local col = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(255, 120, 0), 1 - maxSev)
				-- top, bottom, left, right
				bars[1].Position = Vector2.new(0, 0);            bars[1].Size = Vector2.new(vp.X, thick)
				bars[2].Position = Vector2.new(0, vp.Y - thick); bars[2].Size = Vector2.new(vp.X, thick)
				bars[3].Position = Vector2.new(0, 0);            bars[3].Size = Vector2.new(thick, vp.Y)
				bars[4].Position = Vector2.new(vp.X - thick, 0); bars[4].Size = Vector2.new(thick, vp.Y)
				for i = 1, 4 do bars[i].Color = col; bars[i].Visible = true end
			else
				for i = 1, 4 do bars[i].Visible = false end
			end

			pcall(function() lblDet:SetText(("Aimers: %d (%d behind)"):format(count, behindCount)) end)
			pcall(function() lblWarn:SetText(count > 0 and ("THREAT x%d"):format(count) or "No threats.") end)
		end)

		pluginCleanup = function()
			Bridge.ThreatAimers = nil
			pcall(hideAll)
			pcall(function() if snd then snd:Destroy() end end)
			pcall(function() if Bridge and Bridge.ClearKeybind then Bridge:ClearKeybind("threatSnap") end end)
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
