-- CryptsHBE plugin: Remote Spy + Packet Cracker + Replay (tab "Spy")
-- ============================================================================
-- The single remote-tooling hub. Consolidates SimpleSpy + Hydroxide (spy/closure
-- scan), the Packet Cracker (serializer decode/forge), the old Remote Sniffer
-- (capture + auto-replay + retarget) and Remote Replay (manual fire-at-nearest) onto
-- one "Spy" tab (merged 2026-06-19) so the whole workflow -- capture -> decode ->
-- forge/replay -> fire -- lives in one place.
--
-- The value serializer (Remote -> Script + packet decode display) is a SimpleSpy-grade
-- port (78n/SimpleSpy) and the closure scanner follows Hydroxide (Upbolt/Hydroxide),
-- built ONCE onto the Bridge (Bridge.Serialize/PathTo/GetNilHelper). Every executor
-- global is feature-detected (Potassium != Synapse) and wrapped in pcall.
--
-- DETECTABLE: the live spy installs a scoped __namecall hook (read-only unless you
-- Block). Replay/forge/manual-fire send real remote calls. OFF by default, inert when
-- off. The dumps are read-only + need no hook.
-- ============================================================================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE
local pluginCleanup = nil

-- ============================================================================
-- SHARED SERIALIZER (build once on the Bridge) -- SimpleSpy-grade value->Lua.
-- Ported from 78n/SimpleSpy (i2p / v2s / t2s) + Upbolt/Hydroxide; feature-detected
-- for Potassium. Built here so the Bridge.Serialize contract exists for any module.
-- ============================================================================
if Bridge and not Bridge.Serialize then
	local hugeP, hugeN = math.huge, -math.huge

	-- numbers: keep inf/nan VALID Lua, integers compact, floats full precision
	local function fmtNum(n)
		if type(n) ~= "number" then return tostring(n) end
		if n ~= n then return "0/0" end            -- nan
		if n == hugeP then return "math.huge" end
		if n == hugeN then return "-math.huge" end
		if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
		return string.format("%.17g", n)           -- round-trip-safe float
	end

	-- strings: reloadable quote; escape control + high bytes as \ddd (binary-safe)
	local function escStr(s)
		return '"' .. s:gsub('[%c\128-\255"\\]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			if c == '\n' then return '\\n' end
			if c == '\t' then return '\\t' end
			if c == '\r' then return '\\r' end
			return string.format('\\%d', string.byte(c))
		end) .. '"'
	end

	local function isIdent(s) return type(s) == "string" and s:match("^[%a_][%w_]*$") ~= nil end
	local function v3(v) return ("Vector3.new(%s, %s, %s)"):format(fmtNum(v.X), fmtNum(v.Y), fmtNum(v.Z)) end
	local function v2(v) return ("Vector2.new(%s, %s)"):format(fmtNum(v.X), fmtNum(v.Y)) end

	-- instance -> path. valid idents use .Name, weird names use :FindFirstChild,
	-- nil-parented falls back to a getNil(name,class) lookup over getnilinstances().
	local function pathTo(obj, state)
		if obj == nil then return "nil" end
		if obj == game then return "game" end
		if typeof(obj) ~= "Instance" then return "nil --[[" .. typeof(obj) .. "]]" end
		local segs, cur, rooted = {}, obj, false
		for _ = 1, 128 do
			if cur == nil then break end
			if cur == game then rooted = true; break end
			table.insert(segs, 1, cur)
			cur = cur.Parent
		end
		if not rooted then
			if state then state.getnil = true end
			local cls, nm = "Instance", "?"
			pcall(function() cls = obj.ClassName end)
			pcall(function() nm = obj.Name end)
			return ("getNil(%s, %s)"):format(escStr(tostring(nm)), escStr(tostring(cls)))
		end
		local s = "game"
		local first = segs[1]
		if first then
			local isSvc = false
			pcall(function() isSvc = (game:GetService(first.ClassName) == first) end)
			if isSvc then
				s = ('game:GetService("%s")'):format(first.ClassName)
				table.remove(segs, 1)
			end
		end
		for _, seg in ipairs(segs) do
			local nm = tostring(seg.Name)
			if isIdent(nm) then s = s .. "." .. nm
			else s = s .. (":FindFirstChild(%s)"):format(escStr(nm)) end
		end
		return s
	end

	local serValue
	local function t2s(t, state, depth)
		if state.tables[t] then return "{} --[[cyclic/dup]]" end
		state.tables[t] = true
		if depth > 6 then return "{ --[[max depth]] }" end
		local parts, count = {}, 0
		for k, v in pairs(t) do
			count = count + 1
			if count > 200 then parts[#parts + 1] = "--[[...truncated]]"; break end
			local key
			if isIdent(k) then key = k .. " = "
			else key = "[" .. serValue(k, state, depth + 1) .. "] = " end
			parts[#parts + 1] = key .. serValue(v, state, depth + 1)
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end

	function serValue(v, state, depth)
		state = state or { tables = {}, getnil = false }
		depth = depth or 0
		local tp = typeof(v)
		if tp == "string" then return escStr(v) end
		if tp == "number" then return fmtNum(v) end
		if tp == "boolean" then return tostring(v) end
		if tp == "nil" then return "nil" end
		if tp == "Instance" then return pathTo(v, state) end
		if tp == "EnumItem" then return tostring(v) end
		if tp == "Enum" then return "Enum." .. tostring(v) end
		if tp == "Vector3" then return v3(v) end
		if tp == "Vector2" then return v2(v) end
		if tp == "Vector3int16" then return ("Vector3int16.new(%d, %d, %d)"):format(v.X, v.Y, v.Z) end
		if tp == "Vector2int16" then return ("Vector2int16.new(%d, %d)"):format(v.X, v.Y) end
		if tp == "CFrame" then
			local c = { v:GetComponents() }
			for i = 1, #c do c[i] = fmtNum(c[i]) end
			return "CFrame.new(" .. table.concat(c, ", ") .. ")"
		end
		if tp == "Color3" then return ("Color3.new(%s, %s, %s)"):format(fmtNum(v.R), fmtNum(v.G), fmtNum(v.B)) end
		if tp == "UDim2" then return ("UDim2.new(%s, %s, %s, %s)"):format(fmtNum(v.X.Scale), fmtNum(v.X.Offset), fmtNum(v.Y.Scale), fmtNum(v.Y.Offset)) end
		if tp == "UDim" then return ("UDim.new(%s, %s)"):format(fmtNum(v.Scale), fmtNum(v.Offset)) end
		if tp == "NumberRange" then return ("NumberRange.new(%s, %s)"):format(fmtNum(v.Min), fmtNum(v.Max)) end
		if tp == "Rect" then return ("Rect.new(%s, %s, %s, %s)"):format(fmtNum(v.Min.X), fmtNum(v.Min.Y), fmtNum(v.Max.X), fmtNum(v.Max.Y)) end
		if tp == "BrickColor" then return ("BrickColor.new(%s)"):format(escStr(v.Name)) end
		if tp == "Ray" then return ("Ray.new(%s, %s)"):format(v3(v.Origin), v3(v.Direction)) end
		if tp == "Region3" then
			local pos, sz = v.CFrame.Position, v.Size
			return ("Region3.new(%s, %s)"):format(v3(pos - sz / 2), v3(pos + sz / 2))
		end
		if tp == "NumberSequence" then
			local kp = {}
			for _, k in ipairs(v.Keypoints) do kp[#kp + 1] = ("NumberSequenceKeypoint.new(%s, %s, %s)"):format(fmtNum(k.Time), fmtNum(k.Value), fmtNum(k.Envelope)) end
			return "NumberSequence.new({ " .. table.concat(kp, ", ") .. " })"
		end
		if tp == "ColorSequence" then
			local kp = {}
			for _, k in ipairs(v.Keypoints) do kp[#kp + 1] = ("ColorSequenceKeypoint.new(%s, %s)"):format(fmtNum(k.Time), serValue(k.Value, state, depth + 1)) end
			return "ColorSequence.new({ " .. table.concat(kp, ", ") .. " })"
		end
		if tp == "PhysicalProperties" then
			return ("PhysicalProperties.new(%s, %s, %s, %s, %s)"):format(fmtNum(v.Density), fmtNum(v.Friction), fmtNum(v.Elasticity), fmtNum(v.FrictionWeight), fmtNum(v.ElasticityWeight))
		end
		if tp == "TweenInfo" then
			return ("TweenInfo.new(%s, Enum.EasingStyle.%s, Enum.EasingDirection.%s, %s, %s, %s)"):format(fmtNum(v.Time), v.EasingStyle.Name, v.EasingDirection.Name, fmtNum(v.RepeatCount), tostring(v.Reverses), fmtNum(v.DelayTime))
		end
		if tp == "Font" then
			return ("Font.new(%s, Enum.FontWeight.%s, Enum.FontStyle.%s)"):format(escStr(v.Family), v.Weight.Name, v.Style.Name)
		end
		if tp == "DateTime" then return ("DateTime.fromUnixTimestampMillis(%d)"):format(v.UnixTimestampMillis) end
		if tp == "buffer" then
			if buffer and buffer.tostring then
				local ok, raw = pcall(buffer.tostring, v)
				if ok then return ("buffer.fromstring(%s)"):format(escStr(raw)) end
			end
			return "nil --[[buffer]]"
		end
		if tp == "table" then return t2s(v, state, depth) end
		return ("nil --[[%s: %s]]"):format(tp, (tostring(v):gsub("[\r\n]", " ")))
	end

	Bridge.Serialize = function(v, state) return serValue(v, state) end
	Bridge.SerializeState = function() return { tables = {}, getnil = false } end
	Bridge.PathTo = pathTo
	Bridge.GetNilHelper = table.concat({
		"local function getNil(name, class)",
		"\tfor _, v in next, (getnilinstances and getnilinstances() or {}) do",
		"\t\tif typeof(v) == \"Instance\" and v.ClassName == class and v.Name == name then return v end",
		"\tend",
		"\treturn nil",
		"end",
	}, "\n")
end

local serialize = Bridge.Serialize
local pathTo = Bridge.PathTo
local function ser(v) return serialize(v) end

-- ---- Packet Cracker word lists + Sniffer combat keywords --------------------
local DEC_W = { "deserialize", "deserialise", "unpack", "decode", "read", "deser", "frombuffer", "unmarshal", "parse" }
local ENC_W = { "serialize", "serialise", "pack", "encode", "write", "tobuffer", "marshal", "build" }
local MOD_W = { "serial", "packet", "network", "buffer", "byte", "net", "squash", "blink", "bytenet", "marshal", "replion", "remote" }
local COMBAT_WORDS = { "hit", "damage", "dmg", "swing", "attack", "block", "parry", "shoot", "fire", "bow", "draw",
	"melee", "stab", "slash", "hurt", "combat", "weapon", "strike", "wound", "kill", "buy", "purchase", "shop", "spend", "cash", "ammo", "reload" }
local function matchAny(s, set) s = tostring(s):lower() for _, w in ipairs(set) do if s:find(w, 1, true) then return true end end return false end

-- quick binary-aware preview for raw packet strings (the encoded blob)
local function hexPreview(v)
	if type(v) == "string" then
		if #v > 0 and v:find("[^%g ]") then
			return ("<bin len=%d hex=%s>"):format(#v, (v:sub(1, 24):gsub(".", function(c) return string.format("%02x", c:byte()) end)))
		end
		return string.format("%q", v)
	end
	return tostring(v)
end

local function writeOut(fname, text)
	if Bridge and Bridge.SessionName then pcall(function() fname = Bridge:SessionName(fname) end) end
	pcall(function()
		if makefolder and not (isfolder and isfolder("CryptsHBE")) then makefolder("CryptsHBE") end
		if writefile then writefile("CryptsHBE/" .. fname, text) end
	end)
	return fname
end

return {
	name = "RemoteSpy", tab = "Spy", requires = {},
	load = function(ctx)
		local function C(k) ctx:Control(k) end

		local active = false
		local hookInstalled = false
		local calls = {}       -- order -> { inst, name, method, rawArgs, argc, caller, count }
		local byKey = {}       -- "name|method|argstr" -> call (dedup)
		local order = 0
		local blocked = {}     -- [remoteName]=true -> suppress the real call
		local ignored = {}     -- [remoteName]=true -> don't log
		local needRefresh = false
		local lastRef = 0

		-- nearest enemy (range optional, team-ignore optional) -> player, position
		local function myRoot()
			local c = lPlayer.Character
			return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
		end
		local function nearestEnemy(maxRange, ignoreTeam)
			local lr = myRoot(); if not lr then return nil end
			local best, bpos, bd
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= lPlayer then
					local ally = false
					if ignoreTeam then pcall(function() if lPlayer.Team or p.Team then ally = (lPlayer.Team == p.Team) end end) end
					local pc = p.Character
					local pr = pc and (pc:FindFirstChild("HumanoidRootPart") or pc:FindFirstChild("Head"))
					local hum = pc and pc:FindFirstChildWhichIsA("Humanoid")
					if pr and not ally and (not hum or hum.Health > 0) then
						local d = (pr.Position - lr.Position).Magnitude
						if (not maxRange or d <= maxRange) and (not bd or d < bd) then best, bpos, bd = p, pr.Position, d end
					end
				end
			end
			return best, bpos
		end

		local gSpy = ctx:Groupbox("Remote Spy", "left")
		gSpy:AddToggle("spyActive", { Text = "Spy Active (DETECTABLE)", Default = false, Tooltip = "Install a __namecall hook logging outgoing FireServer/InvokeServer calls + the calling script. Read-only unless you Block. OFF by default. (Default: OFF)" }); C("spyActive")
		gSpy:AddToggle("sniffCombatOnly", { Text = "Combat/economy only", Default = false, Tooltip = "Only log remotes whose name matches hit/damage/shoot/buy/... -- cuts noise when hunting a combat/shop remote. (Default: OFF)" }); C("sniffCombatOnly")
		gSpy:AddInput("spyFilter", { Text = "Name contains", Default = "", Tooltip = "Only log remotes whose name contains this (blank = all). e.g. Combat / PHit / Projectile." }); C("spyFilter")
		local lblSpy = gSpy:AddLabel("Spy off.", true)
		gSpy:AddButton("Clear Log", function() calls = {}; byKey = {}; order = 0; needRefresh = true; pcall(function() lblSpy:SetText("Cleared.") end) end)

		local gSel = ctx:Groupbox("Captured / Selected + Replay", "right")
		gSel:AddDropdown("spyPick", { Text = "Captured call", Values = {}, Multi = false, AllowNull = true, Tooltip = "Pick a captured call to script/decode/replay/block. Fills automatically while Auto-refresh is on." }); C("spyPick")
		gSel:AddToggle("spyAutoRefresh", { Text = "Auto-refresh list", Default = true, Tooltip = "Repopulate the Captured call dropdown automatically (~1/s) as new calls arrive, so you don't have to press Refresh List. (Default: ON)" }); C("spyAutoRefresh")
		local lblSel = gSel:AddLabel("Pick a call.", true)
		local pickMap = {}
		local function refreshList()
			pickMap = {}
			local names = {}
			for _, c in ipairs(calls) do
				local key = ("#%d %s:%s x%d"):format(c.order, c.name, c.method, c.count)
				pickMap[key] = c; names[#names + 1] = key
			end
			Options.spyPick.Values = names
			pcall(function() Options.spyPick:SetValues() end)
		end
		gSel:AddButton("Refresh List", refreshList)
		local function selected() return pickMap[Options.spyPick.Value] end

		-- auto-refresh pump (Heartbeat, throttled, main-thread -- never refresh from the hook)
		ctx:Connect(RunService.Heartbeat, function()
			if needRefresh and Toggles.spyAutoRefresh and Toggles.spyAutoRefresh.Value and (tick() - lastRef) > 1 then
				needRefresh = false; lastRef = tick(); pcall(refreshList)
			end
		end)

		Options.spyPick:OnChanged(function()
			local c = selected()
			if not c then return end
			local argParts = {}
			for i = 1, c.argc do argParts[#argParts + 1] = ser(c.rawArgs[i]) end
			pcall(function() lblSel:SetText(("%s:%s\nargs: %s\nfrom: %s"):format(c.name, c.method, table.concat(argParts, ", "):sub(1, 120), c.caller or "?")) end)
		end)

		local function genScript(c)
			local state = Bridge.SerializeState()
			local remotePath = pathTo(c.inst, state)
			local argParts = {}
			for i = 1, c.argc do argParts[#argParts + 1] = serialize(c.rawArgs[i], state) end
			local lines = {
				"-- CryptsHBE Remote Spy -> Script",
				"-- remote: " .. c.name .. "   method: " .. c.method .. "   from: " .. (c.caller or "?"),
			}
			if state.getnil then lines[#lines + 1] = Bridge.GetNilHelper end
			lines[#lines + 1] = "local remote = " .. remotePath
			lines[#lines + 1] = "local args = { " .. table.concat(argParts, ", ") .. " }"
			lines[#lines + 1] = (c.method == "InvokeServer" and "local result = remote:InvokeServer(unpack(args))" or "remote:FireServer(unpack(args))")
			return table.concat(lines, "\n")
		end
		gSel:AddButton("Generate Script -> file + clipboard", function()
			local c = selected(); if not c then Library:Notify("Pick a call first"); return end
			local code = genScript(c)
			local fn = writeOut("remote_script_" .. tostring(c.name) .. ".lua", code)
			pcall(function() if setclipboard then setclipboard(code) end end)
			Library:Notify("Script -> CryptsHBE/" .. fn .. " (+ clipboard)")
		end):AddToolTip("Writes a runnable Lua script that reproduces this exact call (SimpleSpy-grade serializer: buffers/nil-parented/all userdata), to a file AND your clipboard.")

		-- ---- capture replay (old Sniffer -> Fire): once / auto / retargeted ----
		gSel:AddToggle("sniffRetarget", { Text = "Retarget replay -> nearest enemy", Default = false, Tooltip = "When replaying, swap Player args -> nearest enemy and Vector3 args -> their position (for damage/hit remotes). (Default: OFF)" }); C("sniffRetarget")
		local function buildArgs(c)
			local args = {}
			for i = 1, (c.argc or 0) do args[i] = c.rawArgs[i] end
			if Toggles.sniffRetarget and Toggles.sniffRetarget.Value then
				local tgt, tpos = nearestEnemy(nil, true)
				for i = 1, (c.argc or 0) do
					local a = args[i]
					if typeof(a) == "Instance" and a:IsA("Player") and tgt then args[i] = tgt
					elseif typeof(a) == "Vector3" and tpos then args[i] = tpos end
				end
			end
			return args, (c.argc or 0)
		end
		local function fireCaptured(c)
			if not (c.inst and c.inst.Parent) then Library:Notify("That remote is gone"); return false end
			local args, n = buildArgs(c)
			pcall(function()
				if c.method == "FireServer" then c.inst:FireServer(unpack(args, 1, n))
				elseif c.method == "InvokeServer" then c.inst:InvokeServer(unpack(args, 1, n)) end
			end)
			return true
		end
		gSel:AddButton("Replay Once", function()
			local c = selected(); if not c then Library:Notify("Pick a call first"); return end
			if fireCaptured(c) then Library:Notify("Replayed " .. c.name) end
		end):AddToolTip("Re-send the captured call's exact payload one time (with retarget if enabled).")
		gSel:AddToggle("sniffAutoReplay", { Text = "Auto-Replay (farm)", Default = false, Tooltip = "Re-send the selected captured call repeatedly at the rate below (farm a kill/award remote, or a bolt gun's Shoot for full-auto). (Default: OFF)" }); C("sniffAutoReplay")
		gSel:AddSlider("sniffReplayRate", { Text = "Replays / sec", Min = 1, Max = 30, Default = 5, Rounding = 0 }); C("sniffReplayRate")
		local lastCapReplay = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.sniffAutoReplay and Toggles.sniffAutoReplay.Value) then return end
			local c = selected(); if not c then return end
			local now = tick(); if now - lastCapReplay < 1 / math.max(1, Options.sniffReplayRate.Value) then return end; lastCapReplay = now
			fireCaptured(c)
		end)
		gSel:AddButton("Block this remote", function()
			local c = selected(); if not c then return end
			blocked[c.name] = not blocked[c.name]
			Library:Notify((blocked[c.name] and "BLOCKING " or "Unblocked ") .. c.name)
		end):AddToolTip("Toggle: suppress the game's own calls to this remote (DETECTABLE, alters calls).")
		gSel:AddButton("Ignore this remote", function()
			local c = selected(); if not c then return end
			ignored[c.name] = not ignored[c.name]
			Library:Notify((ignored[c.name] and "Ignoring " or "Un-ignored ") .. c.name)
		end):AddToolTip("Toggle: stop logging this remote (keeps the log clean).")

		-- ---- the hook ------------------------------------------------------
		local function passFilter(name)
			if Toggles.sniffCombatOnly and Toggles.sniffCombatOnly.Value and not matchAny(name, COMBAT_WORDS) then return false end
			local f = (Options.spyFilter and Options.spyFilter.Value or "")
			if f == "" then return true end
			return tostring(name):lower():find(f:lower(), 1, true) ~= nil
		end
		local function record(self, method, args, argc)
			local ok, name = pcall(function() return self.Name end)
			name = ok and name or "?"
			if ignored[name] or not passFilter(name) then return end
			local caller = "?"
			pcall(function() local s = getcallingscript and getcallingscript(); if s then caller = s:GetFullName() end end)
			local argStr = ""
			pcall(function() local p = {}; for i = 1, argc do p[i] = ser(args[i]) end; argStr = table.concat(p, ",") end)
			local key = name .. "|" .. method .. "|" .. argStr:sub(1, 80)
			local e = byKey[key]
			if e then e.count = e.count + 1; e.rawArgs = args; e.argc = argc
			else
				order = order + 1
				e = { inst = self, name = name, method = method, rawArgs = args, argc = argc, caller = caller, count = 1, order = order }
				byKey[key] = e; calls[#calls + 1] = e
				if #calls > 120 then table.remove(calls, 1) end
			end
			needRefresh = true   -- pumped to the dropdown on Heartbeat (not from this hook thread)
			-- expose the latest binary packet so the Packet Cracker can decode it
			pcall(function()
				for i = 1, argc do
					if type(args[i]) == "string" then
						getgenv().CryptsHBE.SpyLastPacket = args[i]
						getgenv().CryptsHBE.SpyLastRemote = self
						getgenv().CryptsHBE.SpyLastMethod = method
						break
					elseif typeof(args[i]) == "buffer" and buffer and buffer.tostring then
						getgenv().CryptsHBE.SpyLastPacket = buffer.tostring(args[i])
						getgenv().CryptsHBE.SpyLastRemote = self
						getgenv().CryptsHBE.SpyLastMethod = method
						break
					end
				end
			end)
			pcall(function() lblSpy:SetText(("Logged %d call(s). Newest: %s:%s"):format(#calls, name, method)) end)
		end
		local function ensureHook()
			if hookInstalled then return true end
			if not (hookmetamethod and getnamecallmethod and checkcaller) then Library:Notify("Executor lacks hookmetamethod"); return false end
			local ok = pcall(function()
				local old
				old = hookmetamethod(game, "__namecall", function(self, ...)
					if active and not checkcaller() then
						local m = getnamecallmethod()
						if m == "FireServer" or m == "InvokeServer" then
							pcall(record, self, m, { ... }, select("#", ...))
							local nm = ""; pcall(function() nm = self.Name end)
							if blocked[nm] then return end   -- suppress the real call
						end
					end
					return old(self, ...)
				end)
			end)
			if not ok then Library:Notify("Spy hook failed"); return false end
			hookInstalled = true; return true
		end
		Toggles.spyActive:OnChanged(function()
			if Toggles.spyActive.Value then
				if not ensureHook() then pcall(function() Toggles.spyActive:SetValue(false) end); return end
				active = true; Library:Notify("Remote Spy ON (detectable)")
			else
				active = false; Library:Notify("Remote Spy off")
			end
		end)

		-- ---- dump everything ----------------------------------------------
		local gDump = ctx:Groupbox("Dump", "left")
		gDump:AddButton("Download all remotes/functions -> .txt", function()
			local L = { "=== CryptsHBE Remote/Function Dump ===", "PlaceId: " .. tostring(game.PlaceId), "" }
			-- remotes + bindables (incl. nil-parented via getnilinstances)
			L[#L + 1] = "-- REMOTES & BINDABLES --"
			local seen, n = {}, 0
			local function addInst(d)
				if seen[d] then return end
				if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") or d:IsA("BindableFunction") then
					seen[d] = true; n = n + 1
					local ok, full = pcall(function() return d:GetFullName() end)
					L[#L + 1] = ("  %s  %s"):format(d.ClassName, ok and full or d.Name)
				end
			end
			pcall(function() for _, d in ipairs(game:GetDescendants()) do addInst(d) end end)
			pcall(function() if getnilinstances then for _, d in ipairs(getnilinstances()) do pcall(function() if typeof(d) == "Instance" then addInst(d) end end) end end end)
			L[#L + 1] = ("(%d remotes/bindables)"):format(n)
			-- scripts + modules (the "functions" source surface)
			L[#L + 1] = ""; L[#L + 1] = "-- SCRIPTS & MODULES --"
			local sc = 0
			pcall(function()
				for _, d in ipairs(game:GetDescendants()) do
					if (d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Script")) and sc < 4000 then
						sc = sc + 1
						local ok, full = pcall(function() return d:GetFullName() end)
						L[#L + 1] = ("  %s  %s"):format(d.ClassName, ok and full or d.Name)
					end
				end
			end)
			L[#L + 1] = ("(%d scripts/modules)"):format(sc)
			-- GC function count (Hydroxide-style closure surface)
			pcall(function()
				if getgc then
					local fc = 0
					for _, o in ipairs(getgc(false)) do if type(o) == "function" then fc = fc + 1 end end
					L[#L + 1] = ""; L[#L + 1] = ("-- GC functions: %d (use ClosureSpy/Inspect for details) --"):format(fc)
				end
			end)
			local fn = writeOut("remotes_functions_" .. tostring(game.PlaceId) .. ".txt", table.concat(L, "\n"))
			Library:Notify(("Dumped %d remotes + %d scripts -> CryptsHBE/%s"):format(n, sc, fn))
		end):AddToolTip("Read-only: every RemoteEvent/Function + BindableEvent/Function (incl. nil-parented) + every Script/ModuleScript + a GC function count, to a .txt.")
		gDump:AddButton("Save capture log (busiest) -> .txt", function()
			local arr = {}
			for _, c in ipairs(calls) do arr[#arr + 1] = c end
			table.sort(arr, function(a, b) return a.count > b.count end)
			local L = { "=== CryptsHBE Capture Log ===", "PlaceId: " .. tostring(game.PlaceId), "" }
			for _, c in ipairs(arr) do
				local path = c.name; pcall(function() if c.inst then path = c.inst:GetFullName() end end)
				local argParts = {}; for i = 1, c.argc do argParts[#argParts + 1] = ser(c.rawArgs[i]) end
				L[#L + 1] = ("[x%d] %s:%s @ %s\n      args: %s"):format(c.count, c.name, c.method, path, table.concat(argParts, ", "):sub(1, 300))
			end
			L[#L + 1] = ""; L[#L + 1] = "Total captured signatures: " .. #arr
			local fn = writeOut("capture_log_" .. tostring(game.PlaceId) .. ".txt", table.concat(L, "\n"))
			Library:Notify("Capture log -> CryptsHBE/" .. fn)
		end):AddToolTip("Save the captured calls (busiest first) + their args to a .txt -- the old Sniffer's Save Log.")
		gDump:AddLabel("Combines the old Sniffer + Remote replay.\nFull Hydroxide closure-editor GUI isn't\npossible in this menu; use Recon/DeepDive\nfor upvalue/constant dumps.", true)

		-- ===== Manual Replay (no capture) -- old Remote Replay plugin ========
		-- For RemoteEvent-damage games: pick ANY remote + an arg type and fire it at the
		-- nearest enemy (once or as an aura). No capture/hook needed. Honeypot-guarded.
		local gMan = ctx:Groupbox("Manual Replay (no capture)", "left")
		gMan:AddLabel("RemoteEvent-damage games. Refresh, pick the\ndamage remote + an arg, fire at the nearest target.", true)
		local rrRemotes = {}
		gMan:AddDropdown("rrRemote", { Text = "Remote", Values = {}, Multi = false, AllowNull = true, Tooltip = "Discovered RemoteEvents (Refresh to populate)." }); C("rrRemote")
		gMan:AddDropdown("rrArg", { Text = "Argument", Values = { "Target Character", "Target Player", "Target HumanoidRootPart", "Target Position", "None" }, Default = "Target Character", Multi = false, AllowNull = false, Tooltip = "What to pass to FireServer. Match the game's damage remote signature." }); C("rrArg")
		gMan:AddSlider("rrRange", { Text = "Range (studs)", Min = 5, Max = 120, Default = 25, Rounding = 0 }); C("rrRange")
		gMan:AddToggle("rrIgnoreTeam", { Text = "Ignore Team", Default = true }); C("rrIgnoreTeam")
		local function refreshRemotes()
			rrRemotes = {}; local names, count = {}, 0
			pcall(function()
				for _, d in ipairs(game:GetDescendants()) do
					if d:IsA("RemoteEvent") then
						count = count + 1; if count > 4000 then break end
						local key, i = d.Name, 2
						while rrRemotes[key] do key = d.Name .. " #" .. i; i = i + 1 end
						rrRemotes[key] = d; names[#names + 1] = key
					end
				end
			end)
			table.sort(names)
			Options.rrRemote.Values = names; pcall(function() Options.rrRemote:SetValues() end)
			Library:Notify("Found " .. #names .. " RemoteEvents")
		end
		gMan:AddButton("Refresh Remotes", refreshRemotes):AddToolTip("Scan the game for RemoteEvents.")
		local function fireManual(plr)
			local remote = rrRemotes[Options.rrRemote.Value or ""]
			if not remote then Library:Notify("Pick a remote first"); return end
			if Bridge.isHoneypot and Bridge.isHoneypot(remote) then Library:Notify("That remote is a honeypot - skipped"); return end
			local c, mode = plr.Character, Options.rrArg.Value
			local arg
			if mode == "Target Player" then arg = plr
			elseif mode == "Target Character" then arg = c
			elseif mode == "Target HumanoidRootPart" then arg = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
			elseif mode == "Target Position" then local nn = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")); arg = nn and nn.Position end
			pcall(function() if mode == "None" then remote:FireServer() else remote:FireServer(arg) end end)
		end
		gMan:AddButton("Fire at Nearest", function()
			local t = nearestEnemy(Options.rrRange.Value, Toggles.rrIgnoreTeam.Value)
			if t then fireManual(t) else Library:Notify("No target in range") end
		end):AddToolTip("Fire the selected remote once at the nearest valid target.")
		gMan:AddToggle("rrAuto", { Text = "Auto-Fire (aura)", Default = false, Tooltip = "Repeatedly fire the remote at the nearest target. (Default: OFF)" }); C("rrAuto")
		gMan:AddSlider("rrRate", { Text = "Auto Rate (/s)", Min = 1, Max = 20, Default = 5, Rounding = 0 }); C("rrRate")
		local rrLast = 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.rrAuto and Toggles.rrAuto.Value) then return end
			local now = tick(); if now - rrLast < (1 / math.max(1, Options.rrRate.Value)) then return end; rrLast = now
			local t = nearestEnemy(Options.rrRange.Value, Toggles.rrIgnoreTeam.Value); if t then fireManual(t) end
		end)

		-- ===== Closure / Upvalue Scanner (Hydroxide's upvalue scanner) ======
		-- Scan the GC for Lua closures, list them by name + upvalue count, dump/modify their
		-- upvalues + constants. The combat/config functions (fireround, nextfiremode, ...) live
		-- here -- their upvalues often hold the remotes + the serializer. Dedupe is by closure
		-- OBJECT identity (Hydroxide), since names collide.
		local gFn = ctx:Groupbox("Closure Scanner", "right")
		gFn:AddInput("spyFnFilter", { Text = "Filter (name/source)", Default = "", Tooltip = "Only list closures whose name or source matches." }); C("spyFnFilter")
		gFn:AddDropdown("spyFn", { Text = "Closure", Values = {}, Multi = false, AllowNull = true, Tooltip = "Scan first, then pick a closure to dump/modify." }); C("spyFn")
		local lblFn = gFn:AddLabel("Scan to list closures.", true)
		local fnMap = {}
		local function fnInfo(o)
			local nm, src, nups = "", "", 0
			pcall(function()
				local info = debug.getinfo(o)
				nm = tostring(info.name or "")
				src = tostring(info.short_src or info.source or "")
				nups = info.nups or (debug.getupvalues and #debug.getupvalues(o)) or 0
			end)
			return nm, src, nups
		end
		gFn:AddButton("Scan Closures", function()
			if not getgc then Library:Notify("Executor lacks getgc"); return end
			fnMap = {}; local names, cnt = {}, 0
			local seenObj = {}   -- Hydroxide: dedupe by closure object, not name
			local filt = ((Options.spyFnFilter and Options.spyFnFilter.Value) or ""):lower()
			pcall(function()
				for _, o in ipairs(getgc(false)) do
					if type(o) == "function" and not seenObj[o] and (not islclosure or islclosure(o)) and cnt < 250 then
						if not (isexecutorclosure and isexecutorclosure(o)) then
							seenObj[o] = true
							local nm, src, nups = fnInfo(o)
							local hay = (nm .. " " .. src):lower()
							if filt == "" or hay:find(filt, 1, true) then
								local label = (nm ~= "" and nm or "?") .. "  [" .. tostring(nups) .. "up] " .. src:sub(-26)
								local k2, i = label, 2; while fnMap[k2] do k2 = label .. " #" .. i; i = i + 1 end
								fnMap[k2] = o; names[#names + 1] = k2; cnt = cnt + 1
							end
						end
					end
				end
			end)
			table.sort(names)
			Options.spyFn.Values = names; pcall(function() Options.spyFn:SetValues() end)
			pcall(function() lblFn:SetText("Found " .. #names .. " closure(s)") end)
			Library:Notify("Closures: " .. #names)
		end):AddToolTip("Scan the GC for Lua closures (Hydroxide's upvalue scanner; dedupes by object + skips executor closures). Filter to narrow (e.g. 'fire', 'combat'), then Dump/Set.")
		gFn:AddButton("Dump Upvalues + Constants -> .txt", function()
			local fn = fnMap[Options.spyFn.Value]
			if not fn then Library:Notify("Pick a closure (Scan first)"); return end
			local L = { "=== Closure Dump ===" }
			pcall(function()
				local info = debug.getinfo(fn)
				L[#L + 1] = "name: " .. tostring(info.name) .. "  source: " .. tostring(info.short_src or info.source) .. "  line: " .. tostring(info.linedefined or info.currentline)
				L[#L + 1] = "params: " .. tostring(info.numparams) .. "  upvalues: " .. tostring(info.nups)
			end)
			L[#L + 1] = ""; L[#L + 1] = "-- UPVALUES --"
			pcall(function() for i, uv in ipairs(debug.getupvalues(fn)) do L[#L + 1] = ("  [%d] %s"):format(i, ser(uv)) end end)
			L[#L + 1] = ""; L[#L + 1] = "-- CONSTANTS --"
			pcall(function() for i, c in ipairs(debug.getconstants(fn)) do L[#L + 1] = ("  [%d] %s"):format(i, ser(c)) end end)
			local fname = writeOut("closure_dump.txt", table.concat(L, "\n"))
			Library:Notify("Closure -> CryptsHBE/" .. fname)
		end):AddToolTip("Writes the selected closure's upvalues + constants (serialized) to a file.")
		gFn:AddInput("spyUvIdx", { Text = "Upval index", Default = "", Numeric = true, Tooltip = "Upvalue index to modify." }); C("spyUvIdx")
		gFn:AddInput("spyUvVal", { Text = "Upval value", Default = "", Tooltip = "Value: number / true / false / string." }); C("spyUvVal")
		gFn:AddButton("Set Upvalue", function()
			local fn = fnMap[Options.spyFn.Value]
			if not fn then Library:Notify("Pick a closure"); return end
			local idx = tonumber(Options.spyUvIdx and Options.spyUvIdx.Value)
			if not idx then Library:Notify("Bad index"); return end
			local raw = (Options.spyUvVal and Options.spyUvVal.Value) or ""
			local v = raw
			if raw == "true" then v = true elseif raw == "false" then v = false elseif tonumber(raw) then v = tonumber(raw) end
			pcall(function() debug.setupvalue(fn, idx, v) end)
			Library:Notify("Set upvalue [" .. idx .. "]")
		end):AddToolTip("Modify a closure's upvalue (Hydroxide-style). Numbers/bools/strings.")

		-- ============================================================================
		-- PACKET CRACKER (merged in) -- find the game's OWN serializer and reuse it to
		-- DECODE the binary packet captured above + ENCODE a forged one. The crack loop
		-- lives on this tab: capture -> decode -> edit -> encode -> fire. Game-specific.
		-- ============================================================================
		local decMap, encMap = {}, {}
		local encoded = nil

		local gFind = ctx:Groupbox("Packet Cracker: Find Serializer", "left")
		gFind:AddDropdown("pcDecoder", { Text = "Decoder (str->data)", Values = {}, Multi = false, AllowNull = true, Tooltip = "Chosen decode function. Scan first." }); C("pcDecoder")
		gFind:AddDropdown("pcEncoder", { Text = "Encoder (data->str)", Values = {}, Multi = false, AllowNull = true, Tooltip = "Chosen encode function. Scan first." }); C("pcEncoder")
		local lblFind = gFind:AddLabel("Scan to find serializer funcs.", true)
		gFind:AddButton("Scan for Serializers", function()
			decMap, encMap = {}, {}
			local decNames, encNames = {}, {}
			-- (a) GC closures by name -- safe, no require side effects
			pcall(function()
				if getgc then
					for _, o in ipairs(getgc(false)) do
						if type(o) == "function" then
							local nm = ""; pcall(function() nm = tostring(debug.getinfo(o).name or "") end)
							if nm ~= "" then
								if matchAny(nm, DEC_W) then local l = "gc:" .. nm; if not decMap[l] then decMap[l] = o; decNames[#decNames + 1] = l end end
								if matchAny(nm, ENC_W) then local l = "gc:" .. nm; if not encMap[l] then encMap[l] = o; encNames[#encNames + 1] = l end end
							end
						end
					end
				end
			end)
			-- (b) ModuleScripts named like a serializer (require shares the game cache)
			pcall(function()
				for _, d in ipairs(RS:GetDescendants()) do
					if d:IsA("ModuleScript") and matchAny(d.Name, MOD_W) then
						local ok, mod = pcall(require, d)
						if ok and type(mod) == "table" then
							for k, v in pairs(mod) do
								if type(v) == "function" and type(k) == "string" then
									if matchAny(k, DEC_W) then local l = d.Name .. "." .. k; if not decMap[l] then decMap[l] = v; decNames[#decNames + 1] = l end end
									if matchAny(k, ENC_W) then local l = d.Name .. "." .. k; if not encMap[l] then encMap[l] = v; encNames[#encNames + 1] = l end end
								end
							end
						end
					end
				end
			end)
			table.sort(decNames); table.sort(encNames)
			Options.pcDecoder.Values = decNames; pcall(function() Options.pcDecoder:SetValues() end)
			Options.pcEncoder.Values = encNames; pcall(function() Options.pcEncoder:SetValues() end)
			local rep = { "=== Serializer Candidates ===", "DECODERS:" }
			for _, n in ipairs(decNames) do rep[#rep + 1] = "  " .. n end
			rep[#rep + 1] = "ENCODERS:"
			for _, n in ipairs(encNames) do rep[#rep + 1] = "  " .. n end
			writeOut("serializers_" .. tostring(game.PlaceId) .. ".txt", table.concat(rep, "\n"))
			pcall(function() lblFind:SetText(("Decoders: %d  Encoders: %d"):format(#decNames, #encNames)) end)
			Library:Notify(("Serializers: %d dec / %d enc"):format(#decNames, #encNames))
		end):AddToolTip("Finds serialize/deserialize functions in the GC + serializer-named modules. Also use the Closure Scanner above -> dump the combat function's upvalues to find the exact one.")

		local gDec = ctx:Groupbox("Packet Cracker: Decode", "right")
		local lblDec = gDec:AddLabel("Capture a packet (above) first.", true)
		gDec:AddButton("Decode Spy's Last Packet", function()
			local fn = decMap[Options.pcDecoder.Value]
			if not fn then Library:Notify("Pick a decoder (Scan first)"); return end
			local pkt = Bridge and Bridge.SpyLastPacket
			if type(pkt) ~= "string" then Library:Notify("No captured packet -- arm the Spy + do the action"); return end
			local ok, res = pcall(fn, pkt)
			if not ok then pcall(function() lblDec:SetText("Decode failed:\n" .. tostring(res):sub(1, 100)) end); Library:Notify("Decode failed (try another decoder)"); return end
			local out = (Bridge and Bridge.Serialize) and Bridge.Serialize(res) or tostring(res)
			writeOut("packet_decoded_" .. tostring(game.PlaceId) .. ".txt", "decoder: " .. Options.pcDecoder.Value .. "\npacket len: " .. #pkt .. "\nraw: " .. hexPreview(pkt) .. "\n\n" .. out)
			pcall(function() lblDec:SetText("Decoded:\n" .. out:sub(1, 200)) end)
			Library:Notify("Decoded -> file (see fields)")
		end):AddToolTip("Runs the chosen decoder on the last binary packet the Spy captured, revealing its real fields (rendered as reconstructable Lua). Try each decoder until one returns a table.")

		local gEnc = ctx:Groupbox("Packet Cracker: Forge + Fire", "right")
		gEnc:AddInput("pcInput", { Text = "Data (Lua table)", Default = "", Tooltip = "A Lua table literal to encode, e.g. { projectileId = 1234, target = workspace.Players.Team1.Bob }. You can use buffer.fromstring/Vector3/instances etc." }); C("pcInput")
		local lblEnc = gEnc:AddLabel("Encode then fire.", true)
		gEnc:AddButton("Encode", function()
			local fn = encMap[Options.pcEncoder.Value]
			if not fn then Library:Notify("Pick an encoder (Scan first)"); return end
			local raw = (Options.pcInput and Options.pcInput.Value) or ""
			local okp, data = pcall(function() return loadstring("return " .. raw)() end)
			if not okp then Library:Notify("Bad Lua table"); return end
			local oke, pkt = pcall(fn, data)
			if not oke then Library:Notify("Encode failed: " .. tostring(pkt):sub(1, 60)); return end
			encoded = pkt
			pcall(function() lblEnc:SetText("Encoded: " .. hexPreview(pkt):sub(1, 120)) end)
			Library:Notify("Encoded (" .. (type(pkt) == "string" and #pkt or "?") .. " bytes)")
		end):AddToolTip("Builds a packet from your Lua table using the game's encoder -> structurally valid.")
		gEnc:AddButton("Fire Encoded at Spy's Last Remote", function()
			if encoded == nil then Library:Notify("Encode something first"); return end
			local r = Bridge and Bridge.SpyLastRemote
			if not (typeof(r) == "Instance") then Library:Notify("No remote -- capture one above first"); return end
			local m = (Bridge and Bridge.SpyLastMethod) or "FireServer"
			pcall(function()
				if m == "InvokeServer" then r:InvokeServer(encoded) else r:FireServer(encoded) end
			end)
			Library:Notify("Fired forged packet at " .. r.Name)
		end):AddToolTip("Fires your forged packet through the remote the Spy last saw (e.g. PHit / CreateProjectile).")
		gEnc:AddLabel("Loop: capture PHit above -> Decode to see\nfields -> change the target/id -> Encode ->\nFire. Uses the game's own serializer so it's\nvalid. Experimental + game-specific.", true)

		pluginCleanup = function() active = false end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
