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

test("inspection : moyenne, infobulle après INSPECT_READY, cache, combat", function()
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
    panel.countdowns[2]:GetScript("OnClick")(panel.countdowns[2])
    panel.actions[3]:GetScript("OnClick")(panel.actions[3])
    eq(Mock.raidActions[1][1], "ready")
    eq(Mock.raidActions[2][1], "countdown"); eq(Mock.raidActions[2][2], 10)
    eq(Mock.raidActions[3][2], 0, "annulation")
    eq(panel.countdowns[3].label:GetText(), string.format(L.RAIDUTILITY_SECONDS, 15))
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

test("utilitaire de raid : trois comptes à rebours, /aeon pull, conversion, dissolution", function()
    reset()
    NS.Modules:SetEnabled("raidutility", true)
    local _, panel = Raid:GetFrames()
    Mock.raidActions = {}
    NS.db.modules.raidutility.countdown2 = 12
    NS.Modules:Refresh("raidutility")
    eq(panel.countdowns[2].label:GetText(), string.format(L.RAIDUTILITY_SECONDS, 12), "libellé suit le réglage")
    NS.db.modules.raidutility.countdown3Key = "ctrl-f3"
    NS.Modules:Refresh("raidutility")
    eq(Mock.overrideBindings[panel]["CTRL-F3"], "AeonUIRaidCountdown3", "touche liée au bouton")
    NS.db.modules.raidutility.countdown3Key = ""
    SlashCmdList.AEONUI("pull")
    SlashCmdList.AEONUI("pull 7")
    SlashCmdList.AEONUI("pull 0")
    eq(Mock.raidActions[1][2], 5, "premier compte à rebours par défaut")
    eq(Mock.raidActions[2][2], 7)
    eq(Mock.raidActions[3][2], 0)
    eq(panel.convert.label:GetText(), L.RAIDUTILITY_TO_RAID)
    panel.convert:GetScript("OnClick")(panel.convert)
    eq(Mock.raidActions[4][1], "toraid")
    Mock.inRaid, Mock.groupSize = true, 3
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    eq(panel.convert.label:GetText(), L.RAIDUTILITY_TO_PARTY)
    -- Dissolution : raid1 = moi, raid2 illisible (secret), raid3 d'un autre royaume.
    Mock.units.player.leader = true
    Mock.units.raid1 = { name = Mock.units.player.name }
    Mock.units.raid2 = { name = Mock.SetSecret("Caché") }
    Mock.units.raid3 = { name = "Ana", realm = "Ailleurs" }
    Mock.raidActions = {}
    panel.actions[5]:GetScript("OnClick")(panel.actions[5])
    eq(#Mock.raidActions, 0, "confirmation d'abord")
    StaticPopupDialogs.AEONUI_DISBAND.OnAccept()
    eq(#Mock.raidActions, 2)
    eq(Mock.raidActions[1][1], "uninvite"); eq(Mock.raidActions[1][2], "Ana-Ailleurs")
    eq(Mock.raidActions[2][1], "leave")
    Mock.units.player.leader = false
    Mock.raidActions = {}
    Raid.Disband()
    eq(#Mock.raidActions, 1, "pas chef : quitte seulement")
    Mock.units.raid1, Mock.units.raid2, Mock.units.raid3 = nil, nil, nil
    NS.db.modules.raidutility.countdown2 = 10
    NS.Modules:SetEnabled("raidutility", false)
    eq(Mock.overrideBindings[panel], nil, "touches libérées")
end)

test("utilitaire de raid : bande compacte, visibilité, garde chef ou assistant", function()
    reset()
    local db = NS.db.modules.raidutility
    db.layout, db.show = "band", "raid"
    NS.Modules:SetEnabled("raidutility", true)
    local toggle, _, band = Raid:GetFrames()
    eq(Mock.stateDrivers[band].visibility, "[group:raid] show; hide")
    eq(Mock.stateDrivers[toggle] and Mock.stateDrivers[toggle].visibility, nil, "bouton retiré")
    truthy(NS.Movers.registry.raidband and not NS.Movers.registry.raidutility, "mover de la bande seul")
    local star = band.markers[1]
    eq(star:GetAttribute("*type2"), "worldmarker")
    eq(star:GetAttribute("marker"), 5, "étoile : marqueur au sol 5")
    eq(star:GetAttribute("*action2"), "toggle")
    eq(star:GetAttribute("shift-action2"), "clear")
    eq(band.clear:GetAttribute("marker"), nil, "effacer : tous les marqueurs au sol")
    Mock.raidActions = {}
    Mock.units.target = { guid = "Creature-1", name = "Ogre" }
    star:GetScript("OnClick")(star, "LeftButton", true)
    eq(#Mock.raidActions, 0, "appui : rien")
    star:GetScript("OnClick")(star, "LeftButton", false)
    eq(Mock.raidActions[1][1], "mark"); eq(Mock.raidActions[1][3], 1)
    star:GetScript("OnClick")(star, "RightButton", false)
    eq(#Mock.raidActions, 1, "clic droit : action sécurisée seulement")
    band.pull:GetScript("OnClick")(band.pull, "LeftButton")
    Mock.shift = true
    band.pull:GetScript("OnClick")(band.pull, "LeftButton")
    Mock.shift = false
    band.pull:GetScript("OnClick")(band.pull, "RightButton")
    eq(Mock.raidActions[2][2], 5); eq(Mock.raidActions[3][2], 10); eq(Mock.raidActions[4][2], 0)
    band.ready:GetScript("OnClick")(band.ready, "LeftButton")
    eq(Mock.raidActions[5][1], "ready")
    -- Raid sans être chef : masqué ; chef : pilote rétabli.
    Mock.inRaid, Mock.groupSize = true, 10
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    eq(Mock.stateDrivers[band].visibility, "hide")
    Mock.units.player.leader = true
    Mock.FireEvent("PARTY_LEADER_CHANGED")
    eq(Mock.stateDrivers[band].visibility, "[group:raid] show; hide")
    Mock.units.player.leader = false
    Mock.inRaid, Mock.groupSize = false, 0
    -- Retour au panneau.
    db.layout, db.show = "panel", "group"
    NS.Modules:Refresh("raidutility")
    eq(Mock.stateDrivers[band].visibility, nil)
    eq(Mock.stateDrivers[toggle].visibility, "[group] show; hide")
    db.toggleKey = "ctrl-r"
    NS.Modules:Refresh("raidutility")
    local _, panel = Raid:GetFrames()
    eq(Mock.overrideBindings[panel]["CTRL-R"], "AeonUIRaidUtilityToggle")
    db.toggleKey = ""
    NS.Modules:SetEnabled("raidutility", false)
    eq(band:IsShown(), false)
end)
