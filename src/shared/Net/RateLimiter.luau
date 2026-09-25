-- Token-bucket rate limiter keyed by arbitrary strings (for example "userId:ActionName").
-- The clock is injected so behaviour is deterministic under test.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
    {} :: {
        _clock: () -> number,
        _buckets: { [string]: { tokens: number, updatedAt: number } },
    },
    RateLimiter
))

function RateLimiter.new(clock: () -> number): RateLimiter
    return setmetatable({
        _clock = clock,
        _buckets = {},
    }, RateLimiter)
end

-- Consumes one token for `key` if available. `burst` is the bucket size and `perSecond`
-- the refill rate.
function RateLimiter.allow(
    self: RateLimiter,
    key: string,
    burst: number,
    perSecond: number
): boolean
    local now = self._clock()
    local bucket = self._buckets[key]
    if bucket == nil then
        bucket = { tokens = burst, updatedAt = now }
        self._buckets[key] = bucket
    else
        local elapsed = math.max(0, now - bucket.updatedAt)
        bucket.tokens = math.min(burst, bucket.tokens + elapsed * perSecond)
        bucket.updatedAt = now
    end

    if bucket.tokens >= 1 then
        bucket.tokens -= 1
        return true
    end

    return false
end

-- Drops every bucket whose key starts with `prefix`, e.g. when a player leaves.
function RateLimiter.forgetPrefix(self: RateLimiter, prefix: string)
    for key in pairs(self._buckets) do
        if string.sub(key, 1, #prefix) == prefix then
            self._buckets[key] = nil
        end
    end
end

return RateLimiter
