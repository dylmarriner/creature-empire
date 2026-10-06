local EscrowDomain = require("../../src/shared/Transfers/EscrowDomain")
local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local TableUtil = require("../../src/shared/Util/TableUtil")
local TransferDomain = require("../../src/shared/Transfers/TransferDomain")

local function payload(items: any?, coins: number?): any
    return { items = items or {}, coins = coins or 0, creatures = {} }
end

local function record(): any
    return TransferDomain.newRecord(
        "t_1",
        "trade",
        { userId = 11, offer = payload({ item_wood = 2 }) },
        { userId = 22, offer = payload({}, 5) },
        100
    )
end

local function expectNoWrite(nextValue: any, label: string)
    Expect.equal(nextValue, nil, `{label} writes nothing`)
end

local function ledgerTransitions()
    local pending = record()
    Expect.truthy(TransferDomain.validateRecord(pending), "new record validates")
    Expect.equal(pending.state, "pending", "new record is pending")
    Expect.truthy(TransferDomain.isParty(pending, 11), "first party recognised")
    Expect.truthy(TransferDomain.isParty(pending, 22), "second party recognised")
    Expect.falsy(TransferDomain.isParty(pending, 33), "stranger is not a party")
    Expect.equal(TransferDomain.counterpartOffer(pending, 11).coins, 5, "11 receives 22's offer")
    Expect.equal(
        TransferDomain.counterpartOffer(pending, 22).items.item_wood,
        2,
        "22 receives 11's offer"
    )

    -- Validation.
    local bad = record()
    bad.parties = { 11, 11 }
    Expect.falsy(TransferDomain.validateRecord(bad), "same user twice rejected")
    bad = record()
    bad.parties = { 11 }
    Expect.falsy(TransferDomain.validateRecord(bad), "one party rejected")
    bad = record()
    bad.offers["22"] = nil
    Expect.falsy(TransferDomain.validateRecord(bad), "missing offer rejected")
    bad = record()
    bad.state = "completed"
    Expect.falsy(TransferDomain.validateRecord(bad), "non-pending new record rejected")
    bad = record()
    bad.parties = { 11, -3 }
    Expect.falsy(TransferDomain.validateRecord(bad), "invalid user id rejected")
    Expect.errorCode(
        select(2, TransferDomain.publish(nil, bad)),
        "invalid_request",
        "publish refuses an invalid record"
    )

    -- publish
    local stored, published = TransferDomain.publish(nil, pending)
    Expect.ok(published, "publish into empty ledger")
    Expect.truthy(stored ~= pending, "stored record is an independent copy")
    local again, republished = TransferDomain.publish(stored, pending)
    expectNoWrite(again, "republish")
    Expect.ok(republished, "republishing is idempotent")

    -- complete
    local completed, completeResult = TransferDomain.complete(stored, 150)
    Expect.ok(completeResult, "pending completes")
    Expect.equal(completed.state, "completed", "state is completed")
    Expect.equal(completed.completedAt, 150, "completion time recorded")
    Expect.equal(stored.state, "pending", "transform does not mutate its input")
    local completedAgain, secondComplete = TransferDomain.complete(completed, 160)
    expectNoWrite(completedAgain, "second complete")
    Expect.ok(secondComplete, "completing twice is idempotent")
    Expect.equal(completed.completedAt, 150, "completion time is not overwritten")
    Expect.errorCode(
        select(2, TransferDomain.complete(nil, 1)),
        "transfer_not_found",
        "completing a missing record"
    )

    -- cancel
    local cancelled, cancelResult = TransferDomain.cancel(stored, "t_1", 170)
    Expect.ok(cancelResult, "pending cancels")
    Expect.equal(cancelled.state, "cancelled", "state is cancelled")
    local cancelledAgain, secondCancel = TransferDomain.cancel(cancelled, "t_1", 180)
    expectNoWrite(cancelledAgain, "second cancel")
    Expect.ok(secondCancel, "cancelling twice is idempotent")
    Expect.errorCode(
        select(2, TransferDomain.cancel(completed, "t_1", 190)),
        "transfer_conflict",
        "a completed record cannot be cancelled"
    )
    Expect.errorCode(
        select(2, TransferDomain.complete(cancelled, 190)),
        "transfer_not_pending",
        "a cancelled record cannot be completed"
    )
    Expect.errorCode(
        select(2, TransferDomain.publish(cancelled, pending)),
        "transfer_not_pending",
        "a cancelled record cannot be republished"
    )

    -- A missing record becomes a tombstone that blocks a late publish.
    local tombstone, tombstoneResult = TransferDomain.cancel(nil, "t_9", 200)
    Expect.ok(tombstoneResult, "cancelling a missing record leaves a tombstone")
    Expect.equal(tombstone.state, "cancelled", "tombstone is cancelled")
    Expect.errorCode(
        select(2, TransferDomain.publish(tombstone, pending)),
        "transfer_not_pending",
        "publish after tombstone is refused"
    )
