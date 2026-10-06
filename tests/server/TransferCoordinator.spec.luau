local EscrowDomain = require("../../src/shared/Transfers/EscrowDomain")
local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local LedgerStore = require("../../src/shared/Transfers/LedgerStore")
local MemoryStore = require("../../src/server/Persistence/MemoryStore")
local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local TableUtil = require("../../src/shared/Util/TableUtil")
local TransferCoordinator = require("../../src/shared/Transfers/TransferCoordinator")
local TransferDomain = require("../../src/shared/Transfers/TransferDomain")

local USER_A = 1001
local USER_B = 2002
local CRASH = { crash = true }

-- A world holding two players' profiles with the failure model that matters for the protocol:
-- `memory` is what the server holds (lost in a crash), `durable` is what was last saved, and the
-- ledger store survives everything. Every profile commit, profile save and ledger write is a
-- numbered step that can be made to crash (before or after taking effect) or to fail.
local function newWorld()
    local world: any = {
        step = 0,
        faultAt = nil,
        faultMode = nil,
        durable = {},
        memory = {},
        now = 1000,
        ids = 0,
    }

    local profileA = Fixtures.profile(100)
    profileA.inventory.item_wood = 10
    profileA.currencies.coins = 50
    Fixtures.addCreature(profileA, "c_a1", "creature_rockhorn")
    local profileB = Fixtures.profile(100)
    profileB.inventory.item_stone = 8
    profileB.currencies.coins = 20
    Fixtures.addCreature(profileB, "c_b1", "creature_mossling")
    world.initial = { [USER_A] = profileA, [USER_B] = profileB }
    for userId, profile in pairs(world.initial) do
        world.durable[userId] = TableUtil.deepCopy(profile)
        world.memory[userId] = TableUtil.deepCopy(profile)
    end

    -- Runs one numbered step under the active fault, if any.
    local function faulty(run: () -> any, failure: any): any
        world.step += 1
        local mine = world.step
        local active = world.faultAt == mine
        if active and world.faultMode == "crashBefore" then
            error(CRASH)
        end
        if active and world.faultMode == "fail" then
            return failure
        end
        local result = run()
        if active and world.faultMode == "crashAfter" then
            error(CRASH)
        end
        return result
    end

    local store = MemoryStore.new()
    local adapter = {
        update = function(key: string, transform: (any) -> any, userIds: { number }?)
            local outcome = faulty(function()
                return { store.update(key, transform, userIds) }
            end, { false, "injected ledger failure" })
            return outcome[1], outcome[2]
        end,
    }
    world.ledgerStore = store
    world.ledger = LedgerStore.new(adapter, function()
        return world.now
    end)

    world.profiles = {
        mutate = function(userId: number, _label: string, fn: (any) -> any)
            return faulty(function()
                local draft = TableUtil.deepCopy(world.memory[userId])
                local result = fn(draft)
                if type(result) == "table" and result.ok == true then
                    assert(ProfileSchema.validate(draft), "mutation produced an invalid profile")
                    world.memory[userId] = draft
                end
                return result
            end, {
                ok = false,
                code = "internal_error",
                message = "injected commit failure",
            })
        end,
        read = function(userId: number)
            return world.memory[userId]
        end,
        save = function(userId: number)
            return faulty(function()
                world.durable[userId] = TableUtil.deepCopy(world.memory[userId])
                return true
            end, false)
        end,
    }

    function world.coordinator(staleAfterSeconds: number?)
        return TransferCoordinator.new({
            ledger = world.ledger,
            profiles = world.profiles,
            clock = function()
                return world.now
            end,
            generateId = function()
                world.ids += 1
                return `c_gen_{world.ids}`
            end,
            staleAfterSeconds = staleAfterSeconds,
        })
    end

    -- Simulates a server crash: unsaved profile changes are lost, the ledger is untouched.
    function world.crash()
        world.faultAt = nil
        for userId, saved in pairs(world.durable) do
            world.memory[userId] = TableUtil.deepCopy(saved)
        end
    end

    return world
