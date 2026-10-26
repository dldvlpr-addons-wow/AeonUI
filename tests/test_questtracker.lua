-- tests/test_questtracker.lua : suivi de quêtes MuscaUI et panneaux sombres (étape 6).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local QT = NS.Modules:Get("questtracker")

local function Enable() NS.Modules:SetEnabled("questtracker", true) end
local function Disable() NS.Modules:SetEnabled("questtracker", false) end

test("suivi de quêtes : support, hauteur, en-têtes au thème, hook d'ancrage, rendu au disable", function()
    reset()
    Enable()
    local holder = _G.MuscaUI_QuestTracker
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
    eq(Mock.overrideBindings[button].G, "MuscaUIQuestItemButton", "touche liée")
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

test("suivi de quêtes : liste voulue (filtres, mémoire, suivi automatique, tri stable)", function()
    local function Facts(logIndex, title, level, extra)
        local facts = { logIndex = logIndex, title = title, level = level, frequency = 0, onMap = true }
        for key, value in pairs(extra or {}) do facts[key] = value end
        return facts
    end
    local facts = { [1] = Facts(3, "Charlie", 12), [2] = Facts(1, "alpha", 10, { onMap = false }),
                    [3] = Facts(2, "Bravo", 11, { complete = true }), [4] = Facts(4, "Delta", 9, { trivial = true }),
                    [5] = Facts(5, "Echo", 12), [6] = Facts(6, "Foxtrot", 12, { frequency = 1 }) }
    local db = { filterActive = true, filterZone = true, hideComplete = false, hideTrivial = true,
                 hideRepeatable = true, autoTrackZone = true, sortMode = "proximity", completedPosition = "mixed" }
    local memory, session = { removed = {}, auto = {} }, { exempt = {}, untracked = { [5] = true } }
    local wanted, ordered = QT.WantedWatches({ 1, 2, 3, 4, 6 }, { 1, 3, 4, 5, 6 }, facts, db, memory, session)
    eq(table.concat(wanted, ","), "1,3", "hors zone, grise, journalière retirées ; retirée à la main jamais reprise")
    eq(ordered, false, "Blizzard trie : ordre laissé")
    truthy(memory.removed[2] and memory.removed[4] and memory.removed[6])
    session.exempt[4] = true
    db.sortMode, db.completedPosition, db.filterZone = "name", "bottom", false
    wanted, ordered = QT.WantedWatches({ 3, 1 }, { 1, 3 }, facts, db, memory, session)
    eq(table.concat(wanted, ","), "2,1,3", "zone coupée : quête rendue ; par nom, terminée en bas")
    eq(memory.removed[2], nil)
    truthy(ordered)
    db.sortMode, db.completedPosition = "level", "top"
    facts[2] = false
    wanted = QT.WantedWatches({ 1, 3 }, { 1, 3 }, facts, db, memory, session)
    eq(table.concat(wanted, ","), "3,1", "terminée en tête")
    eq(memory.removed[4], true, "grise toujours filtrée")
    eq(memory.removed[6], true)
    db.sortMode, db.completedPosition, db.filterZone, db.hideRepeatable = "log", "mixed", true, false
    session.untracked[5] = nil
    wanted = QT.WantedWatches({ 1 }, { 1, 5, 6 }, facts, db, memory, session)
    eq(table.concat(wanted, ","), "1,5,6", "zone : suivies d'office, journalière rendue")
    truthy(memory.auto[5])
    wanted = QT.WantedWatches({ 1, 5, 6 }, { 1 }, facts, db, memory, session)
    eq(table.concat(wanted, ","), "1,6", "quête suivie d'office : retirée en quittant la zone")
    eq(memory.auto[5], nil)
end)

test("suivi de quêtes : liste Blizzard réécrite hors combat, à la main respecté, rendue au disable", function()
    reset()
    local before = _G.C_QuestLog
    local log = {
        { questID = 11, title = "Bravo", level = 10, isOnMap = true },
        { questID = 12, title = "Alpha", level = 12, isOnMap = true },
        { questID = 13, title = "Far", level = 12, isOnMap = false },
        { questID = 14, title = "Charlie", level = 11, isOnMap = true },
    }
    local watches, writes, refuse = { 14, 13, 11, 12 }, 0, false
    local function Find(list, id) for index, value in ipairs(list) do if value == id then return index end end end
    _G.C_QuestLog = {
        GetNumQuestWatches = function() return #watches end,
        GetQuestIDForQuestWatchIndex = function(index) return watches[index] end,
        GetNumQuestLogEntries = function() return #log end,
        GetInfo = function(index) return log[index] end,
        GetLogIndexForQuestID = function(id) for index, info in ipairs(log) do if info.questID == id then return index end end end,
        IsComplete = function() return false end,
        IsQuestTrivial = function() return false end,
        AddQuestWatch = function(id)
            if refuse then return false end
            writes = writes + 1 table.insert(watches, 1, id) return true
        end,
        RemoveQuestWatch = function(id) writes = writes + 1 table.remove(watches, Find(watches, id)) return true end,
    }
    local db = NS.db.modules.questtracker
    db.sortMode = "name"
    Mock.SetCombat(true)
    Enable()
    Mock.Advance(0.25)
    eq(table.concat(watches, ","), "14,13,11,12", "en combat : rien d'écrit")
    -- Journal pas encore chargé : ni écriture, ni purge de la mémoire des retirées.
    local memory = { removed = { [99] = true }, auto = {} }
    NS.global.questWatches = { [NS.Database.CharacterKey()] = memory }
    local loaded = log
    log = {}
    Mock.SetCombat(false)
    Mock.FireEvent("QUEST_LOG_UPDATE")
    Mock.Advance(0.25)
    eq(table.concat(watches, ","), "14,13,11,12", "journal vide : rien d'écrit")
    truthy(memory.removed[99], "journal vide : mémoire des retirées gardée")
    log = loaded
    Mock.FireEvent("QUEST_LOG_UPDATE")
    Mock.Advance(0.25)
    eq(table.concat(watches, ","), "12,11,14", "hors zone retirée, tri par nom")
    eq(memory.removed[99], nil, "journal chargé : quête absente oubliée")
    truthy(_G.MuscaUI_QuestTrackerFilter:IsShown(), "bouton des filtres")
    writes = 0
    Mock.FireEvent("QUEST_LOG_UPDATE")
    Mock.Advance(0.25)
    eq(writes, 0, "ordre déjà bon : aucune écriture")
    -- Blizzard suit d'office une quête acceptée : pas une action du joueur, le filtre s'applique.
    table.insert(watches, 1, 13)
    Mock.FireEvent("QUEST_ACCEPTED", 13)
    Mock.FireEvent("QUEST_WATCH_LIST_CHANGED")
    Mock.Advance(0.25)
    eq(Find(watches, 13), nil, "suivie d'office par Blizzard : filtrée")
    truthy(memory.removed[13], "suivie d'office par Blizzard : mise en mémoire")
    -- Le joueur suit à la main la quête hors zone, puis retire une quête de la zone.
    table.insert(watches, 13)
    Mock.FireEvent("QUEST_WATCH_LIST_CHANGED")
    Mock.Advance(0.25)
    truthy(Find(watches, 13), "suivie à la main : gardée malgré le filtre")
    table.remove(watches, Find(watches, 14))
    Mock.FireEvent("QUEST_WATCH_LIST_CHANGED")
    Mock.Advance(0.25)
    eq(Find(watches, 14), nil, "retirée à la main : pas reprise par le suivi automatique")
    -- Bouton : filtres coupés, la quête retirée revient.
    table.remove(watches, Find(watches, 13))
    Mock.FireEvent("QUEST_WATCH_LIST_CHANGED")
    Mock.Advance(0.25)
    db.filterZone = false
    NS.Modules:Refresh("questtracker")
    Mock.Advance(0.25)
    eq(Find(watches, 13), nil, "retirée à la main, pas par le filtre : pas rendue")
    db.filterZone = true
    _G.MuscaUI_QuestTrackerFilter:GetScript("OnClick")(_G.MuscaUI_QuestTrackerFilter)
    eq(db.filterActive, false)
    -- Rendues au disable : différé en rencontre, gardées si l'ajout échoue ou si 25 sont suivies.
    memory.removed = { [13] = true, [99] = true }
    local encounterBefore = _G.IsEncounterInProgress
    local encounter = true
    _G.IsEncounterInProgress = function() return encounter end
    Disable()
    eq(Find(watches, 13), nil, "rencontre en cours : rien d'écrit")
    truthy(memory.removed[13], "rencontre en cours : mémoire gardée")
    encounter, refuse = false, true
    Mock.Advance(2.1)
    truthy(memory.removed[13], "ajout refusé : mémoire gardée")
    eq(memory.removed[99], nil, "hors journal : oubliée")
    refuse = false
    local full = {}
    for index = 1, 25 do full[index] = 100 + index end
    watches = full
    Enable()
    Disable()
    eq(#watches, 25, "25 suivies : rien d'ajouté")
    truthy(memory.removed[13], "25 suivies : mémoire gardée")
    watches = {}
    Enable()
    Disable()
    eq(table.concat(watches, ","), "13", "rendue au suivi")
    eq(memory.removed[13], nil, "rendue : sortie de la mémoire")
    Mock.Advance(0.25)
    _G.IsEncounterInProgress = encounterBefore
    db.sortMode, db.filterActive = "proximity", true
    NS.global.questWatches = {}
    _G.C_QuestLog = before
end)
