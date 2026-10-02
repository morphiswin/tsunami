--[[
    VHS Happiness

    Watching a VHS tape on a TV lowers unhappiness, the same way reading a
    book or comic does. The bonus builds up while you watch, and each tape can
    only give its full amount once per CooldownHours, so swapping between the
    same few tapes doesn't stack forever.

    Mood values use the same 0-100 scale as the UnhappyChange field in the
    game's literature item scripts:
        ComicBook   UnhappyChange = -20
        Book        UnhappyChange = -40

    Works on Build 41 and Build 42 (including 42.13+, where unhappiness moved
    from BodyDamage to Stats/CharacterStat).
]]

-- Build 41 and Build 42 each have their own copy of this file. Only run once
-- if a game version ever loads both.
if VHSHappiness and VHSHappiness.loaded then return end

VHSHappiness = VHSHappiness or {}
VHSHappiness.loaded = true

VHSHappiness.Config = {
    -- Total unhappiness removed by watching one tape.
    RetailVHSTotal = 40, -- movies / TV series tapes: same as reading a book
    HomeVHSTotal = 20,   -- home video tapes: same as reading a comic book

    -- In-game minutes of watching needed to get a tape's full total. The bonus
    -- is spread evenly over this time, so stopping early gives part of it.
    MinutesForFullBonus = 45,

    -- In-game hours before the same tape can give its bonus again.
    CooldownHours = 24,

    -- How far (in tiles, same floor) you can be from the TV and still count
    -- as watching it.
    MaxDistance = 8,

    -- Require an unobstructed line of sight to the TV (walls block it).
    RequireLineOfSight = true,

    -- Show a green "Unhappiness" arrow when the bonus starts.
    ShowHaloText = true,
    HaloText = "Unhappiness",
}

local Config = VHSHappiness.Config

-- Calls a no-argument method, returning nil if the object or method is
-- missing on this game version.
local function safeCall(obj, method)
    if obj == nil then return nil end
    local ok, result = pcall(function() return obj[method](obj) end)
    if ok then return result end
    return nil
end

-----------------------------------------------------------------------------
-- Unhappiness
-----------------------------------------------------------------------------