end

local OFFER_A = { items = { item_wood = 4 }, coins = 10, creatures = { "c_a1" } }
local OFFER_B = { items = { item_stone = 3 }, coins = 0, creatures = { "c_b1" } }

local function swap(coordinator: any): any
    return coordinator:swap(
        "t_1",
        "trade",
        { userId = USER_A, offer = OFFER_A },
        { userId = USER_B, offer = OFFER_B }
    )
end

-- Everything a profile owns, journaled offers included, as a comparable string.
local function fingerprint(profile: any): string
    local parts = {}
    local function addPayload(tag: string, payload: any)
        for _, itemId in ipairs(TableUtil.sortedKeys(payload.items)) do
            table.insert(parts, `{tag}:{itemId}={payload.items[itemId]}`)
        end
        table.insert(parts, `{tag}:coins={payload.coins}`)
        for _, creatureId in ipairs(TableUtil.sortedKeys(payload.creatures)) do
            table.insert(parts, `{tag}:creature={creatureId}`)
        end
    end
    addPayload("own", {
        items = profile.inventory,
        coins = profile.currencies.coins,
        creatures = profile.creatures,
    })
    for _, id in ipairs(TableUtil.sortedKeys(profile.transfers)) do
        addPayload(`journal[{id}]`, profile.transfers[id].offer)
    end
    return table.concat(parts, ";")
end

local function settledFingerprints(world: any): (string, string)
    return fingerprint(world.memory[USER_A]), fingerprint(world.memory[USER_B])
end

local function expectNoJournals(world: any, label: string)
    for _, userId in ipairs({ USER_A, USER_B }) do
        Expect.equal(
            next(world.memory[userId].transfers),
            nil,
            `{label}: journal empty for {userId}`
        )
    end
end

-- Total of everything in both profiles (journals included), to prove nothing is created or lost.
local function totals(world: any): any
    local sum = { wood = 0, stone = 0, coins = 0, creatures = {} }
    for _, userId in ipairs({ USER_A, USER_B }) do
        local profile = world.memory[userId]
        sum.wood += profile.inventory.item_wood or 0
        sum.stone += profile.inventory.item_stone or 0
        sum.coins += profile.currencies.coins
        local function countCreatures(creatures: any)
            for id in pairs(creatures) do
                sum.creatures[id] = (sum.creatures[id] or 0) + 1
            end
        end
        countCreatures(profile.creatures)
        for _, entry in pairs(profile.transfers) do
            sum.wood += entry.offer.items.item_wood or 0
            sum.stone += entry.offer.items.item_stone or 0
            sum.coins += entry.offer.coins
            countCreatures(entry.offer.creatures)
        end
    end
    return sum
end

local function expectConserved(world: any, label: string)
    local sum = totals(world)
    Expect.equal(sum.wood, 10, `{label}: wood conserved`)
    Expect.equal(sum.stone, 8, `{label}: stone conserved`)
    Expect.equal(sum.coins, 70, `{label}: coins conserved`)
    Expect.equal(sum.creatures.c_a1, 1, `{label}: c_a1 exists exactly once`)
    Expect.equal(sum.creatures.c_b1, 1, `{label}: c_b1 exists exactly once`)
    local count = 0
    for _ in pairs(sum.creatures) do
        count += 1
    end
    Expect.equal(count, 2, `{label}: no other creature appeared`)
end

