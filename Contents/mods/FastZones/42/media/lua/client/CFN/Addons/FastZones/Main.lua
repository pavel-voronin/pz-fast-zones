require("CFN/Home/Main")
require("CFN/Addons/FastZones/Options")

-- Update UI panels
local function refreshHomeInventoryUI()
    if CFN and CFN.Home and CFN.Home.Instance then
        local mainPanel = CFN.Home.Instance

        if mainPanel.reloadItems then
            mainPanel:reloadItems()
        end

        if mainPanel.zonePanel and mainPanel.zonePanel:getIsVisible() and mainPanel.zonePanel.reloadZones then
            mainPanel.zonePanel:reloadZones()
        end
    end
end

-- Get unique building name
local function getBuildingName(building)
    local def = building:getDef()
    if def and def:getX() and def:getY() then
        return "Building_" .. def:getX() .. "_" .. def:getY()
    else
        return "Building_ID_" .. building:getID()
    end
end

-- Rectangle operations for zone calculation
local function rectanglesIntersect(rect1, rect2)
    return rect1.x < rect2.x + rect2.w and rect1.x + rect1.w > rect2.x and rect1.y < rect2.y + rect2.h and rect1.y +
               rect1.h > rect2.y and rect1.z == rect2.z
end

local function subtractRectangle(sourceRect, subtractRect)
    -- If no intersection, return original rectangle
    if not rectanglesIntersect(sourceRect, subtractRect) then
        return {sourceRect}
    end

    -- Calculate intersection bounds
    local intersectX1 = math.max(sourceRect.x, subtractRect.x)
    local intersectY1 = math.max(sourceRect.y, subtractRect.y)
    local intersectX2 = math.min(sourceRect.x + sourceRect.w, subtractRect.x + subtractRect.w)
    local intersectY2 = math.min(sourceRect.y + sourceRect.h, subtractRect.y + subtractRect.h)

    -- If intersection covers entire source rectangle, return empty
    if intersectX1 <= sourceRect.x and intersectY1 <= sourceRect.y and intersectX2 >= sourceRect.x + sourceRect.w and
        intersectY2 >= sourceRect.y + sourceRect.h then
        return {}
    end

    local result = {}

    -- Top rectangle (above intersection)
    if intersectY1 > sourceRect.y then
        table.insert(result, {
            x = sourceRect.x,
            y = sourceRect.y,
            w = sourceRect.w,
            h = intersectY1 - sourceRect.y,
            z = sourceRect.z
        })
    end

    -- Bottom rectangle (below intersection)
    if intersectY2 < sourceRect.y + sourceRect.h then
        table.insert(result, {
            x = sourceRect.x,
            y = intersectY2,
            w = sourceRect.w,
            h = sourceRect.y + sourceRect.h - intersectY2,
            z = sourceRect.z
        })
    end

    -- Left rectangle (left of intersection)
    if intersectX1 > sourceRect.x then
        table.insert(result, {
            x = sourceRect.x,
            y = intersectY1,
            w = intersectX1 - sourceRect.x,
            h = intersectY2 - intersectY1,
            z = sourceRect.z
        })
    end

    -- Right rectangle (right of intersection)
    if intersectX2 < sourceRect.x + sourceRect.w then
        table.insert(result, {
            x = intersectX2,
            y = intersectY1,
            w = sourceRect.x + sourceRect.w - intersectX2,
            h = intersectY2 - intersectY1,
            z = sourceRect.z
        })
    end

    return result
end