end

local function escrowHold()
    local profile = Fixtures.profile(100)
    profile.inventory.item_wood = 10
    profile.inventory.item_stone = 3
    profile.currencies.coins = 50
    Fixtures.addCreature(profile, "c_1", "creature_rockhorn")
    Fixtures.addCreature(profile, "c_2", "creature_mossling")

    local held = Expect.ok(
        EscrowDomain.hold(profile, "t_1", {
            items = { item_wood = 4, item_stone = 3 },
            coins = 20,
            creatures = { "c_1" },
        }, 100),
        "hold"
    )
    Expect.equal(held.items.item_wood, 4, "payload carries the items")
    Expect.equal(held.coins, 20, "payload carries the coins")
    Expect.truthy(held.creatures.c_1 ~= nil, "payload carries the creature")
    Expect.equal(profile.inventory.item_wood, 6, "items left the inventory")
    Expect.equal(profile.inventory.item_stone, nil, "an emptied stack is removed")
    Expect.equal(profile.currencies.coins, 30, "coins left the balance")
    Expect.equal(profile.creatures.c_1, nil, "creature left the roster")
    Expect.truthy(profile.creatures.c_2 ~= nil, "other creatures stay")
    Expect.truthy(ProfileSchema.validate(profile), "profile with a journal entry validates")
    Expect.equal(profile.transfers.t_1.createdAt, 100, "journal records the time")

    held.items.item_wood = 999
    Expect.equal(
        profile.transfers.t_1.offer.items.item_wood,
        4,
        "the journal does not alias the returned payload"
    )

    Expect.errorCode(
        EscrowDomain.hold(profile, "t_1", { items = { item_wood = 1 } }, 100),
        "transfer_conflict",
        "holding the same transfer twice"
    )

    -- Restoring puts everything back and is idempotent.
    local generate = function()
        return "c_new"
    end
    local restored = Expect.ok(EscrowDomain.restore(profile, "t_1", generate), "restore")
    Expect.equal(restored.settled, true, "restore settled the entry")
    Expect.equal(profile.inventory.item_wood, 10, "wood restored")
    Expect.equal(profile.inventory.item_stone, 3, "stone restored")
    Expect.equal(profile.currencies.coins, 50, "coins restored")
    Expect.truthy(profile.creatures.c_1 ~= nil, "creature restored under its own id")
    Expect.equal(profile.transfers.t_1, nil, "journal entry cleared")
    local second = Expect.ok(EscrowDomain.restore(profile, "t_1", generate), "second restore")
    Expect.equal(second.settled, false, "second restore is a no-op")
    Expect.equal(profile.inventory.item_wood, 10, "second restore does not duplicate")
end

local function escrowRefusals()
    local base = Fixtures.profile(100)
    base.inventory.item_wood = 5
    base.currencies.coins = 10
    Fixtures.addCreature(base, "c_idle", "creature_rockhorn")
    Fixtures.addCreature(base, "c_busy", "creature_rockhorn", "b_1")

    local function refused(offer: any, code: string, label: string)
        local profile = TableUtil.deepCopy(base)
        local before = TableUtil.deepCopy(profile)
        Expect.errorCode(EscrowDomain.hold(profile, "t_x", offer, 1), code, label)
        Expect.equal(next(profile.transfers), nil, `{label}: no journal entry`)
        Expect.equal(profile.inventory.item_wood, before.inventory.item_wood, `{label}: items`)
        Expect.equal(profile.currencies.coins, before.currencies.coins, `{label}: coins`)
        Expect.truthy(profile.creatures.c_idle ~= nil, `{label}: creature kept`)
    end

    refused({ items = { item_wood = 6 } }, "insufficient_resources", "too many items")
    refused({ coins = 11 }, "insufficient_currency", "too many coins")
    refused({ creatures = { "c_missing" } }, "creature_not_owned", "unowned creature")
    refused({ creatures = { "c_busy" } }, "creature_already_assigned", "assigned creature")
    refused({ creatures = { "c_idle", "c_idle" } }, "invalid_request", "duplicate creature")
    refused({ items = { item_wood = 0 } }, "invalid_request", "zero quantity")
    refused({ items = { item_wood = 1.5 } }, "invalid_request", "fractional quantity")
    refused({ items = { item_unknown = 1 } }, "invalid_request", "unknown item")
    refused({ coins = -1 }, "invalid_request", "negative coins")
    refused({ coins = 1.5 }, "invalid_request", "fractional coins")
    -- A valid item followed by an invalid one still changes nothing.
    refused(
        { items = { item_wood = 1 }, creatures = { "c_idle", "c_missing" } },
        "creature_not_owned",
        "partially valid offer"
    )

    -- Nothing at all is a valid offer (the receiving side of a gift).
    local profile = TableUtil.deepCopy(base)
    Expect.ok(EscrowDomain.hold(profile, "t_gift", {}, 1), "empty offer is allowed")
    Expect.truthy(profile.transfers.t_gift ~= nil, "empty offer is journaled")
