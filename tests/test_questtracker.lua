-- tests/test_questtracker.lua : suivi de quêtes AeonUI et panneaux sombres (étape 6).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local QT = NS.Modules:Get("questtracker")

local function Enable() NS.Modules:SetEnabled("questtracker", true) end
local function Disable() NS.Modules:SetEnabled("questtracker", false) end

test("suivi de quêtes : support, hauteur, en-têtes au thème, hook d'ancrage, rendu au disable", function()
    reset()
    Enable()
    local holder = _G.AeonUI_QuestTracker
    truthy(holder and holder:IsShown())
    eq(ObjectiveTrackerFrame:GetHeight(), 500)
    local _, relTo = ObjectiveTrackerFrame:GetPoint()
    eq(relTo, holder)
    eq(ObjectiveTrackerFrame:GetParent(), UIParent, "jamais reparenté")
    truthy(NS.IsRegionHidden(ObjectiveTrackerFrame.Header.Background))
    truthy(NS.IsRegionHidden(ObjectiveTrackerFrame.modules[1].Header.Background))
    eq(ObjectiveTrackerFrame.Header.Text.font, NS.db.theme.font)
    eq(ObjectiveTrackerFrame.Header.Text.fontSize, 14)
    ObjectiveTrackerFrame:ClearAllPoints()
    ObjectiveTrackerFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    local _, again = ObjectiveTrackerFrame:GetPoint()
    eq(again, holder, "Blizzard réancre : le hook reprend la main")
    truthy(NS.Movers:Anchor("questtracker"))
    Disable()
    eq(holder:IsShown(), false)
    eq(NS.IsRegionHidden(ObjectiveTrackerFrame.Header.Background), false)
    eq(ObjectiveTrackerFrame.Header.Text.font, "Fonts\\MORPHEUS.TTF")
    truthy(Mock.FindPrinted("/reload"))
end)

test("suivi de quêtes : repli automatique en combat et en instance, jamais si déjà replié par le joueur", function()
    reset()
    NS.db.modules.questtracker.collapseInCombat = true
    Enable()
    Mock.SetCombat(true)
    eq(QT.IsCollapsed(), true)
    Mock.SetCombat(false)
    eq(QT.IsCollapsed(), false, "rouvert à la sortie du combat")
    ObjectiveTrackerFrame:SetCollapsed(true)   -- replié par le joueur
    Mock.SetCombat(true)
    Mock.SetCombat(false)
    eq(QT.IsCollapsed(), true, "le choix du joueur reste")
    ObjectiveTrackerFrame:SetCollapsed(false)
    NS.db.modules.questtracker.collapseInCombat = false
    NS.db.modules.questtracker.collapseInInstance = true
    NS.Modules:Refresh("questtracker")
    Mock.instanceType = "party"
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    eq(QT.IsCollapsed(), true)
    Mock.instanceType = "none"
    Mock.FireEvent("ZONE_CHANGED_NEW_AREA")
    eq(QT.IsCollapsed(), false)
    -- Changement de zone en combat : replier est protégé, fait à la sortie du combat.
    Mock.SetCombat(true)
    Mock.instanceType = "party"
    Mock.FireEvent("ZONE_CHANGED_NEW_AREA")
    eq(QT.IsCollapsed(), false, "rien en combat")
    Mock.SetCombat(false)
    eq(QT.IsCollapsed(), true, "replié à la sortie")
    Mock.instanceType = "none"
    Mock.FireEvent("ZONE_CHANGED_NEW_AREA")
    NS.db.modules.questtracker.collapseInInstance = false
    Disable()
end)

test("habillage : panneaux sombres teintent le NineSlice et le fond, rendus au disable", function()
    reset()
    NS.Modules:SetEnabled("skin", true)
    NS.db.modules.skin.darkPanels = true
    NS.Modules:Refresh("skin")
    eq(CharacterFrame.NineSlice.TopEdge.vertex[1], 0.25)
    eq(CharacterFrame.Bg.vertex[1], 0.25)
    NS.db.modules.skin.darkPanels = false
    NS.Modules:Refresh("skin")
    eq(CharacterFrame.Bg.vertex[1], 1)
    NS.db.modules.skin.darkPanels = true
    NS.Modules:Refresh("skin")
    eq(CharacterFrame.Bg.vertex[1], 0.25)
    NS.Modules:SetEnabled("skin", false)
    eq(CharacterFrame.Bg.vertex[1], 1)
    NS.db.modules.skin.darkPanels = false
    NS.Modules:SetEnabled("skin", true)
end)
