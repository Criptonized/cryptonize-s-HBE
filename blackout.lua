-- CryptsHBE plugin: Blackout (anti-detection)
-- ============================================================================
-- A fast "show nothing incriminating" layer. Blackout hides EVERY cheat visual
-- (ESP/chams/FOV/hitbox via the Streamer flags + the menu + all executor GUIs)
-- so your screen looks like vanilla gameplay -- or, optionally, a full black
-- overlay. Auto-Blackout watches the screen for anti-cheat words and fires it +
-- kills risky features. UI cloak keeps the menu under gethui() (a container the
-- game's own scripts can't enumerate). No game writes -- pure local hiding.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lPlayer = Players.LocalPlayer
local Bridge = getgenv().CryptsHBE
local pluginCleanup = nil

-- Risky toggles auto-disabled when a flag is caught (nil-guarded; unloaded ones skip).
local RISKY = { "bbAutoBlock", "bbWalkEnabled", "bbGhostCamLock", "bbArrowPredict", "aimbotEnabled",
	"triggerEnabled", "saEnabled", "saHook", "extenderToggled", "silentMeleeEnabled", "weaponForceAuto",
	"weaponAutoFire", "sniffActive", "bbAutoBlock" }
local DEFAULT_WORDS = "invalid,cheat,exploit,ban,kick,teleport,detected,suspended,hack,banned,flagged"

