--[[
    VHS Happiness

    Watching a VHS tape on a TV lowers unhappiness, the same way reading a
    book or comic does. Each line of the tape that plays while you're watching
    gives its share, so watching a whole tape gives the full amount.

    Each tape cheers a character up only once, ever, so new tapes are worth
    hunting for. Skill tapes (ones that teach a skill or recipe) give no
    happiness at all; they only give the game's normal skill XP.

    Mood values use the same 0-100 scale as the UnhappyChange field in the
    game's literature item scripts:
        ComicBook   UnhappyChange = -20
        Book        UnhappyChange = -40

    Works on Build 41 and Build 42 (including 42.13+, where unhappiness moved
    from BodyDamage to Stats/CharacterStat).
]]

VHSHappiness = {}

VHSHappiness.Config = {
    -- Total unhappiness removed by watching a whole tape.
    RetailVHSTotal = 40, -- movies / TV series tapes: same as reading a book
    HomeVHSTotal = 20,   -- home video tapes: same as reading a comic book

    -- How far (in tiles, same floor) you can be from the TV and still count
    -- as watching it.
    MaxDistance = 8,

    -- Require an unobstructed line of sight to the TV (walls block it).
    RequireLineOfSight = true,

    -- Show a green "Unhappiness" arrow when a tape starts cheering you up.
    ShowHaloText = true,
    HaloText = "Unhappiness",
}

local Config = VHSHappiness.Config

-- Codes the game's tapes use for mood changes (boredom, stress, fatigue,
-- panic). Any other code on a tape, like CRP+1 or RCP=Make Fishing Rod,
-- means it teaches a skill or recipe.
local MOOD_CODES = { BOR = true, STS = true, FAT = true, PAN = true }

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

    -- Build 41 to 42.12: unhappiness lives on BodyDamage.
    local bodyDamage = player:getBodyDamage()
    local current = bodyDamage:getUnhappynessLevel()
    local new = math.max(0, current - amount)
    bodyDamage:setUnhappynessLevel(new)
    return current - new
end

-----------------------------------------------------------------------------
-- Tapes
-----------------------------------------------------------------------------

function VHSHappiness.getTapeTotal(category)
    if category and string.find(string.lower(tostring(category)), "home") then
        return Config.HomeVHSTotal
    end
    return Config.RetailVHSTotal
end

local function tapeHasLine(media, guid)
    if guid == nil then return false end
    for i = 0, media:getLineCount() - 1 do
        local line = media:getLine(i)
        if line and line:getTextGuid() == guid then
            return true
        end
    end
    return false
end

-- Whether a line's codes (e.g. "BOR-1,CRP+1") include anything but mood
-- changes. Each comma-separated code starts with its name.
local function teachesSkill(codes)
    local length = string.len(codes)
    local pos = 1
    while pos <= length do
        local comma = string.find(codes, ",", pos, true) or length + 1
        local first, last = string.find(codes, "%a+", pos)
        if first and not MOOD_CODES[string.upper(string.sub(codes, first, last))] then
            return true
        end
        pos = comma + 1
    end
    return false
end

local skillTapes = {}

-- Whether any line of the tape teaches a skill or recipe. Checked once per
-- tape, so a skill tape gives no happiness even before its first lesson.
function VHSHappiness.isSkillTape(media)
    local id = media:getId()
    if skillTapes[id] == nil then
        skillTapes[id] = false
        for i = 0, media:getLineCount() - 1 do
            local line = media:getLine(i)
            local codes = line and line:getCodes()
            if codes and teachesSkill(codes) then
                skillTapes[id] = true
                break
            end
        end
    end
    return skillTapes[id]
end

-- The game passes the device that showed the line; if it ever doesn't, find
-- the TV on that square instead.
local function getDeviceData(device, square)
    if device then
        return device:getDeviceData()
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if instanceof(obj, "IsoWaveSignal") then
            local deviceData = obj:getDeviceData()
            if deviceData and deviceData:getIsTelevision() then
                return deviceData
            end
        end
    end
    return nil
end

-----------------------------------------------------------------------------
-- Watching
-----------------------------------------------------------------------------

function VHSHappiness.isWatching(player, tvSquare)
    if player:isDead() or player:isAsleep() then return false end

    local square = player:getCurrentSquare()
    if not square or square:getZ() ~= tvSquare:getZ() then return false end

    local dx = square:getX() - tvSquare:getX()
    local dy = square:getY() - tvSquare:getY()
    if dx * dx + dy * dy > Config.MaxDistance * Config.MaxDistance then return false end

    return not Config.RequireLineOfSight or tvSquare:isCouldSee(player:getPlayerNum())
end

-----------------------------------------------------------------------------
-- Per-tape progress (saved with the character, never reset)
-----------------------------------------------------------------------------

-- Happiness each tape has given this character so far, by tape id.
local function getTapeProgress(player)
    local modData = player:getModData()
    modData.VHSHappiness = modData.VHSHappiness or {}
    return modData.VHSHappiness
end

local function getGiven(progress, tapeId)
    local given = progress[tapeId] or 0
    -- Earlier versions of the mod saved { start = ..., given = ... }.
    if type(given) == "table" then
        given = given.given or 0
    end
    return given
end

-----------------------------------------------------------------------------
-- Halo text
-----------------------------------------------------------------------------

local function showHalo(player)
    if not Config.ShowHaloText then return end
    -- Purely cosmetic, so never let it break the mood change.
    pcall(function()
        HaloTextHelper.addTextWithArrow(player, Config.HaloText, false, HaloTextHelper.getColorGreen())
    end)
end

-----------------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------------

-- Last tape that cheered up each local player, so the halo shows when a
-- viewing starts rather than on every line.
local lastTape = {}

local function creditLine(player, tape)
    local progress = getTapeProgress(player)
    local given = getGiven(progress, tape.id)
    -- Capped at the tape's total, so rewinds and rewatches don't add up.
    local amount = math.min(tape.total / tape.lineCount, tape.total - given)
    if amount <= 0 then return end
    progress[tape.id] = given + amount

    local removed = VHSHappiness.reduceUnhappiness(player, amount)
    local playerNum = player:getPlayerNum()
    if removed > 0 and (given == 0 or lastTape[playerNum] ~= tape.id) then
        showHalo(player)
    end
    lastTape[playerNum] = tape.id
end

-- Fires for every line a radio or TV shows, including each line of a tape.
function VHSHappiness.onDeviceText(guid, codes, x, y, z, text, device)
    local square = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    if not square then return end

    local deviceData = getDeviceData(device, square)
    if not deviceData or not deviceData:getIsTelevision() then return end
    local media = deviceData:getMediaData()
    if not media or media:getLineCount() <= 0 then return end
    -- Only lines from the tape count, not TV broadcasts.
    if not deviceData:isPlayingMedia() and not tapeHasLine(media, guid) then return end
    if VHSHappiness.isSkillTape(media) then return end

    local tape = {
        id = media:getId(),
        total = VHSHappiness.getTapeTotal(media:getCategory()),
        lineCount = media:getLineCount(),
    }
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player and VHSHappiness.isWatching(player, square) then
            creditLine(player, tape)
        end
    end
end

Events.OnDeviceText.Add(VHSHappiness.onDeviceText)