local function happyPath()
    local world = newWorld()
    local result = Expect.ok(swap(world.coordinator()), "swap")
    Expect.equal(result.state, "completed", "swap completes")

    local a = world.memory[USER_A]
    local b = world.memory[USER_B]
    Expect.equal(a.inventory.item_wood, 6, "A keeps the wood it did not offer")
    Expect.equal(a.inventory.item_stone, 3, "A receives stone")
    Expect.equal(a.currencies.coins, 40, "A paid 10 coins")
    Expect.equal(a.creatures.c_a1, nil, "A gave its creature")
    Expect.truthy(a.creatures.c_b1 ~= nil, "A received B's creature")
    Expect.equal(b.inventory.item_wood, 4, "B receives wood")
    Expect.equal(b.inventory.item_stone, 5, "B keeps the stone it did not offer")
    Expect.equal(b.currencies.coins, 30, "B received 10 coins")
    Expect.truthy(b.creatures.c_a1 ~= nil, "B received A's creature")
    expectNoJournals(world, "after swap")
    expectConserved(world, "after swap")

    -- The saved copies match the live ones, so a restart keeps the swap.
    world.crash()
    Expect.truthy(world.memory[USER_A].creatures.c_b1 ~= nil, "swap survives a restart")
    expectConserved(world, "after restart")

    local record = world.ledgerStore.read("transfer_t_1")
    Expect.equal(record.state, "completed", "ledger shows completed")

    -- Replaying settlement does nothing.
    local coordinator = world.coordinator()
    Expect.ok(coordinator:reconcile(USER_A), "reconcile A")
    Expect.ok(coordinator:reconcile(USER_B), "reconcile B")
    Expect.equal(world.memory[USER_A].currencies.coins, 40, "reconcile does not re-credit")
    expectConserved(world, "after reconcile")
end

local function refusedBeforeAnythingMoves()
    local world = newWorld()
    local before = fingerprint(world.memory[USER_A])
    local result = world.coordinator():swap(
        "t_1",
        "trade",
        { userId = USER_A, offer = { items = { item_wood = 99 } } },
        { userId = USER_B, offer = OFFER_B }
    )
    Expect.errorCode(result, "insufficient_resources", "A cannot afford the offer")
    Expect.equal(fingerprint(world.memory[USER_A]), before, "A is untouched")
    expectNoJournals(world, "refused swap")

    -- B cannot afford it: A's already-held offer is returned.
    local second = newWorld()
    local refused = second.coordinator():swap(
        "t_1",
        "trade",
        { userId = USER_A, offer = OFFER_A },
        { userId = USER_B, offer = { coins = 9999 } }
    )
    Expect.errorCode(refused, "insufficient_currency", "B cannot afford the offer")
    Expect.equal(
        fingerprint(second.memory[USER_A]),
        fingerprint(second.initial[USER_A]),
        "A's held offer was returned"
    )
    expectNoJournals(second, "second refused swap")
    expectConserved(second, "second refused swap")

    Expect.errorCode(
        world
            .coordinator()
            :swap("t_1", "trade", { userId = USER_A, offer = {} }, { userId = USER_A, offer = {} }),
        "invalid_request",
        "cannot trade with yourself"
    )
end

