--[[
Name: Astrolabe
Revision: $Rev: 58 $
$Date: 2008-02-07 17:16:11 +0000 (Thu, 07 Feb 2008) $
Author(s): Esamynn (esamynn@wowinterface.com)
Inspired By: Gatherer by Norganna
             MapLibrary by Kristofer Karlsson (krka@kth.se)
Documentation: http://wiki.esamynn.org/Astrolabe
SVN: http://svn.esamynn.org/astrolabe/
Description:
	This is a library for the World of Warcraft UI system to place
	icons accurately on both the Minimap and the Worldmaps accurately
	and maintain the accuracy of those positions.

Copyright (C) 2006-2008 James Carrothers

License:
	This library is free software; you can redistribute it and/or
	modify it under the terms of the GNU Lesser General Public
	License as published by the Free Software Foundation; either
	version 2.1 of the License, or (at your option) any later version.

	This library is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	Lesser General Public License for more details.

	You should have received a copy of the GNU Lesser General Public
	License along with this library; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

Note:
	This library's source code is specifically designed to work with
	World of Warcraft's interpreted AddOn system.  You have an implicit
	licence to use this library with these facilities since that is its
	designated purpose as per:
	http://www.fsf.org/licensing/licenses/gpl-faq.html#InterpreterIncompat
]]

-- WARNING!!!
-- DO NOT MAKE CHANGES TO THIS LIBRARY WITHOUT FIRST CHANGING THE LIBRARY_VERSION_MAJOR
-- STRING (to something unique) OR ELSE YOU MAY BREAK OTHER ADDONS THAT USE THIS LIBRARY!!!
local LIBRARY_VERSION_MAJOR = "Astrolabe-0.4"
local LIBRARY_VERSION_MINOR = tonumber(string.match("$Revision: 58 $", "(%d+)") or 1)

if not DongleStub then error(LIBRARY_VERSION_MAJOR .. " requires DongleStub.") end
if not DongleStub:IsNewerVersion(LIBRARY_VERSION_MAJOR, LIBRARY_VERSION_MINOR) then return end

local Astrolabe = {};

-- define local variables for Data Tables (defined at the end of this file)
local WorldMapSize, MinimapSize, ValidMinimapShapes;

function Astrolabe:GetVersion()
    return LIBRARY_VERSION_MAJOR, LIBRARY_VERSION_MINOR;
end


--------------------------------------------------------------------------------------------------------------
-- Config Constants
--------------------------------------------------------------------------------------------------------------

local configConstants = {
    MinimapUpdateMultiplier = true,
}

-- this constant is multiplied by the current framerate to determine
-- how many icons are updated each frame
Astrolabe.MinimapUpdateMultiplier = 1;

--------------------------------------------------------------------------------------------------------------
-- Working Tables
--------------------------------------------------------------------------------------------------------------

Astrolabe.LastPlayerPosition = { 0, 0, 0, 0 };
Astrolabe.MinimapIcons = {};
Astrolabe.IconsOnEdge = {};
Astrolabe.IconsOnEdge_GroupChangeCallbacks = {};

Astrolabe.UpdateTimer = 0;
Astrolabe.ForceNextUpdate = false;
Astrolabe.IconsOnEdgeChanged = false;

-- This variable indicates whether we know of a visible World Map or not.
-- The state of this variable is controlled by the AstrolabeMapMonitor library.
Astrolabe.WorldMapVisible = false;

local AddedOrUpdatedIcons = {}
local MinimapIconsMetatable = { __index = AddedOrUpdatedIcons }

--------------------------------------------------------------------------------------------------------------
-- Internal Utility Functions
--------------------------------------------------------------------------------------------------------------

local function assert(level,condition,message)
    if not condition then
        error(message,level)
    end
end

local function argcheck(value, num, ...)
    assert(1, type(num) == "number", "Bad argument #2 to 'argcheck' (number expected, got " .. type(level) .. ")")

    for i=1,select("#", unpack(arg)) do
        if type(value) == select(i, unpack(arg)) then return end
    end

    local types = strjoin(", ", unpack(arg))
    local name = string.match(debugstack(2,2,0), ": in function [`<](.-)['>]")
    error(string.format("Bad argument #%d to 'Astrolabe.%s' (%s expected, got %s)", num, name, types, type(value)), 3)
end

local function getContPosition( zoneData, z, x, y )
    if ( z ~= 0 ) then
        zoneData = zoneData[z];
        x = x * zoneData.width + zoneData.xOffset;
        y = y * zoneData.height + zoneData.yOffset;
    else
        x = x * zoneData.width;
        y = y * zoneData.height;
    end
    return x, y;
end


