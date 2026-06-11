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

-- NOTE: the previous global Library.AddToolTip wrapper was removed -- on some
-- LinoriaLib forks it broke control creation (the UI only built the first tab).
-- Tooltips that need multiple lines just use explicit \n in their text instead.

-- GUI-based Drawing fallback for Potassium
local DrawingFallback = {}
DrawingFallback.__index = DrawingFallback

-- Prefer gethui() (hidden, stealthier container) over CoreGui when the executor
-- exposes it; fall back to CoreGui otherwise.
local function getSafeGuiParent()
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and typeof(hui) == "Instance" then return hui end
	return game:GetService("CoreGui")
end

local DrawingGui = Instance.new("ScreenGui")
DrawingGui.Name = "DrawingFallback"
DrawingGui.ResetOnSpawn = false
-- IgnoreGuiInset is REQUIRED: WorldToViewportPoint returns true screen-space
-- coordinates (no topbar inset), so without this the whole ESP overlay is shoved
-- ~36px down and names/boxes sit off their targets. DisplayOrder keeps ESP above
-- the game world while staying below the LinoriaLib menu.
DrawingGui.IgnoreGuiInset = true
DrawingGui.DisplayOrder = 10
DrawingGui.Parent = getSafeGuiParent()

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
	self.transparency = 0
	self.from = Vector2.new(0, 0)
	self.to = Vector2.new(0, 0)
	self.font = 2
	
	-- Create GUI element based on type
	if type == "Circle" then
		self.element = Instance.new("Frame")
		self.element.Size = UDim2.new(0, 1, 0, 1)
		self.element.BackgroundColor3 = self.color
		self.element.BackgroundTransparency = 1
		self.element.BorderSizePixel = 0
		self.element.Parent = DrawingGui
		-- Full-radius corner turns the square Frame into an actual circle, so the
		-- FOV ring and part-scanner rings render round instead of as boxes.
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = self.element

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
		self.element.Font = Enum.Font.SourceSans
		self.element.AutomaticSize = Enum.AutomaticSize.XY
		self.element.Size = UDim2.new(0, 0, 0, 0)
		self.element.Parent = DrawingGui
		
		-- Always create outline stroke so it's ready when needed
		self.border = Instance.new("UIStroke")
		self.border.Color = self.outlineColor
		self.border.Thickness = 1
		self.border.Enabled = self.outline
		self.border.Parent = self.element
	elseif type == "Square" then
		self.element = Instance.new("Frame")
		self.element.BackgroundColor3 = self.color
		self.element.BorderSizePixel = 0
		self.element.Parent = DrawingGui
		
		-- Always create UIStroke so hollow squares render immediately
		self.border = Instance.new("UIStroke")
		self.border.Color = self.color
		self.border.Thickness = math.max(1, self.thickness)
		self.border.Enabled = true
		self.border.Parent = self.element
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
		-- For Text, .size is a NUMBER (font size), not Vector2
		local fontSize = self.size
		if type(fontSize) == "number" then
			self.element.TextSize = math.max(1, fontSize)
		elseif typeof(fontSize) == "Vector2" then
			self.element.TextSize = math.max(1, fontSize.Y)
		else
			self.element.TextSize = 14
		end
		if self.center then
			self.element.AnchorPoint = Vector2.new(0.5, 0.5)
		else
			self.element.AnchorPoint = Vector2.new(0, 0)
		end
		self.element.TextTransparency = self.transparency or 0
		if self.border then
			self.border.Enabled = self.outline
			self.border.Color = self.outlineColor
		end
	elseif self.type == "Square" then
		self.element.Size = UDim2.new(0, self.size.X, 0, self.size.Y)
		self.element.Position = UDim2.new(0, self.position.X, 0, self.position.Y)
		self.element.BackgroundColor3 = self.color
		self.element.BackgroundTransparency = self.filled and 0 or 1
		-- A hollow Square (Filled=false) is meant to read as an outline, but an empty
		-- Frame draws nothing in the GUI fallback -- which is why the 2D box never
		-- rendered. Lazily attach a UIStroke and trace the box in its own colour. (B2)
		if not self.filled then
			if not self.border then
				self.border = Instance.new("UIStroke")
				self.border.Parent = self.element
			end
			self.border.Color = self.color
			self.border.Thickness = math.max(1, self.thickness or 1)
			self.border.Enabled = true
		elseif self.border then
			self.border.Color = self.outlineColor
			self.border.Thickness = self.thickness
		end
	elseif self.type == "Line" then
		-- Proper line rendering from From/To using rotation
		local p1 = self.from
		local p2 = self.to
		if typeof(p1) == "Vector2" and typeof(p2) == "Vector2" then
			local dx = p2.X - p1.X
			local dy = p2.Y - p1.Y
			local length = math.sqrt(dx * dx + dy * dy)
			local angle = math.atan2(dy, dx)
			local cx = (p1.X + p2.X) / 2
			local cy = (p1.Y + p2.Y) / 2
			self.element.Size = UDim2.new(0, length, 0, math.max(1, self.thickness or 1))
			self.element.Position = UDim2.new(0, cx, 0, cy)
			self.element.AnchorPoint = Vector2.new(0.5, 0.5)
			self.element.Rotation = math.deg(angle)
		end
		self.element.BackgroundColor3 = self.color
		self.element.BackgroundTransparency = self.transparency or 0
	end
end

-- Decide whether to use the native Drawing library or the GUI fallback.
-- CRITICAL: a successful Drawing.new() only proves the CONSTRUCTOR works -- not
-- that the object actually paints on screen. On Potassium (Solara-based), native
-- Drawing objects construct fine (this probe passes) but do NOT reliably render
-- 2D ESP -- names, boxes and tracers all stay invisible. That is the real reason
-- ESP looked broken there while the LinoriaLib UI (regular GUI, not Drawing) and
-- chams (a real Highlight) still worked. So we detect the executor and route
-- Potassium/Solara through the GUI fallback, which uses real TextLabels/Frames in
-- a ScreenGui and always renders.
--   Overrides (set before executing):
--     getgenv().FurryHBE_ForceGuiESP   = true  -> always use the GUI fallback
--     getgenv().FurryHBE_ForceNativeESP = true -> always use native Drawing
local execName = ""
pcall(function() if identifyexecutor then execName = tostring((identifyexecutor())) end end)
execName = execName:lower()
local guiOnlyExecutor = execName:find("potassium") ~= nil or execName:find("solara") ~= nil

local nativeConstructs = pcall(function()
	local probe = Drawing.new("Circle")
	-- Potassium uses :Destroy(), other executors use :Remove()
	if probe.Destroy then probe:Destroy() elseif probe.Remove then probe:Remove() end
end)

local useNativeDrawing
if getgenv().FurryHBE_ForceGuiESP then
	useNativeDrawing = false
elseif getgenv().FurryHBE_ForceNativeESP then
	useNativeDrawing = nativeConstructs
else
	useNativeDrawing = nativeConstructs and not guiOnlyExecutor
end
getgenv().FurryHBE_UsingNativeESP = useNativeDrawing  -- readable for debugging

if useNativeDrawing then
	-- Use native Drawing directly — no wrapper, no proxy, no mutation.
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
		From = "from", To = "to", Transparency = "transparency", Font = "font",
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

-- Safe drawing removal: Potassium uses :Destroy(), other executors use :Remove()
local function safeRemoveDrawing(obj)
	if not obj then return end
	if type(obj.Destroy) == "function" then
		pcall(function() obj:Destroy() end)
	elseif type(obj.Remove) == "function" then
		pcall(function() obj:Remove() end)
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

	warn("[Replication] " .. context .. ": " .. tostring(err))
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
	safeRemoveDrawing(fovCircle)
	
	-- Cleanup part scanner
	if partScannerHighlight then
		pcall(function() partScannerHighlight:Destroy() end)
		partScannerHighlight = nil
	end
	safeRemoveDrawing(partScannerProgressCircle)
	if partScannerFillCircle then safeRemoveDrawing(partScannerFillCircle) end
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
	-- F13c: drop every tracked connection.
	if bridge and bridge.DisconnectAll then pcall(function() bridge:DisconnectAll() end) end

	getgenv().FurryHBELoaded = false
end

-- Window setup (with failsafe)
local windowConfig = {
	Title = "cryptonize's library   ·   scroll-wheel over the tabs to switch",
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

-- F13c: tracked-connection helper. Bridge:Connect(signal, fn) connects and records
-- the connection so Bridge:DisconnectAll() (run from cleanup) tears every one down
-- on unload -- no leaked RBXScriptConnections. New code should prefer this over a
-- bare :Connect when it doesn't already manage its own teardown.
Bridge.Connections = {}
function Bridge:Connect(signal, fn)
	local ok, conn = pcall(function() return signal:Connect(fn) end)
	if ok and conn then table.insert(self.Connections, conn); return conn end
	return nil
end
function Bridge:DisconnectAll()
	for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
	self.Connections = {}
end

-- ===== Plugin system (compartmentalization / plug-and-play) ================
-- A plugin is a module string that returns { name, tab, requires, load(ctx), unload }.
-- EnablePlugin loadstrings it and calls load(ctx); UnloadPlugin runs unload + the ctx
-- teardown (disconnects every connection, destroys every tracked instance/groupbox,
-- clears its control keys) and drops all refs so the code GCs. See plugin draft .md.
Bridge.Plugins = {}        -- [name] = { mod, ctx, loaded }
Bridge.PluginSources = {}  -- [name] = { source=, tab=, desc= }
Bridge.Tabs = {}
function Bridge:GetOrMakeTab(name)
	if not self.Tabs[name] then
		local mw = getgenv().mainWindow
		if mw then self.Tabs[name] = mw:AddTab(name) end
	end
	return self.Tabs[name]
end
function Bridge:NewContext(name, tab)
	local C = { _conns = {}, _insts = {}, _gbs = {}, _keys = {}, tab = tab, Bridge = self }
	function C:Connect(signal, fn)
		local ok, c = pcall(function() return signal:Connect(fn) end)
		if ok and c then table.insert(self._conns, c) end
		return c
	end
	function C:Track(inst) table.insert(self._insts, inst); return inst end
	function C:Groupbox(title, side)
		local g = (side == "right") and self.tab:AddRightGroupbox(title) or self.tab:AddLeftGroupbox(title)
		table.insert(self._gbs, g)
		return g
	end
	function C:Control(key) table.insert(self._keys, key) end
	function C:teardown()
		for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
		for _, i in ipairs(self._insts) do pcall(function() if i.Destroy then i:Destroy() elseif i.Remove then i:Remove() end end) end
		-- Best-effort destroy of each groupbox's underlying GUI (LinoriaLib has no
		-- native control-removal, so we probe common container fields).
		for _, g in ipairs(self._gbs) do
			pcall(function()
				for _, k in ipairs({ "Container", "Holder", "ScrollFrame", "Instance" }) do
					local inst = rawget(g, k)
					if typeof(inst) == "Instance" then inst:Destroy() end
				end
			end)
		end
		for _, k in ipairs(self._keys) do pcall(function() rawset(Toggles, k, nil); rawset(Options, k, nil) end) end
		self._conns, self._insts, self._gbs, self._keys = {}, {}, {}, {}
	end
	return C
end
function Bridge:RegisterPluginSource(name, info) self.PluginSources[name] = info end
-- Base URL for external plugin files (set getgenv().FurryHBE_PluginBase to your
-- GitHub raw folder). EnablePlugin fetches <base>/<file> for plugins with no inline
-- source. Per-plugin info.url / info.file / info.source all override.
Bridge.PluginBase = getgenv().FurryHBE_PluginBase or "https://raw.githubusercontent.com/Criptonized/cryptonize-s-HBE/main"
function Bridge:EnablePlugin(name)
	local entry = self.Plugins[name]
	if entry and entry.loaded then return true end
	local info = self.PluginSources[name]
	if not info then return false, "no source registered" end
	-- Resolve the source: inline string, explicit url, local file, or PluginBase/<file>.
	local src = info.source
	if not src then
		local url = info.url
		if (not url or url == "") and self.PluginBase ~= "" then
			url = self.PluginBase:gsub("/$", "") .. "/" .. (info.file or (name:lower() .. ".lua"))
		end
		if info.path and isfile and readfile and isfile(info.path) then
			src = readfile(info.path)
		elseif url and url ~= "" then
			local ok, body = pcall(function() return game:HttpGet(url) end)
			if ok and type(body) == "string" then src = body end
		end
	end
	if not src then return false, "no source/url (set getgenv().FurryHBE_PluginBase)" end
	local fn, cerr = loadstring(src, "=" .. name)
	if not fn then return false, "compile: " .. tostring(cerr) end
	local ok, mod = pcall(fn)
	if not ok or type(mod) ~= "table" or type(mod.load) ~= "function" then return false, "bad module: " .. tostring(mod) end
	local tab = self:GetOrMakeTab(mod.tab or name)
	if not tab then return false, "no tab" end
	local ctx = self:NewContext(name, tab)
	local ok2, err = pcall(mod.load, ctx)
	if not ok2 then pcall(function() ctx:teardown() end); return false, "load: " .. tostring(err) end
	self.Plugins[name] = { mod = mod, ctx = ctx, loaded = true }
	return true
end
function Bridge:UnloadPlugin(name)
	local entry = self.Plugins[name]
	if not (entry and entry.loaded) then return end
	if entry.mod and entry.mod.unload then pcall(entry.mod.unload) end
	pcall(function() entry.ctx:teardown() end)
	self.Plugins[name] = { loaded = false }   -- drop mod + ctx refs so the chunk GCs
	pcall(collectgarbage)
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
			safeRemoveDrawing(ring)
			safeRemoveDrawing(fill)
		end,
	})
end

