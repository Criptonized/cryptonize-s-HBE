-- CryptsHBE plugin: Value Editor
-- ============================================================================
-- "It's all just changing values." A universal value picker: scan a scope (or CLICK a
-- number on your HUD -- ammo, speed, currency -- and it finds the value(s) behind it),
-- pick one, and Set or Hold it to anything. No per-stat feature needed.
--
-- This version is built around ONE workflow: find the value, change it, and let the
-- script TELL YOU if it stuck (read-back) instead of guessing whether it's server-side.
--   * Inspect Mode  -- hover any HUD element; it outlines what you're pointing at and
--     shows its path + the number(s) in it (like a browser inspector). Capture it in one
--     click -- no more "no number under the cursor".
--   * Highlight     -- the selected value's instance is outlined (3D part OR GUI element)
--     so you can SEE what you're editing.
--   * Read-back     -- after Set/Hold it re-reads the value: "stuck", "REVERTED (server-
--     side)", or "clamped" -- so you know in one test whether changing it actually works.
--   * Label fallback-- if a HUD number has no backing value (display-only text), it still
--     lists the label so you know it's cosmetic/server-pushed.
-- CLIENT-SIDE: a held value only "wins" if the game reads it live and trusts the client.
-- ============================================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Workspace = workspace
local lPlayer = Players.LocalPlayer
local pluginCleanup = nil

local function isNum(d)
	return d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue")
end
local function approx(a, b)
	if type(a) ~= "number" or type(b) ~= "number" then return a == b end
	return math.abs(a - b) <= math.max(0.5, math.abs(b) * 0.01)
end
local function numFromText(txt)
	local s = tostring(txt):gsub(",", "")            -- 1,234 -> 1234
	return tonumber(s:match("%-?%d+%.?%d*"))
end

-- Map a value's NAME to the dedicated plugin that can act on that KIND of value, so the
-- inspector can hint "this is better handled by X" instead of just editing it raw. Only
-- suggests a plugin that's actually registered; matching a "handled here" category returns nil.
local SUGGEST = {
	{ words = { "ammo", "mag", "clip", "round", "reserve", "bullet", "shell" }, plugin = "InfAmmo", note = "hold ammo full" },
	{ words = { "windup", "winddown", "firerate", "cooldown", "recoil", "reload", "spread", "burst" }, plugin = "TREK", note = "config-stat / fire rate" },
	{ words = { "cash", "money", "coin", "credit", "score", "kill", "gold", "gem", "token", "point", "xp", "bounty" }, plugin = "Economy", note = "detect / farm points" },
	{ words = { "speed", "throttle", "torque", "velocity", "accel", "gear", "rpm", "chassis" }, plugin = "Vehicle", note = "vehicle tuning" },
	{ words = { "stamina", "energy", "sprint", "breath", "endurance", "oxygen", "fatigue" }, plugin = "World", note = "infinite stamina" },
	{ words = { "build", "progress", "construct", "stage" }, plugin = "Engineer", note = "instant build" },
}
local function suggestPlugin(name)
	local ln = tostring(name):lower()
	for _, s in ipairs(SUGGEST) do
		for _, w in ipairs(s.words) do
			if ln:find(w, 1, true) then
				local B = getgenv().CryptsHBE
				if s.plugin and B and B.PluginSources and B.PluginSources[s.plugin] then return s.plugin, s.note end
				return nil
			end
		end
	end
	return nil
end