--------------------------------------------------------------------------------------------------------------
-- General Utility Functions
--------------------------------------------------------------------------------------------------------------

function Astrolabe:ComputeDistance( c1, z1, x1, y1, c2, z2, x2, y2 )
    --[[
	argcheck(c1, 2, "number");
	assert(3, c1 >= 0, "ComputeDistance: Illegal continent index to c1: "..c1);
	argcheck(z1, 3, "number", "nil");
	argcheck(x1, 4, "number");
	argcheck(y1, 5, "number");
	argcheck(c2, 6, "number");
	assert(3, c2 >= 0, "ComputeDistance: Illegal continent index to c2: "..c2);
	argcheck(z2, 7, "number", "nil");
	argcheck(x2, 8, "number");
	argcheck(y2, 9, "number");
    --]]

    z1 = z1 or 0;
    z2 = z2 or 0;

    local dist, xDelta, yDelta;
    if ( c1 == c2 and z1 == z2 ) then
        -- points in the same zone
        local zoneData = WorldMapSize[c1];
        if ( z1 ~= 0 ) then
            zoneData = zoneData[z1];
        end
        xDelta = (x2 - x1) * zoneData.width;
        yDelta = (y2 - y1) * zoneData.height;

    elseif ( c1 == c2 ) then
        -- points on the same continent
        local zoneData = WorldMapSize[c1];
        x1, y1 = getContPosition(zoneData, z1, x1, y1);
        x2, y2 = getContPosition(zoneData, z2, x2, y2);
        xDelta = (x2 - x1);
        yDelta = (y2 - y1);

    elseif ( c1 and c2 ) then
        local cont1 = WorldMapSize[c1];
        local cont2 = WorldMapSize[c2];
        if ( cont1.parentContinent == cont2.parentContinent ) then
            x1, y1 = getContPosition(cont1, z1, x1, y1);
            x2, y2 = getContPosition(cont2, z2, x2, y2);
            if ( c1 ~= cont1.parentContinent ) then
                x1 = x1 + cont1.xOffset;
                y1 = y1 + cont1.yOffset;
            end
            if ( c2 ~= cont2.parentContinent ) then
                x2 = x2 + cont2.xOffset;
                y2 = y2 + cont2.yOffset;
            end

            xDelta = x2 - x1;
            yDelta = y2 - y1;
        end

    end
    if ( xDelta and yDelta ) then
        dist = sqrt(xDelta*xDelta + yDelta*yDelta);
    end
    return dist, xDelta, yDelta;
end

function Astrolabe:TranslateWorldMapPosition( C, Z, xPos, yPos, nC, nZ )
    --[[
	argcheck(C, 2, "number");
	argcheck(Z, 3, "number", "nil");
	argcheck(xPos, 4, "number");
	argcheck(yPos, 5, "number");
	argcheck(nC, 6, "number");
	argcheck(nZ, 7, "number", "nil");
    --]]

    Z = Z or 0;
    nZ = nZ or 0;
    if ( nC < 0 ) then
        return;
    end

    local zoneData;
    if ( C == nC and Z == nZ ) then
        return xPos, yPos;

    elseif ( C == nC ) then
        -- points on the same continent
        zoneData = WorldMapSize[C];
        xPos, yPos = getContPosition(zoneData, Z, xPos, yPos);
        if ( nZ ~= 0 ) then
            zoneData = WorldMapSize[C][nZ];
            xPos = xPos - zoneData.xOffset;
            yPos = yPos - zoneData.yOffset;
        end

    elseif ( C and nC ) and ( WorldMapSize[C].parentContinent == WorldMapSize[nC].parentContinent ) then
        -- different continents, same world
        zoneData = WorldMapSize[C];
        local parentContinent = zoneData.parentContinent;
        xPos, yPos = getContPosition(zoneData, Z, xPos, yPos);
        if ( C ~= parentContinent ) then
            -- translate up to world map if we aren't there already
            xPos = xPos + zoneData.xOffset;
            yPos = yPos + zoneData.yOffset;
            zoneData = WorldMapSize[parentContinent];
        end
        if ( nC ~= parentContinent ) then
            -- translate down to the new continent
            zoneData = WorldMapSize[nC];
            xPos = xPos - zoneData.xOffset;
            yPos = yPos - zoneData.yOffset;
            if ( nZ ~= 0 ) then
                zoneData = zoneData[nZ];
                xPos = xPos - zoneData.xOffset;
                yPos = yPos - zoneData.yOffset;
            end
        end

    else
        return;
    end

    return (xPos / zoneData.width), (yPos / zoneData.height);
end

