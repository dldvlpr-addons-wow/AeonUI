-- tests/test_m10_cadres.lua : lot M10 (cadres d'unité et barres de ressources).
-- Lissage des barres, filtre de débuffs des barres d'auras, guide de mouvement du tir automatique,
-- surcouche de dissipation sur la barre de vie.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local L = NS.L

test("lissage des barres : interpolation passée seulement avec smoothBars", function()
    reset()
    local calls = {}
    local bar = { SetValue = function(_, ...) calls[#calls + 1] = { n = select("#", ...), ... } end }
    local Elements = NS.UnitFrameElements
    Elements.SetBarValue(bar, 50, { smoothBars = false })
    Elements.SetBarValue(bar, 60, nil)
    Elements.SetBarValue(bar, 70, { smoothBars = true })
    eq(calls[1].n, 1, "sans option : valeur seule")
    eq(calls[2].n, 1, "sans réglage : valeur seule")
    eq(calls[3].n, 2, "lissé : interpolation passée")
    eq(calls[3][2], Enum.StatusBarInterpolation.ExponentialEaseOut)
    eq(calls[3][1], 70)
end)

test("barres d'auras : filtre des débuffs (tous, les miens)", function()
    reset()
    local AuraBars = NS.Modules:Get("aurabars")
    local previous = C_UnitAuras.GetAuraDataByIndex
    local auras = {
        HELPFUL = { { name = "Might", icon = 1, duration = 100, expirationTime = Mock.now + 50 } },
        HARMFUL = { { name = "Mine", icon = 2, duration = 100, expirationTime = Mock.now + 50, isFromPlayerOrPlayerPet = true },
                    { name = "Other", icon = 3, duration = 100, expirationTime = Mock.now + 50, isFromPlayerOrPlayerPet = false } } }
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        return unit == "player" and auras[filter] and auras[filter][index] or nil
    end
    NS.Modules:SetEnabled("aurabars", true)
    local db = AuraBars.db
    local function Names()
        local names = {}
        for _, entry in ipairs(AuraBars.Collect()) do names[#names + 1] = entry.name end
        table.sort(names)
        return table.concat(names, ",")
    end
    eq(db.debuffFilter, "all", "défaut : comportement d'avant")
    eq(Names(), "Might,Mine,Other")
    local lists, saved = NS.db.auraLists, NS.db.auraLists and NS.db.auraLists.blacklist
    auras.HARMFUL[2].spellId = 999
    if lists then lists.blacklist = "999" end
    eq(Names(), "Might,Mine,Other", "défaut : liste noire non appliquée, comme avant")
    if lists then lists.blacklist = saved end
    db.debuffFilter = "mine"
    eq(Names(), "Might,Mine", "buffs intacts, débuff d'autrui écarté")
    db.debuffFilter = "all"
    NS.Modules:SetEnabled("aurabars", false)
    C_UnitAuras.GetAuraDataByIndex = previous
end)

test("minuteur d'attaque : guide de mouvement sur la barre à distance", function()
    reset()
    local Swing = NS.Modules:Get("swingtimer")
    local previousApi, previousVisibility, previousTypes = _G.C_SwingTimer, Swing.db.visibility, Enum.PlayerSwingType
    _G.C_SwingTimer = { EnableRangeCheck = function() end, IsTargetWithinSwingRange = function() return true end }
    Enum.PlayerSwingType = previousTypes or { MainHand = 0, OffHand = 1, Ranged = 2 }
    Swing.db.visibility = NS.Visibility.Spec()
    Swing.db.moveGuide = true
    NS.Modules:SetEnabled("swingtimer", true)
    local bar
    for _, frame in ipairs(Mock.frames) do if frame.hand == "ranged" then bar = frame end end
    truthy(bar and bar.guide, "barre à distance et guide")
    local ranged, still = Swing.db.rangedColor, Swing.db.stillColor
    Mock.FireEvent("PLAYER_SWING", 2, Enum.PlayerSwingType.Ranged)
    Mock.Advance(0.5)
    eq(bar.guide:GetText(), L.SWING_GUIDE_GO, "début du tir : bouger")
    eq(select(1, bar:GetStatusBarColor()), ranged.r)
    Mock.Advance(1.2)
    eq(bar.guide:GetText(), L.SWING_GUIDE_STILL, "dernière demi-seconde : immobile")
    eq(select(1, bar:GetStatusBarColor()), still.r)
    Mock.Advance(0.5)
    eq(bar.guide:GetText(), "", "tir parti : guide vidé")
    eq(select(1, bar:GetStatusBarColor()), ranged.r, "couleur rendue")

    Swing.db.moveGuide = false
    Mock.FireEvent("PLAYER_SWING", 2, Enum.PlayerSwingType.Ranged)
    Mock.Advance(1.8)
    eq(bar.guide:GetText(), "", "option coupée : aucun guide")
    eq(select(1, bar:GetStatusBarColor()), ranged.r)
    NS.Modules:SetEnabled("swingtimer", false)
    Swing.db.visibility, _G.C_SwingTimer, Enum.PlayerSwingType = previousVisibility, previousApi, previousTypes
end)

test("cadres d'unité : surcouche de dissipation posée par le moteur d'auras", function()
    reset()
    local previous = Mock.auraContainer
    Mock.auraContainer = true
    local Elements = NS.UnitFrameElements
    local frame = CreateFrame("Frame")
    frame.health = CreateFrame("StatusBar", nil, frame)
    frame.health:SetHeight(20)
    frame.unit = "target"
    frame.global = { dispelOverlay = false }
    Elements.UpdateDispelOverlay(frame)
    eq(frame.dispelEngine, nil, "option coupée : aucun conteneur")

    frame.global = { dispelOverlay = true, dispelOverlayMode = "mine", dispelOverlayAlpha = 0.5,
                     dispelOverlayIcon = true }
    Elements.UpdateDispelOverlay(frame, true)
    local engine = frame.dispelEngine
    truthy(engine and engine.slots.dispel, "emplacement déclaré")
    eq(engine.slots.dispel.filter, "HARMFUL|RAID", "les miens : dissipables par le joueur")
    eq(engine.unit, "target")
    truthy(engine:GetNumPoints() > 0, "conteneur ancré sur la vie")
    truthy(engine.slots.dispel.button:GetNumPoints() > 0, "bouton ancré")
    local parts = frame.dispelParts
    truthy(parts, "voile et icône créés")
    eq(parts.fill:GetAlpha(), 0.5)
    truthy(parts.mark:IsShown(), "icône affichée")
    eq(parts.icon:GetWidth(), 16, "icône à la hauteur de la vie - 4")
    eq(engine.slots.dispel.button.SetIcon, parts.icon, "icône du débuff posée par le moteur")

    frame.global.dispelOverlayMode, frame.global.dispelOverlayIcon = "all", false
    Elements.UpdateDispelOverlay(frame)
    eq(engine.slots.dispel.filter, "HARMFUL", "tous : tout débuff typé")
    truthy(engine.slots.dispel.candidates and engine.slots.dispel.candidates.includeDispelTypes, "types filtrés")
    eq(parts.mark:IsShown(), false, "icône masquée")

    frame.global.dispelOverlay = false
    Elements.UpdateDispelOverlay(frame)
    eq(engine:IsShown(), false, "option coupée : conteneur masqué")
    Mock.auraContainer = previous
end)

test("lissage des barres : pas de glissement au changement d'unité (UpdateAll)", function()
    reset()
    local Elements = NS.UnitFrameElements
    local seen = {}
    local saved = { Elements.UpdateHealth, Elements.UpdatePower }
    local original = Elements.SetBarValue
    local frame = { global = { smoothBars = true } }
    -- UpdateHealth / UpdatePower lisent frame.snapBars : relevé pendant UpdateAll, sans le reste.
    Elements.UpdateHealth = function(f) seen.health = f.snapBars end
    Elements.UpdatePower = function(f) seen.power = f.snapBars end
    pcall(Elements.UpdateAll, frame)
    Elements.UpdateHealth, Elements.UpdatePower = saved[1], saved[2]
    eq(seen.health, true, "vie posée sans interpolation")
    eq(seen.power, true, "puissance posée sans interpolation")
    eq(frame.snapBars, nil, "drapeau levé après la vie et la puissance")
    eq(Elements.SetBarValue, original)
end)
