--[[--------------------------------------------------------------------------
--  TomTom - A navigational assistant for World of Warcraft
----------------------------------------------------------------------------]]

-- Import Astrolabe for locations
local Astrolabe = DongleStub("Astrolabe-0.4-NC")

-- Create a tooltip to be used when mousing over waypoints
local tooltip = CreateFrame("GameTooltip", "TomTomTooltip", UIParent, "GameTooltipTemplate")
do
	-- Set the the tooltip's lines
	local i = 1
	tooltip.lines = {}
	repeat
		local line = getglobal("TomTomTooltipTextLeft"..i)
		if line then
			tooltip.lines[i] = line
		end
		i = i + 1
	until not line
end

-- Create a local table used as a frame pool
local pool = {}

-- Create a mapping from uniqueID to waypoint
local getuid,resolveuid
do
	local uidmap = {}
	local uid = 0
	function getuid(obj)
		-- Ensure the object doesn't already have a uid mapping
		for k,v in pairs(uidmap) do
			if obj == v then
				error("Attempt to re-use an object without clearing identifier")
			end
		end

		-- Establish the new mapping
		uid = uid + 1

		uidmap[uid] = obj

		return uid
	end

	function resolveuid(uid, remove)
		-- Return the object that corresponds to the UID
		local obj = uidmap[uid]

		if remove then
			uidmap[uid] = nil
		end

		return obj
	end
end

-- Local declarations
local Minimap_OnEnter,Minimap_OnLeave,Minimap_OnUpdate,Minimap_OnClick,Minimap_OnEvent
local Arrow_OnUpdate
local World_OnEnter,World_OnLeave,World_OnClick,World_OnEvent

function TomTom:SetWaypoint(c, z, x, y, callbacks, show_minimap, show_world)
	-- Try to acquire a waypoint from the frame pool
	local point = table.remove(pool)

	if not point then
		point = {}

		local minimap = CreateFrame("Button", nil, Minimap)
		minimap:SetHeight(20)
		minimap:SetWidth(20)
		minimap:RegisterForClicks("RightButtonUp")

		minimap.icon = minimap:CreateTexture("BACKGROUND")
		minimap.icon:SetTexture("Interface\\AddOns\\TomTom\\Images\\GoldGreenDot")
		minimap.icon:SetPoint("CENTER", 0, 0)
		minimap.icon:SetHeight(12)
		minimap.icon:SetWidth(12)

		minimap.arrow = minimap:CreateTexture("BACKGROUND")
		minimap.arrow:SetTexture("Interface\\AddOns\\TomTom\\Images\\MinimapArrow-Green")
		minimap.arrow:SetPoint("CENTER", 0 ,0)
		minimap.arrow:SetHeight(40)
		minimap.arrow:SetWidth(40)
		minimap.arrow:Hide()

		-- Add the behavior scripts 
		minimap:SetScript("OnEnter", Minimap_OnEnter)
		minimap:SetScript("OnLeave", Minimap_OnLeave)
		minimap:SetScript("OnUpdate", Minimap_OnUpdate)
		minimap:SetScript("OnClick", Minimap_OnClick)
		minimap:RegisterEvent("PLAYER_ENTERING_WORLD")
		minimap:SetScript("OnEvent", Minimap_OnEvent)

		local worldmap = CreateFrame("Button", nil, WorldMapDetailFrame)
		worldmap:SetHeight(12)
		worldmap:SetWidth(12)
		worldmap:RegisterForClicks("RightButtonUp")
		worldmap.icon = worldmap:CreateTexture("ARTWORK")
		worldmap.icon:SetAllPoints()
		worldmap.icon:SetTexture("Interface\\AddOns\\TomTom\\Images\\GoldGreenDot")

		worldmap:RegisterEvent("WORLD_MAP_UPDATE")
		worldmap:SetScript("OnEnter", World_OnEnter)
		worldmap:SetScript("OnLeave", World_OnLeave)
		worldmap:SetScript("OnClick", World_OnClick)
		worldmap:SetScript("OnEvent", World_OnEvent)

		point.worldmap = worldmap
		point.minimap = minimap
	end

	point.c = c
	point.z = z
	point.x = x
	point.y = y
	point.show_world = show_world
	point.show_minimap = show_minimap
	point.callbacks = callbacks
	point.worldmap.callbacks = callbacks and callbacks.world
	point.minimap.callbacks = callbacks and callbacks.minimap

	-- Process the callbacks table to put distances in a consumable format
	if callbacks and callbacks.distance then
		local list = {}

		for k,v in pairs(callbacks.distance) do
			table.insert(list, k)
		end

		table.sort(list)
		callbacks.__distances = list
	end

	-- Link the actual frames back to the waypoint object
	point.minimap.point = point
	point.worldmap.point = point

	-- Place the waypoint
	Astrolabe:PlaceIconOnMinimap(point.minimap, c, z, x, y)

	if show_world then
		Astrolabe:PlaceIconOnWorldMap(WorldMapDetailFrame, point.worldmap, c, z, x, y)
	end

	if not show_minimap then
		-- Hide the minimap icon/arrow if minimap is off
		point.minimap:EnableMouse(false)
		point.minimap.icon:Hide()
		point.minimap.arrow:Hide()
		point.minimap:SetScript("OnUpdate", nil)
	else
		point.minimap:EnableMouse(true)
		point.minimap:SetScript("OnUpdate", Minimap_OnUpdate)
		Minimap_OnUpdate(point.minimap, 5.0)
	end

	point.uid = getuid(point)
	return point.uid
