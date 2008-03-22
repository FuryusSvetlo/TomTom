--[[--------------------------------------------------------------------------
--  TomTom by Cladhaire <cladhaire@gmail.com>
----------------------------------------------------------------------------]]

-- Simple localization table for messages
local L = TomTomLocals
local Astrolabe = DongleStub("Astrolabe-0.4")

-- Create the addon object
TomTom = {
	events = {},
	eventFrame = CreateFrame("Frame"),
	RegisterEvent = function(self, event, method)
		self.eventFrame:RegisterEvent(event)
		self.events[event] = event or method
	end,
	UnregisterEvent = function(self, event)
		self.eventFrame:UnregisterEvent(event)
		self.events[event] = nil
	end,
}

TomTom.eventFrame:SetScript("OnEvent", function(self, event, ...)
	local method = TomTom.events[event]
	if method and TomTom[method] then
		TomTom[method](TomTom, event, ...)
	end
end)

TomTom:RegisterEvent("ADDON_LOADED")

-- Local definitions
local GetCurrentCursorPosition
local WorldMap_OnUpdate
local Block_OnClick,Block_OnUpdate,BlockOnEnter,BlockOnLeave
local Block_OnDragStart,Block_OnDragStop
local callbackTbl
local RoundCoords

local waypoints = {}

function TomTom:ADDON_LOADED(event, addon)
	if addon == "TomTom" then
		self:UnregisterEvent("ADDON_LOADED")
		self.defaults = {
			profile = {
				block = {
					enable = true,
					accuracy = 2,
					bordercolor = {1, 0.8, 0, 0.8},
					bgcolor = {0, 0, 0, 0.4},
					lock = false,
					height = 30,
					width = 100,
					fontsize = 12,
				},
				mapcoords = {
					playerenable = true,
					playeraccuracy = 2,
					cursorenable = true,
					cursoraccuracy = 2,
				},
				arrow = {
					enable = true,
					goodcolor = {0, 1, 0},
					badcolor = {1, 0, 0},
					middlecolor = {1, 1, 0},
					arrival = 15,
					lock = false,
					showtta = true,
				},
				minimap = {
					enable = true,
					otherzone = true,
					tooltip = true,
				},
				worldmap = {
					enable = true,
					otherzone = true,
					tooltip = true,
					clickcreate = true,
				},
				comm = {
					enable = true,
					prompt = false,
				},
				persistence = {
					cleardistance = 10,
					savewaypoints = true,
				},
			},
		}

		self.waydefaults = {
			profile = {
				["*"] = {},
			},
		}

		self.db = LibStub("AceDB-3.0"):New("TomTomDB", self.defaults, "Default")
		self.waydb = LibStub("AceDB-3.0"):New("TomTomWaypoints", self.waydefaults)
		self.db.RegisterCallback(self, "OnProfileChanged", "ReloadOptions")
		self.db.RegisterCallback(self, "OnProfileCopied", "ReloadOptions")
		self.db.RegisterCallback(self, "OnProfileReset", "ReloadOptions")
		self.waydb.RegisterCallback(self, "OnProfileChanged", "ReloadWaypoints")
		self.waydb.RegisterCallback(self, "OnProfileCopied", "ReloadWaypoints")
		self.waydb.RegisterCallback(self, "OnProfileReset", "ReloadWaypoints")

		self.tooltip = CreateFrame("GameTooltip", "TomTomTooltip", nil, "GameTooltipTemplate")
		self.dropdown = CreateFrame("Frame", "TomTomDropdown", nil, "UIDropDownMenuTemplate")

		self:RegisterEvent("PLAYER_LEAVING_WORLD")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		self:RegisterEvent("WORLD_MAP_UPDATE")
		self:RegisterEvent("CHAT_MSG_ADDON")

		self:ReloadOptions()
	end
end

function TomTom:ReloadOptions()
	-- This handles the reloading of all options
	self.profile = self.db.profile

	self:ShowHideWorldCoords()
	self:ShowHideCoordBlock()

end

function TomTom:ReloadWaypoints()
end



