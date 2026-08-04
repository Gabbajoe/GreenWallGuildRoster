-- Minimal, dependency-free test runner - no test framework needed for a
-- suite this small. Only covers the handful of functions with zero WoW-API
-- dependency (Logic.lua, ZoneData.lua); everything else in this addon is
-- UI/event glue that isn't worth mocking a whole fake WoW client for.
--
-- Run from anywhere: `lua tests/run_tests.lua`

local ROOT = (arg[0]:match('(.*[/\\])') or './') .. '../'

-- The only WoW global ZoneData.lua actually calls.
_G.GetLocale = function() return _G.__TEST_LOCALE or 'enUS' end

local ns = {}
local function loadAddonFile(path)
    local chunk, err = loadfile(ROOT .. path)
    if not chunk then error(err) end
    return chunk('GreenWallGuildRoster', ns)
end

loadAddonFile('Logic.lua')
loadAddonFile('ZoneData.lua')

local passCount = 0
local failures = {}

local function eq(actual, expected, label)
    if actual == expected then
        passCount = passCount + 1
    else
        failures[#failures + 1] = string.format('%s: expected %s, got %s', label, tostring(expected), tostring(actual))
    end
end

local function check(condition, label)
    if condition then
        passCount = passCount + 1
    else
        failures[#failures + 1] = label
    end
end

-- RankBadge -------------------------------------------------------------
-- Locked in against the real, empirically-verified flag data from two
-- independently-configured guilds - guards against regressing to either of
-- the two previously-falsified rules (flag index 5, or a flat
-- rankIndex<=1 cutoff).
local function flagsWithIndex3(value)
    return function() return { [3] = value } end
end
eq(ns.RankBadge(0, flagsWithIndex3(false)), '2', 'rankIndex 0 is always Guild Master')
eq(ns.RankBadge(2, flagsWithIndex3(true)), '1', 'flag[3]=true is a native officer crown')
eq(ns.RankBadge(2, flagsWithIndex3(false)), '0', 'flag[3]=false is no crown, even for a non-base rank')
eq(ns.RankBadge(5, function() error('rank not found') end), '0', 'a failed flag lookup is treated as no crown, not an error')

-- NewPaletteAssigner ------------------------------------------------------
local nextColor = ns.NewPaletteAssigner()
local first = nextColor('SaftladenTag')
eq(nextColor('SaftladenTag'), first, 'same key keeps the same color on repeat calls')
check(nextColor('MilchbarTag') ~= first, 'two different keys get different colors')

-- ZoneData ------------------------------------------------------------------
-- Guards the exact class of bug this table has had before (wrong/missing
-- translations - Dustwallow Marsh, Hillsbrad Foothills, and the four
-- capital cities that turned out not to be translated in-game at all).
_G.__TEST_LOCALE = 'deDE'
eq(ns.FromCanonicalZone('The Deadmines'), 'Die Todesminen', 'Deadmines EN->DE')
eq(ns.ToCanonicalZone('Die Todesminen'), 'The Deadmines', 'Deadmines DE->EN')
eq(ns.FromCanonicalZone('Wailing Caverns'), 'Die Höhlen des Wehklagens', 'Wailing Caverns EN->DE')
eq(ns.ToCanonicalZone('Die Höhlen des Wehklagens'), 'Wailing Caverns', 'Wailing Caverns DE->EN')
eq(ns.FromCanonicalZone('Stormwind City'), 'Stormwind', 'capital cities are NOT translated in-game')
_G.__TEST_LOCALE = 'enUS'
eq(ns.FromCanonicalZone('Wailing Caverns'), 'Wailing Caverns', 'enUS client: zone text passes through unchanged')

print(string.format('%d passed, %d failed', passCount, #failures))
if #failures > 0 then
    for _, msg in ipairs(failures) do
        print('FAIL: ' .. msg)
    end
    os.exit(1)
end
