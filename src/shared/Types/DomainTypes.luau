export type PositionRecord = {
    x: number,
    y: number,
    z: number,
}

export type Genes = {
    vigor: number,
    might: number,
    focus: number,
}

export type CreatureInstance = {
    id: string,
    speciesId: string,
    level: number,
    experience: number,
    traits: { string },
    mutationId: string?,
    assignedBuildingId: string?,
    genes: Genes,
    generation: number,
    lineage: { speciesA: string, speciesB: string }?,
    bornAt: number,
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

-- Everything one party puts up in a transfer. Held creatures are out of play.
export type TransferPayload = {
    items: { [string]: number },
    coins: number,
    creatures: { [string]: CreatureInstance },
}

-- A profile's record of an offer it has escrowed and not yet settled.
export type TransferJournalEntry = {
    id: string,
    createdAt: number,
    offer: TransferPayload,
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
    eggs: { [string]: { id: string } },
    expeditions: { [string]: { id: string } },
    transfers: { [string]: TransferJournalEntry },
    purchases: { [string]: number },
    passes: { [string]: boolean },
    guildId: string?,
    stats: { [string]: number },
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
    | "storage_full"
    | "creature_capacity_full"
    | "creature_not_assigned"
    | "building_limit_reached"
    | "not_ready"
    | "rate_limited"
    | "transfer_not_found"
    | "transfer_not_pending"
    | "transfer_forbidden"
    | "transfer_conflict"
    | "store_unavailable"
    | "internal_error"

export type DomainResult<T> =
    { ok: true, value: T }
    | { ok: false, code: DomainErrorCode, message: string }

return {}