function TomTom:ShowHideWorldCoords()
	-- Bail out if we're not supposed to be showing this frame
	if self.db.profile.mapcoords.playerenable or self.db.profile.mapcoords.cursorenable then
		-- Create the frame if it doesn't exist
		if not TomTomWorldFrame then
			TomTomWorldFrame = CreateFrame("Frame", nil, WorldMapFrame)
			TomTomWorldFrame.Player = TomTomWorldFrame:CreateFontString("OVERLAY", nil, "GameFontHighlightSmall")
			TomTomWorldFrame.Player:SetPoint("BOTTOM", WorldMapPositioningGuide, "BOTTOM", -100, 11)

			TomTomWorldFrame.Cursor = TomTomWorldFrame:CreateFontString("OVERLAY", nil, "GameFontHighlightSmall")
			TomTomWorldFrame.Cursor:SetPoint("BOTTOM", WorldMapPositioningGuide, "BOTTOM", 100, 11)

			TomTomWorldFrame:SetScript("OnUpdate", WorldMap_OnUpdate)
		end

		TomTomWorldFrame.Player:Hide()
		TomTomWorldFrame.Cursor:Hide()

		if self.db.profile.mapcoords.playerenable then
			TomTomWorldFrame.Player:Show()
		end

		if self.db.profile.mapcoords.cursorenable then
			TomTomWorldFrame.Cursor:Show()
		end

		-- Show the frame
		TomTomWorldFrame:Show()
	elseif TomTomWorldFrame then
		TomTomWorldFrame:Hide()
	end
end

function TomTom:ShowHideCoordBlock()
	-- Bail out if we're not supposed to be showing this frame
	if self.db.profile.block.enable then
		-- Create the frame if it doesn't exist
		if not TomTomBlock then
			-- Create the coordinate display
			TomTomBlock = CreateFrame("Button", "TomTomBlock", UIParent)
			TomTomBlock:SetWidth(120)
			TomTomBlock:SetHeight(32)
			TomTomBlock:SetToplevel(1)
			TomTomBlock:SetFrameStrata("LOW")
			TomTomBlock:SetMovable(true)
			TomTomBlock:EnableMouse(true)
			TomTomBlock:SetClampedToScreen()
			TomTomBlock:RegisterForDrag("LeftButton")
			TomTomBlock:RegisterForClicks("RightButtonUp")
			TomTomBlock:SetPoint("TOP", Minimap, "BOTTOM", -20, -10)

			TomTomBlock.Text = TomTomBlock:CreateFontString("OVERLAY", nil, "GameFontNormal")
			TomTomBlock.Text:SetJustifyH("CENTER")
			TomTomBlock.Text:SetPoint("CENTER", 0, 0)

			TomTomBlock:SetBackdrop({
				bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 16,
				insets = {left = 4, right = 4, top = 4, bottom = 4},
			})
			TomTomBlock:SetBackdropColor(0,0,0,0.4)
			TomTomBlock:SetBackdropBorderColor(1,0.8,0,0.8)

			-- Set behavior scripts
			TomTomBlock:SetScript("OnUpdate", Block_OnUpdate)
			TomTomBlock:SetScript("OnClick", Block_OnClick)
			TomTomBlock:SetScript("OnEnter", Block_OnEnter)
			TomTomBlock:SetScript("OnLeave", Block_OnLeave)
			TomTomBlock:SetScript("OnDragStop", Block_OnDragStop)
			TomTomBlock:SetScript("OnDragStart", Block_OnDragStart)
		end
		-- Show the frame
		TomTomBlock:Show()

		local opt = self.db.profile.block

		-- Update the backdrop color, and border color
		TomTomBlock:SetBackdropColor(unpack(opt.bgcolor))
		TomTomBlock:SetBackdropBorderColor(unpack(opt.bordercolor))

		-- Update the height and width
		TomTomBlock:SetHeight(opt.height)
		TomTomBlock:SetWidth(opt.width)

		-- Update the font size
		local font,height = TomTomBlock.Text:GetFont()
		TomTomBlock.Text:SetFont(font, opt.fontsize, select(3, TomTomBlock.Text:GetFont()))

	elseif TomTomBlock then
		TomTomBlock:Hide()
	end
end

-- Hook the WorldMap OnClick
local Orig_WorldMapButton_OnClick = WorldMapButton_OnClick
function WorldMapButton_OnClick(...)
	local mouseButton, button = ...
	if IsControlKeyDown() and mouseButton == "RightButton" then
		local c,z = GetCurrentMapContinent(), GetCurrentMapZone()
		local x,y = GetCurrentCursorPosition()

		if z == 0 then
			return
		end

		local uid = TomTom:AddZWaypoint(c,z,x*100,y*100)
	else
		return Orig_WorldMapButton_OnClick(...)
	end
end

WorldMapMagnifyingGlassButton:SetText(ZOOM_OUT_BUTTON_TEXT .. "\nCtrl+Right Click To Add a Waypoint")

local function WaypointCallback(event, arg1, arg2, arg3)
	if event == "OnDistanceArrive" then
		TomTom:ClearWaypoint(arg1)
	elseif event == "OnTooltipShown" then
		local tooltip = arg1
		if arg3 then
			tooltip:SetText("TomTom waypoint")
			tooltip:AddLine(string.format("%s yards away", math.floor(arg2)), 1, 1 ,1)
			tooltip:Show()
		else
			tooltip.lines[2]:SetFormattedText("%s yards away", math.floor(arg2), 1, 1, 1)
		end
	end
