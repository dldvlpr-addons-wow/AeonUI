-- tests/test_g_swing.lua : habillage du minuteur d'attaque (fond, bordure, texte, strate).
-- La texture passe par la page Médias, les barres par le mover.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("minuteur d'attaque : habillage appliqué, fond propre gardé au changement d'échelle, puis rendu au thème", function()
    reset()
    local Swing = NS.Modules:Get("swingtimer")
    local previousApi, previousVisibility = _G.C_SwingTimer, Swing.db.visibility
    _G.C_SwingTimer = { EnableRangeCheck = function() end, IsTargetWithinSwingRange = function() return true end }
    Swing.db.visibility = NS.Visibility.Spec()
    NS.Modules:SetEnabled("swingtimer", true)
    local container = _G.MuscaUISwingTimer
    truthy(container, "cadre construit")
    local bar
    for _, frame in ipairs(Mock.frames) do if frame.hand == "mainHand" then bar = frame end end
    truthy(bar and bar.backdropBg, "barre trouvée")
    truthy(bar.backdropBg:IsShown(), "fond affiché par défaut")
    local defaultStrata = container:GetFrameStrata()
    eq(defaultStrata, "MEDIUM", "strate d'origine")
    local defaultAnchors = bar:GetNumPoints()

    Swing.db.showBackground, Swing.db.showBorder, Swing.db.strata = false, false, "HIGH"
    NS.Modules:Refresh("swingtimer")
    eq(bar.backdropBg:IsShown(), false, "fond masqué")
    eq(bar.bg:IsShown(), false, "fond de barre masqué")
    for _, edge in pairs(bar.backdropEdges) do eq(edge:IsShown(), false, "bordure masquée") end
    eq(container:GetFrameStrata(), "HIGH", "strate")
    eq(bar:GetNumPoints(), defaultAnchors, "ancres remplacées, pas ajoutées")

    Swing.db.showBackground, Swing.db.showBorder, Swing.db.strata = true, true, "default"
    Swing.db.customBackground = true
    Swing.db.backgroundColor = { r = 0.9, g = 0.1, b = 0.2, a = 0.5 }
    NS.Modules:Refresh("swingtimer")
    eq(container:GetFrameStrata(), defaultStrata, "strate d'origine rendue")
    for _, edge in pairs(bar.backdropEdges) do truthy(edge:IsShown(), "bordure rendue") end
    eq(bar.backdropBg.color and bar.backdropBg.color[1], 0.9, "fond propre appliqué")
    NS:Fire("PIXEL_CHANGED")
    eq(bar.backdropBg.color and bar.backdropBg.color[1], 0.9, "fond propre gardé après PIXEL_CHANGED")

    Swing.db.customBackground = false
    NS.Modules:Refresh("swingtimer")
    eq(bar.backdropBg.color and bar.backdropBg.color[1], NS.db.theme.backdrop.r, "fond rendu au thème")
    NS.Modules:SetEnabled("swingtimer", false)
    Swing.db.visibility, _G.C_SwingTimer = previousVisibility, previousApi
end)
