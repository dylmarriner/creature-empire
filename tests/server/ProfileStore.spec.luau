local Expect = require("../support/Expect")
local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local ProfileStore = require("../../src/server/Persistence/ProfileStore")
local MemoryStore = require("../../src/server/Persistence/MemoryStore")

local function harness(store: any, jobId: string, clockState: { now: number })
    local waits = {}
    local profileStore = ProfileStore.new({
        store = store,
        schema = ProfileSchema,
        jobId = jobId,
        clock = function()
            return clockState.now
        end,
        wait = function(seconds: number)
            table.insert(waits, seconds)
            clockState.now += seconds
        end,
        lockTimeoutSeconds = 600,
        loadAttempts = 3,
        saveAttempts = 2,
        retryDelaySeconds = 2,
    })
    return profileStore, waits
end

local function run()
    local clock = { now = 1000 }
    local store = MemoryStore.new()
    local serverA, waitsA = harness(store, "job_a", clock)
    local serverB, waitsB = harness(store, "job_b", clock)

    -- New players get a default profile and a session lock.
    local status, profile = serverA:load("player_1", 1)
    Expect.equal(status, "created", "new profile created")
    Expect.equal(profile.schemaVersion, ProfileSchema.CURRENT_VERSION, "default schema")
    local record = store.read("player_1")
    Expect.equal(record.format, 1, "record format")
    Expect.equal(record.session.jobId, "job_a", "session locked to loader")

    -- Saves persist while the lock is held.
    profile.inventory.item_wood = 42
    Expect.equal((serverA:save("player_1", 1, profile, false)), "saved", "save while locked")
    Expect.equal(store.read("player_1").profile.inventory.item_wood, 42, "saved data")

    -- Invalid profiles are never written.
    local invalid = ProfileSchema.createDefault(1000)
    invalid.currencies.coins = -5
    Expect.equal((serverA:save("player_1", 1, invalid, false)), "invalid", "invalid save refused")
    Expect.equal(store.read("player_1").profile.currencies.coins, 0, "invalid save not written")

    -- Another server waits for a live lock, then takes it over.
    local statusB, profileB = serverB:load("player_1", 1)
    Expect.equal(statusB, "loaded", "live lock eventually taken over")
    Expect.equal(profileB.inventory.item_wood, 42, "takeover loads latest data")
    Expect.equal(#waitsB, 2, "takeover waited for every retry")
    Expect.equal(store.read("player_1").session.jobId, "job_b", "lock moved")

    -- The previous holder can no longer write.
    profile.inventory.item_wood = 1
    Expect.equal(
        (serverA:save("player_1", 1, profile, true)),
        "session_lost",
        "stale server save refused"
    )
    Expect.equal(store.read("player_1").profile.inventory.item_wood, 42, "stale write discarded")

    -- Releasing lets the next server load immediately.
    Expect.equal((serverB:save("player_1", 1, profileB, true)), "saved", "release save")
    Expect.equal(store.read("player_1").session, nil, "lock released")
    local waitsBefore = #waitsA
    local statusA = serverA:load("player_1", 1)
    Expect.equal(statusA, "loaded", "released profile loads")
    Expect.equal(#waitsA, waitsBefore, "no waiting after release")

    -- Abandoned locks expire.
    store.write("player_2", {
        format = 1,
        profile = ProfileSchema.createDefault(1000),
        session = { jobId = "crashed", lockedAt = clock.now - 601 },
    })
    local waitsBeforeStale = #waitsB
    Expect.equal((serverB:load("player_2", 2)), "loaded", "stale lock ignored")
    Expect.equal(#waitsB, waitsBeforeStale, "stale lock needs no waiting")

    -- Unknown formats and invalid profiles are refused without being overwritten.
    store.write("player_3", { format = 99, profile = {} })
    Expect.equal((serverA:load("player_3", 3)), "invalid", "unknown format refused")
    Expect.equal(store.read("player_3").format, 99, "unknown format untouched")

    local corrupt = ProfileSchema.createDefault(1000)
    corrupt.inventory.item_wood = -1
    store.write("player_4", { format = 1, profile = corrupt })
    local corruptStatus, corruptProfile, detail = serverA:load("player_4", 4)
    Expect.equal(corruptStatus, "invalid", "invalid profile refused")
    Expect.equal(corruptProfile, nil, "no profile returned for invalid data")
    Expect.truthy(detail ~= nil, "invalid detail provided")
    Expect.equal(store.read("player_4").profile.inventory.item_wood, -1, "invalid data untouched")
    Expect.equal(store.read("player_4").session, nil, "invalid data not locked")

    -- Store outages fail loudly instead of defaulting.
    store.setFailure("DataStore unavailable")
    local outageStatus, outageProfile = serverA:load("player_5", 5)
    Expect.equal(outageStatus, "error", "outage is an error")
    Expect.equal(outageProfile, nil, "outage returns no profile")
    Expect.equal((serverA:save("player_1", 1, profile, false)), "error", "save outage is an error")
    store.setFailure(nil)
    Expect.equal(store.read("player_5"), nil, "outage created nothing")
end

return run