end

--[[-------------------------------------------------------------------
--  Dropdown menu code
-------------------------------------------------------------------]]--

local dropdown_info = {
	-- Define level one elements here
	[1] = {
		{ -- Title
			text = L["Waypoint Options"],
			isTitle = 1,
		},
		{ -- Remove waypoint
			text = L["Remove waypoint"],
			func = function()
				local uid = TomTom.dropdown.uid
				local data = waypoints[uid]
				TomTom:RemoveWaypoint(uid)
				--TomTom:PrintF("Removing waypoint %0.2f, %0.2f in %s", data.x, data.y, data.zone) 
			end,
		},
	}
}

local function init_dropdown(level)
	-- Make sure level is set to 1, if not supplied
	level = level or 1

	-- Get the current level from the info table
	local info = dropdown_info[level]

	-- If a value has been set, try to find it at the current level
	if level > 1 and UIDROPDOWNMENU_MENU_VALUE then
		if info[UIDROPDOWNMENU_MENU_VALUE] then
			info = info[UIDROPDOWNMENU_MENU_VALUE]
		end
	end

	-- Add the buttons to the menu
	for idx,entry in ipairs(info) do
		UIDropDownMenu_AddButton(entry, level)
	end
end

--[[-------------------------------------------------------------------
--  Define callback functions 
-------------------------------------------------------------------]]--
local function _both_onclick(event, uid, self, button)
	TomTom.dropdown.uid = uid
	UIDropDownMenu_Initialize(TomTom.dropdown, init_dropdown)
	ToggleDropDownMenu(1, nil, TomTom.dropdown, "cursor", 0, 0)
end

local function _both_tooltip_show(event, tooltip, uid, dist)
	local data = waypoints[uid]

	tooltip:SetText(data.title or "TomTom waypoint")
	tooltip:AddLine(string.format("%s yards away", math.floor(dist)), 1, 1, 1)
	tooltip:AddLine(string.format("%s (%.2f, %.2f)", data.zone, data.x, data.y), 0.7, 0.7, 0.7)
	tooltip:Show()
end

local function _minimap_tooltip_show(event, tooltip, uid, dist)
	if not TomTom.db.profile.minimap.tooltip then 
		tooltip:Hide()
		return
	end
	return _both_tooltip_show(event, tooltip, uid, dist)
end

local function _world_tooltip_show(event, tooltip, uid, dist)
	if not TomTom.db.profile.worldmap.tooltip then
		tooltip:Hide()
		return
	end
	return _both_tooltip_show(event, tooltip, uid, dist)
end

local function _both_tooltip_update(event, tooltip, uid, dist)
	tooltip.lines[2]:SetFormattedText("%s yards away", math.floor(dist), 1, 1, 1)
end

local function _both_clear_distance(event, uid, range, distance, lastdistance)
	self:RemoveWaypoint(uid)
end

local function _both_remove(event, uid)
	local data = waypoints[uid]
	local sv = self.db.profile.waypoints[data.zone]

	-- Find the entry in the saved variable
	for idx,entry in ipairs(sv) do
		if entry.uid == uid then
			table.remove(sv, idx)
			break
		end
	end
end

local function noop() end

-- TODO: Make this not suck
function TomTom:AddWaypoint(x, y, desc, persistent, noWorld)
	local oc,oz = Astrolabe:GetCurrentPlayerPosition()
	SetMapToCurrentZone()
	local c,z = Astrolabe:GetCurrentPlayerPosition()
	if oc and oz then
		SetMapZoom(oc,oz)
	end

	if not c or not z or c < 1 then
		--self:Print("Cannot find a valid zone to place the coordinates")
		return
	end

	return self:AddZWaypoint(c, z, x, y, desc, persistent, noWorld)
end

function TomTom:AddZWaypoint(c, z, x, y, desc, persistent, noWorld)
	local callbacks = {
		minimap = {
			onclick = _both_onclick,
			tooltip_show = _minimap_tooltip_show,
			tooltip_update = _both_tooltip_update,
		},
		world = {
			onclick = _both_onclick,
			tooltip_show = _world_tooltip_show,
			tooltip_update = _both_tooltip_show,
		},
		distance = {},
	}

	if persistent == nil then
		persistent = self.db.profile.persistence.savewaypoints
	end

	if not persistent then
		local cleardistance = self.db.profile.persistence.cleardistance
		callbacks.distance[cleardistance] = _both_clear_distance
		callbacks.distance[cleardistance+1] = noop
	end

	local uid = self:SetWaypoint(c,z,x/100,y/100, callbacks, (not noWorld))
	self:SetCrazyArrow(uid, self.db.profile.arrow.arrival, desc)

	local coord = self:GetCoord(x / 100, y / 100)
	local zone = self:GetMapFile(c, z)

	waypoints[uid] = {
		title = desc,
		coord = coord,
		x = x,
		y = y,
		zone = zone,
	}

	-- If this is a persistent waypoint, then add it to the waypoints table
	if persistent then
		local data = string.format("%d:%s", coord, title or "")
		table.insert(self.db.profile.waypoints[zone], data)
	end
