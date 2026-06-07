if getgenv().FurryHBEInjected then
	return
end
getgenv().FurryHBEInjected = true
getgenv().FurryHBELoaded = false

if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- NOTE: MT-Api is intentionally NOT loaded. It works by hooking the game
-- metatable's __namecall metamethod, which is exactly what namecall-instance
-- detectors flag. This script no longer uses any MT-Api hooks (AddGetHook/
-- AddSetHook); hitbox changes are tracked via part.Changed:Connect and applied
-- with direct property writes, so MT-Api is unnecessary.

-- Try multiple mirrors for LinoriaLib
local Library = nil
local SaveManager = nil
local linoriaMirrors = {
	"https://raw.githubusercontent.com/RectangularObject/LinoriaLib/main/Library.lua",
	"https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua",
	"https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"
}

for _, url in ipairs(linoriaMirrors) do
	pcall(function()
		if not Library then
			Library = loadstring(game:HttpGet(url))()
		end
	end)
	if Library then break end
end

if not Library then
	error("Failed to load LinoriaLib from all mirrors")
end

local saveManagerMirrors = {
	"https://raw.githubusercontent.com/RectangularObject/LinoriaLib/main/addons/SaveManager.lua",
	"https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/SaveManager.lua"
}

for _, url in ipairs(saveManagerMirrors) do
	pcall(function()
		if not SaveManager then
			SaveManager = loadstring(game:HttpGet(url))()
		end
	end)
	if SaveManager then break end
end
if not SaveManager then
	error("Failed to load SaveManager from all mirrors")
end

SaveManager:SetLibrary(Library)
SaveManager:SetFolder("FurryHBE")

-- Make every tooltip wrap to multiple short lines so long descriptions can't run
-- off the screen. We word-wrap the text before LinoriaLib builds the tooltip.
-- (Patched before any UI is created so it applies to all controls. Best-effort.)
pcall(function()
	local orig = Library.AddToolTip
	if type(orig) ~= "function" then return end
	local function wrap(s, width)
		s = tostring(s)
		if #s <= width and not s:find("\n") then return s end
		local out, line = {}, ""
		for word in s:gmatch("%S+") do
			if #line + #word + 1 > width then
				table.insert(out, line); line = word
			else
				line = (line == "") and word or (line .. " " .. word)
			end
		end
		if line ~= "" then table.insert(out, line) end
		return table.concat(out, "\n")
	end
	Library.AddToolTip = function(self, info, hover)
		if type(info) == "string" then info = wrap(info, 44) end
		return orig(self, info, hover)
	end
end)

-- GUI-based Drawing fallback for Potassium
local DrawingFallback = {}
DrawingFallback.__index = DrawingFallback

local DrawingGui = Instance.new("ScreenGui")
DrawingGui.Name = "DrawingFallback"
DrawingGui.ResetOnSpawn = false
DrawingGui.Parent = game:GetService("CoreGui")

function DrawingFallback.new(type)
	local self = setmetatable({}, DrawingFallback)
	self.type = type
	self.visible = false
	self.color = Color3.fromRGB(255, 255, 255)
	self.thickness = 1
	self.filled = false
	self.position = Vector2.new(0, 0)
	self.size = Vector2.new(0, 0)
	self.radius = 0
	self.text = ""
	self.center = false
	self.outline = false
	self.outlineColor = Color3.fromRGB(0, 0, 0)
	
	-- Create GUI element based on type
	if type == "Circle" then
		self.element = Instance.new("Frame")
		self.element.Size = UDim2.new(0, 1, 0, 1)
		self.element.BackgroundColor3 = self.color
		self.element.BackgroundTransparency = 1
		self.element.BorderSizePixel = 0
		self.element.Parent = DrawingGui
		
		self.border = Instance.new("UIStroke")
		self.border.Color = self.color
		self.border.Thickness = self.thickness
		self.border.Parent = self.element
	elseif type == "Text" then
		self.element = Instance.new("TextLabel")
		self.element.Text = self.text
		self.element.TextColor3 = self.color
		self.element.BackgroundTransparency = 1
		self.element.BorderSizePixel = 0
		self.element.TextSize = 14
		self.element.Parent = DrawingGui
		
		if self.outline then
			self.border = Instance.new("UIStroke")
			self.border.Color = self.outlineColor
			self.border.Thickness = 1
			self.border.Parent = self.element
		end
	elseif type == "Square" then
		self.element = Instance.new("Frame")
		self.element.BackgroundColor3 = self.color
		self.element.BorderSizePixel = 0
		self.element.Parent = DrawingGui
		
		if self.outline then
			self.border = Instance.new("UIStroke")
			self.border.Color = self.outlineColor
			self.border.Thickness = self.thickness
			self.border.Parent = self.element
		end
	elseif type == "Line" then
		self.element = Instance.new("Frame")
		self.element.BackgroundColor3 = self.color
		self.element.BorderSizePixel = 0
		self.element.Parent = DrawingGui
	end
	
	return self
end

function DrawingFallback:Remove()
	if self.element then
		self.element:Destroy()
	end
end

function DrawingFallback:Update()
	if not self.element then return end
	
	self.element.Visible = self.visible
	
	if self.type == "Circle" then
		self.element.Size = UDim2.new(0, self.radius * 2, 0, self.radius * 2)
		self.element.Position = UDim2.new(0, self.position.X - self.radius, 0, self.position.Y - self.radius)
		self.border.Color = self.color
		self.border.Thickness = self.thickness
		self.element.BackgroundTransparency = self.filled and 0 or 1
		if self.filled then
			self.element.BackgroundColor3 = self.color
		end
	elseif self.type == "Text" then
		self.element.Text = self.text
		self.element.TextColor3 = self.color
		self.element.Position = UDim2.new(0, self.position.X, 0, self.position.Y)
		self.element.TextSize = self.size
		if self.center then
			self.element.AnchorPoint = Vector2.new(0.5, 0.5)
		else
			self.element.AnchorPoint = Vector2.new(0, 0)
		end
		if self.border then
			self.border.Color = self.outlineColor
		end
	elseif self.type == "Square" then
		self.element.Size = UDim2.new(0, self.size.X, 0, self.size.Y)
		self.element.Position = UDim2.new(0, self.position.X, 0, self.position.Y)
		self.element.BackgroundColor3 = self.color
		self.element.BackgroundTransparency = self.filled and 0 or 1
		if self.border then
			self.border.Color = self.outlineColor
			self.border.Thickness = self.thickness
		end
	elseif self.type == "Line" then
		-- Line requires from/to positions, simplified for fallback
		self.element.Size = UDim2.new(0, self.thickness, 0, self.size.Y)
		self.element.Position = UDim2.new(0, self.position.X, 0, self.position.Y)
		self.element.BackgroundColor3 = self.color
	end
end

-- Check if Drawing library is available, otherwise use fallback
local DrawingAvailable = pcall(function()
	local probe = Drawing.new("Circle")
	probe:Remove()
end)
if DrawingAvailable then
	-- Use native Drawing
	DrawingFallback.new = Drawing.new
else
	-- Use GUI fallback: map public PascalCase props to internal lowercase storage.
	-- These metamethods go on DrawingFallback itself, which is the metatable of every
	-- instance created via setmetatable({}, DrawingFallback) -- NOT on getmetatable(DrawingFallback).
	local propMap = {
		Visible = "visible", Color = "color", Thickness = "thickness",
		Filled = "filled", Position = "position", Size = "size",
		Radius = "radius", Text = "text", Center = "center",
		Outline = "outline", OutlineColor = "outlineColor",
	}

	DrawingFallback.__index = function(self, key)
		local mapped = propMap[key]
		if mapped then
			return rawget(self, mapped)
		end
		return rawget(DrawingFallback, key)
	end

	DrawingFallback.__newindex = function(self, key, value)
		local mapped = propMap[key]
		if mapped then
			rawset(self, mapped, value)
			DrawingFallback.Update(self)
			return
		end
		rawset(self, key, value)
	end
end

-- Cached services
local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Camera = Workspace.CurrentCamera
local WorldToViewportPoint = Camera.WorldToViewportPoint
local lPlayer = Players.LocalPlayer

-- Global tables
local players = {}
local entities = {}
local teamModule = nil
local weaponCache = {}
local whitelist = {}
local priorityList = {}
local activeExtensions = 0
local lastUpdateTime = 0
local currentTarget = nil
local targetSwitchTime = 0
local worldParts = {}            -- [BasePart] = { Size, Transparency, Massless, CanCollide } (scanned ground/walls/vehicles)
local extendAllowed = nil        -- set of players allowed to extend this tick (closest-targets mode), or nil = all
local eligibleSince = {}         -- [player] = tick() when they first became eligible (humanization delay)
local lastStatusUpdate = 0       -- throttle for the status labels

