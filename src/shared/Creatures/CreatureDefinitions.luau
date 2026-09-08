local ids = table.freeze({
    "creature_rockhorn",
    "creature_embercub",
    "creature_mossling",
    "creature_voltfox",
    "creature_timberpaw",
    "creature_aquafin",
})

local byId = {
    creature_rockhorn = {
        id = "creature_rockhorn",
        displayName = "Rockhorn",
        element = "earth",
        primaryWork = "mining",
        workAffinity = { mining = 1.25 },
    },
    creature_embercub = {
        id = "creature_embercub",
        displayName = "Embercub",
        element = "fire",
        primaryWork = "smelting",
        workAffinity = { smelting = 1.25 },
    },
    creature_mossling = {
        id = "creature_mossling",
        displayName = "Mossling",
        element = "nature",
        primaryWork = "farming",
        workAffinity = { farming = 1.25 },
    },
    creature_voltfox = {
        id = "creature_voltfox",
        displayName = "Voltfox",
        element = "electric",
        primaryWork = "power",
        workAffinity = { power = 1.25 },
    },
    creature_timberpaw = {
        id = "creature_timberpaw",
        displayName = "Timberpaw",
        element = "nature",
        primaryWork = "logging",
        workAffinity = { logging = 1.25 },
    },
    creature_aquafin = {
        id = "creature_aquafin",
        displayName = "Aquafin",
        element = "water",
        primaryWork = "water",
        workAffinity = { water = 1.25 },
    },
}

for _, id in ipairs(ids) do
    assert(byId[id] ~= nil, `Missing creature definition for {id}`)
end

return table.freeze({
    Ids = ids,
    ById = table.freeze(byId),
})
