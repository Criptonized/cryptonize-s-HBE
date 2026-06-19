-- CryptsHBE plugin: Remote Spy (tab "Spy")
-- ============================================================================
-- A consolidated, up-to-date remote spy in the spirit of SimpleSpy + Hydroxide
-- (both archived/outdated). Logs outgoing FireServer/InvokeServer calls with
-- their args + the CALLING SCRIPT, generates a reproducible Lua script for any
-- captured call (Remote -> Script), can Block / Ignore remotes by name, Replay a
-- call, and dump every remote/function in the game to a .txt.
--
-- The value serializer (Remote -> Script arg generator) is a SimpleSpy-grade port
-- (78n/SimpleSpy) + the closure scanner follows Hydroxide (Upbolt/Hydroxide). It
-- is built ONCE onto the Bridge (Bridge.Serialize/PathTo/GetNilHelper) so the
-- Packet Cracker shares the exact same robust impl. Every executor global is
-- feature-detected (Potassium != Synapse) and wrapped in pcall.
--
-- DETECTABLE: the live spy installs a scoped __namecall hook (read-only unless you
-- Block). OFF by default, inert when off. The dumps are read-only + need no hook.
-- ============================================================================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE
local pluginCleanup = nil

-- ============================================================================
-- SHARED SERIALIZER (build once on the Bridge) -- SimpleSpy-grade value->Lua.
-- Ported from 78n/SimpleSpy (i2p / v2s / t2s) + Upbolt/Hydroxide; feature-detected
-- for Potassium. Both RemoteSpy and PacketCracker reference Bridge.Serialize so
-- there is exactly one implementation and no drift.
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

		local gSpy = ctx:Groupbox("Remote Spy", "left")
		gSpy:AddToggle("spyActive", { Text = "Spy Active (DETECTABLE)", Default = false, Tooltip = "Install a __namecall hook logging outgoing FireServer/InvokeServer calls + the calling script. Read-only unless you Block. OFF by default. (Default: OFF)" }); C("spyActive")
		gSpy:AddInput("spyFilter", { Text = "Name contains", Default = "", Tooltip = "Only log remotes whose name contains this (blank = all)." }); C("spyFilter")
		local lblSpy = gSpy:AddLabel("Spy off.", true)
		gSpy:AddButton("Clear Log", function() calls = {}; byKey = {}; order = 0; pcall(function() lblSpy:SetText("Cleared.") end) end)

		local gSel = ctx:Groupbox("Captured / Selected", "right")
		gSel:AddDropdown("spyPick", { Text = "Captured call", Values = {}, Multi = false, AllowNull = true, Tooltip = "Pick a captured call to script/replay/block." }); C("spyPick")
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
		gSel:AddButton("Replay Once", function()
			local c = selected(); if not c then Library:Notify("Pick a call first"); return end
			pcall(function()
				if c.method == "FireServer" then c.inst:FireServer(unpack(c.rawArgs, 1, c.argc))
				elseif c.method == "InvokeServer" then c.inst:InvokeServer(unpack(c.rawArgs, 1, c.argc)) end
			end)
			Library:Notify("Replayed " .. c.name)
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
		gDump:AddLabel("Combines the old Sniffer + Remote replay.\nFull Hydroxide closure-editor GUI isn't\npossible in this menu; use Recon/DeepDive\nfor upvalue/constant dumps.", true)

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

		pluginCleanup = function() active = false end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
