-- tests/test_g_plaques.lua : réglages G des plaques MuscaUI (nom, incantation, recouvrements, bordure, neutres).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local NPF = NS.Modules:Get("nameplateframes")

local function Mount(fields)
    reset()
    NS.Modules:SetEnabled("nameplateframes", true)
    local unit = { name = "Grand Loup Noir", health = 300, healthMax = 400, level = 12, hostile = true }
    for k, v in pairs(fields or {}) do unit[k] = v end
    Mock.units.nameplate1 = unit
    Mock.AddNamePlate("nameplate1")
    return unit, NPF:GetFrame("nameplate1")
end
local function Remount() NS.Modules:Refresh("nameplateframes") return NPF:GetFrame("nameplate1") end

test("plaques G : format du nom premier/dernier mot", function()
    local _, frame = Mount()
    NPF.db.nameFormat = "first"
    frame = Remount()
    eq(frame.name:GetText(), "Grand")
    NPF.db.nameFormat = "last"
    frame = Remount()
    eq(frame.name:GetText(), "Noir")
    NPF.db.nameFormat = "full"
    frame = Remount()
    eq(frame.name:GetText(), "Grand Loup Noir")
    NS.Modules:SetEnabled("nameplateframes", false)
end)

test("plaques G : nom masqué et échelle pendant l'incantation d'un ennemi", function()
    local unit, frame = Mount()
    NPF.db.hideNameWhileCasting, NPF.db.castScale = true, 1.3
    frame = Remount()
    truthy(frame.name:IsShown(), "nom visible sans incantation")
    unit.casting = { name = "Morsure", startTime = 0, endTime = 1000 }
    Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    eq(frame.name:IsShown(), false, "nom masqué pendant l'incantation")
    eq(frame.styleScale, 1.3, "plaque agrandie")
    unit.casting = nil
    Mock.FireEvent("UNIT_SPELLCAST_STOP", "nameplate1")
    truthy(frame.name:IsShown(), "nom revenu")
    eq(frame.styleScale, 1, "échelle revenue")
    NPF.db.hideNameWhileCasting, NPF.db.castScale = false, 1
    NS.Modules:SetEnabled("nameplateframes", false)
end)

test("plaques G : recouvrements cible, focus et survol", function()
    local unit, frame = Mount()
    NPF.db.targetOverlay, NPF.db.focusOverlay, NPF.db.hoverOverlay = true, true, true
    frame = Remount()
    eq(frame.tint:IsShown(), false)
    Mock.units.target = unit
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    truthy(frame.tint:IsShown(), "cible")
    Mock.units.target = nil
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    eq(frame.tint:IsShown(), false)
    Mock.units.focus = unit
    Mock.FireEvent("PLAYER_FOCUS_CHANGED")
    truthy(frame.tint:IsShown(), "focus")
    Mock.units.focus = nil
    Mock.units.mouseover = unit
    Mock.FireEvent("UPDATE_MOUSEOVER_UNIT")
    truthy(frame.hoverTint:IsShown(), "survol")
    Mock.units.mouseover = nil   -- fin du survol : aucun événement, c'est le ticker qui s'en aperçoit
    Mock.Advance(0.2)
    eq(frame.hoverTint:IsShown(), false, "survol quitté")
    NS.Modules:SetEnabled("nameplateframes", false)
end)

test("plaques G : trait de seuil, bordure aucune, ennemi neutre, marqueur de raid à gauche", function()
    local _, frame = Mount({ reaction = 4 })
    NPF.db.healthMarker, NPF.db.borderNone, NPF.db.raidIconSide = 50, true, "left"
    NPF.db.neutralColor = true
    frame = Remount()
    truthy(frame.marker:IsShown(), "trait posé")
    for _, edge in pairs(frame.border) do eq(edge:IsShown(), false, "bordure masquée") end
    local _, _, point = frame.raidIcon:GetPoint()
    eq(point, "LEFT", "marqueur à gauche de la plaque")
    NPF.db.healthMarker = 0
    frame = Remount()
    eq(frame.marker:IsShown(), false)
    NS.Modules:SetEnabled("nameplateframes", false)
end)
