-- Tests for VHSHappiness.lua against a mocked Project Zomboid API.
-- Run with: python3 tests/run_tests.py

local MOD_FILE = MOD_ROOT .. "/VHSHappiness/42/media/lua/client/VHSHappiness.lua"

-- The game's Lua engine (Kahlua) throws if a table changes while pairs() is
-- walking it. Plain Lua allows that, so make pairs() strict here too.
local rawPairs = pairs
pairs = function(t)
    local function size()
        local n = 0
        for _ in rawPairs(t) do n = n + 1 end
        return n
    end
    local startSize = size()
    local iter, state, key = rawPairs(t)
    return function(s, k)
        if size() ~= startSize then
            error("ConcurrentModificationException: table changed during pairs()", 2)
        end
        return iter(s, k)
    end, state, key
end

-----------------------------------------------------------------------------
-- Mock game world
-----------------------------------------------------------------------------

local world

local function javaList(items)
    return {
        size = function() return #items end,
        get = function(_, i) return items[i + 1] end,
    }
end

local function newSquare(x, y, z)
    local sq = { x = x, y = y, z = z, objects = {}, visible = true }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getObjects() return javaList(self.objects) end
    function sq:isCouldSee(playerNum) return self.visible end
    return sq
end

local function getSquare(x, y, z)
    local key = x .. "," .. y .. "," .. z
    if not world.squares[key] then
        world.squares[key] = newSquare(x, y, z)
    end
    return world.squares[key]
end

-- A tape with `lineCount` lines whose guids are "<id>:1", "<id>:2", ...
-- Every line has the code "BOR-1" (boredom), like most vanilla lines.
-- options.sameGuid maps line numbers to a shared guid, like the many vanilla
-- tapes that repeat a line such as "[music]"; options.codes maps line
-- numbers to other codes, e.g. { [12] = "CRP+1" } for a carpentry lesson.
local function newTape(id, category, lineCount, options)
    options = options or {}
    local guids, lines = {}, {}
    for i = 1, lineCount do
        local guid = (options.sameGuid and options.sameGuid[i]) or (id .. ":" .. i)
        local codes = (options.codes and options.codes[i]) or "BOR-1"
        guids[i] = guid
        lines[i] = {
            getTextGuid = function() return guid end,
            getCodes = function() return codes end,
        }
    end
    return {
        guids = guids,
        getId = function() return id end,
        getCategory = function() return category end,
        getLineCount = function() return lineCount end,
        getLine = function(_, i) return lines[i + 1] end, -- 0-based, like Java
    }
end

local function newDeviceData(media, parent, inInventory)
    local dd = { playing = media ~= nil, media = media, parent = parent, inInventory = inInventory }
    function dd:isPlayingMedia() return self.playing end
    function dd:getMediaData() return self.media end
    function dd:isInventoryDevice() return self.inInventory end
    function dd:getParent() return self.parent end
    return dd
end

-- Places a TV, radio or stereo at (x, y, z) playing `media` (a tape, a CD,
-- or nil for nothing). Returns the world object; its device data is in .dd
-- so tests can tweak it.
local function addDevice(x, y, z, media)
    local obj = { __class = "IsoWaveSignal", x = x, y = y, z = z }
    obj.dd = newDeviceData(media, obj, false)
    function obj:getDeviceData() return self.dd end
    table.insert(getSquare(x, y, z).objects, obj)
    return obj
end

local addTV = addDevice

-- A CD player item in `player`'s inventory (or a bag they carry). The game
-- reports where a line was shown from the device's position, which for a
-- carried item is normally the player's; `reportedAt` overrides it.
local function addCarriedCDPlayer(player, cd, reportedAt)
    local item = { inventory = player.inventory }
    function item:getOutermostContainer() return self.inventory end
    function item:getDeviceData() return self.dd end
    item.dd = newDeviceData(cd, item, true)
    local at = reportedAt or { player.x, player.y, player.z }
    item.x, item.y, item.z = at[1], at[2], at[3]
    return item
end

