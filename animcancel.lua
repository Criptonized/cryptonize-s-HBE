-- CryptsHBE plugin: AnimCancel (tab "Anim")
-- Cancel or speed up FIRING / RELOAD / action animations so the per-shot animation
-- stops gating your rate of fire. The honest mechanism (read this):
--   * A weapon/emplacement plays an action animation each shot. If the LOCAL script
--     waits for that track (track.Stopped:Wait() / a debounce = the animation length),
--     stopping or speeding the track unlocks the next shot SOONER -> faster fire.   [WINS]
--   * If the script uses a FIXED task.wait(n) unrelated to the track, cancelling the
--     animation removes the visual but NOT the wait -> no rate change.              [NO HELP]
--   * If the SERVER caps the rate (ServerLastShotTime / LastShotServer -- Pordier's
--     artillery AND its bolt gun both have one), nothing client-side wins.          [SERVER WALL]
-- So this is the client lever for case 1. It is DIRECT API (GetPlayingAnimationTracks
-- + Stop/AdjustSpeed) -- NOT a metamethod hook -- so it stays detection-safe by the
-- core's rules. Confirm it landed via your weapon's own fire-rate / the Artillery
-- plugin's "Accepted" readout, not just the visual.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE
local pluginCleanup = nil

local WATCH_FILE = "CryptsHBE/anim_watch_" .. tostring(game.PlaceId) .. ".json"
-- Default action-animation keywords (matched as substrings of the track NAME). Reload
-- is included on purpose (speeds reloads when client-gated). "equip" is left OUT so we
-- don't fight tool-equipping.
local DEFAULT_KEYWORDS = "shoot,fire,attack,swing,slash,bolt,reload,cycle,load,rechamber,pump,stab,thrust,draw,nock,recoil,blast"
-- Locomotion / passive anims that "All but movement" mode must never touch.
local LOCO = { "idle", "walk", "run", "jump", "fall", "climb", "swim", "sit", "land", "crouch", "prone", "sprint", "stand", "mood", "dance", "emote" }

-- module state
local watched = {}                         -- [AnimationId]=true (learned action anims)
local cancelledThisSec, lastPerSec = 0, 0
local secStart = tick()
local lastAction = "-"
local learning, learnUntil, learnedCount = false, 0, 0
local learnBaseline = {}

local function kwList()
	local raw = (Options.animKeywords and Options.animKeywords.Value) or DEFAULT_KEYWORDS
	local t = {}
	for w in tostring(raw):gmatch("[^,]+") do
		w = w:gsub("%s+", ""):lower()
		if #w > 0 then t[#t + 1] = w end
	end
	if #t == 0 then t = { "shoot", "fire", "attack", "reload" } end
	return t
end

