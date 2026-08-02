local ADDON_NAME, ns = ...

-- Pure logic with no WoW API dependency, kept separate so it can be unit
-- tested directly (see tests/) without mocking the UI-heavy rest of the
-- addon. Loaded first in the TOC, before anything that uses it.

local PALETTE = { '5ec4ff', 'ff6ec4', 'c983ff', 'ffa754', '7fffa0', '8c8cff' }
ns.PEER_COLOR_PALETTE = PALETTE

-- Assigns each never-seen-before key the next color in PALETTE, in
-- first-seen order, cycling once every color's been used. Both the roster
-- window's per-guild coloring and the Prat chat integration's per-tag
-- coloring used to each hand-roll their own copy of this.
local function NewPaletteAssigner(palette)
    palette = palette or PALETTE
    local cache = {}
    local nextIndex = 1
    return function(key)
        if not cache[key] then
            cache[key] = palette[((nextIndex - 1) % #palette) + 1]
            nextIndex = nextIndex + 1
        end
        return cache[key]
    end
end
ns.NewPaletteAssigner = NewPaletteAssigner

-- rankIndex 0 (Guild Master) always gets the crown; for any other rank,
-- whether GuildControlGetRankFlags flag index 3 is set is the empirically-
-- confirmed indicator of the native officer crown - verified against real
-- rank data across two independently-configured guilds (see Core.lua's
-- history for how the earlier flag-index-5 and flat-rankIndex-cutoff
-- rules were each falsified before landing on this one). getFlags is
-- injected so this is testable without a real WoW client.
local function RankBadge(rankIndex, getFlags)
    if rankIndex == 0 then return '2' end
    local ok, flags = pcall(getFlags, rankIndex)
    if ok and flags and flags[3] then return '1' end
    return '0'
end
ns.RankBadge = RankBadge

-- Per-cycle whisper-sync target count for a guild needing this many
-- message chunks: capped at maxTargets, but never allowed to floor below
-- minTargets even for a guild needing many chunks. A floor of 1 here once
-- let the combined roster flicker between fully-populated and nearly-empty
-- for large/busy co-guilds, since only one random target got synced per
-- cycle for exactly the guilds needing the most reach.
local function ComputeWhisperTargetLimit(chunkCount, minTargets, maxTargets, messageBudget)
    return math.max(minTargets, math.min(maxTargets, math.floor(messageBudget / chunkCount)))
end
ns.ComputeWhisperTargetLimit = ComputeWhisperTargetLimit
