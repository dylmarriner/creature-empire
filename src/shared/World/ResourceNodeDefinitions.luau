local TableUtil = require("../Util/TableUtil")

local ids = {
    "node_tree",
    "node_rock",
}

-- Manual gathering nodes in the exploration zone. cooldownSeconds applies per player per node.
local byId = {
    node_tree = {
        id = "node_tree",
        displayName = "Tree",
        actionText = "Chop",
        itemId = "item_wood",
        yield = 3,
        cooldownSeconds = 3,
    },
    node_rock = {
        id = "node_rock",
        displayName = "Rock",
        actionText = "Mine",
        itemId = "item_stone",
        yield = 3,
        cooldownSeconds = 3,
    },
}

for _, id in ipairs(ids) do
    assert(byId[id] ~= nil, `Missing resource node definition for {id}`)
end

return TableUtil.deepFreeze({
    Ids = ids,
    ById = byId,
})