local function newPlayer(x, y, z, unhappiness)
    local p = {
        num = 0, x = x, y = y, z = z, dead = false, asleep = false,
        modData = {}, unhappiness = unhappiness, inventory = {},
    }
    function p:getInventory() return self.inventory end
    function p:getCurrentSquare() return getSquare(self.x, self.y, self.z) end
    function p:getPlayerNum() return self.num end
    function p:isDead() return self.dead end
    function p:isAsleep() return self.asleep end
    function p:getModData() return self.modData end
    function p:getBodyDamage()
        assert(CharacterStat == nil, "BodyDamage unhappiness doesn't exist on Build 42.13+")
        local player = self
        return {
            getUnhappynessLevel = function() return player.unhappiness end,
            setUnhappynessLevel = function(_, v) player.unhappiness = v end,
        }
    end
    function p:getStats()
        local player = self
        return {
            get = function(_, stat)
                assert(stat == CharacterStat.UNHAPPINESS)
                return player.unhappiness * stat.max / 100
            end,
            set = function(_, stat, v)
                assert(stat == CharacterStat.UNHAPPINESS)
                player.unhappiness = v * 100 / stat.max
                return true
            end,
        }
    end
    return p
end

-- Sets up the global API the mod uses and loads a fresh copy of the mod.
-- options.statMax: if set, mimic Build 42.13+ (CharacterStat with that max).
local function loadMod(options)
    options = options or {}
    world = { squares = {}, players = {}, halos = {}, handlers = {} }

    Events = {}
    for _, name in ipairs({ "OnDeviceText" }) do
        world.handlers[name] = {}
        Events[name] = {
            Add = function(fn) table.insert(world.handlers[name], fn) end,
        }
    end

    getCell = function()
        return {
            getGridSquare = function(_, x, y, z)
                assert(x == math.floor(x) and y == math.floor(y) and z == math.floor(z), "whole coords")
                return world.squares[x .. "," .. y .. "," .. z]
            end,
        }
    end
    getNumActivePlayers = function() return #world.players end
    getSpecificPlayer = function(i) return world.players[i + 1] end
    instanceof = function(obj, name) return type(obj) == "table" and obj.__class == name end

    if options.statMax then
        local stat = { max = options.statMax }
        function stat:getMaximumValue() return self.max end
        function stat:getMinimumValue() return 0 end
        CharacterStat = { UNHAPPINESS = stat }
    else
        CharacterStat = nil
    end

    -- Only the 4-argument addTextWithArrow exists on every game version.
    HaloTextHelper = {
        getColorGreen = function() return "green" end,
        addTextWithArrow = function(...)
            assert(select("#", ...) == 4, "expected the 4-argument addTextWithArrow")
            local player, text, arrowIsUp, color = ...
            table.insert(world.halos, { player = player, text = text, up = arrowIsUp, color = color })
        end,
    }

    VHSHappiness = nil
    dofile(MOD_FILE)
end

local function fire(name, ...)
    for _, fn in ipairs(world.handlers[name]) do fn(...) end
end

-- The game showing one line on a device, as OnDeviceText reports it.
-- Coordinates are floats, so they may not be whole numbers; pass
-- passDevice=false to leave out the device argument.
local function showLine(device, guid, passDevice)
    fire("OnDeviceText", guid, "BOR-1", device.x + 0.5, device.y + 0.5, device.z,
        "line text", passDevice ~= false and device or nil)
end

-- Plays lines first..last (default: all) of the tape in `tv`.
local function play(tv, first, last)
    local tape = tv.dd.media
    for i = first or 1, last or #tape.guids do
        showLine(tv, tape.guids[i])
    end
end

local function addPlayer(x, y, z, unhappiness)
    local p = newPlayer(x, y, z, unhappiness)
    getSquare(x, y, z) -- the ground the player stands on is loaded
    p.num = #world.players
    table.insert(world.players, p)
    return p
end

-----------------------------------------------------------------------------
-- Test runner
-----------------------------------------------------------------------------

local tests = {}
local function test(name, fn) table.insert(tests, { name = name, fn = fn }) end

local function near(actual, expected, msg)
    if math.abs(actual - expected) > 1e-6 then
        error(string.format("%s: expected %.4f, got %.4f", msg or "value", expected, actual), 2)
    end
end

-----------------------------------------------------------------------------
-- Tests
-----------------------------------------------------------------------------

test("whole retail tape gives a book's worth (40), spread over its lines", function()
    loadMod()
    local tv = addTV(12, 10, 0, newTape("movie", "Retail-VHS", 18))
    local p = addPlayer(10, 10, 0, 80)
    play(tv, 1, 1)
    near(p.unhappiness, 80 - 40 / 18, "after 1 line")
    play(tv, 2, 18)
    near(p.unhappiness, 40, "after the whole tape")
end)

test("whole home video gives a comic's worth (20)", function()
    loadMod()
    local tv = addTV(10, 13, 0, newTape("home", "Home-VHS", 7))
    local p = addPlayer(10, 10, 0, 80)
    play(tv)
    near(p.unhappiness, 60)
end)

