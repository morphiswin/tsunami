--[[
    VHS Happiness

    Watching a VHS tape on a TV, or listening to a music CD, lowers
    unhappiness the same way reading a book or comic does. Each line of the
    tape or CD that plays while you're watching or listening gives its share,
    so getting through the whole thing gives the full amount.

    Each tape and CD cheers a character up only once, ever, so new ones are
    worth hunting for. Skill tapes (ones that teach a skill or recipe) give no
    happiness at all; they only give the game's normal skill XP. Boredom is
    left to the game.

    Nothing here is a fixed list of tapes: tapes and CDs added by other mods
    work the same way, including ones with their own category names.

    Mood values use the same 0-100 scale as the UnhappyChange field in the
    game's literature item scripts:
        ComicBook   UnhappyChange = -20
        Book        UnhappyChange = -40

    Works on Build 41 and Build 42 (including 42.13+, where unhappiness moved
    from BodyDamage to Stats/CharacterStat).
]]

VHSHappiness = {}

VHSHappiness.Config = {
    -- Total unhappiness removed by getting through a whole tape or CD.
    RetailVHSTotal = 40, -- movies / TV series tapes: same as reading a book
    HomeVHSTotal = 20,   -- home video tapes: same as reading a comic book
    CDTotal = 20,        -- music CDs: same as reading a comic book

    -- How far (in tiles, same floor) you can be from a TV or radio and still
    -- count as watching or listening. A CD player you're carrying always
    -- counts.
    MaxDistance = 8,

    -- Require an unobstructed line of sight to the TV or radio (walls block
    -- it).
    RequireLineOfSight = true,

    -- Show a green "Unhappiness" arrow with every line that cheers you up,
    -- like the game's own "Boredom" arrow.
    ShowHaloText = true,
    HaloText = "Unhappiness",

    -- Line codes that only change how the character feels. A tape with any
    -- other code (CRP+1, RCP=Make Fishing Rod, codes for skills added by
    -- other mods, ...) counts as a skill tape and gives no happiness. If a
    -- mod's movie or music gives no happiness, add the codes it uses here.
    MoodCodes = {
        "BOR", -- boredom
        "STS", -- stress
        "FAT", -- fatigue
        "PAN", -- panic
        "ANG", -- anger
        "END", -- endurance
        "HUN", -- hunger
        "THI", -- thirst
        "MOR", -- morale
        "FEA", -- fear
        "SAN", -- sanity
        "SIC", -- sickness
        "PAI", -- pain
        "DRU", -- drunkenness
        "UHP", -- unhappiness
        "UNH", -- unhappiness
    },
}

local Config = VHSHappiness.Config

local moodCodes = {}
for _, code in ipairs(Config.MoodCodes) do
    moodCodes[code] = true
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

    -- Build 41 to 42.12: unhappiness lives on BodyDamage.
    local bodyDamage = player:getBodyDamage()
    local current = bodyDamage:getUnhappynessLevel()
    local new = math.max(0, current - amount)
    bodyDamage:setUnhappynessLevel(new)
    return current - new
end

-----------------------------------------------------------------------------
-- Tapes and CDs
-----------------------------------------------------------------------------

-- Uses the game's own media type to tell CDs from tapes, so CDs from other
-- mods count even if they use their own category name. The game's tape
-- categories are "Retail-VHS" and "Home-VHS"; a modded tape counts as a home
-- video if its category mentions "home".
function VHSHappiness.getMediaTotal(media)
    if media:getMediaType() == RecordedMedia.getMediaTypeForCategory("CDs") then
        return Config.CDTotal
    end
    local category = string.lower(tostring(media:getCategory() or ""))
    if string.find(category, "home", 1, true) then
        return Config.HomeVHSTotal
    end
    return Config.RetailVHSTotal
end

local function mediaHasLine(media, guid)
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
        if first and not moodCodes[string.upper(string.sub(codes, first, last))] then
            return true
        end
        pos = comma + 1
    end
    return false
end