-- The core guarantee: whatever step a crash or failure lands on, once the profiles are reloaded
-- and reconciled, the result is all-or-nothing and nothing is duplicated or lost.
local function faultSweep()
    local baseline = newWorld()
    swap(baseline.coordinator())
    local totalSteps = baseline.step
    Expect.truthy(totalSteps >= 8, `the protocol has many steps to fault ({totalSteps})`)

    local untouchedA = fingerprint(newWorld().memory[USER_A])
    local untouchedB = fingerprint(newWorld().memory[USER_B])
    local swappedA = fingerprint(baseline.memory[USER_A])
    local swappedB = fingerprint(baseline.memory[USER_B])
    Expect.truthy(untouchedA ~= swappedA, "the swap changes A")

    local seenSwapped = false
    local seenUntouched = false

    for step = 1, totalSteps do
        for _, mode in ipairs({ "crashBefore", "crashAfter", "fail" }) do
            local label = `step {step} {mode}`
            local world = newWorld()
            world.faultAt = step
            world.faultMode = mode

            local success, thrown = pcall(swap, world.coordinator())
            if not success then
                Expect.truthy(
                    thrown == CRASH,
                    `{label}: only the injected crash is thrown ({thrown})`
                )
            end

            -- Restart: unsaved state is lost, then each profile reconciles on load. The record's
            -- age is irrelevant here (staleAfter 0), as is which server runs recovery.
            world.crash()
            local recovery = world.coordinator(0)
            Expect.ok(recovery:reconcile(USER_A), `{label}: reconcile A`)
            Expect.ok(recovery:reconcile(USER_B), `{label}: reconcile B`)

            expectNoJournals(world, label)
            expectConserved(world, label)

            local a, b = settledFingerprints(world)
            local isUntouched = a == untouchedA and b == untouchedB
            local isSwapped = a == swappedA and b == swappedB
            Expect.truthy(isUntouched or isSwapped, `{label}: all-or-nothing (got {a} | {b})`)
            seenUntouched = seenUntouched or isUntouched
            seenSwapped = seenSwapped or isSwapped

            -- Recovery is idempotent, and a second restart changes nothing.
            Expect.ok(recovery:reconcile(USER_A), `{label}: second reconcile A`)
            Expect.ok(recovery:reconcile(USER_B), `{label}: second reconcile B`)
            world.crash()
            local a2, b2 = settledFingerprints(world)
            Expect.truthy(a2 == a and b2 == b, `{label}: stable across a second restart`)
        end
    end

    Expect.truthy(seenSwapped, "some faults still end in a completed swap")
    Expect.truthy(seenUntouched, "some faults end with nothing transferred")
end

-- A crash after the profiles are saved but before the ledger is written leaves a journal entry
-- and no record. Recovery must tombstone the id so a late publish cannot resurrect the swap.
local function latePublishIsRefused()
    local world = newWorld()
    -- Step 1-2 hold, 3-4 save; step 5 is the first ledger write. Crash before it.
    world.faultAt = 5
    world.faultMode = "crashBefore"
    local success, thrown = pcall(swap, world.coordinator())
    Expect.falsy(success, "the swap crashed")
    Expect.truthy(thrown == CRASH, "with the injected crash")
    Expect.equal(world.ledgerStore.read("transfer_t_1"), nil, "nothing was published")

    world.crash()
    local recovery = world.coordinator(0)
    Expect.ok(recovery:reconcile(USER_A), "reconcile A")
    Expect.ok(recovery:reconcile(USER_B), "reconcile B")
    Expect.equal(world.ledgerStore.read("transfer_t_1").state, "cancelled", "tombstone written")
    expectConserved(world, "after tombstone")
    expectNoJournals(world, "after tombstone")

    -- The crashed server, still alive elsewhere, now tries to publish and complete.
    local stale = TransferDomain.newRecord(
        "t_1",
        "trade",
        { userId = USER_A, offer = { items = { item_wood = 4 }, coins = 10, creatures = {} } },
        { userId = USER_B, offer = { items = {}, coins = 0, creatures = {} } },
        1000
    )
    Expect.errorCode(world.ledger:publish(stale), "transfer_not_pending", "late publish refused")
    Expect.errorCode(world.ledger:complete("t_1"), "transfer_not_pending", "late complete refused")
    expectConserved(world, "after the late publish attempt")
end

