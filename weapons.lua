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
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

local function nameHas(n, words)
	n = tostring(n):lower()
	for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end
	return false
end
local function heldTool()
	local c = lPlayer.Character
	return c and c:FindFirstChildWhichIsA("Tool") or nil
end
-- Build a restorable field list (Value objects + numeric attributes) matching `words`.
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

return {
	name = "Weapons", tab = "Weapons", requires = {},
	load = function(ctx)
		local g  = ctx:Groupbox("Weapon Stats (value-based)", "left")
		local g2 = ctx:Groupbox("Fire Rate", "right")
		local function C(k) ctx:Control(k) end

		g:AddToggle("weaponNoRecoil", { Text = "No Spread / No Recoil", Default = false, Tooltip = "Zero recoil/spread/kick/bloom/sway values on the held gun. (Default: OFF)" }); C("weaponNoRecoil")
		g:AddToggle("weaponNoDrop", { Text = "No Bullet Drop", Default = false, Tooltip = "Zero bullet drop/gravity/falloff values on the held gun. (Default: OFF)" }); C("weaponNoDrop")
		g:AddToggle("weaponInstantReload", { Text = "Instant Reload", Default = false, Tooltip = "Set reload time/duration values near 0 on the held gun. (Default: OFF)" }); C("weaponInstantReload")
		local info = g:AddLabel("Fields hit: run a gun to see", true)

		g2:AddToggle("weaponFireRate", { Text = "Fire Rate Boost", Default = false, Tooltip = "Scale the gun's fire-rate/cooldown values by the factor below. (Default: OFF)" }); C("weaponFireRate")
		g2:AddSlider("weaponFireRateX", { Text = "Factor", Min = 1, Max = 20, Default = 3, Rounding = 1 }); C("weaponFireRateX")
		g2:AddDropdown("weaponFireRateMode", { Text = "Value is", Values = { "Delay (lower = faster)", "Rate (higher = faster)" }, Default = "Delay (lower = faster)", Multi = false, AllowNull = false, Tooltip = "Whether the gun stores seconds-between-shots (Delay) or shots-per-second (Rate)." }); C("weaponFireRateMode")

		local RECOIL_W = { "recoil", "spread", "kick", "bloom", "sway", "camkick", "recoilx", "recoily", "recoilz", "punch", "shake" }
		local DROP_W   = { "bulletdrop", "bulletgravity", "projectilegravity", "drop", "falloff", "gravity" }
		local RELOAD_W = { "reloadtime", "reloadduration", "reloaddelay", "reloadcooldown" }
		local RATE_W   = { "firerate", "cooldown", "firedelay", "shotdelay", "debounce", "firetime", "rof", "rpm", "roundspersecond", "roundsperminute" }

		local fR, fD, fL, fF = newFeature(), newFeature(), newFeature(), newFeature()
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
			"Everything restores on toggle-off / gun-\n" ..
			"switch / unload -- no permanent edits.",
			true)

		pluginCleanup = function()
			runFeature(fR, false); runFeature(fD, false); runFeature(fL, false); runFeature(fF, false)
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
