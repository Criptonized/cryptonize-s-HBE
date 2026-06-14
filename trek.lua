-- CryptsHBE plugin: TREK  (framework-aware gun-stat engine)
-- ============================================================================
-- WHY THIS EXISTS: the TREK gun framework (test game 98626216952426, @TREKGun)
-- does NOT store fire-rate/recoil/reload/spread as instance Values or attributes,
-- and does NOT keep them as plain keys in the Config ModuleScript either. Each gun
-- reads them through  Config:GetValue(name)  -- the numbers live behind a function,
-- so the generic Weapons plugin (which scans for numeric Values/keys) finds NOTHING.
--
-- This plugin reaches them two ways, picking whichever works for the held gun:
--   STRATEGY W (wrap):  replace mod.GetValue with a pass-through that calls the real
--       one and OVERRIDES the return for the keys we care about. Robust -- works no
--       matter where GetValue actually fetches the number from. (This is a plain Lua
--       function replacement on the module table, NOT a metamethod/namecall hook.)
--   STRATEGY T (table): if the module is read-only (can't wrap) or exposes no
--       GetValue, locate the backing numeric table (top-level keys, or a table found
--       in GetValue's upvalues via debug.getupvalues) and mutate matching keys each
--       tick, restoring originals on off/switch/unload.
--
-- Fire rate on TREK = the WindUp / WindDown timing pair (there is no "FireRate" key).
-- Lower WindUp/WindDown = faster. Everything is restorable; nothing is permanent.
--
-- It is framework-aware but generic: any kit that funnels stats through a
-- Config:GetValue(name) accessor benefits. Self-reports detected module + active
-- strategy + live values so one test session is decisive.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lPlayer = Players.LocalPlayer

local pluginCleanup = nil

-- ---- helpers ----------------------------------------------------------------
local function heldTool()
	local c = lPlayer.Character
	return c and c:FindFirstChildWhichIsA("Tool") or nil
end

local CFG_NAMES = { "config", "setting", "stat", "data", "tune", "value", "info", "properties", "props" }
local function looksLikeConfig(name)
	name = tostring(name):lower()
	for _, w in ipairs(CFG_NAMES) do if name:find(w, 1, true) then return true end end
	return false
end

-- Find the stat-config ModuleScript inside a tool: prefer a config-named one,
-- else fall back to the first ModuleScript that exposes a GetValue function.
local function findConfigModule(tool)
	if not tool then return nil end
	local named, anyGV
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("ModuleScript") then
			if not named and looksLikeConfig(d.Name) then named = d end
			if not anyGV then
				local ok, m = pcall(require, d)
				if ok and type(m) == "table" and type(rawget(m, "GetValue") or m.GetValue) == "function" then anyGV = d end
			end
		end
	end
	return named or anyGV
end

-- Classify a stat key by name (works on the exact TREK keys + generic substrings).
local function isRecoil(lk) return lk:find("recoil") or lk:find("camerashake") or lk:find("camkick") or lk:find("kick") or lk:find("punch") end
local function isSpread(lk) return lk:find("spread") or lk:find("bloom") or lk:find("sway") end
local function isReload(lk) return lk:find("reload") end
local RATE_DELAY = { windup = true, winddown = true, cooldown = true, firedelay = true, shotdelay = true,
	debounce = true, firetime = true, fireinterval = true, shootdelay = true, shootcooldown = true, charge = true }
local RATE_RATE  = { firerate = true, rpm = true, rof = true, roundsperminute = true, roundspersecond = true, rateoffire = true }
local function isRateDelay(lk) return RATE_DELAY[lk] or lk:find("winddown") or lk:find("windup") or lk:find("cooldown") or lk:find("firedelay") end
local function isRateRate(lk) return RATE_RATE[lk] or lk:find("firerate") or lk:find("rpm") end

-- Given the original numeric value for a key, return the override (or nil = leave alone),
-- reading the live toggle/slider state. Used by BOTH strategies.
local function computeOverride(key, orig)
	if type(orig) ~= "number" then return nil end
	local lk = tostring(key):lower()
	if Toggles.trekNoRecoil and Toggles.trekNoRecoil.Value and isRecoil(lk) then return 0 end
	if Toggles.trekNoSpread and Toggles.trekNoSpread.Value and isSpread(lk) then return 0 end
	if Toggles.trekInstantReload and Toggles.trekInstantReload.Value and isReload(lk) then
		return orig * 0.05
	end
	if Toggles.trekFireRate and Toggles.trekFireRate.Value then
		local x = (Options.trekFireRateX and Options.trekFireRateX.Value) or 1
		local rateMode = ((Options.trekFireRateMode and Options.trekFireRateMode.Value) or ""):find("Rate") ~= nil
		if rateMode and isRateRate(lk) then return orig * x end
		if (not rateMode) and isRateDelay(lk) then return orig / math.max(1, x) end
	end
	return nil
end

-- The stat keys we surface in the live readout (exact TREK casing).
local READOUT_KEYS = { "WindUp", "WindDown", "RecoilX", "RecoilY", "baseSpread", "ReloadSpeed", "BurstAmount", "Damage" }

-- Try every plausible call signature for a GetValue-style accessor; return first non-nil.
local function callGetValue(mod, original, tool, key)
	local function pick(...)
		for i = 1, select("#", ...) do local a = select(i, ...) if a ~= nil then return a end end
		return nil
	end
	local o1, v1 = pcall(original, mod, key)
	local o2, v2 = pcall(original, key)
	local o3, v3 = pcall(original, mod, tool, key)
	local o4, v4 = pcall(original, mod, tool and tool.Name, key)
	return pick(o1 and v1, o2 and v2, o3 and v3, o4 and v4)
end

-- ---- the live engine state --------------------------------------------------
return {
	name = "TREK", tab = "TREK", requires = {},
	load = function(ctx)
		local function C(k) ctx:Control(k) end

		local gMain = ctx:Groupbox("Fire Rate", "left")
		gMain:AddToggle("trekFireRate", { Text = "Fire Rate Boost", Default = false, Tooltip = "Shrink the gun's WindUp/WindDown (or cooldown/fire-delay) by Factor. Lower timing = faster firing. (Default: OFF)" }); C("trekFireRate")
		gMain:AddSlider("trekFireRateX", { Text = "Factor", Min = 1, Max = 30, Default = 4, Rounding = 1, Tooltip = "x4 = fires ~4x faster (delay divided by 4)." }); C("trekFireRateX")
		gMain:AddDropdown("trekFireRateMode", { Text = "Value is", Values = { "Delay (lower = faster)", "Rate (higher = faster)" }, Default = "Delay (lower = faster)", Multi = false, AllowNull = false, Tooltip = "TREK uses Delay (WindUp/WindDown). Use Rate only if a kit stores shots-per-second." }); C("trekFireRateMode")

		local gMods = ctx:Groupbox("Other Overrides", "left")
		gMods:AddToggle("trekNoRecoil", { Text = "No Recoil", Default = false, Tooltip = "Zero RecoilX/Y/Z + camera shake on the held gun. (Default: OFF)" }); C("trekNoRecoil")
		gMods:AddToggle("trekNoSpread", { Text = "No Spread", Default = false, Tooltip = "Zero baseSpread/bloom/sway on the held gun. (Default: OFF)" }); C("trekNoSpread")
		gMods:AddToggle("trekInstantReload", { Text = "Instant Reload", Default = false, Tooltip = "Cut ReloadSpeed to ~5% on the held gun. (Default: OFF)" }); C("trekInstantReload")

		local gInfo = ctx:Groupbox("Detection / Live Values", "right")
		local lblMod = gInfo:AddLabel("Module: hold a gun...", true)
		local lblStrat = gInfo:AddLabel("Strategy: -", true)
		local lblVals = gInfo:AddLabel("Values: -", true)

		-- engine state for the currently-resolved gun
		local cur = { tool = nil, mod = nil, original = nil, strategy = "none", backing = nil, origCache = {} }

		-- STRATEGY T helper: find a numeric backing table to mutate. Looks at top-level
		-- module keys first, then tables hidden in GetValue's upvalues.
		local function findBackingTable(mod, gv)
			-- top level: does the module itself hold numeric stat keys?
			local hasNum = false
			pcall(function()
				for k, v in pairs(mod) do if type(k) == "string" and type(v) == "number" then hasNum = true break end end
			end)
			if hasNum then return mod end
			-- upvalues of GetValue
			if gv and debug and debug.getupvalues then
				local ok, ups = pcall(debug.getupvalues, gv)
				if ok and type(ups) == "table" then
					for _, uv in pairs(ups) do
						if type(uv) == "table" then
							local n = false
							pcall(function() for k, v in pairs(uv) do if type(k) == "string" and type(v) == "number" then n = true break end end end)
							if n then return uv end
						end
					end
				end
			end
			return nil
		end

		-- restore a wrapped module / mutated table back to vanilla
		local function teardownCurrent()
			if cur.strategy == "wrap" and cur.mod and cur.original then
				pcall(function() cur.mod.GetValue = cur.original end)
			elseif cur.strategy == "table" and cur.backing then
				for k, v in pairs(cur.origCache) do pcall(function() cur.backing[k] = v end) end
			end
			cur = { tool = nil, mod = nil, original = nil, strategy = "none", backing = nil, origCache = {} }
		end

		-- resolve (and install the right strategy for) the held gun
		local function resolve()
			local tool = heldTool()
			if tool == cur.tool then return end
			teardownCurrent()
			cur.tool = tool
			if not tool then return end
			local cfg = findConfigModule(tool)
			if not cfg then return end
			local ok, mod = pcall(require, cfg)
			if not ok or type(mod) ~= "table" then return end
			cur.mod = mod
			cur.cfgName = cfg:GetFullName()
			local gv = rawget(mod, "GetValue") or mod.GetValue
			if type(gv) == "function" then
				cur.original = gv
				-- try STRATEGY W: wrap GetValue
				local wrapped = function(...)
					local res = cur.original(...)
					-- find the key argument (a string) among the call args
					for i = 1, select("#", ...) do
						local a = select(i, ...)
						if type(a) == "string" then
							local nv = computeOverride(a, res)
							if nv ~= nil then return nv end
						end
					end
					return res
				end
				local okw = pcall(function() mod.GetValue = wrapped end)
				if okw and rawget(mod, "GetValue") == wrapped then
					cur.strategy = "wrap"
					return
				end
				-- wrap failed (read-only module) -> STRATEGY T on the backing table
				cur.original = gv
				local bt = findBackingTable(mod, gv)
				if bt then cur.backing = bt; cur.strategy = "table"; return end
				cur.strategy = "readonly-novalue"
				return
			end
			-- no GetValue: plain-table config -> STRATEGY T directly on the module
			local bt = findBackingTable(mod, nil)
			if bt then cur.backing = bt; cur.strategy = "table"; return end
			cur.strategy = "no-accessor"
		end

		-- STRATEGY T application (runs only when strategy == table)
		local function applyTable()
			if cur.strategy ~= "table" or not cur.backing then return end
			-- restore everything first so transforms always derive from the true original
			for k, v in pairs(cur.origCache) do pcall(function() cur.backing[k] = v end) end
			for k, v in pairs(cur.backing) do
				if type(k) == "string" and type(v) == "number" then
					local nv = computeOverride(k, cur.origCache[k] ~= nil and cur.origCache[k] or v)
					if nv ~= nil then
						if cur.origCache[k] == nil then cur.origCache[k] = v end
						pcall(function() cur.backing[k] = nv end)
					end
				end
			end
		end

		-- live readout
		local function refreshReadout()
			pcall(function() lblMod:SetText("Module: " .. (cur.cfgName or (cur.tool and (cur.tool.Name .. " (no config module)") or "hold a gun..."))) end)
			local stratText = ({
				wrap = "Wrap GetValue (active)",
				table = "Backing-table mutate (active)",
				["readonly-novalue"] = "FAILED: module read-only, no backing table found",
				["no-accessor"] = "FAILED: no GetValue + no numeric table",
				none = "-",
			})[cur.strategy] or cur.strategy
			pcall(function() lblStrat:SetText("Strategy: " .. stratText) end)
			-- live values via the (possibly wrapped) accessor -> confirms overrides land
			if cur.mod and cur.strategy == "wrap" then
				local parts = {}
				local gv = rawget(cur.mod, "GetValue") or cur.mod.GetValue
				for _, key in ipairs(READOUT_KEYS) do
					local v = callGetValue(cur.mod, gv, cur.tool, key)
					if type(v) == "number" then parts[#parts + 1] = key .. "=" .. tostring(math.floor(v * 1000 + 0.5) / 1000) end
				end
				pcall(function() lblVals:SetText("Values: " .. (#parts > 0 and table.concat(parts, "  ") or "(none returned)")) end)
			elseif cur.strategy == "table" and cur.backing then
				local parts = {}
				for _, key in ipairs(READOUT_KEYS) do
					local v = cur.backing[key]
					if type(v) == "number" then parts[#parts + 1] = key .. "=" .. tostring(v) end
				end
				pcall(function() lblVals:SetText("Values: " .. (#parts > 0 and table.concat(parts, "  ") or "(keys not in this table)")) end)
			else
				pcall(function() lblVals:SetText("Values: -") end)
			end
		end

		-- Probe button: dump everything to workspace/CryptsHBE/config_probe.txt for the chat.
		gInfo:AddButton("Probe + Dump to file", function()
			resolve()
			local out = {}
			local function log(s) out[#out + 1] = s end
			log("=== TREK Config Probe ===")
			log("PlaceId: " .. tostring(game.PlaceId))
			log("Tool: " .. (cur.tool and cur.tool.Name or "none"))
			log("Config module: " .. (cur.cfgName or "none"))
			log("Strategy chosen: " .. cur.strategy)
			if cur.mod then
				log("-- top-level keys --")
				pcall(function()
					for k, v in pairs(cur.mod) do
						local tv = type(v)
						log("  " .. tostring(k) .. " : " .. tv .. (tv ~= "table" and tv ~= "function" and (" = " .. tostring(v)) or ""))
					end
				end)
				local gv = cur.original or rawget(cur.mod, "GetValue") or cur.mod.GetValue
				if type(gv) == "function" then
					log("-- GetValue(key) live values --")
					local KEYS = { "WindUp", "WindDown", "Charged", "BurstAmount", "RaysPerShot", "baseSpread",
						"ReloadSpeed", "RecoilX", "RecoilY", "RecoilZ", "ProjectileVelocity", "Damage",
						"MagCapacity", "ReservedAmmo", "ScopeType", "ZoomFov", "CanZoom", "fallOffStart", "fallOffEnd",
						"FireRate", "RPM", "Cooldown", "FireDelay", "Rate" }
					for _, key in ipairs(KEYS) do
						local v = callGetValue(cur.mod, gv, cur.tool, key)
						if v ~= nil and type(v) ~= "table" and type(v) ~= "function" then log("  GetValue(" .. key .. ") = " .. tostring(v)) end
					end
					if debug and debug.getupvalues then
						log("-- GetValue upvalues --")
						local oU, ups = pcall(debug.getupvalues, gv)
						if oU and type(ups) == "table" then
							for i, uv in pairs(ups) do
								local tv = type(uv)
								if tv == "table" then
									log("  upval[" .. tostring(i) .. "] = {table}")
									pcall(function()
										for k, v in pairs(uv) do
											if type(v) ~= "table" and type(v) ~= "function" then
												log("      " .. tostring(k) .. " = " .. tostring(v))
											elseif type(v) == "table" then
												log("      " .. tostring(k) .. " = {table}")
												for k2, v2 in pairs(v) do
													if type(v2) ~= "table" and type(v2) ~= "function" then log("        " .. tostring(k2) .. " = " .. tostring(v2)) end
												end
											end
										end
									end)
								else
									log("  upval[" .. tostring(i) .. "] = " .. tv .. " " .. tostring(uv))
								end
							end
						end
					end
				end
			end
			local text = table.concat(out, "\n")
			pcall(function()
				if makefolder and not (isfolder and isfolder("CryptsHBE")) then makefolder("CryptsHBE") end
				if writefile then writefile("CryptsHBE/config_probe.txt", text) end
			end)
			if Library then Library:Notify("Probe saved -> workspace/CryptsHBE/config_probe.txt") end
		end):AddToolTip("Re-resolve the held gun, call every stat key, dump GetValue + its upvalues to a file to send back.")

		-- main loop: re-resolve on gun change, apply table strategy, refresh readout
		local lastResolve, lastUI = 0, 0
		ctx:Connect(RunService.Heartbeat, function()
			local now = tick()
			if now - lastResolve > 0.4 then lastResolve = now; pcall(resolve) end
			if cur.strategy == "table" then pcall(applyTable) end
			if now - lastUI > 0.25 then lastUI = now; pcall(refreshReadout) end
		end)
		-- clear engine when our character respawns (new tools, stale module refs)
		ctx:Connect(lPlayer.CharacterAdded, function() pcall(teardownCurrent) end)

		local howGroup = ctx:Groupbox("How to Use", "right")
		howGroup:AddLabel(
			"For TREK-framework guns (this test\n" ..
			"game) whose stats hide behind\n" ..
			"Config:GetValue(name).\n\n" ..
			"1. Hold the gun.\n" ..
			"2. Check 'Strategy' shows (active):\n" ..
			"   Wrap = best; Table = fallback;\n" ..
			"   FAILED = stat is elsewhere/server.\n" ..
			"3. Fire Rate: leave 'Value is' on\n" ..
			"   Delay, raise Factor.\n" ..
			"4. Watch 'Values' -- WindUp/WindDown\n" ..
			"   should drop when Fire Rate is on.\n\n" ..
			"If a NEW gun won't respond, hit\n" ..
			"'Probe + Dump to file' and send the\n" ..
			"file so the keys can be added.\n\n" ..
			"Wrapping replaces a game function -\n" ..
			"more detectable than pure value\n" ..
			"writes; it's opt-in by enabling this.",
			true)

		pluginCleanup = function() pcall(teardownCurrent) end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
