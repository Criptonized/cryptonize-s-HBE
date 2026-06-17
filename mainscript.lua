if getgenv().CryptsHBEInjected then
	return
end
getgenv().CryptsHBEInjected = true
getgenv().CryptsHBELoaded = false

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
SaveManager:SetFolder("CryptsHBE")

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

-- Reject NaN/inf so a bad projection never sizes/positions a fallback element. A garbage
-- coordinate used to stretch a Frame into the giant black bar that smeared across the top
-- of the screen (and clustered ESP boxes into floating squares).
local function dfFinite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end
local DF_MAX = 8192  -- hard cap on any fallback element dimension/offset (px)
local function dfClamp(n) if not dfFinite(n) then return 0 end return math.clamp(n, -DF_MAX, DF_MAX) end

function DrawingFallback:Update()
	if not self.element then return end

	self.element.Visible = self.visible
	-- Bail (hidden) on any non-finite geometry rather than rendering a corrupt element.
	local p = self.position
	if typeof(p) == "Vector2" and not (dfFinite(p.X) and dfFinite(p.Y)) then self.element.Visible = false; return end
	if self.type == "Line" then
		local a, b = self.from, self.to
		if not (typeof(a) == "Vector2" and typeof(b) == "Vector2" and dfFinite(a.X) and dfFinite(a.Y) and dfFinite(b.X) and dfFinite(b.Y)) then self.element.Visible = false; return end
	end

	if self.type == "Circle" then
		self.element.Size = UDim2.new(0, dfClamp(self.radius * 2), 0, dfClamp(self.radius * 2))
		self.element.Position = UDim2.new(0, dfClamp(self.position.X - self.radius), 0, dfClamp(self.position.Y - self.radius))
		self.border.Color = self.color
		self.border.Thickness = self.thickness
		self.element.BackgroundTransparency = self.filled and 0 or 1
		if self.filled then
			self.element.BackgroundColor3 = self.color
		end
	elseif self.type == "Text" then
		self.element.Text = self.text
		self.element.TextColor3 = self.color
		self.element.Position = UDim2.new(0, dfClamp(self.position.X), 0, dfClamp(self.position.Y))
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
		self.element.Size = UDim2.new(0, dfClamp(self.size.X), 0, dfClamp(self.size.Y))
		self.element.Position = UDim2.new(0, dfClamp(self.position.X), 0, dfClamp(self.position.Y))
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
			self.element.Size = UDim2.new(0, dfClamp(length), 0, math.max(1, self.thickness or 1))
			self.element.Position = UDim2.new(0, dfClamp(cx), 0, dfClamp(cy))
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
--     getgenv().CryptsHBE_ForceGuiESP   = true  -> always use the GUI fallback
--     getgenv().CryptsHBE_ForceNativeESP = true -> always use native Drawing
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
if getgenv().CryptsHBE_ForceGuiESP then
	useNativeDrawing = false
elseif getgenv().CryptsHBE_ForceNativeESP then
	useNativeDrawing = nativeConstructs
else
	useNativeDrawing = nativeConstructs and not guiOnlyExecutor
end
getgenv().CryptsHBE_UsingNativeESP = useNativeDrawing  -- readable for debugging

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

-- Treat ALL numeric value types as numbers. Many gun frameworks (TREK, older FE kits)
-- store ammo/stats as Double/IntConstrainedValue, not IntValue/NumberValue -- scanning
-- only the latter is why such ammo looked "server-side" and never got detected/written.
local function isNumericValue(d)
	return isNumericValue(d) or d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue")
end

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
	local bridge = getgenv().CryptsHBE
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

	getgenv().CryptsHBELoaded = false
end

-- Window setup (with failsafe)
local windowConfig = {
	Title = "cryptonize's library   ·   scroll-wheel over the tabs to switch",
	Center = true,
	AutoShow = true,
	TabPadding = 8,
	MenuFadeTime = 0.2,
	-- Wider than LinoriaLib's ~550px default: each tab has two columns, so the default
	-- left ~250px columns clipped longer labels/descriptions on the right. ~720 gives the
	-- columns room so tutorials, the Plugin Manager text, etc. fit instead of cutting off.
	Size = UDim2.fromOffset(720, 600),
}

local mainWindow = safeCall("UI Creation", function()
	return Library:CreateWindow(windowConfig)
end)

