local TableUtil = require("../Util/TableUtil")

local ids = {
    "mutation_gilded",
    "mutation_ironhide",
    "mutation_sparkeyed",
    "mutation_giant",
    "mutation_wisp",
    "mutation_feral",
}

-- A mutation is a rare birth trait. It tints the creature and shifts its genes. Every shift
-- sums to zero (before clamping to the gene range), so a mutation trades one strength for
-- another and is never strictly better than a normal creature. `weight` sets how often each
-- one is picked once a mutation has happened.
local byId = {
    mutation_gilded = {
        id = "mutation_gilded",
        displayName = "Gilded",
        description = "Tireless worker, softer in a fight.",
        geneShift = { vigor = 8, might = -4, focus = -4 },
        weight = 3,
        tint = { r = 255, g = 214, b = 90 },
    },
    mutation_ironhide = {
        id = "mutation_ironhide",
        displayName = "Ironhide",
        description = "Built to fight, slower at its trade.",
        geneShift = { vigor = -4, might = 8, focus = -4 },
        weight = 3,
        tint = { r = 150, g = 160, b = 175 },
    },
    mutation_sparkeyed = {
        id = "mutation_sparkeyed",
        displayName = "Spark-eyed",
        description = "Sharp and precise, lighter and slower.",
        geneShift = { vigor = -4, might = -4, focus = 8 },
        weight = 3,
        tint = { r = 120, g = 220, b = 255 },
    },
    mutation_giant = {
        id = "mutation_giant",
        displayName = "Giant",
        description = "Strong and sturdy, but clumsy.",
        geneShift = { vigor = 5, might = 5, focus = -10 },
        weight = 2,
        tint = { r = 200, g = 120, b = 90 },
    },
    mutation_wisp = {
        id = "mutation_wisp",
        displayName = "Wisp",
        description = "Quick and clever, but frail.",
        geneShift = { vigor = 5, might = -10, focus = 5 },
        weight = 2,
        tint = { r = 190, g = 160, b = 255 },
    },
    mutation_feral = {
        id = "mutation_feral",
        displayName = "Feral",
        description = "Fierce and focused, poor at honest work.",
        geneShift = { vigor = -10, might = 5, focus = 5 },
        weight = 2,
        tint = { r = 220, g = 70, b = 90 },
    },
}

for _, id in ipairs(ids) do
    assert(byId[id] ~= nil, `Missing mutation definition for {id}`)
end

return TableUtil.deepFreeze({
    Ids = ids,
    ById = byId,
})
