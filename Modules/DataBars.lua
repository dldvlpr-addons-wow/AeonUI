-- Modules/DataBars.lua
-- Barres de données AeonUI : expérience (avec repos) et réputation suivie. Deux barres
-- déplaçables, texte réglable, infobulle au survol. Les barres Blizzard sont cachées sans
-- reparentage (Edit Mode). Valeurs passées telles quelles aux widgets (jamais comparées si secrètes).
local _, NS = ...
local L = NS.L
local Media = NS.Media

local function Bar(enabled, overrides)
    local cfg = { enabled = enabled, width = 300, height = 10, text = true }
    for k, v in pairs(overrides or {}) do cfg[k] = v end
    return cfg
end

local DataBars = NS.Modules:Register("databars", {
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    titleKey = "DATABARS_TITLE",
    descKey = "DATABARS_DESC",
    yieldsTo = { "ElvUI" },
    defaults = {
        enabled = false,
        hideBlizzard = true,
        bars = { xp = Bar(true), rep = Bar(true) },
    },
})

local BLIZZARD = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
                   "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar" }
local MOVER_DEFAULTS = { xp = { "BOTTOM", 0, 6 }, rep = { "BOTTOM", 0, 20 } }
local XP_COLOR = { 0.58, 0.0, 0.55 }
local RESTED_COLOR = { 0.0, 0.39, 0.88, 0.5 }
local REACTION_COLORS = { [1] = { 0.8, 0.13, 0.13 }, [2] = { 0.8, 0.13, 0.13 }, [3] = { 0.75, 0.27, 0 },
                          [4] = { 0.9, 0.7, 0 }, [5] = { 0, 0.6, 0.1 }, [6] = { 0, 0.6, 0.1 },
                          [7] = { 0, 0.6, 0.1 }, [8] = { 0, 0.6, 0.1 } }

local active = false
DataBars.frames = {}

