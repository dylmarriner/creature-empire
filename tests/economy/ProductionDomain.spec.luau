local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local ProductionDomain = require("../../src/shared/Economy/ProductionDomain")

local function expectEqual(actual: any, expected: any, label: string)
    if actual ~= expected then
        error(`{label}: expected {expected}, got {actual}`)
    end
end

local function expectOk(result: any, label: string)
    if result.ok ~= true then
        error(`{label}: expected ok result, got {result.code}`)
    end
end

local function expectErrorCode(result: any, code: string, label: string)
    if result.ok ~= false then
        error(`{label}: expected error result`)
    end
    expectEqual(result.code, code, label)
end

local function addCreature(profile: any, id: string, speciesId: string, buildingId: string)
    profile.creatures[id] = {
        id = id,
        speciesId = speciesId,
        level = 1,
        experience = 0,
        traits = {},
        mutationId = nil,
        assignedBuildingId = buildingId,
    }
end

local function addBuilding(
    profile: any,
    id: string,
    definitionId: string,
    level: number,
    workers: { string },
    lastClaimedAt: number
)
    profile.buildings[id] = {
        id = id,
        definitionId = definitionId,
        level = level,
        position = { x = 0, y = 0, z = 0 },
        rotation = 0,
        assignedCreatureIds = workers,
        lastClaimedAt = lastClaimedAt,
    }
end

local function miningProfile(workerCount: number?, level: number?)
    local profile = ProfileSchema.createDefault(100)
    local workers = {}
    for index = 1, workerCount or 1 do
        local id = `rockhorn_{index}`
        addCreature(profile, id, "creature_rockhorn", "mine_1")
        table.insert(workers, id)
    end
    addBuilding(profile, "mine_1", "building_mine", level or 1, workers, 100)
    return profile
end

local function run()
    local profile = miningProfile(1, 1)
    local preview = ProductionDomain.preview(profile, "mine_1", 220)
    expectOk(preview, "Mine preview")
    expectEqual(preview.value.outputItemId, "item_copper_ore", "Mine output item")
    expectEqual(preview.value.outputQuantity, 15, "Mine Rockhorn output")
    expectEqual(preview.value.elapsedSeconds, 120, "Mine elapsed")
    expectEqual(preview.value.clampedElapsedSeconds, 120, "Mine clamped elapsed")

    local claimed = ProductionDomain.claim(profile, "mine_1", 220)
    expectOk(claimed, "Mine claim")
    expectEqual(profile.inventory.item_copper_ore, 15, "Mine claim inventory")
    expectEqual(profile.buildings.mine_1.lastClaimedAt, 220, "Mine claim timestamp")

    local twoWorkers = miningProfile(2, 1)
    local twoWorkerPreview = ProductionDomain.preview(twoWorkers, "mine_1", 220)
    expectOk(twoWorkerPreview, "two Rockhorn preview")
    expectEqual(twoWorkerPreview.value.outputQuantity, 30, "affinity sum output")

    local zeroWorkers = miningProfile(0, 1)
    zeroWorkers.buildings.mine_1.assignedCreatureIds = {}
    local noWork = ProductionDomain.claim(zeroWorkers, "mine_1", 220)
    expectErrorCode(noWork, "nothing_to_claim", "zero workers claim rejected")
    expectEqual(zeroWorkers.buildings.mine_1.lastClaimedAt, 100, "zero claim preserves timestamp")

    local negativeClock = ProductionDomain.preview(miningProfile(1, 1), "mine_1", 99)
    expectErrorCode(negativeClock, "invalid_request", "negative clock delta rejected")

    local offline = ProductionDomain.preview(miningProfile(1, 1), "mine_1", 100 + 12 * 60 * 60)
    expectOk(offline, "offline cap preview")
    expectEqual(offline.value.clampedElapsedSeconds, 8 * 60 * 60, "offline time capped")
    expectEqual(offline.value.outputQuantity, 3600, "offline capped output")

    local levelTwo = ProductionDomain.preview(miningProfile(1, 2), "mine_1", 220)
    expectOk(levelTwo, "level two preview")
    expectEqual(levelTwo.value.outputQuantity, 18, "level multiplier output")

    local furnace = ProfileSchema.createDefault(100)
    furnace.inventory.item_copper_ore = 50
    addCreature(furnace, "ember_1", "creature_embercub", "furnace_1")
    addBuilding(furnace, "furnace_1", "building_furnace", 1, { "ember_1" }, 100)
    local furnaceClaim = ProductionDomain.claim(furnace, "furnace_1", 220)
    expectOk(furnaceClaim, "Furnace claim")
    expectEqual(furnaceClaim.value.outputQuantity, 10, "Furnace output")
    expectEqual(furnaceClaim.value.inputQuantity, 10, "Furnace input quantity")
    expectEqual(furnace.inventory.item_copper_ore, 40, "Furnace consumes ore")
    expectEqual(furnace.inventory.item_copper_bar, 10, "Furnace creates bars")
    expectEqual(furnace.buildings.furnace_1.lastClaimedAt, 220, "Furnace claim timestamp")

    local inputLimited = ProfileSchema.createDefault(100)
    inputLimited.inventory.item_copper_ore = 3
    addCreature(inputLimited, "ember_1", "creature_embercub", "furnace_1")
    addBuilding(inputLimited, "furnace_1", "building_furnace", 1, { "ember_1" }, 100)
    local limited = ProductionDomain.claim(inputLimited, "furnace_1", 220)
    expectOk(limited, "input limited claim")
    expectEqual(limited.value.outputQuantity, 3, "input limited output")
    expectEqual(inputLimited.inventory.item_copper_ore, nil, "input limited ore consumed")
    expectEqual(inputLimited.inventory.item_copper_bar, 3, "input limited bars created")

    local fractional = miningProfile(1, 1)
    local fractionalClaim = ProductionDomain.claim(fractional, "mine_1", 103)
    expectErrorCode(fractionalClaim, "nothing_to_claim", "fractional output not claimable")
    expectEqual(fractional.buildings.mine_1.lastClaimedAt, 100, "fractional time preserved")
    local settled = ProductionDomain.settle(fractional, "mine_1", 103)
    expectOk(settled, "fractional settle")
    expectEqual(settled.value.outputQuantity, 0, "fractional settle output")
    expectEqual(fractional.buildings.mine_1.lastClaimedAt, 103, "settle advances timestamp")

    local corruptRelationship = miningProfile(1, 1)
    corruptRelationship.creatures.rockhorn_1.assignedBuildingId = "other_building"
    local corrupt = ProductionDomain.preview(corruptRelationship, "mine_1", 220)
    expectErrorCode(corrupt, "invalid_request", "corrupt worker relationship rejected")

    local unknownSpecies = miningProfile(1, 1)
    unknownSpecies.creatures.rockhorn_1.speciesId = "creature_unknown"
    local badSpecies = ProductionDomain.preview(unknownSpecies, "mine_1", 220)
    expectErrorCode(badSpecies, "invalid_request", "unknown worker species rejected")

    local invalidLevel = miningProfile(1, 4)
    local badLevel = ProductionDomain.preview(invalidLevel, "mine_1", 220)
    expectErrorCode(badLevel, "invalid_request", "invalid production level rejected")
end

return run
