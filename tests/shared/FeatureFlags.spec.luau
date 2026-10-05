local Expect = require("../support/Expect")
local FeatureFlags = require("../../src/shared/Config/FeatureFlags")

local function run()
    local flags = FeatureFlags.new()

    for name, default in pairs(FeatureFlags.Defaults) do
        Expect.equal(default, false, `{name} ships off`)
        Expect.equal(flags:isEnabled(name), false, `{name} starts off`)
    end

    local accepted, rejected = flags:applyOverrides({ trading = true, guilds = false })
    Expect.equal(accepted, 2, "two overrides accepted")
    Expect.equal(rejected, 0, "none rejected")
    Expect.equal(flags:isEnabled("trading"), true, "override switches a flag on")
    Expect.equal(flags:isEnabled("guilds"), false, "override may restate the default")
    Expect.equal(flags:isEnabled("breeding"), false, "untouched flags keep their default")

    -- Overrides replace the previous set: a flag removed from the store reverts.
    flags:applyOverrides({ breeding = true })
    Expect.equal(flags:isEnabled("trading"), false, "removed override reverts to default")
    Expect.equal(flags:isEnabled("breeding"), true, "new override applies")

    -- Bad entries are ignored and counted, never trusted.
    local _, junk = flags:applyOverrides({
        marketplace = "yes",
        unknown_system = true,
        [1] = true,
        store = true,
    })
    Expect.equal(junk, 3, "non-boolean, unknown and non-string keys rejected")
    Expect.equal(flags:isEnabled("marketplace"), false, "string value is not truthy")
    Expect.equal(flags:isEnabled("store"), true, "valid entry beside junk still applies")

    local _, notATable = flags:applyOverrides("garbage")
    Expect.equal(notATable, 1, "non-table data rejected")
    Expect.equal(flags:isEnabled("store"), false, "bad data clears overrides to defaults")

    flags:applyOverrides(nil)
    Expect.equal(flags:isEnabled("store"), false, "missing data means defaults")

    Expect.falsy(
        pcall(function()
            flags:isEnabled("not_a_flag")
        end),
        "unknown flag name is an error"
    )

    flags:applyOverrides({ guilds = true })
    local snapshot = flags:snapshot()
    Expect.equal(snapshot.guilds, true, "snapshot reflects overrides")
    Expect.equal(snapshot.trading, false, "snapshot reflects defaults")
end

return run