-- Two servers race: one completes while another cancels a stale record. Exactly one wins and
-- both parties act on the same verdict.
local function completeAndCancelRace()
    for _, completeFirst in ipairs({ true, false }) do
        local label = if completeFirst then "complete first" else "cancel first"
        local world = newWorld()
        local coordinator = world.coordinator(0)

        -- Hold and publish by hand, as a crashed server would have left it.
        Expect.ok(
            world.profiles.mutate(USER_A, "hold", function(draft)
                return EscrowDomain.hold(draft, "t_1", OFFER_A, world.now)
            end),
            "hold A"
        )
        Expect.ok(
            world.profiles.mutate(USER_B, "hold", function(draft)
                return EscrowDomain.hold(draft, "t_1", OFFER_B, world.now)
            end),
            "hold B"
        )
        Expect.truthy(world.profiles.save(USER_A) and world.profiles.save(USER_B), "saves")
        local heldA = world.memory[USER_A].transfers.t_1.offer
        local heldB = world.memory[USER_B].transfers.t_1.offer
        Expect.ok(
            world.ledger:publish(
                TransferDomain.newRecord(
                    "t_1",
                    "trade",
                    { userId = USER_A, offer = heldA },
                    { userId = USER_B, offer = heldB },
                    world.now
                )
            ),
            "publish"
        )

        if completeFirst then
            Expect.ok(world.ledger:complete("t_1"), `{label}: complete wins`)
            Expect.errorCode(
                world.ledger:cancel("t_1"),
                "transfer_conflict",
                `{label}: cancel loses`
            )
        else
            Expect.ok(world.ledger:cancel("t_1"), `{label}: cancel wins`)
            Expect.errorCode(
                world.ledger:complete("t_1"),
                "transfer_not_pending",
                `{label}: complete loses`
            )
        end

        Expect.ok(coordinator:reconcile(USER_A), `{label}: reconcile A`)
        Expect.ok(coordinator:reconcile(USER_B), `{label}: reconcile B`)
        expectNoJournals(world, label)
        expectConserved(world, label)
        Expect.equal(
            world.memory[USER_A].creatures.c_b1 ~= nil,
            completeFirst,
            `{label}: A holds B's creature only if completed`
        )
    end
end

-- A pending record that is not stale is left alone; once it ages past the window it is cancelled.
local function pendingRecordsAreLeftUntilStale()
    local world = newWorld()
    world.faultAt = 6 -- crash after the ledger publish, before complete
    world.faultMode = "crashBefore"
    local success = pcall(swap, world.coordinator())
    Expect.falsy(success, "the swap crashed mid-way")
    Expect.equal(world.ledgerStore.read("transfer_t_1").state, "pending", "record is pending")

    world.crash()
    local patient = world.coordinator(120)
    local first = Expect.ok(patient:reconcile(USER_A), "reconcile within the window")
    Expect.equal(first.pending, 1, "a fresh pending record is left alone")
    Expect.equal(next(world.memory[USER_A].transfers) ~= nil, true, "A's offer stays in escrow")

    world.now += 121
    Expect.ok(patient:reconcile(USER_A), "reconcile after the window")
    Expect.ok(patient:reconcile(USER_B), "reconcile B after the window")
    expectNoJournals(world, "after the window")
    expectConserved(world, "after the window")
    Expect.equal(
        world.ledgerStore.read("transfer_t_1").state,
        "cancelled",
        "stale record cancelled"
    )
end

-- The ledger being unreachable never produces a wrong answer, only a pending one.
local function ledgerOutage()
    local world = newWorld()
    world.ledgerStore.setFailure("datastore down")
    local result = Expect.ok(swap(world.coordinator()), "swap reports, not throws")
    Expect.equal(result.state, "pending", "outage leaves the swap pending")
    expectConserved(world, "during the outage")
    Expect.truthy(next(world.memory[USER_A].transfers) ~= nil, "A's offer stays in escrow")

    world.ledgerStore.setFailure(nil)
    world.now += 500
    local recovery = world.coordinator(120)
    Expect.ok(recovery:reconcile(USER_A), "reconcile A after the outage")
    Expect.ok(recovery:reconcile(USER_B), "reconcile B after the outage")
    expectNoJournals(world, "after the outage")
    expectConserved(world, "after the outage")
end

local function run()
    happyPath()
    refusedBeforeAnythingMoves()
    faultSweep()
    latePublishIsRefused()
    completeAndCancelRace()
    pendingRecordsAreLeftUntilStale()
    ledgerOutage()
end

return run