-- Main Tab
local mainTab = mainWindow:AddTab("HBE")
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
local masterToggle = hitboxGroupbox:AddToggle("MasterToggle", { Text = "Master Toggle", Default = true, Tooltip = "Master on/off switch for the entire script. (Default: ON)" }):OnChanged(function()
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
local extenderToggle = hitboxGroupbox:AddToggle("extenderToggled", { Text = "Enable Hitbox Extender", Default = false, Tooltip = "Toggle hitbox extension on/off. (Default: OFF)" }):OnChanged(function()
	if Toggles.extenderToggled.Value then
		updatePlayers()
	else
		-- Immediately snap every part back to its real size/transparency/collision.
		if resetAllPlayers then resetAllPlayers() end
		if resetWorldParts then resetWorldParts() end
	end
end)
registerUIElement("extenderToggled", extenderToggle)
hitboxGroupbox:AddSlider("extenderSize", { Text = "Hitbox Size", Min = 2, Max = 100, Default = 10, Rounding = 1, Tooltip = "Base size for hitbox extension. (Default: 10)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddDropdown("hitboxShape", { Text = "Hitbox Shape", AllowNull = false, Multi = false, Values = { "Cube", "Flat (disk)", "Tall (pillar)" }, Default = "Cube", Tooltip = "Cube = uniform; Flat = wide & short;\nTall = narrow & tall. (Default: Cube)" }):OnChanged(updatePlayers)
-- Manual escape hatch for the rare "head stays enlarged after turning HBE off"
-- case (corrupted size-default capture / a part the game never re-replicates).
-- Snaps every tracked player + world part back to its recorded real values.
hitboxGroupbox:AddButton("Force Restore All", function()
	pcall(function() if resetAllPlayers then resetAllPlayers() end end)
	pcall(function() if resetWorldParts then resetWorldParts() end end)
	if Library and Library.Notify then Library:Notify("Restored all hitboxes to original size") end
end):AddToolTip("Snap every player's parts back to their real size/transparency/collision.\nUse if a head stays enlarged after toggling the extender off.")

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

local partScannerButton = hitboxGroupbox:AddToggle("partScannerToggled", { Text = "Part Scanner Mode", Default = false, Tooltip = "Click and HOLD on a part to add it.\nHold again on a scanned part to remove it.\n(Default: OFF)" }):OnChanged(function(value)
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
hitboxGroupbox:AddToggle("partScannerAllowWorld", { Text = "Allow World Parts", Default = false, Tooltip = "Let the scanner pick up non-character parts\n(ground, walls, vehicles). Off = only\ncharacter/humanoid parts. (Default: OFF)" })
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
hitboxGroupbox:AddToggle("outlineMode", { Text = "Outline Only", Default = false, Tooltip = "Leave the body looking normal and put the enlarged hit\narea on a SEPARATE invisible part, drawn as a clean outline\nin your outline colour (shaped like the expanded part).\nThe hit area still works for hit-reg.\n(Default: OFF)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddLabel("Outline Color"):AddColorPicker("outlineColor", { Title = "Outline Color", Default = Color3.fromRGB(255, 0, 0) })
hitboxGroupbox:AddSlider("outlineTransparency", { Text = "Outline Transparency", Min = 0, Max = 1, Default = 0, Rounding = 2, Tooltip = "Transparency of the outline lines (0 = solid). (Default: 0)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddInput("customPartName", { Text = "Custom Part Name", Default = "HeadHB", Tooltip = "Name for custom body part matching. (Default: HeadHB)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddDropdown("extenderPartList", { Text = "Body Parts", AllowNull = true, Multi = true, Values = table.clone(DEFAULT_BODY_PARTS), Default = { "Head" }, Tooltip = "Select which body parts to extend. (Default: Head)" }):OnChanged(updatePlayers)

-- Part-specific sizing
hitboxGroupbox:AddToggle("partSpecificSizing", { Text = "Part-Specific Sizing", Default = false, Tooltip = "Enable different sizes for different body parts. (Default: OFF)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddSlider("headSize", { Text = "Head Size", Min = 2, Max = 100, Default = 10, Rounding = 1, Tooltip = "Size for head hitbox. (Default: 10)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddSlider("torsoSize", { Text = "Torso Size", Min = 2, Max = 100, Default = 10, Rounding = 1, Tooltip = "Size for torso hitbox. (Default: 10)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddSlider("limbSize", { Text = "Limb Size", Min = 2, Max = 100, Default = 8, Rounding = 1, Tooltip = "Size for arm/leg hitboxes. (Default: 8)" }):OnChanged(updatePlayers)

-- Dynamic sizing
hitboxGroupbox:AddToggle("dynamicSizing", { Text = "Dynamic Sizing", Default = false, Tooltip = "Scale hitbox based on distance to target. (Default: OFF)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddSlider("dynamicScalingFactor", { Text = "Scaling Factor", Min = 0.1, Max = 2, Default = 1, Rounding = 2, Tooltip = "How much to scale based on distance. (Default: 1)" }):OnChanged(updatePlayers)

-- Smooth transitions
hitboxGroupbox:AddToggle("smoothTransitions", { Text = "Smooth Transitions", Default = false, Tooltip = "Interpolate size changes smoothly. (Default: OFF)" }):OnChanged(updatePlayers)
hitboxGroupbox:AddSlider("transitionSpeed", { Text = "Transition Speed", Min = 0.1, Max = 2, Default = 0.5, Rounding = 2, Tooltip = "Speed of size interpolation. (Default: 0.5)" }):OnChanged(updatePlayers)

-- Filter Settings
filterGroupbox:AddSlider("maxDistance", { Text = "Max Distance", Min = 0, Max = 1000, Default = 1000, Rounding = 1, Tooltip = "Maximum distance to extend/ESP players (0 = unlimited). (Default: 1000)" }):OnChanged(updatePlayers)
filterGroupbox:AddToggle("closestTargetsOnly", { Text = "Closest Targets Only", Default = false, Tooltip = "Only extend the nearest N players\n(more legit + better performance). (Default: OFF)" }):OnChanged(updatePlayers)
filterGroupbox:AddSlider("maxTargets", { Text = "Max Targets", Min = 1, Max = 10, Default = 1, Rounding = 0, Tooltip = "How many of the nearest players to extend\nwhen Closest Targets Only is on. (Default: 1)" }):OnChanged(updatePlayers)
filterGroupbox:AddToggle("fovFilterToggled", { Text = "FOV Filter", Default = false, Tooltip = "Only target players within FOV circle. (Default: OFF)" }):OnChanged(updatePlayers)
filterGroupbox:AddSlider("fovSize", { Text = "FOV Size", Min = 10, Max = 500, Default = 100, Rounding = 1, Tooltip = "Radius of FOV circle. (Default: 100)" }):OnChanged(updatePlayers)
filterGroupbox:AddLabel("FOV Color"):AddColorPicker("fovColor", { Title = "FOV Color", Default = Color3.fromRGB(255, 255, 255) })
Options.fovColor:OnChanged(updatePlayers)
filterGroupbox:AddSlider("fovThickness", { Text = "FOV Thickness", Min = 1, Max = 5, Default = 1, Rounding = 1, Tooltip = "Thickness of FOV circle. (Default: 1)" }):OnChanged(updatePlayers)
filterGroupbox:AddToggle("autoExpandFOV", { Text = "Auto-Expand in FOV", Default = false, Tooltip = "Automatically expand hitbox when target is in FOV. (Default: OFF)" }):OnChanged(updatePlayers)
filterGroupbox:AddToggle("weaponFilterToggled", { Text = "Weapon Filter", Default = false, Tooltip = "Ignore players holding specific weapons. (Default: OFF)" }):OnChanged(updatePlayers)
filterGroupbox:AddButton("Extract Weapons", function()
	local weapons = extractWeapons()
	Options.weaponList.Values = weapons
	Options.weaponList:SetValues()
	Library:Notify("Extracted " .. #weapons .. " weapons")
end):AddToolTip("Extract all weapons from the game")
filterGroupbox:AddDropdown("weaponList", { Text = "Ignored Weapons", AllowNull = true, Multi = true, Values = {}, Tooltip = "Select weapons to ignore. (Default: none)" }):OnChanged(updatePlayers)

-- Anti-Detection
antiDetectionGroupbox:AddToggle("randomizationToggled", { Text = "Randomization", Default = false, Tooltip = "Add slight randomization to hitbox sizes. (Default: OFF)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddSlider("randomizationAmount", { Text = "Random Amount", Min = 0, Max = 5, Default = 1, Rounding = 1, Tooltip = "Maximum random size variation. (Default: 1)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("smartJitter", { Text = "Smart Jitter (sine)", Default = false, Tooltip = "Use a smooth sine wave for the size jitter instead of\nrandom snapping (harder to fingerprint). (Default: OFF)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddSlider("maxPlausibleMult", { Text = "Max Plausible x", Min = 0, Max = 50, Default = 0, Rounding = 1, Tooltip = "Cap the hitbox at this multiple of the part's real size.\n0 = no cap. Keeps extension believable. (Default: 0)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("humanizationToggled", { Text = "Humanization Delay", Default = false, Tooltip = "Add delay between target switches. (Default: OFF)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddSlider("humanizationDelay", { Text = "Delay (ms)", Min = 0, Max = 1000, Default = 100, Rounding = 1, Tooltip = "Delay in milliseconds between target switches. (Default: 100)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("legitModeToggled", { Text = "Legit Mode", Default = false, Tooltip = "Only extend when crosshair is near target. (Default: OFF)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddSlider("legitModeFOV", { Text = "Legit FOV", Min = 1, Max = 50, Default = 10, Rounding = 1, Tooltip = "FOV threshold for legit mode. (Default: 10)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("autoOffWhenDead", { Text = "Auto-Off When Dead", Default = false, Tooltip = "Automatically stop extending while you are dead or spectating. (Default: OFF)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("seatDisableHBE", { Text = "Disable While Seated", Default = true, Tooltip = "Stop extending hitboxes while YOU sit in any seat (car/turret/etc).\nPrevents the in-vehicle freeze where players & cars look stuck.\nResumes automatically when you get out. (Default: ON)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddToggle("seatRadiusMode", { Text = "Seated: Nearby Only", Default = false, Tooltip = "When seated, only disable hitboxes for players\nwithin the radius below instead of everyone. (Default: OFF)" }):OnChanged(updatePlayers)
antiDetectionGroupbox:AddSlider("seatRadius", { Text = "Seated Radius (studs)", Min = 5, Max = 200, Default = 30, Rounding = 1, Tooltip = "Radius used by 'Seated: Nearby Only'. (Default: 30)" }):OnChanged(updatePlayers)
-- Heuristic detection-risk estimate from your current settings (updated in updateStatus).
local riskLabel = antiDetectionGroupbox:AddLabel("Detection risk: -")

-- Ignores
ignoresGroupbox:AddToggle("extenderSitCheck", { Text = "Ignore Sitting Players", Default = false, Tooltip = "Don't extend players who are sitting. (Default: OFF)" }):OnChanged(updatePlayers)
ignoresGroupbox:AddToggle("seatExitDelayEnabled", { Text = "Sitting Grace After Exit", Default = false, Tooltip = "When you exit a seat/car, temporarily SUSPEND 'Ignore Sitting\nPlayers' for the delay below so you CAN hit players still seated\n(e.g. hop out to shoot the people still in their cars). Ignore-\nsitting resumes after. Needs 'Ignore Sitting Players' on. (Default: OFF)" }):OnChanged(updatePlayers)
ignoresGroupbox:AddSlider("seatExitDelay", { Text = "Sitting Grace (sec)", Min = 1, Max = 15, Default = 6, Rounding = 1, Tooltip = "How long after you exit a seat that sitting players stay\ntargetable before 'Ignore Sitting Players' kicks back in. (Default: 6)" })
ignoresGroupbox:AddToggle("extenderFFCheck", { Text = "Ignore Forcefielded Players", Default = false, Tooltip = "Don't extend players with forcefields. (Default: OFF)" }):OnChanged(updatePlayers)
ignoresGroupbox:AddToggle("ignoreSelectedPlayersToggled", { Text = "Ignore Selected Players", Default = false, Tooltip = "Don't extend selected players. (Default: OFF)" }):OnChanged(updatePlayers)
ignoresGroupbox:AddDropdown("ignorePlayerList", { Text = "Players", AllowNull = true, Multi = true, Values = {}, Tooltip = "Select players to ignore. (Default: none)" }):OnChanged(updatePlayers)
ignoresGroupbox:AddToggle("ignoreOwnTeamToggled", { Text = "Ignore Own Team", Default = false, Tooltip = "Don't extend teammates. (Default: OFF)" }):OnChanged(updatePlayers)
ignoresGroupbox:AddToggle("ignoreSelectedTeamsToggled", { Text = "Ignore Selected Teams", Default = false, Tooltip = "Don't extend selected teams. (Default: OFF)" }):OnChanged(updatePlayers)
ignoresGroupbox:AddDropdown("ignoreTeamList", { Text = "Teams", AllowNull = true, Multi = true, Values = {}, Tooltip = "Select teams to ignore. (Default: none)" }):OnChanged(updatePlayers)
ignoresGroupbox:AddToggle("collisionsToggled", { Text = "Enable Collisions", Default = false, Tooltip = "Keep collisions on extended hitboxes. (Default: OFF)" }):OnChanged(updatePlayers)

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
local espNameToggle = espNameGroupbox:AddToggle("espNameToggled", { Text = "Enable Name ESP", Default = false, Tooltip = "Show player names. (Default: OFF)" }):AddColorPicker("espNameColor1", { Title = "Fill Color", Default = Color3.fromRGB(255, 255, 255) }):AddColorPicker("espNameColor2", { Title = "Outline Color", Default = Color3.fromRGB(0, 0, 0) })
registerUIElement("espNameToggled", espNameToggle)
Toggles.espNameToggled:OnChanged(updatePlayers)
Options.espNameColor1:OnChanged(updatePlayers)
Options.espNameColor2:OnChanged(updatePlayers)
espNameGroupbox:AddToggle("espNameUseTeamColor", { Text = "Use Team Color", Default = false, Tooltip = "Use team color for name ESP. (Default: OFF)" }):OnChanged(updatePlayers)
espNameGroupbox:AddDropdown("espNameType", { Text = "Name Type", AllowNull = false, Multi = false, Values = { "Display Name", "Account Name", "Both (Display + @User)" }, Default = "Display Name", Tooltip = "Which name to show.\nBoth = DisplayName (@AccountName). (Default: Display Name)" }):OnChanged(updatePlayers)
espNameGroupbox:AddToggle("espDistanceToggled", { Text = "Show Distance", Default = false, Tooltip = "Show distance to player. (Default: OFF)" }):OnChanged(updatePlayers)
espNameGroupbox:AddToggle("espTeamToggled", { Text = "Show Team Name", Default = false, Tooltip = "Show a tiny team-name subscript below the player's name. (Default: OFF)" }):OnChanged(updatePlayers)
espNameGroupbox:AddSlider("espNameSize", { Text = "Name Text Size", Min = 8, Max = 36, Default = 14, Rounding = 0, Tooltip = "Font size of ESP names. Smaller = far less\noverlap when players clump together. (Default: 14)" })

-- Chams
-- Chams default to a VISIBLE fill+outline. They used to default to pure black on
-- both, which renders invisible against most game backgrounds -- the "chams don't
-- work" report. Fill = translucent red, outline = white.
local espChamsToggle = espChamsGroupbox:AddToggle("espHighlightToggled", { Text = "Enable Chams", Default = false, Tooltip = "Show player highlights. (Default: OFF)" }):AddColorPicker("espHighlightColor1", { Title = "Fill Color", Default = Color3.fromRGB(255, 60, 60) }):AddColorPicker("espHighlightColor2", { Title = "Outline Color", Default = Color3.fromRGB(255, 255, 255) })
registerUIElement("espHighlightToggled", espChamsToggle)
Toggles.espHighlightToggled:OnChanged(updatePlayers)
Options.espHighlightColor1:OnChanged(updatePlayers)
Options.espHighlightColor2:OnChanged(updatePlayers)
espChamsGroupbox:AddToggle("espHighlightUseTeamColor", { Text = "Use Team Color", Default = false, Tooltip = "Use team color for chams. (Default: OFF)" }):OnChanged(updatePlayers)
espChamsGroupbox:AddDropdown("espHighlightDepthMode", { Text = "Depth Mode", AllowNull = false, Multi = false, Values = { "Occluded", "AlwaysOnTop" }, Default = "Occluded", Tooltip = "How chams render through walls. (Default: Occluded)" }):OnChanged(updatePlayers)
espChamsGroupbox:AddSlider("espHighlightFillTransparency", { Text = "Fill Transparency", Min = 0, Max = 1, Default = 0.5, Rounding = 2, Tooltip = "Transparency of chams fill. (Default: 0.5)" }):OnChanged(updatePlayers)
espChamsGroupbox:AddSlider("espHighlightOutlineTransparency", { Text = "Outline Transparency", Min = 0, Max = 1, Default = 0, Rounding = 2, Tooltip = "Transparency of chams outline. (Default: 0)" }):OnChanged(updatePlayers)
espChamsGroupbox:AddToggle("espChamsGlow", { Text = "Glow Pulse", Default = false, Tooltip = "Animate the chams outline so it pulses/glows. (Default: OFF)" })

-- Advanced ESP
espAdvancedGroupbox:AddToggle("espHealthBarToggled", { Text = "Health Bar", Default = false, Tooltip = "Show health bar above player. (Default: OFF)" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddToggle("espHealthTextToggled", { Text = "Health Text", Default = false, Tooltip = "Show numeric health next to the health bar. (Default: OFF)" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddToggle("espBoxToggled", { Text = "2D Box", Default = false, Tooltip = "Show 2D box around player. (Default: OFF)" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddSlider("espBoxScale", { Text = "2D Box Size", Min = 0.3, Max = 1.5, Default = 0.85, Rounding = 2, Tooltip = "Scale of the 2D box. Lower = tighter boxes\nthat overlap less when players bunch up. (Default: 0.85)" })
espAdvancedGroupbox:AddToggle("espAntiOverlap", { Text = "Anti-Overlap Names", Default = true, Tooltip = "Nudge ESP names apart when players clump\ntogether so they don't render on top of each other.\n(Default: ON)" })
espAdvancedGroupbox:AddToggle("espRainbow", { Text = "Rainbow ESP", Default = false, Tooltip = "Cycle every player's ESP (name/box/tracer/skeleton/chams)\nthrough a rainbow. (Default: OFF)" })
espAdvancedGroupbox:AddSlider("espRainbowSpeed", { Text = "Rainbow Speed", Min = 0.1, Max = 3, Default = 0.7, Rounding = 2, Tooltip = "How fast the rainbow cycles. (Default: 0.7)" })
espAdvancedGroupbox:AddSlider("espThickness", { Text = "Line Thickness", Min = 1, Max = 5, Default = 1, Rounding = 1, Tooltip = "Thickness of box/tracer/skeleton lines. (Default: 1)" })
espAdvancedGroupbox:AddToggle("espDistanceFade", { Text = "Distance Fade", Default = false, Tooltip = "Fade ESP out as players get farther away (relative to\nESP Max Distance). Native Drawing only. (Default: OFF)" })
espAdvancedGroupbox:AddSlider("espOverlapGap", { Text = "Overlap Spacing", Min = 8, Max = 40, Default = 16, Rounding = 0, Tooltip = "Vertical pixels enforced between names by Anti-Overlap. (Default: 16)" })
espAdvancedGroupbox:AddToggle("espSkeletonToggled", { Text = "Skeleton ESP", Default = false, Tooltip = "Draw lines between the character's bones. (Default: OFF)" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddToggle("espOffscreenToggled", { Text = "Off-Screen Markers", Default = false, Tooltip = "Show an edge marker pointing toward off-screen players. (Default: OFF)" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddToggle("espHalfRate", { Text = "Half-Rate ESP (perf)", Default = false, Tooltip = "Redraw ESP every other frame (~30fps) instead of every frame.\nRoughly halves ESP CPU cost; slight position lag. (Default: OFF)" })
espAdvancedGroupbox:AddToggle("espTracerToggled", { Text = "Tracer Lines", Default = false, Tooltip = "Show lines from screen center to players. (Default: OFF)" }):OnChanged(updatePlayers)
espAdvancedGroupbox:AddLabel("Tracer Color"):AddColorPicker("espTracerColor", { Title = "Tracer Color", Default = Color3.fromRGB(255, 0, 0) })
Options.espTracerColor:OnChanged(updatePlayers)

-- ESP Filters
espFilterGroupbox:AddSlider("espMaxDistance", { Text = "Max Distance", Min = 0, Max = 1000, Default = 1000, Rounding = 1, Tooltip = "Maximum distance for ESP (0 = unlimited). (Default: 1000)" }):OnChanged(updatePlayers)
espFilterGroupbox:AddToggle("espFOVFilter", { Text = "FOV Filter", Default = false, Tooltip = "Only ESP players within FOV. (Default: OFF)" }):OnChanged(updatePlayers)

-- ESP backend diagnostics (#1 render-verify + #2 live readout). The Drawing path is
-- decided at load; the override sets a getgenv flag for the NEXT execute, and the
-- Test button paints a native AND a GUI marker so you can SEE which one renders.
espFilterGroupbox:AddLabel("Backend: " .. (getgenv().FurryHBE_UsingNativeESP and "Native Drawing" or "GUI fallback"), true)
local espDiagLabel = espFilterGroupbox:AddLabel("ESP drawn: -")
local espDiagTick = 0
espFilterGroupbox:AddDropdown("espBackendOverride", { Text = "Force Backend", Values = { "Auto", "Native", "GUI" }, Default = "Auto", Multi = false, AllowNull = false, Tooltip = "Force the ESP draw backend on the NEXT execute (re-run to apply).\nNative = Drawing API, GUI = fallback frames. (Default: Auto)" }):OnChanged(function()
	local v = Options.espBackendOverride.Value
	getgenv().FurryHBE_ForceNativeESP = (v == "Native") or nil
	getgenv().FurryHBE_ForceGuiESP = (v == "GUI") or nil
	if v ~= "Auto" then Library:Notify("ESP backend -> " .. v .. ": re-execute to apply") end
end)
espFilterGroupbox:AddButton("Test ESP Backends (3s)", function()
	local cx, cy = Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2
	local made = {}
	pcall(function()
		if Drawing then
			local t = Drawing.new("Text"); t.Text = "NATIVE ESP OK"; t.Size = 28
			t.Color = Color3.fromRGB(0, 255, 0); t.Center = true; t.Outline = true
			t.Position = Vector2.new(cx, cy - 40); t.Visible = true
			made[#made + 1] = t
		end
	end)
	pcall(function()
		local sg = Instance.new("ScreenGui"); sg.Name = "FurryHBE_ESPTest"; sg.IgnoreGuiInset = true
		sg.DisplayOrder = 9e8; sg.Parent = getSafeGuiParent()
		local lb = Instance.new("TextLabel"); lb.AnchorPoint = Vector2.new(0.5, 0.5)
		lb.Position = UDim2.fromOffset(cx, cy + 40); lb.Size = UDim2.fromOffset(260, 32)
		lb.BackgroundTransparency = 1; lb.Text = "GUI ESP OK"; lb.TextColor3 = Color3.fromRGB(0, 200, 255)
		lb.TextStrokeTransparency = 0; lb.TextSize = 28; lb.Font = Enum.Font.SourceSansBold; lb.Parent = sg
		made[#made + 1] = sg
	end)
	Library:Notify("Center screen: GREEN = Native works, BLUE = GUI works")
	task.delay(3, function()
		for _, o in ipairs(made) do pcall(function() if o.Remove then o:Remove() elseif o.Destroy then o:Destroy() end end) end
	end)
end):AddToolTip("Paint a native + a GUI test marker so you can see which backend renders on your executor.")

-- Enemy / Ally team colours (red = enemy, green = ally), with configurable team lists.
local espTeamGroupbox = espTab:AddLeftGroupbox("Enemy / Ally Colors")
espTeamGroupbox:AddToggle("espTeamColors", { Text = "Enemy/Ally Colors", Default = false, Tooltip = "Colour ESP by relationship -- enemies red, allies green --\noverriding the normal ESP colour. (Default: OFF)" }):AddColorPicker("espEnemyColor", { Title = "Enemy", Default = Color3.fromRGB(255, 60, 60) }):AddColorPicker("espAllyColor", { Title = "Ally", Default = Color3.fromRGB(60, 255, 90) })
espTeamGroupbox:AddLabel("Neutral Color"):AddColorPicker("espNeutralColor", { Title = "Neutral", Default = Color3.fromRGB(235, 235, 235) })
espTeamGroupbox:AddToggle("espOwnTeamFriendly", { Text = "Own Team = Ally", Default = true, Tooltip = "Treat your own team as allies and everyone else as enemies\nwhen team info exists. (Default: ON)" })
espTeamGroupbox:AddDropdown("espFriendlyTeams", { Text = "Friendly Teams", Values = {}, Multi = true, AllowNull = true, Tooltip = "Teams always shown as allies (green)." })
espTeamGroupbox:AddDropdown("espEnemyTeams", { Text = "Enemy Teams", Values = {}, Multi = true, AllowNull = true, Tooltip = "Teams always shown as enemies (red)." })
local function refreshEspTeams()
	local names = {}
	pcall(function() for _, t in ipairs(game:GetService("Teams"):GetChildren()) do names[#names + 1] = t.Name end end)
	for _, key in ipairs({ "espFriendlyTeams", "espEnemyTeams" }) do
		if Options[key] then Options[key].Values = names; pcall(function() Options[key]:SetValues() end) end
	end
	return #names
end
espTeamGroupbox:AddButton("Refresh Teams", function()
	Library:Notify("Teams: " .. refreshEspTeams() .. " found")
end):AddToolTip("Populate the team lists from the game's Teams.")
pcall(refreshEspTeams)

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
-- F13a: type-to-filter for the player dropdowns. Filters the whitelist & priority
-- lists to server players whose name/display matches; already-selected names are
-- always kept visible. Empty = show everyone. (LinoriaLib has no native search, and
-- we can't monkey-patch it, so this drives the dropdown Values directly.)
whitelistGroupbox:AddInput("playerSearch", { Text = "Search Players", Default = "", Tooltip = "Type to filter the Whitelist & Priority player lists. Empty = all." })
local function applyPlayerSearch()
	local q = (Options.playerSearch and Options.playerSearch.Value or ""):lower()
	for _, key in ipairs({ "whitelistPlayerList", "priorityPlayerList" }) do
		local opt = Options[key]
		if opt then
			local names = {}
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= lPlayer and (q == "" or plr.Name:lower():find(q, 1, true) or plr.DisplayName:lower():find(q, 1, true)) then
					names[#names + 1] = plr.Name
				end
			end
			for _, n in ipairs(opt:GetActiveValues()) do if not table.find(names, n) then names[#names + 1] = n end end
			opt.Values = names
			pcall(function() opt:SetValues() end)
		end
	end
end
Options.playerSearch:OnChanged(applyPlayerSearch)
whitelistGroupbox:AddDropdown("whitelistPlayerList", { Text = "Whitelisted Players", AllowNull = true, Multi = true, Values = {}, Tooltip = "Players whitelisted from HBE. (Default: none)" }):OnChanged(updatePlayers)
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

priorityGroupbox:AddToggle("prioritySystemToggled", { Text = "Enable Priority System", Default = false, Tooltip = "Always extend/ESP priority players. (Default: OFF)" }):OnChanged(updatePlayers)
priorityGroupbox:AddDropdown("priorityPlayerList", { Text = "Priority Players", AllowNull = true, Multi = true, Values = {}, Tooltip = "High priority players. (Default: none)" }):OnChanged(updatePlayers)
priorityGroupbox:AddToggle("priorityFlash", { Text = "Flash Priority Targets", Default = true, Tooltip = "Rainbow-flash every ESP element (name, box, tracer,\nskeleton, chams, off-screen marker) of priority players\nso they stand out. (Default: ON)" })
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
	},
	-- Drilling: hopping in/out of cars (driver or passenger), close-range with the
	-- occasional far shot, engaging people in vehicles. Head-focused. Team is NOT a
	-- safe filter here (same-team players can be enemies) -- whitelist real friends.
	["Drilling"] = {
		extenderToggled = true,
		partSpecificSizing = true,     -- head-focused sizing
		extenderSize = 12,             -- base, used for HumanoidRootPart
		headSize = 12,                 -- head is your main hit area, kept moderate (not huge)
		torsoSize = 12,
		limbSize = 8,
		extenderPartList = { Head = true, HumanoidRootPart = true },  -- extend head + root
		extenderTransparency = 0.6,
		hitboxShape = "Cube",
		dynamicSizing = true,          -- scale down at range so far shots stay plausible
		dynamicScalingFactor = 0.7,
		maxDistance = 400,             -- close engagements out to fairly far
		seatDisableHBE = true,         -- no glitching when you hop in/out of a seat
		seatRadiusMode = false,
		ignoreOwnTeamToggled = false,  -- same-team can be enemies -- do NOT filter by team
		randomizationToggled = true,
		legitModeToggled = false,      -- land hits during active drilling, not crosshair-gated
	}
}

profilesGroupbox:AddDropdown("profileSelect", { Text = "Select Profile", AllowNull = false, Multi = false, Values = {"Aggressive", "Stealth", "Legit", "Drilling"}, Default = "Aggressive", Tooltip = "Select a configuration profile. (Default: Aggressive)" })
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
performanceGroupbox:AddSlider("updateRate", { Text = "Update Rate (Hz)", Min = 1, Max = 60, Default = 30, Rounding = 1, Tooltip = "How often to update hitboxes\n(higher = more responsive but more CPU). (Default: 30)" }):OnChanged(updatePlayers)
performanceGroupbox:AddToggle("perfAdaptive", { Text = "Low-FPS Adaptive Throttle", Default = false, Tooltip = "When FPS drops below the floor below, automatically do\nless work -- redraw ESP on fewer frames and skip far-away\nplayers -- to claw back frames. Eases off again once\nFPS recovers. (Default: OFF)" })
performanceGroupbox:AddSlider("perfFpsFloor", { Text = "FPS Floor", Min = 15, Max = 120, Default = 45, Rounding = 0, Tooltip = "Throttling kicks in when measured FPS falls below this;\nthe further below, the harder it throttles. (Default: 45)" })

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
performanceGroupbox:AddSlider("menuTransparency", { Text = "Menu Transparency", Min = 0, Max = 0.9, Default = 0, Rounding = 2, Tooltip = "See-through menu so it doesn't block your view.\nYou can still click everything. (Default: 0)" }):OnChanged(function()
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
		for plr, v in pairs(players) do
			-- Low-FPS throttle: skip players past the distance cap. (F9)
			if not (Bridge.Perf and Bridge.Perf.skipPlayer and Bridge.Perf.skipPlayer(plr)) then
				-- Direct pcall instead of task.spawn: Update() never yields, so spawning
				-- a fresh coroutine per player per frame was pure overhead. pcall still
				-- isolates a per-player error so one bad character can't stop the rest. (perf)
				pcall(function() v:Update() end)
			end
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
local espHalfFrame = false  -- toggled each frame when Half-Rate ESP is on (perf)
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
			-- Separate by at least the upper label's text height. A fixed 16px gap is
			-- smaller than a large name (size up to 36), so clumped names used to
			-- overlap into one unreadable blob -- looking like the name "disappeared"
			-- while the smaller team subscript below stayed legible. (B1)
			local needed = math.max(gap, (prev.size or 14) + 2)
			-- Only declutter labels that share roughly the same column.
			if math.abs(cur.x - prev.x) < 70 and (cur.y - prev.y) < needed then
				cur.y = prev.y + needed
			end
		end
		cur.label.Position = Vector2.new(cur.x, cur.y)
		if cur.team and cur.team.Visible then cur.team.Position = Vector2.new(cur.x, cur.y + cur.size) end
	end
end

-- Render step for ESP (with failsafe)
RunService:BindToRenderStep("furryWalls", Enum.RenderPriority.Camera.Value - 1, function()
	if not getgenv().FurryHBELoaded then return end
	-- Low-FPS throttle: skip some ESP redraws when frames are scarce. (F9)
	if Bridge.Perf and Bridge.Perf.gateESP and Bridge.Perf.gateESP() then return end
	-- Half-Rate ESP (perf): render every other frame on demand.
	if Toggles.espHalfRate and Toggles.espHalfRate.Value then
		espHalfFrame = not espHalfFrame
		if espHalfFrame then return end
	end
	Camera = Workspace.CurrentCamera
	pcall(updateFOVCircle)
	if #espNameSlots > 0 then table.clear(espNameSlots) end
	for _, v in pairs(players) do
		-- Direct pcall, not task.spawn: UpdateESP never yields, so a coroutine per
		-- player per frame was wasted allocation; pcall still isolates errors. This
		-- also guarantees every espNameSlot is filled before resolveEspOverlap runs. (perf)
		local success, err = pcall(function() v:UpdateESP() end)
		if not success then logError("UpdateESP", err, "espNameToggled") end
	end
	pcall(resolveEspOverlap)
	-- #2 live ESP readout: count how many name labels are actually visible this frame
	-- (throttled). 0 visible while players are nearby = the backend isn't painting.
	if espDiagLabel and (tick() - (espDiagTick or 0) > 0.5) then
		espDiagTick = tick()
		local drawn, tracked = 0, 0
		for _, v in pairs(players) do
			tracked = tracked + 1
			if v.nameEsp and v.nameEsp.Visible then drawn = drawn + 1 end
		end
		pcall(function() espDiagLabel:SetText(("ESP drawn: %d / %d tracked"):format(drawn, tracked)) end)
	end
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

	-- Heuristic detection-risk estimate from current settings.
	pcall(function()
		if not riskLabel then return end
		local r = 0
		if Options.extenderSize and Options.extenderSize.Value > 30 then r = r + 2 end
		if Toggles.collisionsToggled and Toggles.collisionsToggled.Value then r = r + 2 end
		if not (Toggles.humanizationToggled and Toggles.humanizationToggled.Value) then r = r + 1 end
		if Toggles.randomizationToggled and Toggles.randomizationToggled.Value and not (Toggles.smartJitter and Toggles.smartJitter.Value) then r = r + 1 end
		if Options.updateRate and Options.updateRate.Value > 30 then r = r + 1 end
		if not (Options.maxPlausibleMult and Options.maxPlausibleMult.Value > 0) then r = r + 1 end
		-- Phantom Recon (Tier 4): a detected anti-cheat raises the risk floor.
		local b = getgenv().FurryHBE
		local acTag = ""
		if b and b.DeepScan and b.DeepScan.acActive then r = r + 3; acTag = " [AC detected]" end
		riskLabel:SetText("Detection risk: " .. (r <= 2 and "Low" or (r <= 4 and "Medium" or "High")) .. acTag)
	end)
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

-- Enemy/Ally ESP colour: explicit Friendly/Enemy team lists win; otherwise (if
-- "Own Team = Ally" is on and team info exists) your team is green and the rest red;
-- else neutral. Returns a Color3 for ESP to override the default with.
local function relationshipColor(player)
	local enemyC   = (Options.espEnemyColor and Options.espEnemyColor.Value) or Color3.fromRGB(255, 60, 60)
	local allyC    = (Options.espAllyColor and Options.espAllyColor.Value) or Color3.fromRGB(60, 255, 90)
	local neutralC = (Options.espNeutralColor and Options.espNeutralColor.Value) or Color3.fromRGB(255, 255, 255)
	local teamName = player.Team and player.Team.Name or nil
	if teamName and Options.espFriendlyTeams and table.find(Options.espFriendlyTeams:GetActiveValues(), teamName) then return allyC end
	if teamName and Options.espEnemyTeams and table.find(Options.espEnemyTeams:GetActiveValues(), teamName) then return enemyC end
	if Toggles.espOwnTeamFriendly and Toggles.espOwnTeamFriendly.Value then
		local ok, same = pcall(function()
			if lPlayer.Team ~= nil or player.Team ~= nil then return lPlayer.Team == player.Team end
			return lPlayer.TeamColor == player.TeamColor
		end)
		if ok and same then return allyC end
		if lPlayer.Team ~= nil or player.Team ~= nil then return enemyC end
	end
	return neutralC
end

-- Expose core helpers on the Bridge so external (loadstring'd) plugins -- which can
-- only see globals, not these locals -- can reuse them.
Bridge.getSafeGuiParent = getSafeGuiParent
Bridge.relationshipColor = relationshipColor

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
		local sittingNow = humanoid ~= nil and humanoid.Sit == true
		if not sittingNow then return false end
		-- "Ignore Sitting Players" off => seated players extend normally.
		if not Toggles.extenderSitCheck.Value then return false end
		-- Sitting grace after exit: for a short window after YOU leave a seat,
		-- SUSPEND "Ignore Sitting Players" so you CAN hit players who are still seated
		-- (e.g. you hop out of your car to shoot the people still sitting in theirs).
		-- After the window, ignore-sitting resumes. Whitelisted players stay ignored
		-- via isIgnored(), so the whitelist is still respected. (F7)
		if Toggles.seatExitDelayEnabled and Toggles.seatExitDelayEnabled.Value then
			local t = Bridge.lastSeatExitTime
			local delay = (Options.seatExitDelay and Options.seatExitDelay.Value) or 6
			if t and (tick() - t) < delay then return false end
		end
		return true
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
				if property == "Size" then
					-- Extension only ever GROWS a part, so a LARGER size reported here is
					-- our own extension leaking past the guard above (deferred .Changed
					-- lag with smooth/dynamic/random sizing). Saving that as the "default"
					-- is exactly what left heads/parts stuck big after HBE or Disable-
					-- While-Seated turned off. Only accept a NOT-larger size as a new real
					-- default; never let the stored default grow. (restore-bug fix)
					local cur, def = part.Size, properties.Size
					if cur.X <= def.X + 0.05 and cur.Y <= def.Y + 0.05 and cur.Z <= def.Z + 0.05 then
						properties.Size = cur
					end
				elseif properties[property] ~= part[property] then
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
			local d = defaultProperties[part]
			-- Drop the legacy SelectionBox outline from older builds if present.
			local oldSel = part:FindFirstChild("FurryHBE_Outline")
			if oldSel then oldSel:Destroy() end

			if Toggles.outlineMode and Toggles.outlineMode.Value then
				-- Outline Only (reworked, F6): leave the REAL part in its original visible
				-- state and move the enlarged hit area onto a SEPARATE invisible part
				-- welded to it, outlined by a Highlight -- a clean outline shaped like the
				-- expanded part, instead of hiding the body behind a big transparent box.
				part.Size = d.Size
				part.Transparency = d.Transparency
				part.Massless = d.Massless
				part.CanCollide = d.CanCollide
				currentSizes[part] = d.Size
				if part.Name == "Head" then
					local face = part:FindFirstChild("face")
					if face then face.Transparency = d.Transparency end
				end

				local proxy = part:FindFirstChild("FurryHBE_HitProxy")
				if not proxy then
					proxy = Instance.new("Part")
					proxy.Name = "FurryHBE_HitProxy"
					proxy.Transparency = 1
					proxy.Massless = true
					proxy.CanCollide = false
					proxy.CanTouch = true
					proxy.CanQuery = true
					proxy.Anchored = false
					proxy.Size = targetSize
					proxy.CFrame = part.CFrame
					proxy.Parent = part
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = part
					weld.Part1 = proxy
					weld.Parent = proxy
					local hl = Instance.new("Highlight")
					hl.Name = "FurryHBE_OutlineHL"
					hl.Adornee = proxy
					hl.FillTransparency = 1
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					hl.Parent = proxy
				end
				proxy.Size = targetSize
				proxy.CanCollide = Toggles.collisionsToggled.Value
				local hl = proxy:FindFirstChild("FurryHBE_OutlineHL")
				if hl then
					hl.OutlineColor = (Options.outlineColor and Options.outlineColor.Value) or Color3.fromRGB(255, 0, 0)
					hl.OutlineTransparency = (Options.outlineTransparency and Options.outlineTransparency.Value) or 0
					hl.FillTransparency = 1
				end
			else
				-- Normal extend: drop any outline proxy; the real part stays enlarged
				-- (sized/Massless/CanCollide already applied above).
				local proxy = part:FindFirstChild("FurryHBE_HitProxy")
				if proxy then proxy:Destroy() end
				part.Transparency = extTransparency
				if part.Name == "Head" then
					local face = part:FindFirstChild("face")
					if face then face.Transparency = extTransparency end
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
			local px = part:FindFirstChild("FurryHBE_HitProxy")
			if px then px:Destroy() end

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
					local px = v:FindFirstChild("FurryHBE_HitProxy")
					if px then px:Destroy() end
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
		-- Enemy/Ally team colour (red enemy, green ally). flashCol still wins for emphasis.
		local relCol = nil
		if Toggles.espTeamColors and Toggles.espTeamColors.Value then relCol = relationshipColor(player) end
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
					
					if Toggles.espNameUseTeamColor.Value and player.Team then
						local ok, tc = pcall(function() return player.TeamColor.Color end)
						nameEsp.Color = ok and tc or Options.espNameColor1.Value
					else
						nameEsp.Color = Options.espNameColor1.Value
					end
					nameEsp.Color = flashCol or relCol or nameEsp.Color
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
						-- "cur/max" format (e.g. 33/100) like the reference ESP.
						healthText.Text = math.floor(humanoid.Health) .. "/" .. math.floor(humanoid.MaxHealth)
						-- Enemy/Ally colour when team-colours on, else the HP gradient.
						healthText.Color = relCol or Color3.fromRGB(math.floor(255 * (1 - pct)), math.floor(255 * pct), 0)
						healthText.OutlineColor = Color3.fromRGB(0, 0, 0)
						healthText.Size = 13
						healthText.Center = true
						-- Centered just above the name, matching the reference layout.
						healthText.Position = Vector2.new(pos.X, pos.Y - ((Options.espNameSize and Options.espNameSize.Value or 14) + 6))
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
					if rootPart then
						local rootPos = rootPart.Position
						-- Root-relative + FIXED world offsets only: never reference the Head,
						-- whose centre shifts when the hitbox extender enlarges it and used to
						-- inflate the box. This keeps the 2D box a constant person-size
						-- regardless of hitbox size. (B3)
						local topPos = rootPos + Vector3.new(0, 2.5, 0)
						local botPos = rootPos - Vector3.new(0, 3, 0)
						local topV = WorldToViewportPoint(Camera, topPos)
						local botV = WorldToViewportPoint(Camera, botPos)
						local scale = (Options.espBoxScale and Options.espBoxScale.Value) or 0.85
						local height = math.abs(topV.Y - botV.Y) * scale
						local width = height * 0.5
						boxEsp.Size = Vector2.new(width, height)
						boxEsp.Position = Vector2.new(pos.X - width / 2, pos.Y - height / 2)
						boxEsp.Color = flashCol or relCol or Options.espNameColor1.Value
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
					tracer.Color = flashCol or relCol or Options.espTracerColor.Value
					tracer.Thickness = thick
					pcall(function() tracer.Transparency = fade end)
					tracer.Visible = true
				else
					tracer.Visible = false
				end

				-- Skeleton ESP (connects bones; missing parts are skipped)
				if Toggles.espSkeletonToggled.Value then
					local idx = 0
					local col = flashCol or ((Toggles.espNameUseTeamColor.Value and player.Team and pcall(function() return player.TeamColor.Color end) and player.TeamColor.Color) or Options.espNameColor1.Value)
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
					offscreenMarker.Color = flashCol or ((Toggles.espNameUseTeamColor.Value and player.Team and pcall(function() return player.TeamColor.Color end) and player.TeamColor.Color) or Options.espNameColor1.Value)
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
			if Toggles.espHighlightUseTeamColor.Value and player.Team then
				local ok, tc = pcall(function() return player.TeamColor.Color end)
				local c = ok and tc or Options.espHighlightColor1.Value
				chams.FillColor = c
				chams.OutlineColor = c
			else
				chams.FillColor = Options.espHighlightColor1.Value
				chams.OutlineColor = Options.espHighlightColor2.Value
			end
			-- Enemy/Ally colours override the chams fill+outline (red enemy / green ally).
			if relCol then chams.FillColor = relCol; chams.OutlineColor = relCol end
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
		safeRemoveDrawing(nameEsp)
		safeRemoveDrawing(teamEsp)
		safeRemoveDrawing(healthBar)
		safeRemoveDrawing(healthText)
		safeRemoveDrawing(offscreenMarker)
		safeRemoveDrawing(boxEsp)
		safeRemoveDrawing(tracer)
		for _, ln in ipairs(skeletonLines) do safeRemoveDrawing(ln) end
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
		-- If no Humanoid ever appeared within the wait (custom rig without one, or a
		-- slow/aborted spawn) bail cleanly -- the loop below indexes `humanoid`, and a
		-- nil index here used to throw inside the (un-pcall'd) CharacterAdded handler.
		-- The Heartbeat update loop still self-heals the character via Update().
		if not humanoid then return false end
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

-- Team is a Player PROPERTY, not an attribute. GetAttributeChangedSignal("Team")
-- never fired, so your own team switches didn't refresh HBE/ESP (every other Team
-- listener in this script correctly uses GetPropertyChangedSignal).
lPlayer:GetPropertyChangedSignal("Team"):Connect(function()
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

-- ===== [F7] Sitting grace-after-exit tracker =====
-- Record the moment YOU leave a seat so the HBE eligibility check (isSitting) can
-- keep still-seated players un-extended for a short grace window (set in Ignores).
pcall(function()
	local wasSeated = false
	RunService.Heartbeat:Connect(function()
		local seated = false
		pcall(function() seated = isLocalSeated() end)
		if wasSeated and not seated then Bridge.lastSeatExitTime = tick() end
		wasSeated = seated
	end)
end)

-- ===== [F9] Low-FPS adaptive throttle =====
-- Measures FPS and, when it drops below the floor, tells the ESP/HBE hot loops to
-- do less work via cheap gate functions (Bridge.Perf). If this block fails to load
-- the gates are simply absent and both loops behave exactly as before.
pcall(function()
	Bridge.Perf = Bridge.Perf or {}
	local P = Bridge.Perf
	P.active, P.stride, P.distCap, P.fps = false, 1, nil, 60

	local fps = 60
	RunService.RenderStepped:Connect(function(dt)
		if dt and dt > 0 then fps = fps * 0.9 + (1 / dt) * 0.1 end
		P.fps = fps
		if not (Toggles.perfAdaptive and Toggles.perfAdaptive.Value) then
			P.active, P.stride, P.distCap = false, 1, nil
			return
		end
		local floor = (Options.perfFpsFloor and Options.perfFpsFloor.Value) or 45
		if fps >= floor then
			P.active, P.stride, P.distCap = false, 1, nil
		else
			P.active = true
			local deficit = math.clamp((floor - fps) / math.max(1, floor), 0, 1)
			P.stride = math.clamp(1 + math.floor(deficit * 4 + 0.5), 1, 4)  -- redraw ESP every 1st-4th frame
			P.distCap = math.clamp(400 - deficit * 320, 80, 400)            -- skip players past 80-400 studs
		end
	end)

	-- ESP gate: true => skip this frame's 2D ESP redraw.
	local f = 0
	P.gateESP = function()
		if not P.active or P.stride <= 1 then return false end
		f = (f + 1) % 1000000
		return (f % P.stride) ~= 0
	end

	-- HBE gate: true => this player is far enough to skip this pass.
	P.skipPlayer = function(plr)
		if not P.active or not P.distCap then return false end
		local char = plr and plr.Character
		if not char then return false end
		return getDistanceToPlayer(char) > P.distCap
	end
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
		-- ESP render path readout (helps diagnose Drawing issues per executor).
		Library:Notify("ESP draw: " .. (getgenv().FurryHBE_UsingNativeESP and "Native Drawing" or "GUI fallback"))
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

-- ----- Miscellaneous tab : Vehicle + Combat (Tool Expander) -----------------
-- Formerly Miscellaneousforgot.lua. Fixes from the original: forward-reference
-- bugs (applyVehicleSpeed / refreshVehicleDetection / applyToolExpansion were
-- called by buttons before being declared), the non-existent infoGroup:SetLabel
-- (now a stored label:SetText), label:AddDropdown (labels can't host dropdowns),
-- seat detection (now uses Humanoid.SeatPart), BodyGyro parented to a Model
-- instead of a BasePart, and a multi-return bug in the upright math. Cleanup is
-- registered through the Bridge and all connections are tracked + disconnected.
pcall(function()
	local miscTab = mainWindow:AddTab("Vehicle/Misc")
	Bridge.MiscTab = miscTab  -- still exposed so future add-ons can attach here too
	local lPlayer = Players.LocalPlayer

	local conns = {}
	local function track(c) table.insert(conns, c); return c end

	-- 4 left + 4 right groupboxes, all under the single Miscellaneous tab.
	local speedGroup     = miscTab:AddLeftGroupbox("Vehicle: Speed")
	local detectGroup    = miscTab:AddLeftGroupbox("Vehicle: Detection")
	local stabilGroup    = miscTab:AddLeftGroupbox("Vehicle: Stability")
	local expanderGroup  = miscTab:AddLeftGroupbox("Combat: Tool Expander")
	local infoGroup      = miscTab:AddRightGroupbox("Vehicle: Info")
	local weaponListGroup= miscTab:AddRightGroupbox("Combat: Weapon List")
	local scannerGroup   = miscTab:AddRightGroupbox("Combat: Tool Scanner")
	local settingsGroupC = miscTab:AddRightGroupbox("Combat: Settings")

	-- Forward declarations: buttons below are created before these are defined.
	local refreshVehicleDetection, applyToolExpansion, detectSpeedSystem

	-- Manual vehicle pick (fallback if auto seat-detection fails).
	local manualVehicle = nil       -- the part you clicked (primary fallback)
	local manualVehicleModel = nil  -- the whole car that part belongs to (F4)

	-- Reject obvious world/map geometry so a hold-pick can't register the ground. (F4)
	local function looksLikeGround(part)
		if not part then return true end
		if part == Workspace.Terrain then return true end
		local n = part.Name:lower()
		if n:find("baseplate") or n:find("terrain") or n:find("ground") or n:find("floor") or n:find("map") then return true end
		if part.Anchored and part.Size.X > 150 and part.Size.Z > 150 then return true end
		return false
	end

	-- ===== Vehicle UI =====
	speedGroup:AddToggle("vehicleAssist", { Text = "Vehicle Assist", Default = false, Tooltip = "Master toggle. Enables the speed jolt + limiter. The\nauto-stabilizer (keep-upright + grip) is its OWN toggle\nunder Vehicle: Stability, so you can jolt/drive with no\nassist fighting the car. (Default: OFF)" })
	speedGroup:AddLabel("Speed Jolt Key"):AddKeyPicker("vehicleJoltKey", { Default = "G", NoUI = true, Text = "Speed Jolt" })
	speedGroup:AddSlider("vehicleJoltPower", { Text = "Jolt Power", Min = 10, Max = 500, Default = 120, Rounding = 1, Tooltip = "Burst of speed per key press. Studs/sec normally, or a %\nof the car's own top speed if 'Jolt in car's units' is on.\n(Default: 120)" })
	speedGroup:AddToggle("vehicleJoltRelative", { Text = "Jolt in car's units", Default = false, Tooltip = "Treat Jolt Power as a % of the car's OWN top speed\n(auto-detected from its VehicleSeat) so a jolt feels the\nsame on slow and fast cars. (Default: OFF)" })
	speedGroup:AddToggle("vehicleTripleTap", { Text = "Triple-tap key = toggle Assist", Default = false, Tooltip = "Tap the Jolt key 3x quickly to flip Vehicle Assist on/off.\nThose 3 taps won't jolt. (Default: OFF)" })
	speedGroup:AddToggle("vehicleAccelerator", { Text = "Speed Accelerator", Default = false, Tooltip = "While you're driving, smoothly builds your speed up to the\nTop Speed below -- a natural power boost that keeps your\nsteering and doesn't shock the suspension like the jolt. (Default: OFF)" })
	speedGroup:AddSlider("vehicleTopSpeed", { Text = "Top Speed (studs/s)", Min = 20, Max = 500, Default = 120, Rounding = 0, Tooltip = "Target speed the accelerator ramps you up to. (Default: 120)" })
	speedGroup:AddSlider("vehicleAccelRate", { Text = "Acceleration", Min = 10, Max = 400, Default = 80, Rounding = 0, Tooltip = "How quickly the accelerator builds speed (studs/sec^2).\nLower = gentler, higher = snappier. (Default: 80)" })

	detectGroup:AddDropdown("vehicleDetectionMode", { Text = "Detection Mode", Values = { "Auto", "A-Chassis", "Basic Seat", "Custom Script" }, Default = "Auto", Multi = false, AllowNull = false, Tooltip = "Leave on Auto -- it detects A-Chassis / VehicleSeat /\ncustom cars for you and shows the result in Vehicle: Info.\nThe other options only force the label if Auto guesses\nwrong; they don't change how assist behaves. (Default: Auto)" })
	detectGroup:AddButton("Refresh Detection", function()
		if refreshVehicleDetection then pcall(refreshVehicleDetection) end
	end):AddToolTip("Rescan your character for the seat/vehicle you're in")
	detectGroup:AddToggle("vehicleManualMode", { Text = "Manual Vehicle", Default = false, Tooltip = "Ignore auto seat-detection and use the vehicle\nyou pick below (use this if auto fails). (Default: OFF)" })
	detectGroup:AddButton("Pick Vehicle (hold-click)", function()
		Bridge:StartHoldPick({
			color = Color3.fromRGB(0, 170, 255),
			filter = function(part) return not looksLikeGround(part) end,
			onPick = function(part)
				if looksLikeGround(part) then Library:Notify("That looks like ground/map, not a vehicle"); return end
				-- Register the WHOLE car: walk up to the top-most Model under Workspace,
				-- so clicking any single part grabs the entire vehicle. (F4)
				local model = part:FindFirstAncestorWhichIsA("Model")
				local top = model
				while top and top.Parent and top.Parent:IsA("Model") do top = top.Parent end
				manualVehicleModel = top or model
				manualVehicle = part
				if not Toggles.vehicleManualMode.Value then Toggles.vehicleManualMode:SetValue(true) end
				if refreshVehicleDetection then pcall(refreshVehicleDetection) end
				Library:Notify("Manual vehicle: " .. ((manualVehicleModel and manualVehicleModel.Name) or part.Name))
			end,
		})
	end):AddToolTip("Aim at ANY part of a car and HOLD left-click until the ring fills -- it registers the whole vehicle (ground/map parts are rejected). Right-click cancels.")
	detectGroup:AddButton("Clear Manual Vehicle", function()
		manualVehicle = nil; manualVehicleModel = nil
		if refreshVehicleDetection then pcall(refreshVehicleDetection) end
		Library:Notify("Manual vehicle cleared")
	end):AddToolTip("Forget the manually picked vehicle")

	stabilGroup:AddToggle("vehicleStabilizer", { Text = "Auto-Stabilizer", Default = true, Tooltip = "Gentle anti-rollover: only nudges the car upright if it tips\npast ~35 degrees, with light torque -- so it never fights your\nsteering or makes the car float/skate. Turn OFF for fully raw\ndriving. (Default: ON)" })
	stabilGroup:AddToggle("vehicleSpeedLimiter", { Text = "Speed Limiter", Default = false, Tooltip = "ON = caps your speed at the limit below even if you keep\njolting. OFF = jolts uncapped (hit the jets). (Default: OFF)" })
	stabilGroup:AddSlider("vehicleSpeedCap", { Text = "Speed Limit (studs/s)", Min = 20, Max = 500, Default = 120, Rounding = 1, Tooltip = "Max horizontal speed while the limiter is on. (Default: 120)" })
	stabilGroup:AddButton("Match Car's Top Speed", function()
		if refreshVehicleDetection then pcall(refreshVehicleDetection) end
		if detectSpeedSystem then
			local sys = detectSpeedSystem()
			if sys and sys.maxSpeed and sys.maxSpeed > 0 then
				Options.vehicleSpeedCap:SetValue(math.clamp(math.floor(sys.maxSpeed), 20, 500))
				Library:Notify("Speed limit set to this car's top speed (" .. math.floor(sys.maxSpeed) .. ")")
			else
				Library:Notify("This car has no readable top speed (it's physics-driven)")
			end
		end
	end):AddToolTip("Set the limiter to the car's own detected top speed, so the cap is in the car's units. (F2)")

	local vehicleInfoLabel = infoGroup:AddLabel("Current Vehicle: None")

	-- ===== Combat UI =====
	weaponListGroup:AddDropdown("expandedWeapons", { Text = "Active Weapons", Values = {}, Multi = true, AllowNull = true, Default = {}, Tooltip = "Tools whose hitbox will be expanded. (Default: none)" })

	expanderGroup:AddToggle("toolExpanderEnabled", { Text = "Enable Tool Expander", Default = false, Tooltip = "Master toggle for tool hitbox expansion. (Default: OFF)" })
	expanderGroup:AddSlider("toolExpandSize", { Text = "Expansion Size", Min = 0.5, Max = 10, Default = 2, Rounding = 1, Tooltip = "Multiplier applied to tool part sizes. (Default: 2)" })
	expanderGroup:AddToggle("toolNonCollide", { Text = "Non-Collidable Hitbox", Default = true, Tooltip = "MELEE-COLLIDE: the enlarged hitbox is non-collidable (won't\nshove you/objects or snag on the world) but still keeps CanTouch\non, so the game's own touch-damage still lands. (Default: ON)" }):OnChanged(function()
		-- Re-apply so the change takes effect immediately on already-expanded tools.
		-- expandTool applies the on/off collision state both ways, so this is enough.
		if applyToolExpansion then pcall(applyToolExpansion) end
	end)
	expanderGroup:AddDropdown("toolPartFilter", { Text = "Parts to Expand", Values = { "Handle", "Blade", "HitBox", "Tip", "All" }, Default = { "Handle", "Blade" }, Multi = true, AllowNull = true, Tooltip = "Which tool parts get expanded (name match). (Default: Handle, Blade)" })

	scannerGroup:AddButton("Scan Tools", function()
		-- Pure read-only scan: collects tool NAMES only, never touches a tool (no
		-- resize/equip), and MERGES into the existing list instead of replacing it so
		-- a rescan can't wipe your current weapon selection. Wrapped in pcall so a bad
		-- container can't error out. (B4)
		pcall(function()
			local seen, tools = {}, {}
			for _, n in ipairs(Options.expandedWeapons.Values or {}) do
				if type(n) == "string" and not seen[n] then seen[n] = true; tools[#tools + 1] = n end
			end
			local function scan(container)
				if not container then return end
				for _, t in ipairs(container:GetChildren()) do
					if t:IsA("Tool") and t.Name ~= "" and not seen[t.Name] then
						seen[t.Name] = true; tools[#tools + 1] = t.Name
					end
				end
			end
			scan(lPlayer:FindFirstChild("Backpack"))
			scan(lPlayer.Character)
			Options.expandedWeapons.Values = tools
			Options.expandedWeapons:SetValues()
			Library:Notify("Found " .. #tools .. " tool(s) -- scan only, nothing modified")
		end)
	end):AddToolTip("Read-only: lists tool names from your backpack/character and merges them into Active Weapons. Never resizes or equips anything.")

	settingsGroupC:AddToggle("toolAutoApply", { Text = "Auto-Apply on Equip", Default = true, Tooltip = "Expand a tool automatically when equipped if it's in the active list. (Default: ON)" })
	settingsGroupC:AddToggle("toolAutoScanEquip", { Text = "Auto-Add on Equip", Default = false, Tooltip = "When you equip a tool, automatically add it to the Active\nWeapons list AND expand it (if the expander is on) -- no\nmanual scanning needed. (Default: OFF)" })
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
			-- Prefer the whole picked car: hand back its primary part so assist acts on
			-- the real chassis, not the single part you happened to click. (F4)
			if manualVehicleModel and manualVehicleModel.Parent then
				return manualVehicleModel.PrimaryPart
					or (manualVehicle and manualVehicle.Parent and manualVehicle)
					or manualVehicleModel:FindFirstChildWhichIsA("BasePart")
			end
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

	-- Best-effort read of the car's OWN speed system so jolt/limiter can work in its
	-- units: a VehicleSeat exposes MaxSpeed/Throttle; A-Chassis/custom cars are
	-- physics-driven so we just report that. (F2/F5)
	detectSpeedSystem = function()
		local root = vehicleRootAndPrimary()
		if not root then return nil end
		local seat = (currentVehicle and currentVehicle:IsA("VehicleSeat") and currentVehicle)
			or root:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat then
			return { kind = "VehicleSeat", maxSpeed = seat.MaxSpeed, throttle = seat.Throttle, seat = seat }
		end
		if root:FindFirstChild("A-Chassis") or root:FindFirstChild("Chassis") then
			return { kind = "A-Chassis" }
		end
		return { kind = "Physics" }
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

	-- Direction the car is actually travelling: follow horizontal velocity when moving
	-- (so boosts always push the way you DRIVE, never a fixed axis -- the old jolt used
	-- LookVector which threw the car off to one side), else fall back to chassis facing.
	local function drivingForward(primary, vel)
		local horiz = Vector3.new(vel.X, 0, vel.Z)
		if horiz.Magnitude > 4 then return horiz.Unit end
		local f = primary.CFrame.LookVector
		f = Vector3.new(f.X, 0, f.Z)
		if f.Magnitude < 0.05 then return nil end
		return f.Unit
	end

	-- One Heartbeat: gentle anti-rollover stabilizer + smooth accelerator + limiter.
	local lastInfoRefresh = 0
	local function assistStep(dt)
		if not Toggles.vehicleAssist.Value then clearGyro(); return end
		local _, primary = ensureVehicle()
		if not primary then clearGyro(); return end
		dt = dt or 1/60

		-- Keep the Info readout current while you're driving (throttled). (F5)
		if tick() - lastInfoRefresh > 0.5 then
			lastInfoRefresh = tick()
			if refreshVehicleDetection then pcall(refreshVehicleDetection) end
		end

		local vel = primary.AssemblyLinearVelocity
		local cf = primary.CFrame

		-- ===== Stabilizer: GENTLE anti-rollover ONLY =====
		-- Only nudges the car upright when it tips past a threshold, with light torque,
		-- so normal driving/leaning/steering is never fought. No velocity rewriting, so
		-- it can't make the car float or skate (the old grip+stiff-gyro problem).
		if (Toggles.vehicleStabilizer == nil) or Toggles.vehicleStabilizer.Value then
			local up = cf.UpVector
			local tiltDeg = math.deg(math.acos(math.clamp(up:Dot(Vector3.new(0, 1, 0)), -1, 1)))
			local gyro = primary:FindFirstChild("FurryHBE_StabGyro")
			if tiltDeg > 35 then
				if not gyro then
					gyro = Instance.new("BodyGyro")
					gyro.Name = "FurryHBE_StabGyro"
					gyro.Parent = primary
				end
				gyro.P = 2200          -- light: a nudge, not a clamp
				gyro.D = 500
				gyro.MaxTorque = Vector3.new(9000, 0, 9000)
				local _, yaw = cf:ToEulerAnglesYXZ()
				gyro.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, yaw, 0)
			elseif gyro then
				gyro:Destroy()        -- upright enough: stop fighting entirely
			end
		else
			local g = primary:FindFirstChild("FurryHBE_StabGyro")
			if g then g:Destroy() end
		end

		-- ===== Accelerator: smooth ramp to Top Speed =====
		-- Adjusts only the FORWARD component of velocity, gradually, and ONLY while you
		-- are already driving -- so it feels like natural power, keeps your steering, and
		-- never shocks the suspension or auto-creeps when parked.
		if Toggles.vehicleAccelerator and Toggles.vehicleAccelerator.Value then
			local fwd = drivingForward(primary, vel)
			local horizSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if fwd and horizSpeed > 4 then
				local top = (Options.vehicleTopSpeed and Options.vehicleTopSpeed.Value) or 120
				local fSpeed = vel:Dot(fwd)
				if fSpeed >= 0 and fSpeed < top then
					local rate = (Options.vehicleAccelRate and Options.vehicleAccelRate.Value) or 80
					local newF = math.min(top, fSpeed + rate * dt)
					primary.AssemblyLinearVelocity = vel + fwd * (newF - fSpeed)
					vel = primary.AssemblyLinearVelocity
				end
			end
		end

		-- ===== Speed limiter (independent of stabilizer) =====
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
		-- Works whenever the master toggle is on -- the auto-stabilizer is NOT required. (F2)
		if not Toggles.vehicleAssist.Value then return end
		local _, primary = ensureVehicle()
		if not primary then return end
		local power = Options.vehicleJoltPower.Value
		-- "In car's units" mode: Jolt Power is a % of the car's auto-detected top
		-- speed, so one tap feels consistent across slow and fast vehicles. (F2)
		if Toggles.vehicleJoltRelative and Toggles.vehicleJoltRelative.Value and detectSpeedSystem then
			local sys = detectSpeedSystem()
			if sys and sys.maxSpeed and sys.maxSpeed > 0 then
				power = sys.maxSpeed * (Options.vehicleJoltPower.Value / 100)
			end
		end
		-- Push along the way you're actually DRIVING (velocity-aligned when moving, else
		-- chassis facing) so the jolt never throws the car off to a fixed side. (fix)
		local vel = primary.AssemblyLinearVelocity
		local fwd = drivingForward(primary, vel) or primary.CFrame.LookVector
		local newVel = vel + fwd * power
		-- Anti-fling: a single jolt can never produce an absurd velocity.
		if newVel.Magnitude > 2000 then newVel = newVel.Unit * 2000 end
		primary.AssemblyLinearVelocity = newVel
	end

	refreshVehicleDetection = function()
		currentVehicle = detectVehicle()
		if not currentVehicle then
			vehicleInfoLabel:SetText("Current Vehicle: None")
			return
		end
		local root = currentVehicle:FindFirstAncestorWhichIsA("Model") or currentVehicle
		local _, primary = vehicleRootAndPrimary()
		local vtype = identifyVehicleType(currentVehicle)
		local src = (Toggles.vehicleManualMode and Toggles.vehicleManualMode.Value) and "manual" or "auto"
		local sys = detectSpeedSystem()
		local speedTxt = "physics"
		if sys then
			if sys.kind == "VehicleSeat" then speedTxt = "Seat top " .. math.floor(sys.maxSpeed or 0)
			else speedTxt = sys.kind end
		end
		vehicleInfoLabel:SetText(string.format("Vehicle: %s | %s (%s) | %s | part: %s",
			root.Name or "?", vtype, src, speedTxt, primary and primary.Name or "?"))
	end

	-- Triple-tap detection: 3 quick taps of the jolt key flip Vehicle Assist when the
	-- option is on; otherwise every press just jolts. (F3)
	local joltTapTimes = {}
	Options.vehicleJoltKey:OnClick(function()
		if Toggles.vehicleTripleTap and Toggles.vehicleTripleTap.Value then
			local now = tick()
			joltTapTimes[#joltTapTimes + 1] = now
			while #joltTapTimes > 0 and now - joltTapTimes[1] > 0.6 do table.remove(joltTapTimes, 1) end
			if #joltTapTimes >= 3 then
				joltTapTimes = {}
				pcall(function()
					Toggles.vehicleAssist:SetValue(not Toggles.vehicleAssist.Value)
					Library:Notify("Vehicle Assist " .. (Toggles.vehicleAssist.Value and "ON" or "OFF") .. " (triple-tap)")
				end)
				return
			end
		end
		pcall(speedJolt)
	end)

	Toggles.vehicleAssist:OnChanged(function()
		if Toggles.vehicleAssist.Value then
			refreshVehicleDetection()
			if not assistConn then assistConn = RunService.Heartbeat:Connect(function(dt) pcall(function() assistStep(dt) end) end) end
		else
			if assistConn then assistConn:Disconnect(); assistConn = nil end
			removeVehiclePhysics()
		end
	end)

	-- ===== Tool expander logic =====
	-- originalToolSizes[tool][part] now stores a RECORD { Size, CanCollide, CanTouch,
	-- Massless } captured before we touch the part, so restore returns it exactly.
	local originalToolSizes = setmetatable({}, { __mode = "k" })

	-- Restore one tool's saved parts to their captured originals (size + the collision/
	-- touch/mass props the MELEE-COLLIDE option changes). Used by every restore path.
	local function restoreToolRecord(saved)
		if not saved then return end
		for part, rec in pairs(saved) do
			if part and part.Parent then
				pcall(function()
					if typeof(rec) == "Vector3" then
						part.Size = rec  -- legacy shape (size only), just in case
					else
						part.Size = rec.Size
						if rec.CanCollide ~= nil then part.CanCollide = rec.CanCollide end
						if rec.CanTouch ~= nil then part.CanTouch = rec.CanTouch end
						if rec.Massless ~= nil then part.Massless = rec.Massless end
					end
				end)
			end
		end
	end

	local function shouldExpandPart(part)
		local filter = Options.toolPartFilter:GetActiveValues()
		if table.find(filter, "All") then return true end
		for _, pat in ipairs(filter) do
			if string.find(part.Name:lower(), pat:lower()) then return true end
		end
		return false
	end

	local function expandTool(tool, expand, force)
		if expand then
			-- `force` skips the active-list gate (used by Auto-Add on Equip, F8).
			if not force and not table.find(Options.expandedWeapons:GetActiveValues(), tool.Name) then return end
			local scale = Options.toolExpandSize.Value
			local nonCollide = Toggles.toolNonCollide and Toggles.toolNonCollide.Value
			for _, part in ipairs(tool:GetDescendants()) do
				if part:IsA("BasePart") and shouldExpandPart(part) then
					originalToolSizes[tool] = originalToolSizes[tool] or {}
					local rec = originalToolSizes[tool][part]
					if not rec then
						rec = { Size = part.Size, CanCollide = part.CanCollide, CanTouch = part.CanTouch, Massless = part.Massless }
						originalToolSizes[tool][part] = rec
					end
					part.Size = rec.Size * scale
					-- MELEE-COLLIDE: the enlarged hitbox is non-collidable (won't shove
					-- you/objects or snag) but keeps CanTouch on so the game's own
					-- Handle.Touched damage still fires, and Massless so it can't drag
					-- your character around. Applied BOTH ways so toggling the option
					-- off re-collides an already-expanded tool. Full originals are
					-- restored via restoreToolRecord on un-expand/unload.
					if nonCollide then
						part.CanCollide = false
						part.CanTouch = true
						part.Massless = true
					else
						part.CanCollide = rec.CanCollide
						part.CanTouch = rec.CanTouch
						part.Massless = rec.Massless
					end
				end
			end
		else
			restoreToolRecord(originalToolSizes[tool])
			originalToolSizes[tool] = nil
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

	-- Add a tool name to Active Weapons (merge into the available values and tick it as
	-- selected) so an auto-detected tool shows up and stays selectable later. (F8)
	local function addToolToList(name)
		if not name or name == "" then return end
		local vals = Options.expandedWeapons.Values or {}
		if not table.find(vals, name) then
			table.insert(vals, name)
			Options.expandedWeapons.Values = vals
			Options.expandedWeapons:SetValues()
		end
		pcall(function()
			local sel = Options.expandedWeapons.Value
			if type(sel) == "table" and not sel[name] then
				sel[name] = true
				Options.expandedWeapons:SetValue(sel)
			end
		end)
	end

	-- TOOL-OVERHAUL: one-click "add the tool I'm holding to the list AND expand it
	-- now", so you don't have to find its name in the dropdown first.
	expanderGroup:AddButton("Add & Expand Held Weapon", function()
		local char = lPlayer.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		if not tool then Library:Notify("Equip a tool first"); return end
		addToolToList(tool.Name)
		if not Toggles.toolExpanderEnabled.Value then Toggles.toolExpanderEnabled:SetValue(true) end
		expandTool(tool, true, true)
		Library:Notify("Expanding: " .. tool.Name)
	end):AddToolTip("Add the currently-held tool to the active list and expand its hitbox immediately.")

	local function hookTool(tool)
		track(tool.Equipped:Connect(function()
			-- Auto-Add on Equip: detect & handle the equipped tool with no manual scan. (F8)
			if Toggles.toolAutoScanEquip and Toggles.toolAutoScanEquip.Value then
				addToolToList(tool.Name)
				if Toggles.toolExpanderEnabled.Value then expandTool(tool, true, true) end
			elseif Toggles.toolExpanderEnabled.Value and Toggles.toolAutoApply.Value then
				expandTool(tool, true)
			end
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
				restoreToolRecord(saved)
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
				restoreToolRecord(saved)
			end
		end,
	})

	print("[Physics] solver warm-up complete")
end)

-- ----- Manual Vehicle HBE (Main tab) ----------------------------------------
-- A standalone hitbox extender for a vehicle/part you pick by aiming at it and
-- clicking -- separate from the player extender, the world-part scanner and the
-- Misc speed module. It re-applies an additive size each frame (storing the real
-- size once, so it never corrupts the original and restores cleanly).
pcall(function()
	local lPlayer = Players.LocalPlayer
	local mvGroup = (Bridge.MiscTab or mainTab):AddRightGroupbox("Manual Vehicle HBE")
	mvGroup:AddToggle("mvHbeEnabled", { Text = "Enable Manual Vehicle HBE", Default = false, Tooltip = "Extend the hitbox of a vehicle/part you pick manually\n(independent of every other extender). (Default: OFF)" })
	mvGroup:AddSlider("mvHbeSize", { Text = "Added Size (studs)", Min = 1, Max = 250, Default = 20, Rounding = 1, Tooltip = "Studs added to the picked part's size. (Default: 20)" })
	mvGroup:AddSlider("mvHbeTransparency", { Text = "Transparency", Min = 0, Max = 1, Default = 0.6, Rounding = 2 })
	mvGroup:AddToggle("mvHbeCollisions", { Text = "Keep Collisions", Default = false, Tooltip = "Leave the extended part collidable. (Default: OFF)" })
	mvGroup:AddToggle("mvHbeWholeModel", { Text = "Whole Model", Default = false, Tooltip = "Extend every BasePart of the picked vehicle's model,\nnot just the one part. (Default: OFF)" })
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

	-- ---- VEH-MOD: gas / health / top-speed on the picked vehicle ----------
	-- Reuses the picked vehicle (above). Detects fuel/health/speed NumberValues +
	-- numeric attributes + VehicleSeat.MaxSpeed on the model and lets you pin them.
	-- "Infinite" holds each value at the highest it's ever been (auto-calibrates to
	-- full after one refuel/repair); Top Speed writes a chosen value.
	local vmGroup = (Bridge.MiscTab or mainTab):AddRightGroupbox("Vehicle Modify (picked)")
	vmGroup:AddToggle("vmInfGas",     { Text = "Infinite Gas/Fuel", Default = false, Tooltip = "Hold detected fuel/gas values at full. (Default: OFF)" })
	vmGroup:AddToggle("vmFullHealth", { Text = "Full Health/Durability", Default = false, Tooltip = "Hold detected health/durability values at full. (Default: OFF)" })
	vmGroup:AddToggle("vmSetSpeed",   { Text = "Set Top Speed", Default = false, Tooltip = "Write the speed below to detected speed values + VehicleSeat.MaxSpeed. (Default: OFF)" })
	vmGroup:AddSlider("vmTopSpeed",   { Text = "Top Speed", Min = 10, Max = 1000, Default = 200, Rounding = 0, Tooltip = "Value written when Set Top Speed is on. (Default: 200)" })
	-- Handling panel (screenshot-style). Writes to the detected VehicleSeat + any
	-- matching tune NumberValues/attributes on the vehicle YOU drive (you own its
	-- network, so the writes replicate). Auto-detected when you pick a vehicle.
	vmGroup:AddToggle("vehBoost",           { Text = "Speed Boost", Default = false, Tooltip = "Master switch for the handling sliders below. (Default: OFF)" })
	vmGroup:AddSlider("vehTargetSpeed",     { Text = "Target Speed", Min = 0, Max = 500, Default = 95, Rounding = 0, Tooltip = "Writes VehicleSeat.MaxSpeed + detected speed values. (Default: 95)" })
	vmGroup:AddSlider("vehAccel",           { Text = "Acceleration", Min = 0, Max = 100, Default = 1, Rounding = 0, Tooltip = "Writes VehicleSeat.Torque + detected torque/accel values. (Default: 1)" })
	vmGroup:AddSlider("vehTurnRate",        { Text = "Turn Rate", Min = 0, Max = 100, Default = 3, Rounding = 0, Tooltip = "Writes VehicleSeat.TurnSpeed + detected turn values. (Default: 3)" })
	vmGroup:AddSlider("vehTurnAngle",       { Text = "Turn Angle", Min = 0, Max = 90, Default = 16, Rounding = 0, Tooltip = "Writes detected steer-angle values (A-Chassis style). (Default: 16)" })
	vmGroup:AddSlider("vehTurnAccel",       { Text = "Turn Acceleration", Min = 0, Max = 100, Default = 3, Rounding = 0, Tooltip = "Writes detected turn-acceleration values. (Default: 3)" })
	vmGroup:AddToggle("vehStability",       { Text = "Stability Assist", Default = false, Tooltip = "Keep the vehicle upright (anti-rollover) via AlignOrientation. (Default: OFF)" })
	vmGroup:AddSlider("vehStabilityStrength", { Text = "Stability Strength", Min = 0, Max = 1, Default = 0.65, Rounding = 2, Tooltip = "How aggressively stability holds you upright. (Default: 0.65)" })
	vmGroup:AddToggle("vehKeepOwnership", { Text = "Keep Ownership (sim radius)", Default = false, Tooltip = "Raise your simulation radius (setsimulationradius) so you keep\nnetwork ownership of the vehicle -- makes the tuning writes far\nmore likely to stick. May be detectable; off by default. (Default: OFF)" })
	local vmInfo = vmGroup:AddLabel("Detected: pick a vehicle, then Detect")
	-- Live confidence readout: are your writes even going to stick? Shows whether
	-- YOU own the vehicle's network (writes replicate) vs the server, and whether a
	-- written value actually held (server didn't revert it).
	local vmStatus = vmGroup:AddLabel("Owner: -")

	local GAS_WORDS       = { "fuel", "gas", "gasoline", "petrol", "diesel" }
	local HEALTH_WORDS    = { "health", "durability", "integrity", "hp" }
	local TURNACCEL_WORDS = { "turnaccel", "turnacceleration", "steeracceleration" }
	local TURN_WORDS      = { "turnspeed", "turnrate", "steerspeed", "returnspeed" }
	local STEER_WORDS     = { "maxsteer", "steerangle", "turnangle", "steerinner", "steerouter" }
	local TORQUE_WORDS    = { "torque", "acceleration", "accel", "horsepower" }
	local SPEED_WORDS     = { "maxspeed", "topspeed", "speed", "velocity" }
	local function nameHasW(n, words) n = n:lower() for _, w in ipairs(words) do if n:find(w) then return true end end return false end
	-- Order matters: turn/steer must be checked before plain "speed" so "TurnSpeed"
	-- doesn't get mis-bucketed as top speed.
	local function classifyVal(name)
		if nameHasW(name, GAS_WORDS) then return "gas" end
		if nameHasW(name, HEALTH_WORDS) then return "health" end
		if nameHasW(name, TURNACCEL_WORDS) then return "turnaccel" end
		if nameHasW(name, TURN_WORDS) then return "turn" end
		if nameHasW(name, STEER_WORDS) then return "steer" end
		if nameHasW(name, TORQUE_WORDS) then return "torque" end
		if nameHasW(name, SPEED_WORDS) then return "speed" end
		return nil
	end
	local function fieldVal(v)  return { read = function() return v.Value end, write = function(n) pcall(function() v.Value = n end) end } end
	local function fieldAttr(i, a) return { read = function() return i:GetAttribute(a) end, write = function(n) pcall(function() i:SetAttribute(a, n) end) end } end
		local function fieldTbl(t, k) return { read = function() return t[k] end, write = function(n) pcall(function() t[k] = n end) end } end
	local function pickedModel() return pickedPart and (pickedPart:FindFirstAncestorWhichIsA("Model") or pickedPart) or nil end
	local function vmPrimary()
		local m = pickedModel(); if not m then return nil end
		return m.PrimaryPart or (pickedPart and pickedPart:IsA("BasePart") and pickedPart) or m:FindFirstChildWhichIsA("BasePart")
	end

	local vmB = { gas = {}, health = {}, speed = {}, torque = {}, turn = {}, steer = {}, turnaccel = {} }
	local vmSeats, vmMaxSeen, vmIsAChassis = {}, {}, false
	local function detectVehMod()
		vmB = { gas = {}, health = {}, speed = {}, torque = {}, turn = {}, steer = {}, turnaccel = {} }
		vmSeats, vmMaxSeen, vmIsAChassis = {}, {}, false
		local m = pickedModel()
		if not m then pcall(function() vmInfo:SetText("Detected: no vehicle picked") end); return end
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("NumberValue") or d:IsA("IntValue") then
				local b = classifyVal(d.Name); if b then table.insert(vmB[b], fieldVal(d)) end
			elseif d:IsA("VehicleSeat") then vmSeats[#vmSeats + 1] = d
				elseif d:IsA("ModuleScript") and (d.Name == "Tune" or d.Name:lower():find("chassis")) then
					-- A-Chassis: require the (pure-data) Tune module and expose numeric keys
					-- as writable fields so the handling sliders can drive its tune.
					pcall(function()
						local tune = require(d)
						if type(tune) == "table" then
							vmIsAChassis = true
							for k, val in pairs(tune) do
								if type(val) == "number" then
									local b = classifyVal(tostring(k)); if b then table.insert(vmB[b], fieldTbl(tune, k)) end
								end
							end
						end
					end)
				end
			pcall(function()
				for an, av in pairs(d:GetAttributes()) do
					if type(av) == "number" then local b = classifyVal(an); if b then table.insert(vmB[b], fieldAttr(d, an)) end end
				end
			end)
		end
		pcall(function() vmInfo:SetText(("%sGas:%d HP:%d Spd:%d Trq:%d Turn:%d Seats:%d"):format(vmIsAChassis and "[A-Chassis] " or "", #vmB.gas, #vmB.health, #vmB.speed, #vmB.torque, #vmB.turn, #vmSeats)) end)
	end
	vmGroup:AddButton("Detect Values", detectVehMod):AddToolTip("Scan the picked vehicle for fuel/health/speed/handling values to modify.")

	local function holdMax(list)
		for _, f in ipairs(list) do
			local v = f.read()
			if type(v) == "number" then vmMaxSeen[f] = math.max(vmMaxSeen[f] or v, v); f.write(vmMaxSeen[f]) end
		end
	end
	local function writeAll(list, n) for _, f in ipairs(list) do f.write(n) end end

	-- Stability assist: AlignOrientation that keeps the vehicle upright (preserving
	-- yaw), responsiveness scaled by strength. Tracked so it tears down cleanly.
	local vmStabPart = nil
	local function clearStab()
		if vmStabPart then
			pcall(function()
				local ao = vmStabPart:FindFirstChild("FurryHBE_StabAO"); if ao then ao:Destroy() end
				local att = vmStabPart:FindFirstChild("FurryHBE_StabAtt"); if att then att:Destroy() end
			end)
			vmStabPart = nil
		end
	end
	local function applyStab(primary, strength)
		if vmStabPart and vmStabPart ~= primary then clearStab() end
		if not (primary and primary.Parent) then return end
		local att = primary:FindFirstChild("FurryHBE_StabAtt")
		if not att then att = Instance.new("Attachment"); att.Name = "FurryHBE_StabAtt"; att.Parent = primary end
		local ao = primary:FindFirstChild("FurryHBE_StabAO")
		if not ao then
			ao = Instance.new("AlignOrientation"); ao.Name = "FurryHBE_StabAO"
			ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
			ao.Attachment0 = att; ao.RigidityEnabled = false; ao.Parent = primary
		end
		ao.MaxTorque = 1e6
		ao.Responsiveness = math.clamp(strength * 200, 5, 200)
		local look = primary.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
		ao.CFrame = CFrame.lookAt(Vector3.new(0, 0, 0), flat.Unit)
		vmStabPart = primary
	end

	local vmLastModel, vmStatusT = nil, 0
	local vmConn = RunService.Heartbeat:Connect(function()
		local m = pickedModel()
		if m ~= vmLastModel then vmLastModel = m; clearStab(); detectVehMod() end  -- auto re-detect + restabilise on new pick
		if not m then clearStab(); return end
		if Toggles.vmInfGas and Toggles.vmInfGas.Value then holdMax(vmB.gas) end
		if Toggles.vmFullHealth and Toggles.vmFullHealth.Value then holdMax(vmB.health) end
		if Toggles.vmSetSpeed and Toggles.vmSetSpeed.Value then
			local sp = Options.vmTopSpeed.Value
			writeAll(vmB.speed, sp)
			for _, s in ipairs(vmSeats) do if s.Parent then pcall(function() s.MaxSpeed = sp end) end end
		end
		-- Handling panel (screenshot-style).
		if Toggles.vehBoost and Toggles.vehBoost.Value then
			local ts, ac, tr = Options.vehTargetSpeed.Value, Options.vehAccel.Value, Options.vehTurnRate.Value
			local ta, tac = Options.vehTurnAngle.Value, Options.vehTurnAccel.Value
			for _, s in ipairs(vmSeats) do if s.Parent then pcall(function() s.MaxSpeed = ts; s.Torque = ac; s.TurnSpeed = tr end) end end
			writeAll(vmB.speed, ts); writeAll(vmB.torque, ac); writeAll(vmB.turn, tr)
			writeAll(vmB.steer, ta); writeAll(vmB.turnaccel, tac)
		end
		if Toggles.vehStability and Toggles.vehStability.Value then
			applyStab(vmPrimary(), Options.vehStabilityStrength.Value)
		else
			clearStab()
		end
		-- Live confidence readout (throttled): network ownership + did a write hold?
		local now = tick()
		if now - vmStatusT > 0.4 then
			vmStatusT = now
			if Toggles.vehKeepOwnership and Toggles.vehKeepOwnership.Value and setsimulationradius then
				pcall(function() setsimulationradius(1e6, 1e6) end)
			end
			local own = "?"
			local prim = vmPrimary()
			if prim and isnetworkowner then
				local ok, r = pcall(function() return isnetworkowner(prim) end)
				if ok then own = r and "YOU (writes stick)" or "server (writes may not stick)" end
			end
			local applied = ""
			if Toggles.vehBoost and Toggles.vehBoost.Value and vmSeats[1] and vmSeats[1].Parent then
				local ok2, ms = pcall(function() return vmSeats[1].MaxSpeed end)
				if ok2 then applied = (math.abs((ms or 0) - Options.vehTargetSpeed.Value) < 1.5) and "  | speed applied OK" or "  | speed REVERTED" end
			end
			pcall(function() vmStatus:SetText("Owner: " .. own .. applied) end)
		end
	end)

	Bridge:RegisterAddon("ManualVehicleHBE", {
		onUnload = function()
			if hbConn then pcall(function() hbConn:Disconnect() end) end
			if vmConn then pcall(function() vmConn:Disconnect() end) end
			pcall(clearStab)
			pcall(restore)
		end,
	})
	print("[Audio] ambient bank loaded")
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
	g:AddToggle("vehicleEspAutoTrack", { Text = "Auto-Track Vehicles", Default = true, Tooltip = "Continuously find drivable vehicles (anything with a\nVehicleSeat) and keep the list LIVE -- new spawns are added,\ndestroyed/despawned ones are removed automatically, so it\nnever shows a car you spawned ages ago. (Default: ON)" })
	g:AddToggle("vehicleEspWheelCars", { Text = "Detect Wheel-Cars (no seat)", Default = false, Tooltip = "VEH-ESP2: also track cars that are a single model with no\nVehicleSeat (just tires + body) -- e.g. other players' cars.\nHeuristic (>=2 wheel/tire parts); may occasionally over-match. (Default: OFF)" })
	g:AddDropdown("vehicleEspList", { Text = "Registered Vehicles", Values = {}, Multi = false, AllowNull = true, Tooltip = "Vehicles currently tracked. (Default: none)" })
	g:AddDropdown("vehicleEspType", { Text = "Mark As", Values = { "Car", "Helicopter", "Boat", "Plane" }, Default = "Car", Multi = false, AllowNull = false, Tooltip = "Type to tag the selected vehicle with (saved to disk). (Default: Car)" })

	local registered = {}     -- { { model=, name=, type= }, ... }
	local vehicleTypes = {}   -- [name] = type (persisted)
	pcall(function()
		if isfile and readfile and isfile(VE_FILE) then
			local ok, t = pcall(function() return HttpService:JSONDecode(readfile(VE_FILE)) end)
			if ok and type(t) == "table" then vehicleTypes = t end
		end
	end)
	local function saveTypes() if writefile then pcall(function() writefile(VE_FILE, HttpService:JSONEncode(vehicleTypes)) end) end end
	-- Drop registered vehicles whose model was destroyed/despawned, so the list never
	-- shows the car you spawned several respawns ago.
	local function pruneDead()
		local changed = false
		for i = #registered, 1, -1 do
			local m = registered[i].model
			if not (typeof(m) == "Instance" and m.Parent) then
				table.remove(registered, i); changed = true
			end
		end
		return changed
	end
	local function refreshList()
		pruneDead()
		local names = {}
		for _, e in ipairs(registered) do table.insert(names, e.name) end
		Options.vehicleEspList.Values = names
		Options.vehicleEspList:SetValues()
	end
	local function isRegistered(m) for _, e in ipairs(registered) do if e.model == m then return true end end return false end
	local function registerModel(m)
		if not m or not m:IsA("Model") or isRegistered(m) then return false end
		table.insert(registered, { model = m, name = m.Name, type = vehicleTypes[m.Name] or "Car" })
		return true
	end
	-- Find every model that contains a VehicleSeat (i.e. a drivable/operatable vehicle).
	local function scanVehicles()
		local added = 0
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("VehicleSeat") then
				local m = d:FindFirstAncestorWhichIsA("Model")
				if m and not isRegistered(m) and registerModel(m) then added = added + 1 end
			end
		end
		return added
	end

	-- VEH-ESP2: heuristic for cars that are ONE model with no VehicleSeat (just tires
	-- + a body), which the VehicleSeat sweep above misses for other players. A model
	-- counts as a wheel-car if it has >=2 wheel/tire-named parts and no Humanoid.
	local WHEEL_WORDS = { "wheel", "tire", "tyre" }
	local function looksLikeWheelCar(m)
		if not (m and m:IsA("Model")) then return false end
		if m:FindFirstChildWhichIsA("Humanoid", true) then return false end   -- it's a character
		if m:FindFirstChildWhichIsA("VehicleSeat", true) then return false end -- already covered
		-- Model-name shortcut for boats/planes/helis that don't have wheels.
		local mn = m.Name:lower()
		if mn:find("boat") or mn:find("ship") or mn:find("heli") or mn:find("plane") or mn:find("jet") then return true end
		local wheels, rotors = 0, 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				local n = d.Name:lower()
				for _, w in ipairs(WHEEL_WORDS) do if n:find(w) then wheels = wheels + 1; break end end
				-- heli/plane rotor or boat propeller/hull also marks a vehicle.
				if n:find("rotor") or n:find("propeller") then rotors = rotors + 1 end
				if n:find("hull") then return true end
				if wheels >= 2 or rotors >= 1 then return true end
			end
		end
		return false
	end
	-- Walk top-level models + one level into folders (where games park vehicles).
	local function eachCandidateModel(cb)
		for _, c in ipairs(Workspace:GetChildren()) do
			if c:IsA("Model") then cb(c)
			elseif c:IsA("Folder") then for _, m in ipairs(c:GetChildren()) do if m:IsA("Model") then cb(m) end end end
		end
	end
	local function scanWheelCars()
		local added = 0
		eachCandidateModel(function(m)
			if not isRegistered(m) and looksLikeWheelCar(m) and registerModel(m) then added = added + 1 end
		end)
		return added
	end

	g:AddButton("Scan Vehicles", function()
		pruneDead()
		local count = scanVehicles()
		if Toggles.vehicleEspWheelCars and Toggles.vehicleEspWheelCars.Value then count = count + scanWheelCars() end
		refreshList()
		Library:Notify("Vehicle ESP: " .. count .. " new (" .. #registered .. " tracked)")
	end):AddToolTip("Find models that contain a VehicleSeat and register them (Auto-Track keeps this live for you)")
	g:AddButton("Register (hold-pick)", function()
		Bridge:StartHoldPick({ color = Color3.fromRGB(0, 255, 170), onPick = function(part)
			local m = part:FindFirstAncestorWhichIsA("Model") or part
			registerModel(m); refreshList(); Library:Notify("Registered vehicle: " .. m.Name)
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

	-- Auto-track: keep the registry live without manual scanning. Throttled so it's
	-- cheap, and only refreshes the dropdown when the set actually changes (so it
	-- won't fight your selection). Prunes destroyed/despawned models too.
	local lastAutoScan = 0
	local autoScanConn = RunService.Heartbeat:Connect(function()
		if not (Toggles.vehicleEspAutoTrack and Toggles.vehicleEspAutoTrack.Value) then return end
		if tick() - lastAutoScan < 1.5 then return end
		lastAutoScan = tick()
		local changed = pruneDead()
		if scanVehicles() > 0 then changed = true end
		if Toggles.vehicleEspWheelCars and Toggles.vehicleEspWheelCars.Value and scanWheelCars() > 0 then changed = true end
		-- Also grab the car YOU are sitting in -- covers single-model cars whose seat
		-- the Workspace sweep might not have matched, so your own vehicle always shows.
		pcall(function()
			local lhum = lPlayer.Character and lPlayer.Character:FindFirstChildWhichIsA("Humanoid")
			if lhum and lhum.SeatPart then
				local m = lhum.SeatPart:FindFirstAncestorWhichIsA("Model")
				if m and not isRegistered(m) and registerModel(m) then changed = true end
			end
		end)
		if changed then refreshList() end
	end)

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
		if autoScanConn then pcall(function() autoScanConn:Disconnect() end) end
		for _, t in ipairs(pool) do safeRemoveDrawing(t) end
	end })
	print("[Content] streaming region active")
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
		"V8 fix + feature pass. ESP now auto-routes Potassium/Solara through the GUI fallback (native Drawing constructs but doesn't render there) so names, 2D boxes and tracers finally show; the fallback overlay was corrected with IgnoreGuiInset and round circles, chams default to a visible red/white instead of invisible black, and Precision no longer freezes the target -- it defaults to extending the Head instead of the HumanoidRootPart (resizing the root is what froze them), sets enlarged parts Massless, and adds target stickiness so the lock stops thrashing between similar-distance players. New Combat tab adds a Weapon Reader (reads the held tool's name/type) and Target Groups (drag-select a box over players to track them with a cyan highlight). Added a Force-Restore-All button for stuck hitboxes; override the ESP path with getgenv().FurryHBE_ForceGuiESP / _ForceNativeESP.",
		"Silent Melee batch on the Combat tab. Left-click (or optional Kill Aura) fires a touch between your weapon's parts -- or your bare fists when no tool is held -- and the chosen target via firetouchinterest, so the game's own .Touched damage handler lands the hit with no hooks. Targets are picked by Closest-to-Crosshair, Closest-in-Range, or your whole Target Group, with melee-only gating, team/whitelist ignores, a melee-reach range limit, and a shiftlock aim ring that turns green on lock. Target Groups also gained an Add-Players-in-Radius button to grab everyone within X studs.",
		"MELEE-COLLIDE: the Tool Expander gained a Non-Collidable Hitbox option (on by default). The enlarged tool hitbox now keeps CanTouch on (so the game's own touch-damage still lands) while CanCollide is forced off and the part is made Massless, so the bigger hitbox no longer shoves you/objects, snags on the world, or drags your character. Originals (size + collision/touch/mass) are captured per part and fully restored on un-expand, toggle-off and unload.",
		"MELEE-PEN + Silent Melee confidence pass. Silent Melee gained Wall Penetration (hit through walls, or turn off for a line-of-sight check) and Shield Bypass (skip the target's shield parts so the touch lands on the body), backed by a manual Pick-Shield hold-picker that registers a shield model's name as a fallback shield matcher for every player. Reliability was raised by firing both firetouchinterest AND the weapon's actual Touched connections via getconnections():Fire(target), plus a live readout that detects whether the held weapon is touch-based and confirms when a target's HP actually drops.",
		"F10 Extract / Calibrate Game: a new Calibrate tab fingerprints the current place and auto-detects non-standard character part names (custom/rthro rigs), gun tools, shields, the melee damage mechanism, vehicle seats and team count. Detected parts/guns/shields are auto-applied to the HBE, Inf-Ammo and Melee-shield lists (each gated by a toggle), with a full on-screen report. The extracted profile can be saved per PlaceId and auto-loads on startup, so each game self-configures after one scan.",
		"Vehicle + utility batch. VEH-MOD adds gas/health/top-speed control on the manually-picked vehicle (detects fuel/health/speed NumberValues + attributes + VehicleSeat.MaxSpeed; Infinite holds each at its highest seen value). VEH-ESP2 adds a wheel-car heuristic so single-model cars with no VehicleSeat (other players' cars) get tracked. Inf-Ammo now also scans player-side numeric attributes and a wider keyword set for separate inventory ammo. Added a type-to-filter search on the player lists and a Bridge:Connect tracked-connection helper for leak-free unloads.",
		"Tool Hitbox Editor (TOOL-RESIZE + TOOL-VIZ) on the Combat tab. A native btools-style Handles gizmo lets you drag a tool's hitbox faces to resize it in 3D, with X/Y/Z sliders for precise sizing and a live green SelectionBox showing the hitbox extent -- the tool's own mesh visual is untouched (only the BasePart size changes), and the edited part is kept non-collidable + CanTouch so it still does touch-damage over the bigger area. Edit your held weapon or hold-pick any part; Reset-to-Original and Stop-Editing buttons manage it.",
		"Precision + tooling polish. PRECISION-OVERHAUL/F11 adds a Resolver (Closest-to-Crosshair / Closest-Distance / Lowest-Health) and a Velocity-Lead slider that predicts a target's position by its velocity when locking. TOOL-OVERHAUL adds a one-click 'Add & Expand Held Weapon' button. The Miscellaneous tab was renamed Vehicle/Misc for clarity. Whole file syntax-validated with the Luau compiler.",
		"Vehicle Tuning panel on the manually-picked vehicle. Picking a vehicle now auto-detects its fuel/health/top-speed plus handling values (torque/turn-speed/steer-angle/turn-accel) and the VehicleSeat. A screenshot-style panel exposes Speed Boost + Target Speed, Acceleration, Turn Rate, Turn Angle, Turn Acceleration, and a Stability Assist (anti-rollover AlignOrientation) with a Strength slider -- each writing to the detected VehicleSeat and matching tune values on the car you drive. A live readout uses isnetworkowner + a write read-back to show whether YOU own the vehicle (writes stick) or the server reverts them, so you instantly know if tuning will work in that game.",
		"Confidence + reach pass. ESP gained a backend readout, a Force-Backend override (Auto/Native/GUI) and a Test-Backends button that paints a native + a GUI marker so you can SEE which renders, plus a live 'ESP drawn N/N' count. Vehicle tuning now detects A-Chassis and requires its Tune module to drive steer/turn values directly. Game profiles export/import as shareable base64 strings via the clipboard. A hook-free Remote Replay tool fires a chosen RemoteEvent at the nearest target for RemoteEvent-damage games. Whole file re-validated with the Luau compiler (clean) with no duplicate control keys.",
		"Improvements + tailoring pass. Vehicle: Keep-Ownership (setsimulationradius) to make tuning writes stick, and Vehicle ESP now also finds boats/planes/helis (rotor/propeller/hull/name heuristics). Weapon Reader reports detected damage/range. Precision shows a [FROZEN?] warning when a locked target's velocity flatlines. Teleport notifies if you rubberband back. The HBE tab shows a heuristic Detection-risk estimate from your settings. Inf-Ammo takes a manual ammo-value name that extends every detection strategy. F10's report now counts RemoteEvents. All Luau-compiler validated.",
		"Performance pass. The per-player HBE and ESP loops no longer spawn a fresh coroutine per player per frame (Update/UpdateESP never yield, so task.spawn was pure allocation -- now a direct pcall, same error isolation, much cheaper). The Silent-Melee crosshair throttles its target scan + LOS raycast to ~12Hz while the crosshair still tracks every frame. A Half-Rate ESP toggle renders ESP every other frame (~30fps) to roughly halve its CPU cost on demand.",
		"Enemy/Ally ESP + Gun Combat. ESP gained an Enemy/Ally colour mode (red enemy, green ally, configurable Friendly/Enemy team lists + Own-Team-Ally) that recolours names, boxes, tracers, chams and the new cur/max health (33/100) readout. A new Aimbot tab adds a hook-free camera Aimbot (FOV, smoothness, target part, visible-only, hold-key/right-mouse, FOV ring), a raycast Triggerbot, and value-based No-Recoil. F10 now also reports the gun/recoil system so you know if those will work. All Luau-compiler validated; 12 tabs.",
		"Calibration engine, Tiers 1-3. The Calibrate tab now fingerprints the game's FRAMEWORK (A-Chassis, ACS, FE Gun Kit, admin systems, combat services, round systems) and exposes everything on Bridge.Calibrate for other modules. A new Tier-3 behavioral Learn engine snapshots every numeric value on you + your character, lets you perform an action, then diffs it to surface ammo/health/currency/recoil fields WITHOUT knowing their names -- with a one-click hand-off into Inf-Ammo's manual detector.",
		"Tier 4: Phantom Recon (opt-in, read-only). The principle is 'read the wiring diagram, never trip the alarm': it builds closures from the anti-cheat's own bytecode and dumps the string constants + reads its environment + maps nil-parented honeypot remotes -- pure reflection that game-level Lua cannot observe (there's no callback for someone reading your upvalues), so the probe never writes, fires or hooks, and there is nothing to register. It publishes a minefield map on Bridge.DeepScan: the Remote Replay tool now refuses to fire mapped honeypots, and the Detection-risk readout flags a detected anti-cheat. (Defeats dev-written Lua anti-cheats only; it does not touch Roblox's binary anti-tamper.)",
		"Tier 5: Collective intelligence. The Calibrate tab gained a per-game profile DB plus community fetch -- point it at any raw-JSON URL (e.g. a GitHub profiles folder) and it pulls <url>/<PlaceId>.json -- with a confidence-scored fallback chain (community -> your local DB -> live scan) that merges and remembers, so a game self-configures instantly next visit.",
		"Advanced frontier (safe set): a camera Aimbot ballistic resolver (lead by velocity x bullet-travel-time + gravity-drop comp), a team-coloured Radar/minimap rotated to your view, a Movement tab (bunny-hop + infinite jump), teleport Persistence (queue_on_teleport re-inject from a loader URL), and an Auto-Soften director that dials aggressive settings into safe ranges when Phantom Recon detects an anti-cheat. The break-prone/hook frontiers (function hooks, fakelag, actor offload, decompiler, WebSocket C2) were researched and drafted separately, NOT integrated, to keep this build stable.",
		"Plugin system v1 (compartmentalization). The Bridge gained EnablePlugin/UnloadPlugin + a tracked plugin context (ctx) that auto-disconnects connections, destroys instances/groupboxes and clears control keys on unload, so plugins are true plug-and-play: enable runs a real loadstring and builds the tab on demand, unload frees its memory/connections and drops refs so the code GCs. A Plugins tab manages it, and the first plugin -- Spectate (cycle the camera through players) -- ships as an on-demand module proving the cycle. Existing tabs are untouched and will migrate into plugins one at a time.",
		"Plugin externalization: the loader now fetches plugins from a Plugin Base URL (your GitHub raw folder, set in the Plugins tab or getgenv().FurryHBE_PluginBase) as <base>/<file>.lua. The Gun Combat block (aimbot/triggerbot/no-recoil), Spectate and the Advanced tab (radar/movement/persistence/auto-soften) were moved OUT into their own files (aimbot.lua, spectate.lua, advanced.lua, precision.lua) and removed from the core (~835 fewer lines). Core helpers getSafeGuiParent + relationshipColor are exposed on the Bridge so external plugins can reuse them.",
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
		-- Modules are now external plugins (loaded on demand), so they're no longer a
		-- requirement for the green light: green = core healthy + no logged errors.
		if #errorLog == 0 then return "green" end
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
		-- Alt-tab / window blur doesn't fire MouseLeave, which left the tooltip stuck.
		pcall(function() UserInputService.WindowFocusReleased:Connect(function() tip.Visible = false end) end)
		Bridge:RegisterAddon("StatusTip", { onUnload = function() pcall(function() tipGui:Destroy() end) end })
	end)

	-- Changelog viewer: the 3 sentences only load when the button is clicked.
	clGroup:AddDropdown("clVersion", { Text = "Version", Values = versionStrings, Default = currentVersion, Multi = false, AllowNull = false, Tooltip = "Pick a version, then click View Changelog. (Default: latest)" })
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
	print("[UI] HUD layout applied")
end)

-- Make the tab-scroll hint obvious. When there are more tabs than fit, LinoriaLib
-- shows a small "scrollwheel >" marker above the tab bar; we find it and make it
-- clearer + brighter. Best-effort (pcall) so it never breaks load.
pcall(function()
	local sg = Library.ScreenGui
	if not sg then return end
	for _, d in ipairs(sg:GetDescendants()) do
		if d:IsA("TextLabel") and typeof(d.Text) == "string" and d.Text:lower():find("scroll") then
			-- Keep it SHORT so it doesn't overflow the small marker and clip to nothing;
			-- just brighten the existing native hint.
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
		"closestTargetsOnly","maxTargets","updateRate","perfAdaptive","perfFpsFloor","randomizationToggled","randomizationAmount",
		"humanizationToggled","legitModeToggled","seatDisableHBE","seatRadiusMode","seatRadius","seatExitDelayEnabled","seatExitDelay",
		"espNameToggled","espNameSize","espHighlightToggled","espBoxToggled","espBoxScale",
		"espTracerToggled","espSkeletonToggled","espHealthBarToggled","espNameType","espMaxDistance",
		-- ESP extras + anti-detect
		"espRainbow","espRainbowSpeed","espThickness","espDistanceFade","espChamsGlow",
		"priorityFlash","smartJitter","maxPlausibleMult","espWhitelisted","espAntiOverlap","espOverlapGap","espHalfRate",
		"espTeamColors","espOwnTeamFriendly","espFriendlyTeams","espEnemyTeams",
		-- Add-on modules (unified persistence)
		"precisionEnabled","precisionExclusive","precisionHitboxSize","precisionTransparency","precisionShape",
		"precisionCollisions","autoSelectTarget","selectionRadius","precisionResolver","precisionLeadTime","dynamicScalingEnabled",
		"scalingCloseFactor","scalingFarFactor","scalingThreshold",
		"vehicleAssist","vehicleJoltPower","vehicleJoltRelative","vehicleTripleTap","vehicleAccelerator","vehicleTopSpeed","vehicleAccelRate","vehicleStabilizer","vehicleSpeedLimiter","vehicleSpeedCap","vehicleManualMode",
		"toolExpanderEnabled","toolExpandSize","toolAutoApply","toolAutoScanEquip","toolNonCollide",
		"infAmmoEnabled","infAmmoAllTools","infAmmoAmount","infAmmoManualName",
		"vehicleEspEnabled","vehicleEspAutoTrack","vehicleEspWheelCars","mvHbeEnabled","mvHbeSize","mvHbeTransparency","mvHbeCollisions","mvHbeWholeModel",
		"vmInfGas","vmFullHealth","vmSetSpeed","vmTopSpeed",
		"vehBoost","vehTargetSpeed","vehAccel","vehTurnRate","vehTurnAngle","vehTurnAccel","vehStability","vehStabilityStrength","vehKeepOwnership",
		"streamerMaster","hideFOVCircle","hidePlayerESP","hideChams","hideHitboxGlow",
		"weaponReaderAuto","groupRadius",
		"silentMeleeEnabled","silentMeleeMode","silentMeleeRange","silentMeleeFOV","silentMeleeOnlyMelee","silentMeleeAura","silentMeleeAuraRate","silentMeleeIgnoreTeam","silentMeleeIgnoreWL","silentMeleeCrosshair","silentMeleeWallPen","silentMeleeShieldBypass","shieldNames",
		"calApplyParts","calApplyAmmo","calApplyShields","deepScanEnabled","profileSourceUrl","pluginBaseUrl",
		"aimbotEnabled","aimbotTrigger","aimbotPart","aimbotFOV","aimbotSmooth","aimbotVisibleOnly","aimbotIgnoreTeam","aimbotIgnoreWL","aimbotShowFOV",
		"triggerEnabled","triggerActivate","triggerDelay","triggerIgnoreTeam","norecoilEnabled",
		"aimbotPredict","aimbotBulletSpeed","aimbotDropComp",
		"radarEnabled","radarRange","radarSize","bhopEnabled","infJumpEnabled","autoSoften","persistEnabled","persistUrl",
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
	print("[Save] profile slot ready")
end)

-- ===== [Improvement #9] Master Panic / Reset All =====
pcall(function()
	emergencyGroupbox:AddButton("PANIC / Reset All", function()
		pcall(function() if Toggles.MasterToggle then Toggles.MasterToggle:SetValue(false) end end)
		for _, k in ipairs({
			"extenderToggled", "precisionEnabled", "vehicleAssist", "mvHbeEnabled",
			"streamerMaster", "infAmmoEnabled", "vehicleEspEnabled", "toolExpanderEnabled",
			"vehicleSpeedLimiter", "vehicleStabilizer", "outlineMode", "espNameToggled", "espHighlightToggled",
			"espBoxToggled", "espTracerToggled", "espSkeletonToggled", "fovFilterToggled",
			"dragSelectMode", "silentMeleeEnabled", "silentMeleeAura",
			"vmInfGas", "vmFullHealth", "vmSetSpeed", "vehBoost", "vehStability", "rrAuto",
			"aimbotEnabled", "triggerEnabled", "norecoilEnabled", "bhopEnabled", "infJumpEnabled",
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
	-- Toggle to show/hide it (it had no off-switch before). Lives in Performance.
	local grp = performanceGroupbox or mainTab:AddRightGroupbox("UI")
	grp:AddToggle("showWatermark", { Text = "Show Watermark", Default = false, Tooltip = "On-screen watermark: name | tracked players | status. (Default: OFF)" }):OnChanged(function()
		pcall(function() Library:SetWatermarkVisibility(Toggles.showWatermark.Value) end)
	end)
	pcall(function() Library:SetWatermarkVisibility(Toggles.showWatermark.Value) end)
	task.spawn(function()
		while getgenv().FurryHBEInjected do
			if Toggles.showWatermark and Toggles.showWatermark.Value then
				pcall(function()
					local n = 0
					for _ in pairs(players) do n = n + 1 end
					local status = (#errorLog == 0) and "OK" or ("ERR " .. #errorLog)
					if Library.SetWatermark then
						Library:SetWatermark(string.format("cryptonize's library  |  tracked %d  |  %s", n, status))
					end
				end)
			end
			task.wait(1)
		end
	end)
end)

-- Wrap long tooltips so they don't run off-screen. SAFE this time: it's deferred
-- and pcall'd, and only sets TextWrapped on already-built hidden tooltip labels --
-- it never replaces Library.AddToolTip (that's what broke the UI build before).
task.spawn(function()
	task.wait(1)  -- let tooltip labels be created during build
	pcall(function()
		local sg = Library.ScreenGui
		if not sg then return end
		for _, d in ipairs(sg:GetDescendants()) do
			if d:IsA("TextLabel") and type(d.Text) == "string" and #d.Text > 30 then
				-- Tooltips live inside a hidden frame (control labels are short, so the
				-- >30 length filter skips them). Only wrap those.
				local insideHidden, p = false, d.Parent
				for _ = 1, 6 do
					if not p or p == sg then break end
					if p:IsA("GuiObject") and p.Visible == false then insideHidden = true; break end
					p = p.Parent
				end
				if insideHidden then
					d.TextWrapped = true
					d.AutomaticSize = Enum.AutomaticSize.Y
					-- Force a readable width so text doesn't clip
					d.Size = UDim2.new(0, 280, d.Size.Y.Scale, math.max(d.Size.Y.Offset, 16))
				end
			end
		end
	end)
end)

-- ===== [V8] Combat tab: Weapon Reader + Target Groups ======================
-- Self-contained add-on block (one isolated pcall, appended at the end per the
-- build rules). Foundation for the future Melee/Silent-Aim work: it exposes the
-- read weapon on Bridge.Weapon and the drag-selected group on Bridge.TargetGroup.
pcall(function()
	local combatTab = mainWindow:AddTab("Combat")

	-- ---- Weapon Reader -----------------------------------------------------
	local wrGroup    = combatTab:AddLeftGroupbox("Weapon Reader")
	local heldLabel  = wrGroup:AddLabel("Held: none")
	local typeLabel  = wrGroup:AddLabel("Type: -")
	wrGroup:AddToggle("weaponReaderAuto", { Text = "Auto-Read Held Weapon", Default = true, Tooltip = "Continuously read the name/type of the tool you're holding. (Default: ON)" })

	Bridge.Weapon = Bridge.Weapon or { name = nil, type = nil, tool = nil }

	-- Heuristic weapon-type classifier from the tool/model name.
	local function classify(tool)
		local n = tool.Name:lower()
		local function has(...) for _, w in ipairs({ ... }) do if n:find(w) then return true end end return false end
		if has("sword", "blade", "katana", "knife", "dagger", "machete", "axe", "scythe", "saber") then return "Melee (blade)" end
		if has("fist", "glove", "punch", "knuckle") then return "Melee (fist)" end
		if has("bat", "hammer", "club", "mace", "staff", "spear", "pole", "pipe", "wrench") then return "Melee (blunt)" end
		if has("bow", "crossbow") then return "Ranged (bow)" end
		if has("gun", "rifle", "pistol", "smg", "shotgun", "sniper", "ak", "glock", "launcher", "uzi", "deagle") then return "Ranged (gun)" end
		if tool:FindFirstChild("Handle") then return "Tool (unknown)" end
		return "Unknown"
	end

	local function currentTool()
		local char = lPlayer.Character
		if not char then return nil end
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") then return t end
		end
		return nil
	end

	-- Read a numeric stat (Value or attribute) whose name matches any keyword.
	local function findStat(tool, words)
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("NumberValue") or d:IsA("IntValue") then
				local n = d.Name:lower()
				for _, w in ipairs(words) do if n:find(w) then return d.Value end end
			end
		end
		local found
		pcall(function()
			for _, d in ipairs(tool:GetDescendants()) do
				for an, av in pairs(d:GetAttributes()) do
					if type(av) == "number" then local ln = an:lower() for _, w in ipairs(words) do if ln:find(w) then found = av; return end end end
				end
			end
		end)
		return found
	end
	local function readNow()
		local t = currentTool()
		if t then
			Bridge.Weapon.tool, Bridge.Weapon.name, Bridge.Weapon.type = t, t.Name, classify(t)
			Bridge.Weapon.damage = findStat(t, { "damage", "dmg" })
			Bridge.Weapon.range = findStat(t, { "range", "reach", "distance" })
			heldLabel:SetText("Held: " .. t.Name)
			local extra = ""
			if Bridge.Weapon.damage then extra = extra .. "  dmg:" .. tostring(Bridge.Weapon.damage) end
			if Bridge.Weapon.range then extra = extra .. "  rng:" .. tostring(Bridge.Weapon.range) end
			typeLabel:SetText("Type: " .. Bridge.Weapon.type .. extra)
		else
			Bridge.Weapon.tool, Bridge.Weapon.name, Bridge.Weapon.type = nil, nil, nil
			heldLabel:SetText("Held: none")
			typeLabel:SetText("Type: -")
		end
		return t
	end

	wrGroup:AddButton("Read Held Weapon", function()
		readNow()
		Library:Notify(Bridge.Weapon.name and ("Weapon: " .. Bridge.Weapon.name .. " [" .. Bridge.Weapon.type .. "]") or "No weapon held")
	end):AddToolTip("Read the equipped tool's name and guess its type (melee/ranged).")

	local wrLast = 0
	local wrConn = RunService.Heartbeat:Connect(function()
		if not (Toggles.weaponReaderAuto and Toggles.weaponReaderAuto.Value) then return end
		local now = tick(); if now - wrLast < 0.3 then return end; wrLast = now
		pcall(readNow)
	end)

	-- ---- Target Groups (drag-select players into an ESP group) -------------
	local tgGroup = combatTab:AddRightGroupbox("Target Groups")
	tgGroup:AddLabel("Drag-select players into a tracked group.\nThey get a cyan highlight, independent of normal ESP.", true)
	local tgCountLabel = tgGroup:AddLabel("Group: 0 players")

	local groupMembers    = {}   -- [Player] = true
	local groupHighlights = {}   -- [Player] = Highlight
	Bridge.TargetGroup = groupMembers  -- exposed for future silent-aim / melee

	local GuiService = game:GetService("GuiService")

	-- Selection-rectangle overlay. IgnoreGuiInset = absolute screen pixels, which
	-- matches UserInputService:GetMouseLocation(). WorldToViewportPoint excludes
	-- the topbar inset, so player points get +inset.Y when hit-testing below.
	local selGui = Instance.new("ScreenGui")
	selGui.Name = "FurryHBE_DragSelect"; selGui.ResetOnSpawn = false
	selGui.IgnoreGuiInset = true; selGui.DisplayOrder = 50
	selGui.Parent = getSafeGuiParent()
	local selBox = Instance.new("Frame")
	selBox.BackgroundColor3 = Color3.fromRGB(0, 200, 255); selBox.BackgroundTransparency = 0.75
	selBox.BorderSizePixel = 0; selBox.Visible = false; selBox.Parent = selGui
	local selStroke = Instance.new("UIStroke"); selStroke.Color = Color3.fromRGB(0, 220, 255)
	selStroke.Thickness = 1; selStroke.Parent = selBox

	local function setGroupHighlight(plr, on)
		if on then
			if not groupHighlights[plr] then
				local hl = Instance.new("Highlight")
				hl.FillColor = Color3.fromRGB(0, 200, 255); hl.OutlineColor = Color3.fromRGB(0, 255, 255)
				hl.FillTransparency = 0.5; hl.OutlineTransparency = 0
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = getSafeGuiParent()
				groupHighlights[plr] = hl
			end
		elseif groupHighlights[plr] then
			pcall(function() groupHighlights[plr]:Destroy() end)
			groupHighlights[plr] = nil
		end
	end

	local function refreshCount()
		local n = 0; for _ in pairs(groupMembers) do n += 1 end
		tgCountLabel:SetText("Group: " .. n .. " players")
	end

	tgGroup:AddToggle("dragSelectMode", { Text = "Drag-Select Mode", Default = false, Tooltip = "Hold left-mouse and drag a box over players to add them\nto the group. Toggle off when done. (Default: OFF)" }):OnChanged(function()
		if not Toggles.dragSelectMode.Value then selBox.Visible = false end
	end)
	tgGroup:AddButton("Clear Group", function()
		for plr in pairs(groupMembers) do setGroupHighlight(plr, false) end
		table.clear(groupMembers); refreshCount()
		Library:Notify("Target group cleared")
	end):AddToolTip("Remove everyone from the target group.")

	local dragStart = nil
	local function dragActive() return Toggles.dragSelectMode and Toggles.dragSelectMode.Value end

	local cBegan = UserInputService.InputBegan:Connect(function(input, gp)
		if not dragActive() or gp then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragStart = UserInputService:GetMouseLocation()
			selBox.Position = UDim2.fromOffset(dragStart.X, dragStart.Y)
			selBox.Size = UDim2.fromOffset(0, 0)
			selBox.Visible = true
		end
	end)
	local cChanged = UserInputService.InputChanged:Connect(function(input)
		if not dragActive() or not dragStart then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local cur = UserInputService:GetMouseLocation()
			local x0, y0 = math.min(dragStart.X, cur.X), math.min(dragStart.Y, cur.Y)
			local x1, y1 = math.max(dragStart.X, cur.X), math.max(dragStart.Y, cur.Y)
			selBox.Position = UDim2.fromOffset(x0, y0)
			selBox.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
		end
	end)
	local cEnded = UserInputService.InputEnded:Connect(function(input)
		if not dragStart then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local cur = UserInputService:GetMouseLocation()
			local x0, y0 = math.min(dragStart.X, cur.X), math.min(dragStart.Y, cur.Y)
			local x1, y1 = math.max(dragStart.X, cur.X), math.max(dragStart.Y, cur.Y)
			dragStart = nil; selBox.Visible = false
			if (x1 - x0) < 6 and (y1 - y0) < 6 then return end  -- ignore a click
			local cam = Workspace.CurrentCamera
			local inset = GuiService:GetGuiInset()
			local added = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= lPlayer then
					local char = plr.Character
					local node = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
					if node then
						local sp, on = cam:WorldToViewportPoint(node.Position)
						local mx, my = sp.X, sp.Y + inset.Y
						if on and mx >= x0 and mx <= x1 and my >= y0 and my <= y1 then
							if not groupMembers[plr] then
								groupMembers[plr] = true; setGroupHighlight(plr, true); added += 1
							end
						end
					end
				end
			end
			refreshCount()
			Library:Notify("Added " .. added .. " player(s) to group")
		end
	end)

	-- Re-adorn highlights to current characters (respawns) and prune leavers.
	local tgConn = RunService.Heartbeat:Connect(function()
		for plr in pairs(groupMembers) do
			if not plr.Parent then
				setGroupHighlight(plr, false); groupMembers[plr] = nil; refreshCount()
			else
				local hl = groupHighlights[plr]
				if hl then hl.Adornee = plr.Character end
			end
		end
	end)

	-- Radius add: "select all players within X studs" into the group.
	tgGroup:AddSlider("groupRadius", { Text = "Radius (studs)", Min = 5, Max = 500, Default = 60, Rounding = 0, Tooltip = "Range used by 'Add Players in Radius'. (Default: 60)" })
	tgGroup:AddButton("Add Players in Radius", function()
		local lchar = lPlayer.Character
		local lroot = lchar and (lchar:FindFirstChild("HumanoidRootPart") or lchar:FindFirstChild("Head"))
		if not lroot then Library:Notify("No character"); return end
		local r, added = Options.groupRadius.Value, 0
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lPlayer then
				local c = plr.Character
				local node = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
				if node and (node.Position - lroot.Position).Magnitude <= r and not groupMembers[plr] then
					groupMembers[plr] = true; setGroupHighlight(plr, true); added += 1
				end
			end
		end
		refreshCount()
		Library:Notify("Added " .. added .. " player(s) within " .. r .. " studs")
	end):AddToolTip("Add every player within the radius above to the target group.")

	-- ---- Silent Melee Aim --------------------------------------------------
	-- On swing / left-click, simulate a touch between your weapon's parts and the
	-- chosen target's parts via firetouchinterest, so the game's own server-side
	-- .Touched damage handler registers the hit. No hooks (rule #3) -- it's a direct
	-- API call. Works for tool melee and (no tool) bare-fist games via your arms.
	local smGroup = combatTab:AddRightGroupbox("Silent Melee")
	smGroup:AddToggle("silentMeleeEnabled", { Text = "Enable Silent Melee", Default = false, Tooltip = "On left-click, fire a touch between your weapon and the\nchosen target so the hit lands even if you aren't aiming at\nthem. Uses firetouchinterest (no hooks). (Default: OFF)" })
	smGroup:AddDropdown("silentMeleeMode", { Text = "Target Mode", AllowNull = false, Multi = false, Values = { "Closest to Crosshair", "Closest in Range", "Target Group" }, Default = "Closest to Crosshair", Tooltip = "How target(s) are chosen each swing. Target Group hits\neveryone in your drag/radius group within range. (Default: Closest to Crosshair)" })
	smGroup:AddSlider("silentMeleeRange", { Text = "Max Range (studs)", Min = 5, Max = 60, Default = 18, Rounding = 0, Tooltip = "Only hit targets within this distance (melee reach). (Default: 18)" })
	smGroup:AddSlider("silentMeleeFOV", { Text = "Crosshair FOV (px)", Min = 20, Max = 600, Default = 160, Rounding = 0, Tooltip = "For 'Closest to Crosshair': max screen distance from center. (Default: 160)" })
	smGroup:AddToggle("silentMeleeOnlyMelee", { Text = "Only Melee Weapons", Default = true, Tooltip = "Only fire while holding a melee weapon (per the Weapon Reader).\nOff = any tool / bare fists. (Default: ON)" })
	smGroup:AddToggle("silentMeleeAura", { Text = "Auto (Kill Aura)", Default = false, Tooltip = "Continuously hit targets in range while enabled, instead\nof only on click. (Default: OFF)" })
	smGroup:AddSlider("silentMeleeAuraRate", { Text = "Aura Rate (/s)", Min = 1, Max = 20, Default = 8, Rounding = 0, Tooltip = "How many times per second Kill Aura fires. (Default: 8)" })
	smGroup:AddToggle("silentMeleeIgnoreTeam", { Text = "Ignore Team", Default = true, Tooltip = "Never hit teammates. (Default: ON)" })
	smGroup:AddToggle("silentMeleeIgnoreWL", { Text = "Ignore Whitelisted", Default = true, Tooltip = "Never hit whitelisted players. (Default: ON)" })
	smGroup:AddToggle("silentMeleeCrosshair", { Text = "Crosshair on Shiftlock", Default = true, Tooltip = "Show an aim ring at screen center while shiftlocked;\nit turns green when a target is locked. (Default: ON)" })
	smGroup:AddToggle("silentMeleeWallPen", { Text = "Wall Penetration", Default = true, Tooltip = "MELEE-PEN: hit targets through walls/objects (touch ignores\nline-of-sight). Turn OFF to only hit targets you can actually\nsee (more legit). (Default: ON)" })
	smGroup:AddToggle("silentMeleeShieldBypass", { Text = "Shield Bypass", Default = true, Tooltip = "MELEE-PEN: skip the target's shield parts and land the touch\ndirectly on their body, so sword+shield blocks are bypassed.\nUses the keyword list + your registered shields. (Default: ON)" })
	local smInfo = smGroup:AddLabel("Lock: off")
	local smMech = smGroup:AddLabel("Damage: ?")

	-- Center aim ring (same DrawingFallback path as ESP).
	local smCross = DrawingFallback.new("Circle")
	smCross.Thickness = 2; smCross.Filled = false; smCross.NumSides = 32; smCross.Radius = 4; smCross.Visible = false

	-- ---- Shield registry (MELEE-PEN shield bypass) -------------------------
	-- Built-in keywords + a manual hold-pick so you can register an oddly-named
	-- shield model; registered names then match that shield on EVERY player as a
	-- fallback to the keyword list.
	local SHIELD_KEYWORDS = { "shield", "block", "guard", "parry", "defend", "buckler", "barrier" }
	local shieldGroup = combatTab:AddLeftGroupbox("Melee: Shields")
	shieldGroup:AddLabel("Register a shield model so Shield Bypass\ncan skip it on every player.", true)
	shieldGroup:AddDropdown("shieldNames", { Text = "Known Shields", AllowNull = true, Multi = true, Values = {}, Tooltip = "Part/model names treated as shields (besides the built-in\nkeywords). Use Pick Shield to add one. (Default: none)" })
	local function addShieldName(name)
		if not name or name == "" then return end
		local vals = Options.shieldNames.Values or {}
		if not table.find(vals, name) then
			table.insert(vals, name); Options.shieldNames.Values = vals; Options.shieldNames:SetValues()
		end
		pcall(function()
			local sel = Options.shieldNames.Value
			if type(sel) == "table" then sel[name] = true; Options.shieldNames:SetValue(sel) end
		end)
	end
	shieldGroup:AddButton("Pick Shield (hold-click)", function()
		Bridge:StartHoldPick({ color = Color3.fromRGB(80, 160, 255), onPick = function(part)
			addShieldName(part.Name)
			local model = part:FindFirstAncestorWhichIsA("Model")
			if model and model ~= part and model ~= Workspace then addShieldName(model.Name) end
			Library:Notify("Registered shield: " .. part.Name)
		end })
	end):AddToolTip("Hold left-click on a shield to register its name as a shield for ALL players.")
	shieldGroup:AddButton("Clear Shields", function()
		Options.shieldNames.Values = {}; Options.shieldNames:SetValues(); pcall(function() Options.shieldNames:SetValue({}) end)
		Library:Notify("Cleared registered shields")
	end):AddToolTip("Forget every registered shield name.")

	local function isShieldName(name)
		local low = name:lower()
		for _, kw in ipairs(SHIELD_KEYWORDS) do if low:find(kw) then return true end end
		if Options.shieldNames then
			for _, n in ipairs(Options.shieldNames:GetActiveValues()) do if name == n then return true end end
		end
		return false
	end
	local function isShieldPart(part)
		if isShieldName(part.Name) then return true end
		local p, hops = part.Parent, 0
		while p and hops < 4 do
			if isShieldName(p.Name) then return true end
			p = p.Parent; hops += 1
		end
		return false
	end
	-- Line-of-sight test (used when Wall Penetration is OFF): true if nothing solid
	-- sits between you and the target part (the target's own character is ignored).
	local function hasLOS(fromPos, toPart)
		local ok, clear = pcall(function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { lPlayer.Character, toPart.Parent }
			local res = Workspace:Raycast(fromPos, toPart.Position - fromPos, params)
			return res == nil
		end)
		return ok and clear or false
	end

	local function meleeTeammate(plr)
		local ok, same = pcall(function()
			if lPlayer.Team ~= nil or plr.Team ~= nil then return lPlayer.Team == plr.Team end
			return lPlayer.TeamColor == plr.TeamColor
		end)
		return ok and same or false
	end
	local function meleeValid(plr)
		if plr == lPlayer then return false end
		local c = plr.Character
		local hum = c and c:FindFirstChildWhichIsA("Humanoid")
		if not (c and hum and hum.Health > 0) then return false end
		if Toggles.silentMeleeIgnoreWL.Value and Options.whitelistPlayerList and table.find(Options.whitelistPlayerList:GetActiveValues(), plr.Name) then return false end
		if Toggles.silentMeleeIgnoreTeam.Value and meleeTeammate(plr) then return false end
		return true
	end
	local function localRoot()
		local c = lPlayer.Character
		return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
	end
	local function pickMeleeTarget()
		local cam = Workspace.CurrentCamera
		local lroot = localRoot()
		if not lroot then return nil end
		local mode = Options.silentMeleeMode.Value
		local maxR = Options.silentMeleeRange.Value
		local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
		local fov = Options.silentMeleeFOV.Value
		local best, bestScore = nil, math.huge
		for _, plr in ipairs(Players:GetPlayers()) do
			if meleeValid(plr) then
				local c = plr.Character
				local node = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")
				if node then
					local d3 = (node.Position - lroot.Position).Magnitude
					-- Wall Penetration OFF => require clear line of sight to the target.
					local losOK = (Toggles.silentMeleeWallPen and Toggles.silentMeleeWallPen.Value) or hasLOS(lroot.Position, node)
					if d3 <= maxR and losOK then
						if mode == "Closest in Range" then
							if d3 < bestScore then best, bestScore = plr, d3 end
						else  -- Closest to Crosshair
							local sp, on = cam:WorldToViewportPoint(node.Position)
							if on then
								local d2 = (Vector2.new(sp.X, sp.Y) - center).Magnitude
								if d2 <= fov and d2 < bestScore then best, bestScore = plr, d2 end
							end
						end
					end
				end
			end
		end
		return best
	end
	-- Your weapon's parts: the held tool's baseparts, or (no tool) your arms/hands.
	local function weaponHitParts()
		local c = lPlayer.Character
		if not c then return {} end
		local tool
		for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") then tool = t break end end
		local parts = {}
		if tool then
			for _, d in ipairs(tool:GetDescendants()) do if d:IsA("BasePart") then parts[#parts + 1] = d end end
		else
			for _, n in ipairs({ "Right Arm", "RightHand", "RightLowerArm", "Left Arm", "LeftHand" }) do
				local p = c:FindFirstChild(n); if p and p:IsA("BasePart") then parts[#parts + 1] = p end
			end
		end
		return parts
	end
	local function fireMeleeAt(plr)
		local char = plr.Character
		if not char then return false end
		local wParts = weaponHitParts()
		local bypass = Toggles.silentMeleeShieldBypass and Toggles.silentMeleeShieldBypass.Value
		-- Target parts = body parts; when Shield Bypass is on, skip shield parts so
		-- the touch lands on the body instead of being intercepted by the shield.
		local tParts = {}
		for _, tp in ipairs(char:GetChildren()) do
			if tp:IsA("BasePart") and not (bypass and isShieldPart(tp)) then tParts[#tParts + 1] = tp end
		end
		for _, wp in ipairs(wParts) do
			for _, tp in ipairs(tParts) do
				-- Primary: simulate the touch so the game's own .Touched handler runs.
				if firetouchinterest then
					pcall(function() firetouchinterest(wp, tp, 0); firetouchinterest(wp, tp, 1) end)
				end
				-- Reliability boost (confidence): also directly :Fire() the weapon
				-- part's Touched connections with the target part, which invokes the
				-- game's damage handler even when firetouchinterest alone doesn't take.
				if getconnections then
					pcall(function()
						for _, conn in ipairs(getconnections(wp.Touched)) do
							if conn.Fire then conn:Fire(tp) end
						end
					end)
				end
			end
		end
		return true
	end
	local function meleeGatePasses()
		if not (Toggles.silentMeleeEnabled and Toggles.silentMeleeEnabled.Value) then return false end
		if Toggles.silentMeleeOnlyMelee.Value then
			local t = currentTool()
			if not t or not classify(t):find("Melee") then return false end
		end
		return true
	end
	-- Confidence aids: mechanism detector + live hit confirmation.
	local pendingHit = nil      -- { plr, hp, t } armed after a single-target swing
	local smLastConfirm = 0     -- tick() of the last confirmed HP drop
	-- Does the held weapon expose .Touched connections? If so the touch path will
	-- land; if not, it's likely a remote/raycast game and Silent Melee can't help.
	local function detectMechanism()
		if not getconnections then return "Damage: unknown (no getconnections)" end
		local n = 0
		for _, wp in ipairs(weaponHitParts()) do
			local ok, conns = pcall(function() return getconnections(wp.Touched) end)
			if ok and conns then n = n + #conns end
		end
		return n > 0 and "Damage: Touch-based detected" or "Damage: no touch conns (remote?)"
	end
	local function doMeleeSwing()
		if not meleeGatePasses() then return end
		if not firetouchinterest and not getconnections then
			Library:Notify("Executor lacks firetouchinterest/getconnections"); return
		end
		if Options.silentMeleeMode.Value == "Target Group" then
			local lroot = localRoot()
			local maxR = Options.silentMeleeRange.Value
			for plr in pairs(groupMembers) do
				if meleeValid(plr) then
					local c = plr.Character
					local node = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
					if node and lroot and (node.Position - lroot.Position).Magnitude <= maxR then
						fireMeleeAt(plr)
					end
				end
			end
		else
			local target = pickMeleeTarget()
			if target then
				fireMeleeAt(target)
				-- Arm hit-confirmation for the single target so we can prove it landed.
				local hum = target.Character and target.Character:FindFirstChildWhichIsA("Humanoid")
				if hum then pendingHit = { plr = target, hp = hum.Health, t = tick() } end
			end
		end
	end

	-- Click trigger (the swing). gameProcessed filters out menu clicks.
	local smClickConn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then pcall(doMeleeSwing) end
	end)
	-- Optional kill-aura loop.
	local smAuraLast = 0
	local smAuraConn = RunService.Heartbeat:Connect(function()
		if not (Toggles.silentMeleeAura and Toggles.silentMeleeAura.Value) then return end
		if not meleeGatePasses() then return end
		local now = tick()
		local rate = (Options.silentMeleeAuraRate and Options.silentMeleeAuraRate.Value) or 8
		if now - smAuraLast < (1 / math.max(1, rate)) then return end
		smAuraLast = now
		pcall(doMeleeSwing)
	end)
	-- Crosshair + lock readout (one scan/frame; label throttled).
	local smLastInfo = 0
	local smLockCache, smLockT = nil, 0
	local smCrossConn = RunService.RenderStepped:Connect(function()
		local enabled = Toggles.silentMeleeEnabled and Toggles.silentMeleeEnabled.Value
		local locked = nil
		if enabled and Options.silentMeleeMode.Value ~= "Target Group" then
			-- Throttle the target scan to ~12 Hz (full player loop + LOS raycast is
			-- expensive); the crosshair itself still follows every frame. (perf)
			local now = tick()
			if now - smLockT > 0.08 then
				smLockT = now
				local ok, res = pcall(pickMeleeTarget); smLockCache = ok and res or nil
			end
			locked = smLockCache
		end
		local show = enabled and Toggles.silentMeleeCrosshair and Toggles.silentMeleeCrosshair.Value
			and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		if show then
			local cam = Workspace.CurrentCamera
			smCross.Position = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
			smCross.Color = locked and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 255, 255)
			smCross.Visible = true
		else
			smCross.Visible = false
		end
		local now = tick()
		-- Hit confirmation: did the pending single-target lose HP shortly after a swing?
		if pendingHit then
			local c = pendingHit.plr and pendingHit.plr.Character
			local hum = c and c:FindFirstChildWhichIsA("Humanoid")
			if hum and hum.Health < pendingHit.hp - 0.01 then
				smLastConfirm = now; pendingHit = nil
			elseif now - pendingHit.t > 0.9 then
				pendingHit = nil
			end
		end
		if now - smLastInfo > 0.2 then
			smLastInfo = now
			pcall(function() smInfo:SetText(enabled and ("Lock: " .. (locked and locked.Name or "none")) or "Lock: off") end)
			-- Mechanism + recent-hit readout (confidence aid).
			local mech = enabled and detectMechanism() or "Damage: ?"
			if now - smLastConfirm < 2 then mech = "Hit confirmed (HP dropped)" end
			pcall(function() smMech:SetText(mech) end)
		end
	end)

	-- ---- Tool Hitbox Editor (TOOL-RESIZE + TOOL-VIZ) -----------------------
	-- btools-style 3D resize: a native Handles gizmo (drag faces to resize) plus a
	-- green SelectionBox showing the hitbox extent. The tool's actual visual (a mesh
	-- on the Handle) is unaffected because we only change the BasePart Size, so the
	-- original look stays while the hitbox grows; the edited part is kept non-
	-- collidable + CanTouch so it still does touch-damage over the bigger area.
	local teGroup = combatTab:AddLeftGroupbox("Tool Hitbox Editor")
	local FACE_AXIS = {
		[Enum.NormalId.Right] = Vector3.new(1, 0, 0), [Enum.NormalId.Left] = Vector3.new(1, 0, 0),
		[Enum.NormalId.Top] = Vector3.new(0, 1, 0), [Enum.NormalId.Bottom] = Vector3.new(0, 1, 0),
		[Enum.NormalId.Front] = Vector3.new(0, 0, 1), [Enum.NormalId.Back] = Vector3.new(0, 0, 1),
	}
	local tePart, teOrigSize, teSelBox, teHandles = nil, nil, nil, nil
	-- Handles need a rendering ScreenGui (PlayerGui is the most reliable parent).
	local teGui = Instance.new("ScreenGui")
	teGui.Name = "FurryHBE_ToolEdit"; teGui.ResetOnSpawn = false
	teGui.Parent = (lPlayer:FindFirstChildOfClass("PlayerGui")) or getSafeGuiParent()
	local teInfo = teGroup:AddLabel("Editing: none")

	local function teClearVisuals()
		if teSelBox then pcall(function() teSelBox:Destroy() end); teSelBox = nil end
		if teHandles then pcall(function() teHandles:Destroy() end); teHandles = nil end
	end
	local function teEdit(part)
		if not (part and part:IsA("BasePart")) then return end
		teClearVisuals()
		tePart, teOrigSize = part, part.Size
		-- TOOL-VIZ: green box showing the hitbox (mesh visual stays its own size/colour).
		teSelBox = Instance.new("SelectionBox")
		teSelBox.Adornee = part; teSelBox.Color3 = Color3.fromRGB(0, 255, 0)
		teSelBox.LineThickness = 0.03; teSelBox.SurfaceColor3 = Color3.fromRGB(0, 255, 0)
		teSelBox.SurfaceTransparency = 0.85; teSelBox.Parent = teGui
		-- TOOL-RESIZE: native btools-style resize handles.
		teHandles = Instance.new("Handles")
		teHandles.Adornee = part; teHandles.Style = Enum.HandlesStyle.Resize
		teHandles.Color3 = Color3.fromRGB(0, 200, 0); teHandles.Parent = teGui
		local startSize
		teHandles.MouseButton1Down:Connect(function() startSize = tePart and tePart.Size end)
		teHandles.MouseDrag:Connect(function(face, distance)
			if not (tePart and tePart.Parent and startSize) then return end
			local axis = FACE_AXIS[face] or Vector3.new(0, 0, 0)
			local ns = startSize + axis * distance
			tePart.Size = Vector3.new(math.max(0.05, ns.X), math.max(0.05, ns.Y), math.max(0.05, ns.Z))
			pcall(function() tePart.CanCollide = false; tePart.CanTouch = true; tePart.Massless = true end)
			pcall(function()
				Options.teSizeX:SetValue(tePart.Size.X); Options.teSizeY:SetValue(tePart.Size.Y); Options.teSizeZ:SetValue(tePart.Size.Z)
			end)
		end)
		local tool = part:FindFirstAncestorWhichIsA("Tool")
		teInfo:SetText("Editing: " .. (tool and tool.Name or part.Name))
		pcall(function()
			Options.teSizeX:SetValue(part.Size.X); Options.teSizeY:SetValue(part.Size.Y); Options.teSizeZ:SetValue(part.Size.Z)
		end)
	end
	local function teHeldHitPart()
		local c = lPlayer.Character
		if not c then return nil end
		for _, t in ipairs(c:GetChildren()) do
			if t:IsA("Tool") then
				return t:FindFirstChild("Handle") or t:FindFirstChildWhichIsA("BasePart")
			end
		end
		return nil
	end

	teGroup:AddButton("Edit Held Weapon", function()
		local p = teHeldHitPart()
		if p then teEdit(p) else Library:Notify("Equip a tool first") end
	end):AddToolTip("Adorn resize handles + a green box to your equipped tool's hitbox.")
	teGroup:AddButton("Edit Picked Part (hold-click)", function()
		Bridge:StartHoldPick({ color = Color3.fromRGB(0, 255, 0), onPick = function(part) teEdit(part) end })
	end):AddToolTip("Hold-click any part to edit its hitbox with the handles.")
	teGroup:AddSlider("teSizeX", { Text = "Size X", Min = 0.1, Max = 100, Default = 1, Rounding = 2 }):OnChanged(function()
		if tePart and tePart.Parent then pcall(function() tePart.Size = Vector3.new(Options.teSizeX.Value, tePart.Size.Y, tePart.Size.Z) end) end
	end)
	teGroup:AddSlider("teSizeY", { Text = "Size Y", Min = 0.1, Max = 100, Default = 1, Rounding = 2 }):OnChanged(function()
		if tePart and tePart.Parent then pcall(function() tePart.Size = Vector3.new(tePart.Size.X, Options.teSizeY.Value, tePart.Size.Z) end) end
	end)
	teGroup:AddSlider("teSizeZ", { Text = "Size Z", Min = 0.1, Max = 100, Default = 1, Rounding = 2 }):OnChanged(function()
		if tePart and tePart.Parent then pcall(function() tePart.Size = Vector3.new(tePart.Size.X, tePart.Size.Y, Options.teSizeZ.Value) end) end
	end)
	teGroup:AddButton("Reset to Original", function()
		if tePart and tePart.Parent and teOrigSize then pcall(function() tePart.Size = teOrigSize end) end
	end):AddToolTip("Restore the edited part to the size it had when you started editing.")
	teGroup:AddButton("Stop Editing (keep size)", function()
		teClearVisuals(); tePart = nil; teInfo:SetText("Editing: none")
	end):AddToolTip("Remove the handles/box but keep the current hitbox size.")

	Bridge:RegisterAddon("CombatTab", { onUnload = function()
		pcall(function() wrConn:Disconnect() end)
		pcall(function() cBegan:Disconnect() end)
		pcall(function() cChanged:Disconnect() end)
		pcall(function() cEnded:Disconnect() end)
		pcall(function() tgConn:Disconnect() end)
		pcall(function() smClickConn:Disconnect() end)
		pcall(function() smAuraConn:Disconnect() end)
		pcall(function() smCrossConn:Disconnect() end)
		safeRemoveDrawing(smCross)
		for plr in pairs(groupMembers) do setGroupHighlight(plr, false) end
		pcall(function() selGui:Destroy() end)
		pcall(function() if tePart and tePart.Parent and teOrigSize then tePart.Size = teOrigSize end end)
		teClearVisuals(); pcall(function() teGui:Destroy() end)
	end })
	print("[Combat] Weapon Reader + Target Groups + Silent Melee registered")
end)

-- ===== [V10] F10 Extract / Calibrate Game ==================================
-- Heuristic best-effort scanner: fingerprints the current place and auto-detects
-- character part names (custom/rthro rigs), gun tools (for Inf-Ammo), shields, the
-- melee damage mechanism, vehicles and teams; applies what it finds to the relevant
-- lists and can save/load the profile per PlaceId (a shareable game profile that
-- also auto-loads on startup). All pcall-isolated; cross-module Options are nil-guarded.
pcall(function()
	local HttpService = game:GetService("HttpService")
	local calTab      = mainWindow:AddTab("Calibrate")
	local scanGroup   = calTab:AddLeftGroupbox("Game Profile / Extract")
	local reportGroup = calTab:AddRightGroupbox("Last Scan Report")
	local CAL_FILE    = "FurryHBE_Calibrate_" .. tostring(game.PlaceId) .. ".json"

	scanGroup:AddLabel("Place: " .. tostring(game.PlaceId), true)
	scanGroup:AddToggle("calApplyParts",  { Text = "Auto-Add Character Parts", Default = true,  Tooltip = "Add detected non-standard character part names to the HBE\npart list and select them. (Default: ON)" })
	scanGroup:AddToggle("calApplyAmmo",    { Text = "Auto-Add Guns to Inf-Ammo", Default = true, Tooltip = "Add detected gun tools to the Inf-Ammo gun list. (Default: ON)" })
	scanGroup:AddToggle("calApplyShields", { Text = "Auto-Register Shields", Default = false, Tooltip = "Add detected shield parts to the Melee shield list. (Default: OFF)" })

	local reportLabel = reportGroup:AddLabel("Run 'Scan & Extract' to fingerprint this game.", true)

	local STD_PARTS = { Head = true, HumanoidRootPart = true, Torso = true, UpperTorso = true, LowerTorso = true,
		["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
		LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
		LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true }
	local AMMO_WORDS   = { "ammo", "mag", "clip", "round", "reserve", "bullet" }
	local GUN_WORDS    = { "gun", "rifle", "pistol", "smg", "shotgun", "sniper", "ak", "glock", "launcher", "uzi", "deagle", "carbine", "revolver" }
	local SHIELD_WORDS = { "shield", "buckler", "barrier" }
	local function nameHas(n, words) n = n:lower() for _, w in ipairs(words) do if n:find(w) then return true end end return false end

	-- Add a name to a LinoriaLib multi-dropdown's Values (and optionally select it).
	local function addToDropdown(opt, name, select)
		if not opt or not name or name == "" then return end
		local vals = opt.Values or {}
		if not table.find(vals, name) then table.insert(vals, name); opt.Values = vals; pcall(function() opt:SetValues() end) end
		if select then pcall(function() local s = opt.Value; if type(s) == "table" then s[name] = true; opt:SetValue(s) end end) end
	end

	-- Prefer another player's full character as the rig sample; fall back to ours.
	local function sampleCharacter()
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lPlayer and p.Character and p.Character:FindFirstChildWhichIsA("Humanoid") then return p.Character end
		end
		return lPlayer.Character
	end

	-- ===== Tier 2: framework fingerprinting ==============================
	-- Build a name index of the key containers once, then test known framework
	-- signatures against it. Identifying the engine lets the right adapter load
	-- (we already adapt A-Chassis vehicles). Exposed on Bridge.Calibrate.
	Bridge.Calibrate = Bridge.Calibrate or {}
	local FRAMEWORKS = {
		{ name = "A-Chassis (vehicles)", any = { "A-Chassis Tune", "AChassisTune" } },
		{ name = "ACS (guns)",           any = { "ACS_Engine", "ACS_Storage", "ACS_Client", "ACS_Server", "ACS_Tools" } },
		{ name = "FE Gun Kit (guns)",    any = { "GunStates", "FAS", "GunValue", "MainModuleFE" } },
		{ name = "Adonis Admin",         any = { "Adonis", "Adonis_Loader" } },
		{ name = "HD Admin",             any = { "HDAdminMain", "HDAdminClient", "HDAdminServer" } },
		{ name = "Kohl's Admin",         any = { "KAdmin", "Kohls" } },
		{ name = "Basic Admin",          any = { "BasicAdmin", "Basic Admin Essentials" } },
		{ name = "Linked Sword combat",  any = { "LinkedSword" } },
		{ name = "Generic combat svc",   any = { "CombatService", "DamageService", "WeaponService" } },
		{ name = "Round system",         any = { "RoundSystem", "GameManager", "MatchService" } },
	}
	local function buildNameIndex()
		local idx, count = {}, 0
		local conts = { game:GetService("ReplicatedStorage"), Workspace, game:GetService("ReplicatedFirst"), lPlayer:FindFirstChild("PlayerScripts") }
		for _, c in ipairs(conts) do
			if c then
				pcall(function()
					for _, d in ipairs(c:GetDescendants()) do
						count = count + 1; if count > 60000 then break end
						idx[d.Name] = true
					end
				end)
			end
		end
		return idx
	end
	local function detectFrameworks()
		local idx = buildNameIndex()
		local found = {}
		for _, fw in ipairs(FRAMEWORKS) do
			for _, sig in ipairs(fw.any) do
				if idx[sig] then found[#found + 1] = fw.name; break end
			end
		end
		Bridge.Calibrate.frameworks = found
		Bridge.Calibrate.framework = found[1]
		return found
	end

	local function runScan(apply)
		local r = {}

		-- 0) framework fingerprint (Tier 2)
		local fws = detectFrameworks()
		r[#r + 1] = "Framework: " .. (#fws > 0 and table.concat(fws, ", ") or "none/custom")

		-- 1) character parts (rig parts, skipping accessories/tool handles)
		local char = sampleCharacter()
		local partNames, nonStd = {}, {}
		if char then
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "Handle"
					and not d:FindFirstAncestorWhichIsA("Accessory") and not d:FindFirstAncestorWhichIsA("Tool") then
					partNames[d.Name] = true
					if not STD_PARTS[d.Name] then nonStd[d.Name] = true end
				end
			end
		end
		local pc, nc = 0, 0
		for _ in pairs(partNames) do pc = pc + 1 end
		local nonStdList = {}
		for n in pairs(nonStd) do
			nc = nc + 1; nonStdList[#nonStdList + 1] = n
			if apply and Toggles.calApplyParts.Value then addToDropdown(Options.extenderPartList, n, true) end
		end
		r[#r + 1] = ("Parts: %d total, %d non-standard"):format(pc, nc)
		if nc > 0 then r[#r + 1] = "  + " .. table.concat(nonStdList, ", ") end

		-- 2) guns / ammo (held + backpack tools)
		local guns, ammoVals = {}, 0
		for _, cont in ipairs({ lPlayer.Character, lPlayer:FindFirstChild("Backpack") }) do
			if cont then
				for _, t in ipairs(cont:GetChildren()) do
					if t:IsA("Tool") then
						local isGun = nameHas(t.Name, GUN_WORDS)
						for _, d in ipairs(t:GetDescendants()) do
							if (d:IsA("IntValue") or d:IsA("NumberValue")) and nameHas(d.Name, AMMO_WORDS) then ammoVals = ammoVals + 1; isGun = true end
						end
						if isGun then guns[t.Name] = true end
					end
				end
			end
		end
		local gc = 0
		for n in pairs(guns) do gc = gc + 1; if apply and Toggles.calApplyAmmo.Value then addToDropdown(Options.infAmmoGuns, n, true) end end
		r[#r + 1] = ("Guns: %d detected, %d ammo-values"):format(gc, ammoVals)

		-- 3) shields
		local shields = {}
		if char then
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") and nameHas(d.Name, SHIELD_WORDS) then shields[d.Name] = true end
			end
		end
		local sc = 0
		for n in pairs(shields) do sc = sc + 1; if apply and Toggles.calApplyShields.Value then addToDropdown(Options.shieldNames, n, true) end end
		r[#r + 1] = ("Shields: %d detected"):format(sc)

		-- 4) vehicles + teams (one workspace pass; pcall'd in case it's huge)
		local vseats, seats = 0, 0
		pcall(function()
			for _, d in ipairs(Workspace:GetDescendants()) do
				if d:IsA("VehicleSeat") then vseats = vseats + 1 elseif d:IsA("Seat") then seats = seats + 1 end
			end
		end)
		r[#r + 1] = ("Vehicles: %d VehicleSeats, %d Seats"):format(vseats, seats)
		local teams = 0
		pcall(function() teams = #game:GetService("Teams"):GetChildren() end)
		r[#r + 1] = ("Teams: %d"):format(teams)
		-- RemoteEvent count: hints whether damage is remote-driven (-> Remote Replay).
		local remotes = 0
		pcall(function()
			for _, d in ipairs(game:GetDescendants()) do if d:IsA("RemoteEvent") then remotes = remotes + 1; if remotes > 4000 then break end end end
		end)
		r[#r + 1] = ("RemoteEvents: %d"):format(remotes)

		-- 5) melee damage mechanism (held tool / arm .Touched connection count)
		local mech = "unknown (no getconnections)"
		if getconnections then
			local n, probe = 0, {}
			local c = lPlayer.Character
			if c then
				local tool
				for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") then tool = t break end end
				if tool then
					for _, d in ipairs(tool:GetDescendants()) do if d:IsA("BasePart") then probe[#probe + 1] = d end end
				else
					local rh = c:FindFirstChild("Right Arm") or c:FindFirstChild("RightHand")
					if rh then probe[1] = rh end
				end
			end
			for _, wp in ipairs(probe) do
				local ok, conns = pcall(function() return getconnections(wp.Touched) end)
				if ok and conns then n = n + #conns end
			end
			mech = n > 0 and ("touch-based (" .. n .. " conns) -> Silent Melee OK") or "no touch conns (remote/raycast?)"
		end
		r[#r + 1] = "Melee dmg: " .. mech

		-- Gun/recoil system: count recoil/spread values on the held tool so you know
		-- if No-Recoil/Aimbot have something to work with in this game. (intelligence)
		local recoilN, isGun = 0, false
		pcall(function()
			local c = lPlayer.Character
			local tool = c and c:FindFirstChildWhichIsA("Tool")
			if tool then
				isGun = nameHas(tool.Name, GUN_WORDS)
				for _, d in ipairs(tool:GetDescendants()) do
					if d:IsA("NumberValue") or d:IsA("IntValue") then
						local n = d.Name:lower()
						for _, w in ipairs({ "recoil", "spread", "kick", "bloom", "sway" }) do if n:find(w) then recoilN = recoilN + 1; break end end
					end
				end
			end
		end)
		r[#r + 1] = ("Gun: %s, recoil values: %d"):format(isGun and "yes" or "no/none held", recoilN)

		pcall(function() reportLabel:SetText(table.concat(r, "\n")) end)
		-- Expose results so any module can read the calibration (Tier 1+2 engine).
		Bridge.Calibrate.parts, Bridge.Calibrate.guns, Bridge.Calibrate.shields = nonStd, guns, shields
		Bridge.Calibrate.report = r
		Bridge.Calibrate.lastScan = tick()
		return { parts = nonStd, guns = guns, shields = shields }
	end

	-- ---- save / load the extracted profile (per PlaceId) ----
	local function keysOf(t) local o = {} for k in pairs(t) do o[#o + 1] = k end return o end
	local function saveProfile(data)
		if not writefile then Library:Notify("Executor has no writefile"); return end
		pcall(function()
			writefile(CAL_FILE, HttpService:JSONEncode({ parts = keysOf(data.parts), guns = keysOf(data.guns), shields = keysOf(data.shields) }))
		end)
		Library:Notify("Saved profile for PlaceId " .. tostring(game.PlaceId))
	end
	local function loadProfile(notify)
		if not (isfile and readfile and isfile(CAL_FILE)) then if notify then Library:Notify("No saved profile for this game") end return end
		local ok, d = pcall(function() return HttpService:JSONDecode(readfile(CAL_FILE)) end)
		if not (ok and type(d) == "table") then if notify then Library:Notify("Saved profile unreadable") end return end
		for _, n in ipairs(d.parts or {}) do addToDropdown(Options.extenderPartList, n, true) end
		for _, n in ipairs(d.guns or {}) do addToDropdown(Options.infAmmoGuns, n, true) end
		for _, n in ipairs(d.shields or {}) do addToDropdown(Options.shieldNames, n, true) end
		if notify then Library:Notify("Loaded saved game profile") end
	end

	scanGroup:AddButton("Scan & Extract", function()
		runScan(true); Library:Notify("Scan complete - see report")
	end):AddToolTip("Fingerprint this game and auto-apply detected parts/guns/shields per the toggles above.")
	scanGroup:AddButton("Scan Only (no apply)", function()
		runScan(false); Library:Notify("Scan complete (report only)")
	end):AddToolTip("Show what would be detected without changing any lists.")
	scanGroup:AddButton("Save Profile", function()
		saveProfile(runScan(false))
	end):AddToolTip("Write the extracted profile to disk for this game (PlaceId).")
	scanGroup:AddButton("Load Profile", function() loadProfile(true) end):AddToolTip("Re-apply the saved profile for this game.")

	-- #6: shareable profile strings (export to clipboard / import a pasted string).
	local function profileToStr(data)
		local json = HttpService:JSONEncode({ parts = keysOf(data.parts), guns = keysOf(data.guns), shields = keysOf(data.shields) })
		if crypt and crypt.base64encode then local ok, e = pcall(function() return crypt.base64encode(json) end); if ok and e then return e end end
		return json
	end
	local function strToProfile(s)
		if not s or s == "" then return nil end
		local txt = s
		if crypt and crypt.base64decode then local ok, dec = pcall(function() return crypt.base64decode(s) end); if ok and dec then txt = dec end end
		local ok, d = pcall(function() return HttpService:JSONDecode(txt) end)
		return (ok and type(d) == "table") and d or nil
	end
	local function applyProfile(d)
		if not d then return false end
		for _, n in ipairs(d.parts or {}) do addToDropdown(Options.extenderPartList, n, true) end
		for _, n in ipairs(d.guns or {}) do addToDropdown(Options.infAmmoGuns, n, true) end
		for _, n in ipairs(d.shields or {}) do addToDropdown(Options.shieldNames, n, true) end
		return true
	end
	scanGroup:AddInput("calProfileStr", { Text = "Profile String", Default = "", Tooltip = "Paste a shared profile string here, then Import." })
	scanGroup:AddButton("Export Profile -> Clipboard", function()
		local s = profileToStr(runScan(false))
		pcall(function() if setclipboard then setclipboard(s) end end)
		pcall(function() Options.calProfileStr:SetValue(s) end)
		Library:Notify("Profile copied to clipboard")
	end):AddToolTip("Encode this game's detected profile to a shareable string (also copied to clipboard).")
	scanGroup:AddButton("Import Profile (from string)", function()
		if applyProfile(strToProfile(Options.calProfileStr.Value)) then Library:Notify("Imported profile") else Library:Notify("Invalid profile string") end
	end):AddToolTip("Apply a profile from the pasted string above.")

	-- ===== Tier 3: behavioral learning engine ===========================
	-- Snapshot every numeric value/attribute on you + your character, you perform an
	-- action (shoot / take damage / earn), then Analyze diffs the snapshot to surface
	-- the fields that changed -- finding ammo/health/currency/recoil WITHOUT knowing
	-- their names (defeats obfuscated games). Generalizes the Inf-Ammo learner.
	local learnGroup = calTab:AddRightGroupbox("Learn (Tier 3)")
	learnGroup:AddLabel("Snapshot -> do an action (shoot / take damage /\nearn) -> Analyze. Finds the values that changed.", true)
	learnGroup:AddDropdown("learnFilter", { Text = "Show", Values = { "Decreased (ammo/health/spent)", "Increased (currency/score)", "Any change" }, Default = "Any change", Multi = false, AllowNull = false })
	local learnInfo = learnGroup:AddLabel("Snapshot to begin.")

	local function collectFields()
		local fields = {}
		local function scan(root)
			if not root then return end
			local ok = pcall(function()
				local n = 0
				for _, d in ipairs(root:GetDescendants()) do
					n = n + 1; if n > 40000 then break end
					if d:IsA("NumberValue") or d:IsA("IntValue") then
						fields[#fields + 1] = { label = d.Name, get = function() return d.Value end }
					else
						pcall(function()
							for an, av in pairs(d:GetAttributes()) do
								if type(av) == "number" then fields[#fields + 1] = { label = d.Name .. "@" .. an, get = function() return d:GetAttribute(an) end } end
							end
						end)
					end
				end
			end)
		end
		scan(lPlayer); scan(lPlayer.Character)
		return fields
	end
	local snap = {}
	local function snapshotNow()
		snap = {}
		for _, f in ipairs(collectFields()) do snap[#snap + 1] = { label = f.label, get = f.get, v0 = f.get() } end
		pcall(function() learnInfo:SetText("Snapshot: " .. #snap .. " values.\nDo the action, then Analyze.") end)
	end
	local function analyze()
		local filter = Options.learnFilter.Value
		local results = {}
		for _, s in ipairs(snap) do
			local now = s.get()
			if type(now) == "number" and type(s.v0) == "number" and now ~= s.v0 then
				local delta = now - s.v0
				local keep = (filter == "Any change") or (filter:find("Decreased") and delta < 0) or (filter:find("Increased") and delta > 0)
				if keep then results[#results + 1] = { label = s.label, delta = delta } end
			end
		end
		table.sort(results, function(a, b) return math.abs(a.delta) > math.abs(b.delta) end)
		local lines = { #results .. " value(s) changed:" }
		for i = 1, math.min(6, #results) do lines[#lines + 1] = ("%s  %+g"):format(results[i].label, results[i].delta) end
		pcall(function() learnInfo:SetText(table.concat(lines, "\n")) end)
		Bridge.Calibrate.learned = results
	end
	learnGroup:AddButton("Snapshot", snapshotNow):AddToolTip("Capture every numeric value on you + your character.")
	learnGroup:AddButton("Analyze", analyze):AddToolTip("Diff against the snapshot and list what changed.")
	learnGroup:AddButton("Top -> Inf-Ammo Name", function()
		if Bridge.Calibrate.learned and Bridge.Calibrate.learned[1] and Options.infAmmoManualName then
			local nm = Bridge.Calibrate.learned[1].label:gsub("@.*$", "")
			pcall(function() Options.infAmmoManualName:SetValue(nm) end)
			Library:Notify("Inf-Ammo manual name -> " .. nm)
		else
			Library:Notify("Analyze first")
		end
	end):AddToolTip("Feed the biggest-changed value's name into Inf-Ammo's manual detector.")

	-- ===== Tier 4: Phantom Recon (read-only AC + combat introspection) ====
	-- THE PRINCIPLE: never test the alarm by tripping it -- read the wiring diagram.
	-- A game-level anti-cheat is just Lua. We READ its environment + bytecode
	-- constants + connections (pure reflection) to learn exactly which values /
	-- remotes / actions it watches. Reflection is invisible to game Lua -- there's no
	-- callback for "someone read my upvalues" -- so the probe never writes, never
	-- fires, never hooks: there is nothing for the AC to register. We then publish a
	-- "minefield map" (honeypots to avoid, values it watches) on Bridge.DeepScan so
	-- every other feature steers around it. (Defeats dev-written Lua anti-cheats; it
	-- does NOT touch Roblox's binary anti-tamper -- that's a separate layer.)
	local dsGroup = calTab:AddRightGroupbox("Phantom Recon (Tier 4)")
	dsGroup:AddToggle("deepScanEnabled", { Text = "Enable Deep Scan", Default = false, Tooltip = "ADVANCED / opt-in. Read-only reflection of the game's scripts +\nmemory (getsenv/getscriptclosure/getconstants/getnilinstances).\nMore detectable at the executor level than other tiers, so it's\noff by default and runs nothing until you press the button." })
	local dsInfo = dsGroup:AddLabel("Deep Scan off.")
	Bridge.DeepScan = Bridge.DeepScan or { acActive = false, watched = {}, avoid = {}, hotProps = {} }

	local AC_SIGS = { "anticheat", "anti-cheat", "antiexploit", "anti_exploit", "anti exploit", "exploitdetect",
		"cheatdetect", "detection", "sentinel", "guardian", "kicklog", "flagged", "watchdog", "integritycheck", "antiaim" }
	local MONITORED_PROPS = { "WalkSpeed", "JumpPower", "JumpHeight", "Health", "MaxHealth", "HipHeight", "Speed", "Gravity" }
	local function acSig(name)
		local ln = tostring(name):lower()
		for _, s in ipairs(AC_SIGS) do if ln:find(s, 1, true) then return s end end
		return nil
	end

	-- Stage 1: fingerprint AC scripts/modules by name (bounded; no giant getgc walk).
	local function fingerprintAC()
		local found = {}
		pcall(function() for _, s in ipairs((getrunningscripts and getrunningscripts()) or {}) do local sig = acSig(s.Name); if sig then found[#found + 1] = { obj = s, name = s.Name, why = sig } end end end)
		pcall(function() for _, m in ipairs((getloadedmodules and getloadedmodules()) or {}) do local sig = acSig(m.Name); if sig then found[#found + 1] = { obj = m, name = m.Name, why = sig } end end end)
		return found
	end

	-- Stage 2: map honeypots -- nil-parented remotes (classic bait the AC references
	-- but never trees) + remotes named like detection. These go on the AVOID list.
	local function mapHoneypots()
		local avoid, n = {}, 0
		pcall(function()
			for _, inst in ipairs((getnilinstances and getnilinstances()) or {}) do
				pcall(function() if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("BindableEvent") then avoid[inst] = "nil-parented remote (bait)" end end)
			end
		end)
		pcall(function()
			for _, d in ipairs(game:GetDescendants()) do
				n = n + 1; if n > 60000 then break end
				if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then local sig = acSig(d.Name); if sig then avoid[d] = "AC-named remote (" .. sig .. ")" end end
			end
		end)
		return avoid
	end

	-- Stage 3: READ THE WIRING. Build a closure from each AC script's bytecode and
	-- dump its string constants (value names, property names, remote names it
	-- references) + the same for its nested protos. Pure read -- never executed.
	local function readWiring(acScripts)
		local watched = {}
		for _, ac in ipairs(acScripts) do
			pcall(function()
				local closure = getscriptclosure and getscriptclosure(ac.obj)
				if not closure then return end
				local function harvest(fn)
					local consts = debug and debug.getconstants and debug.getconstants(fn)
					if type(consts) == "table" then
						for _, c in ipairs(consts) do if type(c) == "string" and #c > 2 then watched[c] = true end end
					end
				end
				harvest(closure)
				pcall(function() for _, proto in ipairs((debug.getprotos and debug.getprotos(closure)) or {}) do harvest(proto) end end)
			end)
		end
		return watched
	end

	-- Stage 4: connection recon -- how many watchers sit on the frame loop (AC
	-- heartbeat checks live here). Read-only count.
	local function reconConns()
		local t = {}
		for _, sig in ipairs({ "Heartbeat", "Stepped", "RenderStepped" }) do
			pcall(function() t[sig] = #getconnections(RunService[sig]) end)
		end
		return t
	end

	local function runProbe()
		if not Toggles.deepScanEnabled.Value then Library:Notify("Enable Deep Scan first"); return end
		local ac = fingerprintAC()
		local avoid = mapHoneypots()
		local watched = readWiring(ac)
		local conns = reconConns()
		-- Which KNOWN-monitored properties does the AC reference?
		local hot = {}
		for _, p in ipairs(MONITORED_PROPS) do if watched[p] then hot[#hot + 1] = p end end
		Bridge.DeepScan.acActive = #ac > 0
		Bridge.DeepScan.avoid = avoid
		Bridge.DeepScan.watched = watched
		Bridge.DeepScan.hotProps = hot
		local wN, aN = 0, 0
		for _ in pairs(watched) do wN = wN + 1 end
		for _ in pairs(avoid) do aN = aN + 1 end
		local lines = {
			"AC scripts: " .. #ac .. (#ac > 0 and (" (" .. ac[1].name .. ")") or ""),
			"Honeypots avoided: " .. aN,
			"AC string-refs read: " .. wN,
			(#hot > 0 and ("Watches: " .. table.concat(hot, ", ")) or "Watches: (none of the common props)"),
			("Frame watchers: HB %d / Step %d / Rndr %d"):format(conns.Heartbeat or 0, conns.Stepped or 0, conns.RenderStepped or 0),
			"Footprint: read-only (0 writes, 0 fires)",
		}
		pcall(function() dsInfo:SetText(table.concat(lines, "\n")) end)
		Library:Notify(#ac > 0 and ("AC detected: " .. ac[1].name) or "No named anti-cheat found")
	end
	dsGroup:AddButton("Run Phantom Probe", runProbe):AddToolTip("Read-only recon: fingerprint the anti-cheat, map honeypots, and read which\nvalues/remotes it watches -- without touching any of them. Nothing is fired or written.")

	-- Minefield map other modules consult before they act.
	Bridge.isHoneypot = function(inst) return Bridge.DeepScan.avoid and Bridge.DeepScan.avoid[inst] ~= nil end
	Bridge.isWatched  = function(name) return Bridge.DeepScan.watched and Bridge.DeepScan.watched[tostring(name)] == true end

	-- ===== Tier 5: Collective intelligence ==============================
	-- A personal multi-game profile DB plus community fetch (point it at any raw-JSON
	-- URL -- e.g. a GitHub profiles folder -- and it pulls <url>/<PlaceId>.json), with
	-- a confidence-scored fallback chain: community (curated) -> your local DB -> a
	-- live scan. Best source wins, results merge, and the outcome is saved back so the
	-- game self-configures instantly next time.
	local ciGroup = calTab:AddLeftGroupbox("Collective (Tier 5)")
	ciGroup:AddInput("profileSourceUrl", { Text = "Profile Source URL", Default = "", Tooltip = "Base raw-JSON URL of a community profile repo. Fetches\n<url>/<PlaceId>.json. Empty = local + live scan only." })
	local ciInfo = ciGroup:AddLabel("Auto-config: community -> local DB -> live scan.")

	local DB_FILE = "FurryHBE_ProfileDB.json"
	local function keysOfSet(t) local o = {} if type(t) == "table" then for k in pairs(t) do o[#o + 1] = k end end return o end
	local function readDB()
		if not (isfile and readfile and isfile(DB_FILE)) then return {} end
		local ok, d = pcall(function() return HttpService:JSONDecode(readfile(DB_FILE)) end)
		return (ok and type(d) == "table") and d or {}
	end
	local function writeDB(db) if writefile then pcall(function() writefile(DB_FILE, HttpService:JSONEncode(db)) end) end end
	local function countKeys(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

	local function fetchCommunity()
		local base = Options.profileSourceUrl.Value
		if not base or base == "" then return nil end
		local url = base
		if not url:find("%.json$") then url = url:gsub("/$", "") .. "/" .. tostring(game.PlaceId) .. ".json" end
		local ok, body = pcall(function() return game:HttpGet(url) end)
		if not ok or type(body) ~= "string" then return nil end
		local ok2, d = pcall(function() return HttpService:JSONDecode(body) end)
		return (ok2 and type(d) == "table") and d or nil
	end
	local function liveProfile()
		local s = runScan(false)
		return { parts = keysOfSet(s.parts), guns = keysOfSet(s.guns), shields = keysOfSet(s.shields) }
	end

	local function autoConfigure()
		local sources = {}
		local com = fetchCommunity()
		if com and (com.parts or com.guns or com.shields) then sources[#sources + 1] = { "Community", 0.9, com } end
		local db = readDB()
		local loc = db[tostring(game.PlaceId)]
		if loc then sources[#sources + 1] = { "Local DB", 0.85, loc } end
		sources[#sources + 1] = { "Live Scan", 0.7, liveProfile() }
		-- Apply low->high confidence so the best source's selections land last; the
		-- additive lists naturally MERGE everything we know.
		table.sort(sources, function(a, b) return a[2] < b[2] end)
		local best
		for _, s in ipairs(sources) do applyProfile(s[3]); best = s end
		if best then db[tostring(game.PlaceId)] = best[3]; writeDB(db) end
		pcall(function() ciInfo:SetText(("Configured: %s (%.0f%% conf), %d sources merged"):format(best and best[1] or "?", (best and best[2] or 0) * 100, #sources)) end)
		Library:Notify("Auto-configured this game")
	end

	ciGroup:AddButton("Auto-Configure (fallback chain)", autoConfigure):AddToolTip("Try community -> local DB -> live scan, merge + apply, and remember.")
	ciGroup:AddButton("Fetch Community Profile", function()
		local com = fetchCommunity()
		if com then applyProfile(com); Library:Notify("Applied community profile") else Library:Notify("No community profile (set the URL?)") end
	end):AddToolTip("Pull this PlaceId's profile from the source URL.")
	ciGroup:AddButton("Save to Local DB", function()
		local db = readDB()
		db[tostring(game.PlaceId)] = liveProfile()
		writeDB(db)
		Library:Notify("Saved to local DB (" .. countKeys(db) .. " games stored)")
	end):AddToolTip("Scan and store this game's profile in your personal DB.")

	-- Auto-load a previously-saved profile for this place on startup.
	pcall(function() loadProfile(false) end)
	print("[Calibrate] F10 extract/calibrate registered")
end)

-- ===== [V19] Plugin Manager + first plug-and-play plugin (Spectate) ========
-- Keystone of the compartmentalization system: plugins are registered as source
-- strings and loaded ON DEMAND via Bridge:EnablePlugin (a real loadstring), then
-- torn down completely via Bridge:UnloadPlugin. This proves the plug-and-play cycle;
-- existing tabs are untouched and will migrate into plugins one at a time later.
pcall(function()
	local pmTab   = mainWindow:AddTab("Plugins")
	local pmGroup = pmTab:AddLeftGroupbox("Plugin Manager")
	pmGroup:AddLabel("Enable loads a plugin's tab + features on demand.\nUnload frees its memory/connections and clears its UI.", true)

	-- Base URL for the external plugin files (set here, or via getgenv().FurryHBE_PluginBase
	-- before running). Enable fetches <base>/<file>. This is what keeps the core small:
	-- plugin code lives in separate .lua files, NOT inline.
	pmGroup:AddInput("pluginBaseUrl", { Text = "Plugin Base URL", Default = Bridge.PluginBase or "", Tooltip = "Raw folder URL holding the plugin .lua files (e.g. a GitHub raw\nfolder). Enable downloads <base>/<file> on demand." })
	Options.pluginBaseUrl:OnChanged(function() Bridge.PluginBase = Options.pluginBaseUrl.Value end)
	if Bridge.PluginBase ~= "" then pcall(function() Options.pluginBaseUrl:SetValue(Bridge.PluginBase) end) end

	-- External plugins (uploaded to the base URL). No inline source -> small core.
	-- Each plugin carries its explicit raw GitHub URL so Enable works even if the
	-- Plugin Base URL field is blank. (Loader still honors `info.url` first.)
	local RAW = "https://raw.githubusercontent.com/Criptonized/cryptonize-s-HBE/main/"
	Bridge:RegisterPluginSource("Aimbot",   { tab = "Aimbot",   file = "aimbot.lua",      url = RAW .. "aimbot.lua",      desc = "Camera aimbot + triggerbot + no-recoil with ballistic prediction." })
	Bridge:RegisterPluginSource("Spectate", { tab = "Spectate", file = "spectate.lua",    url = RAW .. "spectate.lua",    desc = "Cycle the camera through players to spectate." })
	Bridge:RegisterPluginSource("Advanced", { tab = "Advanced", file = "advanced.lua",    url = RAW .. "advanced.lua",    desc = "Radar/minimap, bunny-hop + infinite jump, teleport persistence, auto-soften." })
	Bridge:RegisterPluginSource("Precision", { tab = "Precision", file = "precision.lua", url = RAW .. "precision.lua",   desc = "Single-target hitbox extender with resolver, dynamic scaling + visuals." })
	Bridge:RegisterPluginSource("Streamer", { tab = "Streamer", file = "streamer.lua",    url = RAW .. "streamer.lua",    desc = "Hide visuals, panic key, UI hide, update-rate jitter." })
	Bridge:RegisterPluginSource("Teleport", { tab = "Teleport", file = "teleport.lua",    url = RAW .. "teleport.lua",    desc = "Waypoints, teleport-to-player, seat teleport, anti-rubberband." })
	Bridge:RegisterPluginSource("Remote",   { tab = "Remote",   file = "remotereplay.lua", url = RAW .. "remotereplay.lua", desc = "Manual RemoteEvent replay at the nearest target (for remote-damage games)." })
	Bridge:RegisterPluginSource("InfAmmo",  { tab = "Inf Ammo", file = "infammo.lua",     url = RAW .. "infammo.lua",     desc = "Adaptive inf-ammo (5 strategies + learning) with gun picker." })

	-- One manager row (status + Enable + Unload) per registered plugin.
	local function addRow(name)
		local status = pmGroup:AddLabel(name .. ": not loaded")
		pmGroup:AddButton("Enable " .. name, function()
			local ok, err = Bridge:EnablePlugin(name)
			status:SetText(name .. (ok and ": loaded" or (": FAILED - " .. tostring(err))))
			if Library and Library.Notify then Library:Notify(ok and ("Enabled " .. name) or ("Enable failed: " .. tostring(err))) end
		end):AddToolTip(Bridge.PluginSources[name] and Bridge.PluginSources[name].desc or "")
		pmGroup:AddButton("Unload " .. name, function()
			Bridge:UnloadPlugin(name)
			status:SetText(name .. ": not loaded")
			if Library and Library.Notify then Library:Notify("Unloaded " .. name) end
		end)
	end
	for n in pairs(Bridge.PluginSources) do addRow(n) end
	print("[Plugins] manager + external plugin registry (Aimbot, Spectate)")
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
