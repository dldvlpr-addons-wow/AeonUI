-- MuscaUI_QuestTracker/QuestTracker.lua
-- Suivi de quêtes MuscaUI : le suivi Blizzard (ObjectiveTrackerFrame, ou WatchFrame sur un
-- client plus ancien) est posé sur un support déplaçable, à la hauteur voulue, en-têtes au thème
-- (fond caché, police), et replié de lui-même en combat ou en instance si demandé.
--
-- Le cadre Blizzard n'est pas reparenté (système Edit Mode) : réancré seulement, un hook de
-- SetPoint reprend la main si Blizzard le replace. Les API de repli changent selon le moteur :
-- SetCollapsed, sinon ObjectiveTracker_Collapse/Expand, sinon rien (tout en pcall).
-- Tri, filtres et suivi automatique réécrivent la liste de suivi Blizzard (Add/RemoveQuestWatch),
-- hors combat, hors rencontre et carte fermée, seulement quand l'ordre voulu diffère.
local NS = MuscaUI
local L = NS.L
local Media = NS.Media

local QuestTracker = NS.Modules:Register("questtracker", {
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    secure = true,            -- le suivi contient des boutons d'objets sécurisés : rien en combat
    titleKey = "QT_TITLE",
    descKey = "QT_DESC",
    defaults = {
        enabled = false,
        height = 500,
        skinHeaders = true,
        headerFontSize = 14,
        collapseInCombat = false,
        collapseInInstance = false,
        visibility = NS.Visibility.Spec(),   -- conditions communes (Core/Visibility), en transparence
        raidHide = "never",       -- en raid : "never", "always", "boss" (pendant une rencontre seulement)
        styleText = false,        -- titres et objectifs : police du thème, tailles et couleurs ci-dessous
        titleFontSize = 13,
        objectiveFontSize = 12,
        titleColor = { r = 1, g = 0.82, b = 0 },
        objectiveColor = { r = 0.8, g = 0.8, b = 0.8 },
        completeColor = { r = 0.25, g = 1, b = 0.35 },   -- quête terminée : titre et objectifs
        colorSource = "custom",   -- titres et en-têtes : "custom" (couleurs ci-dessus), "class", "accent"
        dimCompleted = 100,       -- opacité des objectifs terminés (quête terminée comprise), en %
        backgroundOpacity = 0,    -- fond derrière le suivi, en % (0 : aucun)
        accentLine = false,       -- filet d'accent en haut du suivi
        questItemKey = "",        -- touche qui utilise l'objet de quête (suivie d'abord), vide = aucune
        sortMode = "proximity",   -- "proximity" (Blizzard, distance) | "log" | "level" | "name"
        completedPosition = "mixed", -- quêtes terminées : "mixed" | "top" | "bottom"
        filterActive = true,      -- bouton du suivi : filtres appliqués ou tout montré
        filterZone = true,        -- quêtes de la carte courante seulement
        hideComplete = false,
        hideTrivial = true,       -- quêtes grises (niveau trop bas)
        hideRepeatable = false,   -- journalières et hebdomadaires
        autoTrackZone = true,     -- suit les quêtes de la zone ou du donjon (25 au plus)
    },
})

local HEADER_KEYS = { "QuestHeader", "AchievementHeader", "ScenarioHeader", "CampaignQuestHeader",
                      "ProfessionHeader", "MonthlyActivitiesHeader", "BonusObjectiveHeader", "WorldQuestHeader" }