local skillMedia = {}

-- Whether any line of the tape teaches a skill or recipe. Checked once per
-- tape, so a skill tape gives no happiness even before its first lesson.
function VHSHappiness.isSkillMedia(media)
    local id = media:getId()
    if skillMedia[id] == nil then
        skillMedia[id] = false
        for i = 0, media:getLineCount() - 1 do
            local line = media:getLine(i)
            local codes = line and line:getCodes()
            if codes and teachesSkill(codes) then
                skillMedia[id] = true
                break
            end
        end
    end
    return skillMedia[id]
end

-- The game passes the device that showed the line; if it ever doesn't, find
-- one with a tape or CD on that square instead.
local function getDeviceData(device, square)
    if device then
        return device:getDeviceData()
    end
    if not square then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if instanceof(obj, "IsoWaveSignal") then
            local deviceData = obj:getDeviceData()
            if deviceData and deviceData:getMediaData() then
                return deviceData
            end
        end
    end
    return nil
end

-----------------------------------------------------------------------------
-- Watching and listening
-----------------------------------------------------------------------------

-- Whether the device is an item (like a CD player) in the player's
-- inventory, including inside a bag they carry.
local function isCarrying(player, deviceData)
    if not deviceData:isInventoryDevice() then return false end
    local item = deviceData:getParent()
    return item ~= nil and item:getOutermostContainer() == player:getInventory()
end

-- `square` is where the line was shown: the TV, radio or vehicle, or the
-- player carrying a CD player.
function VHSHappiness.isWatchingOrListening(player, square, deviceData)
    if player:isDead() or player:isAsleep() then return false end
    if isCarrying(player, deviceData) then return true end
    if not square then return false end

    local playerSquare = player:getCurrentSquare()
    if not playerSquare or playerSquare:getZ() ~= square:getZ() then return false end

    local dx = playerSquare:getX() - square:getX()
    local dy = playerSquare:getY() - square:getY()
    if dx * dx + dy * dy > Config.MaxDistance * Config.MaxDistance then return false end

    return not Config.RequireLineOfSight or square:isCouldSee(player:getPlayerNum())
end

-----------------------------------------------------------------------------
-- Per-tape/CD progress (saved with the character, never reset)
-----------------------------------------------------------------------------

-- Happiness each tape or CD has given this character so far, by its id.
local function getProgress(player)
    local modData = player:getModData()
    modData.VHSHappiness = modData.VHSHappiness or {}
    return modData.VHSHappiness
end

local function getGiven(progress, mediaId)
    local given = progress[mediaId] or 0
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

local function creditLine(player, media)
    local progress = getProgress(player)
    local given = getGiven(progress, media.id)
    -- Capped at the total, so rewinds and replays don't add up.
    local amount = math.min(media.total / media.lineCount, media.total - given)
    -- Ignore rounding leftovers once the whole thing has been counted.
    if amount <= media.total * 1e-6 then return end
    progress[media.id] = given + amount

    if VHSHappiness.reduceUnhappiness(player, amount) > 0 then
        showHalo(player)
    end
end

-- Fires for every line a radio or TV shows, including each line of a tape
-- or CD.
function VHSHappiness.onDeviceText(guid, codes, x, y, z, text, device)
    local square = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    local deviceData = getDeviceData(device, square)
    if not deviceData then return end
    local media = deviceData:getMediaData()
    if not media or media:getLineCount() <= 0 then return end
    -- Only lines from the tape or CD count, not radio or TV broadcasts.
    if not deviceData:isPlayingMedia() and not mediaHasLine(media, guid) then return end
    if VHSHappiness.isSkillMedia(media) then return end

    local info = {
        id = media:getId(),
        total = VHSHappiness.getMediaTotal(media),
        lineCount = media:getLineCount(),
    }
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player and VHSHappiness.isWatchingOrListening(player, square, deviceData) then
            creditLine(player, info)
        end
    end
end

Events.OnDeviceText.Add(VHSHappiness.onDeviceText)
