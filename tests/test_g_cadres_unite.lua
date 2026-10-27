-- tests/test_g_cadres_unite.lua : cadres d'unité (lot G) : nom > cible, décimales du pourcentage,
-- strate, couleur de puissance, surbrillance, portrait de classe, indicateurs, icône d'incantation, combo.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Elements = NS.UnitFrameElements
local UF = NS.Modules:Get("unitframes")

local function Enable() NS.Modules:SetEnabled("unitframes", true) end
local function Disable() NS.Modules:SetEnabled("unitframes", false) end
local function Target()
    Mock.units.target = { name = "Cible", health = 500, healthMax = 1000, power = 20, powerMax = 100, level = 30,
                          hostile = true, class = "WARRIOR", isPlayer = true }
    Mock.RefreshUnitWatch()
end
local function Anchors(region, relativeTo, point)
    for _, anchor in ipairs(region.points or {}) do
        if (not point or anchor[1] == point) and anchor[2] == relativeTo then return anchor end
    end
end

test("cadres d'unité : valeurs par défaut des nouvelles options = rendu d'origine", function()
    reset()
    local db = NS.db.modules.unitframes
    local cfg = db.units.player
    eq(cfg.strata, "LOW"); eq(cfg.nameTarget, false); eq(cfg.powerColorCustom, false)
    eq(cfg.targetHighlight, false); eq(cfg.portraitStyle, "portrait"); eq(cfg.combatIconSize, 0)
    eq(db.percentDecimals, 0); eq(db.castIcon, "left")
end)

test("cadres d'unité : nom > cible seulement si l'option est cochée", function()
    reset()
    Enable()
    Target()
    Mock.units.targettarget = { name = "Testeur", health = 1, healthMax = 1 }
    Mock.units.targettargettarget = nil
    Mock.units.targettarget = { name = "Ami" }   -- « <unité>target » de la cible
    local frame = UF:GetFrame("target")
    local cfg = NS.db.modules.unitframes.units.target
    Elements.UpdateName(frame)
    eq(frame.name.text, "Cible", "option coupée")
    cfg.nameTarget = true
    -- Mock : la cible de la cible s'appelle "targettarget".
    local original = _G.UnitName
    _G.UnitName = function(unit) if unit == "targettarget" then return "Ami" end return original(unit) end
    Elements.UpdateName(frame)
    eq(frame.name.text, "Cible > Ami", "nom > cible")
    _G.UnitName = function(unit) if unit == "targettarget" then return nil end return original(unit) end
    Elements.UpdateName(frame)
    eq(frame.name.text, "Cible", "sans cible : nom seul")
    _G.UnitName = original
    cfg.nameTarget = false
    Disable()
end)

test("cadres d'unité : décimales du pourcentage de vie, jamais pour les autres modules", function()
    reset()
    Enable()
    Target()
    local frame = UF:GetFrame("target")
    local db = NS.db.modules.unitframes
    db.units.target.healthFormat = "[perc]"
    db.percentDecimals = 1
    Mock.units.target.health, Mock.units.target.healthMax = 333, 1000
    Elements.UpdateHealthTexts(frame)
    eq(frame.health.text.text, "33.3%", "une décimale")
    eq(Elements.percentDecimals, nil, "réglage retiré après les textes")
    eq(T.RenderText("target", "health", "[perc]"), "33%", "hors cadres d'unité : entier")
    db.percentDecimals = 0
    db.units.target.healthFormat = ""
    Disable()
end)

test("cadres d'unité : strate, couleur de puissance, portrait de classe, combo, icône d'incantation", function()
    reset()
    Enable()
    Target()
    local db = NS.db.modules.unitframes
    local cfg = db.units.target
    local frame = UF:GetFrame("target")
    eq(frame.strata, "LOW")
    cfg.strata = "HIGH"
    NS.Modules:Refresh("unitframes")
    eq(frame.strata, "HIGH", "strate reposée au rafraîchissement")
    cfg.strata = "LOW"

    cfg.powerColorCustom, cfg.powerColor = true, { r = 0.1, g = 0.2, b = 0.3 }
    local color
    frame.power.SetStatusBarColor = function(_, r, g, b) color = { r, g, b } end
    Elements.UpdatePower(frame)
    eq(color[1], 0.1); eq(color[3], 0.3)
    cfg.powerColorCustom = false

    _G.SetPortraitTexture = function() end   -- absent du mock
    _G.CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0.25, 0.5 } }
    cfg.portrait, cfg.portraitStyle = true, "class"
    local coords
    frame.portrait.texture.SetTexCoord = function(_, ...) coords = { ... } end
    Elements.UpdatePortrait(frame)
    eq(coords[4], 0.5, "cases de la classe")
    cfg.portraitStyle = "portrait"
    Elements.UpdatePortrait(frame)
    eq(coords[1], 0.15, "portrait ordinaire : coordonnées d'origine")
    _G.CLASS_ICON_TCOORDS, _G.SetPortraitTexture = nil, nil
    cfg.portrait = false

    cfg.combo, cfg.comboAbove, cfg.comboHeight = true, true, 9
    NS.Modules:Refresh("unitframes")
    truthy(Anchors(frame.combo, frame, "BOTTOMLEFT"), "combo posé au-dessus du cadre")
    eq(frame.aurasAnchor, frame.castbar.enabled and frame.castbar or frame, "le reste ne descend pas sous le combo")
    -- Pas de chevauchement : le texte de menace et les auras du dessus partent au-dessus du combo.
    local threat = Anchors(frame.threat, frame, "BOTTOMRIGHT")
    truthy(threat[5] >= NS.Pixel:Scale(9) + NS.Pixel:Scale(4), "menace au-dessus du combo")
    cfg.auras, cfg.aurasAbove = true, true
    NS.Modules:Refresh("unitframes")
    local auras = Anchors(frame.auras, frame, "BOTTOMLEFT")
    truthy(auras[5] >= NS.Pixel:Scale(9) + NS.Pixel:Scale(4), "auras au-dessus du combo")
    cfg.auras, cfg.aurasAbove = false, false
    cfg.combo, cfg.comboAbove, cfg.comboHeight = false, false, 0

    NS.db.modules.unitframes.castIcon = "none"
    NS.Modules:Refresh("unitframes")
    local noIconWidth = frame.castbar.text.width
    NS.db.modules.unitframes.castIcon = "left"
    NS.Modules:Refresh("unitframes")
    truthy(noIconWidth > frame.castbar.text.width, "sans icône, le nom du sort récupère la largeur de l'icône")
    NS.db.modules.unitframes.castIcon = "none"
    NS.Modules:Refresh("unitframes")
    eq(frame.castbar.iconFrame:IsShown(), false, "icône masquée")
    NS.db.modules.unitframes.castIcon = "right"
    NS.Modules:Refresh("unitframes")
    eq(frame.castbar.iconFrame:IsShown(), true)
    truthy(Anchors(frame.castbar.iconFrame, frame.castbar, "LEFT"), "icône à droite de la barre")
    NS.db.modules.unitframes.castIcon = "left"
    Disable()