if not mainWindow then
	warn("[CryptsHBE] Failed to create main window, retrying...")
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
-- LinoriaLib has no RemoveTab, and DESTROYING a tab's Button/Container corrupts the UI:
-- the Window still references them, so tab-switching + the cursor render loop hit dead
-- instances and cascade-fail (tabs glitch, cursor freezes). So we only HIDE the tab button
-- on unload (a pure property write -- safe) and KEEP the cache, so re-enable reuses the
-- same tab and just un-hides it. (A hidden button can leave a small gap in the tab bar;
-- that's the safe trade-off for not breaking the whole menu.)
function Bridge:RemoveTab(name)
	local tab = self.Tabs[name]
	if type(tab) ~= "table" then return end
	pcall(function()
		for _, k in ipairs({ "Button", "TabButton" }) do
			local b = rawget(tab, k)
			if typeof(b) == "Instance" then b.Visible = false end
		end
	end)
end
function Bridge:ShowTab(name)
	local tab = self.Tabs[name]
	if type(tab) ~= "table" then return end
	pcall(function()
		for _, k in ipairs({ "Button", "TabButton" }) do
			local b = rawget(tab, k)
			if typeof(b) == "Instance" then b.Visible = true end
		end
	end)
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
-- Base URL for external plugin files (set getgenv().CryptsHBE_PluginBase to your
-- GitHub raw folder). EnablePlugin fetches <base>/<file> for plugins with no inline
-- source. Per-plugin info.url / info.file / info.source all override.
Bridge.PluginBase = getgenv().CryptsHBE_PluginBase or "https://raw.githubusercontent.com/Criptonized/cryptonize-s-HBE/main"
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
	if not src then return false, "no source/url (set getgenv().CryptsHBE_PluginBase)" end
	local fn, cerr = loadstring(src, "=" .. name)
	if not fn then return false, "compile: " .. tostring(cerr) end
	local ok, mod = pcall(fn)
	if not ok or type(mod) ~= "table" or type(mod.load) ~= "function" then return false, "bad module: " .. tostring(mod) end
	local tab = self:GetOrMakeTab(mod.tab or name)
	if not tab then return false, "no tab" end
	self:ShowTab(mod.tab or name)  -- un-hide if this tab was hidden by a previous unload
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
	pcall(function() self:RemoveTab((entry.mod and entry.mod.tab) or name) end)  -- pop the empty tab out
	self.Plugins[name] = { loaded = false }   -- drop mod + ctx refs so the chunk GCs
	pcall(collectgarbage)
end

-- Shared reverse-engineering dump (used by the weapon + vehicle Deep-Dump buttons):
-- writes a model's full tree -- every child's class/name, every Value's value, every
-- attribute -- plus the read-only string constants of its scripts (revealing the
-- value/remote/function names its code uses) and game remotes matching `remoteWords`, to
-- workspace/CryptsHBE/<fname>. Pure read (getscriptclosure/getconstants); never writes.
function Bridge:DeepDumpModel(root, title, fname, remoteWords)
	if not root then if Library then Library:Notify("Nothing to dump") end return end
	local lines = { "=== " .. title .. " Deep Dump ===", "Root: " .. root.Name .. " (" .. root.ClassName .. ")", "PlaceId: " .. tostring(game.PlaceId), "" }
	local function dumpConsts(inst, depth)
		pcall(function()
			if (inst:IsA("ModuleScript") or inst:IsA("LocalScript") or inst:IsA("Script")) and getscriptclosure and debug and debug.getconstants then
				local cl = getscriptclosure(inst); if not cl then return end
				local strs, seen = {}, {}
				local function harvest(fn)
					local consts = debug.getconstants(fn)
					if type(consts) == "table" then
						for _, c in ipairs(consts) do if type(c) == "string" and #c > 2 and #c < 64 and not seen[c] then seen[c] = true; strs[#strs + 1] = c end end
					end
				end
				harvest(cl)
				pcall(function() for _, p in ipairs((debug.getprotos and debug.getprotos(cl)) or {}) do harvest(p) end end)
				if #strs > 0 then lines[#lines + 1] = string.rep("  ", depth + 1) .. "[consts] " .. table.concat(strs, ", ") end
			end
		end)
	end
	-- Physics props worth seeing on constraints / body-movers / vehicle seats: these are
	-- what actually governs speed on constraint-driven vehicles (no speed Value exists).
	local PHYS_PROPS = { "ActuatorType", "MotorMaxTorque", "MotorMaxAngularAcceleration", "MotorMaxAcceleration",
		"AngularVelocity", "TargetAngle", "MaxSpeed", "Torque", "TurnSpeed", "Stiffness", "Damping", "FreeLength",
		"Velocity", "VectorVelocity", "MaxForce", "Force", "Responsiveness" }
	local function dumpPhys(inst, depth)
		if not (inst:IsA("Constraint") or inst:IsA("BodyMover") or inst:IsA("VehicleSeat")) then return end
		local got = {}
		for _, p in ipairs(PHYS_PROPS) do
			local ok, v = pcall(function() return inst[p] end)
			if ok and v ~= nil then got[#got + 1] = p .. "=" .. tostring(v) end
		end
		if #got > 0 then lines[#lines + 1] = string.rep("  ", depth + 1) .. ". " .. table.concat(got, "  ") end
	end
	-- Require config-type ModuleScripts and print their numeric/string/bool values, so the
	-- actual stat VALUES (fire rate, recoil, reload speed...) are visible -- the script
	-- constants only show the code's strings, not the data. Only config-named modules are
	-- required (avoid running behaviour modules); read-only, pcall-guarded.
	local CFG_NAMES2 = { "config", "setting", "stat", "data", "tune", "value", "info", "properties", "props" }
	local function looksCfg(n) n = tostring(n):lower() for _, w in ipairs(CFG_NAMES2) do if n:find(w, 1, true) then return true end end return false end
	local function dumpModuleValues(inst, depth)
		if not inst:IsA("ModuleScript") or not looksCfg(inst.Name) then return end
		pcall(function()
			local ok, mod = pcall(require, inst)
			if not ok or type(mod) ~= "table" then return end
			local kv, n = {}, 0
			local function walk(t, prefix, dep, seen)
				if dep > 3 or seen[t] then return end
				seen[t] = true
				for k, v in pairs(t) do
					local tv = type(v)
					if (tv == "number" or tv == "boolean" or tv == "string") and n < 120 then
						n = n + 1; kv[#kv + 1] = prefix .. tostring(k) .. "=" .. tostring(v)
					elseif tv == "table" then walk(v, prefix .. tostring(k) .. ".", dep + 1, seen) end
				end
			end
			walk(mod, "", 1, {})
			if #kv > 0 then lines[#lines + 1] = string.rep("  ", depth + 1) .. "[module values] " .. table.concat(kv, "  ") end
		end)
	end
	local function dump(inst, depth, cap)
		if #lines >= cap then return end
		local indent = string.rep("  ", depth)
		local extra = ""
		pcall(function() if inst:IsA("ValueBase") then extra = " = " .. tostring(inst.Value) end end)
		lines[#lines + 1] = indent .. inst.ClassName .. " '" .. inst.Name .. "'" .. extra
		pcall(function() for an, av in pairs(inst:GetAttributes()) do lines[#lines + 1] = indent .. "  @" .. an .. " = " .. tostring(av) end end)
		pcall(dumpPhys, inst, depth)
		pcall(dumpModuleValues, inst, depth)
		dumpConsts(inst, depth)
		for _, c in ipairs(inst:GetChildren()) do
			if #lines >= cap then lines[#lines + 1] = indent .. "  ...(truncated)"; break end
			dump(c, depth + 1, cap)
		end
	end
	dump(root, 0, 4000)
	-- Vehicle profile: classify the platform (plane/heli/tank/armoured/car/ATV/artillery),
	-- detect tracked-vs-wheeled, a gun/turret + its ammo, so the dump says WHAT it is and
	-- whether it has a weapon system at a glance.
	if tostring(title):lower():find("vehicle") then
		pcall(function()
			local p = { wheels = 0, treads = 0, seats = 0, turrets = 0, wings = 0, rotors = 0, thrust = 0, hinge = 0, cyl = 0, ammo = {} }
			for _, d in ipairs(root:GetDescendants()) do
				local n = d.Name:lower()
				if n:find("wheel") or n:find("tire") or n:find("tyre") then p.wheels = p.wheels + 1 end
				if n:find("tread") or n:find("track") or n:find("caterpillar") or n:find("sprocket") then p.treads = p.treads + 1 end
				if n:find("turret") or n:find("cannon") or n:find("barrel") or n:find("muzzle") or (n:find("gun") and not n:find("gunner")) then p.turrets = p.turrets + 1 end
				if n:find("wing") or n:find("aileron") or n:find("rudder") or n:find("elevator") or n:find("flap") then p.wings = p.wings + 1 end
				if n:find("rotor") or n:find("propeller") or n:find("rotorblade") then p.rotors = p.rotors + 1 end
				if d:IsA("VehicleSeat") or d:IsA("Seat") then p.seats = p.seats + 1 end
				if d:IsA("VectorForce") or d:IsA("BodyThrust") or d:IsA("LinearVelocity") or d:IsA("BodyVelocity") then p.thrust = p.thrust + 1 end
				if d:IsA("HingeConstraint") then p.hinge = p.hinge + 1 end
				if d:IsA("CylindricalConstraint") then p.cyl = p.cyl + 1 end
				if (d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("DoubleConstrainedValue") or d:IsA("IntConstrainedValue"))
					and (n:find("ammo") or n:find("shell") or n:find("round") or n:find("magazine") or n:find("rocket") or n:find("missile")) then
					p.ammo[#p.ammo + 1] = d.Name .. "=" .. tostring(d.Value) .. " (" .. d.ClassName .. ")"
				end
			end
			local cls
			if p.wings >= 2 or (p.thrust > 0 and p.wings > 0) then cls = "Plane / aircraft"
			elseif p.rotors >= 1 and p.thrust > 0 then cls = "Helicopter"
			elseif p.treads >= 2 then cls = (p.turrets > 0 and "Tank (tracked + turret)" or "Tracked vehicle")
			elseif p.turrets > 0 and p.wheels >= 3 then cls = "Armoured vehicle (wheeled + turret)"
			elseif p.wheels >= 4 then cls = "Car / wheeled vehicle"
			elseif p.wheels >= 1 and p.wheels <= 3 then cls = "ATV / bike"
			elseif p.turrets > 0 then cls = "Artillery / emplaced gun"
			else cls = "unknown" end
			lines[#lines + 1] = ""
			lines[#lines + 1] = "=== Vehicle Profile ==="
			lines[#lines + 1] = "Type guess: " .. cls
			lines[#lines + 1] = ("Drive: %s   wheels=%d treads=%d cyl=%d hinge=%d thrust=%d"):format(
				(p.treads >= 2 and "TRACKED" or (p.wheels > 0 and "wheeled" or "constraint/other")), p.wheels, p.treads, p.cyl, p.hinge, p.thrust)
			lines[#lines + 1] = ("Seats=%d  Gun/turret parts=%d  Wings=%d  Rotors=%d"):format(p.seats, p.turrets, p.wings, p.rotors)
			lines[#lines + 1] = "Has weapon system: " .. (p.turrets > 0 and "YES (turret/gun)" or "no turret parts found")
			lines[#lines + 1] = "Ammo values: " .. (#p.ammo > 0 and table.concat(p.ammo, "  ") or "none on the model (may live on the operator's taskbar tool)")
		end)
	end
	if type(remoteWords) == "table" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "=== Related Remotes ==="
		pcall(function()
			local n = 0
			for _, d in ipairs(game:GetDescendants()) do
				if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
					local ln = d.Name:lower()
					for _, w in ipairs(remoteWords) do
						if ln:find(w) then n = n + 1; if n <= 250 then lines[#lines + 1] = d.ClassName .. " '" .. d.Name .. "'  @ " .. d:GetFullName() end break end
					end
					if n > 250 then break end
				end
			end
		end)
	end
	local DIR = "CryptsHBE"
	pcall(function() if makefolder and not (isfolder and isfolder(DIR)) then makefolder(DIR) end end)
	fname = Bridge:SessionName(fname)   -- tag with the session number
	local path = DIR .. "/" .. fname
	if not writefile then if Library then Library:Notify("Executor has no writefile") end return end
	local ok = pcall(function() writefile(path, table.concat(lines, "\n")) end)
	if Library then Library:Notify(ok and ("Saved -> workspace/" .. path) or ("Save failed: " .. path)) end
end

-- ===== Session counter: bumps on every load/reattach; all dumps get a _S<N> tag =====
do
	local DIR = "CryptsHBE"
	local SF = DIR .. "/session.txt"
	local n = 0
	pcall(function()
		if makefolder and not (isfolder and isfolder(DIR)) then makefolder(DIR) end
		if isfile and readfile and isfile(SF) then n = tonumber(readfile(SF)) or 0 end
	end)
	n = n + 1
	pcall(function() if writefile then writefile(SF, tostring(n)) end end)
	Bridge.SessionId = n
end
-- Insert _S<N> before the extension of a filename (e.g. dump.txt -> dump_S4.txt).
function Bridge:SessionName(fname)
	local n = tostring(self.SessionId or 0)
	if tostring(fname):find("%.%w+$") then return (fname:gsub("(%.%w+)$", "_S" .. n .. "%1")) end
	return fname .. "_S" .. n
end

getgenv().CryptsHBE = Bridge
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

	RunService:BindToRenderStep("CryptsHBE_HoldPick", Enum.RenderPriority.Last.Value + 2, function()
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
			pcall(function() RunService:UnbindFromRenderStep("CryptsHBE_HoldPick") end)
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
		getgenv().CryptsHBELoaded = true
		updatePlayers()
		if not suppressMasterNotify then Library:Notify("HBE Enabled") end
	else
		-- Restore everyone BEFORE halting the update loop, otherwise the loop
		-- never runs again to undo the extension and the visuals stay stuck on.
		if resetAllPlayers then resetAllPlayers() end
		if resetWorldParts then resetWorldParts() end
		getgenv().CryptsHBELoaded = false
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
hitboxGroupbox:AddToggle("outlineMode", { Text = "Outline Only", Default = false, Tooltip = "Show the enlarged hitbox as a clean wireframe outline\ninstead of a solid block. The real part stays enlarged (so\nhit-reg still works) but is made invisible, with a SelectionBox\noutline in your outline colour. (Default: OFF)" }):OnChanged(updatePlayers)
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
-- Crosshair reference used by the FOV Filter / Legit Mode / Auto-Expand AND the combat
-- crosshair. 1st Person = screen centre; 3rd Person = follows your mouse cursor (when not
-- shiftlocked). Lets "only within crosshair" work in a 3rd-person, free-cursor game.
antiDetectionGroupbox:AddDropdown("crosshairMode", { Text = "Crosshair Mode", Values = { "1st Person (center)", "3rd Person (cursor)" }, Default = "1st Person (center)", Multi = false, AllowNull = false, Tooltip = "1st = aim point is screen centre.\n3rd = aim point follows your cursor (free mouse).\nUsed by FOV Filter, Legit/Auto-Expand and the combat crosshair." }):OnChanged(updatePlayers)
-- Hit Marker: a small center-tick flash when an enemy takes damage right after you attack.
-- Deliberately NOT a fill/flash on the target (which would hide players behind it in a
-- crowd) -- just a crosshair tick, so the play area stays fully visible.
antiDetectionGroupbox:AddToggle("hitMarkerEnabled", { Text = "Hit Marker", Default = false, Tooltip = "Flash a small crosshair tick when an enemy's HP drops just after you\nattack -- confirms a hit without hiding targets behind it. (Default: OFF)" })
antiDetectionGroupbox:AddToggle("hitMarkerAttackOnly", { Text = "Hit Marker: only when I attack", Default = true, Tooltip = "Only flash if you clicked/fired in the last 0.5s (filters out hits other\nplayers landed). Off = flash on ANY enemy HP drop nearby. (Default: ON)" })
antiDetectionGroupbox:AddLabel("Hit Marker Color"):AddColorPicker("hitMarkerColor", { Title = "Hit Marker Color", Default = Color3.fromRGB(255, 255, 255) })
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
espChamsGroupbox:AddDropdown("espHighlightDepthMode", { Text = "Depth Mode", AllowNull = false, Multi = false, Values = { "AlwaysOnTop", "Occluded" }, Default = "AlwaysOnTop", Tooltip = "How chams render through walls.\nAlwaysOnTop = wallhack, visible through mountains/objects.\nOccluded = only visible in direct line of sight.\n(Default: AlwaysOnTop)" }):OnChanged(updatePlayers)
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
espAdvancedGroupbox:AddToggle("espOffscreenPulse", { Text = "Proximity Pulse", Default = true, Tooltip = "Off-screen markers pulse (size + slight brighten) more as the\nplayer gets closer -- a subtle 'they're near' indicator. (Default: ON)" })
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
espFilterGroupbox:AddLabel("Backend: " .. (getgenv().CryptsHBE_UsingNativeESP and "Native Drawing" or "GUI fallback"), true)
local espDiagLabel = espFilterGroupbox:AddLabel("ESP drawn: -")
local espDiagTick = 0
espFilterGroupbox:AddDropdown("espBackendOverride", { Text = "Force Backend", Values = { "Auto", "Native", "GUI" }, Default = "Auto", Multi = false, AllowNull = false, Tooltip = "Force the ESP draw backend on the NEXT execute (re-run to apply).\nNative = Drawing API, GUI = fallback frames. (Default: Auto)" }):OnChanged(function()
	local v = Options.espBackendOverride.Value
	getgenv().CryptsHBE_ForceNativeESP = (v == "Native") or nil
	getgenv().CryptsHBE_ForceGuiESP = (v == "GUI") or nil
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
		local sg = Instance.new("ScreenGui"); sg.Name = "CryptsHBE_ESPTest"; sg.IgnoreGuiInset = true
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
local WL_FILE = "CryptsHBE_Whitelist.json"
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
			writefile("CryptsHBE_CustomProfile.json", game:GetService("HttpService"):JSONEncode(snap))
		end
	end)
	Library:Notify("Saved current settings as 'Custom' profile")
end):AddToolTip("Snapshot the current settings into a loadable 'Custom' profile")

-- Restore a previously saved custom profile from disk, if present.
pcall(function()
	if isfile and isfile("CryptsHBE_CustomProfile.json") and readfile then
		local data = game:GetService("HttpService"):JSONDecode(readfile("CryptsHBE_CustomProfile.json"))
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
emergencyGroupbox:AddToggle("menuAutoHide", { Text = "Auto-hide while menu open", Default = true, Tooltip = "While the menu is open, hide ESP/FOV/chams + the combat crosshair and stop HBE\nextension, so they don't get in the way; restores when you close it. (Default: ON)" })
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

-- ===== Keybinds tab (central; core + plugins register here) =================
-- A dedicated tab for ALL keybinds. Core actions live in the left box; plugins call
-- Bridge:AddKeybind(...) on load to drop their binds in the right box (waypoints, auto-
-- fire, capture-HUD-value, etc.). NoUI=false so they also show in LinoriaLib's floating
-- keybind list. Plugin binds persist as inert keypickers when a plugin unloads (we never
-- destroy library controls -- that corrupts the UI); re-enabling re-points the callback.
local keybindTab = mainWindow:AddTab("Keybinds")
local miscGroupbox = keybindTab:AddLeftGroupbox("Core Keybinds")
miscGroupbox:AddLabel("Toggle UI"):AddKeyPicker("menuKeybind", { Default = "\\", NoUI = false, Text = "Menu Keybind" })
miscGroupbox:AddLabel("Force Update"):AddKeyPicker("forceUpdateKeybind", { Default = "Home", NoUI = false, Text = "Force Update Keybind"})
Options.forceUpdateKeybind:OnClick(updatePlayers)
miscGroupbox:AddLabel("Panic (toggle extender)"):AddKeyPicker("panicKeybind", { Default = "P", NoUI = false, Text = "Panic Keybind" })
Options.panicKeybind:OnClick(function()
	if Toggles.extenderToggled then
		Toggles.extenderToggled:SetValue(not Toggles.extenderToggled.Value)
	end
end)
-- QOL: bind the common toggles too (ESP names + HBE master). OnClick fires once per press.
miscGroupbox:AddLabel("Toggle HBE (master)"):AddKeyPicker("hbeKeybind", { Default = "", NoUI = false, Text = "Toggle HBE" })
Options.hbeKeybind:OnClick(function() if Toggles.extenderToggled then Toggles.extenderToggled:SetValue(not Toggles.extenderToggled.Value) end end)
miscGroupbox:AddLabel("Toggle ESP Names"):AddKeyPicker("espKeybind", { Default = "", NoUI = false, Text = "Toggle ESP" })
Options.espKeybind:OnClick(function() if Toggles.espNameToggled then Toggles.espNameToggled:SetValue(not Toggles.espNameToggled.Value) end end)
Library.ToggleKeybind = Options.menuKeybind

-- Plugin keybind registry: plugins call Bridge:AddKeybind on load and clear on unload.
Bridge.KeybindBox = keybindTab:AddRightGroupbox("Plugin Keybinds")
Bridge.KeybindBox:AddLabel("Enabled plugins register their\nkeybinds here (waypoints, etc.).", true)
Bridge.KeybindCallbacks = {}
Bridge._kbMade = {}
-- id: unique key, text: label, default: key string, mode: "Toggle"/"Hold", cb: function(state)
function Bridge:AddKeybind(id, text, default, mode, cb)
	if not self.KeybindBox then return end
	self.KeybindCallbacks[id] = cb
	if self._kbMade[id] then return end   -- keypicker already exists -> just re-pointed the callback
	self._kbMade[id] = true
	pcall(function()
		self.KeybindBox:AddLabel(text):AddKeyPicker(id, { Default = default or "", Mode = mode or "Toggle", Text = text,
			Callback = function(state) local fn = self.KeybindCallbacks[id]; if fn then pcall(fn, state) end end })
	end)
end
function Bridge:ClearKeybind(id) if self.KeybindCallbacks then self.KeybindCallbacks[id] = nil end end

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
-- The crosshair reference point (screen-space, same space as WorldToViewportPoint):
-- screen centre in 1st person, or the live mouse cursor in 3rd person (unless shiftlocked,
-- where the cursor is pinned to centre anyway). Used by every "near the crosshair" check
-- and by the crosshair/FOV-circle drawing so they all agree.
local function getAimPoint()
	local vp = Camera.ViewportSize
	local mode = (Options.crosshairMode and Options.crosshairMode.Value) or ""
	if mode:find("3rd") and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		local ok, ml = pcall(function() return UserInputService:GetMouseLocation() end)
		if ok and typeof(ml) == "Vector2" then return ml end
	end
	return Vector2.new(vp.X / 2, vp.Y / 2)
end

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
		fovCircle.Position = getAimPoint()
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
	if not getgenv().CryptsHBELoaded then return end
	if Bridge.MenuOpen then return end   -- Auto-hide: don't extend hitboxes while the menu is open

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

-- ===== Auto-hide while the menu is open =====================================
-- When the LinoriaLib menu is open, hide ESP/FOV/chams + stop HBE extension + hide the
-- combat crosshair, so nothing is in the way while you click around the menu; restore on
-- close. Reuses the Streamer hide flags (ESP/FOV/chams already honor them) + sets
-- Bridge.MenuOpen (runUpdatePlayers + the combat crosshair + hit marker check it).
do
	local function menuOpen()
		local ok, t = pcall(function() return Library.Toggled end)   -- LinoriaLib: true = menu visible
		if ok and type(t) == "boolean" then return t end
		return false
	end
	local wasOpen, saved = false, nil
	RunService.Heartbeat:Connect(function()
		local want = (Toggles.menuAutoHide and Toggles.menuAutoHide.Value) and menuOpen()
		if want and not wasOpen then
			wasOpen = true
			saved = { Bridge.Streamer.hideESP, Bridge.Streamer.hideFOV, Bridge.Streamer.hideChams }
			Bridge.Streamer.hideESP, Bridge.Streamer.hideFOV, Bridge.Streamer.hideChams = true, true, true
			Bridge.MenuOpen = true
			pcall(resetAllPlayers); pcall(function() if resetWorldParts then resetWorldParts() end end)
		elseif (not want) and wasOpen then
			wasOpen = false
			Bridge.MenuOpen = false
			if saved then Bridge.Streamer.hideESP, Bridge.Streamer.hideFOV, Bridge.Streamer.hideChams = saved[1], saved[2], saved[3]; saved = nil end
		end
	end)
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
	local extendOn = getgenv().CryptsHBELoaded and Toggles.extenderToggled and Toggles.extenderToggled.Value
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
	if not getgenv().CryptsHBELoaded then return end
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
		local b = getgenv().CryptsHBE
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

	local screenPos = Vector2.new(pos.X, pos.Y)
	local distance = (screenPos - getAimPoint()).Magnitude

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

	local screenPos = Vector2.new(pos.X, pos.Y)
	local distance = (screenPos - getAimPoint()).Magnitude

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
					local dist = (Vector2.new(pos.X, pos.Y) - getAimPoint()).Magnitude
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
			local oldSel = part:FindFirstChild("CryptsHBE_Outline")
			if oldSel then oldSel:Destroy() end

			if Toggles.outlineMode and Toggles.outlineMode.Value then
				-- Outline Only: keep the REAL part ENLARGED (it's already sized to targetSize
				-- above) so the game's hit detection still recognises it. The previous version
				-- reset the part to its original size and put the big hitbox on a SEPARATE proxy
				-- part -- but games check the actual body part / character, not an extra welded
				-- part, so HB stopped registering. Now we just make the enlarged part invisible
				-- and trace it with a SelectionBox: a clean outline of the real hit area.
				part.Transparency = 1
				if part.Name == "Head" then
					local face = part:FindFirstChild("face")
					if face then face.Transparency = 1 end
				end
				-- Drop any proxy left by the older (broken) implementation.
				local oldProxy = part:FindFirstChild("CryptsHBE_HitProxy")
				if oldProxy then oldProxy:Destroy() end
				local sb = part:FindFirstChild("CryptsHBE_OutlineSB")
				if not sb then
					sb = Instance.new("SelectionBox")
					sb.Name = "CryptsHBE_OutlineSB"
					sb.Adornee = part
					sb.SurfaceTransparency = 1
					sb.LineThickness = 0.05
					sb.Parent = part
				end
				sb.Color3 = (Options.outlineColor and Options.outlineColor.Value) or Color3.fromRGB(255, 0, 0)
				sb.Transparency = (Options.outlineTransparency and Options.outlineTransparency.Value) or 0
				sb.SurfaceTransparency = 1
			else
				-- Normal extend: drop the outline SelectionBox + any old proxy; the real part
				-- stays enlarged + visible (sized/Massless/CanCollide already applied above).
				local sb = part:FindFirstChild("CryptsHBE_OutlineSB")
				if sb then sb:Destroy() end
				local proxy = part:FindFirstChild("CryptsHBE_HitProxy")
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
			local ob = part:FindFirstChild("CryptsHBE_Outline")
			if ob then ob:Destroy() end
			local px = part:FindFirstChild("CryptsHBE_HitProxy")
			if px then px:Destroy() end
			local osb = part:FindFirstChild("CryptsHBE_OutlineSB")
			if osb then osb:Destroy() end

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
					local ob = v:FindFirstChild("CryptsHBE_Outline")
					if ob then ob:Destroy() end
					local px = v:FindFirstChild("CryptsHBE_HitProxy")
					if px then px:Destroy() end
					local osb = v:FindFirstChild("CryptsHBE_OutlineSB")
					if osb then osb:Destroy() end
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
				teamEsp.Visible = false
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
					local baseCol = flashCol or ((Toggles.espNameUseTeamColor.Value and player.Team and pcall(function() return player.TeamColor.Color end) and player.TeamColor.Color) or Options.espNameColor1.Value)
					-- Proximity pulse: the closer the off-screen player, the more the marker
					-- grows + brightens (subtle, stays near the base colour). p = closeness 0..1.
					local sz, col = 10, baseCol
					if Toggles.espOffscreenPulse and Toggles.espOffscreenPulse.Value then
						local ref = (maxEspDist > 0 and maxEspDist) or 500
						local p = math.clamp(1 - distance / ref, 0, 1); p = p * p  -- ramp up only when close
						local wave = math.sin(tick() * (6 + p * 10)) * 0.5 + 0.5
						sz = 10 + 8 * p * wave
						col = baseCol:Lerp(Color3.fromRGB(255, 255, 255), 0.4 * p * wave)
					end
					offscreenMarker.Size = Vector2.new(sz, sz)
					offscreenMarker.Position = Vector2.new(markerPos.X - sz / 2, markerPos.Y - sz / 2)
					offscreenMarker.Color = col
					offscreenMarker.Visible = true
				else
					offscreenMarker.Visible = false
				end
			end
		else
			-- No torso target (respawning) or Streamer hideESP: hide EVERY 2D element,
			-- otherwise the last-drawn name/team/health/box/marker/skeleton stays frozen
			-- on screen as a stale floating artifact (the leftover squares/bars).
			nameEsp.Visible = false
			teamEsp.Visible = false
			healthBar.Visible = false
			healthText.Visible = false
			boxEsp.Visible = false
			tracer.Visible = false
			offscreenMarker.Visible = false
			hideSkeleton()
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
		getgenv().CryptsHBELoaded = true
	end
	pcall(updatePlayers)
	
	if Library and Library.Notify then
		Library:Notify("hai :3")
		-- ESP render path readout (helps diagnose Drawing issues per executor).
		Library:Notify("ESP draw: " .. (getgenv().CryptsHBE_UsingNativeESP and "Native Drawing" or "GUI fallback"))
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

-- ----- Vehicle/Misc tab EXTRACTED to plugins/vehicle.lua (Vehicle Assist, Tool Expander,
-- Manual Vehicle HBE, Vehicle Modify/Tuning, Vehicle ESP). Enable it from the Plugins tab. -----

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
		"V8 fix + feature pass. ESP now auto-routes Potassium/Solara through the GUI fallback (native Drawing constructs but doesn't render there) so names, 2D boxes and tracers finally show; the fallback overlay was corrected with IgnoreGuiInset and round circles, chams default to a visible red/white instead of invisible black, and Precision no longer freezes the target -- it defaults to extending the Head instead of the HumanoidRootPart (resizing the root is what froze them), sets enlarged parts Massless, and adds target stickiness so the lock stops thrashing between similar-distance players. New Combat tab adds a Weapon Reader (reads the held tool's name/type) and Target Groups (drag-select a box over players to track them with a cyan highlight). Added a Force-Restore-All button for stuck hitboxes; override the ESP path with getgenv().CryptsHBE_ForceGuiESP / _ForceNativeESP.",
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
		"Plugin externalization: the loader now fetches plugins from a Plugin Base URL (your GitHub raw folder, set in the Plugins tab or getgenv().CryptsHBE_PluginBase) as <base>/<file>.lua. The Gun Combat block (aimbot/triggerbot/no-recoil), Spectate and the Advanced tab (radar/movement/persistence/auto-soften) were moved OUT into their own files (aimbot.lua, spectate.lua, advanced.lua, precision.lua) and removed from the core (~835 fewer lines). Core helpers getSafeGuiParent + relationshipColor are exposed on the Bridge so external plugins can reuse them.",
		"Calibrate + Combat fix pass. Chams now default to AlwaysOnTop (see-through-walls wallhack) instead of Occluded. The Weapon Reader reads brand-named guns ('Weston Ranger') by inspecting their internals (Trigger/Barrel/Mag/Sight parts + ammo values) and now shows current/reserve ammo with a HUD-text fallback ('28 | 271'). Auto-Add Character Parts no longer dumps cosmetics/gear/weapon parts into the hitbox list (filtered), tracks exactly what it added, and adds Undo-Auto-Added + Reset-Body-Parts buttons. The scan also detects brand-named guns for Inf-Ammo. Tier-3 Learn now also snapshots HUD number labels so it catches ammo that lives only on-screen. Long scan / Phantom reports are capped on-screen (no more overlap) with Copy/Save-to-file buttons; profiles, the DB and saved reports now all live in a workspace/CryptsHBE/ folder and report their exact path. The Plugins tab shows a loaded/total summary and warns on startup that plugins are off.",
		"Stability + glitch sweep. Fixed stale ESP artifacts: a player with no torso (respawning) or with Streamer hideESP on now hides EVERY 2D element (name/team/health/box/tracer/off-screen marker/skeleton) -- before, several were left frozen on screen as floating squares/bars. The GUI-fallback renderer now rejects NaN/infinite coordinates and clamps every element's size/offset, so a bad projection can't smear a giant black bar across the top of the screen. Inf-Ammo's player-side scan is scoped to Backpack/leaderstats/Character ONLY (never PlayerGui/PlayerScripts) so it can't scribble the refill amount into the menu's own GUI state and corrupt the tabs. Vehicle Tuning now auto-detects the vehicle you're SITTING in (no manual pick needed) so the speed/handling writes have a target. Added Instant Interact on the Calibrate tab: sets every ProximityPrompt's HoldDuration to 0 (hold-to-interact becomes a tap), with restore-on-off and a live prompt count. Spectate reads the camera live so it survives a respawn. All core + 8 plugins Luau-compiler validated.",
		"Feature batch: Silent Aim + World + tooling. New SilentAim plugin (hook-free Remote mode that fires the chosen damage remote at the FOV-locked target, plus an opt-in Extreme __namecall-hook mode SCOPED to that one remote that redirects the game's own fire to the target's bone). New World plugin (Fullbright, No Fog, Custom FOV, Infinite Stamina -- all generic client visuals/utility). Vehicle Tuning gained a Speed Boost multiplier (stock top speed x1-5, relative to the captured base). Spectate now RequestStreamAroundAsync's the target's area (and yours on reset) so StreamingEnabled games don't get stuck in 'Gameplay Paused'. The Calibrate tab gained a Weapon Deep-Dump: writes the held weapon's full tree + every Value/attribute + its scripts' read-only string constants + gun-related remotes to workspace/CryptsHBE/, the raw data needed to build tailored per-game weapon hacks (inf-ammo/instant-reload/no-recoil/fire-rate) for server-side games where client value-writing can't work.",
		"Constrained-value + vehicle-physics pass. The whole script now treats Double/IntConstrainedValue as numeric (a TREK-style game stored ammo as DoubleConstrainedValue, so it was invisible to every scan -> inf-ammo now works). Inf-Ammo re-detects when its cached ammo objects get replaced (respawn re-creates the gun's value folder), fixing 'stops working after reset'. Outline Only now keeps the REAL part enlarged + invisible with a SelectionBox outline (the old proxy part wasn't recognised for hit-reg). Plugin unload now removes the empty tab (Bridge:RemoveTab). Vehicle Tuning gained physics detection: it counts Cylindrical/Hinge wheel motors, springs and body-movers, diagnoses the drive type, shows live actual speed + wheel spin, and adds a Wheel Motor Boost for constraint-driven vehicles with no speed value. Deep-Dump (weapon + new Picked-Vehicle button) now also prints constraint/body-mover physics props. The menu window is wider (720) so labels stop clipping; the changelog viewer is capped + copies full text to clipboard.",
		"Stability + per-game depth pass. Plugin unload now only HIDES the tab (the previous destroy-tab corrupted LinoriaLib -> tab/cursor glitches); re-enable un-hides it. Inf-Ammo clears its caches on respawn so it re-applies after death. The Learn 'Top -> Inf-Ammo Name' button now skips HUD-only labels and picks the first real value (no more false 'server-side' warning when a writable ammo value exists). Wheel Motor Boost now also force-amplifies the vehicle's velocity toward Multiplier x 60 (the lever that moves a server-driven chassis you own) + raises motor acceleration. The Weapons plugin now reaches stats kept in a config-type ModuleScript (requires config/settings/stat/tune/... modules and writes their matching numeric keys), so Fire Rate / No-Recoil / Reload can hit framework configs (e.g. TREK), and the Deep-Dump now prints those modules' actual values so the exact stat key is visible.",
		"TREK plugin (fire-rate breakthrough). TREK guns hide every stat behind Config:GetValue(name) -- not instance Values, attributes, or plain table keys -- so the generic Weapons scan found nothing. The new TREK plugin reaches them by WRAPPING GetValue (a pass-through that overrides the return for the keys we want) or, if the module is read-only, by mutating the backing table found in GetValue's upvalues. Fire Rate shrinks WindUp/WindDown (TREK has no FireRate key); also No Recoil / No Spread / Instant Reload. A live readout shows the detected module, active strategy, and current WindUp/WindDown values so you can SEE them drop, plus a Probe button that dumps GetValue + its upvalues to a file for adding new keys.",
		"Artillery plugin (Pordier siege guns). The game computes ArtilleryStats.TargetPos (the shell's landing point), so the plugin draws a red impact marker + a perspective-correct white scatter-radius circle + an optional shell arc PURELY READ-ONLY (no writes/remotes), plus a 'View Target' overhead camera so you watch the impact zone while W/S/A/D still aim. Detects the emplacement you're mounted on via Humanoid.SeatPart. Rate-of-fire is server-gated (ShootDelay/ServerLastShotTime are server-owned): Auto-Shoot fires the emplacement's own Shoot remote and the readout watches ServerLastShotTime to report accepted shots/sec, so you can SEE whether the server caps it. Everything restores on dismount/respawn/unload.",
		"Value Editor overhaul ('it's all just changing values'). Inspect Mode outlines the HUD element under your cursor + shows its path/number like a browser inspector (one-click Capture), fixing the 'no number under the cursor' misses with an engine + manual hit-test. The selected value is now HIGHLIGHTED (3D part Highlight or GUI outline) so you see what you're editing. READ-BACK verification on Set Once + Hold reports stuck / REVERTED (server-side) / clamped, so you KNOW if a write works instead of guessing -- and Hold counts server reverts live. If a HUD number has no backing value it still lists the label as display-only text. Kept the green/yellow/red detectability rating (now flags GUI-only text red).",
		"Visual/core batch. (1) Off-screen ESP markers now pulse (grow + slightly brighten) more as a player gets closer -- a subtle proximity indicator (Proximity Pulse toggle). (2) New Crosshair Mode (1st Person = screen centre, 3rd Person = follows your mouse cursor): the FOV Filter, Legit Mode, Auto-Expand, the FOV circle AND the combat crosshair all use this aim point, so 'only within crosshair' works in free-cursor 3rd-person games and the combat ring follows your cursor (not just on shiftlock). (3) Hit Marker: a small center-tick flash when an enemy's HP drops just after you attack -- deliberately NOT a fill/flash on the target so players behind the one you hit stay visible in crowds ('only when I attack' filter + colour picker).",
		"Section Loader plugin. Once your setup is dialled in, pick the plugins you use (whitelist), tick Config Finished, and Load Sections unloads every other loaded plugin (frees its connections/memory). An Engagement Logger samples the range you actually meet enemies at and reports avg/min/max + the most-used distance, with one-click Apply Suggested Distance to cut HBE+ESP reach to what you need (less work, smaller detection surface). Optional distance cutback on load.",
		"Firemodes in Weapon Stats. The Weapons plugin now detects the held gun's firemode (semi / bolt / pump / burst / auto from values/attributes/config/name), can Force Automatic by flipping a firemode VALUE, and has a universal Auto-Fire (rapid-click at an RPM slider) so a semi/bolt/pump gun sprays on games that fire per click client-side -- bind a key to the toggle to hold-spray. Games with no 'Automatic' keyword: 'Learn Held as Automatic' saves the weapon by name (workspace/CryptsHBE/learned_autos.json) so it's recognised next time. Now 15 plugins.",
		"Deep-dive expansion. The core vehicle Deep-Dump now prints a Vehicle Profile: type guess (plane/heli/tank/armoured/car/ATV/artillery), tracked-vs-wheeled, gun/turret detection + its ammo values. New 'Extended Deep Dive' sub-button (Calibrate) drives a new DeepDive plugin that REQUIRES config modules + reads script UPVALUES (surfacing TREK-style GetValue stats + cached tables the static dump can't), correlates taskbar operator-tools to a vehicle's remotes, dumps custom NON-Tool inventories (the Bleeding Blades case -- character/player/ReplicatedStorage weapons + combat remotes, the data for the Invalid-Attack fix), and an all-remotes dump. Now 16 plugins.",
		"Artillery extras. The Artillery plugin gained an Elevation Override (push past the aim cap for more range; read-back shows applied vs server-re-clamped) and Inf Turret Ammo (holds any ammo/shell/round value on the emplacement at max, separate from the gun Inf Ammo so it leaves the working one alone). Both restore on dismount/respawn/unload.",
		"Remote Sniffer plugin (opt-in, DETECTABLE). Logs the game's OUTGOING FireServer/InvokeServer calls WITH their arguments via a read-only, scoped __namecall hook (skips the script's own calls; never alters a call) so you can read the exact payload to replay -- the real damage/hit remote for Bleeding Blades' Invalid-Attack, the artillery Shoot args, shop-purchase remotes. OFF by default, never persisted on (no auto-hook on inject), inert when off or on PANIC, with combat/economy + name filters, a live view and Save-to-file. Now 17 plugins.",
		"Feedback batch. Keybinds tab (central, default) -- core binds moved there + Bridge:AddKeybind so plugins register binds (Auto-Fire is now bindable Hold-to-spray; this is the 'go automatic' path on bolt/semi/pump since they have no firemode value). Value Editor: Pick-HUD is now hover-LOCK based (the target locks when you move onto the menu, fixing the stray-click bug; capture via button or a bindable key) + animated outline colour. Session numbering: every dump/scan/probe gets a _S<N> tag that bumps each load/reattach. Artillery: the scatter circle now raycasts to the GROUND (conforms to terrain, no longer floats), the View-Target camera is smoothed + gimbal-guarded (fixes the up/down glitch), and shell impacts flash the hit marker. New Engineer plugin (Prodier shovel): Auto-Swing (bindable), Instant Build (max a structure's progress/Health with read-back), war-year-gate bypass. Now 18 plugins.",
		"Recon deep-dive suite (1 plugin, 10 read-only tools). Damage Model (per held weapon: touch/raycast/remote -> RECOMMENDS the combat tool + warns when HBE = invalid), Module API map (require every ReplicatedStorage module + dump its table shape), GC/Closure scan (config/stat/ammo/anti tables + functions), Networking/Ownership (isnetworkowner + sim radius -> what you can physics-control), Animation/Timing (tool anim IDs + tracks playing + lengths), Input/Binds (KeyCodes referenced by LocalScripts), Map/World (spawns/teams/objectives/loot/prompts/seats), Economy/Shop (currency + items/prices + purchase remotes), Character/Rig (a target's parts/joints/hitbox names for HBE bones), Anti-Cheat (Phantom Recon summary + AC-named scripts). All reports session-tagged to workspace/CryptsHBE/. Now 19 plugins.",
		"Core slim-down #1: the whole Vehicle/Misc tab (Vehicle Assist, Combat Tool Expander/Scanner, Manual Vehicle HBE, Vehicle Modify/Tuning + Wheel Motor Boost, Vehicle ESP -- ~1,170 lines) was EXTRACTED to a Vehicle plugin (vehicle.lua), dropping the core from ~6,980 to ~5,810 lines. Behaviour is unchanged (the three original blocks run verbatim; only the tab handle now comes from the plugin context, and it builds once so re-enabling won't duplicate groupboxes). Enable 'Vehicle' from the Plugins tab to get the tab back. Now 20 plugins.",
		"Combat plugin-GATED (kept inline). The Combat tab (Weapon Reader, Target Groups, Silent Melee, Tool Hitbox Editor) is too integrated to move safely (it publishes Bridge.Weapon/TargetGroup), so the code stays in the core but is now gated: the tab is hidden by default and every action loop (melee swing, kill-aura, crosshair, weapon-reader, drag-select) early-returns until the Combat plugin sets Bridge.CombatActive. Enable 'Combat' from the Plugins tab to show the tab + activate it (works with Section Loader too). Now 21 plugins.",
		"Economy plugin + World markers. Economy (new tab): scan currency values (cash/points/score/kills/time), WATCH one -- it logs each gain and labels it AUTOMATIC (server granted on kill/time) vs via-your-fire; scan grant remotes (award/reward/kill/score/earn...), pick one + args, and Fire Once / Auto-Farm to duplicate the earn request, with currency read-back proving WORKS (client-grantable) vs no-change (server-authoritative). World plugin gained World Markers: objective + loot/ammo ESP (name + distance) with Teleport-to-Nearest-Loot/Objective. Now 22 plugins.",
		"Value Editor plugin-aware hints. When you hover a value (Inspect Mode) or select one, it now suggests the dedicated plugin that handles that KIND of value -- ammo -> Inf Ammo, fire-rate/recoil -> TREK, cash/score/kills -> Economy, speed/torque -> Vehicle, stamina -> World, build -> Engineer -- shown as a subtle second line on the hover tag (and a 'Better handled by:' line on the selected value). Only suggests a plugin that's actually registered; otherwise stays out of the way.",
		"Calibrator + Recon fixes (from new dumps). Added TREK to the Calibrate framework fingerprint (TREK_SERVICES/TREK_Remotes/TREKGun -> 'enable TREK plugin') -- it was never in the list, so TREK games weren't auto-flagged (nothing was removed). Recon Anti-Cheat now scans GAME containers only + skips CorePackages/CoreGui (was flooding with Roblox-internal false positives like validateOperation/Semantic). Economy currency scan now also reads PlayerGui TextLabels (points like Pordier's 122/585 are a HUD label, not a leaderstat, so the value-only scan missed them).",
		"Menu auto-hide + fixes. New 'Auto-hide while menu open' (Settings, default ON): while the LinoriaLib menu is open it hides ESP/FOV/chams + the combat crosshair and stops HBE extension (via Library.Toggled + the Streamer hide flags + Bridge.MenuOpen), restoring on close. Engineer Instant Build now throttles its write to ~5Hz (kills the lag) and the read-back says REVERTED -- server-side build when value-writes don't stick (which is why it only ticks up 1/swing -- the build is server-validated; Auto-Swing is the only client lever). Economy now detects HUD-label points; note that editing currency is VISUAL-ONLY on server-authoritative games (you can't spend it) -- the real path is replaying the server's award remote (e.g. KilledBy) captured via the Remote Sniffer.",
		"Remote Sniffer -> Fire (replay). Captured calls now store their raw args, so you can Replay Once / Auto-Replay (rate) a captured call -- the one lever for server-side things value-writes can't touch: farm points (replay a kill/award remote like KilledBy), bolt -> pseudo-full-auto (replay the gun's Shoot), or the Bleeding Blades legit-hit replay. 'Retarget to nearest enemy' swaps Player/Vector3 args to turn a captured hit into a silent one. If the server validates the call it won't land (server limit, not a bug).",
		"Smart Setup + hint-jump. Calibrate is now the suite's brain: 'Smart Setup -> Recommend Plugins' fingerprints the game (frameworks incl. TREK, guns, vehicle seats, shields/melee, currency, build tools) and lists the plugins it needs; 'Enable Recommended' loads them all in one click. The Value Editor's plugin hint gained an 'Enable Suggested Plugin' button (one click to load the tool for the hovered/selected value's kind). Both make per-game setup near-automatic.",
		"QOL batch. (1) Performance/Health monitor: live FPS + Lua memory (MB) + plugins loaded/total + tracked + status, shown on the watermark AND a colour-coded 'Health' label (green/yellow/red by FPS) in Performance; Bridge.FPS() exposed. (2) Plugin Manager QOL: per-plugin status colour (green loaded / red failed / grey off), Enable ALL / Disable ALL, and file-based Auto-Enable-on-inject (save your favourite plugins -> they auto-load every run, via workspace/CryptsHBE/autoenable.json). (3) Keybind QOL: bind Toggle HBE + Toggle ESP (PANIC already bindable) in the Keybinds tab.",
		"Config Presets (Settings -> Config Presets). Three one-click bundles: Legit (small crosshair/FOV-gated hitbox, jitter on, nearby-only, minimal ESP, every rage/combat feature off), Rage (big hitbox on everyone, full ESP, hit marker + combat assists on), Visuals-only (hitbox + every combat feature off, full ESP, MasterToggle stays on so ESP keeps running). Each writes a curated map through the safe (Options/Toggles):SetValue path (nil-guarded -> keys for unloaded plugins are skipped) and reports 'N set / M skipped'. Save/Load-ALL is still the SaveManager named configs in Configuration Profiles.",
		"AnimCancel plugin (tab 'Anim', 23rd plugin). Cancels or speeds up the per-shot FIRING/RELOAD animation so it stops gating your rate of fire -- for artillery, bolt-action guns and melee. Collects animators from you + your held tool + the seated emplacement/vehicle model (artillery's shoot anim plays on the emplacement, not you), then Stop()s or AdjustSpeed()s any track matching Keywords / Learned-ids / All-but-movement. 'Learn Action' captures the shot anim id when you fire once; 'Scan Playing Tracks' writes everything currently playing to file. Direct API (GetPlayingAnimationTracks + Stop/AdjustSpeed), NOT a hook -> detection-safe. HONEST: only wins if the gun gates on the track client-side; a fixed task.wait or a server cooldown (ServerLastShotTime / LastShotServer -- Pordier artillery + bolt both have one) still caps you. Confirm via your weapon's real rate / the Artillery 'Accepted' readout.",
		"Dot ESP plugin (tab 'Dots', 24th plugin). Small team-coloured dots floating above players' heads -- like the squad-ping some games put on a held key. Toggle teammates and/or enemies, dot size + float height + its OWN max distance (independent of HBE), team colours via the core relationshipColor. Bound to a toggle hotkey (default V) through the central Keybinds tab. Read-only WorldToViewportPoint projection on a filled-circle pool; honours Streamer hide + menu auto-hide. Keys in PG_KEYS + dotEspEnabled in PANIC.",
		"Artillery: Aim Ring. New 'Aim Ring (where you look)' toggle draws the scatter/landing ring at the terrain point your CAMERA is aimed at (raycast from the view), instead of only the game's ArtilleryStats.TargetPos -- so the radius shows LIVE as you turn the gun and works even when TargetPos is empty/zero (which is why nothing showed before off-target). Ground-conformed like the existing ring; the centre label reads AIM vs IMPACT. Arc + View-Target camera still use the real TargetPos.",
		"Economy/Sections/Weapons batch. (1) Economy 'Rank Remotes by points': fires EACH scanned grant remote once, measures the watched currency's delta, ranks them and auto-selects the winner; 'Farm Best' farms the top one. Honest -- all +0 means server-authoritative or wrong args. (2) Section Loader engagement logger now tracks PER-HITBOX: classifies which body part of the nearest enemy is closest to your aim ray (Head/Torso/Limb), reporting average engagement range + most-aimed part per class, so you can size headSize/torsoSize/limbSize to where you actually fight. (3) Weapons 'Find Fire-Rate Values (wide)': read-only scan listing every rate/cooldown/RPM value across the held tool + character + ReplicatedStorage config modules with full paths -- because the Fire Rate Boost only writes tool-local values, but bolt-gun cooldowns usually live in an RS module. Locate it, then write it (Fire Rate Boost or Value Editor). 'It's all just changing values' once you know which one.",
		"Bleeding Blades batch (decoded the S4 dumps). New BleedingBlades plugin (tab 'Blades', 25th plugin): Model Picker (aim + pick any humanoid/horse/object -> dump its structure + the Combat remotes that act on it, for spectating); Combat Remotes (fire ReplicatedStorage.Combat.PHit [hit] / CreateProjectile [arrow] / Mount [horse] with sniffed args -> the bypass/arrow lever); Server Monitor (read-only listen to the game's message remotes -> shows the 'Server:' validator messages = Invalid Attack / Fall damage / kills); subtle Walk Speed (capped, HeightDetect-aware); experimental Auto-Block (holds MB2 while a DirectionUI telegraph shows) + Dump DirectionUI to map the directional parry. Plus: Vehicle ESP now auto-classifies HORSES (Workspace.Ride / Saddle seats -> 'Horse' type); World Markers now flag bolt/arrow REFILL stations. HONEST: melee is server-validated (no touch conns) so HBE stays off here; PHit/CreateProjectile replay only lands if the server doesn't re-validate -- capture their args with the Sniffer (filter OFF).",
		"Bleeding Blades: Ghost Strike (desync). The honest melee lever -- HBE / Precision HBE / melee-extender all FAIL in BB (server validates your real position, no touch conns, so they trigger the Invalid-Attack kill). But you OWN your HRP (network owner), so the server trusts its position: Ghost Strike saves your spot, CFrames the HRP next to the chosen target, swings (VirtualInputManager LMB), and snaps home -- a legitimate adjacent hit. Cycle Target switches to the next-nearest enemy. Tunable Y offset / strike distance / return delay (keep small + fast vs the per-player HeightDetect + server anti-teleport). Keys F (strike) / T (cycle) in the Keybinds tab. Best-effort v1; true 'body stays home' desync is v2.",
		"Bleeding Blades: Ghost Hold + smarter Auto-Block. (1) Ghost Hold (hold key G): pins your HRP next to the current target so you can swing repeatedly (server keeps seeing you adjacent), release -> snap home -- the controllable 'go to them, kill, come back' version (more exposure -> more HeightDetect risk). (2) Auto-Block rebuilt: the DirectionUI dump showed its arrows are all Visible=true (your OWN block-direction ring; the active one differs by colour/transparency, there's no incoming-direction telegraph), so Auto-Block now triggers on a real THREAT -- holds MB2 while an enemy is within Block Range and facing you. New Block Range slider.",
		"Bleeding Blades: picker/monitor fixes + 3 combat builds. FIXES: Model Picker now arms then captures your next WORLD click (was grabbing whatever's behind the menu); Server Monitor now listens to EVERY RemoteEvent + reads table args (was watching too few). NEW: (1) precise auto-parry -- reads the lit DirectionFrame arrow + 'Face threat while blocking' rotates you toward the nearest attacker so your block covers them; (2) v2 desync-lite -- 'Hold: keep camera home' locks your view to your start spot during Ghost Hold so your body fights at the target while you watch from home; (3) Arrow Predict -- lead + drop aim marker on the nearest enemy for archery (tunable arrow speed + gravity). All balanced-risk, experimental, OFF by default.",
		"Bleeding Blades: teleport pivot + better remote capture. Confirmed in-game the server validates position (logs the teleport + rubberbands), so Ghost Strike/Hold teleport is a dead end -- the only melee lever left is firing PHit directly (no movement). Picker rebuilt on the shared hold-ring (StartHoldPick) + resolves a clicked shield/weapon/helmet up to its CHARACTER. Since the RemoteSniffer barely captures in this custom game, added a Capture/Inspect group: 'Capture Combat' = a scoped __namecall hook logging ONLY Combat.* FireServer calls + args for 15s (no filter to misconfigure, auto-stops); 'Inspect Combat Scripts' = reads the combat LocalScripts' string constants + Instance env vars (getscriptclosure/debug.getconstants/getsenv) to find the remote + how the hit is built WITHOUT a hook. Either gives the PHit/CreateProjectile args -> the silent kill.",
		"Blackout plugin (tab 'Blackout', 26th plugin) -- anti-detection. (1) Instant Blackout (key Insert / button): hides EVERY cheat visual (Streamer hide flags) + the menu + all executor GUIs (gethui sweep) so your screen looks like vanilla gameplay, with an optional full-black overlay; press again to restore. (2) Auto-Blackout: watches PlayerGui text for anti-cheat words (invalid/cheat/ban/kick/teleport/detected/...) and on a match auto-blackouts + disables risky features (ghost/aimbot/silent/extender/sniffer). (3) UI Cloak: reparents the menu under gethui() so the game's scripts can't enumerate it in PlayerGui (drawings already use getSafeGuiParent -> gethui). Exposes Bridge.TriggerBlackout(on). Pure local hiding, no game writes.",
		"Bleeding Blades round 4 (from in-game tests). Server Monitor now works -- it caught the hit feed via Admin.CallBack (ServerLog/ProjectileLog '<player> Hit <player> <n>'). Arrow Predict gained the TRAJECTORY ARC: simulates the projectile from your bow along your aim under the tunable gravity and draws the flight path + ground landing point (you wanted the arc, not just a dot). New Arrow Ammo (Inf Arrows): bows aren't Tools so Inf Ammo can't register them -- this scans you for arrow/ammo/bolt/quiver values + holds them full (client-side). New experimental Weapon Reach: scales the held weapon's blade for reach (almost certainly server-invalidated like HBE -- labelled, to try). AnimCancel now warns that 'Cancel (stop)' BRICKS state-machine melee (sword combat freezes until death) -- use Speed-up for melee, Cancel for guns/bows. Ghost teleport still dead (rubberband + logged) -- the silent PHit-fire (pending the Capture/Inspect args) remains the only real melee lever.",
		"Bleeding Blades round 5: the combat wall. Capture caught ONLY WaistRotation with a serialized binary buffer (packet lib) -- PHit/CreateProjectile never fired -- and firing PHit raw -> server 'ProjectileID missing' (it needs a valid server-tracked projectile id). BB combat is heavily protected (serialized packets + ProjectileID + position validation + server hit-feed via Admin.CallBack), so the silent kill likely isn't practical. Changes: Capture now logs ALL FireServer/InvokeServer except noisy packets (so a real LANDED hit reveals the remote -- re-capture while actually connecting). Ghost is now OFF by default (master Enable toggle; F/G/T do nothing until on) since teleport just rubberbands -- the 'clone desync that kills while your real body stays' isn't achievable in Roblox. Inf Arrows extended to throwables (javelin/pilum/dart/throw/spear). Weapon Reach confirmed dead (doesn't register).",
		"AnimCancel fix + auto-bow recon. AnimCancel now RESTORES sped-up tracks to normal speed when you disable it (was leaving looping anims fast -> bugged character) and defaults to Speed-up (Stop bricks state-machine melee). Toward the user's auto-bow idea (legit ProjectileID from firing the bow -> PHit it at the crosshair target, sidestepping 'ProjectileID missing'): the BB Capture now shows binary/serialized packet args as length+printable+HEX (decodable) and, during the window, auto-dumps every spawned arrow/projectile instance's attributes + child values (where the server-issued ProjectileID lives). Capture prompt now says FIRE A BOW at an enemy (the swing-only captures missed CreateProjectile/PHit).",
		"Bleeding Blades: Bow Silent Aim (homing) -- the no-forge method. When you fire and a new arrow spawns near you, it's steered into the nearest FOV enemy (AssemblyLinearVelocity + CFrame toward target). If the arrow is client-owned this curves it into the target and the game's OWN hit + PHit fire legit -- no forging, no 'ProjectileID missing'. If the server simulates the arrow it's a harmless no-op. FOV + range sliders. Also: AnimCancel default keywords are now PROJECTILE-SAFE (dropped the melee swing/slash/stab words that brick BB's sword state machine even with Speed-up); add them back per-game if needed.",
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
		if not (Library and mainWindow and getgenv().CryptsHBE and Toggles.MasterToggle
			and Toggles.extenderToggled and Options.extenderSize) then return "red" end
		if type(players) ~= "table" or not runUpdatePlayers then return "red" end
		local addons = (getgenv().CryptsHBE.Addons) or {}
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
		tipGui.Name = "CryptsHBE_StatusTip"; tipGui.ResetOnSpawn = false
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
	-- Cap the on-screen note: long entries grew the label so tall it pushed the toggle
	-- button off-screen and you couldn't fold it back up. Full text copies to clipboard.
	local function capCL(s)
		local MAX = 360
		if #s > MAX then return s:sub(1, MAX):gsub("%s+%S*$", "") .. " ... (full text copied to clipboard)" end
		return s
	end
	clGroup:AddButton("View Changelog", function()
		if clShown then
			notesLabel:SetText("Select a version and click 'View Changelog'.")  -- fold back up
			clShown = false
		else
			local v = Options.clVersion.Value
			local full = (v and notesFor[v]) or nil
			if full then pcall(function() if setclipboard then setclipboard(v .. ":\n" .. full) end end) end
			notesLabel:SetText(full and (v .. ":\n" .. capCL(full)) or "No notes for that version.")
			clShown = true
		end
	end):AddToolTip("Show/hide the changelog for the selected version (full text -> clipboard)")

	-- Live status refresh; the loop exits cleanly when the script unloads.
	task.spawn(function()
		while getgenv().CryptsHBEInjected do
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
	local PG_FILE = "CryptsHBE_Game_" .. tostring(game.PlaceId) .. ".json"
	local PG_KEYS = {
		"MasterToggle","extenderToggled","extenderSize","extenderTransparency","hitboxShape",
		"partSpecificSizing","headSize","torsoSize","limbSize","dynamicSizing","smoothTransitions",
		"transitionSpeed","collisionsToggled","outlineMode","outlineTransparency","maxDistance",
		"closestTargetsOnly","maxTargets","updateRate","perfAdaptive","perfFpsFloor","randomizationToggled","randomizationAmount",
		"humanizationToggled","legitModeToggled","crosshairMode","menuAutoHide","seatDisableHBE","seatRadiusMode","seatRadius","seatExitDelayEnabled","seatExitDelay",
		"espNameToggled","espNameSize","espHighlightToggled","espBoxToggled","espBoxScale",
		"espTracerToggled","espSkeletonToggled","espHealthBarToggled","espNameType","espMaxDistance",
		-- ESP extras + anti-detect
		"espRainbow","espRainbowSpeed","espThickness","espDistanceFade","espChamsGlow","espOffscreenPulse",
		"hitMarkerEnabled","hitMarkerAttackOnly",
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
		"vmInfGas","vmFullHealth","vmSetSpeed","vmTopSpeed","vmSpeedMult","vmSpeedMultX","vehWheelBoost",
		"vehBoost","vehTargetSpeed","vehAccel","vehTurnRate","vehTurnAngle","vehTurnAccel","vehStability","vehStabilityStrength","vehKeepOwnership",
		"streamerMaster","hideFOVCircle","hidePlayerESP","hideChams","hideHitboxGlow",
		"weaponReaderAuto","groupRadius",
		"silentMeleeEnabled","silentMeleeMode","silentMeleeRange","silentMeleeFOV","silentMeleeOnlyMelee","silentMeleeAura","silentMeleeAuraRate","silentMeleeIgnoreTeam","silentMeleeIgnoreWL","silentMeleeCrosshair","silentMeleeWallPen","silentMeleeShieldBypass","shieldNames",
		"calApplyParts","calApplyAmmo","calApplyShields","deepScanEnabled","profileSourceUrl","pluginBaseUrl",
		"instantInteract","interactDistance",
		"fullbright","noFog","customFovEnabled","customFov","infStamina",
		"weaponNoRecoil","weaponNoDrop","weaponInstantReload","weaponFireRate","weaponFireRateX","weaponFireRateMode",
		"weaponForceAuto","weaponAutoFire","weaponAutoRPM",
		"trekFireRate","trekFireRateX","trekFireRateMode","trekNoRecoil","trekNoSpread","trekInstantReload",
		"artTrajectory","artAimRing","artScatterRadius","artArc","artTargetCam","artCamHeight","artCamBack","artAutoShoot","artShootRate","artDelayOverride","artDelayValue","artElevOverride","artElevExtra","artInfTurret",
		"secFinished","secApplyDist","secHBEDist","secESPDist",
		-- RemoteSniffer: persist the filters but NOT sniffActive (never auto-install a hook on inject).
		"sniffCombatOnly","sniffFilter","sniffShowArgs","sniffRetarget","sniffAutoReplay","sniffReplayRate",
		"engAutoSwing","engSwingRPM","engInstantBuild","engYear",
		"ecoArgs","ecoAutoFarm","ecoRate","worldMarkers","worldMarkerDist",
		"saEnabled","saMethod","saBone","saPriority","saLock","saFOVCircle","saFOV","saMaxDist","saHitChance","saLOS","saIgnoreTeam","saIgnoreWL","saRemote","saArg","saActivate","saRate","saRedirect","saHook",
		"aimbotEnabled","aimbotTrigger","aimbotPart","aimbotFOV","aimbotSmooth","aimbotVisibleOnly","aimbotIgnoreTeam","aimbotIgnoreWL","aimbotShowFOV",
		"triggerEnabled","triggerActivate","triggerDelay","triggerIgnoreTeam","norecoilEnabled",
		"aimbotPredict","aimbotBulletSpeed","aimbotDropComp",
		"radarEnabled","radarRange","radarSize","bhopEnabled","infJumpEnabled","autoSoften","persistEnabled","persistUrl",
			"animCancelEnabled","animMode","animSpeed","animFilter","animKeywords",
			"dotEspEnabled","dotEspAllies","dotEspEnemies","dotEspTeamColor","dotEspSize","dotEspHeight","dotEspDist",
			"bbWalkEnabled","bbWalkSpeed","bbServerMonitor","bbCombatArgs","bbGhostY","bbGhostOffset","bbGhostReturn","bbBlockRange",
			"bbBlockFace","bbGhostCamLock","bbArrowPredict","bbArrowSpeed","bbArrowDrop",
			"blackoutOverlay","blackoutAuto","blackoutWords",
			"bbArrowAmmo","bbArrowAmt","bbArrowName","bbReach","bbReachX","bbGhostEnabled",
			"bbBowAim","bbBowFov","bbBowRange",
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
			"vmInfGas", "vmFullHealth", "vmSetSpeed", "vmSpeedMult", "vehWheelBoost", "vehBoost", "vehStability", "rrAuto",
			"aimbotEnabled", "triggerEnabled", "norecoilEnabled", "bhopEnabled", "infJumpEnabled",
			"instantInteract", "vmSpeedMult", "fullbright", "noFog", "customFovEnabled", "infStamina",
			"saEnabled", "saHook", "weaponNoRecoil", "weaponNoDrop", "weaponInstantReload", "weaponFireRate",
			"trekFireRate", "trekNoRecoil", "trekNoSpread", "trekInstantReload",
			"artTargetCam", "artAutoShoot", "artDelayOverride", "artElevOverride", "artInfTurret",
			"veHold", "veInspect", "hitMarkerEnabled", "secFinished", "secApplyDist",
			"weaponForceAuto", "weaponAutoFire", "sniffActive", "engAutoSwing", "engInstantBuild",
			"ecoAutoFarm", "worldMarkers", "sniffAutoReplay", "animCancelEnabled", "dotEspEnabled",
			"bbWalkEnabled", "bbAutoBlock", "bbServerMonitor",
		}) do
			pcall(function() if Toggles[k] then Toggles[k]:SetValue(false) end end)
		end
		pcall(function() if resetAllPlayers then resetAllPlayers() end end)
		pcall(function() if resetWorldParts then resetWorldParts() end end)
		local b = getgenv().CryptsHBE
		if b and b.Streamer then
			b.Streamer.hideESP, b.Streamer.hideChams, b.Streamer.hideFOV, b.Streamer.hideHitbox = false, false, false, false
		end
		Library:Notify("PANIC: every feature off, all hitboxes/visuals restored")
	end):AddToolTip("One click: turn every feature off and restore all hitboxes/visuals to normal")
end)

-- ===== Config Presets (Legit / Rage / Visuals-only) =====
-- One-click curated bundles. Each preset writes an explicit map of core control
-- values through the LinoriaLib setter ((Options[k] or Toggles[k]):SetValue) --
-- the same nil-guarded path PANIC and the per-game profile use, so keys for
-- plugins that aren't loaded are simply skipped. These are buttons, not toggles,
-- so there's nothing to persist. Save/Load-ALL already lives in the
-- "Configuration Profiles" groupbox above (SaveManager named configs).
pcall(function()
	local presetGroupbox = profilesTab:AddLeftGroupbox("Config Presets")
	presetGroupbox:AddLabel("One-click bundles -- tweak after.", true)
	presetGroupbox:AddLabel("Save/Load ALL = Configuration Profiles.", true)

	local function applyPreset(label, map)
		local set, skip = 0, 0
		for k, v in pairs(map) do
			local c = Options[k] or Toggles[k]
			if c and pcall(function() c:SetValue(v) end) then
				set = set + 1
			else
				skip = skip + 1
			end
		end
		Library:Notify(("Preset '%s': %d set, %d skipped"):format(label, set, skip))
	end

	-- Legit: subtle, low-detectability. Small hitbox, crosshair/FOV-gated, jittered,
	-- nearby only; minimal ESP (names + health); every rage/combat feature OFF.
	local LEGIT = {
		MasterToggle = true, extenderToggled = true, outlineMode = false,
		extenderSize = 8, maxDistance = 250,
		legitModeToggled = true, fovFilterToggled = true,
		randomizationToggled = true, humanizationToggled = true,
		hitMarkerEnabled = false,
		espNameToggled = true, espHealthBarToggled = true,
		espHighlightToggled = false, espBoxToggled = false,
		espTracerToggled = false, espSkeletonToggled = false,
		espMaxDistance = 500,
		precisionEnabled = false, silentMeleeEnabled = false, silentMeleeAura = false,
		aimbotEnabled = false, triggerEnabled = false, saEnabled = false,
		weaponForceAuto = false,
	}

	-- Rage: maximum coverage + every visual on; combat assists ON (nil-guarded, so
	-- they only fire for the plugins you've actually loaded). Loud by design.
	local RAGE = {
		MasterToggle = true, extenderToggled = true, outlineMode = false,
		extenderSize = 80, maxDistance = 1000,
		legitModeToggled = false, fovFilterToggled = false,
		randomizationToggled = false, humanizationToggled = false,
		hitMarkerEnabled = true,
		espNameToggled = true, espHealthBarToggled = true,
		espHighlightToggled = true, espBoxToggled = true,
		espTracerToggled = true, espSkeletonToggled = true,
		espMaxDistance = 1000,
		silentMeleeEnabled = true, aimbotEnabled = true, triggerEnabled = true,
	}

	-- Visuals-only: full ESP, ZERO hitbox/combat. MasterToggle stays ON so the ESP
	-- loop keeps running; the hitbox extender and every combat feature are OFF.
	local VISUALS = {
		MasterToggle = true, extenderToggled = false, outlineMode = false,
		precisionEnabled = false,
		legitModeToggled = false, fovFilterToggled = false, hitMarkerEnabled = false,
		espNameToggled = true, espHealthBarToggled = true,
		espHighlightToggled = true, espBoxToggled = true,
		espTracerToggled = true, espSkeletonToggled = true,
		espMaxDistance = 1000,
		silentMeleeEnabled = false, silentMeleeAura = false,
		aimbotEnabled = false, triggerEnabled = false, saEnabled = false,
		weaponForceAuto = false, infAmmoEnabled = false,
	}

	presetGroupbox:AddButton("Apply Legit", function() applyPreset("Legit", LEGIT) end):AddToolTip("Subtle: small crosshair/FOV-gated hitbox, jitter on, nearby only, minimal ESP, all rage features off.")
	presetGroupbox:AddButton("Apply Rage", function() applyPreset("Rage", RAGE) end):AddToolTip("Loud: big hitbox on everyone, full ESP, hit marker + combat assists on (if those plugins are loaded).")
	presetGroupbox:AddButton("Apply Visuals-only", function() applyPreset("Visuals-only", VISUALS) end):AddToolTip("ESP only: hitbox extender + every combat feature OFF, all visuals on. Safest.")
	print("[Presets] Legit / Rage / Visuals-only ready")
end)

-- ===== Hit Marker: non-occluding center-tick on a confirmed hit =====
-- Watches every enemy's Humanoid.Health; when one drops shortly after you attack, flash a
-- small crosshair tick at the aim point. No fill/outline on the target, so a player behind
-- the one you hit stays fully visible -- the point the user made about crowded fights.
pcall(function()
	local hmLines = {}
	for _ = 1, 4 do
		local ln = DrawingFallback.new("Line")
		ln.Thickness = 2; ln.Color = Color3.fromRGB(255, 255, 255); ln.Visible = false
		hmLines[#hmLines + 1] = ln
	end
	local lastAttack = 0
	UserInputService.InputBegan:Connect(function(input, gp)
		if not gp and input.UserInputType == Enum.UserInputType.MouseButton1 then lastAttack = tick() end
	end)
	local function isEnemy(plr)
		if plr == lPlayer then return false end
		local ok, ally = pcall(function()
			if lPlayer.Team ~= nil or plr.Team ~= nil then return lPlayer.Team == plr.Team end
			return lPlayer.TeamColor == plr.TeamColor
		end)
		return not (ok and ally)
	end
	local hpCache = {}
	local flashUntil = 0
	local function showMarker(on)
		if not on then for _, ln in ipairs(hmLines) do ln.Visible = false end return end
		local c = getAimPoint()
		local col = (Options.hitMarkerColor and Options.hitMarkerColor.Value) or Color3.fromRGB(255, 255, 255)
		local r1, r2 = 4, 10
		local diag = { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }   -- 4 diagonal ticks
		for i, d in ipairs(diag) do
			local ln = hmLines[i]
			ln.Color = col
			ln.From = c + Vector2.new(d[1] * r1, d[2] * r1)
			ln.To = c + Vector2.new(d[1] * r2, d[2] * r2)
			ln.Visible = true
		end
	end
	-- Let other modules (e.g. artillery shell impacts) flash the marker even when the
	-- auto-detector toggle is off -- shells travel too long for the 0.5s attack window.
	Bridge.FlashHitMarker = function(dur) flashUntil = math.max(flashUntil, tick() + (dur or 0.2)) end
	RunService.Heartbeat:Connect(function()
		local now = tick()
		if Bridge.MenuOpen then showMarker(false); return end   -- hide while menu open
		if Toggles.hitMarkerEnabled and Toggles.hitMarkerEnabled.Value then
			local attackOnly = not (Toggles.hitMarkerAttackOnly and not Toggles.hitMarkerAttackOnly.Value)
			for _, plr in ipairs(Players:GetPlayers()) do
				if isEnemy(plr) then
					local c = plr.Character
					local hum = c and c:FindFirstChildWhichIsA("Humanoid")
					if hum then
						local prev = hpCache[plr]
						if prev and hum.Health < prev - 0.01 then
							if (not attackOnly) or (now - lastAttack < 0.5) then flashUntil = now + 0.15 end
						end
						hpCache[plr] = hum.Health
					end
				end
			end
		end
		showMarker(now < flashUntil)
	end)
end)

-- ===== [Improvement #15] On-screen watermark + Performance/Health monitor =====
pcall(function()
	local grp = performanceGroupbox or mainTab:AddRightGroupbox("UI")
	grp:AddToggle("showWatermark", { Text = "Show Watermark", Default = false, Tooltip = "On-screen watermark: FPS | memory | plugins | tracked | status. (Default: OFF)" }):OnChanged(function()
		pcall(function() Library:SetWatermarkVisibility(Toggles.showWatermark.Value) end)
	end)
	pcall(function() Library:SetWatermarkVisibility(Toggles.showWatermark.Value) end)
	-- Health readout (colour-coded by FPS) in the Performance box.
	local healthLabel = grp:AddLabel("Health: -", true)
	local function tintLabel(lbl, color)
		pcall(function()
			local direct = rawget(lbl, "TextLabel") or rawget(lbl, "Label") or rawget(lbl, "Instance")
			if typeof(direct) == "Instance" and direct:IsA("TextLabel") then direct.TextColor3 = color; return end
			for _, k in ipairs({ "Holder", "Container", "TextLabel", "Instance" }) do
				local h = rawget(lbl, k)
				if typeof(h) == "Instance" then if h:IsA("TextLabel") then h.TextColor3 = color end for _, d in ipairs(h:GetDescendants()) do if d:IsA("TextLabel") then d.TextColor3 = color end end end
			end
		end)
	end
	-- live FPS (sampled every 0.5s) -- exposed on the Bridge for any module.
	local fps, frames, fpsT = 60, 0, tick()
	RunService.RenderStepped:Connect(function()
		frames = frames + 1
		local now = tick()
		if now - fpsT >= 0.5 then fps = math.floor(frames / (now - fpsT) + 0.5); frames = 0; fpsT = now end
	end)
	Bridge.FPS = function() return fps end
	task.spawn(function()
		while getgenv().CryptsHBEInjected do
			pcall(function()
				local n = 0; for _ in pairs(players) do n = n + 1 end
				local total = 0; for _ in pairs(Bridge.PluginSources) do total = total + 1 end
				local loaded = 0; for _, e in pairs(Bridge.Plugins) do if e and e.loaded then loaded = loaded + 1 end end
				local mem = math.floor((collectgarbage("count") or 0) / 1024 + 0.5)   -- Lua memory MB
				local status = (#errorLog == 0) and "OK" or ("ERR " .. #errorLog)
				local col = (fps >= 50 and Color3.fromRGB(70, 220, 90)) or (fps >= 30 and Color3.fromRGB(245, 215, 60)) or Color3.fromRGB(235, 70, 70)
				pcall(function() healthLabel:SetText(("Health: FPS %d  |  mem %dMB  |  plugins %d/%d  |  tracked %d  |  %s"):format(fps, mem, loaded, total, n, status)) end)
				tintLabel(healthLabel, col)
				if Toggles.showWatermark and Toggles.showWatermark.Value and Library.SetWatermark then
					Library:SetWatermark(("cryptonize's library  |  FPS %d  |  %dMB  |  plugins %d/%d  |  tracked %d  |  %s"):format(fps, mem, loaded, total, n, status))
				end
			end)
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
	-- Combat stays inline (it's deeply integrated -- publishes Bridge.Weapon/TargetGroup),
	-- but it's plugin-GATED: the tab is hidden + the action loops are inert until the Combat
	-- plugin sets Bridge.CombatActive. Register the tab so the plugin can show/hide it.
	Bridge.Tabs = Bridge.Tabs or {}
	Bridge.Tabs["Combat"] = combatTab
	Bridge.CombatActive = false
	local function combatOn() return getgenv().CryptsHBE.CombatActive end
	pcall(function() Bridge:RemoveTab("Combat") end)  -- hidden until the Combat plugin enables it

	-- ---- Weapon Reader -----------------------------------------------------
	local wrGroup    = combatTab:AddLeftGroupbox("Weapon Reader")
	local heldLabel  = wrGroup:AddLabel("Held: none")
	local typeLabel  = wrGroup:AddLabel("Type: -")
	wrGroup:AddToggle("weaponReaderAuto", { Text = "Auto-Read Held Weapon", Default = true, Tooltip = "Continuously read the name/type of the tool you're holding. (Default: ON)" })

	Bridge.Weapon = Bridge.Weapon or { name = nil, type = nil, tool = nil }

	-- Word lists for reading a weapon's internals (when its NAME doesn't reveal type).
	local WR_AMMO_WORDS = { "ammo", "mag", "clip", "round", "reserve", "bullet", "shell" }
	local WR_GUN_PARTS  = { "trigger", "barrel", "muzzle", "magazine", "mag release", "magrelease", "chamber",
		"bolt", "slide", "ironsight", "iron sight", "sight", "scope", "stock", "grip", "handguard",
		"flashhider", "flash hider", "suppressor", "silencer", "receiver", "firerate", "fire rate", "recoil" }
	-- Does any descendant's name contain one of `words`?
	local function descHas(tool, words)
		local hit = false
		pcall(function()
			for _, d in ipairs(tool:GetDescendants()) do
				local ln = d.Name:lower()
				for _, w in ipairs(words) do if ln:find(w, 1, true) then hit = true; return end end
			end
		end)
		return hit
	end
	-- Does any descendant carry a numeric Value whose name reads like ammo?
	local function hasAmmoValue(tool)
		local hit = false
		pcall(function()
			for _, d in ipairs(tool:GetDescendants()) do
				if isNumericValue(d) then
					local ln = d.Name:lower()
					for _, w in ipairs(WR_AMMO_WORDS) do if ln:find(w, 1, true) then hit = true; return end end
				end
			end
		end)
		return hit
	end

	-- Heuristic weapon-type classifier: tool/model name first, then its internals.
	local function classify(tool)
		local n = tool.Name:lower()
		local function has(...) for _, w in ipairs({ ... }) do if n:find(w) then return true end end return false end
		if has("sword", "blade", "katana", "knife", "dagger", "machete", "axe", "scythe", "saber") then return "Melee (blade)" end
		if has("fist", "glove", "punch", "knuckle") then return "Melee (fist)" end
		if has("bat", "hammer", "club", "mace", "staff", "spear", "pole", "pipe", "wrench") then return "Melee (blunt)" end
		if has("bow", "crossbow") then return "Ranged (bow)" end
		if has("gun", "rifle", "pistol", "smg", "shotgun", "sniper", "ak", "glock", "launcher", "uzi", "deagle", "carbine", "revolver", "rocket", "minigun") then return "Ranged (gun)" end
		-- Name was just a brand ("Weston Ranger") -- inspect internals. Gun frameworks
		-- (FE Gun Kit, BRM5-style) build the tool from Trigger/Barrel/Mag/Sight parts and
		-- carry Ammo IntValues, so those reveal it's a gun even with no keyword in the name.
		if hasAmmoValue(tool) or descHas(tool, WR_GUN_PARTS) then return "Ranged (gun)" end
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
			if isNumericValue(d) then
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
	-- Read current-mag vs reserve ammo from the tool's values/attributes, splitting by
	-- name (reserve/spare/stored/max = pool; ammo/mag/clip = current). Reserve checked
	-- first so "MaxAmmo"/"ReserveAmmo" don't get mis-bucketed as the current mag.
	local AMMO_RES_WORDS = { "reserve", "spare", "stored", "maxammo", "max ammo", "totalammo", "total ammo", "backup", "pool", "extra" }
	local AMMO_CUR_WORDS = { "ammo", "mag", "clip", "round", "loaded", "inclip", "current", "bullets" }
	local function bucketAmmo(ln, val, cur, reserve)
		for _, w in ipairs(AMMO_RES_WORDS) do if ln:find(w, 1, true) then return cur, val end end
		for _, w in ipairs(AMMO_CUR_WORDS) do if ln:find(w, 1, true) then return (cur == nil and val or cur), reserve end end
		return cur, reserve
	end
	local function readAmmo(tool)
		local cur, reserve
		pcall(function()
			for _, d in ipairs(tool:GetDescendants()) do
				if isNumericValue(d) then cur, reserve = bucketAmmo(d.Name:lower(), d.Value, cur, reserve) end
			end
		end)
		pcall(function()
			for _, d in ipairs(tool:GetDescendants()) do
				for an, av in pairs(d:GetAttributes()) do
					if type(av) == "number" then cur, reserve = bucketAmmo(an:lower(), av, cur, reserve) end
				end
			end
		end)
		return cur, reserve
	end
	-- HUD fallback: BRM5-style games only show ammo as on-screen text ("28 | 271").
	-- Parse the first "<num> | <num>" or "<num> / <num>" we find in the PlayerGui.
	local function readAmmoHUD()
		local pg = lPlayer:FindFirstChildOfClass("PlayerGui")
		if not pg then return nil end
		local res
		pcall(function()
			local n = 0
			for _, d in ipairs(pg:GetDescendants()) do
				n = n + 1; if n > 9000 then break end
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
					local a, b = tostring(d.Text):match("(%d+)%s*[|/]%s*(%d+)")
					if a and b then res = { tonumber(a), tonumber(b) }; return end
				end
			end
		end)
		return res
	end

	local function readNow()
		local t = currentTool()
		if t then
			Bridge.Weapon.tool, Bridge.Weapon.name, Bridge.Weapon.type = t, t.Name, classify(t)
			Bridge.Weapon.damage = findStat(t, { "damage", "dmg" })
			Bridge.Weapon.range = findStat(t, { "range", "reach", "distance" })
			local cur, reserve = readAmmo(t)
			local hudUsed = false
			if cur == nil then local hud = readAmmoHUD(); if hud then cur, reserve, hudUsed = hud[1], hud[2], true end end
			Bridge.Weapon.ammo, Bridge.Weapon.reserve = cur, reserve
			heldLabel:SetText("Held: " .. t.Name)
			local extra = ""
			if cur ~= nil then extra = extra .. "  ammo:" .. tostring(cur) .. (reserve ~= nil and ("/" .. tostring(reserve)) or "") .. (hudUsed and " (HUD)" or "") end
			if Bridge.Weapon.damage then extra = extra .. "  dmg:" .. tostring(Bridge.Weapon.damage) end
			if Bridge.Weapon.range then extra = extra .. "  rng:" .. tostring(Bridge.Weapon.range) end
			typeLabel:SetText("Type: " .. Bridge.Weapon.type .. extra)
		else
			Bridge.Weapon.tool, Bridge.Weapon.name, Bridge.Weapon.type = nil, nil, nil
			Bridge.Weapon.ammo, Bridge.Weapon.reserve = nil, nil
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
		if not combatOn() then return end
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
	selGui.Name = "CryptsHBE_DragSelect"; selGui.ResetOnSpawn = false
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
	local function dragActive() return combatOn() and Toggles.dragSelectMode and Toggles.dragSelectMode.Value end

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
		local center = getAimPoint()   -- screen centre or cursor, per Crosshair Mode
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
		if not combatOn() then return end   -- inert until the Combat plugin is enabled
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
		if not combatOn() or getgenv().CryptsHBE.MenuOpen then pcall(function() smCross.Visible = false end); return end
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
		-- Show on shiftlock (1st person) OR whenever 3rd-Person cursor mode is on, so the
		-- combat crosshair follows the cursor too -- not just when shiftlocked.
		local cursorMode = (Options.crosshairMode and Options.crosshairMode.Value or ""):find("3rd") ~= nil
		local show = enabled and Toggles.silentMeleeCrosshair and Toggles.silentMeleeCrosshair.Value
			and (UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or cursorMode)
		if show then
			smCross.Position = getAimPoint()
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
	teGui.Name = "CryptsHBE_ToolEdit"; teGui.ResetOnSpawn = false
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

	-- Bottom-of-tab tutorial.
	local combatHow = combatTab:AddLeftGroupbox("How to Use")
	combatHow:AddLabel(
		"WEAPON READER: shows the held gun's\n" ..
		"name / type / ammo. 'Auto-Read' keeps\n" ..
		"it live.\n\n" ..
		"TARGET GROUPS: turn on 'Drag-Select\n" ..
		"Mode' and drag a box over players to\n" ..
		"tag them (cyan). Used by Silent Melee's\n" ..
		"'Whole Group' mode. Or 'Add in Radius'.\n\n" ..
		"SILENT MELEE: lands melee hits without\n" ..
		"swinging. TOUCH-based melee only -- the\n" ..
		"'Damage:' line confirms ('touch conns'\n" ..
		"= good, 'remote/raycast' = won't work).\n" ..
		"  1. Hold a melee (or fists, 'Only\n" ..
		"     Melee Weapons' off).\n" ..
		"  2. Pick Target Mode + Max Range.\n" ..
		"  3. Left-click, or 'Auto (Kill Aura)'.\n" ..
		"     Wall Penetration + Shield Bypass\n" ..
		"     help if hits don't land.\n\n" ..
		"TOOL HITBOX EDITOR: 'Edit Held Weapon'\n" ..
		"-> drag the green handles (or X/Y/Z\n" ..
		"sliders) to enlarge the tool's hitbox.\n" ..
		"'Reset to Original' restores it.",
		true)
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

	-- All calibrate output (profiles, the DB, saved reports) goes in ONE folder in the
	-- executor's workspace so it's easy to find/back up, instead of loose files dumped at
	-- the root where you can't tell where they went. The path is reported on every save.
	local OUT_DIR = "CryptsHBE"
	pcall(function() if makefolder and not (isfolder and isfolder(OUT_DIR)) then makefolder(OUT_DIR) end end)
	local function outPath(name) return OUT_DIR .. "/" .. name end
	local function saveText(name, text)
		if not writefile then Library:Notify("Executor has no writefile"); return nil end
		pcall(function() name = Bridge:SessionName(name) end)   -- tag scans/dumps with the session number
		local p = outPath(name)
		local ok = pcall(function() writefile(p, text) end)
		Library:Notify(ok and ("Saved -> workspace/" .. p) or ("Save failed: " .. p))
		return ok and p or nil
	end
	-- Trim a list of lines to a compact, non-overflowing on-screen block (long single
	-- lines wrap and overlapped the next groupbox -- this caps both count and width).
	local function capText(lines, maxLines, maxLen)
		local shown = {}
		for i = 1, math.min(#lines, maxLines) do
			local ln = lines[i]
			if #ln > maxLen then ln = ln:sub(1, maxLen - 3) .. "..." end
			shown[i] = ln
		end
		if #lines > maxLines then shown[#shown + 1] = ("(+%d more lines -- use Save/Copy Report)"):format(#lines - maxLines) end
		return table.concat(shown, "\n")
	end
	local CAL_FILE    = outPath("Calibrate_" .. tostring(game.PlaceId) .. ".json")

	scanGroup:AddLabel("Place: " .. tostring(game.PlaceId), true)
	scanGroup:AddLabel("Tiers 1-2: part-name + framework detection.\nScan & Extract runs them; Tiers 3-5 are on the right.", true)
	scanGroup:AddToggle("calApplyParts",  { Text = "Auto-Add Character Parts", Default = true,  Tooltip = "Add detected non-standard character part names to the HBE\npart list and select them. (Default: ON)" })
	scanGroup:AddToggle("calApplyAmmo",    { Text = "Auto-Add Guns to Inf-Ammo", Default = true, Tooltip = "Add detected gun tools to the Inf-Ammo gun list. (Default: ON)" })
	scanGroup:AddToggle("calApplyShields", { Text = "Auto-Register Shields", Default = false, Tooltip = "Add detected shield parts to the Melee shield list. (Default: OFF)" })

	local reportLabel = reportGroup:AddLabel("Run 'Scan & Extract' to fingerprint this game.", true)
	-- The on-screen report is capped to fit; the FULL detail goes to clipboard / a file in
	-- the CryptsHBE/ folder so you can read or share long scans without UI overlap.
	reportGroup:AddButton("Copy Full Report", function()
		local t = (Bridge.Calibrate and Bridge.Calibrate.reportText) or ""
		pcall(function() if setclipboard then setclipboard(t) end end)
		Library:Notify("Full report copied to clipboard")
	end):AddToolTip("Copy the complete last-scan report to your clipboard.")
	reportGroup:AddButton("Save Report to File", function()
		local t = (Bridge.Calibrate and Bridge.Calibrate.reportText) or ""
		saveText("scan_" .. tostring(game.PlaceId) .. ".txt", t)
	end):AddToolTip("Write the complete report to workspace/CryptsHBE/ in your executor.")

	local STD_PARTS = { Head = true, HumanoidRootPart = true, Torso = true, UpperTorso = true, LowerTorso = true,
		["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
		LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
		LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true }
	local AMMO_WORDS   = { "ammo", "mag", "clip", "round", "reserve", "bullet" }
	local GUN_WORDS    = { "gun", "rifle", "pistol", "smg", "shotgun", "sniper", "ak", "glock", "launcher", "uzi", "deagle", "carbine", "revolver" }
	local SHIELD_WORDS = { "shield", "buckler", "barrier" }
	-- Names we must NEVER auto-add as hitbox parts: cosmetics/gear welded into the rig
	-- (SafetyGlasses, Hardhat, Toolbelt, HiVis...) and gun/tool internals (Handguard,
	-- "Stock end", Barrel, Trigger, Mag...). These polluted the Body Parts list before and
	-- there was no way to tell them from real limbs -- now they're filtered out up front.
	local COSMETIC_WORDS = { "glass", "hat", "helmet", "cap", "hivis", "hi-vis", "hi vis", "vest",
		"lanyard", "radio", "belt", "mesh", "badge", "card", "goggle", "mask", "visor",
		"backpack", "bag", "strap", "patch", "logo", "decal", "accessory", "accessor", "hair",
		"face", "shirt", "pants", "cloth", "fabric", "boot", "shoe", "watch", "armband", "tie",
		"handguard", "stock", "barrel", "trigger", "muzzle", "sight", "scope", "magazine",
		"flash", "hider", "suppress", "silenc", "grip", "rail", "bolt", "receiver", "chamber",
		"sling", "wedge", "motor", "union", "release" }
	-- Gun-internal part names: presence of these in a Tool means it's a gun even when its
	-- name is just a brand ("Weston Ranger") and it carries no ammo IntValue.
	local GUN_PARTS = { "trigger", "barrel", "muzzle", "magazine", "mag release", "chamber", "bolt",
		"ironsight", "iron sight", "flashhider", "flash hider", "suppress", "silenc", "receiver",
		"firerate", "fire rate", "handguard", "foregrip" }
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
		{ name = "TREK gun/vehicle framework (-> enable TREK plugin)", any = { "TREK_SERVICES", "TREK_Remotes", "TREK_Gun", "TREK_Vehicle", "TREKGun" } },
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
		-- Split non-standard names into real-limb CANDIDATES vs cosmetic/weapon junk, and
		-- track exactly what we newly add so "Undo Auto-Added" can reverse precisely.
		local nonStdList, candidates, appliedList = {}, {}, {}
		local prevSet = {}
		if Options.extenderPartList then for _, v in ipairs(Options.extenderPartList.Values or {}) do prevSet[v] = true end end
		for n in pairs(nonStd) do
			nc = nc + 1; nonStdList[#nonStdList + 1] = n
			if not nameHas(n, COSMETIC_WORDS) then
				candidates[#candidates + 1] = n
				if apply and Toggles.calApplyParts.Value then
					if not prevSet[n] then appliedList[#appliedList + 1] = n end
					addToDropdown(Options.extenderPartList, n, true)
				end
			end
		end
		Bridge.Calibrate.autoAdded = appliedList
		r[#r + 1] = ("Parts: %d total, %d non-standard, %d real candidates"):format(pc, nc, #candidates)
		if #candidates > 0 then r[#r + 1] = "  candidates: " .. table.concat(candidates, ", ") end
		if apply and #appliedList > 0 then r[#r + 1] = "  auto-added: " .. table.concat(appliedList, ", ") end
		if nc > #candidates then
			local skipped = {}
			for _, n in ipairs(nonStdList) do if nameHas(n, COSMETIC_WORDS) then skipped[#skipped + 1] = n end end
			r[#r + 1] = "  skipped (cosmetic/weapon): " .. table.concat(skipped, ", ")
		end

		-- 2) guns / ammo (held + backpack tools)
		local guns, ammoVals = {}, 0
		for _, cont in ipairs({ lPlayer.Character, lPlayer:FindFirstChild("Backpack") }) do
			if cont then
				for _, t in ipairs(cont:GetChildren()) do
					if t:IsA("Tool") then
						local isGun = nameHas(t.Name, GUN_WORDS)
						for _, d in ipairs(t:GetDescendants()) do
							if (isNumericValue(d)) and nameHas(d.Name, AMMO_WORDS) then ammoVals = ammoVals + 1; isGun = true end
							if not isGun and nameHas(d.Name, GUN_PARTS) then isGun = true end
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
					if isNumericValue(d) then
						local n = d.Name:lower()
						for _, w in ipairs({ "recoil", "spread", "kick", "bloom", "sway" }) do if n:find(w) then recoilN = recoilN + 1; break end end
						if nameHas(d.Name, AMMO_WORDS) then isGun = true end
					end
					if not isGun and nameHas(d.Name, GUN_PARTS) then isGun = true end
				end
			end
		end)
		r[#r + 1] = ("Gun: %s, recoil values: %d"):format(isGun and "yes" or "no/none held", recoilN)

		-- Keep the full report for Copy/Save, but only show a compact, non-overflowing
		-- slice on-screen (the long candidate lists used to wrap and cover the next box).
		Bridge.Calibrate.reportText = table.concat(r, "\n")
		pcall(function() reportLabel:SetText(capText(r, 8, 64)) end)
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
		local ok = pcall(function()
			writefile(CAL_FILE, HttpService:JSONEncode({ parts = keysOf(data.parts), guns = keysOf(data.guns), shields = keysOf(data.shields) }))
		end)
		Library:Notify(ok and ("Saved profile -> workspace/" .. CAL_FILE) or "Profile save failed")
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
	-- ===== Smart Setup: fingerprint the game -> recommend + enable the right plugins =====
	-- Turns Calibrate into the suite's "brain": after a scan it decides which plugins this
	-- game needs (TREK/Vehicle/Combat/Economy/Engineer/aim/etc.) and can enable them in one click.
	local SS_CUR = { "cash", "money", "coin", "credit", "point", "score", "kill", "gold", "gem", "token", "xp", "funds", "wealth" }
	local SS_BUILD = { "shovel", "spade", "pick", "hammer", "wrench", "build", "trowel", "entrench" }
	local function ssWord(s, words) s = tostring(s):lower() for _, w in ipairs(words) do if s:find(w, 1, true) then return true end end return false end
	scanGroup:AddButton("Smart Setup -> Recommend Plugins", function()
		runScan(false)
		local fws = detectFrameworks() or {}
		local fwStr = (table.concat(fws, ", ")):lower()
		local cal = Bridge.Calibrate or {}
		local rec, seen = {}, {}
		local function add(p, why) if (not seen[p]) and Bridge.PluginSources and Bridge.PluginSources[p] then seen[p] = true; rec[#rec + 1] = { p = p, why = why } end end
		add("Recon", "universal recon"); add("Values", "universal value editor")
		if fwStr:find("trek") then add("TREK", "TREK gun framework") end
		if fwStr:find("chassis") then add("Vehicle", "A-Chassis vehicles") end
		if cal.guns and #cal.guns > 0 then add("InfAmmo", "guns + ammo"); add("Weapons", "gun stats"); add("Aimbot", "aim at players"); add("SilentAim", "silent aim") end
		local seats = 0; pcall(function() for _, d in ipairs(Workspace:GetDescendants()) do if d:IsA("VehicleSeat") or d:IsA("Seat") then seats = 1; break end end end)
		if seats > 0 then add("Vehicle", "vehicle seats present") end
		if (cal.shields and #cal.shields > 0) or fwStr:find("combat") or fwStr:find("sword") then add("Combat", "melee/combat"); add("SilentAim", "remote/melee hit") end
		local hasCur = false
		pcall(function() for _, d in ipairs(lPlayer:GetDescendants()) do if (d:IsA("IntValue") or d:IsA("NumberValue")) and ssWord(d.Name, SS_CUR) then hasCur = true; break end end end)
		if not hasCur then pcall(function() local pg = lPlayer:FindFirstChildOfClass("PlayerGui") if pg then for _, d in ipairs(pg:GetDescendants()) do if d:IsA("TextLabel") and ssWord(d.Name, SS_CUR) then hasCur = true; break end end end end) end
		if hasCur then add("Economy", "currency/points present"); add("RemoteSniffer", "capture award remote") end
		local bt = false
		pcall(function() for _, where in ipairs({ lPlayer.Character, lPlayer:FindFirstChild("Backpack") }) do if where then for _, t in ipairs(where:GetChildren()) do if t:IsA("Tool") and ssWord(t.Name, SS_BUILD) then bt = true; break end end end end end)
		if bt then add("Engineer", "build tool") end
		Bridge.Calibrate.recommended = rec
		local lines = { "Smart Setup:", "Frameworks: " .. (#fws > 0 and table.concat(fws, ", ") or "none/custom") }
		for _, r in ipairs(rec) do lines[#lines + 1] = "  + " .. r.p .. " (" .. r.why .. ")" end
		lines[#lines + 1] = "-> 'Enable Recommended' to load them."
		pcall(function() reportLabel:SetText(table.concat(lines, "\n")) end)
		Library:Notify("Smart Setup: " .. #rec .. " plugin(s) recommended")
	end):AddToolTip("Fingerprint this game and recommend which plugins to enable for it (frameworks, guns, vehicles, currency, build tools).")
	scanGroup:AddButton("Enable Recommended", function()
		local rec = (Bridge.Calibrate and Bridge.Calibrate.recommended) or {}
		if #rec == 0 then Library:Notify("Run 'Smart Setup' first"); return end
		local ok = 0
		for _, r in ipairs(rec) do if pcall(function() return Bridge:EnablePlugin(r.p) end) then ok = ok + 1 end end
		Library:Notify("Enabled " .. ok .. "/" .. #rec .. " recommended plugins")
	end):AddToolTip("Enable every plugin Smart Setup recommended for this game.")
	-- Reverse an auto-apply: remove exactly what the last scan added (restores your prior
	-- hitbox setup), or wipe the Body Parts list back to the limb defaults.
	scanGroup:AddButton("Undo Auto-Added Parts", function()
		local list = (Bridge.Calibrate and Bridge.Calibrate.autoAdded) or {}
		local n = 0
		for _, nm in ipairs(list) do pcall(function() removeBodyPart(nm); n = n + 1 end) end
		if Bridge.Calibrate then Bridge.Calibrate.autoAdded = {} end
		pcall(updatePlayers)
		Library:Notify("Removed " .. n .. " auto-added part(s)")
	end):AddToolTip("Remove exactly the parts the last Scan & Extract added -- leaves your manual ones (e.g. Head) alone.")
	scanGroup:AddButton("Reset Body Parts to Default", function()
		local removed = 0
		if Options.extenderPartList then
			for _, v in ipairs(table.clone(Options.extenderPartList.Values or {})) do
				if not isDefaultBodyPart(v) then pcall(function() removeBodyPart(v); removed = removed + 1 end) end
			end
		end
		if Bridge.Calibrate then Bridge.Calibrate.autoAdded = {} end
		pcall(updatePlayers)
		Library:Notify("Body Parts reset to default (removed " .. removed .. ")")
	end):AddToolTip("Clear every non-default part from the HBE Body Parts list (keeps Head/Torso/limbs).")
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

	-- ===== Weapon Deep-Dump (reverse-engineering aid) ====================
	-- Writes the FULL structure of the held weapon -- every child's class/name, every
	-- Value's value, every attribute -- PLUS the read-only string constants of its
	-- scripts (which reveal the value/remote/function names the gun's code uses) and the
	-- gun-related RemoteEvents in the game. This is the data needed to build TAILORED
	-- weapon hacks (inf-ammo/instant-reload/no-recoil/fire-rate) for a server-side game.
	-- Pure read: getscriptclosure + debug.getconstants like Phantom Recon -- never writes.
	local function dumpScriptConsts(inst, depth, lines)
		pcall(function()
			if (inst:IsA("ModuleScript") or inst:IsA("LocalScript") or inst:IsA("Script")) and getscriptclosure and debug and debug.getconstants then
				local cl = getscriptclosure(inst); if not cl then return end
				local strs, seen = {}, {}
				local function harvest(fn)
					local consts = debug.getconstants(fn)
					if type(consts) == "table" then
						for _, c in ipairs(consts) do
							if type(c) == "string" and #c > 2 and #c < 64 and not seen[c] then seen[c] = true; strs[#strs + 1] = c end
						end
					end
				end
				harvest(cl)
				pcall(function() for _, p in ipairs((debug.getprotos and debug.getprotos(cl)) or {}) do harvest(p) end end)
				if #strs > 0 then lines[#lines + 1] = string.rep("  ", depth + 1) .. "[consts] " .. table.concat(strs, ", ") end
			end
		end)
	end
	local function dumpInstance(inst, depth, lines, cap)
		if #lines >= cap then return end
		local indent = string.rep("  ", depth)
		local extra = ""
		pcall(function() if inst:IsA("ValueBase") then extra = " = " .. tostring(inst.Value) end end)
		lines[#lines + 1] = indent .. inst.ClassName .. " '" .. inst.Name .. "'" .. extra
		pcall(function()
			for an, av in pairs(inst:GetAttributes()) do lines[#lines + 1] = indent .. "  @" .. an .. " = " .. tostring(av) end
		end)
		dumpScriptConsts(inst, depth, lines)
		for _, c in ipairs(inst:GetChildren()) do
			if #lines >= cap then lines[#lines + 1] = indent .. "  ...(truncated)"; break end
			dumpInstance(c, depth + 1, lines, cap)
		end
	end
	scanGroup:AddButton("Deep-Dump Held Weapon", function()
		local char = lPlayer.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		if not tool then Library:Notify("Hold a weapon first, then dump"); return end
		local lines = { "=== Weapon Deep Dump ===", "Tool: " .. tool.Name, "PlaceId: " .. tostring(game.PlaceId), "" }
		dumpInstance(tool, 0, lines, 4000)
		lines[#lines + 1] = ""
		lines[#lines + 1] = "=== Gun-related Remotes (name ~ fire/shoot/hit/damage/reload/weapon/gun/bullet) ==="
		pcall(function()
			local n = 0
			for _, d in ipairs(game:GetDescendants()) do
				if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
					local ln = d.Name:lower()
					if ln:find("fire") or ln:find("shoot") or ln:find("hit") or ln:find("damage") or ln:find("reload") or ln:find("weapon") or ln:find("gun") or ln:find("bullet") or ln:find("ammo") then
						n = n + 1; if n > 250 then break end
						lines[#lines + 1] = d.ClassName .. " '" .. d.Name .. "'  @ " .. d:GetFullName()
					end
				end
			end
		end)
		saveText("weapon_dump_" .. tostring(game.PlaceId) .. ".txt", table.concat(lines, "\n"))
	end):AddToolTip("Write the held weapon's full structure + its scripts' string constants + gun\nremotes to workspace/CryptsHBE/ -- the data needed to build tailored weapon hacks.")

	-- ===== Tier 3: behavioral learning engine ===========================
	-- Snapshot every numeric value/attribute on you + your character, you perform an
	-- action (shoot / take damage / earn), then Analyze diffs the snapshot to surface
	-- the fields that changed -- finding ammo/health/currency/recoil WITHOUT knowing
	-- their names (defeats obfuscated games). Generalizes the Inf-Ammo learner.
	local learnGroup = calTab:AddRightGroupbox("Learn (Tier 3)")
	learnGroup:AddLabel("Snapshot -> do an action (shoot / take damage /\nearn) -> Analyze. Finds the values that changed.", true)
	learnGroup:AddDropdown("learnFilter", { Text = "Show", Values = { "Decreased (ammo/health/spent)", "Increased (currency/score)", "Any change" }, Default = "Any change", Multi = false, AllowNull = false })
	local learnInfo = learnGroup:AddLabel("Snapshot to begin.", true)

	local function collectFields()
		local fields = {}
		local function scan(root)
			if not root then return end
			local ok = pcall(function()
				local n = 0
				for _, d in ipairs(root:GetDescendants()) do
					n = n + 1; if n > 40000 then break end
					if isNumericValue(d) then
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
		scan(lPlayer:FindFirstChild("Backpack"))
		-- HUD numbers: in many games (BRM5-style) ammo/health/currency live ONLY as
		-- on-screen text, not as a Value -- so snapshot the first number in each short
		-- TextLabel/Button too. That's how Analyze catches a mag dropping 28 -> 27.
		pcall(function()
			local pg = lPlayer:FindFirstChildOfClass("PlayerGui")
			if pg then
				local n = 0
				local function firstNum(s) local m = tostring(s):match("%-?%d+%.?%d*"); return m and tonumber(m) or nil end
				for _, d in ipairs(pg:GetDescendants()) do
					n = n + 1; if n > 12000 then break end
					if (d:IsA("TextLabel") or d:IsA("TextButton")) and #tostring(d.Text) <= 12 then
						local num = firstNum(d.Text)
						if num then fields[#fields + 1] = { label = "HUD:" .. d.Name, get = function() return firstNum(d.Text) end } end
					end
				end
			end
		end)
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
			-- Prefer the first REAL value (a writable Value/attribute) over a "HUD:" label
			-- (a TextLabel's displayed number, which can't be written). The HUD label often
			-- ties with the real value -- if we picked it we'd wrongly say "server-side"
			-- even though a real ammo Value exists (and Inf-Ammo already refills it).
			local pick
			for _, r in ipairs(Bridge.Calibrate.learned) do
				if not tostring(r.label):match("^HUD:") then pick = r.label; break end
			end
			if not pick then
				Library:Notify("Only HUD display values changed -> ammo is server-side here")
				return
			end
			local nm = pick:gsub("@.*$", "")
			pcall(function() Options.infAmmoManualName:SetValue(nm) end)
			Library:Notify("Inf-Ammo manual name -> " .. nm)
		else
			Library:Notify("Analyze first")
		end
	end):AddToolTip("Feed the biggest CHANGED real value's name into Inf-Ammo's manual detector\n(skips HUD-only display values).")

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
	local dsInfo = dsGroup:AddLabel("Deep Scan off.", true)
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
			(#ac > 0 and "Next: features now auto-steer around these." or "Next: no AC found -> run Tier 5 Auto-Configure."),
		}
		Bridge.DeepScan.reportText = table.concat(lines, "\n")
		pcall(function() dsInfo:SetText(capText(lines, 8, 70)) end)
		Library:Notify(#ac > 0 and ("AC detected: " .. ac[1].name) or "No named anti-cheat found")
	end
	dsGroup:AddButton("Run Phantom Probe", runProbe):AddToolTip("Read-only recon: fingerprint the anti-cheat, map honeypots, and read which\nvalues/remotes it watches -- without touching any of them. Nothing is fired or written.")
	dsGroup:AddButton("Copy Phantom Report", function()
		local t = (Bridge.DeepScan and Bridge.DeepScan.reportText) or ""
		pcall(function() if setclipboard then setclipboard(t) end end)
		Library:Notify("Phantom report copied to clipboard")
	end):AddToolTip("Copy the full Tier-4 recon output to your clipboard.")

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

	local DB_FILE = outPath("ProfileDB.json")
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

	-- ===== Instant Interact (ProximityPrompt HoldDuration -> 0) ==========
	-- Detector + override for "hold E/T to interact" prompts: drops every prompt's
	-- HoldDuration to 0 so interacting is a tap, optionally widens activation distance,
	-- and restores the originals when turned off. New prompts are caught live.
	local ppGroup = calTab:AddLeftGroupbox("Instant Interact")
	ppGroup:AddToggle("instantInteract", { Text = "Instant Interact (Hold = 0)", Default = false, Tooltip = "Set every ProximityPrompt's HoldDuration to 0 so 'hold to\ninteract' prompts trigger instantly. Restores on off. (Default: OFF)" })
	ppGroup:AddSlider("interactDistance", { Text = "Min Activation Dist", Min = 0, Max = 50, Default = 0, Rounding = 0, Tooltip = "Raise every prompt's MaxActivationDistance to at least this many\nstuds (0 = leave each prompt's own distance alone)." })
	local ppInfo = ppGroup:AddLabel("Prompts: idle", true)
	local ppOrig = setmetatable({}, { __mode = "k" })  -- [prompt] = { holdDuration, maxActivationDistance }
	local ppConn = nil
	local function applyPrompt(pp)
		if not (typeof(pp) == "Instance" and pp:IsA("ProximityPrompt")) then return end
		if not ppOrig[pp] then ppOrig[pp] = { pp.HoldDuration, pp.MaxActivationDistance } end
		pcall(function() pp.HoldDuration = 0 end)
		local minD = (Options.interactDistance and Options.interactDistance.Value) or 0
		if minD > 0 then pcall(function() if pp.MaxActivationDistance < minD then pp.MaxActivationDistance = minD end end) end
	end
	local function sweepPrompts()
		local n = 0
		pcall(function()
			for _, d in ipairs(Workspace:GetDescendants()) do
				if d:IsA("ProximityPrompt") then applyPrompt(d); n = n + 1 end
			end
		end)
		pcall(function() ppInfo:SetText("Prompts: " .. n .. (n > 0 and " set to instant" or " (none found in workspace)")) end)
		return n
	end
	local function restorePrompts()
		for pp, o in pairs(ppOrig) do
			if typeof(pp) == "Instance" and pp.Parent then pcall(function() pp.HoldDuration = o[1]; pp.MaxActivationDistance = o[2] end) end
		end
		table.clear(ppOrig)
	end
	Toggles.instantInteract:OnChanged(function()
		if Toggles.instantInteract.Value then
			sweepPrompts()
			if not ppConn then
				ppConn = Workspace.DescendantAdded:Connect(function(d)
					if Toggles.instantInteract.Value and d:IsA("ProximityPrompt") then task.defer(applyPrompt, d) end
				end)
			end
		else
			if ppConn then pcall(function() ppConn:Disconnect() end); ppConn = nil end
			restorePrompts()
			pcall(function() ppInfo:SetText("Prompts: restored to original") end)
		end
	end)
	ppGroup:AddButton("Re-scan Prompts", function()
		if Toggles.instantInteract.Value then sweepPrompts() else Library:Notify("Enable Instant Interact first") end
	end):AddToolTip("Re-apply HoldDuration=0 to every ProximityPrompt currently in the workspace.")

	-- Bottom-of-tab tutorial.
	local calHow = calTab:AddLeftGroupbox("How to Use")
	calHow:AddLabel(
		"Figures out how a game works so the\n" ..
		"cheat can adapt to it.\n\n" ..
		"SCAN & EXTRACT (Tiers 1-2): detects\n" ..
		"parts, framework, guns + shields and\n" ..
		"auto-applies them. 'Undo Auto-Added\n" ..
		"Parts' reverses a bad apply.\n\n" ..
		"LEARN (Tier 3): finds values with no\n" ..
		"names. Snapshot -> shoot / take damage\n" ..
		"-> Analyze lists what changed. A\n" ..
		"'HUD:...' result = display-only =\n" ..
		"server-side (can't be written).\n\n" ..
		"PHANTOM RECON (Tier 4): read-only AC\n" ..
		"recon. Then run Tier 5 Auto-Configure.\n\n" ..
		"DEEP-DUMP HELD WEAPON: hold a gun ->\n" ..
		"dumps its full structure + remotes to\n" ..
		"workspace/CryptsHBE/ -- send me that\n" ..
		"file for a tailored weapon hack.\n\n" ..
		"INSTANT INTERACT: ProximityPrompt hold\n" ..
		"time -> 0. Files save to\n" ..
		"workspace/CryptsHBE/.",
		true)

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

	-- Base URL for the external plugin files (set here, or via getgenv().CryptsHBE_PluginBase
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
	Bridge:RegisterPluginSource("SilentAim", { tab = "Silent Aim", file = "silentaim.lua", url = RAW .. "silentaim.lua",   desc = "Silent aim: hook-free Remote mode + opt-in Extreme namecall-hook redirect." })
	Bridge:RegisterPluginSource("World",    { tab = "World",      file = "world.lua",     url = RAW .. "world.lua",       desc = "Fullbright, No Fog, Custom FOV, Infinite Stamina (generic client visuals/utility)." })
	Bridge:RegisterPluginSource("Weapons",  { tab = "Weapons",    file = "weapons.lua",   url = RAW .. "weapons.lua",     desc = "Generic value-based gun hacks: No Recoil/Spread, No Bullet Drop, Instant Reload, Fire Rate." })
	Bridge:RegisterPluginSource("Values",   { tab = "Values",     file = "valueeditor.lua", url = RAW .. "valueeditor.lua", desc = "Universal value editor: pick any value (or click a HUD number) and set/hold it." })
	Bridge:RegisterPluginSource("TREK",     { tab = "TREK",       file = "trek.lua",      url = RAW .. "trek.lua",        desc = "TREK-framework gun engine: reaches stats behind Config:GetValue (fire rate via WindUp/WindDown, recoil, reload, spread) by wrapping the accessor or mutating the backing table." })
	Bridge:RegisterPluginSource("Artillery", { tab = "Artillery", file = "artillery.lua", url = RAW .. "artillery.lua",    desc = "Artillery/siege-mortar assist: reads TargetPos to draw the impact marker + scatter circle + an over-target camera, plus best-effort auto-shoot with server-acceptance readout." })
	Bridge:RegisterPluginSource("Sections",  { tab = "Sections",   file = "sections.lua",  url = RAW .. "sections.lua",    desc = "Section Loader: keep only the plugins you use (unload the rest), cut HBE/ESP distance, and an engagement-range logger that suggests the distance you actually need." })
	Bridge:RegisterPluginSource("DeepDive",  { tab = "DeepDive",   file = "deepdive.lua",  url = RAW .. "deepdive.lua",    desc = "Extended reverse-engineering: required-module/upvalue dumps, custom-inventory dumper (non-Tool weapons), all-remotes dump; powers the core's Extended Deep Dive button." })
	Bridge:RegisterPluginSource("RemoteSniffer", { tab = "Sniffer", file = "remotesniffer.lua", url = RAW .. "remotesniffer.lua", desc = "OPT-IN/DETECTABLE: logs outgoing FireServer/InvokeServer calls + their arguments (read-only namecall hook) so you see the exact payload to replay -- damage remotes, artillery Shoot, shop purchases." })
	Bridge:RegisterPluginSource("Engineer",  { tab = "Engineer",   file = "engineer.lua",  url = RAW .. "engineer.lua",    desc = "Prodier shovel build helper: Auto-Swing (bindable), Instant Build (max a structure's progress/Health under your crosshair, with read-back), and a war-year-gate bypass." })
	Bridge:RegisterPluginSource("Recon",     { tab = "Recon",      file = "recon.lua",     url = RAW .. "recon.lua",       desc = "Deep-dive analysis suite: Damage Model (recommends the combat tool), Module API map, GC scan, Networking/ownership, Animation, Input binds, Map/World, Economy/Shop, Character/Rig, Anti-Cheat -- read-only reports to workspace/CryptsHBE/." })
	Bridge:RegisterPluginSource("Vehicle",   { tab = "Vehicle/Misc", file = "vehicle.lua", url = RAW .. "vehicle.lua",     desc = "The Vehicle/Misc tab (extracted from the core to shrink it): Vehicle Assist + Tool Expander + Manual Vehicle HBE + Vehicle Modify/Tuning + Vehicle ESP. Enable to get the tab back." })
	Bridge:RegisterPluginSource("Combat",    { tab = "Combat",     file = "combat.lua",    url = RAW .. "combat.lua",      desc = "Gate for the inline Combat tab (Weapon Reader, Target Groups, Silent Melee, Tool Hitbox Editor). Code stays in the core; this shows the tab + makes its features active only while enabled." })
	Bridge:RegisterPluginSource("Economy",   { tab = "Economy",    file = "economy.lua",   url = RAW .. "economy.lua",     desc = "Currency detection + point-farm: watch a currency value (classifies auto/server vs your-fire gains), find the grant remote, and Fire/Auto-Farm it with read-back to prove if it pays out." })
	Bridge:RegisterPluginSource("AnimCancel", { tab = "Anim",      file = "animcancel.lua", url = RAW .. "animcancel.lua",  desc = "Cancel/speed firing + reload animations so the per-shot animation stops gating your fire rate (artillery, bolt-action, melee). Direct API, no hook. Learn the action anim, then Cancel or Speed-up it. Client lever only -- confirm via your weapon's real rate." })
	Bridge:RegisterPluginSource("DotESP",    { tab = "Dots",      file = "dotesp.lua",    url = RAW .. "dotesp.lua",      desc = "Dot ESP: small team-coloured dots floating above players' heads (teammates and/or enemies), on a toggle hotkey (default V). Own distance, honours Streamer + menu-hide. Read-only screen projection." })
	Bridge:RegisterPluginSource("BleedingBlades", { tab = "Blades", file = "bleedingblades.lua", url = RAW .. "bleedingblades.lua", desc = "Bleeding Blades toolkit: pick any model -> its remotes, fire Combat remotes (PHit hit / CreateProjectile arrow / Mount), watch server messages (Invalid Attack / Fall damage), subtle walk speed, and an experimental DirectionUI-based auto-block for the directional parry." })
	Bridge:RegisterPluginSource("Blackout",  { tab = "Blackout",  file = "blackout.lua",   url = RAW .. "blackout.lua",    desc = "Anti-detection blackout: one key hides every cheat visual + menu (+ optional full black overlay) so the screen looks vanilla; Auto-Blackout fires on an anti-cheat word + disables risky features; UI cloak keeps the menu under gethui()." })

	-- Plugins load on demand: their tabs + features DON'T EXIST until enabled, so an
	-- absent Aimbot/Precision tab just looks broken. Make "they're off" obvious with a
	-- live loaded/total summary plus a one-time warning notification on startup.
	local pmTotal, pmLoaded, loadedSet = 0, 0, {}
	for _ in pairs(Bridge.PluginSources) do pmTotal = pmTotal + 1 end
	local pmSummary = pmGroup:AddLabel("Plugins loaded: 0 / " .. pmTotal .. "  (enable below)", true)
	local function refreshSummary()
		pcall(function() pmSummary:SetText(("Plugins loaded: %d / %d%s"):format(pmLoaded, pmTotal, pmLoaded == 0 and "  --  ALL OFF, enable below" or "")) end)
	end

	-- per-plugin status colour (green loaded / red failed / grey off)
	local function tintStatus(lbl, color)
		pcall(function()
			local direct = rawget(lbl, "TextLabel") or rawget(lbl, "Label") or rawget(lbl, "Instance")
			if typeof(direct) == "Instance" and direct:IsA("TextLabel") then direct.TextColor3 = color; return end
			for _, k in ipairs({ "Holder", "Container", "TextLabel", "Instance" }) do
				local h = rawget(lbl, k)
				if typeof(h) == "Instance" then if h:IsA("TextLabel") then h.TextColor3 = color end for _, d in ipairs(h:GetDescendants()) do if d:IsA("TextLabel") then d.TextColor3 = color end end end
			end
		end)
	end
	local PM_GREEN, PM_RED, PM_GREY = Color3.fromRGB(70, 220, 90), Color3.fromRGB(235, 70, 70), Color3.fromRGB(150, 150, 150)
	local rowEnable, rowUnload = {}, {}
	-- One manager row (status + Enable + Unload) per registered plugin.
	local function addRow(name)
		local status = pmGroup:AddLabel(name .. ": not loaded"); tintStatus(status, PM_GREY)
		local function doEnable()
			local ok, err = Bridge:EnablePlugin(name)
			status:SetText(name .. (ok and ": loaded" or (": FAILED - " .. tostring(err)))); tintStatus(status, ok and PM_GREEN or PM_RED)
			if ok and not loadedSet[name] then loadedSet[name] = true; pmLoaded = pmLoaded + 1; refreshSummary() end
			return ok, err
		end
		local function doUnload()
			Bridge:UnloadPlugin(name)
			status:SetText(name .. ": not loaded"); tintStatus(status, PM_GREY)
			if loadedSet[name] then loadedSet[name] = nil; pmLoaded = math.max(0, pmLoaded - 1); refreshSummary() end
		end
		rowEnable[name], rowUnload[name] = doEnable, doUnload
		pmGroup:AddButton("Enable " .. name, function() local ok, err = doEnable(); if Library and Library.Notify then Library:Notify(ok and ("Enabled " .. name) or ("Enable failed: " .. tostring(err))) end end):AddToolTip(Bridge.PluginSources[name] and Bridge.PluginSources[name].desc or "")
		pmGroup:AddButton("Unload " .. name, function() doUnload(); if Library and Library.Notify then Library:Notify("Unloaded " .. name) end end)
	end
	for n in pairs(Bridge.PluginSources) do addRow(n) end
	refreshSummary()

	-- ===== Quick Actions (QOL): enable/disable all + auto-enable favourites on inject =====
	local HttpService = game:GetService("HttpService")
	local AE_FILE = "CryptsHBE/autoenable.json"
	local function readAE() local t = { enabled = false, list = {} } pcall(function() if isfile and readfile and isfile(AE_FILE) then local d = HttpService:JSONDecode(readfile(AE_FILE)); if type(d) == "table" then t = d end end end) return t end
	local function writeAE(t) pcall(function() if makefolder and not (isfolder and isfolder("CryptsHBE")) then makefolder("CryptsHBE") end if writefile then writefile(AE_FILE, HttpService:JSONEncode(t)) end end) end
	local qa = pmTab:AddRightGroupbox("Quick Actions")
	qa:AddButton("Enable ALL", function() local n = 0 for nm in pairs(Bridge.PluginSources) do if rowEnable[nm] and rowEnable[nm]() then n = n + 1 end end Library:Notify("Enabled " .. n .. " plugins") end):AddToolTip("Load every registered plugin (heavy -- fetches each from GitHub).")
	qa:AddButton("Disable ALL", function() for nm in pairs(Bridge.PluginSources) do if rowUnload[nm] then rowUnload[nm]() end end Library:Notify("Disabled all plugins") end)
	qa:AddInput("autoEnableList", { Text = "Auto-enable list", Default = "", Tooltip = "Comma-separated plugin names auto-loaded on inject (e.g. Values,Recon,Combat)." })
	local ae0 = readAE(); pcall(function() Options.autoEnableList:SetValue(table.concat(ae0.list or {}, ",")) end)
	qa:AddLabel(ae0.enabled and ("Auto-enable: ON (" .. #(ae0.list or {}) .. ")") or "Auto-enable: off", true)
	qa:AddButton("Use Currently Loaded", function() local t = {} for nm in pairs(loadedSet) do t[#t + 1] = nm end Options.autoEnableList:SetValue(table.concat(t, ",")) Library:Notify("Filled with " .. #t .. " loaded plugin(s)") end):AddToolTip("Put the currently-enabled plugins into the list.")
	qa:AddButton("Save Auto-Enable (ON)", function()
		local list = {} for nm in tostring(Options.autoEnableList.Value or ""):gmatch("[^,]+") do nm = nm:gsub("%s", ""); if nm ~= "" then list[#list + 1] = nm end end
		writeAE({ enabled = true, list = list }); Library:Notify("Auto-enable saved (" .. #list .. ") -- loads next inject")
	end):AddToolTip("These plugins auto-load every time you run the script.")
	qa:AddButton("Clear Auto-Enable", function() writeAE({ enabled = false, list = {} }); Library:Notify("Auto-enable cleared") end)
	-- apply on inject (after the UI settles)
	task.spawn(function()
		task.wait(0.5)
		local ae = readAE()
		if ae.enabled and type(ae.list) == "table" and #ae.list > 0 then
			local n = 0 for _, nm in ipairs(ae.list) do if rowEnable[nm] then if pcall(rowEnable[nm]) then n = n + 1 end end end
			if Library and Library.Notify then Library:Notify("Auto-enabled " .. n .. " plugin(s)") end
		end
	end)
	if Library and Library.Notify then
		pcall(function() Library:Notify("Plugins are OFF -- enable them in the Plugins tab to use Aimbot / Precision / Teleport / Inf Ammo / etc.", 10) end)
	end
	print("[Plugins] manager + external plugin registry (Aimbot, Spectate)")
end)

pcall(finalInit)

-- Clean teardown when the UI library is unloaded: restore everyone, drop the
-- render binds, and clear the injection flag so the script can be re-run.
pcall(function()
	if Library and Library.OnUnload then
		Library:OnUnload(function()
			pcall(cleanup)
			getgenv().CryptsHBEInjected = nil
		end)
	end
end)

-- Adaptive self-heal watchdog. Every few seconds it reconciles the tracked-player
-- table with the real player list: re-adds anyone missing (a PlayerAdded that was
-- missed, or an object that got dropped) and prunes players who left. Keeps ESP/HBE
-- working without needing the manual "Fix Missing Players" button, and recovers
-- automatically from transient errors. Everything is pcall'd so it can't break.
task.spawn(function()
	while getgenv().CryptsHBEInjected do
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