-- Forward declarations (Lua does not hoist locals; these are assigned later but
-- referenced earlier by UI callbacks, so they must exist as upvalues up front)
local runUpdatePlayers
local resetAllPlayers
local resetWorldParts
local getDistanceToPlayer
local addPlayer
local flashUIElement
local updateConsoleTab
local partScannerHighlight
local partScannerProgressCircle
local partScannerFillCircle
local DEFAULT_BODY_PARTS = { "Custom Part", "Head", "HumanoidRootPart", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local addBodyPart, removeBodyPart, isDefaultBodyPart, partListContains

-- Stable wrapper: the UI is built (and binds updatePlayers to ~40 :OnChanged
-- callbacks and the Force-Update key) BEFORE the heavy implementation exists.
-- Arguments are passed by value, so binding the real function directly would
-- capture nil. This wrapper is non-nil from the start and forwards to the real
-- body (runUpdatePlayers) once it's assigned further down.
local function updatePlayers(...)
	if runUpdatePlayers then
		return runUpdatePlayers(...)
	end
end

-- Error logging system
local errorLog = {}
local uiElementStatus = {}
local uiElementReferences = {}

local lastLogKey, lastLogTime = nil, 0
local function logError(context, err, uiElement)
	local now = tick()
	local key = tostring(context) .. "|" .. tostring(err)
	-- Throttle identical errors. The ESP/update loops run every frame, so a single
	-- recurring failure used to flood the log, spam warnings, and fire the UI flash
	-- (which spawns 3 tasks each) ~60x/sec -- the real cause of the freeze/lag, the
	-- runaway error text clipping the UI, and Clear Errors "glitching".
	if key == lastLogKey and (now - lastLogTime) < 1 then return end
	lastLogKey, lastLogTime = key, now

	table.insert(errorLog, { context = context, error = tostring(err), time = now, uiElement = uiElement })
	while #errorLog > 50 do table.remove(errorLog, 1) end  -- cap so it can't grow unbounded

	warn("[FurryHBE Error] " .. context .. ": " .. tostring(err))
	if uiElement and uiElementReferences[uiElement] then
		pcall(flashUIElement, uiElement)
	end
	if updateConsoleTab then pcall(updateConsoleTab) end
end

local function safeCall(context, fn, ...)
	local success, result = pcall(fn, ...)
	if not success then
		logError(context, result)
		return nil, result
	end
	return result
end

-- Visual feedback system for UI elements
function flashUIElement(elementName)
	if not uiElementReferences[elementName] then return end
	
	local element = uiElementReferences[elementName]
	local originalColor = element.BackgroundColor3 or Color3.fromRGB(30, 30, 30)
	
	-- Flash red 3 times
	for i = 1, 3 do
		task.spawn(function()
			if element.BackgroundColor3 then
				element.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
				task.wait(0.1)
				element.BackgroundColor3 = originalColor
				task.wait(0.1)
			end
		end)
	end
	
	uiElementStatus[elementName] = {
		lastError = tick(),
		errorCount = (uiElementStatus[elementName] and uiElementStatus[elementName].errorCount or 0) + 1
	}
end

local function registerUIElement(name, element)
	uiElementReferences[name] = element
	uiElementStatus[name] = {
		errorCount = 0,
		lastError = nil
	}
end

-- Team detection module (modularized)
local TeamDetection = {
	[718936923] = function(player, lPlayer, playerChar, lPlayerChar) -- Neighborhood War
		if not lPlayerChar or not playerChar or not playerChar:FindFirstChild("HumanoidRootPart") then return true end
		return lPlayerChar.HumanoidRootPart.Color == playerChar.HumanoidRootPart.Color
	end,
	[633284182] = function(player, lPlayer) -- Fireteam
		if not player:FindFirstChild("PlayerData") or not player.PlayerData:FindFirstChild("TeamValue") then return true end
		return lPlayer.PlayerData.TeamValue.Value == player.PlayerData.TeamValue.Value
	end,
	[2029250188] = function(player, lPlayer, playerChar, lPlayerChar) -- Q-Clash
		if not lPlayerChar or not playerChar then return true end
		return lPlayerChar.Parent == playerChar.Parent
	end,
	[2978450615] = function(player, lPlayer) -- Paintball Reloaded
		local success, result = pcall(function()
			return getrenv()._G.PlayerProfiles.Data[lPlayer.Name].Team == getrenv()._G.PlayerProfiles.Data[player.Name].Team
		end)
		return success and result or false
	end,
	[1934496708] = function(player, lPlayer) -- Project: SCP
		if Workspace.FriendlyFire.Value then return false end
		return (not player.Team or player.Team.Name == "LOBBY" or lPlayer.Team.Name == "LOBBY" or player.Team.Name == "Admin" or lPlayer.Team == player.Team) or
		teamModule[lPlayer.Team.Name] == teamModule[player.Team.Name] or
		((teamModule[lPlayer.Team.Name] == "CI" and teamModule[player.Team.Name] == "CD") or
		(teamModule[player.Team.Name] == "CI" and teamModule[lPlayer.Team.Name] == "CD"))
	end,
	[2622527242] = function(player, lPlayer) -- SCP rBreach
		if not player.Team or player.Team.Name == "Intro" or player.Team.Name == "Spectator" or player.Team.Name == "Not Playing" or lPlayer.Team == player.Team then return true end
		local lPlayerTeamName = lPlayer.Team.Name
		local playerTeamName = player.Team.Name
		local selfTeam, playerTeam
		
		local teamMappings = {
			["Class-D Personnel"] = "Chads",
			["Chaos Insurgency"] = "Chads",
			["Facility Personnel"] = "Crayon Eaters",
			["Security Department"] = "Crayon Eaters",
			["Mobile Task Force"] = "Crayon Eaters",
			["SCPs"] = "Menaces to Society",
			["Serpent's Hand"] = "Menaces to Society",
			["Global Occult Coalition"] = "Who?",
			["Unusual Incidents Unit"] = "Who2?"
		}
		
		selfTeam = teamMappings[lPlayerTeamName]
		playerTeam = teamMappings[playerTeamName]
		
		if selfTeam == "Who2?" or playerTeam == "Who2?" then
			if selfTeam == "Crayon Eaters" or playerTeam == "Crayon Eaters" or selfTeam == "Who?" or playerTeam == "Who?" then
				return true
			end
		end
		return selfTeam == playerTeam
	end,
	[8770868695] = function(player, lPlayer, playerChar, lPlayerChar) -- Anomalous Activities: First Contact
		if not lPlayerChar or not playerChar or not player.Team or player.Team.Name == "Dead" or player.Team.Name == "Inactive" then return true end
		return lPlayerChar.Parent == playerChar.Parent
	end,
	[5884786982] = function(player, lPlayer, playerChar, lPlayerChar) -- Escape The Darkness
		if not lPlayerChar or not playerChar then return true end
		return lPlayerChar.Name ~= "Killer" and playerChar.Name ~= "Killer"
	end,
	[2162282815] = function(player, lPlayer) -- Rush Point
		if not player:FindFirstChild("SelectedTeam") then return true end
		return player.SelectedTeam.Value == lPlayer.SelectedTeam.Value
	end,
	[1240644540] = function(player, lPlayer) -- Vampire Hunters 3
		if not teamModule or not teamModule.IsPlayerSurvivor then return true end
		return teamModule.IsPlayerSurvivor(nil, player) == true and teamModule.IsPlayerSurvivor(nil, lPlayer) == true
	end,
	[10236714118] = function(player, lPlayer) -- Return of Humans vs Zombies
		if not player:FindFirstChild("PlayerData") or not player.PlayerData:FindFirstChild("Team") then return true end
		return lPlayer.PlayerData.Team.Value == player.PlayerData.Team.Value
	end
}

-- Game-specific initialization
local function initializeGameSpecific()
	if game.GameId == 504234221 then -- Vampire Hunters 3
		local success, result = pcall(function()
			return require(ReplicatedStorage.Scripts.Modules.PlayerModule)
		end)
		if success then teamModule = result end
	end
	if game.GameId == 1934496708 then -- Project: SCP
		local success, result = pcall(function()
			return require(Workspace:WaitForChild("Teams"))
		end)
		if success then teamModule = result end
	end
end
initializeGameSpecific()

-- Weapon extraction system
local function extractWeapons()
	weaponCache = {}
	local function scanContainer(container)
		for _, item in pairs(container:GetDescendants()) do
			if item:IsA("Tool") or item:IsA("HopperBin") or item.ClassName:find("Gun") or item.ClassName:find("Weapon") then
				if item.Name ~= "" and not table.find(weaponCache, item.Name) then
					table.insert(weaponCache, item.Name)
				end
			end
		end
	end
	
	-- Scan workspace and replicated storage
	scanContainer(Workspace)
	scanContainer(ReplicatedStorage)
	
	-- Scan player inventories
	for _, player in pairs(Players:GetPlayers()) do
		if player.Character then
			scanContainer(player.Character)
		end
		if player:FindFirstChild("Backpack") then
			scanContainer(player.Backpack)
		end
	end
	
	table.sort(weaponCache)
	return weaponCache
end

-- FOV Circle Drawing (with fallback)
local fovCircle = DrawingFallback.new("Circle")
fovCircle.Thickness = 1
fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.Filled = false
fovCircle.Visible = false

-- Cleanup function
local function cleanup()
	for player, playerData in pairs(players) do
		if playerData.DeleteVisuals then
			pcall(function() playerData:DeleteVisuals() end)
		end
	end
	fovCircle:Remove()
	
	-- Cleanup part scanner
	if partScannerHighlight then
		pcall(function() partScannerHighlight:Destroy() end)
		partScannerHighlight = nil
	end
	partScannerProgressCircle:Remove()
	if partScannerFillCircle then partScannerFillCircle:Remove() end
	RunService:UnbindFromRenderStep("partScanner")
	if resetWorldParts then resetWorldParts() end

	-- Tear down any registered add-ons (Precision, Streamer, ...).
	local bridge = getgenv().FurryHBE
	if bridge and bridge.Addons then
		for name, addon in pairs(bridge.Addons) do
			if type(addon.onUnload) == "function" then
				pcall(addon.onUnload)
			end
		end
		bridge.Addons = {}
	end

	getgenv().FurryHBELoaded = false
end

-- Window setup (with failsafe)
local windowConfig = {
	Title = "cryptonize's library",
	Center = true,
	AutoShow = true,
	TabPadding = 8,
	MenuFadeTime = 0.2,
}

local mainWindow = safeCall("UI Creation", function()
	return Library:CreateWindow(windowConfig)
end)

if not mainWindow then
	warn("[FurryHBE] Failed to create main window, retrying...")
	task.wait(0.5)
	mainWindow = Library:CreateWindow(windowConfig)
end

-- Bridge: publish the internals that optional add-on presets (e.g. the
-- Precision module in testingv2.lua) need to attach to THIS window/library
-- instead of redefining their own. Without this, an add-on's
-- `getgenv().Library` / `mainWindow` / `DrawingFallback` are all nil and it
-- either silently returns or errors on the first line that touches them.
local Bridge = {
	Library = Library,
	SaveManager = SaveManager,
	DrawingFallback = DrawingFallback,
	mainWindow = mainWindow,
	Services = {
		Players = Players,
		RunService = RunService,
		Workspace = Workspace,
		ReplicatedStorage = ReplicatedStorage,
		UserInputService = UserInputService,
	},

	-- ----- Add-on coordination -------------------------------------------
	-- Registered add-on cleanup handlers, invoked by cleanup()/unload.
	Addons = {},
	-- Shared "hide visuals but keep functionality" flags. Render paths honor
	-- these every frame, so an add-on (e.g. Streamer Mode) just sets a flag
	-- instead of fighting the loop by poking each drawing's .Visible.
	Streamer = { hideESP = false, hideChams = false, hideFOV = false, hideHitbox = false },
	-- [player] = "addonName": claimed players are skipped by the main extender
	-- so an add-on (e.g. Precision) can own a target without the two fighting.
	Claims = {},
}

-- Register an add-on so it tears down with the main script. opts.onUnload runs
-- during cleanup()/Library unload. Returns the bridge for chaining.
function Bridge:RegisterAddon(name, opts)
	opts = opts or {}
	self.Addons[name] = opts
	return self
end

function Bridge:ClaimPlayer(player, addonName)
	if player then self.Claims[player] = addonName end
end
function Bridge:ReleasePlayer(player)
	if player then self.Claims[player] = nil end
end

getgenv().FurryHBE = Bridge
-- Convenience aliases some add-ons expect at the top level.
getgenv().Library = Library
getgenv().mainWindow = mainWindow
getgenv().DrawingFallback = DrawingFallback

-- ============================================================================
--  Shared hold-to-pick subsystem (mirrors the Part Scanner's click-and-hold
--  ring). Any add-on calls Bridge:StartHoldPick{ onPick = function(part) ... end,
--  filter = function(part) -> bool, color = Color3, duration = seconds }.
--  Aim at a part, hold left-click; a ring fills, and on completion onPick fires.
--  Right-click or a 20s timeout cancels.
-- ============================================================================
do
	local holdActive   = nil      -- current request opts, or nil when idle
	local holding      = false
	local holdStart    = 0
	local activatedAt  = 0
	local hoverPart    = nil
	local highlight    = nil

	local ring = DrawingFallback.new("Circle")
	ring.Thickness = 2; ring.Filled = false; ring.Color = Color3.fromRGB(255, 255, 255); ring.Visible = false
	local fill = DrawingFallback.new("Circle")
	fill.Thickness = 1; fill.Filled = true; fill.Color = Color3.fromRGB(0, 255, 0); fill.Visible = false

	local function clearHighlight()
		if highlight then pcall(function() highlight:Destroy() end); highlight = nil end
	end
	local function stop()
		holdActive = nil; holding = false; hoverPart = nil
		ring.Visible = false; fill.Visible = false
		clearHighlight()
	end

	local function rayUnderCursor()
		local cam = Workspace.CurrentCamera
		local mouse = lPlayer:GetMouse()
		local r = cam:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { lPlayer.Character }
		local res = Workspace:Raycast(r.Origin, r.Direction * 2000, params)
		return res and res.Instance or nil
	end

	function Bridge:StartHoldPick(opts)
		opts = opts or {}
		holdActive = opts
		holding = false
		holdStart = tick()
		activatedAt = tick()
		hoverPart = nil
		clearHighlight()
		if opts.notify ~= false then
			Library:Notify("Hold left-click on a part to select it (right-click cancels)")
		end
	end
	function Bridge:CancelHoldPick() stop() end

	RunService:BindToRenderStep("FurryHBE_HoldPick", Enum.RenderPriority.Last.Value + 2, function()
		if not holdActive then
			ring.Visible = false; fill.Visible = false
			return
		end
		-- Safety timeout so the picker never gets stuck on forever.
		if tick() - activatedAt > 20 then stop(); return end

		local part = rayUnderCursor()
		local valid = part ~= nil and (not holdActive.filter or holdActive.filter(part) == true)

		if part ~= hoverPart then
			hoverPart = part
			holdStart = tick()
			clearHighlight()
			if valid then
				local col = holdActive.color or Color3.fromRGB(0, 170, 255)
				highlight = Instance.new("Highlight")
				highlight.Adornee = part:FindFirstAncestorWhichIsA("Model") or part
				highlight.FillColor = col
				highlight.OutlineColor = col
				highlight.FillTransparency = 0.6
				highlight.OutlineTransparency = 0
				highlight.Parent = game:GetService("CoreGui")
			end
		end

		if not holding then holdStart = tick() end

		local mouse = lPlayer:GetMouse()
		local center = Vector2.new(mouse.X, mouse.Y)
		local maxR = 28
		local duration = holdActive.duration or 1.0

		if valid and holding then
			local progress = math.min((tick() - holdStart) / duration, 1)
			ring.Position = center; ring.Radius = maxR; ring.Filled = false
			ring.Color = Color3.fromRGB(255, 255, 255); ring.Visible = true
			fill.Position = center; fill.Radius = math.max(1, maxR * progress); fill.Filled = true
			fill.Color = Color3.fromRGB(math.floor(255 * (1 - progress)), math.floor(255 * progress), 0); fill.Visible = true
			if progress >= 1 then
				local cb = holdActive.onPick
				local picked = part
				stop()
				if cb then pcall(cb, picked) end
			end
		else
			ring.Visible = false; fill.Visible = false
		end
	end)

	-- Left mouse = hold to fill (ignore clicks the menu consumed). Right = cancel.
	UserInputService.InputBegan:Connect(function(input, gp)
		if not holdActive then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not gp then
			holding = true; holdStart = tick()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 and not gp then
			stop(); Library:Notify("Pick cancelled")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then holding = false end
	end)

	Bridge:RegisterAddon("HoldPick", {
		onUnload = function()
			pcall(stop)
			pcall(function() RunService:UnbindFromRenderStep("FurryHBE_HoldPick") end)
			pcall(function() ring:Remove() end)
			pcall(function() fill:Remove() end)
		end,
	})
end

-- Main Tab
local mainTab = mainWindow:AddTab("Main")
local hitboxGroupbox = mainTab:AddLeftGroupbox("Hitbox Settings")
local filterGroupbox = mainTab:AddLeftGroupbox("Filter Settings")
local antiDetectionGroupbox = mainTab:AddLeftGroupbox("Anti-Detection")
local ignoresGroupbox = mainTab:AddRightGroupbox("Ignores")
local statusGroupbox = mainTab:AddRightGroupbox("Status")

-- Master toggle. NOTE: AddToggle is a Groupbox method, NOT a Window method.
-- The previous version called mainWindow:AddToggle(...), which is nil and threw
-- immediately after CreateWindow -- that error aborted the rest of the script,
-- so the window appeared empty and no notification ever fired.
local suppressMasterNotify = true
local masterToggle = hitboxGroupbox:AddToggle("MasterToggle", { Text = "Master Toggle", Default = true, Tooltip = "Master on/off switch for the entire script" }):OnChanged(function()
	if Toggles.MasterToggle.Value then
		getgenv().FurryHBELoaded = true
		updatePlayers()
		if not suppressMasterNotify then Library:Notify("HBE Enabled") end
	else
		-- Restore everyone BEFORE halting the update loop, otherwise the loop
		-- never runs again to undo the extension and the visuals stay stuck on.
		if resetAllPlayers then resetAllPlayers() end
		if resetWorldParts then resetWorldParts() end
		getgenv().FurryHBELoaded = false
		if not suppressMasterNotify then Library:Notify("HBE Disabled") end
	end
end)
suppressMasterNotify = false
registerUIElement("MasterToggle", masterToggle)

-- Hitbox Settings
local extenderToggle = hitboxGroupbox:AddToggle("extenderToggled", { Text = "Enable Hitbox Extender", Default = false, Tooltip = "Toggle hitbox extension on/off" }):OnChanged(function()
	if Toggles.extenderToggled.Value then
		updatePlayers()
	else
		-- Immediately snap every part back to its real size/transparency/collision.
		if resetAllPlayers then resetAllPlayers() end
		if resetWorldParts then resetWorldParts() end
	end
end)
registerUIElement("extenderToggled", extenderToggle)
hitboxGroupbox:AddSlider("extenderSize", { Text = "Hitbox Size", Min = 2, Max = 100, Default = 10, Rounding = 1, Tooltip = "Base size for hitbox extension" }):OnChanged(updatePlayers)
hitboxGroupbox:AddDropdown("hitboxShape", { Text = "Hitbox Shape", AllowNull = false, Multi = false, Values = { "Cube", "Flat (disk)", "Tall (pillar)" }, Default = "Cube", Tooltip = "Cube = uniform; Flat = wide & short; Tall = narrow & tall" }):OnChanged(updatePlayers)

-- Part Scanner
local partScannerToggled = false
local partScannerHolding = false
partScannerHighlight = nil
local partScannerProgress = 0
local partScannerHoverTime = 0
local partScannerHoverDuration = 1.2 -- seconds to HOLD before add/remove
local partScannerCurrentPart = nil
-- Outer ring (the target boundary)
partScannerProgressCircle = DrawingFallback.new("Circle")
partScannerProgressCircle.Thickness = 2
partScannerProgressCircle.Color = Color3.fromRGB(255, 255, 255)
partScannerProgressCircle.Filled = false
partScannerProgressCircle.Visible = false
-- Inner filled circle that grows from 0 -> ring radius as you hold (the progress)
partScannerFillCircle = DrawingFallback.new("Circle")
partScannerFillCircle.Thickness = 1
partScannerFillCircle.Color = Color3.fromRGB(0, 255, 0)
partScannerFillCircle.Filled = true
partScannerFillCircle.Visible = false

local partScannerButton = hitboxGroupbox:AddToggle("partScannerToggled", { Text = "Part Scanner Mode", Default = false, Tooltip = "Click and HOLD on a part to add it. Hold again on a scanned part to remove it." }):OnChanged(function(value)
	partScannerToggled = value
	partScannerHolding = false
	partScannerProgress = 0
	partScannerCurrentPart = nil
	if value then
		Library:Notify("Part Scanner: click & hold on a part to add it; hold on a scanned part to remove it")
	else
		-- Cleanup
		if partScannerHighlight then
			partScannerHighlight:Destroy()
			partScannerHighlight = nil
		end
		partScannerProgressCircle.Visible = false
		partScannerFillCircle.Visible = false
		Library:Notify("Part Scanner Mode disabled")
	end
end)
hitboxGroupbox:AddToggle("partScannerAllowWorld", { Text = "Allow World Parts", Default = false, Tooltip = "Let the scanner pick up non-character parts (ground, walls, vehicles). Off = only character/humanoid parts." })
hitboxGroupbox:AddButton("Clear Scanned Parts", function()
	-- Snapshot first; removeBodyPart mutates the Values list as it goes.
	local toRemove = {}
	for _, v in ipairs(Options.extenderPartList.Values) do
		if not isDefaultBodyPart(v) then
			table.insert(toRemove, v)
		end
	end
	for _, v in ipairs(toRemove) do
		removeBodyPart(v)
	end
	updatePlayers()
	Library:Notify("Cleared " .. #toRemove .. " scanned part(s)")
end):AddToolTip("Remove every part added via the Part Scanner (keeps the default body parts)")
hitboxGroupbox:AddSlider("extenderTransparency", { Text = "Transparency", Min = 0, Max = 1, Default = 0.5, Rounding = 2, Tooltip = "Transparency of extended hitboxes (0 = visible, 1 = invisible). (Default: 0.5)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddToggle("outlineMode", { Text = "Outline Only", Default = false, Tooltip = "Hide the enlarged hitbox block and show only a coloured wireframe outline at the hitbox size (the part is still extended for hit-reg). (Default: OFF)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddLabel("Outline Color"):AddColorPicker("outlineColor", { Title = "Outline Color", Default = Color3.fromRGB(255, 0, 0) })
hitboxGroupbox:AddSlider("outlineTransparency", { Text = "Outline Transparency", Min = 0, Max = 1, Default = 0, Rounding = 2, Tooltip = "Transparency of the outline lines (0 = solid). (Default: 0)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddInput("customPartName", { Text = "Custom Part Name", Default = "HeadHB", Tooltip = "Name for custom body part matching" }):OnChanged(updatePlayers)
hitboxGroupbox:AddDropdown("extenderPartList", { Text = "Body Parts", AllowNull = true, Multi = true, Values = table.clone(DEFAULT_BODY_PARTS), Default = "HumanoidRootPart", Tooltip = "Select which body parts to extend" }):OnChanged(updatePlayers)

-- Part-specific sizing
hitboxGroupbox:AddToggle("partSpecificSizing", { Text = "Part-Specific Sizing", Default = false, Tooltip = "Enable different sizes for different body parts" }):OnChanged(updatePlayers)
hitboxGroupbox:AddSlider("headSize", { Text = "Head Size", Min = 2, Max = 100, Default = 10, Rounding = 1, Tooltip = "Size for head hitbox" }):OnChanged(updatePlayers)
hitboxGroupbox:AddSlider("torsoSize", { Text = "Torso Size", Min = 2, Max = 100, Default = 10, Rounding = 1, Tooltip = "Size for torso hitbox" }):OnChanged(updatePlayers)
hitboxGroupbox:AddSlider("limbSize", { Text = "Limb Size", Min = 2, Max = 100, Default = 8, Rounding = 1, Tooltip = "Size for arm/leg hitboxes" }):OnChanged(updatePlayers)

-- Dynamic sizing
hitboxGroupbox:AddToggle("dynamicSizing", { Text = "Dynamic Sizing", Default = false, Tooltip = "Scale hitbox based on distance to target" }):OnChanged(updatePlayers)
hitboxGroupbox:AddSlider("dynamicScalingFactor", { Text = "Scaling Factor", Min = 0.1, Max = 2, Default = 1, Rounding = 2, Tooltip = "How much to scale based on distance" }):OnChanged(updatePlayers)

-- Smooth transitions
hitboxGroupbox:AddToggle("smoothTransitions", { Text = "Smooth Transitions", Default = false, Tooltip = "Interpolate size changes smoothly" }):OnChanged(updatePlayers)
hitboxGroupbox:AddSlider("transitionSpeed", { Text = "Transition Speed", Min = 0.1, Max = 2, Default = 0.5, Rounding = 2, Tooltip = "Speed of size interpolation" }):OnChanged(updatePlayers)

-- Filter Settings
filterGroupbox:AddSlider("maxDistance", { Text = "Max Distance", Min = 0, Max = 1000, Default = 1000, Rounding = 1, Tooltip = "Maximum distance to extend/ESP players (0 = unlimited)" }):OnChanged(updatePlayers)
filterGroupbox:AddToggle("closestTargetsOnly", { Text = "Closest Targets Only", Default = false, Tooltip = "Only extend the nearest N players (more legit + better performance)" }):OnChanged(updatePlayers)
filterGroupbox:AddSlider("maxTargets", { Text = "Max Targets", Min = 1, Max = 10, Default = 1, Rounding = 0, Tooltip = "How many of the nearest players to extend when Closest Targets Only is on" }):OnChanged(updatePlayers)
filterGroupbox:AddToggle("fovFilterToggled", { Text = "FOV Filter", Default = false, Tooltip = "Only target players within FOV circle" }):OnChanged(updatePlayers)
filterGroupbox:AddSlider("fovSize", { Text = "FOV Size", Min = 10, Max = 500, Default = 100, Rounding = 1, Tooltip = "Radius of FOV circle" }):OnChanged(updatePlayers)
filterGroupbox:AddLabel("FOV Color"):AddColorPicker("fovColor", { Title = "FOV Color", Default = Color3.fromRGB(255, 255, 255) })
Options.fovColor:OnChanged(updatePlayers)
filterGroupbox:AddSlider("fovThickness", { Text = "FOV Thickness", Min = 1, Max = 5, Default = 1, Rounding = 1, Tooltip = "Thickness of FOV circle" }):OnChanged(updatePlayers)
filterGroupbox:AddToggle("autoExpandFOV", { Text = "Auto-Expand in FOV", Default = false, Tooltip = "Automatically expand hitbox when target is in FOV" }):OnChanged(updatePlayers)
filterGroupbox:AddToggle("weaponFilterToggled", { Text = "Weapon Filter", Default = false, Tooltip = "Ignore players holding specific weapons" }):OnChanged(updatePlayers)
filterGroupbox:AddButton("Extract Weapons", function()
	local weapons = extractWeapons()
	Options.weaponList.Values = weapons
	Options.weaponList:SetValues()
	Library:Notify("Extracted " .. #weapons .. " weapons")
end):AddToolTip("Extract all weapons from the game")
filterGroupbox:AddDropdown("weaponList", { Text = "Ignored Weapons", AllowNull = true, Multi = true, Values = {}, Tooltip = "Select weapons to ignore" }):OnChanged(updatePlayers)

-- Anti-Detection
antiDetectionGroupbox:AddToggle("randomizationToggled", { Text = "Randomization", Default = false, Tooltip = "Add slight randomization to hitbox sizes" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddSlider("randomizationAmount", { Text = "Random Amount", Min = 0, Max = 5, Default = 1, Rounding = 1, Tooltip = "Maximum random size variation. (Default: 1)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("smartJitter", { Text = "Smart Jitter (sine)", Default = false, Tooltip = "Use a smooth sine wave for the size jitter instead of random snapping (harder to fingerprint). (Default: OFF)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddSlider("maxPlausibleMult", { Text = "Max Plausible x", Min = 0, Max = 50, Default = 0, Rounding = 1, Tooltip = "Cap the hitbox at this multiple of the part's real size. 0 = no cap. Keeps extension believable. (Default: 0)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("humanizationToggled", { Text = "Humanization Delay", Default = false, Tooltip = "Add delay between target switches" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddSlider("humanizationDelay", { Text = "Delay (ms)", Min = 0, Max = 1000, Default = 100, Rounding = 1, Tooltip = "Delay in milliseconds between target switches" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("legitModeToggled", { Text = "Legit Mode", Default = false, Tooltip = "Only extend when crosshair is near target" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddSlider("legitModeFOV", { Text = "Legit FOV", Min = 1, Max = 50, Default = 10, Rounding = 1, Tooltip = "FOV threshold for legit mode" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("autoOffWhenDead", { Text = "Auto-Off When Dead", Default = false, Tooltip = "Automatically stop extending while you are dead or spectating" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("seatDisableHBE", { Text = "Disable While Seated", Default = true, Tooltip = "Stop extending hitboxes while YOU sit in any seat (car/turret/etc).\nPrevents the in-vehicle freeze where players & cars look stuck.\nResumes automatically when you get out. (Default: ON)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("seatRadiusMode", { Text = "Seated: Nearby Only", Default = false, Tooltip = "When seated, only disable hitboxes for players within the radius below instead of everyone" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddSlider("seatRadius", { Text = "Seated Radius (studs)", Min = 5, Max = 200, Default = 30, Rounding = 1, Tooltip = "Radius used by 'Seated: Nearby Only'" }):OnChanged(updatePlayers)

-- Ignores
ignoresGroupbox:AddToggle("extenderSitCheck", { Text = "Ignore Sitting Players", Default = false, Tooltip = "Don't extend players who are sitting" }):OnChanged(updatePlayers)
ignoresGroupbox:AddToggle("extenderFFCheck", { Text = "Ignore Forcefielded Players", Default = false, Tooltip = "Don't extend players with forcefields" }):OnChanged(updatePlayers)
ignoresGroupbox:AddToggle("ignoreSelectedPlayersToggled", { Text = "Ignore Selected Players", Default = false, Tooltip = "Don't extend selected players" }):OnChanged(updatePlayers)
ignoresGroupbox:AddDropdown("ignorePlayerList", { Text = "Players", AllowNull = true, Multi = true, Values = {}, Tooltip = "Select players to ignore" }):OnChanged(updatePlayers)
ignoresGroupbox:AddToggle("ignoreOwnTeamToggled", { Text = "Ignore Own Team", Default = false, Tooltip = "Don't extend teammates" }):OnChanged(updatePlayers)
ignoresGroupbox:AddToggle("ignoreSelectedTeamsToggled", { Text = "Ignore Selected Teams", Default = false, Tooltip = "Don't extend selected teams" }):OnChanged(updatePlayers)
ignoresGroupbox:AddDropdown("ignoreTeamList", { Text = "Teams", AllowNull = true, Multi = true, Values = {}, Tooltip = "Select teams to ignore" }):OnChanged(updatePlayers)
ignoresGroupbox:AddToggle("collisionsToggled", { Text = "Enable Collisions", Default = false, Tooltip = "Keep collisions on extended hitboxes" }):OnChanged(updatePlayers)

-- Status
local statusActiveLabel = statusGroupbox:AddLabel("Active Players: 0")
local statusExtendedLabel = statusGroupbox:AddLabel("Extended: 0")
local statusWhitelistLabel = statusGroupbox:AddLabel("Whitelisted: 0")
local statusPriorityLabel = statusGroupbox:AddLabel("Priority: 0")
local statusErrorsLabel = statusGroupbox:AddLabel("Errors: 0")

-- ESP Tab
local espTab = mainWindow:AddTab("ESP")
local espNameGroupbox = espTab:AddLeftGroupbox("Name ESP")
local espChamsGroupbox = espTab:AddLeftGroupbox("Chams")
local espAdvancedGroupbox = espTab:AddRightGroupbox("Advanced ESP")
local espFilterGroupbox = espTab:AddRightGroupbox("ESP Filters")

-- Name ESP
local espNameToggle = espNameGroupbox:AddToggle("espNameToggled", { Text = "Enable Name ESP", Default = false, Tooltip = "Show player names" }):AddColorPicker("espNameColor1", { Title = "Fill Color", Default = Color3.fromRGB(255, 255, 255) }):AddColorPicker("espNameColor2", { Title = "Outline Color", Default = Color3.fromRGB(0, 0, 0) })
registerUIElement("espNameToggled", espNameToggle)
Toggles.espNameToggled:OnChanged(updatePlayers)
Options.espNameColor1:OnChanged(updatePlayers)
Options.espNameColor2:OnChanged(updatePlayers)
espNameGroupbox:AddToggle("espNameUseTeamColor", { Text = "Use Team Color", Default = false, Tooltip = "Use team color for name ESP" }):OnChanged(updatePlayers)
espNameGroupbox:AddDropdown("espNameType", { Text = "Name Type", AllowNull = false, Multi = false, Values = { "Display Name", "Account Name", "Both (Display + @User)" }, Default = "Display Name", Tooltip = "Which name to show.\nBoth = DisplayName (@AccountName). (Default: Display Name)" }):OnChanged(updatePlayers)
espNameGroupbox:AddToggle("espDistanceToggled", { Text = "Show Distance", Default = false, Tooltip = "Show distance to player" }):OnChanged(updatePlayers)
espNameGroupbox:AddToggle("espTeamToggled", { Text = "Show Team Name", Default = false, Tooltip = "Show a tiny team-name subscript below the player's name" }):OnChanged(updatePlayers)
espNameGroupbox:AddSlider("espNameSize", { Text = "Name Text Size", Min = 8, Max = 36, Default = 14, Rounding = 0, Tooltip = "Font size of ESP names. Smaller = far less overlap when players clump together." })

-- Chams
local espChamsToggle = espChamsGroupbox:AddToggle("espHighlightToggled", { Text = "Enable Chams", Default = false, Tooltip = "Show player highlights" }):AddColorPicker("espHighlightColor1", { Title = "Fill Color", Default = Color3.fromRGB(0, 0, 0) }):AddColorPicker("espHighlightColor2", { Title = "Outline Color", Default = Color3.fromRGB(0, 0, 0) })
registerUIElement("espHighlightToggled", espChamsToggle)
Toggles.espHighlightToggled:OnChanged(updatePlayers)
Options.espHighlightColor1:OnChanged(updatePlayers)
Options.espHighlightColor2:OnChanged(updatePlayers)
espChamsGroupbox:AddToggle("espHighlightUseTeamColor", { Text = "Use Team Color", Default = false, Tooltip = "Use team color for chams" }):OnChanged(updatePlayers)
espChamsGroupbox:AddDropdown("espHighlightDepthMode", { Text = "Depth Mode", AllowNull = false, Multi = false, Values = { "Occluded", "AlwaysOnTop" }, Default = "Occluded", Tooltip = "How chams render through walls" }):OnChanged(updatePlayers)
espChamsGroupbox:AddSlider("espHighlightFillTransparency", { Text = "Fill Transparency", Min = 0, Max = 1, Default = 0.5, Rounding = 2, Tooltip = "Transparency of chams fill" }):OnChanged(updatePlayers)
espChamsGroupbox:AddSlider("espHighlightOutlineTransparency", { Text = "Outline Transparency", Min = 0, Max = 1, Default = 0, Rounding = 2, Tooltip = "Transparency of chams outline" }):OnChanged(updatePlayers)
espChamsGroupbox:AddToggle("espChamsGlow", { Text = "Glow Pulse", Default = false, Tooltip = "Animate the chams outline so it pulses/glows. (Default: OFF)" })

-- Advanced ESP
espAdvancedGroupbox:AddToggle("espHealthBarToggled", { Text = "Health Bar", Default = false, Tooltip = "Show health bar above player" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddToggle("espHealthTextToggled", { Text = "Health Text", Default = false, Tooltip = "Show numeric health next to the health bar" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddToggle("espBoxToggled", { Text = "2D Box", Default = false, Tooltip = "Show 2D box around player" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddSlider("espBoxScale", { Text = "2D Box Size", Min = 0.3, Max = 1.5, Default = 0.85, Rounding = 2, Tooltip = "Scale of the 2D box. Lower = tighter boxes that overlap less when players bunch up." })
espAdvancedGroupbox:AddToggle("espAntiOverlap", { Text = "Anti-Overlap Names", Default = true, Tooltip = "Nudge ESP names apart when players clump together so they don't render on top of each other." })
espAdvancedGroupbox:AddToggle("espRainbow", { Text = "Rainbow ESP", Default = false, Tooltip = "Cycle every player's ESP (name/box/tracer/skeleton/chams) through a rainbow. (Default: OFF)" })
espAdvancedGroupbox:AddSlider("espRainbowSpeed", { Text = "Rainbow Speed", Min = 0.1, Max = 3, Default = 0.7, Rounding = 2, Tooltip = "How fast the rainbow cycles. (Default: 0.7)" })
espAdvancedGroupbox:AddSlider("espThickness", { Text = "Line Thickness", Min = 1, Max = 5, Default = 1, Rounding = 1, Tooltip = "Thickness of box/tracer/skeleton lines. (Default: 1)" })
espAdvancedGroupbox:AddToggle("espDistanceFade", { Text = "Distance Fade", Default = false, Tooltip = "Fade ESP out as players get farther away (relative to ESP Max Distance). Native Drawing only. (Default: OFF)" })
espAdvancedGroupbox:AddSlider("espOverlapGap", { Text = "Overlap Spacing", Min = 8, Max = 40, Default = 16, Rounding = 0, Tooltip = "Vertical pixels enforced between names by Anti-Overlap." })
espAdvancedGroupbox:AddToggle("espSkeletonToggled", { Text = "Skeleton ESP", Default = false, Tooltip = "Draw lines between the character's bones" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddToggle("espOffscreenToggled", { Text = "Off-Screen Markers", Default = false, Tooltip = "Show an edge marker pointing toward off-screen players" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddToggle("espTracerToggled", { Text = "Tracer Lines", Default = false, Tooltip = "Show lines from screen center to players" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddLabel("Tracer Color"):AddColorPicker("espTracerColor", { Title = "Tracer Color", Default = Color3.fromRGB(255, 0, 0) })
Options.espTracerColor:OnChanged(updatePlayers)

-- ESP Filters
espFilterGroupbox:AddSlider("espMaxDistance", { Text = "Max Distance", Min = 0, Max = 1000, Default = 1000, Rounding = 1, Tooltip = "Maximum distance for ESP (0 = unlimited)" }):OnChanged(updatePlayers)
espFilterGroupbox:AddToggle("espFOVFilter", { Text = "FOV Filter", Default = false, Tooltip = "Only ESP players within FOV" }):OnChanged(updatePlayers)

-- Whitelist Tab
local whitelistTab = mainWindow:AddTab("Whitelist")
local whitelistGroupbox = whitelistTab:AddLeftGroupbox("Player Whitelist")
local priorityGroupbox = whitelistTab:AddRightGroupbox("Priority Players")

whitelistGroupbox:AddButton("Refresh Player Lists", function()
	-- Ensure every current player appears in the whitelist/priority/ignore dropdowns.
	local added = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lPlayer then
			for _, listName in ipairs({ "whitelistPlayerList", "priorityPlayerList", "ignorePlayerList" }) do
				local list = Options[listName]
				if list and not table.find(list.Values, plr.Name) then
					table.insert(list.Values, plr.Name)
					list:SetValues()
					added = added + 1
				end
			end
		end
	end
	Library:Notify("Player lists refreshed (" .. added .. " entries added)")
end):AddToolTip("Re-sync the whitelist / priority / ignore dropdowns with everyone currently in the server")
whitelistGroupbox:AddDropdown("whitelistPlayerList", { Text = "Whitelisted Players", AllowNull = true, Multi = true, Values = {}, Tooltip = "Players whitelisted from HBE" }):OnChanged(updatePlayers)
whitelistGroupbox:AddToggle("espWhitelisted", { Text = "Keep ESP on Whitelisted", Default = true, Tooltip = "Whitelisted players keep their ESP; only their hitbox extension is skipped.\n(Default: ON)" })
local whitelistCountLabel = whitelistGroupbox:AddLabel("Whitelisted: 0")

-- Whitelist auto-persistence: saved to disk and restored on every execute, so you
-- never have to re-whitelist everyone again (no full config-save required). It also
-- re-applies when a whitelisted player rejoins the server.
local WL_FILE = "FurryHBE_Whitelist.json"
local savedWhitelist = {}
local function applyWhitelist()
	local list = Options.whitelistPlayerList
	if not list then return end
	local val = {}
	for _, n in ipairs(savedWhitelist) do
		if not table.find(list.Values, n) then table.insert(list.Values, n) end
		val[n] = true
	end
	list:SetValues()
	pcall(function() list:SetValue(val) end)
end
local function saveWhitelist()
	savedWhitelist = Options.whitelistPlayerList:GetActiveValues()
	if writefile then pcall(function() writefile(WL_FILE, game:GetService("HttpService"):JSONEncode(savedWhitelist)) end) end
end
pcall(function()
	if isfile and readfile and isfile(WL_FILE) then
		local ok, t = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(WL_FILE)) end)
		if ok and type(t) == "table" then savedWhitelist = t end
	end
end)
applyWhitelist()
Options.whitelistPlayerList:OnChanged(saveWhitelist)
Players.PlayerAdded:Connect(function() task.wait(0.25); pcall(applyWhitelist) end)

priorityGroupbox:AddToggle("prioritySystemToggled", { Text = "Enable Priority System", Default = false, Tooltip = "Always extend/ESP priority players" }):OnChanged(updatePlayers)
priorityGroupbox:AddDropdown("priorityPlayerList", { Text = "Priority Players", AllowNull = true, Multi = true, Values = {}, Tooltip = "High priority players" }):OnChanged(updatePlayers)
priorityGroupbox:AddToggle("priorityFlash", { Text = "Flash Priority Targets", Default = true, Tooltip = "Rainbow-flash every ESP element (name, box, tracer, skeleton, chams, off-screen marker) of priority players so they stand out" })
local priorityCountLabel = priorityGroupbox:AddLabel("Priority: 0")

-- Profiles Tab
local profilesTab = mainWindow:AddTab("Settings")
local profilesGroupbox = profilesTab:AddLeftGroupbox("Configuration Profiles")

local profiles = {
	["Aggressive"] = {
		extenderSize = 25,
		extenderTransparency = 0.3,
		dynamicSizing = false,
		randomizationToggled = false,
		legitModeToggled = false
	},
	["Stealth"] = {
		extenderSize = 8,
		extenderTransparency = 0.8,
		dynamicSizing = true,
		randomizationToggled = true,
		legitModeToggled = true
	},
	["Legit"] = {
		extenderSize = 5,
		extenderTransparency = 0.9,
		dynamicSizing = true,
		randomizationToggled = true,
		legitModeToggled = true
	}
}

profilesGroupbox:AddDropdown("profileSelect", { Text = "Select Profile", AllowNull = false, Multi = false, Values = {"Aggressive", "Stealth", "Legit"}, Default = "Aggressive", Tooltip = "Select a configuration profile" })
profilesGroupbox:AddButton("Load Profile", function()
	local profileName = Options.profileSelect.Value
	local profile = profiles[profileName]
	if profile then
		for option, value in pairs(profile) do
			-- Sliders/dropdowns live in Options; toggles live in Toggles.
			local control = Options[option] or Toggles[option]
			if control then
				control:SetValue(value)
			end
		end
		updatePlayers()
		Library:Notify("Loaded profile: " .. profileName)
	end
end):AddToolTip("Load selected profile settings")
-- Settings captured by a custom profile (mix of sliders/dropdowns + toggles).
local PROFILE_KEYS = {
	"extenderSize", "extenderTransparency", "hitboxShape", "maxDistance",
	"dynamicSizing", "randomizationToggled", "legitModeToggled",
	"partSpecificSizing", "smoothTransitions", "collisionsToggled",
}

profilesGroupbox:AddButton("Save Custom Profile", function()
	local snap = {}
	for _, k in ipairs(PROFILE_KEYS) do
		local ctrl = Options[k] or Toggles[k]
		if ctrl then snap[k] = ctrl.Value end
	end
	profiles["Custom"] = snap
	if not table.find(Options.profileSelect.Values, "Custom") then
		table.insert(Options.profileSelect.Values, "Custom")
		Options.profileSelect:SetValues()
	end
	pcall(function() Options.profileSelect:SetValue("Custom") end)
	-- Best-effort persistence to disk (executor-dependent).
	pcall(function()
		if writefile then
			writefile("FurryHBE_CustomProfile.json", game:GetService("HttpService"):JSONEncode(snap))
		end
	end)
	Library:Notify("Saved current settings as 'Custom' profile")
end):AddToolTip("Snapshot the current settings into a loadable 'Custom' profile")

-- Restore a previously saved custom profile from disk, if present.
pcall(function()
	if isfile and isfile("FurryHBE_CustomProfile.json") and readfile then
		local data = game:GetService("HttpService"):JSONDecode(readfile("FurryHBE_CustomProfile.json"))
		if type(data) == "table" then
			profiles["Custom"] = data
			if not table.find(Options.profileSelect.Values, "Custom") then
				table.insert(Options.profileSelect.Values, "Custom")
				Options.profileSelect:SetValues()
			end
		end
	end
end)

-- NOTE: The Precision, Streamer and Teleport add-ons are now BUILT IN to this
-- single file (see the "INLINED ADD-ONS" section near the bottom). There is no
-- longer any separate-file loader -- everything ships in mainscript.lua.

-- Emergency + Console are folded into the Settings tab (formerly Profiles) so the
-- tab bar isn't so spread out.
local emergencyGroupbox = profilesTab:AddRightGroupbox("Fixes")
local consoleGroupbox = profilesTab:AddRightGroupbox("Error Console")
local consoleOutput = consoleGroupbox:AddLabel("No errors detected", true)  -- wrap so long errors don't clip off-screen
local consoleCopyButton = consoleGroupbox:AddButton("Copy Latest Error", function()
	if #errorLog > 0 then
		local latestError = errorLog[#errorLog]
		local errorText = "[Error Context: " .. latestError.context .. "]\n" ..
		                  "[Error Message: " .. latestError.error .. "]\n" ..
		                  "[Time: " .. os.date("%H:%M:%S", latestError.time) .. "]\n" ..
		                  (latestError.uiElement and "[UI Element: " .. latestError.uiElement .. "]" or "")
		setclipboard(errorText)
		Library:Notify("Error copied to clipboard")
	else
		Library:Notify("No errors to copy")
	end
end):AddToolTip("Copy the latest error to clipboard")
local consoleClearButton = consoleGroupbox:AddButton("Clear Errors", function()
	errorLog = {}
	uiElementStatus = {}
	for name, element in pairs(uiElementReferences) do
		uiElementStatus[name] = {
			errorCount = 0,
			lastError = nil
		}
	end
	consoleOutput:SetText("No errors detected")
	Library:Notify("Error log cleared")
end):AddToolTip("Clear all errors from the log")

-- The Error Console now lives in the Settings tab (always present). This just
-- refreshes its label instead of showing/hiding a dedicated tab.
function updateConsoleTab()
	if #errorLog > 0 then
		local latestError = errorLog[#errorLog]
		local msg = tostring(latestError.error)
		if #msg > 180 then msg = msg:sub(1, 180) .. "..." end  -- truncate so it can't overflow
		consoleOutput:SetText("[" .. #errorLog .. "] " .. latestError.context .. ":\n" .. msg)
	else
		consoleOutput:SetText("No errors detected")
	end
end

emergencyGroupbox:AddButton("Fix Missing Players", function()
	local found = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if players[player] or player == lPlayer then 
			continue 
		else
			found = found + 1
			addPlayer(player)
		end
	end
	if found > 0 then
		Library:Notify("Found " .. found .. " players")
	else
		Library:Notify("No missing players found")
	end
	updatePlayers()
end):AddToolTip("Attempts to find players that were not detected by the HBE")

emergencyGroupbox:AddButton("Force Cleanup", function()
	cleanup()
	Library:Notify("Cleanup complete")
end):AddToolTip("Force cleanup of all hooks and visuals")

emergencyGroupbox:AddButton("Re-extract Weapons", function()
	local weapons = extractWeapons()
	Options.weaponList.Values = weapons
	Options.weaponList:SetValues()
	Library:Notify("Re-extracted " .. #weapons .. " weapons")
end):AddToolTip("Re-scan game for weapons")

-- Keybinds
local miscGroupbox = mainTab:AddLeftGroupbox("Keybinds")
miscGroupbox:AddLabel("Toggle UI"):AddKeyPicker("menuKeybind", { Default = "\\", NoUI = true, Text = "Menu Keybind" })
miscGroupbox:AddLabel("Force Update"):AddKeyPicker("forceUpdateKeybind", { Default = "Home", NoUI = true, Text = "Force Update Keybind"})
Options.forceUpdateKeybind:OnClick(updatePlayers)
miscGroupbox:AddLabel("Panic (toggle extender)"):AddKeyPicker("panicKeybind", { Default = "P", NoUI = true, Text = "Panic Keybind" })
Options.panicKeybind:OnClick(function()
	if Toggles.extenderToggled then
		Toggles.extenderToggled:SetValue(not Toggles.extenderToggled.Value)
	end
end)
Library.ToggleKeybind = Options.menuKeybind

-- Performance settings
local performanceGroupbox = mainTab:AddRightGroupbox("Performance")
performanceGroupbox:AddSlider("updateRate", { Text = "Update Rate (Hz)", Min = 1, Max = 60, Default = 30, Rounding = 1, Tooltip = "How often to update hitboxes (higher = more responsive but more CPU)" }):OnChanged(updatePlayers)

-- Menu transparency: blend every menu background toward invisible so the window
-- stops blocking your view. Input is unaffected -- transparency does NOT stop
-- clicks, so every button/slider stays usable. Originals are captured once
-- (weak keys so destroyed frames are GC'd) and all values are scaled from them,
-- so dragging the slider back to 0 restores the menu exactly.
local menuBaseTransparency = setmetatable({}, { __mode = "k" })
local function applyMenuTransparency(alpha)
	local roots = {}
	if Library.ScreenGui then table.insert(roots, Library.ScreenGui) end
	local holder = rawget(Library, "Holder") or rawget(Library, "MainFrame")
	if holder then table.insert(roots, holder) end
	for _, root in ipairs(roots) do
		pcall(function()
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("GuiObject") then
					if menuBaseTransparency[d] == nil then
						menuBaseTransparency[d] = d.BackgroundTransparency
					end
					local base = menuBaseTransparency[d]
					-- Only fade backgrounds that are actually visible; leave text,
					-- strokes and already-invisible frames alone so the menu stays legible.
					if base < 1 then
						d.BackgroundTransparency = base + (1 - base) * alpha
					end
				end
			end
		end)
	end
end
performanceGroupbox:AddSlider("menuTransparency", { Text = "Menu Transparency", Min = 0, Max = 0.9, Default = 0, Rounding = 2, Tooltip = "See-through menu so it doesn't block your view. You can still click everything." }):OnChanged(function()
	applyMenuTransparency(Options.menuTransparency.Value)
end)

-- Reset buttons
hitboxGroupbox:AddButton("Reset Hitbox Settings", function()
	Options.extenderSize:SetValue(10)
	Options.extenderTransparency:SetValue(0.5)
	Options.partSpecificSizing:SetValue(false)
	Options.dynamicSizing:SetValue(false)
	Options.smoothTransitions:SetValue(false)
	updatePlayers()
	Library:Notify("Reset hitbox settings")
end)

filterGroupbox:AddButton("Reset Filter Settings", function()
	Options.maxDistance:SetValue(1000)
	Options.fovFilterToggled:SetValue(false)
	Options.weaponFilterToggled:SetValue(false)
	updatePlayers()
	Library:Notify("Reset filter settings")
end)

antiDetectionGroupbox:AddButton("Reset Anti-Detection", function()
	Options.randomizationToggled:SetValue(false)
	Options.humanizationToggled:SetValue(false)
	Options.legitModeToggled:SetValue(false)
	updatePlayers()
	Library:Notify("Reset anti-detection settings")
end)

-- SaveManager integration
SaveManager:BuildConfigSection(mainTab)
SaveManager:LoadAutoloadConfig()

-- Helper functions (moved after UI creation to avoid reference errors)
local function updateFOVCircle()
	local success, err = pcall(function()
		-- Streamer Mode: force the circle hidden while keeping the FOV filter live.
		if Bridge.Streamer.hideFOV then
			fovCircle.Visible = false
			return
		end
		if not Toggles.fovFilterToggled or not Toggles.fovFilterToggled.Value then
			fovCircle.Visible = false
			return
		end

		if not Options.fovSize or not Options.fovColor or not Options.fovThickness then
			fovCircle.Visible = false
			return
		end

		fovCircle.Visible = true
		fovCircle.Radius = Options.fovSize.Value
		fovCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
		fovCircle.Color = Options.fovColor.Value
		fovCircle.Thickness = Options.fovThickness.Value
	end)
	
	if not success then
		logError("updateFOVCircle", err, "fovFilterToggled")
	end
end

local function isLocalDead()
	local char = lPlayer.Character
	if not char then return true end
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hum then return true end
	return hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead
end

-- True while the local player is sitting in / occupying ANY seat (vehicle seat,
-- regular Seat, anchored seat, turret, etc.). Covers Humanoid.Sit, the Seated
-- state, and a live SeatPart so it catches every variant.
local function isLocalSeated()
	local char = lPlayer.Character
	if not char then return false end
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hum then return false end
	if hum.SeatPart ~= nil then return true end
	if hum.Sit == true then return true end
	local ok, seated = pcall(function() return hum:GetState() == Enum.HumanoidStateType.Seated end)
	return ok and seated or false
end

function runUpdatePlayers()
	if not getgenv().FurryHBELoaded then return end

	-- Safety: stop extending while the local player is dead/spectating.
	if Toggles.autoOffWhenDead and Toggles.autoOffWhenDead.Value and isLocalDead() then
		resetAllPlayers()
		resetWorldParts()
		return
	end

	local success, err = pcall(function()
		local currentTime = tick()
		if Options.updateRate and Options.updateRate.Value then
			if currentTime - lastUpdateTime < (1 / Options.updateRate.Value) then
				return
			end
		end
		lastUpdateTime = currentTime

		-- Closest-targets mode: rank players by distance and only allow the nearest N.
		extendAllowed = nil
		if Toggles.closestTargetsOnly and Toggles.closestTargetsOnly.Value then
			local maxN = (Options.maxTargets and Options.maxTargets.Value) or 1
			local ranked = {}
			for plr in pairs(players) do
				local char = plr.Character
				if char then
					table.insert(ranked, { player = plr, dist = getDistanceToPlayer(char) })
				end
			end
			table.sort(ranked, function(a, b) return a.dist < b.dist end)
			extendAllowed = {}
			for i = 1, math.min(maxN, #ranked) do
				extendAllowed[ranked[i].player] = true
			end
		end

		activeExtensions = 0
		for _, v in pairs(players) do
			task.spawn(function()
				pcall(function()
					v:Update()
				end)
			end)
		end
	end)
	
	if not success then
		logError("updatePlayers", err, "extenderToggled")
	end
end

-- Force every tracked player's parts back to their real (unextended) state,
-- ignoring all toggles. Used when the extender/master is switched off so the
-- visuals clear instantly instead of waiting on the update loop.
function resetAllPlayers()
	for _, v in pairs(players) do
		task.spawn(function()
			pcall(function()
				if v.ResetVisuals then v:ResetVisuals() end
			end)
		end)
	end
end

-- ===== World-part / vehicle HBE =====================================
-- The per-player loop only touches character parts, so scanned ground/walls/
-- vehicle parts are extended here instead. World parts grow ADDITIVELY (original
-- size + hitbox size) so a vehicle's hitbox enlarges rather than collapsing to a
-- fixed cube, and are only extended while their name is selected in the dropdown.
local function setupWorldPart(part)
	if worldParts[part] then return end
	worldParts[part] = {
		Size = part.Size,
		Transparency = part.Transparency,
		Massless = part.Massless,
		CanCollide = part.CanCollide,
	}
	part.Destroying:Connect(function()
		worldParts[part] = nil
	end)
end

local function restoreWorldPart(part)
	local d = worldParts[part]
	if not d then return end
	pcall(function()
		part.Size = d.Size
		part.Transparency = d.Transparency
		part.CanCollide = d.CanCollide
	end)
end

function resetWorldParts()
	for part in pairs(worldParts) do
		if typeof(part) == "Instance" and part.Parent then
			restoreWorldPart(part)
		end
	end
end

local function updateWorldParts()
	local extendOn = getgenv().FurryHBELoaded and Toggles.extenderToggled and Toggles.extenderToggled.Value
	local activeNames = Options.extenderPartList and Options.extenderPartList:GetActiveValues() or {}
	local size = Options.extenderSize and Options.extenderSize.Value or 10
	for part, d in pairs(worldParts) do
		if typeof(part) ~= "Instance" or not part.Parent then
			worldParts[part] = nil
		else
			pcall(function()
				if extendOn and table.find(activeNames, part.Name) then
					part.Size = d.Size + Vector3.new(size, size, size)
					part.Transparency = Bridge.Streamer.hideHitbox and 1 or Options.extenderTransparency.Value
					part.CanCollide = Toggles.collisionsToggled.Value and true or d.CanCollide
				else
					part.Size = d.Size
					part.Transparency = d.Transparency
					part.CanCollide = d.CanCollide
				end
			end)
		end
	end
end

-- Anti-overlap declutter. Each player's UpdateESP registers its name label here
-- (UpdateESP runs synchronously -- no yields -- so by the time the loop returns
-- every slot is present). After all players update we nudge clumped names apart.
local espNameSlots = {}
local function resolveEspOverlap()
	if not (Toggles.espAntiOverlap and Toggles.espAntiOverlap.Value) then return end
	local slots = espNameSlots
	if #slots < 2 then return end
	table.sort(slots, function(a, b) return a.y < b.y end)
	local gap = (Options.espOverlapGap and Options.espOverlapGap.Value) or 16
	for i = 1, #slots do
		local cur = slots[i]
		for j = 1, i - 1 do
			local prev = slots[j]
			-- Only declutter labels that share roughly the same column.
			if math.abs(cur.x - prev.x) < 70 and (cur.y - prev.y) < gap then
				cur.y = prev.y + gap
			end
		end
		cur.label.Position = Vector2.new(cur.x, cur.y)
		if cur.team and cur.team.Visible then cur.team.Position = Vector2.new(cur.x, cur.y + cur.size) end
	end
end

-- Render step for ESP (with failsafe)
RunService:BindToRenderStep("furryWalls", Enum.RenderPriority.Camera.Value - 1, function()
	if not getgenv().FurryHBELoaded then return end
	Camera = Workspace.CurrentCamera
	pcall(updateFOVCircle)
	if #espNameSlots > 0 then table.clear(espNameSlots) end
	for _, v in pairs(players) do
		task.spawn(function()
			local success, err = pcall(function()
				v:UpdateESP()
			end)
			if not success then
				logError("UpdateESP", err, "espNameToggled")
			end
		end)
	end
	pcall(resolveEspOverlap)
end)

-- Other helper functions
local function updateList(list)
	list:SetValues()
	list:Display()
end

local function updateStatus()
	-- Throttle: the labels don't need a 60 Hz refresh.
	local now = tick()
	if now - lastStatusUpdate < 0.2 then return end
	lastStatusUpdate = now

	local activeCount = 0
	local extendedCount = activeExtensions
	local whitelistedCount = Options.whitelistPlayerList and #Options.whitelistPlayerList:GetActiveValues() or 0
	local priorityCount = Options.priorityPlayerList and #Options.priorityPlayerList:GetActiveValues() or 0
	local errorCount = #errorLog
	
	for _ in pairs(players) do
		activeCount = activeCount + 1
	end
	
	statusActiveLabel:SetText("Active Players: " .. activeCount)
	statusExtendedLabel:SetText("Extended: " .. extendedCount)
	statusWhitelistLabel:SetText("Whitelisted: " .. whitelistedCount)
	statusPriorityLabel:SetText("Priority: " .. priorityCount)
	statusErrorsLabel:SetText("Errors: " .. errorCount)
	whitelistCountLabel:SetText("Whitelisted: " .. whitelistedCount)
	priorityCountLabel:SetText("Priority: " .. priorityCount)
end

local function isWhitelisted(player)
	if not Options.whitelistPlayerList then return false end
	return table.find(Options.whitelistPlayerList:GetActiveValues(), player.Name) ~= nil
end

local function isPriority(player)
	if not Toggles.prioritySystemToggled or not Toggles.prioritySystemToggled.Value then return false end
	if not Options.priorityPlayerList then return false end
	return table.find(Options.priorityPlayerList:GetActiveValues(), player.Name) ~= nil
end

function getDistanceToPlayer(playerChar)
	if not playerChar then return math.huge end
	
	local head = playerChar:FindFirstChild("Head")
	if not head then return math.huge end
	
	local lChar = lPlayer.Character
	if not lChar then return math.huge end
	
	local lHead = lChar:FindFirstChild("Head")
	if not lHead then return math.huge end
	
	return (head.Position - lHead.Position).Magnitude
end

-- Helper functions that reference Toggles/Options (must be after UI creation, with failsafes)

-- Part Scanner functions / body-part list helpers
function isDefaultBodyPart(name)
	return table.find(DEFAULT_BODY_PARTS, name) ~= nil
end

function partListContains(name)
	return Options.extenderPartList ~= nil and table.find(Options.extenderPartList.Values, name) ~= nil
end

function addBodyPart(name)
	if not partListContains(name) then
		table.insert(Options.extenderPartList.Values, name)
		Options.extenderPartList:SetValues()
	end
	pcall(function()
		if type(Options.extenderPartList.Value) == "table" then
			Options.extenderPartList.Value[name] = true
			Options.extenderPartList:SetValue(Options.extenderPartList.Value)
		end
	end)
end

function removeBodyPart(name)
	local vals = Options.extenderPartList.Values
	local idx = table.find(vals, name)
	if idx then table.remove(vals, idx) end
	-- Restore and untrack any scanned world parts sharing this name.
	for part in pairs(worldParts) do
		if typeof(part) == "Instance" and part.Name == name then
			restoreWorldPart(part)
			worldParts[part] = nil
		end
	end
	pcall(function()
		if type(Options.extenderPartList.Value) == "table" then
			Options.extenderPartList.Value[name] = nil
		end
	end)
	Options.extenderPartList:SetValues()
	pcall(function()
		if type(Options.extenderPartList.Value) == "table" then
			Options.extenderPartList:SetValue(Options.extenderPartList.Value)
		end
	end)
end

local function isPartWithHitbox(part)
	if not part or not part:IsA("BasePart") then return false end

	-- Character/humanoid parts are always scannable
	local parent = part.Parent
	while parent do
		if parent:IsA("Model") and parent:FindFirstChildWhichIsA("Humanoid") then
			return true
		end
		parent = parent.Parent
	end

	-- World parts (ground, walls, vehicles) only when explicitly allowed
	if Toggles.partScannerAllowWorld and Toggles.partScannerAllowWorld.Value then
		return part.CanCollide == true
	end

	return false
end

local function getPartUnderCursor()
	local mouse = lPlayer:GetMouse()
	local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {lPlayer.Character}
	
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
	if result and result.Instance then
		return result.Instance
	end
	return nil
end

local function updatePartScanner()
	if not partScannerToggled then
		partScannerProgressCircle.Visible = false
		partScannerFillCircle.Visible = false
		return
	end

	local partUnderCursor = getPartUnderCursor()
	local valid = partUnderCursor ~= nil and isPartWithHitbox(partUnderCursor)

	-- Refresh the highlight whenever the hovered part changes (independent of holding).
	-- Green = will add on hold, Red = will remove on hold (an existing scanned part).
	if partUnderCursor ~= partScannerCurrentPart then
		partScannerCurrentPart = partUnderCursor
		partScannerProgress = 0
		partScannerHoverTime = tick()

		if partScannerHighlight then
			partScannerHighlight:Destroy()
			partScannerHighlight = nil
		end

		if valid then
			local willRemove = partListContains(partUnderCursor.Name) and not isDefaultBodyPart(partUnderCursor.Name)
			local hl = willRemove and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(0, 255, 0)
			partScannerHighlight = Instance.new("Highlight")
			partScannerHighlight.Adornee = partUnderCursor
			partScannerHighlight.FillColor = hl
			partScannerHighlight.OutlineColor = hl
			partScannerHighlight.FillTransparency = 0.7
			partScannerHighlight.OutlineTransparency = 0
			partScannerHighlight.Parent = game:GetService("CoreGui")
		end
	end

	-- While the mouse button isn't held, keep the timer reset so the hold always
	-- measures from the moment the user presses (not from when they started hovering).
	if not partScannerHolding then
		partScannerProgress = 0
		partScannerHoverTime = tick()
	end

	if valid and partScannerHolding then
		partScannerProgress = math.min((tick() - partScannerHoverTime) / partScannerHoverDuration, 1)

		local mouse = lPlayer:GetMouse()
		local center = Vector2.new(mouse.X, mouse.Y)
		local maxR = 28

		partScannerProgressCircle.Position = center
		partScannerProgressCircle.Radius = maxR
		partScannerProgressCircle.Filled = false
		partScannerProgressCircle.Color = Color3.fromRGB(255, 255, 255)
		partScannerProgressCircle.Visible = true

		partScannerFillCircle.Position = center
		partScannerFillCircle.Radius = math.max(1, maxR * partScannerProgress)
		partScannerFillCircle.Filled = true
		partScannerFillCircle.Color = Color3.fromRGB(
			math.floor(255 * (1 - partScannerProgress)),
			math.floor(255 * partScannerProgress),
			0
		)
		partScannerFillCircle.Visible = true

		if partScannerProgress >= 1 then
			local partName = partScannerCurrentPart.Name
			if partListContains(partName) and not isDefaultBodyPart(partName) then
				removeBodyPart(partName)
				Library:Notify("Removed '" .. partName .. "' from body part list")
			elseif partListContains(partName) then
				Library:Notify("'" .. partName .. "' is a default body part (already listed)")
			else
				addBodyPart(partName)
				-- Non-character (world) parts must be tracked by instance so the
				-- dedicated world-part loop actually extends them.
				local isChar = false
				local p = partScannerCurrentPart.Parent
				while p do
					if p:IsA("Model") and p:FindFirstChildWhichIsA("Humanoid") then isChar = true break end
					p = p.Parent
				end
				if not isChar then setupWorldPart(partScannerCurrentPart) end
				Library:Notify("Added '" .. partName .. "' to body part list")
			end
			updatePlayers()
			-- Require releasing and re-pressing before the next add/remove.
			partScannerHolding = false
			partScannerProgress = 0
			partScannerHoverTime = tick()
			partScannerCurrentPart = nil -- force highlight recolor next frame
		end
	else
		partScannerProgressCircle.Visible = false
		partScannerFillCircle.Visible = false
	end
end

-- Add part scanner to render step
RunService:BindToRenderStep("partScanner", Enum.RenderPriority.Last.Value + 1, function()
	pcall(updatePartScanner)
end)

-- Part scanner is click-and-HOLD. Track the left mouse button; ignore clicks the
-- LinoriaLib menu consumed (gameProcessed) so interacting with the UI never scans.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and partScannerToggled and not gameProcessed then
		partScannerHolding = true
		partScannerHoverTime = tick()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		partScannerHolding = false
	end
end)

local function isPlayerInFOV(playerChar)
	if not Toggles.fovFilterToggled or not Toggles.fovFilterToggled.Value then
		return true
	end
	
	if not Options.fovSize then return true end
	
	local head = playerChar:FindFirstChild("Head")
	if not head then return false end
	
	local pos, onScreen = WorldToViewportPoint(Camera, head.Position)
	if not onScreen then return false end
	
	local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
	local screenPos = Vector2.new(pos.X, pos.Y)
	local distance = (screenPos - screenCenter).Magnitude
	
	return distance <= Options.fovSize.Value
end

local function isPlayerHoldingWeapon(player)
	if not Toggles.weaponFilterToggled or not Toggles.weaponFilterToggled.Value then
		return false
	end
	
	if not Options.weaponList then return false end
	
	local character = player.Character
	if not character then return false end
	
	local ignoredWeapons = Options.weaponList:GetActiveValues()
	if #ignoredWeapons == 0 then return false end
	
	for _, item in pairs(character:GetChildren()) do
		if item:IsA("Tool") then
			if table.find(ignoredWeapons, item.Name) then
				return true
			end
		end
	end
	
	return false
end

local function isInLegitMode(playerChar)
	if not Toggles.legitModeToggled or not Toggles.legitModeToggled.Value then
		return true
	end
	
	if not Options.legitModeFOV then return true end
	
	local head = playerChar:FindFirstChild("Head")
	if not head then return false end
	
	local pos, onScreen = WorldToViewportPoint(Camera, head.Position)
	if not onScreen then return false end
	
	local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
	local screenPos = Vector2.new(pos.X, pos.Y)
	local distance = (screenPos - screenCenter).Magnitude
	
	return distance <= Options.legitModeFOV.Value
end

-- Player addition function (with failsafe)
function addPlayer(player)
	if players[player] then return end -- Fix duplicate player entries
	
	local success, err = pcall(function()
		-- Guard each insert so names never duplicate (the whitelist auto-persist may
		-- have pre-seeded the same name, and rejoins could otherwise stack entries).
		for _, listName in ipairs({ "ignorePlayerList", "whitelistPlayerList", "priorityPlayerList" }) do
			local list = Options[listName]
			if list and not table.find(list.Values, player.Name) then
				table.insert(list.Values, player.Name)
				updateList(list)
			end
		end
	end)
	
	if not success then
		logError("addPlayer - list update", err)
		return
	end
	
	players[player] = {}
	local playerIdx = players[player]
	local playerChar = player.Character
	local defaultProperties = {}
	local currentSizes = {}
	local targetSizes = {}
	-- [part] = { Size=, Transparency=, CanCollide=, Massless= } : the last values WE
	-- wrote. Used to ignore our own (deferred) Changed events so they can't corrupt
	-- the stored defaults -- the root cause of "hitbox stays extended after turning off".
	local appliedProps = {}

	local function isTeammate()
		-- Detectors are keyed by GameId for some games and PlaceId for others.
		local detector = TeamDetection[game.GameId] or TeamDetection[game.PlaceId]

		if detector then
			local success, result = pcall(function()
				return detector(player, lPlayer, playerChar, lPlayer.Character)
			end)
			if success then return result == true end
		end

		-- Generic fallback: prefer Team objects, then TeamColor.
		local ok, result = pcall(function()
			if lPlayer.Team ~= nil or player.Team ~= nil then
				return lPlayer.Team == player.Team
			end
			if lPlayer.TeamColor ~= nil and player.TeamColor ~= nil then
				return lPlayer.TeamColor == player.TeamColor
			end
			return false
		end)
		return ok and result or false
	end

	local function isDead()
		if not playerChar then return true end
		local humanoid = playerChar:FindFirstChildWhichIsA("Humanoid")
		
		local success, result = pcall(function()
			if game.PlaceId == 6172932937 then -- Energy Assault
				return player.ragdolled.Value
			elseif game.GameId == 718936923 then -- Neighborhood War
				return playerChar:FindFirstChild("Dead") ~= nil
			end
			return humanoid and humanoid:GetState() == Enum.HumanoidStateType.Dead
		end)
		
		return success and result or (humanoid and humanoid:GetState() == Enum.HumanoidStateType.Dead)
	end

	local function isSitting()
		local humanoid = playerChar:FindFirstChildWhichIsA("Humanoid")
		return Toggles.extenderSitCheck.Value and humanoid ~= nil and humanoid.Sit == true
	end

	local function isFFed()
		if not playerChar then return false end
		
		local success, result = pcall(function()
			if game.PlaceId == 4991214437 or game.PlaceId == 6652350934 then -- town
				return playerChar.Head.Material == Enum.Material.ForceField
			end
			local ff = playerChar:FindFirstChildWhichIsA("ForceField")
			return Toggles.extenderFFCheck.Value and playerChar ~= nil and ff ~= nil and ff.Visible == true
		end)
		
		return success and result or false
	end

	local function isIgnored()
		if not playerChar then return true end
		if isWhitelisted(player) then return true end
		if isPriority(player) then return false end -- Priority players never ignored
		
		local distance = getDistanceToPlayer(playerChar)
		local maxDist = Options.maxDistance.Value
		if maxDist > 0 and distance > maxDist then return true end
		
		if not isPlayerInFOV(playerChar) then return true end
		
		if isPlayerHoldingWeapon(player) then return true end
		
		return Toggles.ignoreOwnTeamToggled.Value and isTeammate() or
		Toggles.ignoreSelectedTeamsToggled.Value and table.find(Options.ignoreTeamList:GetActiveValues(), tostring(player.Team)) or
		Toggles.ignoreSelectedPlayersToggled.Value and table.find(Options.ignorePlayerList:GetActiveValues(), tostring(player.Name))
	end

	-- HBE setup with optimized hooking
	local debounce = false
	local hookedParts = {}
	
	local function setup(part)
		if hookedParts[part] then return end -- Already hooked

		-- Keyed by the part INSTANCE (not its name) so duplicate-named parts
		-- (accessory Handles, vehicle parts, etc.) each keep their own defaults.
		defaultProperties[part] = {}
		local properties = defaultProperties[part]
		properties.Size = part.Size
		properties.Transparency = part.Transparency
		properties.Massless = part.Massless
		properties.CanCollide = part.CanCollide

		currentSizes[part] = part.Size
		targetSizes[part] = part.Size

		local changed = part.Changed:Connect(function(property)
			if debounce then return end
			if properties[property] then
				-- Ignore changes that match what WE last wrote. Roblox fires .Changed
				-- with DEFERRED behavior, so our own resize writes arrive here AFTER
				-- debounce has reset -- without this guard the extended value would be
				-- saved as the "default" and the part could never be restored.
				local applied = appliedProps[part]
				if applied and applied[property] == part[property] then
					return
				end
				if properties[property] ~= part[property] then
					properties[property] = part[property]
				end
				playerIdx:Update()
			end
		end)

		hookedParts[part] = {
			changed = changed
		}

		part.Destroying:Connect(function()
			if hookedParts[part] then
				local hooks = hookedParts[part]
				hooks.changed:Disconnect()
				hookedParts[part] = nil
			end
			-- Drop the per-instance state so the tables don't leak.
			defaultProperties[part] = nil
			currentSizes[part] = nil
			targetSizes[part] = nil
				appliedProps[part] = nil
		end)
	end

	local function isActive(part)
		local name = part.Name
		for _, v in pairs(Options.extenderPartList:GetActiveValues()) do
			if string.find(name, v, 1, true) or (v == "Custom Part" and Options.customPartName.Value ~= "" and string.find(name, Options.customPartName.Value, 1, true)) or
			(v == "Left Arm" and string.match(name, "Left") and (string.match(name, "Arm") or string.match(name, "Hand"))) or
			(v == "Right Arm" and string.match(name, "Right") and (string.match(name, "Arm") or string.match(name, "Hand"))) or
			(v == "Left Leg" and string.match(name, "Left") and (string.match(name, "Leg") or string.match(name, "Foot"))) or
			(v == "Right Leg" and string.match(name, "Right") and (string.match(name, "Leg") or string.match(name, "Foot"))) then
				return true
			end
		end
		return false
	end

	local function getTargetSize(part)
		local baseSize = Options.extenderSize.Value
		
		if Toggles.partSpecificSizing.Value then
			if part.Name == "Head" then
				baseSize = Options.headSize.Value
			elseif part.Name == "Torso" or part.Name == "UpperTorso" or part.Name == "LowerTorso" then
				baseSize = Options.torsoSize.Value
			elseif string.match(part.Name, "Arm") or string.match(part.Name, "Leg") or string.match(part.Name, "Hand") or string.match(part.Name, "Foot") then
				baseSize = Options.limbSize.Value
			end
		end
		
		if Toggles.dynamicSizing.Value then
			local distance = getDistanceToPlayer(playerChar)
			local scaleFactor = Options.dynamicScalingFactor.Value
			baseSize = baseSize * (1 - (distance / 1000) * scaleFactor)
			baseSize = math.max(2, baseSize)
		end
		
		if Toggles.randomizationToggled.Value then
			local amt = Options.randomizationAmount.Value
			if Toggles.smartJitter and Toggles.smartJitter.Value then
				-- Smooth sine-based jitter -- less detectable than random per-frame snapping.
				baseSize = baseSize + math.sin(tick() * 3) * amt
			else
				baseSize = baseSize + (math.random() * 2 - 1) * amt
			end
		end

		-- Max-plausible cap: never exceed this multiple of the part's REAL size, so the
		-- extension stays within a believable range. 0 = off.
		if Options.maxPlausibleMult and Options.maxPlausibleMult.Value > 0 then
			local d = defaultProperties[part]
			local realSize = (d and d.Size) or part.Size
			local cap = math.max(realSize.X, realSize.Y, realSize.Z) * Options.maxPlausibleMult.Value
			baseSize = math.min(baseSize, math.max(2, cap))
		end

		-- Auto-Expand in FOV: grow the hitbox when the target sits near the crosshair.
		if Toggles.autoExpandFOV and Toggles.autoExpandFOV.Value then
			local head = playerChar:FindFirstChild("Head")
			if head then
				local pos, onScreen = WorldToViewportPoint(Camera, head.Position)
				if onScreen then
					local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
					local dist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
					local fovR = (Options.fovSize and Options.fovSize.Value) or 100
					if dist <= fovR then
						baseSize = baseSize * 1.5
					end
				end
			end
		end

		-- Hitbox shape: reshape the cube without changing its overall reach.
		local shape = Options.hitboxShape and Options.hitboxShape.Value or "Cube"
		if shape == "Flat (disk)" then
			return Vector3.new(baseSize, math.max(1, baseSize * 0.25), baseSize)
		elseif shape == "Tall (pillar)" then
			return Vector3.new(math.max(1, baseSize * 0.5), baseSize * 1.5, math.max(1, baseSize * 0.5))
		end
		return Vector3.new(baseSize, baseSize, baseSize)
	end

	local function lerp(a, b, t)
		return a + (b - a) * t
	end

	local function resize(part)
		if not defaultProperties[part] then
			setup(part)
		end
		
		-- Player-level eligibility (independent of which part we're on).
		local playerEligible = Toggles.extenderToggled.Value and not isIgnored() and not isSitting() and not isFFed() and not isDead() and isInLegitMode(playerChar)

		-- Seat safety: while the local player is seated (driving, on a turret, any
			-- seat), optionally stop extending -- either everyone, or just players
			-- within a small radius so a nearby enemy's giant hitbox doesn't engulf
			-- your seat / mess with your aim.
			if playerEligible and Toggles.seatDisableHBE and Toggles.seatDisableHBE.Value and isLocalSeated() then
				if Toggles.seatRadiusMode and Toggles.seatRadiusMode.Value then
					if getDistanceToPlayer(playerChar) <= (Options.seatRadius and Options.seatRadius.Value or 30) then
						playerEligible = false
					end
				else
					playerEligible = false
				end
			end

			-- Yield any player an add-on has claimed (e.g. Precision owns this target),
		-- so the two never fight over the same parts.
		if playerEligible and Bridge.Claims[player] then
			playerEligible = false
		end

		-- Closest-targets mode: only the nearest N allowed players extend.
		if playerEligible and extendAllowed ~= nil and not extendAllowed[player] then
			playerEligible = false
		end

		-- Humanization: require the player to stay eligible for the delay first.
		if playerEligible and Toggles.humanizationToggled and Toggles.humanizationToggled.Value then
			if not eligibleSince[player] then eligibleSince[player] = tick() end
			local delay = (Options.humanizationDelay and Options.humanizationDelay.Value or 0) / 1000
			if tick() - eligibleSince[player] < delay then
				playerEligible = false
			end
		elseif not playerEligible then
			eligibleSince[player] = nil
		end

		local shouldExtend = playerEligible and isActive(part)

		if shouldExtend then
			activeExtensions = activeExtensions + 1

			if part.Name ~= "HumanoidRootPart" then
				part.Massless = true
			end
			
			if Toggles.collisionsToggled.Value then
				-- Make the enlarged hitbox physically collide.
				part.CanCollide = true
			else
				part.CanCollide = false
			end
			
			local targetSize = getTargetSize(part)
			
			if Toggles.smoothTransitions.Value then
				local currentSize = currentSizes[part] or part.Size
				local speed = Options.transitionSpeed.Value
				local newSize = lerp(currentSize, targetSize, speed)
				currentSizes[part] = newSize
				part.Size = newSize
			else
				part.Size = targetSize
			end

			-- Streamer Mode forces the enlarged hitbox fully transparent.
			local extTransparency = Bridge.Streamer.hideHitbox and 1 or Options.extenderTransparency.Value
			-- Outline Mode: keep the hitbox enlarged (for hit-reg) but make the block
			-- invisible and draw a coloured wireframe instead, so the body isn't hidden
			-- behind a big transparent box.
			local outline = part:FindFirstChild("FurryHBE_Outline")
			if Toggles.outlineMode and Toggles.outlineMode.Value then
				extTransparency = 1
				if not outline then
					outline = Instance.new("SelectionBox")
					outline.Name = "FurryHBE_Outline"
					outline.Adornee = part
					outline.LineThickness = 0.03
					outline.SurfaceTransparency = 1
					outline.Parent = part
				end
				outline.Color3 = (Options.outlineColor and Options.outlineColor.Value) or Color3.fromRGB(255, 0, 0)
				outline.Transparency = (Options.outlineTransparency and Options.outlineTransparency.Value) or 0
			elseif outline then
				outline:Destroy()
			end
			part.Transparency = extTransparency

			if part.Name == "Head" then
				local face = part:FindFirstChild("face")
				if face then
					face.Transparency = extTransparency
				end
			end
		else
			local d = defaultProperties[part]
			part.Massless = d.Massless
			part.CanCollide = d.CanCollide
			part.Size = d.Size
			part.Transparency = d.Transparency
			currentSizes[part] = d.Size
			local ob = part:FindFirstChild("FurryHBE_Outline")
			if ob then ob:Destroy() end

			if part.Name == "Head" then
				local face = part:FindFirstChild("face")
				if face then
					face.Transparency = d.Transparency
				end
			end
		end
	end

	function playerIdx:Update()
		-- Adaptive recovery: if the character reference went stale (respawn/timing),
		-- re-grab it instead of going dark until something else refreshes it.
		if (not playerChar or not playerChar.Parent) and player then playerChar = player.Character end
		if not playerChar then return end
		debounce = true
		for _, v in pairs(playerChar:GetChildren()) do
			if v:IsA("BasePart") then
				resize(v)
					-- Track what we wrote so our own deferred .Changed events can't
					-- corrupt the stored defaults (the "stays extended when off" bug).
					appliedProps[v] = { Size = v.Size, Transparency = v.Transparency, CanCollide = v.CanCollide, Massless = v.Massless }
			end
		end
		debounce = false
	end

	-- Restore every part to its recorded defaults regardless of toggle state.
	function playerIdx:ResetVisuals()
		if not playerChar then return end
		debounce = true
		for _, v in pairs(playerChar:GetChildren()) do
			if v:IsA("BasePart") and defaultProperties[v] then
				pcall(function()
					local d = defaultProperties[v]
					v.Massless = d.Massless
					v.CanCollide = d.CanCollide
					v.Size = d.Size
					v.Transparency = d.Transparency
					currentSizes[v] = d.Size
						appliedProps[v] = { Size = d.Size, Transparency = d.Transparency, CanCollide = d.CanCollide, Massless = d.Massless }
					local ob = v:FindFirstChild("FurryHBE_Outline")
					if ob then ob:Destroy() end
					if v.Name == "Head" then
						local face = v:FindFirstChild("face")
						if face then
							face.Transparency = d.Transparency
						end
					end
				end)
			end
		end
		debounce = false
	end

	-- ESP with enhancements
	-- Only ever return a BasePart. The old version did a bare substring match and
	-- happily returned accessory MODELS like "TorsoStrap" (matches "Torso"), then
	-- `.Position` on a Model threw "Position is not a valid member of Model" --
	-- the recurring UpdateESP error, worst on custom rigs with extra accessories.
	local function FindFirstChildMatching(parent, name)
		if not parent then return nil end
		local exact = parent:FindFirstChild(name)
		if exact and exact:IsA("BasePart") then return exact end
		for _, v in pairs(parent:GetChildren()) do
			if v:IsA("BasePart") and string.match(v.Name, name) then
				return v
			end
		end
		return nil
	end

	local nameEsp = DrawingFallback.new("Text")
	nameEsp.Center = true
	nameEsp.Outline = true

	-- Tiny team-name subscript rendered just below the name
	local teamEsp = DrawingFallback.new("Text")
	teamEsp.Center = true
	teamEsp.Outline = true

	local healthBar = DrawingFallback.new("Square")
	healthBar.Filled = true
	healthBar.Thickness = 1
	
	local boxEsp = DrawingFallback.new("Square")
	boxEsp.Filled = false
	boxEsp.Thickness = 1
	
	local tracer = DrawingFallback.new("Line")
	tracer.Thickness = 1

	-- Numeric health label next to the health bar
	local healthText = DrawingFallback.new("Text")
	healthText.Center = false
	healthText.Outline = true

	-- Edge marker pointing at the player when they are off-screen
	local offscreenMarker = DrawingFallback.new("Square")
	offscreenMarker.Filled = true
	offscreenMarker.Thickness = 1

	-- Skeleton ESP line pool (reused each frame; enough for an R15 rig)
	local skeletonLines = {}
	for i = 1, 16 do
		local ln = DrawingFallback.new("Line")
		ln.Thickness = 1
		ln.Visible = false
		skeletonLines[i] = ln
	end
	-- Bone pairs by part name (covers both R6 and R15; missing parts are skipped)
	local SKELETON_BONES = {
		{"Head","UpperTorso"}, {"Head","Torso"},
		{"UpperTorso","LowerTorso"}, {"UpperTorso","LeftUpperArm"}, {"UpperTorso","RightUpperArm"},
		{"LeftUpperArm","LeftLowerArm"}, {"LeftLowerArm","LeftHand"},
		{"RightUpperArm","RightLowerArm"}, {"RightLowerArm","RightHand"},
		{"LowerTorso","LeftUpperLeg"}, {"LowerTorso","RightUpperLeg"},
		{"LeftUpperLeg","LeftLowerLeg"}, {"LeftLowerLeg","LeftFoot"},
		{"RightUpperLeg","RightLowerLeg"}, {"RightLowerLeg","RightFoot"},
		{"Torso","Left Arm"}, {"Torso","Right Arm"}, {"Torso","Left Leg"}, {"Torso","Right Leg"},
	}
	local function hideSkeleton()
		for _, ln in ipairs(skeletonLines) do ln.Visible = false end
	end

	local chams = Instance.new("Highlight")
	chams.Parent = game:GetService("CoreGui")

	-- Expose the drawing objects on the player record so the name-declutter pass
	-- and add-ons can reach them (they're otherwise closure-local upvalues).
	playerIdx.nameEsp = nameEsp
	playerIdx.teamEsp = teamEsp
	playerIdx.healthBar = healthBar
	playerIdx.healthText = healthText
	playerIdx.boxEsp = boxEsp
	playerIdx.tracer = tracer
	playerIdx.offscreenMarker = offscreenMarker
	playerIdx.skeletonLines = skeletonLines
	playerIdx.chams = chams

	function playerIdx:UpdateESP()
		-- Team subscript is hidden by default; only the name-render path turns it on,
		-- so every early-return branch below leaves it correctly hidden.
		-- Default the extra visuals off; only their render paths below turn them on,
		-- so every early-return branch leaves them correctly hidden.
		teamEsp.Visible = false
		healthText.Visible = false
		offscreenMarker.Visible = false
		hideSkeleton()
		-- Adaptive recovery: re-grab a stale character so ESP self-heals on respawn.
		if (not playerChar or not playerChar.Parent) and player then playerChar = player.Character end
		-- ESP is INDEPENDENT of the HBE ignore filters (HBE max distance, HBE FOV
		-- filter, team, weapon). Those used to gate ESP via isIgnored(), which is why
		-- ESP flickered off when a target left HBE range/FOV (out of range, behind a
		-- car, just respawned/joined) and only popped back when you aimed at or shot
		-- them. ESP now uses ONLY its own gates: espMaxDistance and the optional
		-- espFOVFilter below. Whitelisted players still show ESP unless you turn the
		-- "Keep ESP on Whitelisted" toggle off.
		local hideForWL = isWhitelisted(player) and not (Toggles.espWhitelisted and Toggles.espWhitelisted.Value)
		if not playerChar or isDead() or hideForWL then
			nameEsp.Visible = false
			healthBar.Visible = false
			boxEsp.Visible = false
			tracer.Visible = false
			chams.Enabled = false
			return
		end
		
		local distance = getDistanceToPlayer(playerChar)
		local maxEspDist = Options.espMaxDistance.Value
		if maxEspDist > 0 and distance > maxEspDist then
			nameEsp.Visible = false
			healthBar.Visible = false
			boxEsp.Visible = false
			tracer.Visible = false
			chams.Enabled = false
			return
		end
		
		if Toggles.espFOVFilter.Value and not isPlayerInFOV(playerChar) then
			nameEsp.Visible = false
			healthBar.Visible = false
			boxEsp.Visible = false
			tracer.Visible = false
			chams.Enabled = false
			return
		end
		
		-- Rainbow colour: priority players flash to stand out; OR, if global Rainbow
		-- ESP is on, every player cycles. Applied wherever `flashCol` is used below.
		local flashCol = nil
		local rainbowOn = Toggles.espRainbow and Toggles.espRainbow.Value
		local prioFlash = Toggles.priorityFlash and Toggles.priorityFlash.Value and isPriority(player)
		if rainbowOn or prioFlash then
			local spd = (Options.espRainbowSpeed and Options.espRainbowSpeed.Value) or 0.7
			flashCol = Color3.fromHSV((tick() * spd) % 1, 1, 1)
		end
		-- Line thickness + distance fade (fade is native-Drawing only; harmless on the GUI fallback).
		local thick = (Options.espThickness and Options.espThickness.Value) or 1
		local fade = 0
		if Toggles.espDistanceFade and Toggles.espDistanceFade.Value then
			local md = (Options.espMaxDistance and Options.espMaxDistance.Value) or 1000
			if md > 0 then fade = math.clamp(distance / md, 0, 0.85) end
		end

		local target = FindFirstChildMatching(playerChar, "Torso")
		if not target then target = FindFirstChildMatching(playerChar, "UpperTorso") end
		if not target then target = FindFirstChildMatching(playerChar, "HumanoidRootPart") end
		
		-- Streamer Mode (hideESP) skips all 2D drawing work; the else-branch below
		-- leaves every 2D drawing hidden. Chams are handled separately further down.
		if target and not Bridge.Streamer.hideESP then
			local pos, vis = WorldToViewportPoint(Camera, target.Position)

			if vis then
				-- Name ESP
				if Toggles.espNameToggled.Value then
					local nt = Options.espNameType.Value
					if nt == "Account Name" then
						nameEsp.Text = player.Name
					elseif nt == "Both (Display + @User)" then
						nameEsp.Text = player.DisplayName .. " (@" .. player.Name .. ")"
					else
						nameEsp.Text = player.DisplayName
					end
					
					if Toggles.espDistanceToggled.Value then
						nameEsp.Text = nameEsp.Text .. " [" .. math.floor(distance) .. "m]"
					end
					
					if Toggles.espNameUseTeamColor.Value then
						nameEsp.Color = player.TeamColor.Color
					else
						nameEsp.Color = Options.espNameColor1.Value
					end
					nameEsp.Color = flashCol or nameEsp.Color
						pcall(function() nameEsp.Transparency = fade end)
						nameEsp.OutlineColor = Options.espNameColor2.Value
					nameEsp.Position = Vector2.new(pos.X, pos.Y)
					-- User-controlled fixed size (no distance inflation) so names stay
					-- legible and don't balloon/overlap when players clump together.
					nameEsp.Size = (Options.espNameSize and Options.espNameSize.Value) or 14
					nameEsp.Visible = true

						-- Register this name for the post-loop anti-overlap pass.
						table.insert(espNameSlots, { label = nameEsp, team = teamEsp, x = pos.X, y = pos.Y, size = nameEsp.Size })

					-- Tiny team-name subscript directly below the name
					if Toggles.espTeamToggled.Value then
						local teamName = player.Team and player.Team.Name or nil
						if teamName then
							teamEsp.Text = teamName
							teamEsp.Color = nameEsp.Color
							teamEsp.OutlineColor = Options.espNameColor2.Value
							teamEsp.Size = math.max(9, nameEsp.Size * 0.6)
							teamEsp.Position = Vector2.new(pos.X, pos.Y + nameEsp.Size)
							teamEsp.Visible = true
						else
							teamEsp.Visible = false
						end
					else
						teamEsp.Visible = false
					end
				else
					nameEsp.Visible = false
					teamEsp.Visible = false
				end
				
				-- Health Bar
				if Toggles.espHealthBarToggled.Value then
					local humanoid = playerChar:FindFirstChildWhichIsA("Humanoid")
					if humanoid then
						local healthPercent = humanoid.Health / humanoid.MaxHealth
						local barWidth = 50
						local barHeight = 5
						healthBar.Size = Vector2.new(barWidth * healthPercent, barHeight)
						healthBar.Position = Vector2.new(pos.X - barWidth/2, pos.Y - 20)
						healthBar.Color = Color3.fromRGB(255 * (1 - healthPercent), 255 * healthPercent, 0)
						healthBar.Visible = true
					else
						healthBar.Visible = false
					end
				else
					healthBar.Visible = false
				end

				-- Health Text (numeric HP next to the bar)
				if Toggles.espHealthTextToggled.Value then
					local humanoid = playerChar:FindFirstChildWhichIsA("Humanoid")
					if humanoid and humanoid.MaxHealth > 0 then
						local pct = humanoid.Health / humanoid.MaxHealth
						healthText.Text = tostring(math.floor(humanoid.Health))
						healthText.Color = Color3.fromRGB(math.floor(255 * (1 - pct)), math.floor(255 * pct), 0)
						healthText.OutlineColor = Color3.fromRGB(0, 0, 0)
						healthText.Size = 13
						healthText.Position = Vector2.new(pos.X + 28, pos.Y - 24)
						healthText.Visible = true
					else
						healthText.Visible = false
					end
				else
					healthText.Visible = false
				end

				-- 2D Box: derive a screen-space rectangle from the character's part
				-- POSITIONS only (head-top -> below the root), never their Sizes. This
				-- is deliberate: when the hitbox extender is on, GetBoundingBox() (the
				-- old method) grew to include the enlarged parts, producing huge boxes
				-- that overlapped and jumbled together when players bunched up.
				-- Position-based sizing is immune to that, and the Box Size slider
				-- tightens it further.
				if Toggles.espBoxToggled.Value then
					local rootPart = playerChar:FindFirstChild("HumanoidRootPart") or target
					local head = playerChar:FindFirstChild("Head")
					if rootPart then
						local rootPos = rootPart.Position
						local topPos = (head and head.Position or rootPos) + Vector3.new(0, 0.5, 0)
						local botPos = rootPos - Vector3.new(0, 3, 0)
						local topV = WorldToViewportPoint(Camera, topPos)
						local botV = WorldToViewportPoint(Camera, botPos)
						local scale = (Options.espBoxScale and Options.espBoxScale.Value) or 0.85
						local height = math.abs(topV.Y - botV.Y) * scale
						local width = height * 0.5
						boxEsp.Size = Vector2.new(width, height)
						boxEsp.Position = Vector2.new(pos.X - width / 2, pos.Y - height / 2)
						boxEsp.Color = flashCol or Options.espNameColor1.Value
						boxEsp.Thickness = thick
						pcall(function() boxEsp.Transparency = fade end)
						boxEsp.Visible = true
					else
						boxEsp.Visible = false
					end
				else
					boxEsp.Visible = false
				end
				
				-- Tracer
				if Toggles.espTracerToggled.Value then
					tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
					tracer.To = Vector2.new(pos.X, pos.Y)
					tracer.Color = flashCol or Options.espTracerColor.Value
					tracer.Thickness = thick
					pcall(function() tracer.Transparency = fade end)
					tracer.Visible = true
				else
					tracer.Visible = false
				end

				-- Skeleton ESP (connects bones; missing parts are skipped)
				if Toggles.espSkeletonToggled.Value then
					local idx = 0
					local col = flashCol or (Toggles.espNameUseTeamColor.Value and player.TeamColor.Color or Options.espNameColor1.Value)
					for _, bone in ipairs(SKELETON_BONES) do
						local a = playerChar:FindFirstChild(bone[1])
						local b = playerChar:FindFirstChild(bone[2])
						if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
							local pa, va = WorldToViewportPoint(Camera, a.Position)
							local pb, vb = WorldToViewportPoint(Camera, b.Position)
							if va and vb then
								idx += 1
								local ln = skeletonLines[idx]
								if ln then
									ln.From = Vector2.new(pa.X, pa.Y)
									ln.To = Vector2.new(pb.X, pb.Y)
									ln.Color = col
									ln.Thickness = thick
									ln.Visible = true
								end
							end
						end
					end
					for i = idx + 1, #skeletonLines do skeletonLines[i].Visible = false end
				else
					hideSkeleton()
				end
			else
				-- Player exists but is off-screen
				nameEsp.Visible = false
				healthBar.Visible = false
				boxEsp.Visible = false
				tracer.Visible = false
				healthText.Visible = false
				hideSkeleton()

				-- Off-screen marker pointing from screen center toward the player
				if Toggles.espOffscreenToggled.Value then
					local vp = Camera.ViewportSize
					local center = Vector2.new(vp.X / 2, vp.Y / 2)
					local dir = Vector2.new(pos.X, pos.Y) - center
					if pos.Z < 0 then dir = -dir end
					if dir.Magnitude < 1 then dir = Vector2.new(0, -1) end
					dir = dir.Unit
					local markerPos = center + dir * (math.min(vp.X, vp.Y) / 2 - 40)
					offscreenMarker.Size = Vector2.new(10, 10)
					offscreenMarker.Position = Vector2.new(markerPos.X - 5, markerPos.Y - 5)
					offscreenMarker.Color = flashCol or (Toggles.espNameUseTeamColor.Value and player.TeamColor.Color or Options.espNameColor1.Value)
					offscreenMarker.Visible = true
				else
					offscreenMarker.Visible = false
				end
			end
		else
			nameEsp.Visible = false
			healthBar.Visible = false
			boxEsp.Visible = false
			tracer.Visible = false
		end
		
		-- Chams (independently suppressed by Streamer Mode's hideChams flag)
		if Toggles.espHighlightToggled.Value and not Bridge.Streamer.hideChams then
			chams.Adornee = playerChar
			if Toggles.espHighlightUseTeamColor.Value then
				chams.FillColor = player.TeamColor.Color
				chams.OutlineColor = player.TeamColor.Color
			else
				chams.FillColor = Options.espHighlightColor1.Value
				chams.OutlineColor = Options.espHighlightColor2.Value
			end
			if flashCol then chams.FillColor = flashCol; chams.OutlineColor = flashCol end
			chams.DepthMode = Enum.HighlightDepthMode[Options.espHighlightDepthMode.Value]
			chams.FillTransparency = Options.espHighlightFillTransparency.Value
			if Toggles.espChamsGlow and Toggles.espChamsGlow.Value then
				-- Glow pulse: oscillate the outline transparency over time.
				chams.OutlineTransparency = 0.5 + 0.5 * math.abs(math.sin(tick() * 3))
			else
				chams.OutlineTransparency = Options.espHighlightOutlineTransparency.Value
			end
			chams.Enabled = true
		else
			chams.Enabled = false
		end
	end

	function playerIdx:DeleteVisuals()
		nameEsp:Remove()
		teamEsp:Remove()
		healthBar:Remove()
		healthText:Remove()
		offscreenMarker:Remove()
		boxEsp:Remove()
		tracer:Remove()
		for _, ln in ipairs(skeletonLines) do ln:Remove() end
		chams:Destroy()
	end

	-- Character handling
	local function WaitForFullChar(char)
		local startTime = tick()
		local humanoid = char:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then
			repeat
				if char == nil then
					return false
				end
				humanoid = char:FindFirstChildWhichIsA("Humanoid")
				task.wait()
			until humanoid or tick()-startTime >= 2
		end
		local loaded = false
		startTime = tick()
		repeat
			local limbs = 0
			for _, v in pairs(char:GetChildren()) do
				if humanoid:GetLimb(v) ~= Enum.Limb.Unknown then
					limbs += 1
				end
			end
			if limbs == 6 or limbs == 15 then
				loaded = true
			end
			task.wait()
		until loaded or tick()-startTime >= 3
		return true
	end

	player.CharacterAdded:Connect(function(character)
		playerChar = character
		defaultProperties = {}
		currentSizes = {}
		targetSizes = {}
		appliedProps = {}
		hookedParts = {}
		if WaitForFullChar(character) then
			playerIdx:Update()
			local humanoid = character:FindFirstChildWhichIsA("Humanoid")
			if humanoid then
				humanoid:GetPropertyChangedSignal("Health"):Connect(function()
					if humanoid.Health <= 0 then
						playerIdx:Update()
					end
				end)
				humanoid.StateChanged:Connect(function(_, newState)
					if newState == Enum.HumanoidStateType.Dead then
						playerIdx:Update()
					end
				end)
			end
			if character:FindFirstChildWhichIsA("ForceField") then
				playerIdx:Update()
			end
			character.ChildAdded:Connect(function(child)
				pcall(function()
					if game.GameId == 718936923 then -- Neighborhood War
						if child.Name == "Dead" then
							playerIdx:Update()
							return
						end
					end
					if child:IsA("ForceField") then
						playerIdx:Update()
					end
				end)
			end)
			character.ChildRemoved:Connect(function(child)
				if child:IsA("ForceField") then
					playerIdx:Update()
				end
			end)
			if game.PlaceId == 4991214437 or game.PlaceId == 6652350934 then -- town
				local head = playerChar:FindFirstChild("Head")
				if head then
					head:GetPropertyChangedSignal("Material"):Connect(function()
						playerIdx:Update()
					end)
				end
			end
		end
	end)
	
	player.CharacterRemoving:Connect(function()
		if playerIdx then
			defaultProperties = {}
			currentSizes = {}
			targetSizes = {}
			for part, hooks in pairs(hookedParts) do
				pcall(function()
					hooks.changed:Disconnect()
				end)
			end
			hookedParts = {}
		end
	end)
	
	player:GetPropertyChangedSignal("Team"):Connect(function()
		playerIdx:Update()
	end)
	
	if game.PlaceId == 6172932937 then -- Energy Assault
		pcall(function()
			local ragdolled = player:WaitForChild("ragdolled")
			ragdolled.Changed:Connect(function()
				playerIdx:Update()
			end)
		end)
	end
	
	if game.GameId == 1934496708 then -- Project: SCP
		pcall(function()
			local ff = Workspace:WaitForChild("FriendlyFire")
			ff.Changed:Connect(function()
				playerIdx:Update()
			end)
		end)
	end
	
	if game.GameId == 2162282815 then -- Rush Point
		pcall(function()
			local mapFolder = Workspace:WaitForChild("MapFolder")
			local gamePlayers = mapFolder:WaitForChild("Players")
			for _,v in pairs(gamePlayers:GetChildren()) do
				if v.Name == player.Name then
					playerChar = v
					playerIdx:Update()
				end
			end
			gamePlayers.ChildAdded:Connect(function(v)
				if v.Name == player.Name then
					playerChar = v
					playerIdx:Update()
				end
			end)
		end)
	end
	
	if game.PlaceId == 4991214437 or game.PlaceId == 6652350934 then -- town
		if playerChar then
			local head = playerChar:FindFirstChild("Head")
			if head then
				head:GetPropertyChangedSignal("Material"):Connect(function()
					playerIdx:Update()
				end)
			end
		end
	end
end

local function removePlayer(player)
	if not players[player] then return end
	
	pcall(function()
		players[player]:DeleteVisuals()
	end)
	eligibleSince[player] = nil

	pcall(function()
		local idx = table.find(Options.ignorePlayerList.Values, player.Name)
		if idx then
			table.remove(Options.ignorePlayerList.Values, idx)
			updateList(Options.ignorePlayerList)
		end
	end)
	
	pcall(function()
		local idx = table.find(Options.whitelistPlayerList.Values, player.Name)
		if idx then
			table.remove(Options.whitelistPlayerList.Values, idx)
			updateList(Options.whitelistPlayerList)
		end
	end)
	
	pcall(function()
		local idx = table.find(Options.priorityPlayerList.Values, player.Name)
		if idx then
			table.remove(Options.priorityPlayerList.Values, idx)
			updateList(Options.priorityPlayerList)
		end
	end)
	
	players[player] = nil
end

-- Initialize players (with failsafe)
for _, player in ipairs(Players:GetPlayers()) do
	if player == lPlayer then
		continue
	end
	pcall(function()
		addPlayer(player)
	end)
end

for _, team in pairs(Teams:GetTeams()) do
	if team:IsA("Team") then
		pcall(function()
			table.insert(Options.ignoreTeamList.Values, team.Name)
			updateList(Options.ignoreTeamList)
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	pcall(function()
		addPlayer(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	pcall(function()
		removePlayer(player)
	end)
end)

Teams.ChildAdded:Connect(function(team)
	if team:IsA("Team") then
		pcall(function()
			table.insert(Options.ignoreTeamList.Values, team.Name)
			updateList(Options.ignoreTeamList)
		end)
	end
end)

Teams.ChildRemoved:Connect(function(team)
	if team:IsA("Team") then
		pcall(function()
			local idx = table.find(Options.ignoreTeamList.Values, team.Name)
			if idx then
				table.remove(Options.ignoreTeamList.Values, idx)
				updateList(Options.ignoreTeamList)
			end
		end)
	end
end)

lPlayer:GetAttributeChangedSignal("Team"):Connect(function()
	pcall(updatePlayers)
end)

lPlayer.CharacterAdded:Connect(function()
	pcall(updatePlayers)
end)

-- Status + hitbox update loop (with failsafe).
-- Because this build uses no namecall/property hooks, hitbox extension must be
-- re-applied continuously or the game can reset part sizes back to normal.
-- runUpdatePlayers() self-throttles to the "Update Rate" slider, so this is the
-- single driver that keeps extensions persistent AND makes that slider meaningful.
RunService.Heartbeat:Connect(function()
	pcall(updateStatus)
	pcall(updatePlayers)
	pcall(updateWorldParts)
end)

-- Game-specific anticheat handling
if game.PlaceId == 111311599 then
	pcall(function()
		local anticheat = game:GetService("ReplicatedFirst")["Serverbased AntiCheat"]
		local sValue = lPlayer:WaitForChild("SValue")
		local function constructAnticheatString()
			return "CS-" .. math.random(11111, 99999) .. "-" .. math.random(1111, 9999) .. "-" .. math.random(111111, 999999) .. math.random(1111111, 9999999) .. (sValue.Value * 6) ^ 2 + 18
		end
		task.spawn(function()
			while true do
				task.wait(2)
				pcall(function()
					game:GetService("ReplicatedStorage").ACDetect:FireServer(sValue.Value, constructAnticheatString())
				end)
			end
		end)
		anticheat.Disabled = true
	end)
end

-- Final initialization with failsafe
local function finalInit()
	-- Honor the Master Toggle's default state on load
	if Toggles.MasterToggle and Toggles.MasterToggle.Value then
		getgenv().FurryHBELoaded = true
	end
	pcall(updatePlayers)
	
	if Library and Library.Notify then
		Library:Notify("hai :3")
		if Library.ToggleKeybind and Library.ToggleKeybind.Value then
			Library:Notify("Press " .. Library.ToggleKeybind.Value .. " to open the menu")
		end
	end
	
	-- Show error summary if there were any errors
	if #errorLog > 0 then
		task.wait(1)
		Library:Notify("Loaded with " .. #errorLog .. " error(s) - check console")
		for i, err in ipairs(errorLog) do
			warn("[Error " .. i .. "] " .. err.context .. ": " .. err.error)
		end
	end
end

-- ============================================================================
--  INLINED ADD-ONS  (Precision / Streamer / Teleport)
--  These were previously separate files loaded at runtime; they are now built
--  straight into this single script. Each is wrapped in pcall so one failing
--  can never abort the others or the main script, and each registers its
--  teardown through Bridge:RegisterAddon (run by cleanup()/Library unload).
--  They use the locals already in scope (Bridge, Library, mainWindow,
--  DrawingFallback, Players/RunService/Workspace) plus the global Toggles/Options.
-- ============================================================================

-- ----- Precision HBE (standalone single-target extender) --------------------
pcall(function()
	local HttpService = game:GetService("HttpService")
	local cam     = Workspace.CurrentCamera
	local lPlayer = Players.LocalPlayer
	local CFG_FILE = "FurryHBE_Precision.json"

	local precisionTab = mainWindow:AddTab("Precision")

	local hbeGroup      = precisionTab:AddLeftGroupbox("Precision HBE")
	local targetGroup   = precisionTab:AddLeftGroupbox("Target Selection")
	local antiGroup     = precisionTab:AddLeftGroupbox("Filters / Anti-Detection")
	local scalingGroup  = precisionTab:AddRightGroupbox("Dynamic Scaling")
	local zoneGroup     = precisionTab:AddRightGroupbox("Visual Zone")
	local debugGroup    = precisionTab:AddRightGroupbox("Info")
	local cfgGroup      = precisionTab:AddRightGroupbox("Config")

	hbeGroup:AddToggle("precisionEnabled", { Text = "Enable Precision HBE", Default = false, Tooltip = "Standalone single-target hitbox extender. Works even with the main Master Toggle off." })
	hbeGroup:AddToggle("precisionExclusive", { Text = "Exclusive Mode", Default = false, Tooltip = "Also switch the main mass-extender OFF while Precision is active. (Claims already stop the two fighting over your target, so this is optional.)" })
	hbeGroup:AddSlider("precisionHitboxSize", { Text = "Base Hitbox Size", Min = 2, Max = 100, Default = 12, Rounding = 1, Tooltip = "Base size applied to the target's parts (before dynamic scaling)" })
	hbeGroup:AddSlider("precisionTransparency", { Text = "Transparency", Min = 0, Max = 1, Default = 0.6, Rounding = 2, Tooltip = "Transparency of the extended hitbox (0 = solid, 1 = invisible)" })
	hbeGroup:AddDropdown("precisionShape", { Text = "Hitbox Shape", AllowNull = false, Multi = false, Values = { "Cube", "Flat (disk)", "Tall (pillar)" }, Default = "Cube", Tooltip = "Cube = uniform; Flat = wide & short; Tall = narrow & tall" })
	hbeGroup:AddToggle("precisionCollisions", { Text = "Keep Collisions", Default = false, Tooltip = "Leave the extended part collidable (off = restore original CanCollide)" })
	hbeGroup:AddToggle("precisionSmooth", { Text = "Smooth Transitions", Default = false, Tooltip = "Interpolate size changes instead of snapping" })
	hbeGroup:AddSlider("precisionSmoothSpeed", { Text = "Smooth Speed", Min = 0.05, Max = 1, Default = 0.3, Rounding = 2, Tooltip = "How fast the size eases toward the target (1 = instant)" })
	hbeGroup:AddDropdown("precisionParts", { Text = "Parts to Extend", AllowNull = true, Multi = true, Values = { "HumanoidRootPart", "Head", "Torso", "UpperTorso", "LowerTorso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }, Default = "HumanoidRootPart", Tooltip = "Which of the target's parts to extend" })

	targetGroup:AddToggle("autoSelectTarget", { Text = "Auto-Select Target", Default = true, Tooltip = "Automatically lock onto the nearest visible player" })
	targetGroup:AddSlider("selectionRadius", { Text = "Selection Radius (studs)", Min = 5, Max = 1000, Default = 150, Rounding = 1, Tooltip = "Max distance for auto-selection" })
	targetGroup:AddLabel("Manual Target"):AddKeyPicker("targetKeybind", { Default = "T", NoUI = true, Text = "Cycle Target" })

	antiGroup:AddToggle("precisionRespectWhitelist", { Text = "Respect Whitelist", Default = true, Tooltip = "Never target players on the main script's whitelist" })
	antiGroup:AddToggle("precisionIgnoreTeam", { Text = "Ignore Teammates", Default = false, Tooltip = "Skip players on your team (Team / TeamColor based)" })
	antiGroup:AddToggle("precisionAutoOffDead", { Text = "Auto-Off When Dead", Default = true, Tooltip = "Stop extending while you are dead or have no character" })
	antiGroup:AddToggle("precisionFOVGate", { Text = "FOV Gate", Default = false, Tooltip = "Only extend when the target is within the FOV radius of your crosshair" })
	antiGroup:AddSlider("precisionFOVRadius", { Text = "FOV Radius (px)", Min = 20, Max = 600, Default = 150, Rounding = 0 })
	antiGroup:AddToggle("precisionRandomize", { Text = "Randomize Size", Default = false, Tooltip = "Add slight per-frame jitter to the hitbox size" })
	antiGroup:AddSlider("precisionRandomAmount", { Text = "Random Amount", Min = 0, Max = 5, Default = 1, Rounding = 1 })

	scalingGroup:AddToggle("dynamicScalingEnabled", { Text = "Dynamic Distance Scaling", Default = true, Tooltip = "Scale the hitbox between Close and Far factors based on distance" })
	scalingGroup:AddSlider("scalingCloseFactor", { Text = "Close Range Factor", Min = 0.5, Max = 3.0, Default = 1.5, Rounding = 2 })
	scalingGroup:AddSlider("scalingFarFactor", { Text = "Far Range Factor", Min = 0.1, Max = 3.0, Default = 0.6, Rounding = 2 })
	scalingGroup:AddSlider("scalingThreshold", { Text = "Close/Far Threshold (studs)", Min = 10, Max = 300, Default = 60, Rounding = 1 })

	zoneGroup:AddToggle("showVisualZone", { Text = "Show Interaction Zone", Default = true })
	zoneGroup:AddSlider("zoneRadius", { Text = "Zone Radius (studs)", Min = 5, Max = 100, Default = 15, Rounding = 1 })
	zoneGroup:AddLabel("Zone Color"):AddColorPicker("zoneColor", { Title = "Zone Color", Default = Color3.fromRGB(0, 255, 255) })

	debugGroup:AddToggle("showProximityLabel", { Text = "Show Proximity Label", Default = true })
	debugGroup:AddToggle("showDistance", { Text = "Show Target Distance", Default = true })
	local infoTargetLabel = debugGroup:AddLabel("Target: none")
	local infoSizeLabel   = debugGroup:AddLabel("Applied size: -")

	local PRECISION_KEYS = {
		"precisionEnabled","precisionExclusive","precisionHitboxSize","precisionTransparency",
		"precisionShape","precisionCollisions","precisionSmooth","precisionSmoothSpeed","precisionParts",
		"autoSelectTarget","selectionRadius",
		"precisionRespectWhitelist","precisionIgnoreTeam","precisionAutoOffDead",
		"precisionFOVGate","precisionFOVRadius","precisionRandomize","precisionRandomAmount",
		"dynamicScalingEnabled","scalingCloseFactor","scalingFarFactor","scalingThreshold",
		"showVisualZone","zoneRadius","showProximityLabel","showDistance",
	}
	local function savePrecisionConfig()
		if not writefile then Library:Notify("Executor has no writefile"); return end
		local data = {}
		for _, k in ipairs(PRECISION_KEYS) do
			local c = Options[k] or Toggles[k]
			if c ~= nil then data[k] = c.Value end
		end
		local ok = pcall(function() writefile(CFG_FILE, HttpService:JSONEncode(data)) end)
		Library:Notify(ok and "Precision config saved" or "Save failed")
	end
	local function loadPrecisionConfig(notify)
		if not (isfile and readfile and isfile(CFG_FILE)) then
			if notify then Library:Notify("No saved Precision config") end
			return
		end
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CFG_FILE)) end)
		if ok and type(data) == "table" then
			for k, v in pairs(data) do
				local c = Options[k] or Toggles[k]
				if c then pcall(function() c:SetValue(v) end) end
			end
			if notify then Library:Notify("Precision config loaded") end
		elseif notify then
			Library:Notify("Saved config was unreadable")
		end
	end
	cfgGroup:AddButton("Save Config", savePrecisionConfig):AddToolTip("Write current Precision settings to " .. CFG_FILE)
	cfgGroup:AddButton("Load Config", function() loadPrecisionConfig(true) end):AddToolTip("Restore Precision settings from disk")

	local visualZone = DrawingFallback.new("Circle")
	visualZone.Thickness = 1; visualZone.Filled = false; visualZone.Visible = false
	local proximityLabel = DrawingFallback.new("Text")
	proximityLabel.Center = true; proximityLabel.Outline = true; proximityLabel.Size = 18; proximityLabel.Visible = false
	local targetNameLabel = DrawingFallback.new("Text")
	targetNameLabel.Center = true; targetNameLabel.Outline = true; targetNameLabel.Size = 14; targetNameLabel.Visible = false

	local selectedTarget     = nil
	local lastExtendedChar   = nil
	local extendedParts      = {}
	local claimedPlayer      = nil
	local currentAppliedSize = nil
	local lastInfoUpdate     = 0

	local function claim(plr)
		if claimedPlayer ~= plr then
			if claimedPlayer then Bridge:ReleasePlayer(claimedPlayer) end
			Bridge:ClaimPlayer(plr, "Precision")
			claimedPlayer = plr
		end
	end
	local function releaseClaim()
		if claimedPlayer then Bridge:ReleasePlayer(claimedPlayer); claimedPlayer = nil end
	end

	local function restoreExtended()
		for part, orig in pairs(extendedParts) do
			if typeof(part) == "Instance" and part.Parent then
				pcall(function()
					part.Size = orig.Size; part.Transparency = orig.Transparency; part.CanCollide = orig.CanCollide
				end)
			end
			extendedParts[part] = nil
		end
	end

	local function isLocalDead()
		local char = lPlayer.Character
		if not char then return true end
		local hum = char:FindFirstChildWhichIsA("Humanoid")
		if not hum then return true end
		return hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead
	end

	local function targetDistance(char)
		local node = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
		local lChar = lPlayer.Character
		local lNode = lChar and (lChar:FindFirstChild("HumanoidRootPart") or lChar:FindFirstChild("Head"))
		if node and lNode then return (node.Position - lNode.Position).Magnitude end
		return math.huge
	end

	local function computeSize(dist)
		local base = Options.precisionHitboxSize.Value
		if not Toggles.dynamicScalingEnabled.Value then return base end
		local threshold = math.max(1, Options.scalingThreshold.Value)
		local t = math.clamp(dist / threshold, 0, 1)
		return base * (Options.scalingCloseFactor.Value + (Options.scalingFarFactor.Value - Options.scalingCloseFactor.Value) * t)
	end

	local function sizeVectorForShape(s)
		local shape = Options.precisionShape and Options.precisionShape.Value or "Cube"
		if shape == "Flat (disk)" then
			return Vector3.new(s, math.max(1, s * 0.25), s)
		elseif shape == "Tall (pillar)" then
			return Vector3.new(math.max(1, s * 0.5), s * 1.5, math.max(1, s * 0.5))
		end
		return Vector3.new(s, s, s)
	end

	local function extendChar(char, scalar)
		local names   = Options.precisionParts:GetActiveValues()
		local transp  = Options.precisionTransparency.Value
		local keepCol = Toggles.precisionCollisions.Value
		if Toggles.precisionRandomize.Value then
			scalar = math.max(1, scalar + (math.random() * 2 - 1) * Options.precisionRandomAmount.Value)
		end
		local desired = {}
		for _, n in ipairs(names) do
			local p = char:FindFirstChild(n)
			if p and p:IsA("BasePart") then desired[p] = true end
		end
		for part, orig in pairs(extendedParts) do
			if not desired[part] then
				if typeof(part) == "Instance" and part.Parent then
					pcall(function() part.Size = orig.Size; part.Transparency = orig.Transparency; part.CanCollide = orig.CanCollide end)
				end
				extendedParts[part] = nil
			end
		end
		for part in pairs(desired) do
			local e = extendedParts[part]
			if not e then
				e = { Size = part.Size, Transparency = part.Transparency, CanCollide = part.CanCollide, Cur = scalar }
				extendedParts[part] = e
			end
			local applied = scalar
			if Toggles.precisionSmooth.Value then
				e.Cur = e.Cur + (scalar - e.Cur) * Options.precisionSmoothSpeed.Value
				applied = e.Cur
			else
				e.Cur = scalar
			end
			pcall(function()
				part.Size = sizeVectorForShape(applied)
				part.Transparency = transp
				part.CanCollide = keepCol and true or e.CanCollide
			end)
		end
	end

	local function passesFilters(plr, char)
		if Toggles.precisionRespectWhitelist.Value and Options.whitelistPlayerList then
			if table.find(Options.whitelistPlayerList:GetActiveValues(), plr.Name) then return false end
		end
		if Toggles.precisionIgnoreTeam.Value then
			local ok, same = pcall(function()
				if lPlayer.Team ~= nil or plr.Team ~= nil then return lPlayer.Team == plr.Team end
				return lPlayer.TeamColor == plr.TeamColor
			end)
			if ok and same then return false end
		end
		if Toggles.precisionFOVGate.Value then
			local head = char:FindFirstChild("Head")
			if not head then return false end
			local p, on = cam:WorldToViewportPoint(head.Position)
			if not on then return false end
			local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
			if (Vector2.new(p.X, p.Y) - center).Magnitude > Options.precisionFOVRadius.Value then return false end
		end
		return true
	end

	local function getClosestVisiblePlayer(maxDist)
		local bestDist, bestPlr = maxDist or math.huge, nil
		for _, plr in pairs(Players:GetPlayers()) do
			if plr ~= lPlayer then
				local char = plr.Character
				local head = char and char:FindFirstChild("Head")
				local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
				if head and hum and hum.Health > 0 and passesFilters(plr, char) then
					local _, onScreen = cam:WorldToViewportPoint(head.Position)
					if onScreen then
						local dist = (head.Position - cam.CFrame.Position).Magnitude
						if dist < bestDist then bestDist, bestPlr = dist, plr end
					end
				end
			end
		end
		return bestPlr
	end

	local function cycleTarget()
		local alive = {}
		for _, plr in pairs(Players:GetPlayers()) do
			local char = plr.Character
			local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
			if plr ~= lPlayer and hum and hum.Health > 0 and passesFilters(plr, char) then
				table.insert(alive, plr)
			end
		end
		if #alive == 0 then selectedTarget = nil; return end
		if not selectedTarget or not table.find(alive, selectedTarget) then
			selectedTarget = alive[1]
		else
			local idx = table.find(alive, selectedTarget) + 1
			if idx > #alive then idx = 1 end
			selectedTarget = alive[idx]
		end
	end

	Options.targetKeybind:OnClick(function()
		if Toggles.precisionEnabled.Value then
			Toggles.autoSelectTarget:SetValue(false)
			cycleTarget()
		end
	end)

	local function applyExclusive()
		if Toggles.precisionEnabled.Value and Toggles.precisionExclusive.Value then
			if Toggles.extenderToggled and Toggles.extenderToggled.Value then
				Toggles.extenderToggled:SetValue(false)
				Library:Notify("Precision exclusive: main extender disabled")
			end
		end
	end
	Toggles.precisionEnabled:OnChanged(function()
		if Toggles.precisionEnabled.Value then
			applyExclusive()
		else
			restoreExtended(); releaseClaim()
			lastExtendedChar = nil; selectedTarget = nil
		end
	end)
	Toggles.precisionExclusive:OnChanged(applyExclusive)

	local function precisionTick()
		if not Toggles.precisionEnabled.Value then return end
		if Toggles.precisionAutoOffDead.Value and isLocalDead() then
			if next(extendedParts) then restoreExtended() end
			releaseClaim(); lastExtendedChar = nil; currentAppliedSize = nil
			return
		end
		-- Respect the main script's "Disable While Seated" (shared via Toggles).
		-- Honors radius mode: only stop if the target is within the seated radius.
		if Toggles.seatDisableHBE and Toggles.seatDisableHBE.Value and isLocalSeated() then
			local stop = true
			if Toggles.seatRadiusMode and Toggles.seatRadiusMode.Value then
				local c = selectedTarget and selectedTarget.Character
				stop = c ~= nil and targetDistance(c) <= (Options.seatRadius and Options.seatRadius.Value or 30)
			end
			if stop then
				if next(extendedParts) then restoreExtended() end
				releaseClaim(); lastExtendedChar = nil; currentAppliedSize = nil
				return
			end
		end
		cam = Workspace.CurrentCamera
		if Toggles.autoSelectTarget.Value then
			selectedTarget = getClosestVisiblePlayer(Options.selectionRadius.Value)
		end
		local char = selectedTarget and selectedTarget.Character
		local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
		local alive = hum and hum.Health > 0 and passesFilters(selectedTarget, char)
		if char ~= lastExtendedChar or not alive then
			restoreExtended(); releaseClaim()
			lastExtendedChar = (char and alive) and char or nil
		end
		if char and alive then
			claim(selectedTarget)
			local dist = targetDistance(char)
			currentAppliedSize = computeSize(dist)
			extendChar(char, currentAppliedSize)
		else
			currentAppliedSize = nil
		end
	end

	local function precisionVisuals()
		if not Toggles.precisionEnabled.Value then
			visualZone.Visible = false; proximityLabel.Visible = false; targetNameLabel.Visible = false
			return
		end
		cam = Workspace.CurrentCamera
		local now = tick()
		if now - lastInfoUpdate > 0.2 then
			lastInfoUpdate = now
			local char = selectedTarget and selectedTarget.Character
			if char then
				infoTargetLabel:SetText("Target: " .. selectedTarget.Name .. " (" .. math.floor(targetDistance(char)) .. "m)")
				infoSizeLabel:SetText("Applied size: " .. (currentAppliedSize and string.format("%.1f", currentAppliedSize) or "-"))
			else
				infoTargetLabel:SetText("Target: none"); infoSizeLabel:SetText("Applied size: -")
			end
		end
		if Toggles.showVisualZone.Value then
			local root = lPlayer.Character and lPlayer.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local pos, onScreen = cam:WorldToViewportPoint(root.Position)
				if onScreen and pos.Z > 0 then
					visualZone.Visible = true
					local scale = 1000 / pos.Z
					visualZone.Radius = Options.zoneRadius.Value * scale
					visualZone.Position = Vector2.new(pos.X, pos.Y)
					visualZone.Color = Options.zoneColor.Value
				else visualZone.Visible = false end
			else visualZone.Visible = false end
		else visualZone.Visible = false end
		local char = selectedTarget and selectedTarget.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		if char and hum and hum.Health > 0 then
			local head = char:FindFirstChild("Head")
			if head then
				local pos, onScreen = cam:WorldToViewportPoint(head.Position)
				local d = targetDistance(char)
				if onScreen then
					if Toggles.showProximityLabel.Value then
						local category = d < 10 and "Close" or (d < 30 and "Medium" or "Far")
						proximityLabel.Text = category
						proximityLabel.Position = Vector2.new(pos.X, pos.Y - 30)
						proximityLabel.Color = category == "Close" and Color3.fromRGB(0,255,0)
							or (category == "Medium" and Color3.fromRGB(255,255,0)) or Color3.fromRGB(255,0,0)
						proximityLabel.Visible = true
					else proximityLabel.Visible = false end
					local txt = selectedTarget.Name
					if Toggles.showDistance.Value then txt = txt .. " [" .. math.floor(d) .. "m]" end
					targetNameLabel.Text = txt
					targetNameLabel.Position = Vector2.new(pos.X, pos.Y - 45)
					targetNameLabel.Color = Color3.fromRGB(255,255,255)
					targetNameLabel.Visible = true
				else proximityLabel.Visible = false; targetNameLabel.Visible = false end
			else proximityLabel.Visible = false; targetNameLabel.Visible = false end
		else
			proximityLabel.Visible = false; targetNameLabel.Visible = false
		end
	end

	local hbConn = RunService.Heartbeat:Connect(function() pcall(precisionTick) end)
	RunService:BindToRenderStep("PrecisionVisuals", Enum.RenderPriority.Camera.Value + 1, function() pcall(precisionVisuals) end)

	Bridge:RegisterAddon("Precision", {
		onUnload = function()
			pcall(restoreExtended)
			pcall(releaseClaim)
			if hbConn then pcall(function() hbConn:Disconnect() end) end
			pcall(function() RunService:UnbindFromRenderStep("PrecisionVisuals") end)
			pcall(function() visualZone:Remove() end)
			pcall(function() proximityLabel:Remove() end)
			pcall(function() targetNameLabel:Remove() end)
		end,
	})

	pcall(function() loadPrecisionConfig(false) end)
	print("[Precision HBE] Built-in module loaded.")
end)

-- ----- Streamer Mode --------------------------------------------------------
pcall(function()
	local mainGui = Library.ScreenGui

	local streamTab    = mainWindow:AddTab("Streamer")
	local visualsGroup  = streamTab:AddLeftGroupbox("Visual Overrides")
	local uiGroup       = streamTab:AddLeftGroupbox("UI Control")
	local panicGroup    = streamTab:AddRightGroupbox("Panic")
	local miscGroup     = streamTab:AddRightGroupbox("Extra")

	visualsGroup:AddToggle("streamerMaster", { Text = "Streamer Mode", Default = false, Tooltip = "Hide all visual indicators while keeping hitbox functionality active" })
	visualsGroup:AddToggle("hideFOVCircle",  { Text = "Hide FOV Circle",  Default = true })
	visualsGroup:AddToggle("hidePlayerESP",  { Text = "Hide Player ESP",  Default = true })
	visualsGroup:AddToggle("hideChams",      { Text = "Hide Chams",       Default = true })
	visualsGroup:AddToggle("hideHitboxGlow", { Text = "Hide Hitbox Glow", Default = true, Tooltip = "Force extended hitboxes fully transparent (without touching your Transparency slider)" })

	uiGroup:AddToggle("hideUIOnToggle", { Text = "Hide UI with Streamer Mode", Default = false, Tooltip = "Also hide the HBE window itself whenever Streamer Mode is on" })
	uiGroup:AddLabel("Hide/Show UI"):AddKeyPicker("hideUIKey", { Default = "F8", NoUI = true, Text = "Toggle UI visibility" })

	panicGroup:AddLabel("Emergency Key"):AddKeyPicker("streamerPanicKey", { Default = "End", NoUI = true, Text = "Instant clean state" })

	miscGroup:AddToggle("randomizeUpdateRate", { Text = "Jitter Update Rate", Default = false, Tooltip = "Add small random variation to the Update Rate (light anti-pattern; throttled)" })

	local menuVisible = true
	local hiddenByStreamer = false

	local function setMenu(visible)
		menuVisible = visible
		if mainGui then
			pcall(function() mainGui.Enabled = visible end)
		else
			pcall(function() Library:SetVisible(visible) end)
		end
	end

	local function syncStreamerFlags()
		local master = Toggles.streamerMaster.Value
		local S = Bridge.Streamer
		S.hideFOV    = master and Toggles.hideFOVCircle.Value or false
		S.hideESP    = master and Toggles.hidePlayerESP.Value or false
		S.hideChams  = master and Toggles.hideChams.Value or false
		S.hideHitbox = master and Toggles.hideHitboxGlow.Value or false
		if master and Toggles.hideUIOnToggle.Value then
			if menuVisible then setMenu(false); hiddenByStreamer = true end
		elseif hiddenByStreamer and (not master or not Toggles.hideUIOnToggle.Value) then
			setMenu(true)
			hiddenByStreamer = false
		end
	end

	local jitterConn = nil
	local lastJitter = 0
	local originalUpdateRate = nil

	local function startJitter()
		if not Options.updateRate then return end
		originalUpdateRate = originalUpdateRate or Options.updateRate.Value
		if jitterConn then jitterConn:Disconnect() end
		jitterConn = RunService.Heartbeat:Connect(function()
			if not Toggles.randomizeUpdateRate.Value then return end
			local now = tick()
			if now - lastJitter < 0.4 then return end
			lastJitter = now
			local base = originalUpdateRate or 30
			Options.updateRate:SetValue(math.clamp(base + math.random(-5, 5), 1, 60))
		end)
	end
	local function stopJitter()
		if jitterConn then jitterConn:Disconnect(); jitterConn = nil end
		if originalUpdateRate and Options.updateRate then
			Options.updateRate:SetValue(originalUpdateRate)
			originalUpdateRate = nil
		end
	end

	Options.hideUIKey:OnClick(function()
		setMenu(not menuVisible)
		hiddenByStreamer = false
	end)
	Options.streamerPanicKey:OnClick(function()
		if Toggles.MasterToggle then Toggles.MasterToggle:SetValue(false) end
		if Toggles.streamerMaster then Toggles.streamerMaster:SetValue(false) end
		local S = Bridge.Streamer
		S.hideESP, S.hideChams, S.hideFOV, S.hideHitbox = false, false, false, false
		stopJitter()
		setMenu(false)
		hiddenByStreamer = false
	end)

	for _, name in ipairs({ "streamerMaster", "hideFOVCircle", "hidePlayerESP", "hideChams", "hideHitboxGlow", "hideUIOnToggle" }) do
		Toggles[name]:OnChanged(syncStreamerFlags)
	end
	Toggles.randomizeUpdateRate:OnChanged(function()
		if Toggles.randomizeUpdateRate.Value then startJitter() else stopJitter() end
	end)

	Bridge:RegisterAddon("Streamer", {
		onUnload = function()
			stopJitter()
			local S = Bridge.Streamer
			S.hideESP, S.hideChams, S.hideFOV, S.hideHitbox = false, false, false, false
			setMenu(true)
		end,
	})

	syncStreamerFlags()
	print("[Streamer] Built-in module loaded.")
end)

-- ----- Teleport -------------------------------------------------------------
pcall(function()
	local HttpService = game:GetService("HttpService")
	local lPlayer  = Players.LocalPlayer
	local WP_FILE  = "FurryHBE_Waypoints.json"

	local teleportTab   = mainWindow:AddTab("Teleport")
	local waypointGroup = teleportTab:AddLeftGroupbox("Waypoints")
	local teleportGroup = teleportTab:AddLeftGroupbox("Teleport")
	local settingsGroup = teleportTab:AddRightGroupbox("Settings")

	local waypoints = {}

	waypointGroup:AddDropdown("waypointList", { Text = "Saved Waypoints", AllowNull = true, Multi = false, Values = {}, Default = nil, Tooltip = "Select a waypoint to teleport to" })

	settingsGroup:AddToggle("useSitTeleport", { Text = "Sit Before Teleport", Default = true, Tooltip = "Sit on a temporary seat first to mask the teleport as a normal move" })
	settingsGroup:AddToggle("desyncFlash", { Text = "Desync Flash", Default = false, Tooltip = "Briefly flicker position to mask the teleport as network lag (can fling in some games)" })
	settingsGroup:AddSlider("teleportSitTime", { Text = "Sit Settle Time", Min = 0.05, Max = 1, Default = 0.3, Rounding = 2, Tooltip = "How long to stay seated around the teleport" })

	local activeTempSeats = {}

	local function teleportTo(targetPosition)
		local char = lPlayer.Character
		if not char then return end
		local humanoid = char:FindFirstChildWhichIsA("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
		if not humanoid or not root then return end
		local settle = (Options.teleportSitTime and Options.teleportSitTime.Value) or 0.3
		local dest = CFrame.new(targetPosition)
		if Toggles.useSitTeleport.Value then
			local seat = Instance.new("Part")
			seat.Name = "FurryHBE_TempSeat"
			seat.Size = Vector3.new(2, 1, 2)
			seat.Anchored = true
			seat.CanCollide = false
			seat.Transparency = 1
			seat.CFrame = root.CFrame - Vector3.new(0, 3, 0)
			seat.Parent = Workspace
			activeTempSeats[seat] = true
			humanoid.Sit = true
			task.wait(settle)
			if Toggles.desyncFlash.Value then
				root.CFrame = CFrame.new(99999, 99999, 99999)
				task.wait(0.05)
			end
			root.CFrame = dest * CFrame.new(0, 3, 0)
			task.wait(settle)
			humanoid.Sit = false
			activeTempSeats[seat] = nil
			pcall(function() seat:Destroy() end)
			root.CFrame = dest
		else
			if Toggles.desyncFlash.Value then
				root.CFrame = CFrame.new(99999, 99999, 99999)
				task.wait(0.05)
			end
			root.CFrame = dest
		end
	end

	local function rebuildDropdown(selectName)
		local list = Options.waypointList
		local names = {}
		for _, wp in ipairs(waypoints) do table.insert(names, wp.name) end
		list.Values = names
		list:SetValues()
		if selectName and table.find(names, selectName) then
			list:SetValue(selectName)
		elseif #names == 0 then
			pcall(function() list:SetValue(nil) end)
		end
	end

	local function saveWaypoints()
		if not writefile then return end
		local data = {}
		for _, wp in ipairs(waypoints) do
			table.insert(data, { name = wp.name, x = wp.position.X, y = wp.position.Y, z = wp.position.Z })
		end
		pcall(function() writefile(WP_FILE, HttpService:JSONEncode(data)) end)
	end

	local function loadWaypoints()
		if not (isfile and readfile and isfile(WP_FILE)) then return end
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(WP_FILE)) end)
		if ok and type(data) == "table" then
			waypoints = {}
			for _, wp in ipairs(data) do
				if wp.name and wp.x then
					table.insert(waypoints, { name = wp.name, position = Vector3.new(wp.x, wp.y, wp.z) })
				end
			end
			rebuildDropdown()
		end
	end

	waypointGroup:AddButton("Add Waypoint", function()
		local char = lPlayer.Character
		local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
		if not root then Library:Notify("No character to save"); return end
		local name = "Waypoint " .. (#waypoints + 1)
		table.insert(waypoints, { name = name, position = root.Position })
		rebuildDropdown(name)
		saveWaypoints()
		Library:Notify("Waypoint saved: " .. name)
	end):AddToolTip("Save current position as a waypoint")

	waypointGroup:AddButton("Delete Selected", function()
		local sel = Options.waypointList.Value
		if not sel then return end
		for i, wp in ipairs(waypoints) do
			if wp.name == sel then table.remove(waypoints, i); break end
		end
		rebuildDropdown(waypoints[#waypoints] and waypoints[#waypoints].name or nil)
		saveWaypoints()
		Library:Notify("Waypoint deleted: " .. sel)
	end):AddToolTip("Remove the selected waypoint")

	teleportGroup:AddButton("Teleport to Selected", function()
		local sel = Options.waypointList.Value
		if not sel then Library:Notify("No waypoint selected"); return end
		local targetPos
		for _, wp in ipairs(waypoints) do
			if wp.name == sel then targetPos = wp.position; break end
		end
		if not targetPos then return end
		task.spawn(function()
			local ok, err = pcall(teleportTo, targetPos)
			if not ok then Library:Notify("Teleport failed: " .. tostring(err)) end
		end)
	end):AddToolTip("Teleport to the selected waypoint using the anti-detection method")

	-- ===== Teleport to player =====
	teleportGroup:AddDropdown("tpPlayerList", { Text = "Target Player", Values = {}, Multi = false, AllowNull = true, Tooltip = "Player to teleport to" })
	local function refreshTpPlayers()
		local names = {}
		for _, p in ipairs(Players:GetPlayers()) do if p ~= lPlayer then table.insert(names, p.Name) end end
		Options.tpPlayerList.Values = names
		Options.tpPlayerList:SetValues()
	end
	local function getTargetPlayer()
		local n = Options.tpPlayerList.Value
		return n and Players:FindFirstChild(n) or nil
	end
	teleportGroup:AddButton("Refresh Players", function()
		refreshTpPlayers(); Library:Notify("Player list refreshed")
	end):AddToolTip("Re-list players for the dropdown")
	teleportGroup:AddButton("Teleport to Player", function()
		local p = getTargetPlayer()
		local char = p and p.Character
		local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
		if not root then Library:Notify("Target has no character"); return end
		task.spawn(function()
			local ok, err = pcall(teleportTo, root.Position + Vector3.new(0, 0, 3))
			if not ok then Library:Notify("Teleport failed: " .. tostring(err)) end
		end)
	end):AddToolTip("Teleport right next to the selected player")
	teleportGroup:AddButton("Teleport to Nearest Seat", function()
		local p = getTargetPlayer()
		local char = p and p.Character
		local troot = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
		if not troot then Library:Notify("Target has no character"); return end
		-- nearest EMPTY seat within 60 studs of the target (e.g. a free seat in their car)
		local best, bestD = nil, math.huge
		for _, s in ipairs(Workspace:GetDescendants()) do
			if (s:IsA("VehicleSeat") or s:IsA("Seat")) and s.Occupant == nil then
				local d = (s.Position - troot.Position).Magnitude
				if d < bestD and d < 60 then bestD = d; best = s end
			end
		end
		if not best then Library:Notify("No empty seat near that player"); return end
		task.spawn(function()
			pcall(function()
				local c = lPlayer.Character
				local hum = c and c:FindFirstChildWhichIsA("Humanoid")
				local root = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
				if root then root.CFrame = best.CFrame + Vector3.new(0, 2, 0) end
				task.wait(0.12)
				if hum and best.Occupant == nil then best:Sit(hum) end
			end)
		end)
	end):AddToolTip("Teleport into the nearest empty seat next to the selected player (e.g. a seat in their car/heli)")
	refreshTpPlayers()
	Players.PlayerAdded:Connect(refreshTpPlayers)
	Players.PlayerRemoving:Connect(function() task.wait(0.2); pcall(refreshTpPlayers) end)

	Bridge:RegisterAddon("Teleport", {
		onUnload = function()
			for seat in pairs(activeTempSeats) do pcall(function() seat:Destroy() end) end
			activeTempSeats = {}
		end,
	})

	pcall(loadWaypoints)
	print("[Teleport] Built-in module loaded.")
end)

-- ----- Miscellaneous tab : Vehicle + Combat (Tool Expander) -----------------
-- Formerly Miscellaneousforgot.lua. Fixes from the original: forward-reference
-- bugs (applyVehicleSpeed / refreshVehicleDetection / applyToolExpansion were
-- called by buttons before being declared), the non-existent infoGroup:SetLabel
-- (now a stored label:SetText), label:AddDropdown (labels can't host dropdowns),
-- seat detection (now uses Humanoid.SeatPart), BodyGyro parented to a Model
-- instead of a BasePart, and a multi-return bug in the upright math. Cleanup is
-- registered through the Bridge and all connections are tracked + disconnected.
pcall(function()
	local miscTab = mainWindow:AddTab("Miscellaneous")
	Bridge.MiscTab = miscTab  -- still exposed so future add-ons can attach here too
	local lPlayer = Players.LocalPlayer

	local conns = {}
	local function track(c) table.insert(conns, c); return c end

	-- 4 left + 4 right groupboxes, all under the single Miscellaneous tab.
	local speedGroup     = miscTab:AddLeftGroupbox("Vehicle: Speed")
	local detectGroup    = miscTab:AddLeftGroupbox("Vehicle: Detection")
	local stabilGroup    = miscTab:AddLeftGroupbox("Vehicle: Limiter")
	local expanderGroup  = miscTab:AddLeftGroupbox("Combat: Tool Expander")
	local infoGroup      = miscTab:AddRightGroupbox("Vehicle: Info")
	local weaponListGroup= miscTab:AddRightGroupbox("Combat: Weapon List")
	local scannerGroup   = miscTab:AddRightGroupbox("Combat: Tool Scanner")
	local settingsGroupC = miscTab:AddRightGroupbox("Combat: Settings")

	-- Forward declarations: buttons below are created before these are defined.
	local refreshVehicleDetection, applyToolExpansion

	-- Manual vehicle pick (fallback if auto seat-detection fails).
	local manualVehicle = nil

	-- ===== Vehicle UI =====
	speedGroup:AddToggle("vehicleAssist", { Text = "Vehicle Assist", Default = false, Tooltip = "Master toggle. Auto-stabilizes the vehicle (firmer at higher speed) and enables the speed jolt + limiter. (Default: OFF)" })
	speedGroup:AddLabel("Speed Jolt Key"):AddKeyPicker("vehicleJoltKey", { Default = "G", NoUI = true, Text = "Speed Jolt" })
	speedGroup:AddSlider("vehicleJoltPower", { Text = "Jolt Power", Min = 10, Max = 500, Default = 120, Rounding = 1, Tooltip = "Burst of speed added each key press, in studs/sec. (Default: 120)" })

	detectGroup:AddDropdown("vehicleDetectionMode", { Text = "Detection Mode", Values = { "Auto", "A-Chassis", "Basic Seat", "Custom Script" }, Default = "Auto", Multi = false, AllowNull = false, Tooltip = "Hint for how to detect the vehicle (Auto works for most)" })
	detectGroup:AddButton("Refresh Detection", function()
		if refreshVehicleDetection then pcall(refreshVehicleDetection) end
	end):AddToolTip("Rescan your character for the seat/vehicle you're in")
	detectGroup:AddToggle("vehicleManualMode", { Text = "Manual Vehicle", Default = false, Tooltip = "Ignore auto seat-detection and use the vehicle you pick below (use this if auto fails)" })
	detectGroup:AddButton("Pick Vehicle (hold-click)", function()
		Bridge:StartHoldPick({
			color = Color3.fromRGB(0, 170, 255),
			onPick = function(part)
				manualVehicle = part
				if not Toggles.vehicleManualMode.Value then Toggles.vehicleManualMode:SetValue(true) end
				if refreshVehicleDetection then pcall(refreshVehicleDetection) end
				local model = part:FindFirstAncestorWhichIsA("Model")
				Library:Notify("Manual vehicle: " .. (model and model.Name or part.Name))
			end,
		})
	end):AddToolTip("Aim at a vehicle and HOLD left-click until the ring fills to select it (right-click cancels)")
	detectGroup:AddButton("Clear Manual Vehicle", function()
		manualVehicle = nil
		if refreshVehicleDetection then pcall(refreshVehicleDetection) end
		Library:Notify("Manual vehicle cleared")
	end):AddToolTip("Forget the manually picked vehicle")

	stabilGroup:AddToggle("vehicleSpeedLimiter", { Text = "Speed Limiter", Default = false, Tooltip = "ON = caps your speed at the limit below even if you keep jolting. OFF = jolts uncapped (hit the jets). (Default: OFF)" })
	stabilGroup:AddSlider("vehicleSpeedCap", { Text = "Speed Limit (studs/s)", Min = 20, Max = 500, Default = 120, Rounding = 1, Tooltip = "Max horizontal speed while the limiter is on. (Default: 120)" })

	local vehicleInfoLabel = infoGroup:AddLabel("Current Vehicle: None")

	-- ===== Combat UI =====
	weaponListGroup:AddDropdown("expandedWeapons", { Text = "Active Weapons", Values = {}, Multi = true, AllowNull = true, Default = {}, Tooltip = "Tools whose hitbox will be expanded" })

	expanderGroup:AddToggle("toolExpanderEnabled", { Text = "Enable Tool Expander", Default = false, Tooltip = "Master toggle for tool hitbox expansion" })
	expanderGroup:AddSlider("toolExpandSize", { Text = "Expansion Size", Min = 0.5, Max = 10, Default = 2, Rounding = 1, Tooltip = "Multiplier applied to tool part sizes" })
	expanderGroup:AddDropdown("toolPartFilter", { Text = "Parts to Expand", Values = { "Handle", "Blade", "HitBox", "Tip", "All" }, Default = { "Handle", "Blade" }, Multi = true, AllowNull = true, Tooltip = "Which tool parts get expanded (name match)" })

	scannerGroup:AddButton("Scan Tools", function()
		local tools = {}
		local function scan(container)
			if not container then return end
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t.Name ~= "" and not table.find(tools, t.Name) then table.insert(tools, t.Name) end
			end
		end
		scan(lPlayer:FindFirstChild("Backpack"))
		scan(lPlayer.Character)
		Options.expandedWeapons.Values = tools
		Options.expandedWeapons:SetValues()
		Library:Notify("Found " .. #tools .. " tool(s)")
	end):AddToolTip("Scan your backpack and character for tools")

	settingsGroupC:AddToggle("toolAutoApply", { Text = "Auto-Apply on Equip", Default = true, Tooltip = "Expand a tool automatically when equipped if it's in the active list" })
	settingsGroupC:AddButton("Apply Now", function()
		if applyToolExpansion then pcall(applyToolExpansion) end
	end):AddToolTip("Force-apply expansion to the currently equipped tool(s)")

	-- ===== Vehicle logic (combined assist: jolt + limiter + auto-stabilizer) =====
	local currentVehicle, vehicleType
	local assistConn = nil

	local function detectVehicle()
		-- Manual override: if Manual Vehicle is on, use the part you picked so assist
		-- still works when auto seat-detection fails.
		if Toggles.vehicleManualMode and Toggles.vehicleManualMode.Value then
			if manualVehicle and manualVehicle.Parent then return manualVehicle end
			return nil
		end
		local char = lPlayer.Character
		if not char then return nil end
		local hum = char:FindFirstChildWhichIsA("Humanoid")
		if hum and hum.SeatPart then return hum.SeatPart end
		return nil
	end

	local function identifyVehicleType(vehicle)
		local root = vehicle:FindFirstAncestorWhichIsA("Model")
		if root and (root:FindFirstChild("A-Chassis") or root:FindFirstChild("Chassis")) then return "A-Chassis" end
		if vehicle:IsA("VehicleSeat") then return "Basic Seat" end
		return "Custom Script"
	end

	local function vehicleRootAndPrimary()
		if not currentVehicle or not currentVehicle.Parent then return nil, nil end
		local root = currentVehicle:FindFirstAncestorWhichIsA("Model") or currentVehicle
		local primary = root.PrimaryPart or (currentVehicle:IsA("BasePart") and currentVehicle) or root:FindFirstChildWhichIsA("BasePart")
		return root, primary
	end

	-- Track the part we last attached a gyro to so we can clean it up the moment we
	-- leave/switch vehicles (audit fix: an empty car was being left stabilized).
	local activePrimary = nil
	local function clearGyro()
		if activePrimary then
			pcall(function()
				local g = activePrimary:FindFirstChild("FurryHBE_StabGyro")
				if g then g:Destroy() end
			end)
			activePrimary = nil
		end
	end
	local function removeVehiclePhysics() clearGyro() end

	-- Always re-validate which vehicle we're actually in; if it changed or we got
	-- out, drop the old gyro first.
	local function ensureVehicle()
		currentVehicle = detectVehicle()
		local root, primary = vehicleRootAndPrimary()
		if primary ~= activePrimary then clearGyro(); activePrimary = primary end
		return root, primary
	end

	-- One Heartbeat: auto-stabilize (torque scales with speed) + enforce the limiter.
	local function assistStep()
		if not Toggles.vehicleAssist.Value then clearGyro(); return end
		local _, primary = ensureVehicle()
		if not primary then return end
		local vel = primary.AssemblyLinearVelocity
		local speed = vel.Magnitude

		-- Auto-stabilizer: keep upright, torque/responsiveness scaled to speed so it
		-- self-adjusts no matter how fast you go. Roll+pitch only (yaw stays free) so
		-- steering isn't fought.
		local gyro = primary:FindFirstChild("FurryHBE_StabGyro")
		if not gyro then
			gyro = Instance.new("BodyGyro")
			gyro.Name = "FurryHBE_StabGyro"
			gyro.D = 500
			gyro.Parent = primary
		end
		gyro.P = math.clamp(speed * 200, 2000, 30000)
		local strength = math.clamp(800 + speed * 40, 800, 60000)
		gyro.MaxTorque = Vector3.new(strength, 0, strength)
		local _, yaw = primary.CFrame:ToEulerAnglesYXZ()
		gyro.CFrame = CFrame.new(primary.Position) * CFrame.Angles(0, yaw, 0)

		-- Speed limiter: clamp horizontal speed to the cap when enabled.
		if Toggles.vehicleSpeedLimiter.Value then
			local cap = Options.vehicleSpeedCap.Value
			local horiz = Vector3.new(vel.X, 0, vel.Z)
			if horiz.Magnitude > cap then
				local capped = horiz.Unit * cap
				primary.AssemblyLinearVelocity = Vector3.new(capped.X, vel.Y, capped.Z)
			end
		end
	end

	-- Speed jolt: an impulse via AssemblyLinearVelocity (no persistent BodyVelocity),
	-- so wheel physics on advanced chassis aren't fought/broken (the old tire bug).
	-- The limiter clamps it next frame; with the limiter off it's a full "jet".
	local function speedJolt()
		if not Toggles.vehicleAssist.Value then return end
		local _, primary = ensureVehicle()
		if not primary then return end
		local newVel = primary.AssemblyLinearVelocity + primary.CFrame.LookVector * Options.vehicleJoltPower.Value
		-- Anti-fling: a single jolt can never produce an absurd velocity.
		if newVel.Magnitude > 2000 then newVel = newVel.Unit * 2000 end
		primary.AssemblyLinearVelocity = newVel
	end

	refreshVehicleDetection = function()
		currentVehicle = detectVehicle()
		vehicleInfoLabel:SetText("Current Vehicle: " .. (currentVehicle and identifyVehicleType(currentVehicle) or "None"))
	end

	Options.vehicleJoltKey:OnClick(function() pcall(speedJolt) end)

	Toggles.vehicleAssist:OnChanged(function()
		if Toggles.vehicleAssist.Value then
			refreshVehicleDetection()
			if not assistConn then assistConn = RunService.Heartbeat:Connect(function() pcall(assistStep) end) end
		else
			if assistConn then assistConn:Disconnect(); assistConn = nil end
			removeVehiclePhysics()
		end
	end)

	-- ===== Tool expander logic =====
	local originalToolSizes = setmetatable({}, { __mode = "k" })

	local function shouldExpandPart(part)
		local filter = Options.toolPartFilter:GetActiveValues()
		if table.find(filter, "All") then return true end
		for _, pat in ipairs(filter) do
			if string.find(part.Name:lower(), pat:lower()) then return true end
		end
		return false
	end

	local function expandTool(tool, expand)
		if expand then
			if not table.find(Options.expandedWeapons:GetActiveValues(), tool.Name) then return end
			local scale = Options.toolExpandSize.Value
			for _, part in ipairs(tool:GetDescendants()) do
				if part:IsA("BasePart") and shouldExpandPart(part) then
					originalToolSizes[tool] = originalToolSizes[tool] or {}
					if not originalToolSizes[tool][part] then originalToolSizes[tool][part] = part.Size end
					part.Size = originalToolSizes[tool][part] * scale
				end
			end
		else
			local saved = originalToolSizes[tool]
			if saved then
				for part, origSize in pairs(saved) do
					if part and part.Parent then part.Size = origSize end
				end
				originalToolSizes[tool] = nil
			end
		end
	end

	applyToolExpansion = function()
		if not Toggles.toolExpanderEnabled.Value then return end
		local char = lPlayer.Character
		if not char then return end
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then expandTool(tool, true) end
		end
	end

	local function hookTool(tool)
		track(tool.Equipped:Connect(function()
			if Toggles.toolExpanderEnabled.Value and Toggles.toolAutoApply.Value then expandTool(tool, true) end
		end))
		track(tool.Unequipped:Connect(function() expandTool(tool, false) end))
	end
	local function scanContainer(container)
		if not container then return end
		for _, t in ipairs(container:GetChildren()) do if t:IsA("Tool") then hookTool(t) end end
		track(container.ChildAdded:Connect(function(c) if c:IsA("Tool") then hookTool(c) end end))
	end
	scanContainer(lPlayer.Character)
	scanContainer(lPlayer:FindFirstChild("Backpack"))
	track(lPlayer.CharacterAdded:Connect(function(char)
		scanContainer(char)
		scanContainer(lPlayer:FindFirstChild("Backpack"))
	end))

	Toggles.toolExpanderEnabled:OnChanged(function()
		if Toggles.toolExpanderEnabled.Value then
			applyToolExpansion()
		else
			for tool, saved in pairs(originalToolSizes) do
				for part, origSize in pairs(saved) do
					if part and part.Parent then part.Size = origSize end
				end
				originalToolSizes[tool] = nil
			end
		end
	end)

	-- ===== Cleanup (Bridge teardown) =====
	Bridge:RegisterAddon("Misc", {
		onUnload = function()
			for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
			if assistConn then pcall(function() assistConn:Disconnect() end) end
			pcall(removeVehiclePhysics)
			for tool, saved in pairs(originalToolSizes) do
				for part, origSize in pairs(saved) do
					if part and part.Parent then pcall(function() part.Size = origSize end) end
				end
			end
		end,
	})

	print("[Misc] Vehicle + Combat module loaded.")
end)

-- ----- Manual Vehicle HBE (Main tab) ----------------------------------------
-- A standalone hitbox extender for a vehicle/part you pick by aiming at it and
-- clicking -- separate from the player extender, the world-part scanner and the
-- Misc speed module. It re-applies an additive size each frame (storing the real
-- size once, so it never corrupts the original and restores cleanly).
pcall(function()
	local lPlayer = Players.LocalPlayer
	local mvGroup = (Bridge.MiscTab or mainTab):AddRightGroupbox("Manual Vehicle HBE")
	mvGroup:AddToggle("mvHbeEnabled", { Text = "Enable Manual Vehicle HBE", Default = false, Tooltip = "Extend the hitbox of a vehicle/part you pick manually (independent of every other extender)" })
	mvGroup:AddSlider("mvHbeSize", { Text = "Added Size (studs)", Min = 1, Max = 250, Default = 20, Rounding = 1, Tooltip = "Studs added to the picked part's size" })
	mvGroup:AddSlider("mvHbeTransparency", { Text = "Transparency", Min = 0, Max = 1, Default = 0.6, Rounding = 2 })
	mvGroup:AddToggle("mvHbeCollisions", { Text = "Keep Collisions", Default = false, Tooltip = "Leave the extended part collidable" })
	mvGroup:AddToggle("mvHbeWholeModel", { Text = "Whole Model", Default = false, Tooltip = "Extend every BasePart of the picked vehicle's model, not just the one part" })
	local mvInfo = mvGroup:AddLabel("Picked: none")

	local pickedPart = nil
	local extended = {}     -- [BasePart] = { Size, Transparency, CanCollide }

	local function restore()
		for part, orig in pairs(extended) do
			if typeof(part) == "Instance" and part.Parent then
				pcall(function() part.Size = orig.Size; part.Transparency = orig.Transparency; part.CanCollide = orig.CanCollide end)
			end
			extended[part] = nil
		end
	end

	local function targetParts()
		if not pickedPart or not pickedPart.Parent then return {} end
		if Toggles.mvHbeWholeModel.Value then
			local model = pickedPart:FindFirstAncestorWhichIsA("Model") or pickedPart
			local t = {}
			for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then t[#t + 1] = d end end
			if #t == 0 and pickedPart:IsA("BasePart") then t[1] = pickedPart end
			return t
		end
		return pickedPart:IsA("BasePart") and { pickedPart } or {}
	end

	local function apply()
		local add = Options.mvHbeSize.Value
		local transp = Options.mvHbeTransparency.Value
		local keepCol = Toggles.mvHbeCollisions.Value
		local desired = {}
		for _, part in ipairs(targetParts()) do desired[part] = true end
		for part, orig in pairs(extended) do
			if not desired[part] then
				if typeof(part) == "Instance" and part.Parent then
					pcall(function() part.Size = orig.Size; part.Transparency = orig.Transparency; part.CanCollide = orig.CanCollide end)
				end
				extended[part] = nil
			end
		end
		for part in pairs(desired) do
			local e = extended[part]
			if not e then
				e = { Size = part.Size, Transparency = part.Transparency, CanCollide = part.CanCollide }
				extended[part] = e
			end
			pcall(function()
				part.Size = e.Size + Vector3.new(add, add, add)
				part.Transparency = transp
				part.CanCollide = keepCol and true or e.CanCollide
			end)
		end
	end

	mvGroup:AddButton("Pick Vehicle (hold-click)", function()
		Bridge:StartHoldPick({
			color = Color3.fromRGB(255, 170, 0),
			onPick = function(part)
				restore()                   -- drop the previous pick cleanly first
				pickedPart = part
				local model = part:FindFirstAncestorWhichIsA("Model")
				mvInfo:SetText("Picked: " .. (model and model.Name or part.Name))
				Library:Notify("Picked vehicle: " .. (model and model.Name or part.Name))
			end,
		})
	end):AddToolTip("Aim at a vehicle and HOLD left-click until the ring fills to select it (right-click cancels)")

	mvGroup:AddButton("Clear Pick", function()
		restore()
		pickedPart = nil
		mvInfo:SetText("Picked: none")
	end):AddToolTip("Restore and forget the picked vehicle")

	Toggles.mvHbeEnabled:OnChanged(function()
		if not Toggles.mvHbeEnabled.Value then restore() end
	end)

	local hbConn = RunService.Heartbeat:Connect(function()
		if pickedPart and not pickedPart.Parent then
			restore(); pickedPart = nil; mvInfo:SetText("Picked: none")
			return
		end
		if Toggles.mvHbeEnabled.Value and pickedPart then pcall(apply) end
	end)

	Bridge:RegisterAddon("ManualVehicleHBE", {
		onUnload = function()
			if hbConn then pcall(function() hbConn:Disconnect() end) end
			pcall(restore)
		end,
	})
	print("[ManualVehicleHBE] Loaded on Miscellaneous tab.")
end)

-- ----- Vehicle ESP (Miscellaneous tab) --------------------------------------
pcall(function()
	local miscTab = Bridge.MiscTab
	if not miscTab then return end
	local lPlayer = Players.LocalPlayer
	local HttpService = game:GetService("HttpService")
	local VE_FILE = "FurryHBE_VehicleTypes.json"
	local TYPE_COLOR = {
		Car = Color3.fromRGB(255, 255, 255), Helicopter = Color3.fromRGB(0, 255, 255),
		Boat = Color3.fromRGB(80, 160, 255), Plane = Color3.fromRGB(255, 230, 60),
	}

	local g = miscTab:AddLeftGroupbox("Vehicle ESP")
	g:AddToggle("vehicleEspEnabled", { Text = "Enable Vehicle ESP", Default = false, Tooltip = "Draw name + type + distance on registered vehicles. (Default: OFF)" })
	g:AddDropdown("vehicleEspList", { Text = "Registered Vehicles", Values = {}, Multi = false, AllowNull = true, Tooltip = "Vehicles currently tracked" })
	g:AddDropdown("vehicleEspType", { Text = "Mark As", Values = { "Car", "Helicopter", "Boat", "Plane" }, Default = "Car", Multi = false, AllowNull = false, Tooltip = "Type to tag the selected vehicle with (saved to disk)" })

	local registered = {}     -- { { model=, name=, type= }, ... }
	local vehicleTypes = {}   -- [name] = type (persisted)
	pcall(function()
		if isfile and readfile and isfile(VE_FILE) then
			local ok, t = pcall(function() return HttpService:JSONDecode(readfile(VE_FILE)) end)
			if ok and type(t) == "table" then vehicleTypes = t end
		end
	end)
	local function saveTypes() if writefile then pcall(function() writefile(VE_FILE, HttpService:JSONEncode(vehicleTypes)) end) end end
	local function refreshList()
		local names = {}
		for _, e in ipairs(registered) do table.insert(names, e.name) end
		Options.vehicleEspList.Values = names
		Options.vehicleEspList:SetValues()
	end
	local function isRegistered(m) for _, e in ipairs(registered) do if e.model == m then return true end end return false end
	local function registerModel(m)
		if not m or not m:IsA("Model") or isRegistered(m) then return end
		table.insert(registered, { model = m, name = m.Name, type = vehicleTypes[m.Name] or "Car" })
		refreshList()
	end

	g:AddButton("Scan Vehicles", function()
		local count = 0
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("VehicleSeat") then
				local m = d:FindFirstAncestorWhichIsA("Model")
				if m and not isRegistered(m) then registerModel(m); count = count + 1 end
			end
		end
		Library:Notify("Vehicle ESP: registered " .. count .. " vehicle(s)")
	end):AddToolTip("Find models that contain a VehicleSeat and register them")
	g:AddButton("Register (hold-pick)", function()
		Bridge:StartHoldPick({ color = Color3.fromRGB(0, 255, 170), onPick = function(part)
			local m = part:FindFirstAncestorWhichIsA("Model") or part
			registerModel(m); Library:Notify("Registered vehicle: " .. m.Name)
		end })
	end):AddToolTip("Aim at a vehicle and hold-click to register it")
	g:AddButton("Set Type to Selected", function()
		local sel = Options.vehicleEspList.Value
		if not sel then return end
		for _, e in ipairs(registered) do
			if e.name == sel then e.type = Options.vehicleEspType.Value; vehicleTypes[e.name] = e.type end
		end
		saveTypes(); Library:Notify(sel .. " -> " .. Options.vehicleEspType.Value)
	end):AddToolTip("Tag the selected vehicle as Car/Helicopter/Boat/Plane (saved)")
	g:AddButton("Remove Selected", function()
		local sel = Options.vehicleEspList.Value
		for i = #registered, 1, -1 do if registered[i].name == sel then table.remove(registered, i) end end
		refreshList()
	end)
	g:AddButton("Clear All", function() registered = {}; refreshList() end)

	local pool = {}
	local function getText(i)
		if not pool[i] then
			local t = DrawingFallback.new("Text")
			t.Center = true; t.Outline = true; t.Size = 14
			pool[i] = t
		end
		return pool[i]
	end
	local function hideFrom(i) for j = i, #pool do pool[j].Visible = false end end

	RunService:BindToRenderStep("FurryHBE_VehicleESP", Enum.RenderPriority.Camera.Value, function()
		if not Toggles.vehicleEspEnabled.Value then hideFrom(1); return end
		local cam = Workspace.CurrentCamera
		local lchar = lPlayer.Character
		local lroot = lchar and (lchar:FindFirstChild("HumanoidRootPart") or lchar:FindFirstChild("Head"))
		local idx = 0
		for _, e in ipairs(registered) do
			local m = e.model
			if typeof(m) == "Instance" and m.Parent then
				local okp, cf = pcall(function() return m:GetPivot() end)
				if okp and cf then
					local sp, on = cam:WorldToViewportPoint(cf.Position)
					if on then
						idx = idx + 1
						local t = getText(idx)
						local dist = lroot and math.floor((cf.Position - lroot.Position).Magnitude) or 0
						local driver = ""
						pcall(function()
							local seat = m:FindFirstChildWhichIsA("VehicleSeat", true)
							if seat and seat.Occupant then
								local p = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
								driver = p and (" <" .. p.Name .. ">") or " <occupied>"
							end
						end)
						t.Text = e.name .. " [" .. e.type .. "] " .. dist .. "m" .. driver
						t.Position = Vector2.new(sp.X, sp.Y)
						t.Color = TYPE_COLOR[e.type] or Color3.fromRGB(255, 255, 255)
						t.Visible = true
					end
				end
			end
		end
		hideFrom(idx + 1)
	end)

	Bridge:RegisterAddon("VehicleESP", { onUnload = function()
		pcall(function() RunService:UnbindFromRenderStep("FurryHBE_VehicleESP") end)
		for _, t in ipairs(pool) do pcall(function() t:Remove() end) end
	end })
	print("[VehicleESP] Loaded.")
end)

-- ----- Inf Ammo + Gun Picker (Miscellaneous tab) ----------------------------
pcall(function()
	local miscTab = Bridge.MiscTab
	if not miscTab then return end
	local lPlayer = Players.LocalPlayer
	local AMMO_PAT = { "ammo", "bullet", "mag", "clip", "round", "reserve", "shell" }

	local g = miscTab:AddRightGroupbox("Inf Ammo / Guns")
	g:AddToggle("infAmmoEnabled", { Text = "Enable Inf Ammo", Default = false, Tooltip = "Continuously refills numeric ammo values on your equipped gun(s).\nClient-side heuristic; some games keep ammo server-side. (Default: OFF)" })
	g:AddToggle("infAmmoAllTools", { Text = "Apply to Any Tool", Default = false, Tooltip = "Apply to every equipped tool, not just registered guns. (Default: OFF)" })
	g:AddSlider("infAmmoAmount", { Text = "Refill Amount", Min = 1, Max = 9999, Default = 999, Rounding = 0, Tooltip = "Value ammo fields are refilled to each tick. (Default: 999)" })
	g:AddDropdown("infAmmoGuns", { Text = "Registered Guns", Values = {}, Multi = true, AllowNull = true, Tooltip = "Guns this applies to (unless 'Apply to Any Tool')" })

	local function addGun(name)
		if not name or name == "" then return end
		local list = Options.infAmmoGuns
		if not table.find(list.Values, name) then table.insert(list.Values, name); list:SetValues() end
		local v = list.Value
		if type(v) == "table" then v[name] = true; pcall(function() list:SetValue(v) end) end
		Library:Notify("Registered gun: " .. name)
	end
	g:AddButton("Register Gun in Hand", function()
		local char = lPlayer.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		if tool then addGun(tool.Name) else Library:Notify("No tool equipped") end
	end):AddToolTip("Register the tool you're currently holding")
	g:AddButton("Register Gun (hold-pick)", function()
		Bridge:StartHoldPick({ color = Color3.fromRGB(255, 120, 0), onPick = function(part)
			local tool = part:FindFirstAncestorWhichIsA("Tool")
			if tool then addGun(tool.Name) else Library:Notify("That isn't part of a Tool") end
		end })
	end):AddToolTip("Aim at a gun/tool and hold-click to register it")
	g:AddButton("Clear Guns", function()
		Options.infAmmoGuns.Values = {}; Options.infAmmoGuns:SetValues(); pcall(function() Options.infAmmoGuns:SetValue({}) end)
	end)

	local function isAmmoName(n)
		n = n:lower()
		for _, p in ipairs(AMMO_PAT) do if n:find(p) then return true end end
		return false
	end
	local detLabel = g:AddLabel("Detection: idle", true)

	-- ===== Adaptive ammo resolver =====================================
	-- Like the attach flow: try each detection STRATEGY in order and fall through
	-- until one actually finds ammo; cache the winner per gun. If every static
	-- strategy fails, a LEARNING detector watches the gun's numbers and adopts any
	-- value that drops when you fire. So even oddly-built guns get covered.
	local fieldCache = setmetatable({}, { __mode = "k" })  -- [tool] = { fields=, how= }
	local snapshots  = setmetatable({}, { __mode = "k" })  -- [tool] = { [valueObj] = lastValue }

	local function fieldFromValue(v)
		return { read = function() return v.Value end, write = function(n) pcall(function() v.Value = n end) end }
	end
	local function fieldFromAttr(inst, name)
		return { read = function() return inst:GetAttribute(name) or 0 end, write = function(n) pcall(function() inst:SetAttribute(name, n) end) end }
	end

	local function stratValueNames(tool)
		local out = {}
		for _, d in ipairs(tool:GetDescendants()) do
			if (d:IsA("IntValue") or d:IsA("NumberValue")) and isAmmoName(d.Name) then out[#out + 1] = fieldFromValue(d) end
		end
		return out
	end
	local function stratAttributes(tool)
		local out = {}
		local function scan(inst) for an, av in pairs(inst:GetAttributes()) do if type(av) == "number" and isAmmoName(an) then out[#out + 1] = fieldFromAttr(inst, an) end end end
		pcall(scan, tool)
		for _, d in ipairs(tool:GetDescendants()) do pcall(scan, d) end
		return out
	end
	local function stratConfiguration(tool)
		local out = {}
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("Configuration") or (typeof(d.Name) == "string" and d.Name:lower():find("config")) then
				for _, c in ipairs(d:GetChildren()) do
					if c:IsA("IntValue") or c:IsA("NumberValue") then out[#out + 1] = fieldFromValue(c) end
				end
			end
		end
		return out
	end
	local function stratPlayerSide(_)
		local out = {}
		for _, d in ipairs(lPlayer:GetDescendants()) do
			if (d:IsA("IntValue") or d:IsA("NumberValue")) and isAmmoName(d.Name) then out[#out + 1] = fieldFromValue(d) end
		end
		return out
	end
	local STRATS = {
		{ name = "ValueNames", fn = stratValueNames },
		{ name = "Attributes", fn = stratAttributes },
		{ name = "Configuration", fn = stratConfiguration },
		{ name = "PlayerSide", fn = stratPlayerSide },
	}

	local function stratLearning(tool)
		local snap = snapshots[tool]
		if not snap then
			snap = {}
			for _, d in ipairs(tool:GetDescendants()) do
				if d:IsA("IntValue") or d:IsA("NumberValue") then snap[d] = d.Value end
			end
			snapshots[tool] = snap
			return {}
		end
		local out = {}
		for v, last in pairs(snap) do
			if typeof(v) == "Instance" and v.Parent then
				if v.Value < last then out[#out + 1] = fieldFromValue(v) end  -- decreased = ammo
				snap[v] = v.Value
			else
				snap[v] = nil
			end
		end
		return out
	end

	local function resolveFields(tool)
		local cached = fieldCache[tool]
		if cached and #cached.fields > 0 then return cached end
		for _, s in ipairs(STRATS) do
			local fields = s.fn(tool)
			if #fields > 0 then fieldCache[tool] = { fields = fields, how = s.name }; return fieldCache[tool] end
		end
		local learned = stratLearning(tool)
		if #learned > 0 then fieldCache[tool] = { fields = learned, how = "Learned" }; return fieldCache[tool] end
		return nil
	end

	local lastHow = nil
	local function refillTool(tool)
		local res = resolveFields(tool)
		if not res then return end
		local amt = Options.infAmmoAmount.Value
		for _, f in ipairs(res.fields) do
			local cur = f.read()
			if type(cur) == "number" and cur < amt then f.write(amt) end
		end
		if res.how ~= lastHow then
			lastHow = res.how
			pcall(function() detLabel:SetText("Detection: " .. res.how) end)
		end
	end

	local lastRefill = 0
	local ammoConn = RunService.Heartbeat:Connect(function()
		if not Toggles.infAmmoEnabled.Value then return end
		local now = tick()
		if now - lastRefill < 0.15 then return end  -- light throttle
		lastRefill = now
		local char = lPlayer.Character
		if not char then return end
		local active = Options.infAmmoGuns:GetActiveValues()
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") and (Toggles.infAmmoAllTools.Value or table.find(active, tool.Name)) then
				pcall(refillTool, tool)
			end
		end
	end)
	Bridge:RegisterAddon("InfAmmo", { onUnload = function()
		if ammoConn then pcall(function() ammoConn:Disconnect() end) end
	end })
	print("[InfAmmo] Loaded.")
end)

-- ----- Version / Changelog tab + live status light --------------------------
pcall(function()
	local clTab       = mainWindow:AddTab("Version/CL")
	local statusGroup = clTab:AddLeftGroupbox("Status")
	local clGroup     = clTab:AddRightGroupbox("Changelog")

	-- Changelog entries, OLDEST first. Version auto-computes: V1, then +0.5 each
	-- entry (V1, V1.5, V2, ...). To add a release, append a 3-sentence string.
	local CHANGELOG = {
		"Initial Hitbox Extender release. Core extension, ESP, filters and the LinoriaLib UI are all in place. The Master Toggle drives the entire script.",
		"Added the add-on Bridge and the standalone Precision HBE module. Precision locks onto one target and scales its hitbox by distance. It claims its target so the main extender never fights it.",
		"Added Streamer Mode and Teleport, plus ESP name de-overlap and box/name size sliders. Streamer hides every visual while keeping function. Teleport saves waypoints with an anti-detection sit routine.",
		"Fixed the 'stays extended when off' bug and added Disable-While-Seated. Deferred Changed events no longer corrupt the stored defaults. Seated mode can disable hitboxes globally or only within a radius.",
		"Integrated every module into this single file, renamed the UI and added this Version/Changelog tab. Everything now ships in one script. A live status light reports core health at a glance.",
		"Added the Vehicle + Combat (Tool Expander) module into the Miscellaneous tab. Vehicle speed and stabilizer detect your seat and apply physics; the Tool Expander scales equipped tool hitboxes. The original file's forward-reference, SetLabel and seat-detection bugs were all fixed.",
		"Added manual vehicle picking. The Miscellaneous tab can now select a vehicle by aiming and clicking when auto-detection fails, so Speed/Stabilizer still work. The Main tab also gained a separate Manual Vehicle HBE that extends the hitbox of any vehicle you pick.",
		"Priority players now rainbow-flash across all ESP (name, box, tracer, skeleton, chams, off-screen marker). Manual Vehicle HBE moved to the Miscellaneous tab, the vehicle pickers use the hold-ring, and the status light got a working hover tooltip. Emergency and Console were folded into a single Settings tab to declutter the tab bar.",
		"Stability pass: fixed the recurring 'Position is not a valid member of Model' ESP error (accessory models like TorsoStrap were matched as body parts), throttled/capped error logging to stop the freeze and Clear-Errors glitch, and wrapped console + tooltip text so nothing clips off-screen. Disable-While-Seated now defaults on to stop the in-car freeze. Whitelists auto-save to disk and restore every execute, whitelisted players can keep ESP, and ESP names support Display/Account/Both.",
		"Feature batch: Outline-Only HBE (wireframe instead of a solid block, with colour + transparency). Vehicle Assist replaces the old speed/stabilizer -- a keybind speed jolt, a speed limiter, and an auto-stabilizer that scales with speed (impulse-based to stop the tire glitch). Teleport-to-player plus teleport-into-the-nearest-seat. Vehicle ESP with a registered list and Car/Heli/Boat/Plane tagging. Inf-ammo with an in-hand / hold-pick gun picker. ESP is now fully independent of the HBE filters so it never flickers off.",
		"Resilience pass: added an adaptive self-heal watchdog that reconciles the player list every few seconds (auto-recovers missed joins/respawns, prunes leavers), self-refreshing character references so ESP/HBE never go dark on a stale character, BasePart guards on the skeleton, Vehicle Assist now releases its gyro the instant you exit/switch vehicles, and duplicate player-list entries are prevented. Everything stays pcall-isolated so an error degrades to partial function, never a freeze.",
		"Improvements batch 1: per-game settings profiles (auto-save/load by PlaceId), a master PANIC/Reset-All button, global Rainbow ESP with a speed slider, animated chams Glow Pulse, a vehicle anti-fling clamp on the speed jolt, and an on-screen watermark showing tracked-player count and error status. Each was added as an isolated module so it can't affect the core.",
		"Improvements batch 2: Smart Jitter (smooth sine size-variation) and a Max-Plausible cap for safer extension, ESP line-thickness + distance-fade, Vehicle ESP now shows the driver/occupant name, and the per-game profile now persists every add-on's settings too (unified persistence). Remaining draft items (aim-resolver modes, dropdown search, blurred/animated UI) are game/fork-specific and intentionally left for dedicated passes.",
		"Adaptive Inf-Ammo resolver: it now tries detection strategies in order (named values, attributes, Configuration folders, player-side values) and falls through until one finds the ammo, caching the winner per gun. If all fail, a learning detector watches the gun and adopts any number that drops when you fire. A label shows which method detected.",
	}
	local function verNum(i) return 1 + 0.5 * (i - 1) end
	local function fmtV(n) return "V" .. (n == math.floor(n) and tostring(math.floor(n)) or tostring(n)) end

	local versionStrings, notesFor = {}, {}
	for i = #CHANGELOG, 1, -1 do            -- newest first in the dropdown
		local v = fmtV(verNum(i))
		table.insert(versionStrings, v)
		notesFor[v] = CHANGELOG[i]
	end
	local currentVersion = fmtV(verNum(#CHANGELOG))

	local STATUS_DESC = {
		green  = "Green = 100% functional. Core, all modules and rendering are operational with no logged errors.",
		yellow = "Yellow = Core is working. The UI and hitbox core run, but a module failed to load or errors were logged.",
		red    = "Red = Critical error. The UI launched but the core is not functional.",
	}
	local STATUS_COLOR = {
		green  = Color3.fromRGB(60, 220, 90),
		yellow = Color3.fromRGB(245, 215, 60),
		red    = Color3.fromRGB(235, 70, 70),
	}
	local LEGEND = "Status colours:\n- " .. STATUS_DESC.green .. "\n- " .. STATUS_DESC.yellow .. "\n- " .. STATUS_DESC.red

	local versionLabel = statusGroup:AddLabel("cryptonize's library  " .. currentVersion)
	local statusLabel  = statusGroup:AddLabel("Status: checking...")

	-- Best-effort colour of a LinoriaLib label's underlying TextLabel.
	local function tintLabel(lbl, color)
		pcall(function()
			local inst = rawget(lbl, "TextLabel") or rawget(lbl, "Label") or rawget(lbl, "Instance")
			if typeof(inst) == "Instance" and inst:IsA("TextLabel") then inst.TextColor3 = color; return end
			for _, k in ipairs({ "Holder", "Container", "TextLabel", "Instance" }) do
				local h = rawget(lbl, k)
				if typeof(h) == "Instance" then
					if h:IsA("TextLabel") then h.TextColor3 = color end
					for _, d in ipairs(h:GetDescendants()) do
						if d:IsA("TextLabel") then d.TextColor3 = color end
					end
				end
			end
		end)
	end

	-- Core health check: RED if UI is up but core is broken; GREEN if everything
	-- (core + all three modules + no logged errors); YELLOW if core works but a
	-- module failed to register or errors were logged.
	local function computeStatus()
		if not (Library and mainWindow and getgenv().FurryHBE and Toggles.MasterToggle
			and Toggles.extenderToggled and Options.extenderSize) then return "red" end
		if type(players) ~= "table" or not runUpdatePlayers then return "red" end
		local addons = (getgenv().FurryHBE.Addons) or {}
		local full = addons.Precision and addons.Streamer and addons.Teleport and addons.Misc
		if full and #errorLog == 0 then return "green" end
		return "yellow"
	end

	local function refreshStatus()
		local s = computeStatus()
		statusLabel:SetText("Status: " .. string.upper(s))
		tintLabel(statusLabel, STATUS_COLOR[s])
		tintLabel(versionLabel, STATUS_COLOR[s])
	end
	refreshStatus()

	-- Self-contained hover tooltip (reliable across LinoriaLib forks): bind
	-- MouseEnter/Leave on the real TextLabels and draw our own follow-the-mouse box.
	local function labelInstance(lbl)
		local inst = rawget(lbl, "TextLabel") or rawget(lbl, "Label") or rawget(lbl, "Instance")
		if typeof(inst) == "Instance" and inst:IsA("TextLabel") then return inst end
		for _, k in ipairs({ "Holder", "Container" }) do
			local h = rawget(lbl, k)
			if typeof(h) == "Instance" then
				if h:IsA("TextLabel") then return h end
				for _, d in ipairs(h:GetDescendants()) do if d:IsA("TextLabel") then return d end end
			end
		end
	end
	pcall(function()
		local tipGui = Instance.new("ScreenGui")
		tipGui.Name = "FurryHBE_StatusTip"; tipGui.ResetOnSpawn = false
		tipGui.DisplayOrder = 999999; tipGui.IgnoreGuiInset = true
		tipGui.Parent = game:GetService("CoreGui")
		local tip = Instance.new("TextLabel")
		tip.AutomaticSize = Enum.AutomaticSize.Y
		tip.Size = UDim2.fromOffset(320, 0)
		tip.BackgroundColor3 = Color3.fromRGB(20, 20, 20); tip.BackgroundTransparency = 0.05
		tip.TextColor3 = Color3.fromRGB(235, 235, 235); tip.TextSize = 13
		tip.Font = Enum.Font.SourceSans; tip.TextWrapped = true
		tip.TextXAlignment = Enum.TextXAlignment.Left; tip.TextYAlignment = Enum.TextYAlignment.Top
		tip.Text = LEGEND; tip.Visible = false; tip.ZIndex = 999999; tip.Parent = tipGui
		local pad = Instance.new("UIPadding", tip)
		pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)
		pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
		Instance.new("UIStroke", tip).Color = Color3.fromRGB(0, 0, 0)
		local function bind(inst)
			if not inst then return end
			inst.MouseEnter:Connect(function() tip.Visible = true end)
			inst.MouseLeave:Connect(function() tip.Visible = false end)
		end
		bind(labelInstance(statusLabel)); bind(labelInstance(versionLabel))
		UserInputService.InputChanged:Connect(function(input)
			if tip.Visible and input.UserInputType == Enum.UserInputType.MouseMovement then
				tip.Position = UDim2.fromOffset(input.Position.X + 18, input.Position.Y + 12)
			end
		end)
		Bridge:RegisterAddon("StatusTip", { onUnload = function() pcall(function() tipGui:Destroy() end) end })
	end)

	-- Changelog viewer: the 3 sentences only load when the button is clicked.
	clGroup:AddDropdown("clVersion", { Text = "Version", Values = versionStrings, Default = currentVersion, Multi = false, AllowNull = false, Tooltip = "Pick a version, then click View Changelog" })
	local notesLabel = clGroup:AddLabel("Select a version and click 'View Changelog'.", true)
	local clShown = false
	clGroup:AddButton("View Changelog", function()
		if clShown then
			notesLabel:SetText("Select a version and click 'View Changelog'.")  -- fold back up
			clShown = false
		else
			local v = Options.clVersion.Value
			notesLabel:SetText((v and notesFor[v]) and (v .. ":\n" .. notesFor[v]) or "No notes for that version.")
			clShown = true
		end
	end):AddToolTip("Show/hide the changelog for the selected version")

	-- Live status refresh; the loop exits cleanly when the script unloads.
	task.spawn(function()
		while getgenv().FurryHBEInjected do
			task.wait(1)
			pcall(refreshStatus)
		end
	end)
	print("[Version/CL] Tab created. Current " .. currentVersion)
end)

-- Make the tab-scroll hint obvious. When there are more tabs than fit, LinoriaLib
-- shows a small "scrollwheel >" marker above the tab bar; we find it and make it
-- clearer + brighter. Best-effort (pcall) so it never breaks load.
pcall(function()
	local sg = Library.ScreenGui
	if not sg then return end
	for _, d in ipairs(sg:GetDescendants()) do
		if d:IsA("TextLabel") and typeof(d.Text) == "string" and d.Text:lower():find("scroll") then
			d.Text = "scroll-wheel here to switch tabs"
			d.TextColor3 = Color3.fromRGB(255, 180, 60)
			d.TextTransparency = 0
			d.Visible = true
		end
	end
end)

-- ===== [Improvement #1] Per-game settings profile (auto-loads per PlaceId) =====
pcall(function()
	local HttpService = game:GetService("HttpService")
	local PG_FILE = "FurryHBE_Game_" .. tostring(game.PlaceId) .. ".json"
	local PG_KEYS = {
		"MasterToggle","extenderToggled","extenderSize","extenderTransparency","hitboxShape",
		"partSpecificSizing","headSize","torsoSize","limbSize","dynamicSizing","smoothTransitions",
		"transitionSpeed","collisionsToggled","outlineMode","outlineTransparency","maxDistance",
		"closestTargetsOnly","maxTargets","updateRate","randomizationToggled","randomizationAmount",
		"humanizationToggled","legitModeToggled","seatDisableHBE","seatRadiusMode","seatRadius",
		"espNameToggled","espNameSize","espHighlightToggled","espBoxToggled","espBoxScale",
		"espTracerToggled","espSkeletonToggled","espHealthBarToggled","espNameType","espMaxDistance",
		-- ESP extras + anti-detect
		"espRainbow","espRainbowSpeed","espThickness","espDistanceFade","espChamsGlow",
		"priorityFlash","smartJitter","maxPlausibleMult","espWhitelisted","espAntiOverlap","espOverlapGap",
		-- Add-on modules (unified persistence)
		"precisionEnabled","precisionExclusive","precisionHitboxSize","precisionTransparency","precisionShape",
		"precisionCollisions","autoSelectTarget","selectionRadius","dynamicScalingEnabled",
		"scalingCloseFactor","scalingFarFactor","scalingThreshold",
		"vehicleAssist","vehicleJoltPower","vehicleSpeedLimiter","vehicleSpeedCap","vehicleManualMode",
		"toolExpanderEnabled","toolExpandSize","toolAutoApply",
		"infAmmoEnabled","infAmmoAllTools","infAmmoAmount",
		"vehicleEspEnabled","mvHbeEnabled","mvHbeSize","mvHbeTransparency","mvHbeCollisions","mvHbeWholeModel",
		"streamerMaster","hideFOVCircle","hidePlayerESP","hideChams","hideHitboxGlow",
	}
	local g = profilesTab:AddLeftGroupbox("Per-Game Profile")
	g:AddLabel("Game PlaceId: " .. tostring(game.PlaceId), true)
	local function savePG()
		if not writefile then Library:Notify("Executor has no writefile"); return end
		local data = {}
		for _, k in ipairs(PG_KEYS) do
			local c = Options[k] or Toggles[k]
			if c ~= nil then
				local v = c.Value
				if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then data[k] = v end
			end
		end
		pcall(function() writefile(PG_FILE, HttpService:JSONEncode(data)) end)
		Library:Notify("Saved settings for this game")
	end
	local function loadPG(notify)
		if not (isfile and readfile and isfile(PG_FILE)) then
			if notify then Library:Notify("No saved profile for this game") end
			return
		end
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(PG_FILE)) end)
		if ok and type(data) == "table" then
			for k, v in pairs(data) do
				local c = Options[k] or Toggles[k]
				if c then pcall(function() c:SetValue(v) end) end
			end
			if notify then Library:Notify("Loaded this game's profile") end
		end
	end
	g:AddButton("Save Game Profile", savePG):AddToolTip("Save current core settings, keyed to this game's PlaceId")
	g:AddButton("Load Game Profile", function() loadPG(true) end):AddToolTip("Re-apply this game's saved settings")
	g:AddButton("Delete Game Profile", function()
		if delfile and isfile and isfile(PG_FILE) then pcall(function() delfile(PG_FILE) end); Library:Notify("Deleted this game's profile") end
	end):AddToolTip("Forget the saved settings for this game")
	pcall(function() loadPG(false) end)  -- auto-load on inject
	print("[PerGameProfile] Ready for PlaceId " .. tostring(game.PlaceId))
end)

-- ===== [Improvement #9] Master Panic / Reset All =====
pcall(function()
	emergencyGroupbox:AddButton("PANIC / Reset All", function()
		pcall(function() if Toggles.MasterToggle then Toggles.MasterToggle:SetValue(false) end end)
		for _, k in ipairs({
			"extenderToggled", "precisionEnabled", "vehicleAssist", "mvHbeEnabled",
			"streamerMaster", "infAmmoEnabled", "vehicleEspEnabled", "toolExpanderEnabled",
			"vehicleSpeedLimiter", "outlineMode", "espNameToggled", "espHighlightToggled",
			"espBoxToggled", "espTracerToggled", "espSkeletonToggled", "fovFilterToggled",
		}) do
			pcall(function() if Toggles[k] then Toggles[k]:SetValue(false) end end)
		end
		pcall(function() if resetAllPlayers then resetAllPlayers() end end)
		pcall(function() if resetWorldParts then resetWorldParts() end end)
		local b = getgenv().FurryHBE
		if b and b.Streamer then
			b.Streamer.hideESP, b.Streamer.hideChams, b.Streamer.hideFOV, b.Streamer.hideHitbox = false, false, false, false
		end
		Library:Notify("PANIC: every feature off, all hitboxes/visuals restored")
	end):AddToolTip("One click: turn every feature off and restore all hitboxes/visuals to normal")
end)

-- ===== [Improvement #15] On-screen watermark (name | tracked | status) =====
pcall(function()
	pcall(function() Library:SetWatermarkVisibility(true) end)
	task.spawn(function()
		while getgenv().FurryHBEInjected do
			pcall(function()
				local n = 0
				for _ in pairs(players) do n = n + 1 end
				local status = (#errorLog == 0) and "OK" or ("ERR " .. #errorLog)
				if Library.SetWatermark then
					Library:SetWatermark(string.format("cryptonize's library  |  tracked %d  |  %s", n, status))
				end
			end)
			task.wait(1)
		end
	end)
end)

pcall(finalInit)

-- Clean teardown when the UI library is unloaded: restore everyone, drop the
-- render binds, and clear the injection flag so the script can be re-run.
pcall(function()
	if Library and Library.OnUnload then
		Library:OnUnload(function()
			pcall(cleanup)
			getgenv().FurryHBEInjected = nil
		end)
	end
end)

-- Adaptive self-heal watchdog. Every few seconds it reconciles the tracked-player
-- table with the real player list: re-adds anyone missing (a PlayerAdded that was
-- missed, or an object that got dropped) and prunes players who left. Keeps ESP/HBE
-- working without needing the manual "Fix Missing Players" button, and recovers
-- automatically from transient errors. Everything is pcall'd so it can't break.
task.spawn(function()
	while getgenv().FurryHBEInjected do
		task.wait(3)
		pcall(function()
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= lPlayer and not players[plr] then
					pcall(addPlayer, plr)
				end
			end
			for plr in pairs(players) do
				if typeof(plr) ~= "Instance" or not plr.Parent then
					pcall(function() removePlayer(plr) end)
					players[plr] = nil
				end
			end
		end)
	end
end)