-- Lowers unhappiness by `amount` on the 0-100 scale and returns how much it
-- actually went down (it can't go below zero).
function VHSHappiness.reduceUnhappiness(player, amount)
    -- Build 42.13+: unhappiness is a CharacterStat on Stats.
    if CharacterStat and CharacterStat.UNHAPPINESS then
        local stat = CharacterStat.UNHAPPINESS
        local stats = player:getStats()
        local scale = stat:getMaximumValue() / 100
        local current = stats:get(stat)
        local new = math.max(stat:getMinimumValue(), current - amount * scale)
        stats:set(stat, new)
        return (current - new) / scale
    end

    -- Build 41 / early Build 42: unhappiness lives on BodyDamage.
    local bodyDamage = player:getBodyDamage()
    local current = bodyDamage:getUnhappynessLevel()
    local new = math.max(0, current - amount)
    bodyDamage:setUnhappynessLevel(new)
    return current - new
end

-----------------------------------------------------------------------------
-- Finding a TV that's playing a tape
-----------------------------------------------------------------------------

local function getMediaData(deviceData)
    local media = safeCall(deviceData, "getMediaData")
    if media then return media end

    -- Older builds: look the tape up by its index.
    local index = safeCall(deviceData, "getMediaIndex")
    if index == nil or index < 0 then return nil end
    local radio = getZomboidRadio and getZomboidRadio()
    local recorded = safeCall(radio, "getRecordedMedia")
    if not recorded then return nil end
    local ok, result = pcall(function() return recorded:getMediaDataFromIndex(index) end)
    if ok then return result end
    return nil
end

function VHSHappiness.getTapeTotal(category)
    if category and string.find(string.lower(tostring(category)), "home") then
        return Config.HomeVHSTotal
    end
    return Config.RetailVHSTotal
end

-- Returns { id, total } for the tape this device is playing, or nil if it
-- isn't a TV playing a tape. TVs only accept VHS tapes.
function VHSHappiness.getPlayingTape(deviceData)
    if not deviceData then return nil end
    if not safeCall(deviceData, "getIsTelevision") then return nil end
    if not safeCall(deviceData, "getIsTurnedOn") then return nil end
    if not safeCall(deviceData, "isPlayingMedia") then return nil end

    local media = getMediaData(deviceData)
    local id = safeCall(media, "getId")
    if id == nil then
        id = "index:" .. tostring(safeCall(deviceData, "getMediaIndex"))
    end
    return {
        id = tostring(id),
        total = VHSHappiness.getTapeTotal(safeCall(media, "getCategory")),
    }
end

local function canSee(square, playerNum)
    if not Config.RequireLineOfSight then return true end
    local ok, result = pcall(function() return square:isCouldSee(playerNum) end)
    -- If the check isn't available, don't block the bonus over it.
    if not ok then return true end
    return result == true
end

-- Returns the tape the player is currently watching, or nil.
function VHSHappiness.findWatchedTape(player)
    local square = player:getCurrentSquare()
    if not square then return nil end

    local cell = getCell()
    local px, py, pz = square:getX(), square:getY(), square:getZ()
    local maxDist = Config.MaxDistance
    local radius = math.ceil(maxDist)
    local playerNum = player:getPlayerNum()

    for x = px - radius, px + radius do
        for y = py - radius, py + radius do
            local dx, dy = x - px, y - py
            if dx * dx + dy * dy <= maxDist * maxDist then
                local sq = cell:getGridSquare(x, y, pz)
                if sq then
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        if instanceof(obj, "IsoWaveSignal") then
                            local tape = VHSHappiness.getPlayingTape(obj:getDeviceData())
                            if tape and canSee(sq, playerNum) then
                                return tape
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-----------------------------------------------------------------------------
-- Per-tape progress (saved with the character)
-----------------------------------------------------------------------------

local function getTapeRecords(player)
    local modData = player:getModData()
    modData.VHSHappiness = modData.VHSHappiness or {}
    return modData.VHSHappiness
end

local function getTapeRecord(player, tapeId, now)
    local records = getTapeRecords(player)
    local record = records[tapeId]
    if not record or now - record.start >= Config.CooldownHours then
        record = { start = now, given = 0 }
        records[tapeId] = record
    end
    return record
end

-----------------------------------------------------------------------------
-- Halo text
-----------------------------------------------------------------------------

local function showHalo(player)
    if not Config.ShowHaloText or not HaloTextHelper then return end
    local ok, green = pcall(HaloTextHelper.getColorGreen)
    if not ok then return end
    -- Build 42.13+ takes a separator argument; earlier builds don't.
    if pcall(HaloTextHelper.addTextWithArrow, player, Config.HaloText, "[br/]", false, green) then return end
    pcall(HaloTextHelper.addTextWithArrow, player, Config.HaloText, false, green)
end

-----------------------------------------------------------------------------
-- Update loop
-----------------------------------------------------------------------------

-- Tape each local player was last rewarded for, so the halo only shows when
-- a viewing starts rather than every minute.
local currentTape = {}

function VHSHappiness.updatePlayer(player)
    local playerNum = player:getPlayerNum()
    if player:isDead() or player:isAsleep() then
        currentTape[playerNum] = nil
        return
    end

    local tape = VHSHappiness.findWatchedTape(player)
    if not tape then
        currentTape[playerNum] = nil
        return
    end

    local record = getTapeRecord(player, tape.id, getGameTime():getWorldAgeHours())
    local remaining = tape.total - record.given
    if remaining <= 0 then return end

    local perMinute = tape.total / math.max(1, Config.MinutesForFullBonus)
    local amount = math.min(remaining, perMinute)
    record.given = record.given + amount

    local removed = VHSHappiness.reduceUnhappiness(player, amount)
    if removed > 0 and currentTape[playerNum] ~= tape.id then
        currentTape[playerNum] = tape.id
        showHalo(player)
    end
end

function VHSHappiness.onEveryOneMinute()
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player then
            VHSHappiness.updatePlayer(player)
        end
    end
end

-- Drop records whose cooldown has ended so mod data doesn't grow forever.
function VHSHappiness.onEveryDays()
    local now = getGameTime():getWorldAgeHours()
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player then
            local records = getTapeRecords(player)
            for id, record in pairs(records) do
                if now - record.start >= Config.CooldownHours then
                    records[id] = nil
                end
            end
        end
    end
end

Events.EveryOneMinute.Add(VHSHappiness.onEveryOneMinute)
Events.EveryDays.Add(VHSHappiness.onEveryDays)