--*****************************************************************************
-- This function will do its utmost to retrieve some sort of valid position
-- for the specified unit, including changing the current map zoom (if needed).
-- Map Zoom is returned to its previous setting before this function returns.
--*****************************************************************************
function Astrolabe:GetUnitPosition( unit, noMapChange )
    local x, y = GetPlayerMapPosition(unit);
    if ( x <= 0 and y <= 0 ) then
        if ( noMapChange ) then
            -- no valid position on the current map, and we aren't allowed
            -- to change map zoom, so return
            return;
        end
        local lastCont, lastZone = GetCurrentMapContinent(), GetCurrentMapZone();
        SetMapToCurrentZone();
        x, y = GetPlayerMapPosition(unit);
        if ( x <= 0 and y <= 0 ) then
            SetMapZoom(GetCurrentMapContinent());
            x, y = GetPlayerMapPosition(unit);
            if ( x <= 0 and y <= 0 ) then
                -- we are in an instance or otherwise off the continent map
                return;
            end
        end
        local C, Z = GetCurrentMapContinent(), GetCurrentMapZone();
        if ( C ~= lastCont or Z ~= lastZone ) then
            SetMapZoom(lastCont, lastZone); -- set map zoom back to what it was before
        end
        return C, Z, x, y;
    end
    return GetCurrentMapContinent(), GetCurrentMapZone(), x, y;
end

--*****************************************************************************
-- This function will do its utmost to retrieve some sort of valid position
-- for the specified unit, including changing the current map zoom (if needed).
-- However, if a monitored WorldMapFrame (See AstrolabeMapMonitor.lua) is
-- visible, then will simply return nil if the current zoom does not provide
-- a valid position for the player unit.  Map Zoom is returned to its previous
-- setting before this function returns, if it was changed.
--*****************************************************************************
function Astrolabe:GetCurrentPlayerPosition()
    local x, y = GetPlayerMapPosition("player");
    if ( x <= 0 and y <= 0 ) then
        if ( self.WorldMapVisible ) then
            -- we know there is a visible world map, so don't cause
            -- WORLD_MAP_UPDATE events by changing map zoom
            return;
        end
        local lastCont, lastZone = GetCurrentMapContinent(), GetCurrentMapZone();
        SetMapToCurrentZone();
        x, y = GetPlayerMapPosition("player");
        if ( x <= 0 and y <= 0 ) then
            SetMapZoom(GetCurrentMapContinent());
            x, y = GetPlayerMapPosition("player");
            if ( x <= 0 and y <= 0 ) then
                -- we are in an instance or otherwise off the continent map
                return;
            end
        end
        local C, Z = GetCurrentMapContinent(), GetCurrentMapZone();
        if ( C ~= lastCont or Z ~= lastZone ) then
            SetMapZoom(lastCont, lastZone); --set map zoom back to what it was before
        end
        return C, Z, x, y;
    end
    return GetCurrentMapContinent(), GetCurrentMapZone(), x, y;
end


--------------------------------------------------------------------------------------------------------------
-- Working Table Cache System
--------------------------------------------------------------------------------------------------------------

local tableCache = {};
tableCache["__mode"] = "v";
setmetatable(tableCache, tableCache);

local function GetWorkingTable( icon )
    if ( tableCache[icon] ) then
        return tableCache[icon];
    else
        local T = {};
        tableCache[icon] = T;
        return T;
    end
end


--------------------------------------------------------------------------------------------------------------
-- Minimap Icon Placement
--------------------------------------------------------------------------------------------------------------

-- local variables specifically for use in this section
local minimapShape = false;
local MinimapCompassRing = MiniMapCompassRing;
local twoPi = math.pi * 2;
local atan2 = math.atan2;
local sin = math.sin;
local cos = math.cos;
local abs = math.abs;
local sqrt = math.sqrt;
local min = math.min

local function placeIconOnMinimap( minimap, minimapZoom, mapWidth, mapHeight, icon, dist, xDist, yDist )
    local mapDiameter;
    if ( Astrolabe.minimapOutside ) then
        mapDiameter = MinimapSize.outdoor[minimapZoom];
    else
        mapDiameter = MinimapSize.indoor[minimapZoom];
    end
    local mapRadius = mapDiameter / 2;
    local xScale = mapDiameter / mapWidth;
    local yScale = mapDiameter / mapHeight;
    local iconDiameter = ((icon:GetWidth() / 2) + 3) * xScale;
    local iconOnEdge = nil;
    local isRound = true;

    if ( minimapShape and not (xDist == 0 or yDist == 0) ) then
        isRound = (xDist < 0) and 1 or 3;
        if ( yDist < 0 ) then
            isRound = minimapShape[isRound];
        else
            isRound = minimapShape[isRound + 1];
        end
    end

    -- for non-circular portions of the Minimap edge
    if not ( isRound ) then
        dist = (abs(xDist) > abs(yDist)) and abs(xDist) or abs(yDist);
    end

    if ( (dist + iconDiameter) > mapRadius ) then
        -- position along the outside of the Minimap
        iconOnEdge = true;
        local factor = (mapRadius - iconDiameter) / dist;
        xDist = xDist * factor;
        yDist = yDist * factor;
    end

    if ( Astrolabe.IconsOnEdge[icon] ~= iconOnEdge ) then
        Astrolabe.IconsOnEdge[icon] = iconOnEdge;
        Astrolabe.IconsOnEdgeChanged = true;
    end

    icon:ClearAllPoints();
    icon:SetPoint("CENTER", minimap, "CENTER", xDist/xScale, -yDist/yScale);
