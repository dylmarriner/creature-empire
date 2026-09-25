-- Client-to-server semantic actions. Each name is a RemoteEvent under ReplicatedStorage.Remotes.
-- Capture and manual gathering are world interactions handled by server-owned ProximityPrompts,
-- so they have no client-invokable remote.
return table.freeze({
    AssignCreature = "AssignCreature",
    UnassignCreature = "UnassignCreature",
    ReleaseCreature = "ReleaseCreature",
    PlaceBuilding = "PlaceBuilding",
    UpgradeBuilding = "UpgradeBuilding",
    RemoveBuilding = "RemoveBuilding",
    ClaimProduction = "ClaimProduction",
    SellResource = "SellResource",
    RequestSync = "RequestSync",
    Travel = "Travel",
})