local function saveWatched()
	pcall(function()
		if makefolder and not (isfolder and isfolder("CryptsHBE")) then makefolder("CryptsHBE") end
		if writefile then
			local arr = {}
			for id in pairs(watched) do arr[#arr + 1] = id end
			writefile(WATCH_FILE, HttpService:JSONEncode(arr))
		end
	end)
end

local function loadWatched()
	pcall(function()
		if isfile and readfile and isfile(WATCH_FILE) then
			local arr = HttpService:JSONDecode(readfile(WATCH_FILE))
			if type(arr) == "table" then for _, id in ipairs(arr) do watched[tostring(id)] = true end end
		end
	end)
end

local function countWatched()
	local n = 0; for _ in pairs(watched) do n = n + 1 end; return n
end

-- Every Animator that could be playing the shot animation: you, your held tool, and
-- (when seated) the emplacement/vehicle model you're in -- artillery plays its fire
-- animation on the emplacement, not on your character.
local function collectAnimators()
	local list, seen = {}, {}
	local function addFrom(inst)
		if not inst then return end
		pcall(function()
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("Animator") and not seen[d] then seen[d] = true; list[#list + 1] = d end
			end
		end)
	end
	local char = lPlayer.Character
	addFrom(char)
	if char then
		local tool = char:FindFirstChildWhichIsA("Tool"); if tool then addFrom(tool) end
		local hum = char:FindFirstChildWhichIsA("Humanoid")
		if hum and hum.SeatPart then
			local m = hum.SeatPart:FindFirstAncestorWhichIsA("Model"); if m then addFrom(m) end
		end
	end
	return list
end

local function trackId(track)
	local id = ""
	pcall(function() id = (track.Animation and track.Animation.AnimationId) or "" end)
	return id
end

local function matchTrack(track)
	local id = trackId(track)
	if watched[id] then return true end
	local name = tostring(track.Name or ""):lower()
	local filter = (Options.animFilter and Options.animFilter.Value) or "Keywords"
	if filter == "Watched only" then
		return false
	elseif filter == "All but movement" then
		for _, w in ipairs(LOCO) do if name:find(w, 1, true) then return false end end
		return true
	else -- Keywords
		for _, w in ipairs(kwList()) do if name:find(w, 1, true) then return true end end
		return false
	end
end

local function applyTo(track)
	if not matchTrack(track) then return end
	local mode = (Options.animMode and Options.animMode.Value) or "Cancel (stop)"
	if mode == "Speed-up" then
		pcall(function() track:AdjustSpeed((Options.animSpeed and Options.animSpeed.Value) or 16) end)
	else
		pcall(function() track:Stop(0) end)
	end
	cancelledThisSec = cancelledThisSec + 1
	local nm = tostring(track.Name or "")
	lastAction = (nm ~= "" and nm) or trackId(track)
end

local function noteLearn(track)
	if not learning then return end
	local id = trackId(track)
	if id ~= "" and not learnBaseline[id] and not watched[id] then
		watched[id] = true; learnedCount = learnedCount + 1
	end
end

return {
	name = "AnimCancel", tab = "Anim", requires = {},
	load = function(ctx)
		loadWatched()
		local g = ctx:Groupbox("Animation Cancel", "left")
		g:AddLabel("Stops/speeds the per-shot animation so it\nstops gating your fire rate. Client lever only\n-- confirm via your weapon's actual rate.", true)
		g:AddToggle("animCancelEnabled", { Text = "Enable", Default = false, Tooltip = "Cancel/speed matching animations every frame. Watch your weapon's REAL fire rate (or the Artillery 'Accepted' readout) to confirm it actually unlocked faster shots. (Default: OFF)" }); ctx:Control("animCancelEnabled")
		g:AddDropdown("animMode", { Text = "Mode", AllowNull = false, Multi = false, Values = { "Cancel (stop)", "Speed-up" }, Default = "Cancel (stop)", Tooltip = "Cancel = Stop() the track instantly (best when the gun waits on the track).\nSpeed-up = AdjustSpeed() so it finishes fast (gentler, less obvious)." }); ctx:Control("animMode")
		g:AddLabel("WARNING: 'Cancel (stop)' can BRICK state-machine\nmelee (sword combat: stuck, can't swing, until you die).\nUse 'Speed-up' for melee; Cancel suits guns/bows.", true)
		g:AddSlider("animSpeed", { Text = "Speed-up x", Min = 2, Max = 50, Default = 16, Rounding = 0, Tooltip = "Multiplier for Speed-up mode." }); ctx:Control("animSpeed")
		g:AddDropdown("animFilter", { Text = "Match", AllowNull = false, Multi = false, Values = { "Keywords", "Watched only", "All but movement" }, Default = "Keywords", Tooltip = "Keywords = match the track name against the list below (+ any Learned ids).\nWatched only = ONLY the ids you Learned (surgical -- safest).\nAll but movement = everything except idle/walk/run/jump etc. (aggressive)." }); ctx:Control("animFilter")
		g:AddInput("animKeywords", { Text = "Keywords", Default = DEFAULT_KEYWORDS, Finished = true, Tooltip = "Comma-separated substrings matched against the animation NAME." }); ctx:Control("animKeywords")

		local g2 = ctx:Groupbox("Learn / Scan", "right")
		local lbl = g2:AddLabel("Off.", true)
		g2:AddButton("Learn Action (fire now)", function()
			learnBaseline = {}
			for _, an in ipairs(collectAnimators()) do
				pcall(function() for _, t in ipairs(an:GetPlayingAnimationTracks()) do learnBaseline[trackId(t)] = true end end)
			end
			learnedCount = 0; learning = true; learnUntil = tick() + 3.5
			Library:Notify("Learning -- FIRE your weapon now (3.5s)")
		end):AddToolTip("Snapshots what's playing, then for 3.5s captures any NEW animation that starts -- fire once and it learns the shot/reload anim ids into Watched.")
		g2:AddButton("Clear Watched", function()
			watched = {}; saveWatched(); Library:Notify("Cleared learned animations")
		end)
		g2:AddButton("Scan Playing Tracks", function()
			local lines = { "=== Animation Scan ===", "PlaceId: " .. tostring(game.PlaceId), "" }
			local n = 0
			for _, an in ipairs(collectAnimators()) do
				pcall(function()
					lines[#lines + 1] = "Animator @ " .. an:GetFullName()
					for _, t in ipairs(an:GetPlayingAnimationTracks()) do
						n = n + 1
						lines[#lines + 1] = ("  %s  id=%s  len=%.2f  speed=%.2f"):format(tostring(t.Name), trackId(t), t.Length or 0, t.Speed or 0)
					end
				end)
			end
			local fname = "anim_scan_" .. tostring(game.PlaceId) .. ".txt"
			if Bridge and Bridge.SessionName then pcall(function() fname = Bridge:SessionName(fname) end) end
			pcall(function()
				if makefolder and not (isfolder and isfolder("CryptsHBE")) then makefolder("CryptsHBE") end
				if writefile then writefile("CryptsHBE/" .. fname, table.concat(lines, "\n")) end
			end)
			Library:Notify(n .. " tracks playing -> CryptsHBE/" .. fname)
		end):AddToolTip("Writes every animation currently playing (name + id + length) to a file so you can read the exact ids to add to Keywords/Watched.")

		-- Single driver: reset the per-second counter, end a learn window, sweep + apply.
		local lastSweep, lastLbl = 0, 0
		ctx:Connect(RunService.Heartbeat, function()
			local now = tick()
			if now - secStart >= 1 then secStart = now; lastPerSec = cancelledThisSec; cancelledThisSec = 0 end
			if learning and now > learnUntil then
				learning = false; saveWatched()
				Library:Notify("Learned " .. learnedCount .. " action anim(s) -- total " .. countWatched())
			end
			local active = Toggles.animCancelEnabled and Toggles.animCancelEnabled.Value
			if (active or learning) and (now - lastSweep >= 0.03) then
				lastSweep = now
				for _, an in ipairs(collectAnimators()) do
					pcall(function()
						for _, t in ipairs(an:GetPlayingAnimationTracks()) do
							if learning then noteLearn(t) end
							if active then applyTo(t) end
						end
					end)
				end
			end
			if now - lastLbl >= 0.25 then
				lastLbl = now
				local state = learning and ("LEARNING (" .. learnedCount .. ")")
					or (active and "ON" or "off")
				pcall(function()
					lbl:SetText(("%s | %s | watched %d | %d/s | last: %s"):format(
						state,
						(Options.animMode and Options.animMode.Value) or "?",
						countWatched(), lastPerSec, tostring(lastAction)))
				end)
			end
		end)

		pluginCleanup = function() pcall(saveWatched) end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
