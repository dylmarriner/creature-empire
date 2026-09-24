--[[
    Session-locked profile persistence over an abstract key/value store.

    Stored record format (format 1):
        {
            format = 1,
            profile = <PlayerProfile>,
            session = { jobId = string, lockedAt = number } | nil,
        }

    Guarantees:
    - A load never replaces an unreadable or invalid record with defaults; it fails instead.
    - Only one server holds the session lock for a key. Saves from a server that lost the
      lock are refused, so two servers can never interleave writes to one profile.
    - A lock older than `lockTimeoutSeconds` is treated as abandoned (crashed server). A live
      lock is waited on for `loadAttempts` retries and then taken over; the previous holder
      discovers the takeover on its next save and stops writing.
    - Only schema-valid profiles are written.

    The store adapter must provide:
        update(key, transform, userIds) -> (success: boolean, errorMessage: string?)
    where transform(oldValue) returns the new value, or nil to cancel the write. The
    transform may run more than once and must not yield.
]]

local RECORD_FORMAT = 1

export type StoreAdapter = {
    update: (
        key: string,
        transform: (old: any) -> any,
        userIds: { number }?
    ) -> (boolean, string?),
}

export type Schema = {
    createDefault: (now: number) -> any,
    validate: (profile: any) -> (boolean, string?),
    migrate: (profile: any) -> (any, string?),
}

export type Options = {
    store: StoreAdapter,
    schema: Schema,
    jobId: string,
    clock: () -> number,
    wait: (seconds: number) -> (),
    lockTimeoutSeconds: number?,
    loadAttempts: number?,
    saveAttempts: number?,
    retryDelaySeconds: number?,
}

export type LoadStatus = "loaded" | "created" | "invalid" | "error"
export type SaveStatus = "saved" | "session_lost" | "invalid" | "error"

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type ProfileStore = typeof(setmetatable(
    {} :: {
        _store: StoreAdapter,
        _schema: Schema,
        _jobId: string,
        _clock: () -> number,
        _wait: (seconds: number) -> (),
        _lockTimeoutSeconds: number,
        _loadAttempts: number,
        _saveAttempts: number,
        _retryDelaySeconds: number,
    },
    ProfileStore
))

function ProfileStore.new(options: Options): ProfileStore
    assert(type(options.jobId) == "string" and options.jobId ~= "", "jobId is required")
    return setmetatable({
        _store = options.store,
        _schema = options.schema,
        _jobId = options.jobId,
        _clock = options.clock,
        _wait = options.wait,
        _lockTimeoutSeconds = options.lockTimeoutSeconds or 1800,
        _loadAttempts = options.loadAttempts or 5,
        _saveAttempts = options.saveAttempts or 3,
        _retryDelaySeconds = options.retryDelaySeconds or 3,
    }, ProfileStore)
end

local function isHeldByOther(session: any, jobId: string, now: number, timeout: number): boolean
    if type(session) ~= "table" or session.jobId == jobId then
        return false
    end
    local lockedAt = session.lockedAt
    if type(lockedAt) ~= "number" or lockedAt ~= lockedAt then
        return false
    end
    return now - lockedAt < timeout
end

-- Loads and locks the profile stored under `key`.
-- Returns (status, profile?, detail?). Only "loaded" and "created" return a profile.
function ProfileStore.load(
    self: ProfileStore,
    key: string,
    userId: number
): (LoadStatus, any, string?)
    local lastDetail: string? = nil

    for attempt = 1, self._loadAttempts do
        local takeOver = attempt == self._loadAttempts
        local outcome: string? = nil
        local loadedProfile: any = nil
        local detail: string? = nil

        local success, storeError = self._store.update(key, function(old: any): any
            local now = self._clock()
            outcome = nil
            loadedProfile = nil
            detail = nil

            if old == nil then
                local profile = self._schema.createDefault(now)
                outcome = "created"
                loadedProfile = profile
                return {
                    format = RECORD_FORMAT,
                    profile = profile,
                    session = { jobId = self._jobId, lockedAt = now },
                }
            end

            if type(old) ~= "table" or old.format ~= RECORD_FORMAT then
                outcome = "invalid"
                detail = "stored record has an unknown format"
                return nil
            end

            if
                not takeOver
                and isHeldByOther(old.session, self._jobId, now, self._lockTimeoutSeconds)
            then
                outcome = "locked"
                return nil
            end

            local migrated, reason = self._schema.migrate(old.profile)
            if migrated == nil then
                outcome = "invalid"
                detail = reason or "stored profile failed validation"
                return nil
            end

            outcome = "loaded"
            loadedProfile = migrated
            return {
                format = RECORD_FORMAT,
                profile = migrated,
                session = { jobId = self._jobId, lockedAt = now },
            }
        end, { userId })

        if success then
            if outcome == "loaded" or outcome == "created" then
                return outcome :: LoadStatus, loadedProfile, nil
            elseif outcome == "invalid" then
                return "invalid", nil, detail
            end
            lastDetail = "profile is locked by another server"
        else
            lastDetail = storeError or "store update failed"
        end

        if attempt < self._loadAttempts then
            self._wait(self._retryDelaySeconds * attempt)
        end
    end

    return "error", nil, lastDetail
end

-- Writes `profile` if this server still holds the session lock. With `release`, the lock is
-- cleared so another server can load immediately.
function ProfileStore.save(
    self: ProfileStore,
    key: string,
    userId: number,
    profile: any,
    release: boolean
): (SaveStatus, string?)
    local valid, reason = self._schema.validate(profile)
    if not valid then
        return "invalid", reason
    end

    local lastDetail: string? = nil
    for attempt = 1, self._saveAttempts do
        local outcome: string? = nil

        local success, storeError = self._store.update(key, function(old: any): any
            local now = self._clock()
            outcome = nil

            if
                type(old) ~= "table"
                or old.format ~= RECORD_FORMAT
                or type(old.session) ~= "table"
                or old.session.jobId ~= self._jobId
            then
                outcome = "session_lost"
                return nil
            end

            outcome = "saved"
            return {
                format = RECORD_FORMAT,
                profile = profile,
                session = if release then nil else { jobId = self._jobId, lockedAt = now },
            }
        end, { userId })

        if success then
            if outcome == "saved" then
                return "saved", nil
            elseif outcome == "session_lost" then
                return "session_lost", "profile session is held by another server"
            end
            lastDetail = "store update produced no outcome"
        else
            lastDetail = storeError or "store update failed"
        end

        if attempt < self._saveAttempts then
            self._wait(self._retryDelaySeconds * attempt)
        end
    end

    return "error", lastDetail
end

return ProfileStore
