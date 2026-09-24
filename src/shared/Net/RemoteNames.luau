-- Server-to-client RemoteEvents under ReplicatedStorage.Remotes.
return table.freeze({
    -- (requestId: number, actionName: string, result: { ok, code?, message? })
    ActionResult = "ActionResult",
    -- (snapshot: table) authoritative view of the player's own profile
    StateSnapshot = "StateSnapshot",
    -- (message: { kind: string, text: string }) world interaction feedback
    Notify = "Notify",
})