test("half a tape gives half, and finishing it later gives the rest", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 10))
    local p = addPlayer(10, 10, 0, 100)
    play(tv, 1, 5)
    near(p.unhappiness, 80, "half")
    play(tv, 6, 10)
    near(p.unhappiness, 60, "rest")
end)

test("a tape that repeats a line still gives its full amount", function()
    loadMod()
    local music = { [2] = "music", [5] = "music", [8] = "music" }
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 10, { sameGuid = music }))
    local p = addPlayer(10, 10, 0, 100)
    play(tv)
    near(p.unhappiness, 60)
end)

test("a tape cheers you up only once, however often you rewatch it", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 18))
    local p = addPlayer(10, 10, 0, 100)
    play(tv)
    near(p.unhappiness, 60, "first viewing")
    for _ = 1, 5 do play(tv) end
    near(p.unhappiness, 60, "rewatches")
end)

test("skill tapes give no happiness, even before their first lesson", function()
    local cases = {
        { "carpentry lesson late in the tape", "Retail-VHS", { [17] = "BOR-1,CRP+1" } },
        { "recipe", "Retail-VHS", { [3] = "RCP=Make Fishing Rod" } },
        { "home video teaching a skill", "Home-VHS", { [5] = "MTL+1" } },
    }
    for _, case in ipairs(cases) do
        loadMod()
        local tv = addTV(11, 10, 0, newTape("skill", case[2], 18, { codes = case[3] }))
        local p = addPlayer(10, 10, 0, 50)
        play(tv, 1, 1)
        near(p.unhappiness, 50, case[1] .. ", first line")
        play(tv)
        near(p.unhappiness, 50, case[1] .. ", whole tape")
        assert(#world.halos == 0, case[1] .. ": no halo")
    end
end)

test("tapes that only change mood (stress, fatigue, panic) still count", function()
    loadMod()
    local moods = { [2] = "STS+0.1", [4] = "FAT-1", [6] = "BOR-1, PAN+25" }
    local tv = addTV(11, 10, 0, newTape("scary-movie", "Retail-VHS", 10, { codes = moods }))
    local p = addPlayer(10, 10, 0, 100)
    play(tv)
    near(p.unhappiness, 60)
end)

test("a different tape has its own bonus", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie-1", "Retail-VHS", 18))
    local p = addPlayer(10, 10, 0, 100)
    play(tv)
    tv.dd.media = newTape("movie-2", "Retail-VHS", 30)
    play(tv)
    near(p.unhappiness, 20)
end)

test("unhappiness never goes below zero", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 18))
    local p = addPlayer(10, 10, 0, 5)
    play(tv)
    near(p.unhappiness, 0)
end)

test("TV broadcasts don't count, even with a tape inserted", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 18))
    tv.dd.playing = false
    local p = addPlayer(10, 10, 0, 50)
    showLine(tv, "life-and-living-broadcast-line")
    near(p.unhappiness, 50)
end)

test("extra lines while a tape plays can't push a tape past its total", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 10))
    local p = addPlayer(10, 10, 0, 100)
    for i = 1, 20 do
        showLine(tv, "not-from-the-tape-" .. i)
    end
    play(tv)
    near(p.unhappiness, 60)
end)

test("a tape line still counts if playback stopped as it was shown", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 10))
    tv.dd.playing = false
    local p = addPlayer(10, 10, 0, 50)
    showLine(tv, "movie:10")
    near(p.unhappiness, 46)
end)

test("no bonus from a TV or radio with nothing playing", function()
    loadMod()
    local tv = addTV(11, 10, 0, nil)
    local radio = addDevice(10, 11, 0, nil)
    local p = addPlayer(10, 10, 0, 50)
    showLine(tv, "tv-broadcast-line")
    showLine(radio, "radio-broadcast-line")
    near(p.unhappiness, 50)
end)

test("radio broadcasts don't count, even with a CD inserted", function()
    loadMod()
    local p = addPlayer(10, 10, 0, 50)
    local cdPlayer = addCarriedCDPlayer(p, newTape("album", "CDs", 10))
    cdPlayer.dd.playing = false
    showLine(cdPlayer, "radio-broadcast-line")
    near(p.unhappiness, 50)
end)

