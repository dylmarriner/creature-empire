export type PositionRecord = {
    x: number,
    y: number,
    z: number,
}

export type CreatureInstance = {
    id: string,
    speciesId: string,
    level: number,
    experience: number,
    traits: { string },
    mutationId: string?,
    assignedBuildingId: string?,
}

export type BuildingInstance = {
    id: string,
    definitionId: string,
    level: number,
    position: PositionRecord,
    rotation: number,
    assignedCreatureIds: { string },
    lastClaimedAt: number,
}

export type PlayerProfile = {
    schemaVersion: number,
    currencies: {
        coins: number,
        gems: number,
    },
    inventory: { [string]: number },
    creatures: { [string]: CreatureInstance },
    buildings: { [string]: BuildingInstance },
    unlocks: { [string]: boolean },
    lastSeenAt: number,
}

export type DomainErrorCode =
    "insufficient_resources"
    | "creature_already_assigned"
    | "building_capacity_full"
    | "invalid_placement"
    | "not_unlocked"
    | "nothing_to_claim"
    | "invalid_request"

export type DomainResult<T> =
    { ok: true, value: T }
    | { ok: false, code: DomainErrorCode, message: string }

return {}
