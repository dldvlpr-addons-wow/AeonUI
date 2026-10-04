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

test("suivi de quêtes : visibilité fine (monture, sans cible, raid boss), textes par état", function()
    reset()
    local db = NS.db.modules.questtracker
    local mounted = false
    local IsMountedBefore = _G.IsMounted
    _G.IsMounted = function() return mounted end
    db.visibility, db.raidHide = NS.Visibility.Spec({ mounted = "no" }), "boss"
    Enable()
    eq(ObjectiveTrackerFrame:GetAlpha(), 1)
    mounted = true
    Mock.FireEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    eq(ObjectiveTrackerFrame:GetAlpha(), 0, "à dos de monture")
    mounted = false
    Mock.instanceType = "raid"
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    eq(ObjectiveTrackerFrame:GetAlpha(), 1, "raid, hors rencontre")
    Mock.FireEvent("ENCOUNTER_START")
    eq(ObjectiveTrackerFrame:GetAlpha(), 0, "rencontre de raid")
    Mock.FireEvent("ENCOUNTER_END")
    eq(ObjectiveTrackerFrame:GetAlpha(), 1)
    Mock.instanceType = "none"
    db.visibility = NS.Visibility.Spec({ target = "yes" })
    NS.Modules:Refresh("questtracker")
    eq(ObjectiveTrackerFrame:GetAlpha(), 0, "sans cible")
    Mock.units.target = { name = "Ogre" }
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    eq(ObjectiveTrackerFrame:GetAlpha(), 1)
    Mock.units.target = nil
    -- Textes : quête 1 terminée, quête 2 en cours.
    local function Block(id)
        local block = { id = id, HeaderText = ObjectiveTrackerFrame:CreateFontString(), usedLines = {} }
        block.HeaderText:SetFont("Fonts\\ARIALN.TTF", 11, "")
        block.usedLines.a = { Text = ObjectiveTrackerFrame:CreateFontString() }
        return block
    end
    local done, open = Block(1), Block(2)
    ObjectiveTrackerFrame.modules[1].usedBlocks = { QuestTemplate = { [1] = done, [2] = open } }
    local C_QuestLogBefore = _G.C_QuestLog
    _G.C_QuestLog = { IsComplete = function(id) return id == 1 end }
    db.styleText = true
    NS.Modules:Refresh("questtracker")
    eq(done.HeaderText.fontSize, 13)
    eq(done.HeaderText.textColor[2], 1, "titre terminé : vert")
    eq(open.HeaderText.textColor[2], 0.82, "titre en cours")
    eq(open.usedLines.a.Text.fontSize, 12)
    eq(open.usedLines.a.Text.textColor[1], 0.8, "objectif en cours")
    db.styleText = false
    ObjectiveTrackerFrame:Update()
    Mock.Advance(0.1)
    eq(done.HeaderText.font, "Fonts\\ARIALN.TTF", "police d'origine rendue après Update")
    Disable()
    eq(ObjectiveTrackerFrame:GetAlpha(), 1, "rendu visible")
    ObjectiveTrackerFrame.modules[1].usedBlocks = nil
    _G.C_QuestLog, _G.IsMounted = C_QuestLogBefore, IsMountedBefore
    db.visibility, db.raidHide = NS.Visibility.Spec(), "never"
end)

test("habillage : style sombre teint le NineSlice et le fond, rendu au disable", function()
    reset()
    NS.Modules:SetEnabled("skin", true)
    NS.db.modules.skin.windowStyle = "dark"
    NS.db.modules.skin.skinWindows = true
    NS.Modules:Refresh("skin")
    eq(CharacterFrame.NineSlice.TopEdge.vertex[1], 0.25)
    eq(CharacterFrame.Bg.vertex[1], 0.25)
    NS.db.modules.skin.skinWindows = false
    NS.Modules:Refresh("skin")
    eq(CharacterFrame.Bg.vertex[1], 1)
    NS.db.modules.skin.skinWindows = true
    NS.Modules:Refresh("skin")
    eq(CharacterFrame.Bg.vertex[1], 0.25)
    NS.Modules:SetEnabled("skin", false)
    eq(CharacterFrame.Bg.vertex[1], 1)
    NS.db.modules.skin.skinWindows, NS.db.modules.skin.windowStyle = false, "theme"
    NS.Modules:SetEnabled("skin", true)
end)

test("suivi de quêtes : touche d'objet de quête, quête suivie d'abord, figée en combat", function()
    reset()
    local C_QuestLogBefore = _G.C_QuestLog
    local watched = { [2] = true }
    local items = { [1] = "item:100", [2] = "item:200" }
    _G.C_QuestLog = {
        GetNumQuestLogEntries = function() return 3 end,
        GetInfo = function(index) return { questID = index } end,
        GetQuestWatchType = function(questID) return watched[questID] and 0 or nil end,
    }
    _G.GetQuestLogSpecialItemInfo = function(index) return items[index] end
    NS.db.modules.questtracker.questItemKey = "g"
    Enable()
    local button = QT:GetQuestItemButton()
    eq(Mock.overrideBindings[button].G, "AeonUIQuestItemButton", "touche liée")
    eq(button:GetAttribute("type"), "item")
    eq(button:GetAttribute("item"), "item:200", "quête suivie d'abord")
    watched[2] = nil
    Mock.SetCombat(true)
    Mock.FireEvent("QUEST_WATCH_LIST_CHANGED")
    eq(button:GetAttribute("item"), "item:200", "figé en combat")
    Mock.SetCombat(false)
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    eq(button:GetAttribute("item"), "item:100", "sinon la première du journal")
    Disable()
    eq(Mock.overrideBindings[button], nil, "touche rendue")
    NS.db.modules.questtracker.questItemKey = ""
    _G.C_QuestLog, _G.GetQuestLogSpecialItemInfo = C_QuestLogBefore, nil
end)
