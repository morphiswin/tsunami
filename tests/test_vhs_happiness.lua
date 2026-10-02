-- Tests for VHSHappiness.lua against a mocked Project Zomboid API.
-- Run with: python3 tests/run_tests.py

local MOD_FILE = MOD_ROOT .. "/VHSHappiness/42/media/lua/client/VHSHappiness.lua"

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

local function newMedia(id, category)
    return {
        getId = function() return id end,
        getCategory = function() return category end,
    }
end

-- Places a TV at (x, y, z) and returns its device data so tests can tweak it.
local function addTV(x, y, z, media)
    local dd = { tv = true, on = true, playing = true, media = media, index = 7 }
    function dd:getIsTelevision() return self.tv end
    function dd:getIsTurnedOn() return self.on end
    function dd:isPlayingMedia() return self.playing end
    function dd:getMediaData() return self.media end
    function dd:getMediaIndex() return self.index end
    local tv = { __class = "IsoWaveSignal" }
    function tv:getDeviceData() return dd end
    table.insert(getSquare(x, y, z).objects, tv)
    return dd
end

local function newPlayer(x, y, z, unhappiness)
    local p = {
        num = 0, x = x, y = y, z = z, dead = false, asleep = false,
        modData = {}, unhappiness = unhappiness,
    }
    function p:getCurrentSquare() return getSquare(self.x, self.y, self.z) end
    function p:getPlayerNum() return self.num end
    function p:isDead() return self.dead end
    function p:isAsleep() return self.asleep end
    function p:getModData() return self.modData end
    function p:getBodyDamage()
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
-- options.haloSignature: "b41" (4 args) or "b42" (5 args with separator).
local function loadMod(options)
    options = options or {}
    world = { squares = {}, hours = 0, players = {}, halos = {}, mediaByIndex = {} }

    local handlers = {}
    Events = {}
    for _, name in ipairs({ "EveryOneMinute", "EveryDays" }) do
        handlers[name] = {}
        Events[name] = { Add = function(fn) table.insert(handlers[name], fn) end }
    end
    world.fire = function(name)
        for _, fn in ipairs(handlers[name]) do fn() end
    end

    getCell = function()
        return {
            getGridSquare = function(_, x, y, z)
                return world.squares[x .. "," .. y .. "," .. z]
            end,
        }
    end
    getGameTime = function()
        return { getWorldAgeHours = function() return world.hours end }
    end
    getNumActivePlayers = function() return #world.players end
    getSpecificPlayer = function(i) return world.players[i + 1] end
    instanceof = function(obj, name) return type(obj) == "table" and obj.__class == name end
    getZomboidRadio = function()
        return {
            getRecordedMedia = function()
                return {
                    getMediaDataFromIndex = function(_, i) return world.mediaByIndex[i] end,
                }
            end,
        }
    end

    if options.statMax then
        local stat = { max = options.statMax }
        function stat:getMaximumValue() return self.max end
        function stat:getMinimumValue() return 0 end
        CharacterStat = { UNHAPPINESS = stat }
    else
        CharacterStat = nil
    end

    local signature = options.haloSignature or "b42"
    HaloTextHelper = {
        getColorGreen = function() return "green" end,
        addTextWithArrow = function(...)
            local args = { ... }
            if signature == "b42" then
                assert(select("#", ...) == 5 and type(args[3]) == "string", "bad b42 halo call")
                table.insert(world.halos, { text = args[2], up = args[4], color = args[5] })
            else
                assert(select("#", ...) == 4 and type(args[3]) == "boolean", "bad b41 halo call")
                table.insert(world.halos, { text = args[2], up = args[3], color = args[4] })
            end
        end,
    }

    VHSHappiness = nil
    dofile(MOD_FILE)
end

-- Advances the clock by `minutes` in-game minutes, firing the mod's events.
local function watch(minutes)
    for _ = 1, minutes do
        world.hours = world.hours + 1 / 60
        world.fire("EveryOneMinute")
    end
end

local function addPlayer(x, y, z, unhappiness)
    local p = newPlayer(x, y, z, unhappiness)
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

test("retail tape gives a book's worth (40) spread over 45 minutes", function()
    loadMod()
    addTV(12, 10, 0, newMedia("movie-1", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 80)
    watch(1)
    near(p.unhappiness, 80 - 40 / 45, "after 1 minute")
    watch(44)
    near(p.unhappiness, 40, "after 45 minutes")
    watch(60)
    near(p.unhappiness, 40, "capped after the full bonus")
end)

test("home video gives a comic's worth (20)", function()
    loadMod()
    addTV(10, 13, 0, newMedia("home-1", "Home-VHS"))
    local p = addPlayer(10, 10, 0, 80)
    watch(120)
    near(p.unhappiness, 60)
end)

test("same tape works again after the cooldown", function()
    loadMod()
    addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 100)
    watch(60)
    near(p.unhappiness, 60, "first viewing")
    watch(23 * 60) -- one in-game day after the first viewing started
    near(p.unhappiness, 60, "still on cooldown")
    watch(60)
    near(p.unhappiness, 20, "second viewing")
end)

