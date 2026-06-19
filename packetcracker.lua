-- CryptsHBE plugin: Packet Cracker (tab "Packets")
-- ============================================================================
-- The serializer cracker. Many games (Bleeding Blades, TREK, ByteNet/Blink/Squash
-- users) pack remote args into a BINARY buffer with their own serializer, so a
-- captured packet is unreadable and a forged one is rejected. This finds the game's
-- OWN serialize/deserialize functions and reuses them to:
--   1. DECODE the last packet the Remote Spy captured -> see its real fields
--      (ProjectileID, target, position, ...).
--   2. ENCODE a forged packet from a Lua table you type -> fire it through a remote.
-- Because it uses the game's own functions, a forged packet is structurally valid.
-- EXPERIMENTAL + game-dependent: needs a discoverable serializer + the right function.
-- Pair with Remote Spy (capture the packet) and the Closure Scanner (find the funcs).
--
-- The decoded-field display uses the SHARED SimpleSpy-grade serializer (Bridge.Serialize,
-- built by either this plugin or RemoteSpy, whichever loads first) so decoded tables
-- render as reconstructable Lua (buffers, instances, all userdata).
-- ============================================================================
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE
local pluginCleanup = nil

-- ============================================================================
-- SHARED SERIALIZER (build once on the Bridge) -- identical to remotespy.lua's
-- preamble so this plugin works standalone (no load-order dependency). SimpleSpy-grade.
-- ============================================================================
if Bridge and not Bridge.Serialize then
	local hugeP, hugeN = math.huge, -math.huge

	local function fmtNum(n)
		if type(n) ~= "number" then return tostring(n) end
		if n ~= n then return "0/0" end
		if n == hugeP then return "math.huge" end
		if n == hugeN then return "-math.huge" end
		if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
		return string.format("%.17g", n)
	end

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

local DEC_W = { "deserialize", "deserialise", "unpack", "decode", "read", "deser", "frombuffer", "unmarshal", "parse" }
local ENC_W = { "serialize", "serialise", "pack", "encode", "write", "tobuffer", "marshal", "build" }
local MOD_W = { "serial", "packet", "network", "buffer", "byte", "net", "squash", "blink", "bytenet", "marshal", "replion", "remote" }

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
	name = "PacketCracker", tab = "Packets", requires = {},
	load = function(ctx)
		local function C(k) ctx:Control(k) end
		local decMap, encMap = {}, {}
		local encoded = nil

		local gFind = ctx:Groupbox("1. Find Serializer", "left")
		gFind:AddDropdown("pcDecoder", { Text = "Decoder (str->data)", Values = {}, Multi = false, AllowNull = true }); C("pcDecoder")
		gFind:AddDropdown("pcEncoder", { Text = "Encoder (data->str)", Values = {}, Multi = false, AllowNull = true }); C("pcEncoder")
		local lblFind = gFind:AddLabel("Scan to find serializer funcs.", true)

		local function matchAny(s, set) s = s:lower() for _, w in ipairs(set) do if s:find(w, 1, true) then return true end end return false end
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
		end):AddToolTip("Finds serialize/deserialize functions in the GC + serializer-named modules. Also try the Closure Scanner (Spy tab) -> dump the combat function's upvalues to find the exact one.")

		-- ===== Decode =====
		local gDec = ctx:Groupbox("2. Decode captured packet", "right")
		local lblDec = gDec:AddLabel("Capture a packet with Remote Spy first.", true)
		gDec:AddButton("Decode Spy's Last Packet", function()
			local fn = decMap[Options.pcDecoder.Value]
			if not fn then Library:Notify("Pick a decoder (Scan first)"); return end
			local pkt = Bridge and Bridge.SpyLastPacket
			if type(pkt) ~= "string" then Library:Notify("No captured packet -- run Remote Spy + do the action"); return end
			local ok, res = pcall(fn, pkt)
			if not ok then pcall(function() lblDec:SetText("Decode failed:\n" .. tostring(res):sub(1, 100)) end); Library:Notify("Decode failed (try another decoder)"); return end
			-- render decoded fields with the shared SimpleSpy-grade serializer (reconstructable Lua)
			local out = (Bridge and Bridge.Serialize) and Bridge.Serialize(res) or tostring(res)
			writeOut("packet_decoded_" .. tostring(game.PlaceId) .. ".txt", "decoder: " .. Options.pcDecoder.Value .. "\npacket len: " .. #pkt .. "\nraw: " .. hexPreview(pkt) .. "\n\n" .. out)
			pcall(function() lblDec:SetText("Decoded:\n" .. out:sub(1, 200)) end)
			Library:Notify("Decoded -> file (see fields)")
		end):AddToolTip("Runs the chosen decoder on the last binary packet the Remote Spy captured, revealing its real fields (rendered as reconstructable Lua). Try each decoder until one returns a table.")

		-- ===== Encode + fire =====
		local gEnc = ctx:Groupbox("3. Forge + fire", "right")
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
			if not (typeof(r) == "Instance") then Library:Notify("No remote -- capture one with Remote Spy"); return end
			local m = (Bridge and Bridge.SpyLastMethod) or "FireServer"
			pcall(function()
				if m == "InvokeServer" then r:InvokeServer(encoded) else r:FireServer(encoded) end
			end)
			Library:Notify("Fired forged packet at " .. r.Name)
		end):AddToolTip("Fires your forged packet through the remote the Remote Spy last saw (e.g. PHit / CreateProjectile).")
		gEnc:AddLabel("Loop: Spy captures PHit -> Decode to see\nfields -> change the target/id -> Encode ->\nFire. Uses the game's own serializer so it's\nvalid. Experimental + game-specific.", true)

		pluginCleanup = function() end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