local function Known(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

local function S(n) return NS.Pixel:Scale(n) end

--------------------------------------------------------------------------------
-- Données (pures)
--------------------------------------------------------------------------------

function DataBars.AtMaxLevel()
    local level, max = Known(UnitLevel("player")), Known(GetMaxPlayerLevel and GetMaxPlayerLevel())
    if not level or not max then return false end
    return level >= max or (IsXPUserDisabled and IsXPUserDisabled() == true)
end

--- Faction suivie : name, standingID, min, max, value (tout client), ou nil.
function DataBars.WatchedFaction()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local data = C_Reputation.GetWatchedFactionData()
        if not data or not data.name then return nil end
        return data.name, data.standingID or data.reaction, data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
    end
    if GetWatchedFactionInfo then
        local name, standing, min, max, value = GetWatchedFactionInfo()
        if name then return name, standing, min, max, value end
    end
    return nil
end

local function Percent(value, max)
    value, max = Known(value), Known(max)
    if not value or not max or max <= 0 then return nil end
    return value / max * 100
end

--------------------------------------------------------------------------------
-- Cadres
--------------------------------------------------------------------------------

local function Create(key)
    local frame = CreateFrame("Frame", "AeonUI_DataBar_" .. key, UIParent)
    frame.key = key
    frame:SetFrameStrata("LOW")
    frame:EnableMouse(true)
    Media:CreateBackdrop(frame)
    -- Repos créé avant la barre principale : dessiné dessous, seule la part au-delà de l'XP dépasse.
    frame.rested = Media:CreateStatusBar(frame)
    frame.rested:SetAllPoints(frame)
    frame.rested:SetStatusBarColor(unpack(RESTED_COLOR))
    frame.rested.bg:Hide()
    frame.bar = Media:CreateStatusBar(frame)
    frame.bar:SetAllPoints(frame)
    frame.text = Media:CreateText(frame.bar, "OVERLAY", -2)
    frame.text:SetPoint("CENTER")
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        DataBars["Tooltip_" .. key](GameTooltip)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    DataBars.frames[key] = frame
    return frame
end

local function Layout(frame, cfg)
    frame:SetSize(S(cfg.width), S(cfg.height))
    if cfg.text then frame.text:Show() else frame.text:Hide() end
end

function DataBars.Update_xp(frame)
    if DataBars.AtMaxLevel() then frame:Hide() return end
    frame:Show()
    local cur, max, rested = UnitXP("player"), UnitXPMax("player"), GetXPExhaustion()
    frame.bar:SetMinMaxValues(0, max)
    frame.bar:SetValue(cur)
    frame.bar:SetStatusBarColor(unpack(XP_COLOR))
    if Known(rested) and rested > 0 then
        frame.rested:Show()
        frame.rested:SetMinMaxValues(0, max)
        frame.rested:SetValue(cur + rested)
    else
        frame.rested:Hide()
    end
    local pct = Percent(cur, max)
    frame.text:SetText(pct and string.format("%s / %s  (%.1f %%)%s", AbbreviateNumbers(cur), AbbreviateNumbers(max), pct,
        Known(rested) and rested > 0 and string.format("  +%s", AbbreviateNumbers(rested)) or "") or "")
end

function DataBars.Tooltip_xp(tt)
    local cur, max, rested = UnitXP("player"), UnitXPMax("player"), GetXPExhaustion()
    tt:AddLine(L.DATABARS_XP)
    tt:AddDoubleLine(L.DATABARS_XP_CURRENT, string.format("%s / %s", AbbreviateNumbers(cur), AbbreviateNumbers(max)), 1, 1, 1, 1, 1, 1)
    if Known(rested) and rested > 0 then tt:AddDoubleLine(L.DATABARS_XP_RESTED, AbbreviateNumbers(rested), 1, 1, 1, 0.4, 0.6, 1) end
end

function DataBars.Update_rep(frame)
    local name, standing, min, max, value = DataBars.WatchedFaction()
    if not name then frame:Hide() return end
    frame:Show()
    frame.rested:Hide()
    local span, progress = (Known(max) or 0) - (Known(min) or 0), (Known(value) or 0) - (Known(min) or 0)
    frame.bar:SetMinMaxValues(0, span > 0 and span or 1)
    frame.bar:SetValue(progress)
    local color = REACTION_COLORS[Known(standing) or 0] or { 0.5, 0.5, 0.5 }
    frame.bar:SetStatusBarColor(unpack(color))
    local label = _G["FACTION_STANDING_LABEL" .. tostring(Known(standing) or "")] or ""
    local pct = Percent(progress, span)
    frame.text:SetText(pct and string.format("%s: %s  %s / %s  (%.0f %%)", name, label, AbbreviateNumbers(progress), AbbreviateNumbers(span), pct) or name)
end

function DataBars.Tooltip_rep(tt)
    local name, standing, min, max, value = DataBars.WatchedFaction()
    if not name then tt:AddLine(L.DATABARS_REP_NONE) return end
    tt:AddLine(name)
    local label = _G["FACTION_STANDING_LABEL" .. tostring(Known(standing) or "")] or ""
    tt:AddDoubleLine(label, string.format("%s / %s", AbbreviateNumbers((Known(value) or 0) - (Known(min) or 0)), AbbreviateNumbers((Known(max) or 0) - (Known(min) or 0))), 1, 1, 1, 1, 1, 1)
end

local function Setup(key)
    local cfg = DataBars.db.bars[key]
    local frame = DataBars.frames[key] or Create(key)
    Layout(frame, cfg)
    local d = MOVER_DEFAULTS[key]
    NS.Movers:Register("databar_" .. key, frame, L["MOVER_DATABAR_" .. key:upper()], d[1], d[2], d[3])
    NS.Movers:Load("databar_" .. key)
    DataBars["Update_" .. key](frame)
end

local function Teardown(key)
    local frame = DataBars.frames[key]
    if frame then frame:Hide() end
    NS.Movers:Unregister("databar_" .. key)
end

function DataBars:Reconcile()
    for _, key in ipairs({ "xp", "rep" }) do
        if self.db.bars[key].enabled then Setup(key) else Teardown(key) end
    end
    for _, name in ipairs(BLIZZARD) do
        if self.db.hideBlizzard then NS.HideBlizzardFrame(name, true) else NS.ShowBlizzardFrame(name) end
    end
end

function DataBars:Update()
    for key, frame in pairs(self.frames) do
        if self.db.bars[key].enabled then self["Update_" .. key](frame) end
    end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    if active then DataBars:Update() end
end)

function DataBars:OnEnable()
    active = true
    self:Reconcile()
    for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION",
                             "PLAYER_ENTERING_WORLD", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN" }) do
        NS.RegisterEventSafe(events, event)
    end
end

function DataBars:OnDisable()
    active = false
    events:UnregisterAllEvents()
    for _, key in ipairs({ "xp", "rep" }) do Teardown(key) end
    for _, name in ipairs(BLIZZARD) do NS.ShowBlizzardFrame(name) end
    if next(self.frames) then NS.Print(L.MSG_DATABARS_DISABLED_RELOAD) end
end

function DataBars:OnRefresh()
    if active then self:Reconcile() end
end

NS:On("PIXEL_CHANGED", function() if active then DataBars:Reconcile() end end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function DataBars:BuildOptions(o)
    o.layout:Note(L.NOTE_DATABARS_RELOAD, 20)
    o:Check("hideBlizzard", L.OPT_DATABARS_HIDE_BLIZZARD)
    o.layout:Button(L.OPT_UF_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
    for _, key in ipairs({ "xp", "rep" }) do
        o:Tab(L["DATABARS_" .. key:upper()])
        o:Check("bars." .. key .. ".enabled", L.OPT_DATABARS_ENABLED)
        o:Slider("bars." .. key .. ".width", L.OPT_UF_WIDTH, 100, 800, 10)
        o:Slider("bars." .. key .. ".height", L.OPT_UF_HEIGHT, 4, 30, 1)
        o:Check("bars." .. key .. ".text", L.OPT_DATABARS_TEXT)
    end
end