return {
	name = "Blackout", tab = "Blackout", requires = {},
	load = function(ctx)
		local function C(k) ctx:Control(k) end
		local guiParent = (Bridge.getSafeGuiParent and Bridge.getSafeGuiParent()) or game:GetService("CoreGui")

		-- full-black overlay in its OWN ScreenGui so the hide-sweep can skip it
		local overlayGui = Instance.new("ScreenGui")
		overlayGui.Name = "_bo" .. tostring(math.random(10000, 99999))
		overlayGui.IgnoreGuiInset = true
		overlayGui.ResetOnSpawn = false
		overlayGui.DisplayOrder = 2000000000
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1); frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BackgroundTransparency = 0; frame.BorderSizePixel = 0; frame.Parent = overlayGui
		overlayGui.Enabled = false
		pcall(function() overlayGui.Parent = guiParent end)

		local gMain = ctx:Groupbox("Blackout", "left")
		local lblState = gMain:AddLabel("Blackout: off", true)
		gMain:AddToggle("blackoutOverlay", { Text = "Full black overlay", Default = false, Tooltip = "Also drop an opaque black screen (vs. just hiding the cheat visuals so the screen looks vanilla). (Default: OFF)" }); C("blackoutOverlay")

		-- Enable/disable every executor GUI (gethui children = executor-only, safe to sweep) +
		-- the Linoria menu explicitly. Skips the overlay so it can stay up.
		local function setExecGuisEnabled(on)
			pcall(function()
				local ok, hui = pcall(function() return gethui and gethui() end)
				if ok and hui then
					for _, g in ipairs(hui:GetChildren()) do
						if g ~= overlayGui and (g:IsA("ScreenGui") or g:IsA("GuiBase2d")) then pcall(function() g.Enabled = on end) end
					end
				end
			end)
			pcall(function() if Library and Library.ScreenGui then Library.ScreenGui.Enabled = on end end)
		end

		local blackoutOn, savedS = false, nil
		local function setBlackout(on)
			blackoutOn = on
			local S = Bridge.Streamer
			if on then
				if S then savedS = { S.hideESP, S.hideChams, S.hideFOV, S.hideHitbox }; S.hideESP, S.hideChams, S.hideFOV, S.hideHitbox = true, true, true, true end
				setExecGuisEnabled(false)
				if Toggles.blackoutOverlay and Toggles.blackoutOverlay.Value then overlayGui.Enabled = true end
			else
				if S and savedS then S.hideESP, S.hideChams, S.hideFOV, S.hideHitbox = savedS[1], savedS[2], savedS[3], savedS[4]; savedS = nil end
				setExecGuisEnabled(true)
				overlayGui.Enabled = false
			end
			pcall(function() lblState:SetText("Blackout: " .. (on and "ON (key/button restores)" or "off")) end)
		end
		getgenv().CryptsHBE.TriggerBlackout = function(v) pcall(function() setBlackout(v and true or false) end) end

		gMain:AddButton("Blackout Now", function() setBlackout(not blackoutOn) end):AddToolTip("Toggle: hide all cheat visuals + menu (+ optional black screen). Press again (or the key) to restore.")
		if Bridge and Bridge.AddKeybind then
			pcall(function() Bridge:AddKeybind("blackoutKey", "Blackout", "Insert", "Toggle", function() setBlackout(not blackoutOn) end) end)
		end

		-- ===== Auto-Blackout on flag =====
		local gAuto = ctx:Groupbox("Auto-Blackout", "right")
		gAuto:AddToggle("blackoutAuto", { Text = "Auto on anti-cheat flag", Default = false, Tooltip = "Watch the screen for anti-cheat words; on a match, blackout + disable risky features. (Default: OFF)" }); C("blackoutAuto")
		gAuto:AddInput("blackoutWords", { Text = "Flag words", Default = DEFAULT_WORDS, Finished = true, Tooltip = "Comma-separated words that trigger auto-blackout." }); C("blackoutWords")
		local lblAuto = gAuto:AddLabel("Watching: off", true)
		local function disableRisky()
			for _, k in ipairs(RISKY) do pcall(function() if Toggles[k] then Toggles[k]:SetValue(false) end end) end
		end
		local function wordList()
			local t = {}
			for w in tostring((Options.blackoutWords and Options.blackoutWords.Value) or DEFAULT_WORDS):gmatch("[^,]+") do
				w = w:gsub("%s+", ""):lower(); if #w > 0 then t[#t + 1] = w end
			end
			return t
		end
		local wasFlagged, lastScan = false, 0
		ctx:Connect(RunService.Heartbeat, function()
			if not (Toggles.blackoutAuto and Toggles.blackoutAuto.Value) then return end
			local now = tick(); if now - lastScan < 0.4 then return end; lastScan = now
			local pg = lPlayer:FindFirstChildOfClass("PlayerGui"); if not pg then return end
			local words = wordList()
			local hitWord = nil
			pcall(function()
				for _, d in ipairs(pg:GetDescendants()) do
					if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible and type(d.Text) == "string" and #d.Text > 2 then
						local s = d.Text:lower()
						for _, w in ipairs(words) do if s:find(w, 1, true) then hitWord = w; break end end
					end
					if hitWord then break end
				end
			end)
			if hitWord then
				if not wasFlagged then
					wasFlagged = true
					if not blackoutOn then setBlackout(true) end
					disableRisky()
					Library:Notify("Auto-Blackout: '" .. hitWord .. "' detected")
				end
				pcall(function() lblAuto:SetText("FLAGGED ('" .. hitWord .. "')") end)
			else
				wasFlagged = false
				pcall(function() lblAuto:SetText("Watching: ON") end)
			end
		end)

		-- ===== UI cloak (gethui) =====
		local gCloak = ctx:Groupbox("UI Cloak", "right")
		local lblCloak = gCloak:AddLabel("Menu parent: ?", true)
		gCloak:AddButton("Cloak UI (gethui)", function()
			local ok, hui = pcall(function() return gethui and gethui() end)
			if not (ok and hui) then Library:Notify("gethui unavailable on this executor"); return end
			pcall(function() if Library and Library.ScreenGui and Library.ScreenGui.Parent ~= hui then Library.ScreenGui.Parent = hui end end)
			pcall(function() if overlayGui.Parent ~= hui then overlayGui.Parent = hui end end)
			Library:Notify("UI cloaked under gethui")
		end):AddToolTip("Reparent the menu (+ overlay) under gethui() so the game's scripts can't find it in PlayerGui. (Drawings already use getSafeGuiParent -> gethui.)")
		local lastP = 0
		ctx:Connect(RunService.Heartbeat, function()
			local now = tick(); if now - lastP < 1 then return end; lastP = now
			pcall(function()
				local p = Library and Library.ScreenGui and Library.ScreenGui.Parent
				lblCloak:SetText("Menu parent: " .. (p and p.ClassName or "n/a"))
			end)
		end)

		pluginCleanup = function()
			pcall(function() if blackoutOn then setBlackout(false) end end)
			pcall(function() overlayGui:Destroy() end)
			pcall(function() getgenv().CryptsHBE.TriggerBlackout = nil end)
			pcall(function() if Bridge and Bridge.ClearKeybind then Bridge:ClearKeybind("blackoutKey") end end)
		end
	end,
	unload = function() if pluginCleanup then pcall(pluginCleanup); pluginCleanup = nil end end,
}
