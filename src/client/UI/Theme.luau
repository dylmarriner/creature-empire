local Theme = {
    Font = Enum.Font.Gotham,
    FontBold = Enum.Font.GothamBold,

    Background = Color3.fromRGB(28, 32, 40),
    Surface = Color3.fromRGB(40, 46, 58),
    SurfaceRaised = Color3.fromRGB(54, 62, 78),
    Border = Color3.fromRGB(78, 88, 108),
    Text = Color3.fromRGB(240, 242, 246),
    TextMuted = Color3.fromRGB(170, 178, 192),
    Accent = Color3.fromRGB(88, 170, 110),
    AccentDark = Color3.fromRGB(60, 128, 80),
    Warning = Color3.fromRGB(230, 170, 60),
    Danger = Color3.fromRGB(210, 82, 72),
    Coin = Color3.fromRGB(250, 208, 80),
    Gem = Color3.fromRGB(120, 200, 250),
    Disabled = Color3.fromRGB(90, 96, 108),

    Corner = UDim.new(0, 8),
    Padding = 8,
}

return table.freeze(Theme)