end

local function escrowSettle()
    local profile = Fixtures.profile(100)
    profile.inventory.item_wood = 4
    Fixtures.addCreature(profile, "c_mine", "creature_rockhorn")
    Expect.ok(
        EscrowDomain.hold(
            profile,
            "t_1",
            { items = { item_wood = 4 }, creatures = { "c_mine" } },
            5
        ),
        "hold"
    )

    local incoming = {
        items = { item_stone = 2 },
        coins = 9,
        creatures = {
            c_theirs = {
                id = "c_theirs",
                speciesId = "creature_voltfox",
                level = 3,
                experience = 10,
                traits = {},
                genes = { vigor = 20, might = 1, focus = 31 },
                generation = 2,
                bornAt = 7,
                assignedBuildingId = "b_other_players_building",
            },
        },
    }
    local generate = function()
        return "c_fresh"
    end

    local settled = Expect.ok(
        EscrowDomain.settleCompleted(profile, "t_1", incoming, generate),
        "settle completed"
    )
    Expect.equal(settled.settled, true, "settled")
    Expect.equal(profile.inventory.item_wood, nil, "offered items are gone for good")
    Expect.equal(profile.inventory.item_stone, 2, "received items arrive")
    Expect.equal(profile.currencies.coins, 9, "received coins arrive")
    Expect.equal(profile.creatures.c_mine, nil, "offered creature is gone for good")
    local received = profile.creatures.c_theirs
    Expect.truthy(received ~= nil, "received creature arrives under its id")
    Expect.equal(received.assignedBuildingId, nil, "received creature is idle")
    Expect.equal(received.genes.focus, 31, "genes are carried across")
    Expect.equal(received.generation, 2, "generation is carried across")
    Expect.equal(profile.transfers.t_1, nil, "journal entry cleared")
    Expect.truthy(ProfileSchema.validate(profile), "settled profile validates")

    local replay = Expect.ok(
        EscrowDomain.settleCompleted(profile, "t_1", incoming, generate),
        "replayed settle"
    )
    Expect.equal(replay.settled, false, "replayed settle is a no-op")
    Expect.equal(profile.inventory.item_stone, 2, "replay does not double-credit items")
    Expect.equal(profile.currencies.coins, 9, "replay does not double-credit coins")

    -- A received creature whose id already exists is re-identified, never overwritten.
    local collision = Fixtures.profile(100)
    Fixtures.addCreature(collision, "c_theirs", "creature_rockhorn")
    Expect.ok(EscrowDomain.hold(collision, "t_2", {}, 5), "hold empty offer")
    Expect.ok(
        EscrowDomain.settleCompleted(collision, "t_2", incoming, generate),
        "settle with an id collision"
    )
    Expect.equal(collision.creatures.c_theirs.speciesId, "creature_rockhorn", "own creature kept")
    Expect.equal(
        collision.creatures.c_fresh.speciesId,
        "creature_voltfox",
        "newcomer re-identified"
    )
    Expect.equal(collision.creatures.c_fresh.id, "c_fresh", "re-identified record carries new id")
    Expect.truthy(
        ProfileSchema.validate(collision),
        "profile with a re-identified creature validates"
    )

    -- Receiving ignores capacity: the transfer is final.
    local crowded = Fixtures.profile(100)
    for index = 1, 30 do
        Fixtures.addCreature(crowded, `c_{index}`, "creature_rockhorn")
    end
    Expect.ok(EscrowDomain.hold(crowded, "t_3", {}, 5), "hold on a crowded roster")
    Expect.ok(
        EscrowDomain.settleCompleted(crowded, "t_3", incoming, generate),
        "settle is never refused for capacity"
    )
end

local function run()
    ledgerTransitions()
    escrowHold()
    escrowRefusals()
    escrowSettle()
end

return run
