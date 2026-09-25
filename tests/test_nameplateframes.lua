-- tests/test_nameplateframes.lua : plaques de nom AeonUI (étape 3).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local NPF = NS.Modules:Get("nameplateframes")

local function Enable() NS.Modules:SetEnabled("nameplateframes", true) end
local function Disable() NS.Modules:SetEnabled("nameplateframes", false) end
local function Enemy(token, fields)
    local unit = { name = "Loup", health = 300, healthMax = 400, level = 12, hostile = true }
    for k, v in pairs(fields or {}) do unit[k] = v end
    Mock.units[token] = unit
    return unit
end

test("plaques : montage à l'apparition, ancrée sur la plaque, démontage, réutilisation", function()
    reset()
    Enable()
    Enemy("nameplate1")
    local plate = Mock.AddNamePlate("nameplate1")
    local frame = NPF:GetFrame("nameplate1")
    truthy(frame, "cadre monté")
    truthy(frame:IsShown())
    local _, relTo = frame:GetPoint()
    eq(relTo, plate, "ancré sur la plaque")
    eq(frame.health:GetValue(), 300)
    eq(frame.name:GetText(), "Loup")
    eq(frame.level:GetText(), "12")
    eq(plate.UnitFrame:GetAlpha(), 0, "habillage Blizzard invisible")
    Mock.RemoveNamePlate("nameplate1")
    eq(NPF:GetFrame("nameplate1"), nil)
    eq(frame:IsShown(), false)
    Mock.namePlates["nameplate1"] = plate
    Mock.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(NPF:GetFrame("nameplate1"), frame, "même cadre réutilisé")
    Disable()
    eq(plate.UnitFrame:GetAlpha(), 1, "alpha rendu")
    truthy(Mock.FindPrinted("/reload"))
    Mock.namePlates = {}
end)

test("plaques : couleur de menace connue, réaction si secrète, allié sans barre", function()
    reset()
    Enable()
    Enemy("nameplate1", { threat = 3 })
    Mock.AddNamePlate("nameplate1")
    local frame = NPF:GetFrame("nameplate1")
    eq(frame.health.barColor[1], 0.85, "agro : rouge")
    Mock.units.nameplate1.threat = 2
    Mock.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
    eq(frame.health.barColor[1], 0.95, "menace 2 : orange")
    Mock.units.nameplate1.threat = Mock.SetSecret(9)
    Mock.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    eq(frame.health.barColor[1], 0.85, "secret : couleur de réaction (hostile rouge)")
    Mock.units.nameplate1.threat = 0
    Mock.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    eq(frame.health.barColor[1], 0.85, "pas de menace : réaction")
    Mock.units.nameplate2 = { name = "Garde", health = 10, healthMax = 10, level = 60, hostile = false }
    Mock.AddNamePlate("nameplate2")
    local ally = NPF:GetFrame("nameplate2")
    eq(ally.health:IsShown(), false, "allié : nom seul")
    eq(ally.name:GetText(), "Garde")
    NPF.db.friendlyHealth = true
    NS.Modules:Refresh("nameplateframes")
    truthy(ally.health:IsShown(), "option : barre alliée")
    NPF.db.friendlyHealth = false
    Disable()
    Mock.namePlates = {}
end)

test("plaques : surbrillance de la cible, incantation, débuffs, chevrons compatibles", function()
    reset()
    Enable()
    local enemy = Enemy("nameplate1")
    Enemy("nameplate2", { name = "Autre" })
    Mock.AddNamePlate("nameplate1")
    Mock.AddNamePlate("nameplate2")
    Mock.units.target = enemy
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    local frame, other = NPF:GetFrame("nameplate1"), NPF:GetFrame("nameplate2")
    eq(frame.border.top.color[1], NS.db.theme.accent.r, "cible : bordure d'accent")
    eq(frame:GetAlpha(), 1)
    eq(other:GetAlpha(), 0.7, "autre plaque atténuée")
    truthy(NS.Modules:Get("nameplates"):GetArrows():IsShown(), "chevrons toujours là")
    enemy.casting = { name = "Morsure", duration = 1.5 }
    Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    truthy(frame.castbar:IsShown())
    eq(frame.castbar.text:GetText(), "Morsure")
    enemy.casting = nil
    Mock.FireEvent("UNIT_SPELLCAST_STOP", "nameplate1")
    eq(frame.castbar:IsShown(), false)
    Mock.debuffs.nameplate1 = { { icon = "autre", duration = 5, expirationTime = Mock.now + 5, isFromPlayerOrPlayerPet = false },
                                { icon = "x", duration = 5, expirationTime = Mock.now + 5, isFromPlayerOrPlayerPet = true } }
    Mock.FireEvent("UNIT_AURA", "nameplate1")
    truthy(frame.auras and frame.auras.native == false, "repli maison (unité changeante)")
    truthy(frame.auras.buttons[1]:IsShown())
    eq(frame.auras.buttons[1].icon.texture, "x", "filtre « les miens » par défaut sur les plaques")
    truthy(not (frame.auras.buttons[2] and frame.auras.buttons[2]:IsShown()), "débuff d'un autre caché")
    Mock.units.target = nil
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    eq(other:GetAlpha(), 1, "sans cible : rien d'atténué")
    Disable()
    Mock.namePlates = {}
end)

test("plaques : ElvUI chargé, le module cède ; options construites", function()
    reset()
    Mock.loadedAddons.ElvUI = true
    Enable()
    eq(NPF.enabled, false)
    Mock.loadedAddons.ElvUI = nil
    NS.db.modules.nameplateframes.enabled = false
    Enable()
    NS.Options:BuildMain()
    Disable()
end)

test("plaques : taille des textes suit fontDelta", function()
    reset()
    NS.db.modules.nameplateframes.fontDelta = 2
    Enable()
    Enemy("nameplate1")
    Mock.AddNamePlate("nameplate1")
    local frame = NPF:GetFrame("nameplate1")
    local _, base = NS.Media:Font()
    local _, size = frame.name:GetFont()
    eq(size, base + 2, "nom : thème + 2")
    _, size = frame.level:GetFont()
    eq(size, base + 1, "niveau : un cran en dessous")
    NS.db.modules.nameplateframes.fontDelta = -1
    Disable()
end)