end

function Astrolabe:PlaceIconOnMinimap( icon, continent, zone, xPos, yPos )
    -- check argument types
    argcheck(icon, 2, "table");
    assert(3, icon.SetPoint and icon.ClearAllPoints, "Usage Message");
    argcheck(continent, 3, "number");
    argcheck(zone, 4, "number", "nil");
    argcheck(xPos, 5, "number");
    argcheck(yPos, 6, "number");

    local lC, lZ, lx, ly = unpack(self.LastPlayerPosition);
    local dist, xDist, yDist = self:ComputeDistance(lC, lZ, lx, ly, continent, zone, xPos, yPos);
    if not ( dist ) then
        --icon's position has no meaningful position relative to the player's current location
        return -1;
    end
    local iconData = GetWorkingTable(icon);
    iconData = GetWorkingTable(icon);
    self.MinimapIcons[icon] = nil;
    AddedOrUpdatedIcons[icon] = iconData

    iconData.continent = continent;
    iconData.zone = zone;
    iconData.xPos = xPos;
    iconData.yPos = yPos;
    iconData.dist = dist;
    iconData.xDist = xDist;
    iconData.yDist = yDist;

    -- check Minimap Shape
    minimapShape = GetMinimapShape and ValidMinimapShapes[GetMinimapShape()];

    -- place the icon on the Minimap and :Show() it
    local map = Minimap
    placeIconOnMinimap(map, map:GetZoom(), map:GetWidth(), map:GetHeight(), icon, dist, xDist, yDist);
    icon:Show()

    return 0;
end

function Astrolabe:RemoveIconFromMinimap( icon )
    if not ( self.MinimapIcons[icon] ) then
        return 1;
    end
    AddedOrUpdatedIcons[icon] = nil
    self.MinimapIcons[icon] = nil;
    self.IconsOnEdge[icon] = nil;
    icon:Hide();
    return 0;
end

function Astrolabe:RemoveAllMinimapIcons()
    self:DumpNewIconsCache()
    local minimapIcons = self.MinimapIcons;
    local IconsOnEdge = self.IconsOnEdge;
    for k, v in pairs(minimapIcons) do
        minimapIcons[k] = nil;
        IconsOnEdge[k] = nil;
        k:Hide();
    end
end

local lastZoom; -- to remember the last seen Minimap zoom level

function Astrolabe:UpdateMinimapIconPositions()
    self:CalculateMinimapIconPositions()
end

-- local variables to track the full update coroutine
local fullUpdateCrashed = true
local fullUpdateThread


function Astrolabe:CalculateMinimapIconPositions()
    local C, Z, x, y = self:GetCurrentPlayerPosition();
    if ( C and C >= 0 ) then
        -- put new/updated icons into the main datacache
        self:DumpNewIconsCache()

        -- check current frame rate
        local numPerCycle = GetFramerate() * (self.MinimapUpdateMultiplier or 1) * 2

        -- check Minimap Shape
        minimapShape = GetMinimapShape and ValidMinimapShapes[GetMinimapShape()];

        local currentZoom = Minimap:GetZoom();
        lastZoom = currentZoom;
        local Minimap = Minimap;
        local mapWidth = Minimap:GetWidth();
        local mapHeight = Minimap:GetHeight();
        local count = 0
        for icon, data in pairs(self.MinimapIcons) do
            local dist, xDist, yDist = self:ComputeDistance(C, Z, x, y, data.continent, data.zone, data.xPos, data.yPos);
            if ( dist ) then
                placeIconOnMinimap(Minimap, currentZoom, mapWidth, mapHeight, icon, dist, xDist, yDist);

                data.dist = dist;
                data.xDist = xDist;
                data.yDist = yDist;
            else
                self:RemoveIconFromMinimap(icon)
            end

            count = count + 1
            if ( count >= numPerCycle ) then
                count = 0
            end
        end

        local lastPosition = self.LastPlayerPosition;
        lastPosition[1] = C;
        lastPosition[2] = Z;
        lastPosition[3] = x;
        lastPosition[4] = y;
    else
        if not ( self.WorldMapVisible ) then
            self.processingFrame:Hide();
        end
    end