end

-- Code taken from HandyNotes, thanks Xinhuan

---------------------------------------------------------
-- Public functions for plugins to convert between MapFile <-> C,Z
--
local continentMapFile = {
	[WORLDMAP_COSMIC_ID] = "Cosmic", -- That constant is -1
	[0] = "World",
	[1] = "Kalimdor",
	[2] = "Azeroth",
	[3] = "Expansion01",
}
local reverseMapFileC = {}
local reverseMapFileZ = {}
for C = 1, #Astrolabe.ContinentList do
	for Z = 1, #Astrolabe.ContinentList[C] do
		local mapFile = Astrolabe.ContinentList[C][Z]
		reverseMapFileC[mapFile] = C
		reverseMapFileZ[mapFile] = Z
	end
end
for C = -1, 3 do
	local mapFile = continentMapFile[C]
	reverseMapFileC[mapFile] = C
	reverseMapFileZ[mapFile] = 0
end

function TomTom:GetMapFile(C, Z)
	if not C or not Z then return end
	if Z == 0 then
		return continentMapFile[C]
	elseif C > 0 then
		return Astrolabe.ContinentList[C][Z]
	end
end
function TomTom:GetCZ(mapFile)
	return reverseMapFileC[mapFile], reverseMapFileZ[mapFile]
end

-- Public functions for plugins to convert between coords <--> x,y
function TomTom:GetCoord(x, y)
	return floor(x * 10000 + 0.5) * 10000 + floor(y * 10000 + 0.5)
end
function TomTom:GetXY(id)
	return floor(id / 10000) / 10000, (id % 10000) / 10000
end

do
	function GetCurrentCursorPosition()
		-- Coordinate calculation code taken from CT_MapMod
		local cX, cY = GetCursorPosition()
		local ceX, ceY = WorldMapFrame:GetCenter()
		local wmfw, wmfh = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()

		cX = ( ( ( cX / WorldMapFrame:GetScale() ) - ( ceX - wmfw / 2 ) ) / wmfw + 22/10000 )
		cY = ( ( ( ( ceY + wmfh / 2 ) - ( cY / WorldMapFrame:GetScale() ) ) / wmfh ) - 262/10000 )

		return cX, cY
	end

	local coord_fmt = "%%.%df, %%.%df"
	function RoundCoords(x,y,prec)
		local fmt = coord_fmt:format(prec, prec)
		return fmt:format(x*100, y*100)
	end

	function WorldMap_OnUpdate(self, elapsed)
		local c,z,x,y = Astrolabe:GetCurrentPlayerPosition()
		local opt = TomTom.db.profile

		if not x or not y then
			self.Player:SetText("Player: ---")
		else
			self.Player:SetFormattedText("Player: %s", RoundCoords(x, y, opt.mapcoords.playeraccuracy))
		end

		local cX, cY = GetCurrentCursorPosition()

		if not cX or not cY then
			self.Cursor:SetText("Cursor: ---")
		else
			self.Cursor:SetFormattedText("Cursor: %s", RoundCoords(cX, cY, opt.mapcoords.cursoraccuracy))
		end
	end
end

do 
	function Block_OnUpdate(self, elapsed)
		local c,z,x,y = Astrolabe:GetCurrentPlayerPosition()
		local opt = TomTom.db.profile

		if not x or not y then
			-- Hide the frame when we have no coordinates
			self:Hide()
		else
			self.Text:SetFormattedText("%s", RoundCoords(x, y, opt.block.accuracy))
		end
	end

	function Block_OnDragStart(self, button, down)
		if not TomTom.db.profile.block.lock then
			self:StartMoving()
		end
	end

	function Block_OnDragStop(self, button, down)
		self:StopMovingOrSizing()
	end
end

SLASH_WAY1 = "/way"
SlashCmdList["WAY"] = function(msg)
	local x,y,desc = msg:match("(%d+%.?%d*)%s+(%d+%.?%d*)%s*(.*)$")
	if not desc:match("%S") then desc = nil end

	x,y = tonumber(x), tonumber(y)
	--TomTom:PrintF("Adding waypoint %d %d", x, y)
	TomTom:AddWaypoint(x, y, desc)
end
