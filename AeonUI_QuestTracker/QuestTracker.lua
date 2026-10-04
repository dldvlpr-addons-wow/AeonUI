-- AeonUI_QuestTracker/QuestTracker.lua
-- Suivi de quêtes AeonUI : le suivi Blizzard (ObjectiveTrackerFrame, ou WatchFrame sur un
-- client plus ancien) est posé sur un support déplaçable, à la hauteur voulue, en-têtes au thème
-- (fond caché, police), et replié de lui-même en combat ou en instance si demandé.
--
-- Le cadre Blizzard n'est pas reparenté (système Edit Mode) : réancré seulement, un hook de
-- SetPoint reprend la main si Blizzard le replace. Les API de repli changent selon le moteur :
-- SetCollapsed, sinon ObjectiveTracker_Collapse/Expand, sinon rien (tout en pcall).
local NS = AeonUI
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
        questItemKey = "",        -- touche qui utilise l'objet de quête (suivie d'abord), vide = aucune
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
local inEncounter = false

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
    fontString:SetFont(Media:Font(), size, Media:Outline())
    fontString:SetTextColor(color.r, color.g, color.b)
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

function QuestTracker:StyleBlocks()
    local db = self.db
    if not active then return end
    EachBlock(function(block)
        local lines = type(block.usedLines) == "table" and block.usedLines or {}
        if not db.styleText then
            RestoreFont(block.HeaderText)
            for _, line in pairs(lines) do if type(line) == "table" then RestoreFont(line.Text) end end
            return
        end
        local complete = QuestTracker.QuestComplete(block)
        StyleFont(block.HeaderText, db.titleFontSize, complete and db.completeColor or db.titleColor)
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
            if db.skinHeaders then
                text:SetFont(Media:Font(), db.headerFontSize, Media:Outline())
            else
                text:SetFont(unpack(header.foreverOriginalFont))
            end
        end
    end
end

local function Build()
    holder = CreateFrame("Frame", "AeonUI_QuestTracker", UIParent)
    holder:SetFrameStrata("LOW")
    if not hooked then
        hooked = true
        hooksecurefunc(Tracker(), "SetPoint", function()
            if active and not anchoring then AnchorTracker() end
        end)
        if Tracker().Update then hooksecurefunc(Tracker(), "Update", QueueStyle) end
    end
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
    SkinHeaders()
    self:UpdateCollapse()
    self:UpdateVisibility()
    self:StyleBlocks()
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
            questItemButton = CreateFrame("Button", "AeonUIQuestItemButton", UIParent, "SecureActionButtonTemplate")
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

local events = CreateFrame("Frame")
local VISIBILITY_EVENTS = { PLAYER_TARGET_CHANGED = true, PLAYER_MOUNT_DISPLAY_CHANGED = true,
                            ENCOUNTER_START = true, ENCOUNTER_END = true, GROUP_ROSTER_UPDATE = true }

events:SetScript("OnEvent", function(_, event)
    if not active then return end
    if event == "ENCOUNTER_START" then inEncounter = true
    elseif event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then inEncounter = false end
    QuestTracker:UpdateVisibility(event)
    if VISIBILITY_EVENTS[event] then return end
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
    if event ~= "PLAYER_REGEN_DISABLED" and event ~= "PLAYER_REGEN_ENABLED" then SkinHeaders() end
end)

function QuestTracker:OnEnable()
    if not Tracker() then return end
    active = true
    self:Apply()
    self:BindQuestItem(true)
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
                             "ZONE_CHANGED_NEW_AREA", "QUEST_WATCH_LIST_CHANGED", "QUEST_LOG_UPDATE",
                             "PLAYER_TARGET_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED", "ENCOUNTER_START", "ENCOUNTER_END",
                             "GROUP_ROSTER_UPDATE" }) do
        NS.RegisterEventSafe(events, event)
    end
end

function QuestTracker:OnDisable()
    if not active then return end
    active = false
    events:UnregisterAllEvents()
    self:BindQuestItem(false)
    if autoCollapsed then autoCollapsed = false self.SetCollapsed(false) end
    for background in pairs(headerBackgrounds) do NS.ShowRegion(background) end
    for _, header in ipairs(Headers()) do
        if header.foreverOriginalFont and header.Text then header.Text:SetFont(unpack(header.foreverOriginalFont)) end
    end
    for fontString in pairs(originalFonts) do RestoreFont(fontString) end
    Tracker():SetAlpha(1)
    holder:Hide()
    NS.Movers:Unregister("questtracker")
    NS.Print(L.MSG_QT_DISABLED_RELOAD)
end

function QuestTracker:OnRefresh()
    if active then self:Apply() self:BindQuestItem(true) end
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
    o:Check("styleText", L.OPT_QT_STYLE_TEXT)
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
