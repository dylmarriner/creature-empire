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
    | "insufficient_currency"
    | "unknown_currency"
    | "starter_already_granted"
    | "capture_not_eligible"
    | "duplicate_creature_instance"
    | "duplicate_building_instance"
    | "invalid_generated_id"
    | "creature_not_owned"
    | "building_not_owned"
    | "incompatible_work"
    | "creature_already_assigned"
    | "building_capacity_full"
    | "max_level_reached"
    | "invalid_placement"
    | "not_unlocked"
    | "nothing_to_claim"
    | "invalid_request"

export type DomainResult<T> =
    { ok: true, value: T }
    | { ok: false, code: DomainErrorCode, message: string }

return {}
