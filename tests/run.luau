local process = require("@lune/process")

local specs = {
    { name = "shared/ProductionAndGridMath", run = require("./shared/ProductionMath.spec") },
    { name = "shared/DefinitionsIntegrity", run = require("./shared/DefinitionsIntegrity.spec") },
    { name = "economy/ProfileSchema", run = require("./economy/ProfileSchema.spec") },
    { name = "economy/InventoryDomain", run = require("./economy/InventoryDomain.spec") },
    { name = "economy/CurrencyDomain", run = require("./economy/CurrencyDomain.spec") },
    { name = "economy/BuildingCostDomain", run = require("./economy/BuildingCostDomain.spec") },
    { name = "economy/ProductionDomain", run = require("./economy/ProductionDomain.spec") },
    { name = "economy/MarketAndCapacity", run = require("./economy/MarketAndCapacity.spec") },
    {
        name = "creatures/CreatureOwnershipDomain",
        run = require("./creatures/CreatureOwnershipDomain.spec"),
    },
    {
        name = "creatures/WorkAssignmentDomain",
        run = require("./creatures/WorkAssignmentDomain.spec"),
    },
    {
        name = "creatures/WorkAssignmentMutation",
        run = require("./creatures/WorkAssignmentMutation.spec"),
    },
    { name = "buildings/PlacementDomain", run = require("./buildings/PlacementDomain.spec") },
    { name = "buildings/UpgradeDomain", run = require("./buildings/UpgradeDomain.spec") },
    { name = "world/GatheringDomain", run = require("./world/GatheringDomain.spec") },
    { name = "progression/ObjectiveDomain", run = require("./progression/ObjectiveDomain.spec") },
    { name = "profiles/ProfileIntegrity", run = require("./profiles/ProfileIntegrity.spec") },
    { name = "net/ActionSchemas", run = require("./net/ActionSchemas.spec") },
    { name = "gameplay/ActionPipeline", run = require("./gameplay/ActionPipeline.spec") },
    { name = "server/ProfileStore", run = require("./server/ProfileStore.spec") },
    { name = "integration/VerticalSlice", run = require("./integration/VerticalSlice.spec") },
}

local failures = 0
for _, spec in ipairs(specs) do
    local success, message = pcall(spec.run)
    if success then
        print(`PASS {spec.name}`)
    else
        failures += 1
        print(`FAIL {spec.name}: {message}`)
    end
end

if failures > 0 then
    print(`{failures} of {#specs} spec(s) failed`)
    process.exit(1)
end

print(`Creature Empire pure-domain tests passed ({#specs} specs)`)
