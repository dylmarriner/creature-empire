local TableUtil = require("../Util/TableUtil")

local ids = {
    "creature_rockhorn",
    "creature_embercub",
    "creature_mossling",
    "creature_voltfox",
    "creature_timberpaw",
    "creature_aquafin",
    -- Hybrids: bred only, one for every pair of base species (see HYBRIDS below).
    "creature_magmaback",
    "creature_lichenhorn",
    "creature_thunderhorn",
    "creature_burrowpaw",
    "creature_tidehorn",
    "creature_cinderbloom",
    "creature_stormcub",
    "creature_charpaw",
    "creature_steamfin",
    "creature_sparkmoss",
    "creature_thicketling",
    "creature_marshling",
    "creature_stormpaw",
    "creature_galvanfin",
    "creature_driftpaw",
}

local WILD_SPECIES_COUNT = 6

-- captureChance is the server-rolled probability that a capture attempt succeeds.
-- spawnWeight controls how often the species appears in the exploration zone.
-- color is presentation data only.
local byId = {
    creature_rockhorn = {
        id = "creature_rockhorn",
        displayName = "Rockhorn",
        element = "earth",
        primaryWork = "mining",
        workAffinity = { mining = 1.25 },
        captureChance = 0.6,
        spawnWeight = 3,
        color = { r = 124, g = 108, b = 92 },
    },
    creature_embercub = {
        id = "creature_embercub",
        displayName = "Embercub",
        element = "fire",
        primaryWork = "smelting",
        workAffinity = { smelting = 1.25 },
        captureChance = 0.45,
        spawnWeight = 2,
        color = { r = 226, g = 96, b = 44 },
    },
    creature_mossling = {
        id = "creature_mossling",
        displayName = "Mossling",
        element = "nature",
        primaryWork = "farming",
        workAffinity = { farming = 1.25 },
        captureChance = 0.7,
        spawnWeight = 4,
        color = { r = 104, g = 176, b = 72 },
    },
    creature_voltfox = {
        id = "creature_voltfox",
        displayName = "Voltfox",
        element = "electric",
        primaryWork = "power",
        workAffinity = { power = 1.25 },
        captureChance = 0.35,
        spawnWeight = 1,
        color = { r = 244, g = 208, b = 63 },
    },
    creature_timberpaw = {
        id = "creature_timberpaw",
        displayName = "Timberpaw",
        element = "nature",
        primaryWork = "logging",
        workAffinity = { logging = 1.25 },
        captureChance = 0.7,
        spawnWeight = 4,
        color = { r = 150, g = 100, b = 60 },
    },
    creature_aquafin = {
        id = "creature_aquafin",
        displayName = "Aquafin",
        element = "water",
        primaryWork = "water",
        -- Aquafin irrigates farms until dedicated water buildings exist.
        workAffinity = { water = 1.25, farming = 1.1 },
        captureChance = 0.55,
        spawnWeight = 3,
        color = { r = 64, g = 150, b = 220 },
    },
}

-- Hybrids are never found in the Wilds (captureChance and spawnWeight are 0). Breeding two
-- different base species can produce the hybrid for that pair. A hybrid is a generalist: it
-- works both parents' trades at 1.15, against 1.25 for a specialist's own trade, so it trades
-- peak output for flexibility. Colour is the average of the parents'.
local HYBRID_AFFINITY = 1.15

local HYBRIDS = {
    { "magmaback", "Magmaback", "fire", "creature_rockhorn", "creature_embercub" },
    { "lichenhorn", "Lichenhorn", "nature", "creature_rockhorn", "creature_mossling" },
    { "thunderhorn", "Thunderhorn", "electric", "creature_rockhorn", "creature_voltfox" },
    { "burrowpaw", "Burrowpaw", "earth", "creature_rockhorn", "creature_timberpaw" },
    { "tidehorn", "Tidehorn", "water", "creature_rockhorn", "creature_aquafin" },
    { "cinderbloom", "Cinderbloom", "fire", "creature_embercub", "creature_mossling" },
    { "stormcub", "Stormcub", "electric", "creature_embercub", "creature_voltfox" },
    { "charpaw", "Charpaw", "fire", "creature_embercub", "creature_timberpaw" },
    { "steamfin", "Steamfin", "water", "creature_embercub", "creature_aquafin" },
    { "sparkmoss", "Sparkmoss", "nature", "creature_mossling", "creature_voltfox" },
    { "thicketling", "Thicketling", "nature", "creature_mossling", "creature_timberpaw" },
    { "marshling", "Marshling", "water", "creature_mossling", "creature_aquafin" },
    { "stormpaw", "Stormpaw", "electric", "creature_voltfox", "creature_timberpaw" },
    { "galvanfin", "Galvanfin", "electric", "creature_voltfox", "creature_aquafin" },
    { "driftpaw", "Driftpaw", "water", "creature_timberpaw", "creature_aquafin" },
}

local hybridByPair = {}

local function pairKey(speciesA: string, speciesB: string): string
    if speciesA > speciesB then
        speciesA, speciesB = speciesB, speciesA
    end
    return `{speciesA}|{speciesB}`
end

for _, entry in ipairs(HYBRIDS) do
    local key, displayName, element, parentA, parentB = table.unpack(entry)
    local first = byId[parentA]
    local second = byId[parentB]
    assert(first ~= nil and second ~= nil, `hybrid {key} has an unknown parent`)

    local id = `creature_{key}`
    local workAffinity = {}
    workAffinity[first.primaryWork] = HYBRID_AFFINITY
    workAffinity[second.primaryWork] = HYBRID_AFFINITY

    byId[id] = {
        id = id,
        displayName = displayName,
        element = element,
        primaryWork = first.primaryWork,
        workAffinity = workAffinity,
        captureChance = 0,
        spawnWeight = 0,
        hybridOf = { parentA, parentB },
        color = {
            r = (first.color.r + second.color.r) // 2,
            g = (first.color.g + second.color.g) // 2,
            b = (first.color.b + second.color.b) // 2,
        },
    }

    local pair = pairKey(parentA, parentB)
    assert(hybridByPair[pair] == nil, `two hybrids share the parents {pair}`)
    hybridByPair[pair] = id
end

for _, id in ipairs(ids) do
    assert(byId[id] ~= nil, `Missing creature definition for {id}`)
end

-- Species that spawn in the Wilds and can be captured.
local wildIds = {}
for _, id in ipairs(ids) do
    if byId[id].spawnWeight > 0 then
        table.insert(wildIds, id)
    end
end
assert(#wildIds == WILD_SPECIES_COUNT, "unexpected number of wild species")

-- The hybrid bred from two base species, or nil when the pair has none (same species, or a
-- parent that is itself a hybrid).
local function hybridFor(speciesA: string, speciesB: string): string?
    return hybridByPair[pairKey(speciesA, speciesB)]
end

return TableUtil.deepFreeze({
    Ids = ids,
    WildIds = wildIds,
    ById = byId,
    hybridFor = hybridFor,
})