end

function Astrolabe:GetDistanceToIcon( icon )
    local data = self.MinimapIcons[icon];
    if ( data ) then
        return data.dist, data.xDist, data.yDist;
    end
end

function Astrolabe:IsIconOnEdge( icon )
    return self.IconsOnEdge[icon];
end

function Astrolabe:GetDirectionToIcon( icon )
    local data = self.MinimapIcons[icon];
    if ( data ) then
        local dir = atan2(data.xDist, -(data.yDist))
        if ( dir > 0 ) then
            return twoPi - dir;
        else
            return -dir;
        end
    end
end

function Astrolabe:Register_OnEdgeChanged_Callback( func, ident )
    -- check argument types
    argcheck(func, 2, "function");

    self.IconsOnEdge_GroupChangeCallbacks[func] = ident;
end

-- for use ONLY by the activate function
function Astrolabe:DumpNewIconsCache()
    local MinimapIcons = self.MinimapIcons
    for icon, data in pairs(AddedOrUpdatedIcons) do
        MinimapIcons[icon] = data
        AddedOrUpdatedIcons[icon] = nil
    end
end


--------------------------------------------------------------------------------------------------------------
-- World Map Icon Placement
--------------------------------------------------------------------------------------------------------------

function Astrolabe:PlaceIconOnWorldMap( worldMapFrame, icon, continent, zone, xPos, yPos )
    -- check argument types
    argcheck(worldMapFrame, 2, "table");
    assert(3, worldMapFrame.GetWidth and worldMapFrame.GetHeight, "Usage Message");
    argcheck(icon, 3, "table");
    assert(3, icon.SetPoint and icon.ClearAllPoints, "Usage Message");
    argcheck(continent, 4, "number");
    argcheck(zone, 5, "number", "nil");
    argcheck(xPos, 6, "number");
    argcheck(yPos, 7, "number");

    local C, Z = GetCurrentMapContinent(), GetCurrentMapZone();
    local nX, nY = self:TranslateWorldMapPosition(continent, zone, xPos, yPos, C, Z);

    -- anchor and :Show() the icon if it is within the boundry of the current map, :Hide() it otherwise
    if ( nX and nY and (0 < nX and nX <= 1) and (0 < nY and nY <= 1) ) then
        icon:ClearAllPoints();
        icon:SetPoint("CENTER", worldMapFrame, "TOPLEFT", nX * worldMapFrame:GetWidth(), -nY * worldMapFrame:GetHeight());
        icon:Show();
    else
        icon:Hide();
    end
    return nX, nY;
end


--------------------------------------------------------------------------------------------------------------
-- Handler Scripts
--------------------------------------------------------------------------------------------------------------