return {
	name = "Values", tab = "Values", requires = {},
	load = function(ctx)
		local Bridge = getgenv().CryptsHBE
		local scanG = ctx:Groupbox("Value Editor", "left")
		local setG  = ctx:Groupbox("Set / Hold", "left")
		local pickG = ctx:Groupbox("Pick from HUD", "right")

		local found = {}        -- key -> { fld, rate, reason, inst }
		local selField = nil
		local selInst = nil
		local lastHold = 0

		-- ===== overlay for GUI/part highlighting (web-inspector style) =====
		local guiParent = (Bridge and Bridge.getSafeGuiParent and Bridge.getSafeGuiParent()) or game:GetService("CoreGui")
		local overlay = ctx:Track(Instance.new("ScreenGui"))
		overlay.Name = "CryptsHBE_VEOverlay"
		overlay.ResetOnSpawn = false
		overlay.IgnoreGuiInset = true   -- match GuiObject.AbsolutePosition (true screen px)
		overlay.DisplayOrder = 9
		pcall(function() overlay.Parent = guiParent end)
		local function mkBox(color)
			local f = Instance.new("Frame")
			f.BackgroundTransparency = 1; f.BorderSizePixel = 0; f.Visible = false; f.Parent = overlay
			local s = Instance.new("UIStroke"); s.Color = color; s.Thickness = 2; s.Parent = f
			return f
		end
		local hoverBox = mkBox(Color3.fromRGB(80, 200, 255))
		local selBox   = mkBox(Color3.fromRGB(70, 220, 90))
		local hoverTag = Instance.new("TextLabel")
		hoverTag.BackgroundColor3 = Color3.fromRGB(15, 15, 18); hoverTag.BackgroundTransparency = 0.15
		hoverTag.TextColor3 = Color3.fromRGB(120, 220, 255); hoverTag.TextSize = 13; hoverTag.Font = Enum.Font.Code
		hoverTag.BorderSizePixel = 0; hoverTag.Visible = false; hoverTag.AutomaticSize = Enum.AutomaticSize.XY
		hoverTag.Parent = overlay
		local partHL = ctx:Track(Instance.new("Highlight"))
		partHL.FillColor = Color3.fromRGB(70, 220, 90); partHL.FillTransparency = 0.6
		partHL.OutlineColor = Color3.fromRGB(120, 255, 140); partHL.Enabled = false
		pcall(function() partHL.Parent = overlay end)
		local function boxTo(frame, obj)
			local ok = pcall(function()
				local ap, as = obj.AbsolutePosition, obj.AbsoluteSize
				frame.Position = UDim2.fromOffset(ap.X, ap.Y)
				frame.Size = UDim2.fromOffset(as.X, as.Y)
				frame.Visible = true
			end)
			if not ok then frame.Visible = false end
		end

		-- ===== detectability rating (kept; feeds colour + reason) =====
		local RATE_COLOR = { green = Color3.fromRGB(70, 220, 90), yellow = Color3.fromRGB(245, 215, 60), red = Color3.fromRGB(235, 70, 70) }
		local RATE_SYM   = { green = "+ ", yellow = "? ", red = "! " }
		local AC_PROPS = { "walkspeed", "jumppower", "jumpheight", "hipheight", "gravity", "maxhealth", "health" }
		local function rateField(name, inst)
			local ok, watched = pcall(function() return Bridge and Bridge.isWatched and Bridge.isWatched(name) end)
			if ok and watched then return "red", "anti-cheat watches this name (deep probe)" end
			local ln = tostring(name):lower()
			for _, w in ipairs(AC_PROPS) do if ln:find(w, 1, true) then return "red", "server-validated stat" end end
			local path = ""; pcall(function() path = inst:GetFullName():lower() end)
			if path:find("leaderstats", 1, true) then return "yellow", "leaderstats -- server-replicated" end
			if path:find("playergui", 1, true) or path:find("coregui", 1, true) then return "red", "GUI text -- usually display-only" end
			local mine = false
			pcall(function() mine = (lPlayer.Character ~= nil and inst:IsDescendantOf(lPlayer.Character)) or inst:IsDescendantOf(lPlayer) end)
			if mine then return "green", "client-side (yours)" end
			return "yellow", "shared/server-side -- may revert"
		end
		local function tint(lbl, rate)
			local color = RATE_COLOR[rate] or Color3.fromRGB(235, 235, 235)
			pcall(function()
				local direct = rawget(lbl, "TextLabel") or rawget(lbl, "Label") or rawget(lbl, "Instance")
				if typeof(direct) == "Instance" and direct:IsA("TextLabel") then direct.TextColor3 = color; return end
				for _, k in ipairs({ "Holder", "Container", "TextLabel", "Instance" }) do
					local h = rawget(lbl, k)
					if typeof(h) == "Instance" then
						if h:IsA("TextLabel") then h.TextColor3 = color end
						for _, d in ipairs(h:GetDescendants()) do if d:IsA("TextLabel") then d.TextColor3 = color end end
					end
				end
			end)
		end

		-- ===== field abstractions =====
		local function fVal(v) return { read = function() return v.Value end, write = function(n) pcall(function() v.Value = n end) end, alive = function() return v.Parent ~= nil end, path = v:GetFullName(), inst = v } end
		local function fAttr(i, a) return { read = function() return i:GetAttribute(a) end, write = function(n) pcall(function() i:SetAttribute(a, n) end) end, alive = function() return i.Parent ~= nil end, path = i:GetFullName() .. " @" .. a, inst = i } end
		-- display-only label: writing only changes the on-screen text (cosmetic) so you know
		-- it's not a real value -- read-back will show whether the game even keeps your text.
		local function fLabel(o) return { read = function() return numFromText(o.Text) end, write = function(n) pcall(function() o.Text = tostring(n) end) end, alive = function() return o.Parent ~= nil end, path = o:GetFullName() .. " (TEXT)", inst = o } end

		local function collect(root, q, matchNum, out, capN)
			if not root then return end
			pcall(function()
				local n = 0
				for _, d in ipairs(root:GetDescendants()) do
					n = n + 1; if n > capN then break end
					if isNum(d) then
						local ok = (q == "" or d.Name:lower():find(q, 1, true)) and (not matchNum or math.abs((d.Value or 0) - matchNum) < 1.0)
						if ok then out[#out + 1] = { name = d.Name, fld = fVal(d), inst = d } end
					end
					pcall(function()
						for an, av in pairs(d:GetAttributes()) do
							if type(av) == "number" and (q == "" or an:lower():find(q, 1, true)) and (not matchNum or math.abs(av - matchNum) < 1.0) then
								out[#out + 1] = { name = d.Name .. "@" .. an, fld = fAttr(d, an), inst = d }
							end
						end
					end)
				end
			end)
		end

		local function seatedVehicle()
			local c = lPlayer.Character
			local hum = c and c:FindFirstChildWhichIsA("Humanoid")
			local seat = hum and hum.SeatPart
			return (seat and seat.Parent) and (seat:FindFirstAncestorWhichIsA("Model") or seat) or nil
		end
		local function rootsForScope()
			local s = (Options.veScope and Options.veScope.Value) or "Held Tool"
			local c = lPlayer.Character
			if s == "Held Tool" then return { c and c:FindFirstChildWhichIsA("Tool") } end
			if s == "Character" then return { c } end
			if s == "Backpack" then return { lPlayer:FindFirstChild("Backpack") } end
			if s == "Player + leaderstats" then return { lPlayer:FindFirstChild("Backpack"), lPlayer:FindFirstChild("leaderstats"), lPlayer:FindFirstChildOfClass("PlayerGui"), c } end
			if s == "Seated Vehicle" then return { seatedVehicle() } end
			if s == "Workspace (heavy)" then return { Workspace } end
			return { c }
		end

		scanG:AddDropdown("veScope", { Text = "Scope", Values = { "Held Tool", "Character", "Backpack", "Player + leaderstats", "Seated Vehicle", "Workspace (heavy)" }, Default = "Held Tool", Multi = false, AllowNull = false }); ctx:Control("veScope")
		scanG:AddInput("veSearch", { Text = "Name contains", Default = "", Tooltip = "Filter found values by name (e.g. ammo, speed). Empty = all." }); ctx:Control("veSearch")
		scanG:AddDropdown("veFound", { Text = "Found values", Values = {}, Multi = false, AllowNull = true, Tooltip = "Scan or Pick first, then choose a value to edit." }); ctx:Control("veFound")
		local veInfo = scanG:AddLabel("Scan, or use Pick from HUD.", true)

		local function highlightSelected()
			selBox.Visible = false; partHL.Enabled = false
			if not selInst then return end
			pcall(function()
				if selInst:IsA("GuiObject") then
					boxTo(selBox, selInst)
				elseif selInst:IsA("BasePart") then
					partHL.Adornee = selInst; partHL.Enabled = true
				elseif selInst:IsA("Model") then
					partHL.Adornee = selInst; partHL.Enabled = true
				end
			end)
		end

		local function buildList(items)
			found = {}
			local entries = {}
			local cg, cy, cr = 0, 0, 0
			for _, it in ipairs(items) do
				local cur = it.fld.read()
				local rate, reason = rateField(it.name, it.inst)
				if rate == "green" then cg = cg + 1 elseif rate == "red" then cr = cr + 1 else cy = cy + 1 end
				local base = (RATE_SYM[rate] or "") .. it.name .. " = " .. tostring(cur)
				local key, i2 = base, 2
				while found[key] do key = base .. " #" .. i2; i2 = i2 + 1 end
				found[key] = { fld = it.fld, rate = rate, reason = reason, inst = it.inst }; entries[#entries + 1] = key
			end
			table.sort(entries)
			Options.veFound.Values = entries
			pcall(function() Options.veFound:SetValues() end)
			pcall(function() tint(veInfo, nil) end)
			pcall(function() veInfo:SetText(("%d found:  +%d safe   ?%d test   !%d watched/server\nPick one -- colour shows how likely it works/is safe."):format(#entries, cg, cy, cr)) end)
		end

		scanG:AddButton("Scan Values", function()
			local items, q = {}, (Options.veSearch.Value or ""):lower()
			local cap = ((Options.veScope.Value or "") == "Workspace (heavy)") and 40000 or 8000
			for _, r in ipairs(rootsForScope()) do collect(r, q, nil, items, cap) end
			buildList(items)
		end):AddToolTip("List numeric values in the chosen scope (filtered by the name box).")

		Options.veFound:OnChanged(function()
			local k = Options.veFound.Value
			local entry = k and found[k] or nil
			selField = entry and entry.fld or nil
			selInst = entry and entry.inst or nil
			highlightSelected()
			if entry then
				local sp, snote = suggestPlugin(selInst and selInst.Name or selField.path)
				pcall(function() veInfo:SetText(("Selected: %s\nCurrent: %s\nRating: %s -- %s%s"):format(
					selField.path, tostring(selField.read()), entry.rate:upper(), entry.reason,
					sp and ("\nBetter handled by: " .. sp .. " plugin (" .. snote .. ")") or "")) end)
				pcall(function() tint(veInfo, entry.rate) end)
			end
		end)

		-- ===== HUD hit-test =====
		-- Returns the most-specific (smallest) TextLabel/TextButton under a screen point,
		-- with a number in its text. Tries the engine helper first, then a manual scan so
		-- it still works when GetGuiObjectsAtPosition misses (the "no number" bug).
		local function inset() local ok, i = pcall(function() return GuiService:GetGuiInset() end); return ok and i or Vector2.new(0, 36) end
		local function objAt(px, py)
			local pg = lPlayer:FindFirstChildOfClass("PlayerGui")
			local ins = inset()
			if pg then
				for _, oy in ipairs({ py - ins.Y, py }) do
					local ok, list = pcall(function() return pg:GetGuiObjectsAtPosition(px, oy) end)
					if ok and list then
						for _, o in ipairs(list) do
							if (o:IsA("TextLabel") or o:IsA("TextButton")) and numFromText(o.Text) then return o end
						end
					end
				end
			end
			-- manual fallback: smallest visible text element whose bounds contain the cursor.
			-- PlayerGui ONLY (the game HUD) -- never CoreGui/gethui, so the CryptsHBE menu +
			-- our own overlay can't be picked. That's what makes "move to the button without
			-- losing your target" work: over the menu, objAt returns nil and the lock holds.
			local best, bestArea = nil, math.huge
			if pg then
				pcall(function()
					for _, o in ipairs(pg:GetDescendants()) do
						if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Visible and numFromText(o.Text) then
							local ap, as = o.AbsolutePosition, o.AbsoluteSize
							if as.X > 0 and as.Y > 0 and px >= ap.X and px <= ap.X + as.X and py >= ap.Y and py <= ap.Y + as.Y then
								local area = as.X * as.Y
								if area < bestArea then best, bestArea = o, area end
							end
						end
					end
				end)
			end
			return best
		end

		local function searchNumber(num, srcObj)
			local items = {}
			collect(lPlayer.Character, "", num, items, 8000)
			collect(lPlayer:FindFirstChild("Backpack"), "", num, items, 8000)
			collect(lPlayer:FindFirstChild("leaderstats"), "", num, items, 4000)
			collect(lPlayer:FindFirstChildOfClass("PlayerGui"), "", num, items, 8000)
			collect(seatedVehicle(), "", num, items, 8000)
			collect(Workspace, "", num, items, 40000)
			-- if nothing backs the HUD number, still surface the label so you know it's text-only
			if #items == 0 and srcObj then items[#items + 1] = { name = srcObj.Name .. " [label]", fld = fLabel(srcObj), inst = srcObj } end
			buildList(items)
			Library:Notify("HUD " .. tostring(num) .. " -> " .. (#items > 0 and (#items .. " match(es)") or "0 (display-only text)"))
		end

		-- ===== Pick from HUD (hover-based; no stray clicks) =====
		pickG:AddLabel("Turn on Inspect, HOVER a number on your HUD\n(it locks even when you move to the button),\nthen Capture (button or bind).", true)
		pickG:AddToggle("veInspect", { Text = "Inspect Mode (hover)", Default = false, Tooltip = "Outlines the HUD element under your cursor (animated) + shows its path/number. The\ntarget LOCKS when you move onto the menu, so Capture grabs what you were pointing at. (Default: OFF)" }); ctx:Control("veInspect")
		local lblHover = pickG:AddLabel("Hover: -", true)
		local lastHover = nil
		local function captureHovered()
			if not (lastHover and lastHover.Parent) then Library:Notify("Nothing locked -- turn on Inspect Mode + point at a number"); return end
			local num = numFromText(lastHover.Text)
			if not num then Library:Notify("Locked element has no number"); return end
			searchNumber(num, lastHover)
		end
		pickG:AddButton("Capture Hovered", captureHovered):AddToolTip("Search for the number in the currently LOCKED element (the last HUD number you hovered).")
		-- Bind a key so you can capture WITHOUT moving the cursor at all: hover, press the key.
		pickG:AddLabel("Capture Key"):AddKeyPicker("veCaptureKey", { Default = "C", Mode = "Hold", Text = "Capture HUD value", Callback = function(state) if state then captureHovered() end end })

		-- ===== Set / Hold (with read-back) =====
		setG:AddInput("veSetValue", { Text = "New Value", Default = "999", Tooltip = "Number to write to the selected value." }); ctx:Control("veSetValue")
		local lblVerify = setG:AddLabel("Read-back: -", true)
		local function newVal() return tonumber(Options.veSetValue.Value) end
		local pendingVerify = nil
		setG:AddButton("Set Once", function()
			local v = newVal()
			if not selField then Library:Notify("Pick a value first"); return end
			if not v then Library:Notify("New Value isn't a number"); return end
			local old = selField.read()
			selField.write(v)
			pendingVerify = { target = v, old = old, at = tick() + 0.2 }
			Library:Notify("Set " .. selField.path .. " -> " .. v)
		end):AddToolTip("Write New Value once, then read it back to see if it stuck.")
		setG:AddToggle("veHold", { Text = "Hold Value", Default = false, Tooltip = "Keep writing New Value every tick so the game can't reset it. Read-back shows if the server is fighting you. (Default: OFF)" }); ctx:Control("veHold")

		local holdBaseline, holdReverts, holdPrime, prevHold = nil, 0, true, false

		ctx:Connect(RunService.Heartbeat, function()
			-- Set Once read-back
			if pendingVerify and tick() >= pendingVerify.at then
				local rb = selField and selField.read()
				local msg
				if type(rb) ~= "number" then msg = "n/a"
				elseif approx(rb, pendingVerify.target) then msg = "stuck (= " .. tostring(rb) .. ")"
				elseif approx(rb, pendingVerify.old) then msg = "REVERTED to " .. tostring(rb) .. " -- server-side"
				else msg = "clamped to " .. tostring(rb) end
				pcall(function() lblVerify:SetText("Set read-back: " .. msg) end)
				pendingVerify = nil
			end
			-- Hold
			local holdOn = Toggles.veHold and Toggles.veHold.Value and selField
			if holdOn and not prevHold then holdReverts = 0; holdPrime = true; holdBaseline = nil end
			prevHold = holdOn and true or false
			if not holdOn then return end
			local now = tick(); if now - lastHold < 0.1 then return end; lastHold = now
			if selField.alive and not selField.alive() then pcall(function() lblVerify:SetText("Hold: value object gone (respawn?)") end); return end
			local cur = selField.read()
			local v = newVal()
			if v then
				-- count a revert: between our writes the value drifted back off-target
				if not holdPrime and type(cur) == "number" and not approx(cur, v) then holdReverts = holdReverts + 1 end
				selField.write(v)
				holdPrime = false
				pcall(function()
					lblVerify:SetText(("Hold: now %s -> %s  %s"):format(
						tostring(cur), tostring(v),
						holdReverts > 0 and ("server reverting (x" .. holdReverts .. ")") or "holding OK"))
				end)
			end
		end)

		-- ===== inspect-mode hover loop (throttled) =====
		local lastInspect = 0
		ctx:Connect(RunService.RenderStepped, function()
			if not (Toggles.veInspect and Toggles.veInspect.Value) then
				hoverBox.Visible = false; hoverTag.Visible = false; lastHover = nil
				return
			end
			local now = tick(); if now - lastInspect < 0.04 then return end; lastInspect = now
			local pos = UserInputService:GetMouseLocation()
			local o = objAt(pos.X, pos.Y)
			-- Only update the lock when we're actually over a HUD number. Over the menu objAt
			-- returns nil, so lastHover STAYS -- you can move to Capture without losing it.
			if o then lastHover = o end
			-- animated outline colour so it's obviously a live inspector (was static).
			local hue = (tick() * 0.6) % 1
			local col = Color3.fromHSV(hue, 0.85, 1)
			local target = lastHover
			if target and target.Parent then
				boxTo(hoverBox, target)
				pcall(function() if hoverBox:FindFirstChildOfClass("UIStroke") then hoverBox:FindFirstChildOfClass("UIStroke").Color = col end end)
				local sp, snote = suggestPlugin(target.Name)
				pcall(function()
					local locked = (o == nil)   -- cursor has left the element (e.g. on the menu)
					local hint = sp and ("\n   \u{2192} " .. sp .. " plugin: " .. snote) or ""
					hoverTag.Text = (locked and " [LOCKED] " or " ") .. target.Name .. "  = " .. tostring(numFromText(target.Text)) .. " " .. hint
					hoverTag.TextColor3 = col
					local ap = target.AbsolutePosition
					hoverTag.Position = UDim2.fromOffset(ap.X, math.max(0, ap.Y - (sp and 32 or 18)))
					hoverTag.Visible = true
				end)
				pcall(function() lblHover:SetText((o == nil and "LOCKED: " or "Hover: ") .. target.Name .. " = " .. tostring(numFromText(target.Text)) .. (sp and ("  [\u{2192} " .. sp .. "]") or "")) end)
			else
				hoverBox.Visible = false; hoverTag.Visible = false
				pcall(function() lblHover:SetText("Hover: point at a HUD number") end)
			end
		end)

		-- keep the selected GUI box following its element (HUD moves/animates)
		ctx:Connect(RunService.RenderStepped, function()
			if selInst and selBox.Visible then pcall(function() if selInst:IsA("GuiObject") then boxTo(selBox, selInst) end end) end
		end)

		local howG = ctx:Groupbox("How to Use", "right")
		howG:AddLabel(
			"Change ANY value -- ammo, speed, money.\n\n" ..
			"FIND IT:\n" ..
			"  - Inspect Mode ON, hover the number on\n" ..
			"    your HUD (it outlines what you point\n" ..
			"    at), then 'Capture Hovered'. OR\n" ..
			"  - (it LOCKS on the menu), then Capture\n   Hovered or the Capture Key (C). OR\n" ..
			"  - set Scope + name box, 'Scan Values'.\n\n" ..
			"CHANGE IT: pick from 'Found values' (the\n" ..
			"selected one gets outlined), type New\n" ..
			"Value, 'Set Once' or 'Hold Value'.\n\n" ..
			"DID IT WORK? watch Read-back:\n" ..
			"  stuck    = it took -- you're done.\n" ..
			"  REVERTED = server overwrote it (server-\n" ..
			"             side; client can't win).\n" ..
			"  clamped  = capped (e.g. ammo MaxValue).\n\n" ..
			"Too many matches? change the number in-\n" ..
			"game (fire/drive) and Pick again.\n\n" ..
			"COLOUR = detectability: +green yours,\n" ..
			"?yellow shared, !red server/AC-watched.",
			true)

		pluginCleanup = function()
			pcall(function() if Toggles.veHold then Toggles.veHold:SetValue(false) end end)
			pcall(function() hoverBox.Visible = false; selBox.Visible = false; hoverTag.Visible = false; partHL.Enabled = false end)
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
