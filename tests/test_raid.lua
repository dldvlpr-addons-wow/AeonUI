-- tests/test_raid.lua : étape 16, utilitaire de raid, niveau d'objet en inspection.
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset
local Gear = NS.Modules:Get("gear")
local Raid = NS.Modules:Get("raidutility")

local function TooltipHas(pattern)
    for _, line in ipairs(GameTooltip.lines or {}) do
        if tostring(line):find(pattern, 1, true) then return true end
    end
    return false
end

local function Equip()
    Mock.equipped[1] = { link = "item:100:0:0", level = 60, quality = 4 }
    Mock.equipped[5] = { link = "item:200:0:0", level = 50, quality = 3 }
end

test("inspection : moyenne, infobulle après INSPECT_READY, cache, combat, ElvUI", function()
    reset()
    Equip()
    eq(Gear.UnitAverage("player"), 55)
    Mock.units.mouseover = { guid = "Player-2", name = "Bob", class = "WARRIOR", isPlayer = true }
    Mock.inspects = {}
    Mock.now = Mock.now + 10
    Mock.ShowUnitTooltip("mouseover")
    eq(Mock.inspects[1], "mouseover", "inspection demandée")
    eq(TooltipHas("55.0"), false, "pas encore de niveau")
    Mock.FireEvent("INSPECT_READY", "Player-2")
    truthy(TooltipHas("55.0"), "infobulle rafraîchie avec le niveau")
    Mock.ShowUnitTooltip("mouseover")
    truthy(TooltipHas("55.0"), "cache")
    eq(#Mock.inspects, 1, "pas de seconde inspection")
    Mock.equipped[3] = { link = "item:300:0:0", quality = 2 }   -- lien sans niveau : hors cache
    eq(select(2, Gear.UnitAverage("mouseover")), 1, "lien sans niveau compté manquant")
    Mock.equipped[3] = nil
    Mock.units.mouseover.guid = "Player-3"
    Mock.combat = true
    Mock.ShowUnitTooltip("mouseover")
    eq(#Mock.inspects, 1, "pas d'inspection en combat")
    Mock.combat = false
    Mock.units.mouseover.guid = Mock.SetSecret("Player-4")
    Mock.now = Mock.now + 10
    Mock.ShowUnitTooltip("mouseover")
    eq(#Mock.inspects, 1, "GUID secret : rien")
    Mock.units.mouseover.guid = "Player-2"
    Mock.loadedAddons.ElvUI = true
    Mock.ShowUnitTooltip("mouseover")
    eq(TooltipHas("55.0"), false, "ElvUI : sa propre ligne")
    Mock.loadedAddons.ElvUI = nil
    Mock.tooltipUnit = nil
end)

test("inspection : niveaux sur la fenêtre d'inspection", function()
    reset()
    Equip()
    InspectFrame.unit = "target"
    Mock.units.target = { guid = "Player-5", name = "Zed", isPlayer = true }
    InspectFrame:Show()
    Gear:UpdateInspect()
    local level
    for _, region in ipairs({ InspectHeadSlot:GetRegions() }) do
        if region.text == "60" then level = region end
    end
    truthy(level and level:IsShown(), "niveau 60 sur le casque inspecté")
    NS.db.modules.gear.inspect = false
    Gear:UpdateInspect()
    eq(level:IsShown(), false, "option coupée")
    NS.db.modules.gear.inspect = true
    InspectFrame:Hide()
end)

test("utilitaire de raid : visibilité en groupe, panneau, actions, marqueurs", function()
    reset()
    NS.Modules:SetEnabled("raidutility", true)
    local toggle, panel = Raid:GetFrames()
    eq(Mock.stateDrivers[toggle].visibility, "[group] show; hide")
    toggle:GetScript("OnClick")(toggle)
    truthy(panel:IsShown(), "panneau ouvert")
    Mock.raidActions = {}
    panel.actions[1]:GetScript("OnClick")(panel.actions[1])
    panel.actions[3]:GetScript("OnClick")(panel.actions[3])
    panel.actions[4]:GetScript("OnClick")(panel.actions[4])
    eq(Mock.raidActions[1][1], "ready")
    eq(Mock.raidActions[2][1], "countdown"); eq(Mock.raidActions[2][2], 10)
    eq(Mock.raidActions[3][2], 0, "annulation")
    Mock.units.target = { guid = "Creature-1", name = "Ogre" }
    panel.targetMarkers[8]:GetScript("OnClick")(panel.targetMarkers[8])
    eq(Mock.raidActions[4][1], "mark"); eq(Mock.raidActions[4][3], 8)
    _G.GetRaidTargetIndex = function() return 8 end
    panel.targetMarkers[8]:GetScript("OnClick")(panel.targetMarkers[8])
    eq(Mock.raidActions[5][3], 0, "même marqueur : retiré")
    _G.GetRaidTargetIndex = nil
    local marker = panel.worldMarkers[1]
    eq(marker:GetAttribute("type"), "worldmarker")
    eq(marker:GetAttribute("marker"), 1)
    eq(marker:GetAttribute("*action2"), "clear")
    eq(panel.clearWorld:GetAttribute("action"), "clear")
    Mock.combat = true
    toggle:GetScript("OnClick")(toggle)
    truthy(panel:IsShown(), "pas de fermeture en combat")
    Mock.combat = false
    NS.Modules:SetEnabled("raidutility", false)
    eq(Mock.stateDrivers[toggle].visibility, nil)
    eq(toggle:IsShown(), false)
end)