function Astrolabe:OnEvent( frame, event )
    if ( event == "MINIMAP_UPDATE_ZOOM" ) then
        -- update minimap zoom scale
        local Minimap = Minimap;
        local curZoom = Minimap:GetZoom();
        if ( GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") ) then
            if ( curZoom < 2 ) then
                Minimap:SetZoom(curZoom + 1);
            else
                Minimap:SetZoom(curZoom - 1);
            end
        end
        if ( GetCVar("minimapZoom")+0 == Minimap:GetZoom() ) then
            self.minimapOutside = true;
        else
            self.minimapOutside = false;
        end
        Minimap:SetZoom(curZoom);

        -- re-calculate all Minimap Icon positions
        if ( frame:IsVisible() ) then
            self:CalculateMinimapIconPositions();
        end

    elseif ( event == "PLAYER_LEAVING_WORLD" ) then
        frame:Hide();
        self:RemoveAllMinimapIcons(); --dump all minimap icons

    elseif ( event == "PLAYER_ENTERING_WORLD" ) then
        frame:Show();
        if not ( frame:IsVisible() ) then
            -- do the minimap recalculation anyways if the OnShow script didn't execute
            self:CalculateMinimapIconPositions();
        end

    elseif ( event == "ZONE_CHANGED_NEW_AREA" ) then
        frame:Hide();
        frame:Show();

    end
end

function Astrolabe:OnUpdate( frame, elapsed )
    -- on-edge group changed call-backs
    if ( self.IconsOnEdgeChanged ) then
        self.IconsOnEdgeChanged = false;
        for func in pairs(self.IconsOnEdge_GroupChangeCallbacks) do
            pcall(func);
        end
    end

    self:UpdateMinimapIconPositions();
end

function Astrolabe:OnShow( frame )
    -- set the world map to a zoom with a valid player position
    if not ( self.WorldMapVisible ) then
        SetMapToCurrentZone();
    end
    local C, Z = Astrolabe:GetCurrentPlayerPosition();
    if ( C and C >= 0 ) then
        SetMapZoom(C, Z);
    else
        frame:Hide();
    end

    -- re-calculate minimap icon positions
    self:CalculateMinimapIconPositions();
end

-- called by AstrolabMapMonitor when all world maps are hidden
function Astrolabe:AllWorldMapsHidden()
    self.processingFrame:Hide();
    self.processingFrame:Show();
end


--------------------------------------------------------------------------------------------------------------
-- Library Registration
--------------------------------------------------------------------------------------------------------------

local function activate( newInstance, oldInstance )
    if ( oldInstance ) then -- this is an upgrade activate
        if ( oldInstance.DumpNewIconsCache ) then
            oldInstance:DumpNewIconsCache()
        end
        for k, v in pairs(oldInstance) do
            if ( type(v) ~= "function" and (not configConstants[k]) ) then
                newInstance[k] = v;
            end
        end
        Astrolabe = oldInstance;
    else
        local frame = CreateFrame("Frame");
        frame:Hide();
        newInstance.processingFrame = frame;

        newInstance.ContinentList = { GetMapContinents() };
        for C in pairs(newInstance.ContinentList) do
            local zones = { GetMapZones(C) };
            newInstance.ContinentList[C] = zones;
            for Z in ipairs(zones) do
                SetMapZoom(C, Z);
                zones[Z] = GetMapInfo();
            end
        end
    end
    configConstants = nil -- we don't need this anymore

    local frame = newInstance.processingFrame;
    frame:SetParent("Minimap");
    frame:UnregisterAllEvents();
    frame:RegisterEvent("MINIMAP_UPDATE_ZOOM");
    frame:RegisterEvent("PLAYER_LEAVING_WORLD");
    frame:RegisterEvent("PLAYER_ENTERING_WORLD");
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
    frame:SetScript("OnEvent",
                    function( ... )
			Astrolabe:OnEvent(this, event, unpack(arg));
                    end
    );
    frame:SetScript("OnUpdate",
                    function( ... )
			Astrolabe:OnUpdate(this, arg1);
                    end
    );
    frame:SetScript("OnShow",
                    function( ... )
			Astrolabe:OnShow(this);
                    end
    );

    setmetatable(Astrolabe.MinimapIcons, MinimapIconsMetatable)

    -- register this library with AstrolabeMapMonitor
    local AstrolabeMapMonitor = DongleStub("AstrolabeMapMonitor");
    AstrolabeMapMonitor:RegisterAstrolabeLibrary(Astrolabe, LIBRARY_VERSION_MAJOR);
end

DongleStub:Register(Astrolabe, activate)


--------------------------------------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------------------------------------

-- diameter of the Minimap in game yards at
-- the various possible zoom levels
MinimapSize = {
    indoor = {
        [0] = 300, -- scale
        [1] = 240, -- 1.25
        [2] = 180, -- 5/3
        [3] = 120, -- 2.5
        [4] = 80,  -- 3.75
        [5] = 50,  -- 6
    },
    outdoor = {
        [0] = 466 + 2/3, -- scale
        [1] = 400,       -- 7/6
        [2] = 333 + 1/3, -- 1.4
        [3] = 266 + 2/6, -- 1.75
        [4] = 200,       -- 7/3
        [5] = 133 + 1/3, -- 3.5
    },
}

ValidMinimapShapes = {
    -- { upper-left, lower-left, upper-right, lower-right }
    ["SQUARE"]                = { false, false, false, false },
    ["CORNER-TOPLEFT"]        = { true,  false, false, false },
    ["CORNER-TOPRIGHT"]       = { false, false, true,  false },
    ["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
    ["CORNER-BOTTOMRIGHT"]    = { false, false, false, true },
    ["SIDE-LEFT"]             = { true,  true,  false, false },
    ["SIDE-RIGHT"]            = { false, false, true,  true },
    ["SIDE-TOP"]              = { true,  false, true,  false },
    ["SIDE-BOTTOM"]           = { false, true,  false, true },
    ["TRICORNER-TOPLEFT"]     = { true,  true,  true,  false },
    ["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true },
    ["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { false, true,  true,  true },
}

-- distances across and offsets of the world maps
-- in game yards
WorldMapSize = {
    -- World Map of Azeroth
    [0] = {
        parentContinent = 0,
        height = 29687.90575403711,
        width = 44531.82907938571,
    },
    -- Kalimdor
    { --[1]
        parentContinent = 0,
        height = 24532.39670836129,
        width = 36798.56388065484,
        xOffset = -8310.762035321373,
        yOffset = 1815.149000954498,
        zoneData = {
            Ashenvale = {
                height = 3843.627450950699,
                width = 5766.471113365881,
                xOffset = 15366.08027406009,
                yOffset = 8126.716152815561,
            },
            Aszhara = {
                height = 3381.153764845262,
                width = 5070.669448432522,
                xOffset = 20342.99178351035,
                yOffset = 7457.974565554941,
            },
            Barrens = {
                height = 6756.028094350823,
                width = 10132.98626357964,
                xOffset = 14443.19633043607,
                yOffset = 11187.03406016663,
            },
            Darkshore = {
                height = 4366.52571734943,
                width = 6549.780280774227,
                xOffset = 14124.4534386827,
                yOffset = 4466.419105960455,
            },
            Darnassus = {
                height = 705.7102838625474,
                width = 1058.300884213672,
                xOffset = 14127.75729935019,
                yOffset = 2561.497770365213,
            },
            Desolace = {
                height = 2997.808472061639,
                width = 4495.726850591814,
                xOffset = 12832.80723200791,
                yOffset = 12347.420176847,
            },
            Durotar = {
                height = 3524.884894927208,
                width = 5287.285801274457,
                xOffset = 19028.47465485265,
                yOffset = 10991.20642822035,
            },
            Dustwallow = {
                height = 3499.922239823486,
                width = 5249.824712249077,
                xOffset = 18040.98829886713,
                yOffset = 14832.74650226312,
            },
            Felwood = {
                height = 3833.206376333298,
                width = 5749.8046476606,
                xOffset = 15424.4116748014,
                yOffset = 5666.381311442202,
            },
            Feralas = {
                height = 4633.182754891688,
                width = 6949.760203962193,
                xOffset = 11624.54217828119,
                yOffset = 15166.06954533647,
            },
            Moonglade = {
                height = 1539.548478194226,
                width = 2308.253559286662,
                xOffset = 18447.22668103606,
                yOffset = 4308.084192710569,
            },
            Mulgore = {
                height = 3424.88834791471,
                width = 5137.32138887616,
                xOffset = 15018.17633401988,
                yOffset = 13072.38917227894,
            },
            Ogrimmar = {
                height = 935.3750279485016,
                width = 1402.563051365538,
                xOffset = 20746.49533101771,
                yOffset = 10525.68532631853,
            },
            Silithus = {
                height = 2322.839629859208,
                width = 3483.224287356748,
                xOffset = 14528.60591761034,
                yOffset = 18757.61998086822,
            },
            StonetalonMountains = {
                height = 3256.141917023559,
                width = 4883.173287670144,
                xOffset = 13820.29750397374,
                yOffset = 9882.909063258192,
            },
            Tanaris = {
                height = 4599.847335452488,
                width = 6899.765399158026,
                xOffset = 17284.7655865671,
                yOffset = 18674.28905369955,
            },
            Teldrassil = {
                height = 3393.632169760774,
                width = 5091.467863261982,
                xOffset = 13251.58449896318,
                yOffset = 968.6223632831094,
            },
            ThousandNeedles = {
                height = 2933.241274801781,
                width = 4399.86408093722,
                xOffset = 17499.32929341832,
                yOffset = 16766.0151133423,
            },
            ThunderBluff = {
                height = 695.8116150081206,
                width = 1043.762849319158,
                xOffset = 16549.32009877855,
                yOffset = 13649.45129927044,
            },
            UngoroCrater = {
                height = 2466.588521980952,
                width = 3699.872808671186,
                xOffset = 16532.70803775362,
                yOffset = 18765.95157787033,
            },
            Winterspring = {
                height = 4733.190938744951,
                width = 7099.756078049357,
                xOffset = 17382.67868933954,
                yOffset = 4266.421320915686,
            },
        },
    },
    -- Eastern Kingdoms
    { --[2]
        parentContinent = 0,
        height = 25098.84390074281,
        width = 37649.15159852673,
        xOffset = 15525.32200715066,
        yOffset = 672.3934326738229,
        zoneData = {
            Alterac = {
                height = 1866.508741236576,
                width = 2799.820894040741,
                xOffset = 16267.51182664554,
                yOffset = 7693.598754637632,
            },
            Arathi = {
                height = 2399.784956908336,
                width = 3599.78645678886,
                xOffset = 17917.40598190062,
                yOffset = 9326.804744097401,
            },
            Badlands = {
                height = 1658.195027852759,
                width = 2487.343589680943,
                xOffset = 19129.83542887301,
                yOffset = 15082.55526717644,
            },
            BlastedLands = {
                height = 2233.146573433955,
                width = 3349.808966078055,
                xOffset = 18292.37876312771,
                yOffset = 19759.24272564734,
            },
            BurningSteppes = {
                height = 1951.911155356982,
                width = 2928.988452241535,
                xOffset = 17317.44291506163,
                yOffset = 16224.12640057407,
            },
            DeadwindPass = {
                height = 1666.528298197048,
                width = 2499.848163715574,
                xOffset = 17884.07519016362,
                yOffset = 19059.30117481421,
            },
            DunMorogh = {
                height = 3283.064682642022,
                width = 4924.664537147015,
                xOffset = 15248.84370721237,
                yOffset = 13070.22369811241,
            },
            Duskwood = {
                height = 1799.84874595001,
                width = 2699.837284973949,
                xOffset = 16217.51007473156,
                yOffset = 18909.31475362112,
            },
            EasternPlaguelands = {
                height = 2581.024511737268,
                width = 3870.596078314358,
                xOffset = 19236.07699848783,
                yOffset = 5393.799386328108,
            },
            Elwynn = {
                height = 2314.38613060264,
                width = 3470.62593362794,
                xOffset = 15515.46777926721,
                yOffset = 17132.38313881497,
            },
            Hilsbrad = {
                height = 2133.153088717906,
                width = 3199.802496078764,
                xOffset = 15984.19170342619,
                yOffset = 8793.505832296016,
            },
            Hinterlands = {
                height = 2566.448674847725,
                width = 3849.77134323942,
                xOffset = 18625.69536724846,
                yOffset = 7726.929725104341,
            },
            Ironforge = {
                height = 527.5626661642974,
                width = 790.5745810546713,
                xOffset = 17764.34206355846,
                yOffset = 13762.32403658607,
            },
            LochModan = {
                height = 1839.436067817912,
                width = 2758.158752877019,
                xOffset = 19044.42466174755,
                yOffset = 13680.58746225864,
            },
            Redridge = {
                height = 1447.811817383856,
                width = 2170.704876735185,
                xOffset = 18621.52904187992,
                yOffset = 17767.73128664901,
            },
            SearingGorge = {
                height = 1487.371558351205,
                width = 2231.119799153945,
                xOffset = 17373.68649889545,
                yOffset = 15292.9566475719,
            },
            Silverpine = {
                height = 2799.763349841058,
                width = 4199.739879721531,
                xOffset = 13601.00798540562,
                yOffset = 7526.945768538925,
            },
            Stormwind = {
                height = 896.2784132739149,
                width = 1344.138055148283,
                xOffset = 15669.93346231942,
                yOffset = 17471.62163820253,
            },
            Stranglethorn = {
                height = 4253.796738213571,
                width = 6380.866711475876,
                xOffset = 14830.09122763351,
                yOffset = 20361.27611706414,
            },
            SwampOfSorrows = {
                height = 1529.04028583782,
                width = 2293.606089974149,
                xOffset = 19273.57577346738,
                yOffset = 18813.48829580375,
            },
            Tirisfal = {
                height = 3012.244783356771,
                width = 4518.469744413802,
                xOffset = 14017.64852522109,
                yOffset = 5356.296558943325,
            },
            Undercity = {
                height = 640.0492683780853,
                width = 959.3140238076666,
                xOffset = 16177.65630384973,
                yOffset = 7315.685533181013,
            },
            WesternPlaguelands = {
                height = 2866.410476553068,
                width = 4299.7374000546,
                xOffset = 16634.14908983872,
                yOffset = 5827.092974820261,
            },
            Westfall = {
                height = 2333.132106534445,
                width = 3499.786489780177,
                xOffset = 14034.31142029944,
                yOffset = 18592.67765947875,
            },
            Wetlands = {
                height = 2756.004767589141,
                width = 4135.166184805389,
                xOffset = 17440.35277057554,
                yOffset = 11341.20698670613,
            },
        },
    },
}

local zeroData;
zeroData = { xOffset = 0, height = 0, yOffset = 0, width = 0, __index = function() return zeroData end };
setmetatable(zeroData, zeroData);
setmetatable(WorldMapSize, zeroData);

for continent, zones in pairs(Astrolabe.ContinentList) do
    local mapData = WorldMapSize[continent];
    for index, mapName in pairs(zones) do
        if not ( mapData.zoneData[mapName] ) then
            --WE HAVE A PROBLEM!!!
            ChatFrame1:AddMessage("Astrolabe is missing data for "..select(index, GetMapZones(continent))..".");
            mapData.zoneData[mapName] = zeroData;
        end
        mapData[index] = mapData.zoneData[mapName];
        mapData.zoneData[mapName] = nil;
    end
end


-- do a full update of the Minimap positioning system
-- Astrolabe:CalculateMinimapIconPositions();
