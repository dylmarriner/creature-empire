local TableUtil = require("../Util/TableUtil")

local ids = {
    "creature_rockhorn",
    "creature_embercub",
    "creature_mossling",
    "creature_voltfox",
    "creature_timberpaw",
    "creature_aquafin",
}

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

for _, id in ipairs(ids) do
    assert(byId[id] ~= nil, `Missing creature definition for {id}`)
end

return TableUtil.deepFreeze({
    Ids = ids,
    ById = byId,
})
