local ADDON_NAME, ns = ...

-- GetGuildRosterInfo's zone field always comes back pre-localized to the
-- CALLING client's own language - there's no zone ID exposed for other
-- players, and no Blizzard API to translate a zone name back to one.
-- Wire format uses English as the neutral key: a non-English sender
-- reverse-looks-up their local zone text to the English name before
-- sending; a non-English receiver forward-translates the received
-- English name back to their own language for display. Covers the major
-- world zones. Built from two /gwgr exportzones dumps (enUS + deDE),
-- matched up by uiMapID - not researched by hand, so no risk of the wiki-
-- vs-actual-Classic mismatches that bit the old hand-built version
-- (Dustwallow Marsh, Hillsbrad Foothills, and worse: the four capital
-- cities turned out to not be translated at all in-game - "Sturmwind",
-- "Eisenschmiede", "Donnerfels", "Unterstadt" were all wrong, the deDE
-- client just shows the English city names). See TRANSLATING.md - this
-- file is a plain drop-in target for a new language's exported table.
-- Dungeon/instance names aren't covered by the map-ID export and just
-- pass through untranslated, except The Deadmines - confirmed correct by
-- a live in-game screenshot, not the export.
local ZONE_EN_DE = {
    ['Durotar'] = 'Durotar', ['Mulgore'] = 'Mulgore', ['The Barrens'] = 'Das Brachland',
    ['Alterac Mountains'] = 'Alteracgebirge', ['Arathi Highlands'] = 'Arathihochland', ['Badlands'] = 'Ödland',
    ['Blasted Lands'] = 'Verwüstete Lande', ['Tirisfal Glades'] = 'Tirisfal', ['Silverpine Forest'] = 'Silberwald',
    ['Western Plaguelands'] = 'Westliche Pestländer', ['Eastern Plaguelands'] = 'Östliche Pestländer',
    ['Hillsbrad Foothills'] = 'Vorgebirge von Hillsbrad', ['The Hinterlands'] = 'Hinterland',
    ['Dun Morogh'] = 'Dun Morogh', ['Searing Gorge'] = 'Sengende Schlucht', ['Burning Steppes'] = 'Brennende Steppe',
    ['Elwynn Forest'] = 'Wald von Elwynn', ['Deadwind Pass'] = 'Gebirgspass der Totenwinde',
    ['Duskwood'] = 'Dämmerwald', ['Loch Modan'] = 'Loch Modan', ['Redridge Mountains'] = 'Rotkammgebirge',
    ['Stranglethorn Vale'] = 'Schlingendorntal', ['Swamp of Sorrows'] = 'Sümpfe des Elends', ['Westfall'] = 'Westfall',
    ['Wetlands'] = 'Sumpfland', ['Teldrassil'] = 'Teldrassil', ['Darkshore'] = 'Dunkelküste',
    ['Ashenvale'] = 'Eschental', ['Thousand Needles'] = 'Tausend Nadeln',
    ['Stonetalon Mountains'] = 'Steinkrallengebirge', ['Desolace'] = 'Desolace', ['Feralas'] = 'Feralas',
    ['Dustwallow Marsh'] = 'Marschen von Dustwallow', ['Tanaris'] = 'Tanaris', ['Azshara'] = 'Azshara',
    ['Felwood'] = 'Teufelswald', ["Un'Goro Crater"] = "Un'Goro-Krater", ['Moonglade'] = 'Moonglade',
    ['Silithus'] = 'Silithus', ['Winterspring'] = 'Winterquell',
    -- Capital cities are NOT translated in-game, unlike what the old
    -- wiki-sourced table assumed.
    ['Stormwind City'] = 'Stormwind', ['Orgrimmar'] = 'Orgrimmar', ['Ironforge'] = 'Ironforge',
    ['Thunder Bluff'] = 'Thunder Bluff', ['Darnassus'] = 'Darnassus', ['Undercity'] = 'Undercity',
    -- Battlegrounds
    ['Alterac Valley'] = 'Alteractal', ['Warsong Gulch'] = 'Warsongschlucht', ['Arathi Basin'] = 'Arathibecken',
    ['The Deadmines'] = 'Die Todesminen',
}
local ZONE_DE_EN = {}
for en, de in pairs(ZONE_EN_DE) do ZONE_DE_EN[de] = en end

-- Sender side: local zone text -> canonical English for the wire.
local function ToCanonicalZone(zone)
    if not zone or zone == '' then return zone end
    if GetLocale() == 'deDE' then
        return ZONE_DE_EN[zone] or zone
    end
    return zone
end
ns.ToCanonicalZone = ToCanonicalZone

-- Receiver side: canonical English (as received) -> local display text.
local function FromCanonicalZone(zone)
    if not zone or zone == '' then return zone end
    if GetLocale() == 'deDE' then
        return ZONE_EN_DE[zone] or zone
    end
    return zone
end
ns.FromCanonicalZone = FromCanonicalZone