end

function TomTom:ClearWaypoint(uid)
	local point = resolveuid(uid, true)
	if point then
		Astrolabe:RemoveIconFromMinimap(point.minimap)
		point.minimap:Hide()
		point.worldmap:Hide()
		table.insert(pool, point)
		point.uid = nil
	end
end

function TomTom:GetDistanceToWaypoint(uid)
	local point = resolveuid(uid)
	return point and Astrolabe:GetDistanceToIcon(point.minimap)
end

function TomTom:GetDirectionToWaypoint(uid)
	local point = resolveuid(uid)
	return point and Astrolabe:GetDirectionToIcon(point.minimap)
end

do
	local tooltip_uid,tooltip_callbacks

	local function tooltip_onupdate(self, elapsed)
		if tooltip_callbacks and tooltip_callbacks.tooltip_update then
			local dist,x,y = TomTom:GetDistanceToWaypoint(tooltip_uid)
			tooltip_callbacks.tooltip_update("tooltip_update", tooltip, tooltip_uid, dist)
		end
	end

	function Minimap_OnClick(self, button)
		local data = self.callbacks

		if data and data.onclick then
			data.onclick("onclick", self.point.uid, self, button)
		end
	end

	function Minimap_OnEnter(self, motion)
		local data = self.callbacks

		if data and data.tooltip_show then
			local uid = self.point.uid
			local dist,x,y = TomTom:GetDistanceToWaypoint(uid)

			tooltip_uid = uid
			tooltip_callbacks = data

			-- Parent to UIParent, unless it's hidden
			if UIParent:IsVisible() then
				tooltip:SetParent(UIParent)
			else
				tooltip:SetParent(self)
			end

			tooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")

			data.tooltip_show("tooltip_show", tooltip, uid, dist)
			tooltip:Show()

			-- Set the update script if there is one
			if data.tooltip_update then
				tooltip:SetScript("OnUpdate", tooltip_onupdate)
			else
				tooltip:SetScript("OnUpdate", nil)
			end
		end
	end

	function Minimap_OnLeave(self, motion)
		tooltip_uid,tooltip_callbacks = nil,nil
		tooltip:Hide()
	end

	World_OnEnter = Minimap_OnEnter
	World_OnLeave = Minimap_OnLeave
	World_OnClick = Minimap_OnClick

	local square_half = math.sqrt(0.5)
	local rad_135 = math.rad(135)
	local minimap_count = 0
	function Minimap_OnUpdate(self, elapsed)
		local dist,x,y = Astrolabe:GetDistanceToIcon(self)
		if not dist then
			self:Hide()
			return
		end

		minimap_count = minimap_count + elapsed

		-- Only take action every 0.2 seconds
		if minimap_count < 0.1 then return end

		-- Reset the counter
		minimap_count = 0

		local edge = Astrolabe:IsIconOnEdge(self)
		local data = self.point
		local callbacks = data.callbacks

		if edge then
			-- Check to see if this is a transition
			self.icon:Hide()
			self.arrow:Show()

			-- Rotate the icon, as required
			local angle = Astrolabe:GetDirectionToIcon(self)
			angle = angle + rad_135

			if GetCVar("rotateMinimap") == "1" then
				local cring = MiniMapCompassRing:GetFacing()
				angle = angle + cring
			end

			local sin,cos = math.sin(angle) * square_half, math.cos(angle) * square_half
			self.arrow:SetTexCoord(0.5-sin, 0.5+cos, 0.5+cos, 0.5+sin, 0.5-cos, 0.5-sin, 0.5+sin, 0.5-cos)

		else
			self.icon:Show()
			self.arrow:Hide()
		end

		if callbacks and callbacks.distance then
			local list = callbacks.__distances

			local state = data.state
			local newstate

			-- Calculate the initial state
			if not state then
				for i=1,#list do
					if dist <= list[i] then
						state = i
						break
					end
				end

				-- Handle the case where we're outside the largest circle
				if not state then state = #list end

				data.state = state
			else
				-- Calculate the new state
				for i=1,#list do
					if dist <= list[i] then
						newstate = i
						break
					end
				end

				-- Handle the case where we're outside the largest circle
				if not newstate then newstate = #list end
			end

			-- If newstate is set, then this is a transition
			-- If only state is set, this is the initial state

			if state ~= newstate then
				-- Handle the initial state
				newstate = newstate or state
				local distance = list[newstate]
				local callback = callbacks.distance[distance]
				if callback then
					callback("distance", self.point.uid, distance, dist, data.lastdist)
				end
				data.state = newstate
			end	

			-- Update the last distance with the current distance
			data.lastdist = dist
		end
	end

	function World_OnEvent(self, event, ...)
		if event == "WORLD_MAP_UPDATE" then
			if not self.point.uid then
				return
			end

			local data = self.point
			if data.worldmap and data.show_world then
				local x,y = Astrolabe:PlaceIconOnWorldMap(WorldMapDetailFrame, self, data.c, data.z, data.x, data.y)
				if (x and y and (0 < x and x <= 1) and (0 < y and y <= 1)) then
					self:Show()
				else
					self:Hide()
				end
			else
				self:Hide()
			end
		end
	end

	function Minimap_OnEvent(self, event, ...)
		if event == "PLAYER_ENTERING_WORLD" then
			local data = self.point
			if data and data.uid and resolveuid(data.uid) then
				Astrolabe:PlaceIconOnMinimap(self, data.c, data.z, data.x, data.y)
			end
		end
	end
end
