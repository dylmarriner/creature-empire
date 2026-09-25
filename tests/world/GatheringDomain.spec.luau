local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local GatheringDomain = require("../../src/shared/World/GatheringDomain")

local function run()
    local profile = Fixtures.profile()
    local gathered = Expect.ok(GatheringDomain.gather(profile, "node_tree"), "chop tree")
    Expect.equal(gathered.itemId, "item_wood", "tree yields wood")
    Expect.equal(gathered.quantity, 3, "tree yield")
    Expect.equal(profile.inventory.item_wood, 3, "wood added")

    Expect.ok(GatheringDomain.gather(profile, "node_rock"), "mine rock")
    Expect.equal(profile.inventory.item_stone, 3, "stone added")

    profile.inventory.item_wood = 199
    local partial = Expect.ok(GatheringDomain.gather(profile, "node_tree"), "near capacity")
    Expect.equal(partial.quantity, 1, "yield limited by storage")
    Expect.errorCode(GatheringDomain.gather(profile, "node_tree"), "storage_full", "storage full")
    Expect.equal(profile.inventory.item_wood, 200, "full storage unchanged")

    Expect.errorCode(
        GatheringDomain.gather(profile, "node_gold"),
        "invalid_request",
        "unknown node"
    )
end

return run