test("stopping early keeps progress for the rest of the tape", function()
    loadMod()
    local dd = addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 100)
    watch(9)
    dd.playing = false
    watch(30)
    near(p.unhappiness, 92, "paused")
    dd.playing = true
    watch(60)
    near(p.unhappiness, 60, "finished later")
end)

test("a different tape has its own bonus", function()
    loadMod()
    local dd = addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 100)
    watch(60)
    dd.media = newMedia("movie-2", "Retail-VHS")
    watch(60)
    near(p.unhappiness, 20)
end)

test("unhappiness never goes below zero", function()
    loadMod()
    addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 5)
    watch(60)
    near(p.unhappiness, 0)
end)

test("no bonus when the TV is off, not playing, or not a TV", function()
    for _, field in ipairs({ "on", "playing", "tv" }) do
        loadMod()
        local dd = addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
        dd[field] = false
        local p = addPlayer(10, 10, 0, 50)
        watch(60)
        near(p.unhappiness, 50, field)
    end
end)

test("no bonus when too far, on another floor, or out of sight", function()
    loadMod()
    addTV(19, 10, 0, newMedia("far", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 50)
    watch(60)
    near(p.unhappiness, 50, "9 tiles away")

    loadMod()
    addTV(10, 10, 1, newMedia("upstairs", "Retail-VHS"))
    p = addPlayer(10, 10, 0, 50)
    watch(60)
    near(p.unhappiness, 50, "another floor")

    loadMod()
    addTV(12, 10, 0, newMedia("behind-wall", "Retail-VHS"))
    getSquare(12, 10, 0).visible = false
    p = addPlayer(10, 10, 0, 50)
    watch(60)
    near(p.unhappiness, 50, "behind a wall")
end)

test("works at exactly the max distance", function()
    loadMod()
    addTV(18, 10, 0, newMedia("edge", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 50)
    watch(60)
    near(p.unhappiness, 10)
end)

test("no bonus while asleep", function()
    loadMod()
    addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 50)
    p.asleep = true
    watch(60)
    near(p.unhappiness, 50)
end)

test("Build 42.13+ stats API (0-100 scale)", function()
    loadMod({ statMax = 100 })
    addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 70)
    watch(60)
    near(p.unhappiness, 30)
end)

test("Build 42.13+ stats API (0-1 scale) is rescaled", function()
    loadMod({ statMax = 1 })
    addTV(11, 10, 0, newMedia("home-1", "Home-VHS"))
    local p = addPlayer(10, 10, 0, 70)
    watch(60)
    near(p.unhappiness, 50)
end)

test("falls back to looking the tape up by index", function()
    loadMod()
    local dd = addTV(11, 10, 0, nil)
    dd.getMediaData = nil
    world.mediaByIndex[7] = newMedia("home-by-index", "Home-VHS")
    local p = addPlayer(10, 10, 0, 70)
    watch(60)
    near(p.unhappiness, 50)
    assert(p.modData.VHSHappiness["home-by-index"], "record keyed by tape id")
end)

test("unknown tape still counts as a retail tape", function()
    loadMod()
    local dd = addTV(11, 10, 0, nil)
    dd.getMediaData = nil
    local p = addPlayer(10, 10, 0, 70)
    watch(60)
    near(p.unhappiness, 30)
end)

test("halo shows once when a viewing starts (Build 42 signature)", function()
    loadMod({ haloSignature = "b42" })
    local dd = addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    addPlayer(10, 10, 0, 100)
    watch(10)
    assert(#world.halos == 1, "one halo, got " .. #world.halos)
    assert(world.halos[1].text == "Unhappiness" and world.halos[1].up == false)
    dd.playing = false
    watch(1)
    dd.playing = true
    watch(1)
    assert(#world.halos == 2, "halo again after resuming")
end)

test("halo uses the Build 41 signature when needed", function()
    loadMod({ haloSignature = "b41" })
    addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    addPlayer(10, 10, 0, 100)
    watch(5)
    assert(#world.halos == 1, "one halo, got " .. #world.halos)
end)

test("no halo when already perfectly happy", function()
    loadMod()
    addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    addPlayer(10, 10, 0, 0)
    watch(5)
    assert(#world.halos == 0)
end)

test("split-screen players each get their own bonus", function()
    loadMod()
    addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    local p1 = addPlayer(10, 10, 0, 50)
    local p2 = addPlayer(12, 10, 0, 30)
    watch(60)
    near(p1.unhappiness, 10, "player 1")
    near(p2.unhappiness, 0, "player 2")
end)

test("expired records are pruned daily", function()
    loadMod()
    local dd = addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 50)
    watch(60)
    dd.playing = false
    world.fire("EveryDays")
    assert(p.modData.VHSHappiness["movie-1"], "kept during cooldown")
    watch(24 * 60)
    world.fire("EveryDays")
    assert(p.modData.VHSHappiness["movie-1"] == nil, "pruned after cooldown")
end)

test("loading the file twice doesn't double the bonus", function()
    loadMod()
    dofile(MOD_FILE)
    addTV(11, 10, 0, newMedia("movie-1", "Retail-VHS"))
    local p = addPlayer(10, 10, 0, 80)
    watch(1)
    near(p.unhappiness, 80 - 40 / 45)
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
