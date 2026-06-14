-- CryptsHBE plugin: Weapons (GENERIC value-based gun hacks)
-- ============================================================================
-- Best-effort, hook-free: each toggle scans the HELD tool for NumberValue/IntValue
-- children + numeric attributes whose name matches a stat, captures the original, and
-- overrides it every tick (restoring on toggle-off / gun-switch / unload). It works only
-- on games that keep these stats CLIENT-SIDE. The live "Fields hit" readout shows the
-- count per stat -- if it's 0, the game stores that stat server-side and you need the
-- Calibrate -> Deep-Dump Held Weapon output to build a TAILORED hack instead.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

-- ---- Firemode support -------------------------------------------------------
-- Detect a weapon's firemode (semi / bolt / pump / burst / auto) from its values,
-- attributes, config keys or name, and let you FORCE automatic two ways: flip any
-- firemode value to auto (value-based) AND a universal auto-fire clicker (works even
-- when a gun has no firemode value, on games that fire per click client-side).
-- Some games have no universal "Automatic" keyword, so you can LEARN a weapon as
-- automatic (saved by name to workspace/CryptsHBE/) and it's recognised next time.
local FM_AUTO  = { "automatic", "fullauto", "full auto", "auto", "full" }
local FM_SEMI  = { "semiauto", "semi-auto", "semi", "single" }
local FM_BOLT  = { "boltaction", "bolt action", "bolt", "bolting" }
local FM_PUMP  = { "pump" }
local FM_BURST = { "burst" }
local FM_KEYS  = { "firemode", "firingmode", "firetype", "mode", "fireselector", "selector", "auto" }
local LEARN_FILE = "CryptsHBE/learned_autos.json"
local function txtHas(s, words) s = tostring(s):lower() for _, w in ipairs(words) do if s:find(w, 1, true) then return true end end return false end
local function loadLearned()
	local set = {}
	pcall(function()
		if isfile and readfile and isfile(LEARN_FILE) then
			local t = game:GetService("HttpService"):JSONDecode(readfile(LEARN_FILE))
			if type(t) == "table" then for _, n in ipairs(t) do set[n] = true end end
		end
	end)
	return set