end)

test("cadres d'unité : taille et décalage des indicateurs (0 = taille d'origine)", function()
    reset()
    Enable()
    Target()
    local cfg = NS.db.modules.unitframes.units.target
    local frame = UF:GetFrame("target")
    local defaultSize = frame.raidIcon.width
    truthy(defaultSize and defaultSize > 0, "taille d'origine")
    cfg.raidIconSize, cfg.raidIconOffsetX = 30, 5
    NS.Modules:Refresh("unitframes")
    eq(frame.raidIcon.width, NS.Pixel:Scale(30), "taille réglée")
    local anchors = frame.raidIcon.points
    eq(anchors[#anchors][4], NS.Pixel:Scale(5), "décalage horizontal appliqué à la dernière ancre")
    cfg.raidIconSize, cfg.raidIconOffsetX = 0, 0
    NS.Modules:Refresh("unitframes")
    eq(frame.raidIcon.width, defaultSize, "retour à la taille d'origine")
    Disable()
end)

test("cadres d'unité : surbrillance de cible et de survol, retirée quand l'état cesse", function()
    reset()
    Enable()
    Target()
    Mock.units.focus = Mock.units.target   -- même unité que la cible
    Mock.RefreshUnitWatch()
    local focus = UF:GetFrame("focus")
    local cfg = NS.db.modules.unitframes.units.focus
    Elements.UpdateHighlight(focus)
    eq(focus.highlight, nil, "option coupée : rien créé")
    cfg.targetHighlight = true
    Elements.UpdateHighlight(focus)
    eq(focus.highlight:IsShown(), true, "le focus est la cible")
    Mock.units.focus = { name = "Autre" }
    Elements.UpdateHighlight(focus)
    eq(focus.highlight:IsShown(), false, "n'est plus la cible")
    cfg.targetHighlight, cfg.hoverHighlight = false, true
    focus:GetScript("OnEnter")(focus)
    eq(focus.highlight:IsShown(), true, "survol")
    focus:GetScript("OnLeave")(focus)
    eq(focus.highlight:IsShown(), false, "fin du survol")
    cfg.hoverHighlight = false
    Disable()
end)

test("cadres d'unité : texte de latence et habillage de la barre d'incantation", function()
    reset()
    Enable()
    local db = NS.db.modules.unitframes
    local player = Mock.units.player
    local bar = UF:GetFrame("player").castbar
    player.casting = { name = "Éclair", duration = 3, startTime = 1000000, endTime = 1003000 }
    db.castLatency = true
    Mock.FireEvent("UNIT_SPELLCAST_START", "player")
    truthy(bar.latency:IsShown(), "zone de latence")
    eq(bar.latencyText:IsShown(), false, "texte coupé par défaut")
    db.castLatencyText = true
    Mock.FireEvent("UNIT_SPELLCAST_START", "player")
    eq(bar.latencyText:IsShown(), true, "texte affiché")
    truthy(bar.latencyText.text:find(" ms$"), "format en ms")
    player.casting = nil
    db.castLatencyText = false

    -- Défauts : rendu d'origine.
    eq(bar.bg:IsShown(), true); eq(bar.backdropEdges.top:IsShown(), true); eq(bar:GetAlpha(), 1)
    db.castBackground, db.castBorder, db.castAlpha, db.castStrata = false, false, 0.5, "HIGH"
    NS.Modules:Refresh("unitframes")
    eq(bar.bg:IsShown(), false, "fond masqué"); eq(bar.backdropBackground:IsShown(), false)
    eq(bar.backdropEdges.top:IsShown(), false, "bordure masquée")
    eq(bar:GetAlpha(), 0.5, "opacité")
    eq(bar:GetFrameStrata(), "HIGH", "strate")
    db.castBackground, db.castBorder, db.castAlpha, db.castStrata = true, true, 1, ""
    NS.Modules:Refresh("unitframes")
    eq(bar.bg:IsShown(), true, "fond rendu"); eq(bar:GetAlpha(), 1)
    eq(bar:GetFrameStrata(), bar.detached and UIParent:GetFrameStrata() or UF:GetFrame("player"):GetFrameStrata(), "strate d origine rendue")
    eq(bar.backdropBackground:IsShown(), true, "fond du cadre rendu"); eq(bar.backdropEdges.top:IsShown(), true, "bordure rendue")
    eq(bar:GetFrameStrata(), "MEDIUM", "strate en dur (joueur détaché : UIParent)")
    Disable()
end)
