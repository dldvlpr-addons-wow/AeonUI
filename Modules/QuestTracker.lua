-- Modules/QuestTracker.lua
-- Suivi de quêtes AeonUI : le suivi Blizzard (ObjectiveTrackerFrame, ou WatchFrame sur un
-- client plus ancien) est posé sur un support déplaçable, à la hauteur voulue, en-têtes au thème
-- (fond caché, police), et replié de lui-même en combat ou en instance si demandé.
--
-- Le cadre Blizzard n'est pas reparenté (système Edit Mode) : réancré seulement, un hook de
-- SetPoint reprend la main si Blizzard le replace. Les API de repli changent selon le moteur :
-- SetCollapsed, sinon ObjectiveTracker_Collapse/Expand, sinon rien (tout en pcall).
local _, NS = ...
local L = NS.L
local Media = NS.Media

local QuestTracker = NS.Modules:Register("questtracker", {
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    secure = true,            -- le suivi contient des boutons d'objets sécurisés : rien en combat
    titleKey = "QT_TITLE",
    descKey = "QT_DESC",
    yieldsTo = { "ElvUI" },
    defaults = {
        enabled = false,
        height = 500,
        skinHeaders = true,
        headerFontSize = 14,
        collapseInCombat = false,
        collapseInInstance = false,
    },
})

local HEADER_KEYS = { "QuestHeader", "AchievementHeader", "ScenarioHeader", "CampaignQuestHeader",
                      "ProfessionHeader", "MonthlyActivitiesHeader", "BonusObjectiveHeader", "WorldQuestHeader" }

local active = false
local holder
local anchoring, hooked = false, false
local autoCollapsed = false      -- replié par nous (combat ou instance) : à rouvrir
local headerBackgrounds = {}     -- fonds cachés

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
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if not active then return end
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
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
                             "ZONE_CHANGED_NEW_AREA", "QUEST_WATCH_LIST_CHANGED", "QUEST_LOG_UPDATE" }) do
        NS.RegisterEventSafe(events, event)
    end
end

function QuestTracker:OnDisable()
    if not active then return end
    active = false
    events:UnregisterAllEvents()
    if autoCollapsed then autoCollapsed = false self.SetCollapsed(false) end
    for background in pairs(headerBackgrounds) do NS.ShowRegion(background) end
    for _, header in ipairs(Headers()) do
        if header.foreverOriginalFont and header.Text then header.Text:SetFont(unpack(header.foreverOriginalFont)) end
    end
    holder:Hide()
    NS.Movers:Unregister("questtracker")
    NS.Print(L.MSG_QT_DISABLED_RELOAD)
end

function QuestTracker:OnRefresh()
    if active then self:Apply() end
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
    o:Slider("headerFontSize", L.OPT_QT_HEADER_FONT_SIZE, 10, 20, 1)
    o:Check("collapseInCombat", L.OPT_QT_COLLAPSE_COMBAT)
    o:Check("collapseInInstance", L.OPT_QT_COLLAPSE_INSTANCE)
    o.layout:Button(L.OPT_UF_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
end