end
local function saveLearned(set)
	pcall(function()
		if makefolder and not (isfolder and isfolder("CryptsHBE")) then makefolder("CryptsHBE") end
		local list = {}; for n in pairs(set) do list[#list + 1] = n end
		if writefile then writefile(LEARN_FILE, game:GetService("HttpService"):JSONEncode(list)) end
	end)
end

local function nameHas(n, words)
	n = tostring(n):lower()
	for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end
	return false
end
local function heldTool()
	local c = lPlayer.Character
	return c and c:FindFirstChildWhichIsA("Tool") or nil
end
-- Some gun frameworks (TREK, FE kits) keep stats in a config-type ModuleScript instead of
-- instance Values, so fire-rate/recoil/reload have no Value to write. We require those
-- modules (the executor shares the game's require cache, so it's the SAME table the gun
-- reads) and expose their matching numeric keys as writable fields. Only modules NAMED
-- like config/settings/stats/data/tune/values are required, to avoid running behaviour
-- modules with side effects. Best-effort: only helps if the gun reads the table live.
local CFG_NAMES = { "config", "setting", "stat", "data", "tune", "value", "info", "properties", "props" }
local function looksLikeConfig(name) name = tostring(name):lower() for _, w in ipairs(CFG_NAMES) do if name:find(w, 1, true) then return true end end return false end
local function scanTable(t, words, out, depth, seen)
	if depth > 4 or type(t) ~= "table" or seen[t] then return end
	seen[t] = true
	for k, v in pairs(t) do
		if type(v) == "number" and type(k) == "string" and nameHas(k, words) then
			out[#out + 1] = { orig = v, set = function(n) pcall(function() t[k] = n end) end }
		elseif type(v) == "table" then scanTable(v, words, out, depth + 1, seen) end
	end
end
-- Build a restorable field list (Value objects + numeric attributes + config-module keys).
local function fieldsFor(tool, words)
	local out = {}
	if not tool then return out end
	pcall(function()
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("NumberValue") or d:IsA("IntValue") or d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue") then
				if nameHas(d.Name, words) then out[#out + 1] = { orig = d.Value, set = function(v) pcall(function() d.Value = v end) end } end
			end
			pcall(function()
				for an, av in pairs(d:GetAttributes()) do
					if type(av) == "number" and nameHas(an, words) then out[#out + 1] = { orig = av, set = function(v) pcall(function() d:SetAttribute(an, v) end) end } end
				end
			end)
			if d:IsA("ModuleScript") and looksLikeConfig(d.Name) then
				pcall(function()
					local ok, mod = pcall(require, d)
					if ok and type(mod) == "table" then scanTable(mod, words, out, 1, {}) end
				end)
			end
		end
	end)
	return out
end
local function newFeature() return { tool = nil, fields = {} } end
-- Apply (or restore) a feature. Re-scans when the held tool changes so a new gun's
-- originals are captured fresh; transform() always runs on the ORIGINAL (never compounds).
local function runFeature(f, on, words, transform)
	if not on then
		if #f.fields > 0 then for _, fl in ipairs(f.fields) do fl.set(fl.orig) end end
		f.fields, f.tool = {}, nil
		return 0
	end
	local tool = heldTool()
	if tool ~= f.tool then
		for _, fl in ipairs(f.fields) do fl.set(fl.orig) end  -- restore old gun
		f.tool = tool
		f.fields = fieldsFor(tool, words)
	end
	for _, fl in ipairs(f.fields) do fl.set(transform(fl.orig)) end
	return #f.fields
end

-- Best-guess firemode of the held tool. learned = set of names you've tagged automatic.
local function detectFiremode(tool, learned)
	if not tool then return "no tool held" end
	if learned[tool.Name] then return "Automatic (learned)" end
	local hits = {}
	pcall(function()
		for _, d in ipairs(tool:GetDescendants()) do
			-- a StringValue whose name or value names a mode (e.g. FireMode = "Auto")
			if d:IsA("StringValue") then
				local s = (d.Name .. " " .. tostring(d.Value)):lower()
				if txtHas(s, FM_AUTO) then hits.auto = true elseif txtHas(s, FM_SEMI) then hits.semi = true
				elseif txtHas(s, FM_BOLT) then hits.bolt = true elseif txtHas(s, FM_PUMP) then hits.pump = true
				elseif txtHas(s, FM_BURST) then hits.burst = true end
			end
			-- a BoolValue/flag named like the modes (Bolting, Automatic, ...)
			if d:IsA("BoolValue") or d:IsA("NumberValue") or d:IsA("IntValue") then
				local n = d.Name:lower()
				if txtHas(n, FM_BOLT) then hits.bolt = true elseif txtHas(n, FM_PUMP) then hits.pump = true
				elseif txtHas(n, FM_BURST) then hits.burst = true end
			end
		end
	end)
	local tn = tool.Name:lower()
	if txtHas(tn, FM_AUTO) then hits.auto = true elseif txtHas(tn, FM_BOLT) then hits.bolt = true
	elseif txtHas(tn, FM_PUMP) then hits.pump = true end
	-- priority: explicit auto > burst > bolt > pump > semi > unknown
	if hits.auto then return "Automatic" elseif hits.burst then return "Burst"
	elseif hits.bolt then return "Bolt-action" elseif hits.pump then return "Pump"
	elseif hits.semi then return "Semi-auto" end
	return "unknown (Learn it if it's auto)"
end

-- Firemode VALUES to flip toward automatic (Bool->true, String->"Automatic"). Numbers are
-- left alone (their auto code varies per game). Returns a restorable field list.
local function firemodeFields(tool)
	local out = {}
	if not tool then return out end
	pcall(function()
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BoolValue") and nameHas(d.Name, FM_AUTO) then
				out[#out + 1] = { orig = d.Value, set = function(v) pcall(function() d.Value = v end) end, auto = true }
			elseif d:IsA("StringValue") and nameHas(d.Name, FM_KEYS) then
				out[#out + 1] = { orig = d.Value, set = function(v) pcall(function() d.Value = v end) end, auto = "Automatic" }
			end
		end
	end)
	return out
end

return {
	name = "Weapons", tab = "Weapons", requires = {},
	load = function(ctx)
		local g  = ctx:Groupbox("Weapon Stats (value-based)", "left")
		local g2 = ctx:Groupbox("Fire Rate", "right")
		local function C(k) ctx:Control(k) end
		local learnedAutos = loadLearned()

		g:AddToggle("weaponNoRecoil", { Text = "No Spread / No Recoil", Default = false, Tooltip = "Zero recoil/spread/kick/bloom/sway values on the held gun. (Default: OFF)" }); C("weaponNoRecoil")
		g:AddToggle("weaponNoDrop", { Text = "No Bullet Drop", Default = false, Tooltip = "Zero bullet drop/gravity/falloff values on the held gun. (Default: OFF)" }); C("weaponNoDrop")
		g:AddToggle("weaponInstantReload", { Text = "Instant Reload", Default = false, Tooltip = "Set reload time/duration values near 0 on the held gun. (Default: OFF)" }); C("weaponInstantReload")
		local info = g:AddLabel("Fields hit: run a gun to see", true)

		g2:AddToggle("weaponFireRate", { Text = "Fire Rate Boost", Default = false, Tooltip = "Scale the gun's fire-rate/cooldown values by the factor below. (Default: OFF)" }); C("weaponFireRate")
		g2:AddSlider("weaponFireRateX", { Text = "Factor", Min = 1, Max = 20, Default = 3, Rounding = 1 }); C("weaponFireRateX")
		g2:AddDropdown("weaponFireRateMode", { Text = "Value is", Values = { "Delay (lower = faster)", "Rate (higher = faster)" }, Default = "Delay (lower = faster)", Multi = false, AllowNull = false, Tooltip = "Whether the gun stores seconds-between-shots (Delay) or shots-per-second (Rate)." }); C("weaponFireRateMode")

		local g3 = ctx:Groupbox("Firemode", "right")
		local fmInfo = g3:AddLabel("Firemode: hold a gun", true)
		g3:AddToggle("weaponForceAuto", { Text = "Force Automatic (value)", Default = false, Tooltip = "Flip any firemode value on the held gun toward automatic (Bool->true,\nString->'Automatic'). Restores on off. (Default: OFF)" }); C("weaponForceAuto")
		g3:AddToggle("weaponAutoFire", { Text = "Auto-Fire (universal)", Default = false, Tooltip = "Rapid-clicks at the RPM below so a semi/bolt/pump gun fires as fast as the game allows.\nUse the keybind to the right to HOLD-to-spray. (Default: OFF)" })
			:AddKeyPicker("weaponAutoFireKey", { Default = "F", Mode = "Hold", Text = "Auto-Fire", SyncToggleState = true, Tooltip = "Hold to spray (syncs the Auto-Fire toggle). Rebind here or in the Keybinds tab." })
		C("weaponAutoFire")
		g3:AddSlider("weaponAutoRPM", { Text = "Auto-Fire RPM", Min = 60, Max = 1200, Default = 600, Rounding = 0, Tooltip = "Rounds per minute for Auto-Fire (600 = 10/sec)." }); C("weaponAutoRPM")
		g3:AddButton("Learn Held as Automatic", function()
			local t = heldTool()
			if not t then Library:Notify("Hold the automatic weapon first"); return end
			learnedAutos[t.Name] = true; saveLearned(learnedAutos)
			Library:Notify("Learned '" .. t.Name .. "' as automatic")
		end):AddToolTip("Tag the held weapon as automatic by name, so it's recognised even with no firemode keyword. Shoot an auto gun, learn it, then it's detected on later guns of that name.")
		g3:AddButton("Forget Learned Autos", function()
			learnedAutos = {}; saveLearned(learnedAutos); Library:Notify("Cleared learned automatic weapons")
		end)

		local RECOIL_W = { "recoil", "spread", "kick", "bloom", "sway", "camkick", "recoilx", "recoily", "recoilz", "punch", "shake" }
		local DROP_W   = { "bulletdrop", "bulletgravity", "projectilegravity", "drop", "falloff", "gravity" }
		local RELOAD_W = { "reloadtime", "reloadduration", "reloaddelay", "reloadcooldown" }
		local RATE_W   = { "firerate", "cooldown", "firedelay", "shotdelay", "debounce", "firetime", "rof", "rpm", "roundspersecond", "roundsperminute", "rateoffire", "fireinterval", "shootdelay", "shootcooldown", "spm", "windup", "winddown", "charge" }

		local fR, fD, fL, fF = newFeature(), newFeature(), newFeature(), newFeature()
		-- Force-Auto value flip state (its own restorable list; firemode fields aren't numeric).
		local fmTool, fmFields = nil, {}
		local function runForceAuto(on)
			if not on then
				for _, fl in ipairs(fmFields) do fl.set(fl.orig) end
				fmFields, fmTool = {}, nil; return 0
			end
			local tool = heldTool()
			if tool ~= fmTool then
				for _, fl in ipairs(fmFields) do fl.set(fl.orig) end
				fmTool = tool; fmFields = firemodeFields(tool)
			end
			for _, fl in ipairs(fmFields) do fl.set(fl.auto) end
			return #fmFields
		end
		local last = 0
		ctx:Connect(RunService.Heartbeat, function()
			local now = tick(); if now - last < 0.1 then return end; last = now
			local nR = runFeature(fR, Toggles.weaponNoRecoil.Value, RECOIL_W, function() return 0 end)
			local nD = runFeature(fD, Toggles.weaponNoDrop.Value, DROP_W, function() return 0 end)
			local nL = runFeature(fL, Toggles.weaponInstantReload.Value, RELOAD_W, function() return 0.05 end)
			local x = Options.weaponFireRateX.Value
			local rate = (Options.weaponFireRateMode.Value or ""):find("Rate") ~= nil
			local nF = runFeature(fF, Toggles.weaponFireRate.Value, RATE_W, function(o)
				if rate then return o * x else return o / math.max(1, x) end
			end)
			pcall(function() info:SetText(("Fields hit  Recoil:%d  Drop:%d  Reload:%d  Rate:%d\n(all 0 -> stats are server-side; use Deep-Dump)"):format(nR, nD, nL, nF)) end)
			-- Firemode: force-auto value flip + live detector readout.
			local nA = runForceAuto(Toggles.weaponForceAuto and Toggles.weaponForceAuto.Value)
			pcall(function()
				fmInfo:SetText(("Firemode: %s\nForce-Auto fields: %d   (Auto-Fire %s)"):format(
					detectFiremode(heldTool(), learnedAutos), nA,
					(Toggles.weaponAutoFire and Toggles.weaponAutoFire.Value) and "ON" or "off"))
			end)
		end)

		-- Universal Auto-Fire: rapid synthetic clicks so a semi/bolt/pump gun sprays.
		-- Only fires when a gun is held; restores nothing (it just clicks). mouse1click is
		-- the broadest method; falls back gracefully if the executor lacks it.
		local lastShot = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.weaponAutoFire and Toggles.weaponAutoFire.Value) then return end
			if not heldTool() then return end
			local rpm = (Options.weaponAutoRPM and Options.weaponAutoRPM.Value) or 600
			local interval = 60 / math.max(60, rpm)
			local now = tick(); if now - lastShot < interval then return end; lastShot = now
			pcall(function()
				if mouse1click then mouse1click()
				elseif mouse1press and mouse1release then mouse1press(); mouse1release() end
			end)
		end)

		-- Bottom-of-tab tutorial.
		local howGroup = ctx:Groupbox("How to Use", "left")
		howGroup:AddLabel(
			"Generic client-side gun-stat overrides.\n" ..
			"Hold a gun, flip a toggle, watch the\n" ..
			"'Fields hit' readout:\n" ..
			"  - > 0  -> stat is client-side; the\n" ..
			"    toggle is working.\n" ..
			"  - = 0  -> the game keeps it SERVER-\n" ..
			"    SIDE; this can't touch it. Use\n" ..
			"    Calibrate -> Deep-Dump and ask for\n" ..
			"    a TAILORED hack instead.\n\n" ..
			"FIRE RATE: set 'Value is' to Delay if\n" ..
			"the gun stores seconds-between-shots\n" ..
			"(most do), or Rate if shots-per-second,\n" ..
			"then raise Factor.\n\n" ..
			"FIREMODE: the readout shows the held gun's\n" ..
			"mode. Force Automatic flips a firemode\n" ..
			"VALUE; Auto-Fire rapid-clicks so ANY gun\n" ..
			"sprays (bind a key to it to hold-spray).\n" ..
			"No 'Auto' keyword? Shoot a real auto gun\n" ..
			"and 'Learn Held as Automatic' so it's\n" ..
			"recognised by name next time.\n\n" ..
			"Everything restores on toggle-off / gun-\n" ..
			"switch / unload -- no permanent edits.",
			true)

		pluginCleanup = function()
			runFeature(fR, false); runFeature(fD, false); runFeature(fL, false); runFeature(fF, false)
			runForceAuto(false)
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