local active = false
local holder
local anchoring, hooked = false, false
local autoCollapsed = false      -- replié par nous (combat ou instance) : à rouvrir
local headerBackgrounds = {}     -- fonds cachés
local originalFonts = setmetatable({}, { __mode = "k" })   -- [FontString] = { police d'origine }
local dimmedLines = setmetatable({}, { __mode = "k" })     -- [ligne d'objectif] = true : opacité baissée par nous
local inEncounter = false
local UpdateFilterButton

local function Tracker()
    return _G.ObjectiveTrackerFrame or _G.WatchFrame or _G.QuestWatchFrame
end

--------------------------------------------------------------------------------
-- Repli (API selon le moteur)
--------------------------------------------------------------------------------

function QuestTracker.IsCollapsed()
    local tracker = Tracker()
    if not tracker then return false end
    if tracker.IsCollapsed then
        local ok, value = pcall(tracker.IsCollapsed, tracker)
        if ok then return value == true end
    end
    return tracker.isCollapsed == true or tracker.collapsed == true
end

function QuestTracker.SetCollapsed(collapsed)
    local tracker = Tracker()
    if not tracker then return false end
    if tracker.SetCollapsed then return pcall(tracker.SetCollapsed, tracker, collapsed) end
    if collapsed and _G.ObjectiveTracker_Collapse then return pcall(ObjectiveTracker_Collapse) end
    if not collapsed and _G.ObjectiveTracker_Expand then return pcall(ObjectiveTracker_Expand) end
    return false
end

--- Replie si une condition (combat, instance) le demande, rouvre quand plus aucune ne tient.
function QuestTracker:UpdateCollapse(event)
    local db = self.db
    -- InCombatLockdown est encore faux pendant PLAYER_REGEN_DISABLED : l'événement fait foi.
    local inCombat = event == "PLAYER_REGEN_DISABLED" or (event ~= "PLAYER_REGEN_ENABLED" and NS.InCombat())
    local want = (db.collapseInCombat and inCombat) or (db.collapseInInstance and IsInInstance() == true)
    if want and not autoCollapsed and not self.IsCollapsed() then
        autoCollapsed = true
        self.SetCollapsed(true)
    elseif not want and autoCollapsed then
        autoCollapsed = false
        self.SetCollapsed(false)
    end
end

--- Transparent hors de sa visibilité commune, ou en raid selon raidHide. Alpha seulement : le suivi
-- contient des boutons sécurisés, le cacher en combat est bloqué. Il reste cliquable invisible.
function QuestTracker:ShouldHide(event)
    local db = self.db
    if not NS.Visibility.Evaluate(db.visibility, NS.Visibility.State(event)) then return true end
    if db.raidHide ~= "never" then
        local _, instanceType = IsInInstance()
        if instanceType == "raid" and (db.raidHide == "always" or inEncounter) then return true end
    end
    return false
end

function QuestTracker:UpdateVisibility(event)
    local tracker = Tracker()
    if tracker then tracker:SetAlpha(self:ShouldHide(event) and 0 or 1) end
end

--------------------------------------------------------------------------------
-- Titres et objectifs : police, tailles, couleurs par état
--------------------------------------------------------------------------------

local function StyleFont(fontString, size, color)
    if not (fontString and fontString.SetFont) then return end
    if not originalFonts[fontString] then originalFonts[fontString] = { fontString:GetFont() } end
    -- Relu sur le widget (Blizzard repose la couleur à sa mise à jour) : écrit seulement si différent.
    local path, outline = Media:Font("questtracker"), Media:Outline()
    local currentPath, currentSize, currentOutline = fontString:GetFont()
    if currentPath ~= path or currentSize ~= size or (currentOutline or "") ~= (outline or "") then
        fontString:SetFont(path, size, outline)
    end
    local r, g, b = fontString:GetTextColor()
    if not (r and math.abs(r - color.r) < 0.001 and math.abs(g - color.g) < 0.001 and math.abs(b - color.b) < 0.001) then
        fontString:SetTextColor(color.r, color.g, color.b)
    end
end

local function EachBlock(callback)
    local tracker = Tracker()
    for _, module in ipairs(tracker and tracker.modules or {}) do
        -- usedBlocks[modèle][id] = bloc (moteur 11+), ou directement [id] = bloc.
        for _, entry in pairs(type(module.usedBlocks) == "table" and module.usedBlocks or {}) do
            if type(entry) == "table" and (entry.HeaderText or entry.usedLines) then
                callback(entry)
            elseif type(entry) == "table" then
                for _, block in pairs(entry) do
                    if type(block) == "table" then callback(block) end
                end
            end
        end
    end
end

function QuestTracker.QuestComplete(block)
    local id = block.id
    if type(id) ~= "number" or not (C_QuestLog and C_QuestLog.IsComplete) then return false end
    local done = C_QuestLog.IsComplete(id)
    return not NS.IsSecret(done) and done == true
end

--- Police d'origine rendue ; la couleur, Blizzard la repose à sa mise à jour suivante.
local function RestoreFont(fontString)
    if fontString and originalFonts[fontString] then fontString:SetFont(unpack(originalFonts[fontString])) end
end

--- Couleur des titres et des en-têtes : celle choisie, sinon classe ou accent.
function QuestTracker:SourceColor(custom)
    local source = self.db.colorSource
    if source == "accent" then
        local r, g, b = Media:Accent()
        return { r = r, g = g, b = b }
    elseif source == "class" and _G.UnitClass then
        local _, classFile = UnitClass("player")
        if classFile and not NS.IsSecret(classFile) then
            local r, g, b = NS.ClassColor(classFile)
            return { r = r, g = g, b = b }
        end
    end
    return custom
end

--- Objectif `key` du bloc terminé ? (quête terminée, ou objectif fini selon le journal.)
function QuestTracker.ObjectiveDone(block, key, complete)
    if complete then return true end
    local id = block.id
    if type(key) ~= "number" or type(id) ~= "number" or not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return false end
    local objectives = C_QuestLog.GetQuestObjectives(id)
    local objective = type(objectives) == "table" and objectives[key]
    local finished = type(objective) == "table" and objective.finished
    return not NS.IsSecret(finished) and finished == true
end

--- Opacité des objectifs terminés (rendue à 1 pour une ligne qu'on avait baissée).
local function DimLines(block, lines)
    local alpha = (tonumber(QuestTracker.db.dimCompleted) or 100) / 100
    local complete = QuestTracker.QuestComplete(block)
    for key, line in pairs(lines) do
        if type(line) == "table" and line.SetAlpha then
            if alpha < 1 and QuestTracker.ObjectiveDone(block, key, complete) then
                line:SetAlpha(alpha)
                dimmedLines[line] = true
            elseif dimmedLines[line] then
                line:SetAlpha(1)
                dimmedLines[line] = nil
            end
        end
    end
end

function QuestTracker:StyleBlocks()
    local db = self.db
    if not active then return end
    EachBlock(function(block)
        local lines = type(block.usedLines) == "table" and block.usedLines or {}
        DimLines(block, lines)
        if not db.styleText then
            RestoreFont(block.HeaderText)
            for _, line in pairs(lines) do if type(line) == "table" then RestoreFont(line.Text) end end
            return
        end
        local complete = QuestTracker.QuestComplete(block)
        StyleFont(block.HeaderText, db.titleFontSize, complete and db.completeColor or self:SourceColor(db.titleColor))
        for _, line in pairs(lines) do
            if type(line) == "table" then
                StyleFont(line.Text, db.objectiveFontSize, complete and db.completeColor or db.objectiveColor)
            end
        end
    end)
end

-- Après chaque mise à jour Blizzard, une passe à l'image suivante (plusieurs Update par image).
local styleQueued = false
local function QueueStyle()
    if styleQueued or not active then return end
    styleQueued = true
    C_Timer.After(0, function()
        styleQueued = false
        QuestTracker:StyleBlocks()
    end)
end

--------------------------------------------------------------------------------
-- Support, ancrage, habillage
--------------------------------------------------------------------------------

local function AnchorTracker()
    local tracker = Tracker()
    if anchoring or not holder or not tracker then return end
    -- Le suivi contient des boutons d'objets sécurisés : le ré-ancrer en combat est bloqué.
    if NS.InCombat() then NS:RunOutOfCombat(AnchorTracker) return end
    anchoring = true
    NS.ClearPointsRaw(tracker)   -- système Edit Mode : sans sa surcharge Lua (Compat)
    NS.SetPointRaw(tracker, "TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    anchoring = false
end

local function Headers()
    local tracker, list = Tracker(), {}
    if not tracker then return list end
    if tracker.Header then list[#list + 1] = tracker.Header end
    for _, module in ipairs(tracker.modules or {}) do
        if module.Header then list[#list + 1] = module.Header end
    end
    local blocks = tracker.BlocksFrame or tracker
    for _, key in ipairs(HEADER_KEYS) do
        if blocks[key] then list[#list + 1] = blocks[key] end
    end
    return list
end

local function SkinHeaders()
    local db = QuestTracker.db
    for _, header in ipairs(Headers()) do
        local background = header.Background
        if background then
            headerBackgrounds[background] = true
            if db.skinHeaders then NS.HideRegion(background) else NS.ShowRegion(background) end
        end
        local text = header.Text
        if text and text.SetFont then
            if not header.foreverOriginalFont then header.foreverOriginalFont = { text:GetFont() } end
            local path, size, flags
            if db.skinHeaders then
                path, size, flags = Media:Font("questtracker"), db.headerFontSize, Media:Outline()
            else
                path, size, flags = unpack(header.foreverOriginalFont)
            end
            local curPath, curSize, curFlags = text:GetFont()   -- SetFont relance une mise en page : seulement si ça change
            if curPath ~= path or curSize ~= size or curFlags ~= flags then text:SetFont(path, size, flags) end
            -- Couleur de classe ou d'accent ; la couleur Blizzard est capturée puis rendue.
            if text.SetTextColor then
                if not header.muscaOriginalColor then header.muscaOriginalColor = { text:GetTextColor() } end
                local custom = QuestTracker:SourceColor(nil)
                if db.skinHeaders and custom then text:SetTextColor(custom.r, custom.g, custom.b)
                else text:SetTextColor(unpack(header.muscaOriginalColor)) end
            end
        end
    end
end

local function Build()
    holder = CreateFrame("Frame", "MuscaUI_QuestTracker", UIParent)
    holder:SetFrameStrata("LOW")
    -- Fond et filet d'accent : sur le support, pas sur le cadre Blizzard (Edit Mode).
    holder.background = holder:CreateTexture(nil, "BACKGROUND")
    holder.background:SetAllPoints(holder)
    holder.accentLine = holder:CreateTexture(nil, "BORDER")
    holder.accentLine:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    holder.accentLine:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    holder.accentLine:SetHeight(2)
    if not hooked then
        hooked = true
        hooksecurefunc(Tracker(), "SetPoint", function()
            if active and not anchoring then AnchorTracker() end
        end)
        if Tracker().Update then hooksecurefunc(Tracker(), "Update", QueueStyle) end
    end
end

--- Fond (opacité) et filet d'accent du support. ponytail: sur toute la hauteur réglée, pas celle du contenu.
function QuestTracker:ApplyBackground()
    if not holder then return end
    local opacity = (tonumber(self.db.backgroundOpacity) or 0) / 100
    local c = NS.db.theme.backdrop
    NS.SetSolidColor(holder.background, c.r, c.g, c.b, opacity)
    holder.background:SetShown(opacity > 0)
    local r, g, b = Media:Accent()
    NS.SetSolidColor(holder.accentLine, r, g, b, 1)
    holder.accentLine:SetShown(self.db.accentLine and true or false)
end

function QuestTracker:Apply()
    local tracker = Tracker()
    if not tracker then return end
    if not holder then Build() end
    local width = tracker:GetWidth()
    holder:SetSize(width > 0 and width or 260, self.db.height)
    tracker:SetHeight(self.db.height)
    NS.Movers:Register("questtracker", holder, L.MOVER_QUESTTRACKER, "TOPRIGHT", -40, -260)
    NS.Movers:Load("questtracker")
    AnchorTracker()
    self:ApplyBackground()
    SkinHeaders()
    self:UpdateCollapse()
    self:UpdateVisibility()
    self:StyleBlocks()
    UpdateFilterButton()
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Touche d'objet de quête
--------------------------------------------------------------------------------
-- Bouton sécurisé caché, lié à la touche ; l'objet est choisi hors combat (attribut protégé) et
-- garde celui d'avant pendant le combat. ponytail: quête suivie d'abord, pas la plus proche.

local questItemButton

function QuestTracker:UpdateQuestItem()
    if not questItemButton or NS.InCombat() then return end
    questItemButton:SetAttribute("item", NS.GetQuestItemLink())
end

function QuestTracker:BindQuestItem(on)
    NS:RunOutOfCombat(function()
        local key = self.db.questItemKey
        on = on and type(key) == "string" and key ~= ""
        if on and not questItemButton then
            questItemButton = CreateFrame("Button", "MuscaUIQuestItemButton", UIParent, "SecureActionButtonTemplate")
            questItemButton:RegisterForClicks("AnyDown")
            questItemButton:SetAttribute("type", "item")
            questItemButton:Hide()
        end
        if not questItemButton then return end
        ClearOverrideBindings(questItemButton)
        if on then
            SetOverrideBindingClick(questItemButton, true, key:upper(), questItemButton:GetName(), "LeftButton")
            self:UpdateQuestItem()
        end
    end)
end

function QuestTracker:GetQuestItemButton() return questItemButton end

--------------------------------------------------------------------------------
-- Tri, filtres, suivi automatique
--------------------------------------------------------------------------------

local MAX_WATCHES = 25   -- MAX_QUEST_WATCHES
local NO_FACTS = { logIndex = 0, level = 0, title = "", complete = false }
local SORT_KEYS = {
    log = function(facts) return facts.logIndex end,
    level = function(facts) return facts.level end,
    name = function(facts) return facts.title:lower() end,
}

local function Filtered(facts, db)
    if not (facts and db.filterActive) then return false end
    return (db.filterZone and not facts.onMap) or (db.hideComplete and facts.complete)
        or (db.hideTrivial and facts.trivial) or (db.hideRepeatable and (facts.frequency == 1 or facts.frequency == 2))
        or false
end

--- Liste de suivi voulue et vrai si son ordre compte. `watched` : quêtes suivies, dans l'ordre ;
-- `zone` : quêtes de la carte (journal) ; `facts[questID]` : NS.GetQuestFacts, false si hors journal ;
-- `memory` (par personnage, mis à jour ici) : { removed = retirées par un filtre, auto = suivies par
-- nous } ; `session` : { exempt = suivies à la main, untracked = retirées à la main }.
function QuestTracker.WantedWatches(watched, zone, facts, db, memory, session)
    local wanted, listed, inZone = {}, {}, {}
    local function add(questID)
        listed[questID] = true
        wanted[#wanted + 1] = questID
    end
    for _, questID in ipairs(zone) do inZone[questID] = true end
    for _, questID in ipairs(watched) do
        if memory.auto[questID] and not (db.autoTrackZone and inZone[questID]) then
            memory.auto[questID] = nil
        elseif not session.exempt[questID] and Filtered(facts[questID], db) then
            memory.removed[questID] = true
        else
            add(questID)
        end
    end
    local restored = {}
    for questID in pairs(memory.removed) do
        if not facts[questID] then memory.removed[questID] = nil
        elseif not Filtered(facts[questID], db) then restored[#restored + 1] = questID end
    end
    table.sort(restored)
    for _, questID in ipairs(restored) do
        if #wanted >= MAX_WATCHES then break end
        memory.removed[questID] = nil
        add(questID)
    end
    if db.autoTrackZone then
        for _, questID in ipairs(zone) do
            if #wanted >= MAX_WATCHES then break end
            if not listed[questID] and not session.untracked[questID] and not memory.removed[questID]
                and facts[questID] and not Filtered(facts[questID], db) then
                memory.auto[questID] = true
                add(questID)
            end
        end
    end
    local key, completed = SORT_KEYS[db.sortMode], db.completedPosition
    local ordered = key ~= nil or completed == "top" or completed == "bottom"
    if ordered then
        local rank = {}
        for index, questID in ipairs(wanted) do rank[questID] = index end
        table.sort(wanted, function(a, b)
            local fa, fb = facts[a] or NO_FACTS, facts[b] or NO_FACTS
            local doneA, doneB = fa.complete == true, fb.complete == true
            if completed ~= "mixed" and doneA ~= doneB then return doneA == (completed == "top") end
            if key and key(fa) ~= key(fb) then return key(fa) < key(fb) end
            return rank[a] < rank[b]
        end)
    end
    return wanted, ordered
end

local session = { exempt = {}, untracked = {} }
local lastWatched              -- liste après notre dernière passe : tout écart vient du joueur
local insertAtHead = true      -- AddQuestWatch insère en tête (non vérifié) ; inversé si l'ordre relu diffère
local orderFailures = 0        -- deux échecs : plus de réordonnancement jusqu'au prochain changement de zone
local passQueued = false
local mapHooked = false
local blizzardAdded = {}       -- suivies d'office par Blizzard (QUEST_ACCEPTED, QUEST_WATCH_UPDATE) : pas exemptées
local logReady = false         -- un QUEST_LOG_UPDATE reçu : le journal est chargé

local function MapShown() return _G.WorldMapFrame and WorldMapFrame:IsShown() end

local function Memory()
    NS.global.questWatches = NS.global.questWatches or {}
    local key = NS.Database.CharacterKey()
    local memory = NS.global.questWatches[key] or { removed = {}, auto = {} }
    NS.global.questWatches[key] = memory
    return memory
end

local function NoteManualChanges(watched, memory)
    local now = {}
    for _, questID in ipairs(watched) do
        now[questID] = true
        if lastWatched and not lastWatched[questID] and not blizzardAdded[questID] then
            session.exempt[questID], session.untracked[questID], memory.removed[questID] = true, nil, nil
        end
    end
    for questID in pairs(lastWatched or {}) do
        if not now[questID] then session.untracked[questID], memory.auto[questID] = true, nil end
    end
end

--- Écritures minimales : retraits, puis seulement les quêtes hors de la plus longue fin (insertion
-- en tête) ou du plus long début (insertion en fin) déjà à leur place.
local function Rewrite(watched, wanted, ordered)
    local keep, current = {}, {}
    for _, questID in ipairs(wanted) do keep[questID] = true end
    for _, questID in ipairs(watched) do
        if keep[questID] then current[#current + 1] = questID else NS.SetQuestWatched(questID, false) end
    end
    local present = {}
    for _, questID in ipairs(current) do present[questID] = true end
    if not ordered then
        for _, questID in ipairs(wanted) do
            if not present[questID] then NS.SetQuestWatched(questID, true) end
        end
        return
    end
    local count, kept = #wanted, 0
    if insertAtHead then
        while kept < count and current[#current - kept] == wanted[count - kept] do kept = kept + 1 end
        for index = count - kept, 1, -1 do
            if present[wanted[index]] then NS.SetQuestWatched(wanted[index], false) end
            NS.SetQuestWatched(wanted[index], true)
        end
    else
        while kept < count and current[kept + 1] == wanted[kept + 1] do kept = kept + 1 end
        for index = kept + 1, count do
            if present[wanted[index]] then NS.SetQuestWatched(wanted[index], false) end
            NS.SetQuestWatched(wanted[index], true)
        end
    end
end

local function SameList(a, b)
    if #a ~= #b then return false end
    for index = 1, #a do if a[index] ~= b[index] then return false end end
    return true
end

function QuestTracker:SortPass()
    if not active or NS.InCombat() or inEncounter or MapShown() then return end
    -- Journal pas encore chargé : rien lu, rien écrit, rien purgé.
    if not logReady or NS.GetNumQuestLogEntries() == 0 then return end
    local db, memory = self.db, Memory()
    local watched = NS.GetWatchedQuestIDs()
    NoteManualChanges(watched, memory)
    local zone, facts = NS.GetQuestIDsOnMap(), {}
    local function read(questID)
        if facts[questID] == nil then facts[questID] = NS.GetQuestFacts(questID) or false end
    end
    for _, questID in ipairs(watched) do read(questID) end
    for questID in pairs(memory.removed) do read(questID) end
    if db.autoTrackZone then for _, questID in ipairs(zone) do read(questID) end end
    local wasRemoved = {}
    for questID in pairs(memory.removed) do wasRemoved[questID] = true end
    local wanted, ordered = QuestTracker.WantedWatches(watched, zone, facts, db, memory, session)
    ordered = ordered and orderFailures < 2
    Rewrite(watched, wanted, ordered)
    local after = NS.GetWatchedQuestIDs()
    lastWatched = {}
    for _, questID in ipairs(after) do lastWatched[questID] = true end
    -- Ajout refusé par le client : ni suivie par nous, ni sortie de la mémoire des retirées.
    for questID in pairs(memory.auto) do if not lastWatched[questID] then memory.auto[questID] = nil end end
    for _, questID in ipairs(wanted) do
        if wasRemoved[questID] and not lastWatched[questID] then memory.removed[questID] = true end
    end
    blizzardAdded = {}
    if not ordered then return end
    if SameList(after, wanted) then
        orderFailures = 0
    else
        orderFailures, insertAtHead = orderFailures + 1, not insertAtHead
    end
end

-- Une passe 0,2 s après la dernière mise à jour : Blizzard retrie par distance au changement de
-- zone (SortQuestWatches), notre ordre passe après le sien.
local function QueueSort()
    if passQueued or not active then return end
    passQueued = true
    C_Timer.After(0.2, function()
        passQueued = false
        QuestTracker:SortPass()
    end)
end

--- Filtres coupés (module éteint) : les quêtes retirées reviennent au suivi, 25 au plus. Rencontre,
-- carte ouverte ou journal vide : nouvel essai 2 s plus tard, la mémoire reste intacte.
local function RestoreRemoved()
    if active then return end   -- réactivé entre-temps : la passe de tri s'en charge
    if NS.IsEncounterInProgress() or MapShown() or NS.GetNumQuestLogEntries() == 0 then
        C_Timer.After(2, function() NS:RunOutOfCombat(RestoreRemoved) end)
        return
    end
    local memory = Memory()
    local list = {}
    for questID in pairs(memory.removed) do list[#list + 1] = questID end
    table.sort(list)
    local count = #NS.GetWatchedQuestIDs()
    for _, questID in ipairs(list) do
        if count >= MAX_WATCHES then break end
        if not NS.GetQuestFacts(questID) then
            memory.removed[questID] = nil
        elseif NS.SetQuestWatched(questID, true) then
            memory.removed[questID], count = nil, count + 1
        end
    end
end

local filterButton
function UpdateFilterButton()
    local db = QuestTracker.db
    if not filterButton then
        filterButton = CreateFrame("Button", "MuscaUI_QuestTrackerFilter", holder)
        filterButton:SetFrameStrata("MEDIUM")
        filterButton:SetSize(16, 16)
        filterButton:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -28, -2)
        filterButton.icon = filterButton:CreateTexture(nil, "ARTWORK")
        filterButton.icon:SetAllPoints(filterButton)
        filterButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
        Media:CreateBorder(filterButton)
        filterButton:SetScript("OnClick", function(self)
            QuestTracker.db.filterActive = not QuestTracker.db.filterActive
            UpdateFilterButton()
            QueueSort()
            if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
        end)
        filterButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(QuestTracker.db.filterActive and L.QT_FILTER_ON or L.QT_FILTER_OFF)
            GameTooltip:Show()
        end)
        filterButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    filterButton.icon:SetDesaturated(not db.filterActive)
    filterButton:SetShown(active and (db.filterZone or db.hideComplete or db.hideTrivial or db.hideRepeatable) and true or false)
end

local events = CreateFrame("Frame")
local SORT_EVENTS = { QUEST_WATCH_LIST_CHANGED = true, QUEST_LOG_UPDATE = true, QUEST_ACCEPTED = true,
                      ZONE_CHANGED = true, ZONE_CHANGED_NEW_AREA = true, PLAYER_REGEN_ENABLED = true,
                      ENCOUNTER_END = true, PLAYER_ENTERING_WORLD = true, QUEST_WATCH_UPDATE = true }
local VISIBILITY_EVENTS = { PLAYER_TARGET_CHANGED = true, PLAYER_MOUNT_DISPLAY_CHANGED = true,
                            ENCOUNTER_START = true, ENCOUNTER_END = true, GROUP_ROSTER_UPDATE = true,
                            PLAYER_SOFT_ENEMY_CHANGED = true, GAME_PAD_ACTIVE_CHANGED = true,
                            PLAYER_UPDATE_RESTING = true, UNIT_ENTERED_VEHICLE = true, UNIT_EXITED_VEHICLE = true }

events:SetScript("OnEvent", function(_, event, questID)
    if not active then return end
    if event == "QUEST_LOG_UPDATE" then logReady = true end
    if (event == "QUEST_ACCEPTED" or event == "QUEST_WATCH_UPDATE") and questID then blizzardAdded[questID] = true end
    if event == "ENCOUNTER_START" then inEncounter = true
    elseif event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then inEncounter = false end
    QuestTracker:UpdateVisibility(event)
    if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then orderFailures = 0 end
    if SORT_EVENTS[event] then QueueSort() end
    if VISIBILITY_EVENTS[event] or event == "ZONE_CHANGED" or event == "QUEST_ACCEPTED" or event == "QUEST_WATCH_UPDATE" then
        return
    end
    if event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_LIST_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
        QuestTracker:UpdateQuestItem()
    end
    if event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_LIST_CHANGED" then QueueStyle() end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED_NEW_AREA" then
        -- Replier est protégé en combat ; PLAYER_REGEN_ENABLED refera le calcul à la sortie.
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or not NS.InCombat() then
            QuestTracker:UpdateCollapse(event)
        end
    end
    -- Les en-têtes ne changent pas avec le journal de quêtes : QUEST_LOG_UPDATE (fréquent) ne les reprend pas.
    if event ~= "PLAYER_REGEN_DISABLED" and event ~= "PLAYER_REGEN_ENABLED" and event ~= "QUEST_LOG_UPDATE" then
        SkinHeaders()
    end
end)

function QuestTracker:OnEnable()
    if not Tracker() then return end
    active = true
    self:Apply()
    self:BindQuestItem(true)
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
                             "ZONE_CHANGED_NEW_AREA", "QUEST_WATCH_LIST_CHANGED", "QUEST_LOG_UPDATE",
                             "PLAYER_TARGET_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED", "ENCOUNTER_START", "ENCOUNTER_END",
                             "GROUP_ROSTER_UPDATE", "ZONE_CHANGED", "QUEST_ACCEPTED", "QUEST_WATCH_UPDATE",
                             "PLAYER_SOFT_ENEMY_CHANGED", "GAME_PAD_ACTIVE_CHANGED", "PLAYER_UPDATE_RESTING" }) do
        NS.RegisterEventSafe(events, event)
    end
    NS.RegisterEventSafe(events, "UNIT_ENTERED_VEHICLE", "player")
    NS.RegisterEventSafe(events, "UNIT_EXITED_VEHICLE", "player")
    if not mapHooked and _G.WorldMapFrame then
        mapHooked = true
        WorldMapFrame:HookScript("OnHide", QueueSort)   -- passe refusée carte ouverte : reprise à la fermeture
    end
    QueueSort()
end

function QuestTracker:OnDisable()
    if not active then return end
    active = false
    events:UnregisterAllEvents()
    self:BindQuestItem(false)
    if autoCollapsed then autoCollapsed = false self.SetCollapsed(false) end
    NS:RunOutOfCombat(RestoreRemoved)
    lastWatched = nil
    if filterButton then filterButton:Hide() end
    for background in pairs(headerBackgrounds) do NS.ShowRegion(background) end
    for _, header in ipairs(Headers()) do
        if header.foreverOriginalFont and header.Text then header.Text:SetFont(unpack(header.foreverOriginalFont)) end
        if header.muscaOriginalColor and header.Text then header.Text:SetTextColor(unpack(header.muscaOriginalColor)) end
    end
    for line in pairs(dimmedLines) do line:SetAlpha(1) end
    wipe(dimmedLines)
    for fontString in pairs(originalFonts) do RestoreFont(fontString) end
    Tracker():SetAlpha(1)
    holder:Hide()
    NS.Movers:Unregister("questtracker")
    NS.Print(L.MSG_QT_DISABLED_RELOAD)
end

function QuestTracker:OnRefresh()
    if not active then return end
    self:Apply()
    self:BindQuestItem(true)
    orderFailures = 0
    QueueSort()
end

NS:On("PIXEL_CHANGED", function()
    if active then NS:RunOutOfCombat(function() if active then QuestTracker:Apply() end end) end
end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function QuestTracker:BuildOptions(o)
    o.layout:Note(L.NOTE_QT_RELOAD, 20)
    o:Slider("height", L.OPT_QT_HEIGHT, 200, 1000, 10)
    o:Check("skinHeaders", L.OPT_QT_SKIN_HEADERS)
    o:Advanced()
    o:Slider("headerFontSize", L.OPT_QT_HEADER_FONT_SIZE, 10, 20, 1)
    o:EndAdvanced()
    o:Check("collapseInCombat", L.OPT_QT_COLLAPSE_COMBAT)
    o:Check("collapseInInstance", L.OPT_QT_COLLAPSE_INSTANCE)
    o:Dropdown("raidHide", L.OPT_QT_RAID_HIDE, {
        { name = L.OPT_QT_RAID_NEVER, value = "never" }, { name = L.OPT_QT_RAID_ALWAYS, value = "always" },
        { name = L.OPT_QT_RAID_BOSS, value = "boss" },
    })
    o:Dropdown("sortMode", L.OPT_QT_SORT, {
        { name = L.QT_SORT_PROXIMITY, value = "proximity" }, { name = L.QT_SORT_LOG, value = "log" },
        { name = L.QT_SORT_LEVEL, value = "level" }, { name = L.QT_SORT_NAME, value = "name" },
    })
    o:Dropdown("completedPosition", L.OPT_QT_COMPLETED, {
        { name = L.QT_COMPLETED_MIXED, value = "mixed" }, { name = L.QT_COMPLETED_TOP, value = "top" },
        { name = L.QT_COMPLETED_BOTTOM, value = "bottom" },
    })
    o:Check("filterZone", L.OPT_QT_FILTER_ZONE)
    o:Check("hideComplete", L.OPT_QT_HIDE_COMPLETE)
    o:Check("hideTrivial", L.OPT_QT_HIDE_TRIVIAL)
    o:Check("hideRepeatable", L.OPT_QT_HIDE_REPEATABLE)
    o:Check("autoTrackZone", L.OPT_QT_AUTO_TRACK)
    o:Check("styleText", L.OPT_QT_STYLE_TEXT)
    o:Slider("dimCompleted", L.OPT_G_SKIN_QT_DIM, 0, 100, 5, nil, "%d %%")
    o:Slider("backgroundOpacity", L.OPT_G_SKIN_QT_BACKGROUND, 0, 100, 5, nil, "%d %%")
    o:Check("accentLine", L.OPT_G_SKIN_QT_ACCENT_LINE)
    o:Dropdown("colorSource", L.OPT_G_SKIN_QT_COLOR_SOURCE, {
        { name = L.OPT_G_SKIN_QT_COLOR_CUSTOM, value = "custom" }, { name = L.OPT_G_SKIN_QT_COLOR_CLASS, value = "class" },
        { name = L.OPT_G_SKIN_QT_COLOR_ACCENT, value = "accent" },
    })
    o:Advanced()
    o:Slider("titleFontSize", L.OPT_QT_TITLE_FONT_SIZE, 8, 20, 1, 36)
    o:Slider("objectiveFontSize", L.OPT_QT_OBJECTIVE_FONT_SIZE, 8, 20, 1, 36)
    o:Color("titleColor", L.OPT_QT_TITLE_COLOR, 36)
    o:Color("objectiveColor", L.OPT_QT_OBJECTIVE_COLOR, 36)
    o:Color("completeColor", L.OPT_QT_COMPLETE_COLOR, 36)
    o:EditBox("questItemKey", L.OPT_QT_QUEST_ITEM_KEY, 1)
    o:EndAdvanced()
    o.layout:Button(L.OPT_UF_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
    o:Visibility("visibility", L.OPT_VISIBILITY, { noMouseover = true })
end