test("whole CD on a CD player you carry gives a comic's worth (20)", function()
    loadMod()
    local p = addPlayer(10, 10, 0, 80)
    local cdPlayer = addCarriedCDPlayer(p, newTape("album", "CDs", 13))
    play(cdPlayer, 1, 1)
    near(p.unhappiness, 80 - 20 / 13, "after 1 line")
    play(cdPlayer, 2, 13)
    near(p.unhappiness, 60, "after the whole CD")
    assert(#world.halos == 13, "a halo per line, got " .. #world.halos)
end)

test("a CD player you carry counts wherever the game says the line came from", function()
    for _, at in ipairs({ { 0, 0, 0 }, { 300, 300, 0 }, { 10, 10, 1 } }) do
        loadMod()
        local p = addPlayer(10, 10, 0, 80)
        local cdPlayer = addCarriedCDPlayer(p, newTape("album", "CDs", 10), at)
        play(cdPlayer)
        near(p.unhappiness, 60, "reported at " .. table.concat(at, ","))
    end
end)

test("a CD cheers you up only once, however often you replay it", function()
    loadMod()
    local p = addPlayer(10, 10, 0, 100)
    local cdPlayer = addCarriedCDPlayer(p, newTape("album", "CDs", 10))
    for _ = 1, 4 do play(cdPlayer) end
    near(p.unhappiness, 80)
end)

test("no CD bonus while asleep or dead, even when carrying the CD player", function()
    for _, field in ipairs({ "asleep", "dead" }) do
        loadMod()
        local p = addPlayer(10, 10, 0, 50)
        p[field] = true
        play(addCarriedCDPlayer(p, newTape("album", "CDs", 10)))
        near(p.unhappiness, 50, field)
    end
end)

test("a CD playing in the world follows the same distance rules as a TV", function()
    loadMod()
    local stereo = addDevice(14, 10, 0, newTape("album", "CDs", 10))
    local near1 = addPlayer(10, 10, 0, 50)
    local far = addPlayer(30, 10, 0, 50)
    play(stereo)
    near(near1.unhappiness, 30, "4 tiles away")
    near(far.unhappiness, 50, "20 tiles away")
end)

test("someone else's CD player only counts if you're close enough", function()
    loadMod()
    local owner = addPlayer(10, 10, 0, 50)
    local friend = addPlayer(12, 10, 0, 50)
    local stranger = addPlayer(30, 10, 0, 50)
    play(addCarriedCDPlayer(owner, newTape("album", "CDs", 10)))
    near(owner.unhappiness, 30, "owner")
    near(friend.unhappiness, 30, "split-screen friend next to them")
    near(stranger.unhappiness, 50, "split-screen player far away")

    loadMod()
    owner = addPlayer(10, 10, 0, 50)
    friend = addPlayer(12, 10, 0, 50)
    play(addCarriedCDPlayer(owner, newTape("album", "CDs", 10), { 0, 0, 0 }))
    near(owner.unhappiness, 30, "owner, position unknown")
    near(friend.unhappiness, 50, "friend, when the game doesn't say where it is")
end)

test("tapes and CDs each keep their own progress", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 18))
    local p = addPlayer(10, 10, 0, 100)
    local cdPlayer = addCarriedCDPlayer(p, newTape("album", "CDs", 10))
    play(tv)
    play(cdPlayer)
    near(p.unhappiness, 40)
end)

test("no bonus when too far, on another floor, out of sight, asleep or dead", function()
    local cases = {
        { "9 tiles away", function() return addTV(19, 10, 0, newTape("t", "Retail-VHS", 5)) end },
        { "another floor", function() return addTV(10, 10, 1, newTape("t", "Retail-VHS", 5)) end },
        { "behind a wall", function()
            local tv = addTV(12, 10, 0, newTape("t", "Retail-VHS", 5))
            getSquare(12, 10, 0).visible = false
            return tv
        end },
        { "asleep", function(p) p.asleep = true; return addTV(11, 10, 0, newTape("t", "Retail-VHS", 5)) end },
        { "dead", function(p) p.dead = true; return addTV(11, 10, 0, newTape("t", "Retail-VHS", 5)) end },
    }
    for _, case in ipairs(cases) do
        loadMod()
        local p = addPlayer(10, 10, 0, 50)
        play(case[2](p))
        near(p.unhappiness, 50, case[1])
    end
end)

test("walls don't matter when line of sight is turned off", function()
    loadMod()
    VHSHappiness.Config.RequireLineOfSight = false
    local tv = addTV(12, 10, 0, newTape("t", "Retail-VHS", 5))
    getSquare(12, 10, 0).visible = false
    local p = addPlayer(10, 10, 0, 50)
    play(tv)
    near(p.unhappiness, 10)
end)