-- Calculate non-overlapping zones for a room
local function calculateNonOverlappingZones(roomDef)
    CFN.Home.Manager.load()
    local existingZones = CFN.Home.Manager.getAllZones()

    -- Start with the room rectangle (without subtracting 1 - we'll do it consistently)
    local roomRect = {
        x = roomDef:getX(),
        y = roomDef:getY(),
        w = roomDef:getW(),
        h = roomDef:getH(),
        z = roomDef:getZ()
    }

    local remainingRects = {roomRect}

    -- Convert existing zones to have consistent w/h (add 1 back if they were stored with -1)
    for _, zone in ipairs(existingZones) do
        local zoneRect = {
            x = zone.x,
            y = zone.y,
            w = zone.w + 1, -- Add 1 back to match room coordinates
            h = zone.h + 1, -- Add 1 back to match room coordinates
            z = zone.z
        }

        local newRemainingRects = {}

        for _, rect in ipairs(remainingRects) do
            local subtractedRects = subtractRectangle(rect, zoneRect)
            for _, subtractedRect in ipairs(subtractedRects) do
                table.insert(newRemainingRects, subtractedRect)
            end
        end

        remainingRects = newRemainingRects

        if #remainingRects == 0 then
            break
        end
    end

    return remainingRects
end

-- Add zone from rectangle to CFN
local function addZoneFromRectToCFN(zoneName, rect)
    CFN.Home.Manager.load()

    local zone = {
        name = zoneName,
        x = rect.x,
        y = rect.y,
        z = rect.z,
        w = rect.w - 1, -- Subtract 1 for storage consistency
        h = rect.h - 1 -- Subtract 1 for storage consistency
    }

    CFN.Home.Manager.addZone(zone)
    refreshHomeInventoryUI()
end

-- Remove zone from CFN
local function removeZoneFromCFN(zone)
    CFN.Home.Manager.removeZone(zone)
    refreshHomeInventoryUI()
end

-- Collect ALL rooms from building (not random!)
local function collectBuildingRooms(building)
    local allRooms = {}

    -- Get BuildingDef from IsoBuilding
    local buildingDef = building:getDef()
    if not buildingDef then
        return allRooms
    end

    -- Get rooms from BuildingDef
    local roomDefs = buildingDef:getRooms()
    if not roomDefs then
        return allRooms
    end

    local roomsCount = roomDefs:size()

    -- Get ALL rooms from BuildingDef.rooms ArrayList
    for i = 0, roomsCount - 1 do
        local roomDef = roomDefs:get(i) -- Get RoomDef from ArrayList
        if roomDef then
            local room = roomDef:getIsoRoom() -- Get IsoRoom from RoomDef
            if room then
                local roomKey = roomDef:getX() .. "_" .. roomDef:getY() .. "_" .. roomDef:getZ()
                table.insert(allRooms, room)
            end
        end
    end

    return allRooms
end

-- Check if building has any zones AND collect only building zones to remove
local function checkAndCollectBuildingZones(buildingRooms, buildingName)
    local zonesToRemove = {}

    CFN.Home.Manager.load()
    local allZones = CFN.Home.Manager.getAllZones()

    -- Check all zones - only remove zones that belong to this building (by name)
    for _, zone in ipairs(allZones) do
        local zoneName = zone.name or ""

        -- Check if this zone belongs to this building by name pattern
        if zoneName == buildingName or string.find(zoneName, "^" .. buildingName .. "_") then
            table.insert(zonesToRemove, zone)
        end
    end

    return #zonesToRemove > 0, zonesToRemove
end

-- Remove building zones from collected list
local function removeBuildingZones(zonesToRemove)
    local removedCount = 0

    -- Handle zones to completely remove
    for _, zone in ipairs(zonesToRemove) do

        -- Check if zone still exists before removing
        local stillExists = false
        local currentZones = CFN.Home.Manager.getAllZones()
        for _, currentZone in ipairs(currentZones) do
            if currentZone.name == zone.name and currentZone.x == zone.x and currentZone.y == zone.y and currentZone.z ==
                zone.z then
                stillExists = true
                break
            end
        end

        if stillExists then
            CFN.Home.Manager.removeZone(zone)
            removedCount = removedCount + 1
        end
    end

    if removedCount > 0 then
        refreshHomeInventoryUI()
    end

    return removedCount
end

-- Add all building rooms as zones
local function addBuildingZones(buildingRooms, buildingName)
    local addedCount = 0

    for _, room in pairs(buildingRooms) do
        local roomDef = room:getRoomDef()
        if roomDef then
            -- Calculate non-overlapping rectangles for this room
            local nonOverlappingRects = calculateNonOverlappingZones(roomDef)

            if #nonOverlappingRects > 0 then
                -- For building-wide addition, use only building name (no room suffix)
                local zoneName = buildingName

                -- Add each non-overlapping rectangle as a separate zone
                for _, rect in ipairs(nonOverlappingRects) do
                    addZoneFromRectToCFN(zoneName, rect)
                    addedCount = addedCount + 1
                end
            end
        end
    end

    return addedCount
end

-- Find zone by player position
local function findZoneByPlayerPosition(playerX, playerY, playerZ)
    CFN.Home.Manager.load()
    local zones = CFN.Home.Manager.getAllZones()

    for _, zone in ipairs(zones) do
        -- Check if player position is within zone bounds
        if playerX >= zone.x and playerX <= zone.x + zone.w and playerY >= zone.y and playerY <= zone.y + zone.h and
            playerZ == zone.z then
            return zone
        end
    end

    return nil
end

-- Add single room as zone (with toggle functionality)
local function addRoomToCFNZones(room)
    local roomDef = room:getRoomDef()
    if not roomDef then
        return
    end

    local building = room:getBuilding()
    if not building then
        return
    end

    -- Get player position
    local player = getPlayer()
    local playerX = math.floor(player:getX())
    local playerY = math.floor(player:getY())
    local playerZ = math.floor(player:getZ())

    -- Check if there's any zone at player position (not just current room zone)
    local existingZone = findZoneByPlayerPosition(playerX, playerY, playerZ)

    if existingZone then
        removeZoneFromCFN(existingZone)
    else

        -- Calculate non-overlapping rectangles for this room
        local nonOverlappingRects = calculateNonOverlappingZones(roomDef)

        if #nonOverlappingRects == 0 then
            return
        end

        local buildingName = getBuildingName(building)
        local rawName = room:getName()
        local roomName = (rawName ~= nil and rawName ~= "") and rawName or
                             ("Room_" .. roomDef:getX() .. "_" .. roomDef:getY())

        -- Add each non-overlapping rectangle as a separate zone
        for _, rect in ipairs(nonOverlappingRects) do
            local zoneName = buildingName .. "_" .. roomName -- Same name for all parts

            addZoneFromRectToCFN(zoneName, rect)
        end
    end
end

-- Add entire building as zones (with smart toggle)
local function addBuildingToCFNZones(building)
    local buildingName = getBuildingName(building)
    local buildingRooms = collectBuildingRooms(building)

    -- Check for existing building zones (by name, not intersection)
    local hasZones, zonesToRemove = checkAndCollectBuildingZones(buildingRooms, buildingName)

    if hasZones then
        removeBuildingZones(zonesToRemove)
    else
        addBuildingZones(buildingRooms, buildingName)
    end
end

-- Key press handler
local function onKeyPressed(key)
    local player = getPlayer()
    if not player then
        return
    end

    local square = player:getCurrentSquare()
    if not square then
        return
    end

    -- Get keys from options
    local roomKey = CFN.Home.Options.RoomToZoneKey()
    local buildingKey = CFN.Home.Options.BuildingToZoneKey()

    if key == buildingKey then
        -- Add/remove entire building (only works inside buildings)
        local room = square:getRoom()
        if not room then
            return
        end

        local building = room:getBuilding()
        if not building then
            return
        end

        addBuildingToCFNZones(building)
    elseif key == roomKey then
        -- Add/remove zone at current position (works with zones OR rooms)
        local room = square:getRoom()

        -- Get player position for zone check
        local playerX = math.floor(player:getX())
        local playerY = math.floor(player:getY())
        local playerZ = math.floor(player:getZ())

        -- Check if there's a zone at player position
        local existingZone = findZoneByPlayerPosition(playerX, playerY, playerZ)

        if existingZone then
            -- Found zone at position - remove it
            removeZoneFromCFN(existingZone)
        elseif room then
            -- No zone but in a room - add room as zone
            addRoomToCFNZones(room)
        else
            -- Neither zone nor room at position - do nothing
        end
    end
end

if CFN and CFN.Home and CFN.Home.Options and CFN.Home.Manager then
    Events.OnKeyPressed.Add(onKeyPressed)
end
