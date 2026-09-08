local ProductionMath = require("../src/shared/Economy/ProductionMath")
local GridMath = require("../src/shared/Buildings/GridMath")
local runProfileSchemaSpec = require("./economy/ProfileSchema.spec")
local runInventoryDomainSpec = require("./economy/InventoryDomain.spec")
local runInventoryTransactionDomainSpec = require("./economy/InventoryTransactionDomain.spec")
local runCurrencyDomainSpec = require("./economy/CurrencyDomain.spec")
local runBuildingCostDomainSpec = require("./economy/BuildingCostDomain.spec")
local runProductionDomainSpec = require("./economy/ProductionDomain.spec")
local runBuildingPlacementDomainSpec = require("./buildings/BuildingPlacementDomain.spec")
local runBuildingUpgradeDomainSpec = require("./buildings/BuildingUpgradeDomain.spec")
local runCreatureOwnershipDomainSpec = require("./creatures/CreatureOwnershipDomain.spec")
local runWorkAssignmentDomainSpec = require("./creatures/WorkAssignmentDomain.spec")
local runWorkAssignmentMutationDomainSpec = require("./creatures/WorkAssignmentMutationDomain.spec")

local function expectEqual(actual: any, expected: any, label: string)
    if actual ~= expected then
        error(`{label}: expected {expected}, got {actual}`)
    end
end

expectEqual(ProductionMath.calculateOutput(10, 1, 1, 1, 120), 20, "base production")
expectEqual(ProductionMath.clampElapsedSeconds(12 * 60 * 60), 8 * 60 * 60, "offline production cap")
expectEqual(GridMath.snapCoordinate(5.9, 4), 4, "positive grid snap")
expectEqual(GridMath.snapCoordinate(-5.9, 4), -4, "negative grid snap")

local snapped = GridMath.snapPosition({ x = 7.9, y = 0.1, z = -9.2 }, 4)
expectEqual(snapped.x, 8, "position x")
expectEqual(snapped.y, 0, "position y")
expectEqual(snapped.z, -8, "position z")

runProfileSchemaSpec()
runInventoryDomainSpec()
runInventoryTransactionDomainSpec()
runCurrencyDomainSpec()
runBuildingCostDomainSpec()
runProductionDomainSpec()
runBuildingPlacementDomainSpec()
runBuildingUpgradeDomainSpec()
runCreatureOwnershipDomainSpec()
runWorkAssignmentDomainSpec()
runWorkAssignmentMutationDomainSpec()

print("Creature Empire pure-domain tests passed")