test("counts at exactly the max distance", function()
    loadMod()
    local tv = addTV(18, 10, 0, newTape("t", "Retail-VHS", 5))
    local p = addPlayer(10, 10, 0, 50)
    play(tv)
    near(p.unhappiness, 10)
end)

test("Build 42.13+ stats API (0-100 scale)", function()
    loadMod({ statMax = 100 })
    local tv = addTV(11, 10, 0, newTape("t", "Retail-VHS", 18))
    local p = addPlayer(10, 10, 0, 70)
    play(tv)
    near(p.unhappiness, 30)
end)

test("Build 42.13+ stats API (0-1 scale) is rescaled", function()
    loadMod({ statMax = 1 })
    local tv = addTV(11, 10, 0, newTape("t", "Home-VHS", 18))
    local p = addPlayer(10, 10, 0, 70)
    play(tv)
    near(p.unhappiness, 50)
end)

test("finds the TV on the square if the event doesn't pass the device", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("t", "Retail-VHS", 2))
    table.insert(getSquare(11, 10, 0).objects, 1, { __class = "IsoWaveSignal", getDeviceData = function() return nil end })
    local p = addPlayer(10, 10, 0, 50)
    showLine(tv, "t:1", false)
    showLine(tv, "t:2", false)
    near(p.unhappiness, 10)
end)

test("halo shows with every line that cheers you up, like the Boredom one", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 18))
    local p = addPlayer(10, 10, 0, 100)
    play(tv, 1, 9)
    assert(#world.halos == 9, "one halo per line, got " .. #world.halos)
    local halo = world.halos[1]
    assert(halo.player == p and halo.text == "Unhappiness" and halo.up == false and halo.color == "green")

    play(tv, 10, 18)
    assert(#world.halos == 18, "halo through to the last line, got " .. #world.halos)

    play(tv)
    assert(#world.halos == 18, "no halo once the tape is used up")
end)

test("halo stops once unhappiness reaches zero", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 18))
    local p = addPlayer(10, 10, 0, 5) -- each line removes 40/18 = 2.2
    play(tv)
    near(p.unhappiness, 0)
    assert(#world.halos == 3, "halos only while it was going down, got " .. #world.halos)
end)

test("no halo when already perfectly happy, or when turned off", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("t", "Retail-VHS", 5))
    addPlayer(10, 10, 0, 0)
    play(tv)
    assert(#world.halos == 0, "already happy")

    loadMod()
    VHSHappiness.Config.ShowHaloText = false
    tv = addTV(11, 10, 0, newTape("t", "Retail-VHS", 5))
    addPlayer(10, 10, 0, 50)
    play(tv)
    assert(#world.halos == 0, "turned off")
end)

test("a broken halo never blocks the mood change", function()
    loadMod()
    HaloTextHelper = nil
    local tv = addTV(11, 10, 0, newTape("t", "Retail-VHS", 5))
    local p = addPlayer(10, 10, 0, 50)
    play(tv)
    near(p.unhappiness, 10)
end)

test("split-screen players each get their own bonus", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("t", "Retail-VHS", 18))
    local p1 = addPlayer(10, 10, 0, 50)
    local p2 = addPlayer(12, 10, 0, 30)
    local p3 = addPlayer(30, 10, 0, 30)
    play(tv)
    near(p1.unhappiness, 10, "player 1")
    near(p2.unhappiness, 0, "player 2")
    near(p3.unhappiness, 30, "player 3, too far away")
end)

test("progress saved by earlier versions of the mod carries over", function()
    loadMod()
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 18))
    local p = addPlayer(10, 10, 0, 100)
    p.modData.VHSHappiness = { movie = { start = 0, given = 30 } }
    play(tv)
    near(p.unhappiness, 90)
end)

test("loading the file twice can't push a tape past its total", function()
    loadMod()
    dofile(MOD_FILE)
    assert(#world.handlers.OnDeviceText == 2, "both copies registered")
    local tv = addTV(11, 10, 0, newTape("movie", "Retail-VHS", 18))
    local p = addPlayer(10, 10, 0, 80)
    play(tv)
    near(p.unhappiness, 40)
end)

-----------------------------------------------------------------------------

local failed = 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        print("PASS  " .. t.name)
    else
        failed = failed + 1
        print("FAIL  " .. t.name .. "\n      " .. tostring(err))
    end
end
print(string.format("\n%d passed, %d failed", #tests - failed, failed))
return failed
