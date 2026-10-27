-- Modules/DataBars.lua
-- Barres de données MuscaUI : expérience (avec repos) et réputation suivie. Deux barres
-- déplaçables, texte réglable, infobulle au survol. Les barres Blizzard sont cachées sans
-- reparentage (Edit Mode). Valeurs passées telles quelles aux widgets (jamais comparées si secrètes).
local _, NS = ...
local L = NS.L
local Media = NS.Media

local function Bar(enabled, overrides)
    -- orientation : "HORIZONTAL" ou "VERTICAL" (remplie de bas en haut ; width = longueur, height = épaisseur)
    local cfg = { enabled = enabled, width = 300, height = 10, text = true, orientation = "HORIZONTAL",
                  separators = "none",       -- graduations : "none" | "5" | "10" (pour cent de la barre)
                  textBackground = false,    -- fond sombre derrière le texte
                  textSizeOffset = -2,       -- écart à la police du thème
                  border = true,             -- bordure du thème autour de la barre
                  clickThrough = false,      -- la souris traverse la barre (plus d'infobulle)
                  customColor = false, color = { r = 0.58, g = 0, b = 0.55 } }   -- remplissage à la couleur choisie
    for k, v in pairs(overrides or {}) do cfg[k] = v end
    return cfg
end

local DataBars = NS.Modules:Register("databars", {
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    titleKey = "DATABARS_TITLE",
    descKey = "DATABARS_DESC",
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
    local frame = CreateFrame("Frame", "MuscaUI_DataBar_" .. key, UIParent)
    frame.key = key
    frame:SetFrameStrata("LOW")
    frame:EnableMouse(true)
    local _, edges = Media:CreateBackdrop(frame)
    frame.edges = edges
    -- Repos créé avant la barre principale : dessiné dessous, seule la part au-delà de l'XP dépasse.
    frame.rested = Media:CreateStatusBar(frame)
    frame.rested:SetAllPoints(frame)
    frame.rested:SetStatusBarColor(unpack(RESTED_COLOR))
    frame.rested.bg:Hide()
    frame.bar = Media:CreateStatusBar(frame)
    frame.bar:SetAllPoints(frame)
    frame.text = Media:CreateText(frame.bar, "OVERLAY", -2)
    frame.text:SetPoint("CENTER")
    frame.textBackground = frame.bar:CreateTexture(nil, "ARTWORK")
    NS.SetSolidColor(frame.textBackground, 0, 0, 0, 0.6)
    frame.textBackground:SetPoint("TOPLEFT", frame.text, "TOPLEFT", -S(3), S(1))
    frame.textBackground:SetPoint("BOTTOMRIGHT", frame.text, "BOTTOMRIGHT", S(3), -S(1))
    frame.separators = {}
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
    local vertical = cfg.orientation == "VERTICAL"
    if vertical then frame:SetSize(S(cfg.height), S(cfg.width)) else frame:SetSize(S(cfg.width), S(cfg.height)) end
    for _, bar in ipairs({ frame.bar, frame.rested }) do
        bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        if bar.SetRotatesTexture then bar:SetRotatesTexture(vertical) end
    end
    -- Texte tourné d'un quart de tour le long d'une barre verticale.
    if frame.text.SetRotation then frame.text:SetRotation(vertical and math.pi / 2 or 0) end
    if cfg.text then frame.text:Show() else frame.text:Hide() end
    Media:SetTextSizeDelta(frame.text, cfg.textSizeOffset)
    frame.textBackground:SetShown(cfg.text and cfg.textBackground)
    for _, edge in pairs(frame.edges or {}) do edge:SetShown(cfg.border) end
    frame:EnableMouse(not cfg.clickThrough)
    DataBars.LayoutSeparators(frame, cfg)
end

--- Pas des graduations en pour cent de la barre : 5, 10, ou nil sans graduations.
function DataBars.SeparatorStep(value)
    return value == "5" and 5 or value == "10" and 10 or nil
end

--- Graduations (traits fins) tous les 5 ou 10 % de la barre, réutilisées d'un réglage à l'autre.
function DataBars.LayoutSeparators(frame, cfg)
    local step = DataBars.SeparatorStep(cfg.separators)
    local vertical = cfg.orientation == "VERTICAL"
    local length = S(cfg.width)   -- la longueur de la barre, quelle que soit l'orientation
    local count = step and (100 / step - 1) or 0
    for i = 1, math.max(count, #frame.separators) do
        local line = frame.separators[i]
        if i <= count then
            if not line then
                line = frame.bar:CreateTexture(nil, "OVERLAY")
                NS.SetSolidColor(line, 0, 0, 0, 0.7)
                frame.separators[i] = line
            end
            local offset = length * i * step / 100
            line:ClearAllPoints()
            if vertical then
                line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, offset)
                line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, offset)
                line:SetHeight(S(1))
            else
                line:SetPoint("TOPLEFT", frame, "TOPLEFT", offset, 0)
                line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offset, 0)
                line:SetWidth(S(1))
            end
            line:Show()
        elseif line then
            line:Hide()
        end
    end
end

--- Couleur de remplissage : celle choisie si `customColor`, sinon `default` ({ r, g, b } en liste).
function DataBars.FillColor(cfg, default)
    if cfg.customColor then return cfg.color.r, cfg.color.g, cfg.color.b end
    return default[1], default[2], default[3]
end

function DataBars.Update_xp(frame)
    if DataBars.AtMaxLevel() then frame:Hide() return end
    frame:Show()
    local cur, max, rested = UnitXP("player"), UnitXPMax("player"), GetXPExhaustion()
    frame.bar:SetMinMaxValues(0, max)
    frame.bar:SetValue(cur)
    local custom = DataBars.db.bars.xp
    frame.bar:SetStatusBarColor(DataBars.FillColor(custom, XP_COLOR))
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
    frame.bar:SetStatusBarColor(DataBars.FillColor(DataBars.db.bars.rep, color))
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
        o:Dropdown("bars." .. key .. ".orientation", L.OPT_BAR_ORIENTATION, {
            { name = L.OPT_BAR_HORIZONTAL, value = "HORIZONTAL" }, { name = L.OPT_BAR_VERTICAL, value = "VERTICAL" },
        })
        o:Slider("bars." .. key .. ".width", L.OPT_BAR_LENGTH, 100, 800, 10)
        o:Slider("bars." .. key .. ".height", L.OPT_BAR_THICKNESS, 4, 30, 1)
        o:Check("bars." .. key .. ".text", L.OPT_DATABARS_TEXT)
        o:Advanced()
        o:Check("bars." .. key .. ".textBackground", L.OPT_G_MAP_BAR_TEXT_BACKGROUND, 36)
        o:Slider("bars." .. key .. ".textSizeOffset", L.OPT_G_MAP_BAR_TEXT_SIZE, -6, 8, 1, 36)
        o:Dropdown("bars." .. key .. ".separators", L.OPT_G_MAP_BAR_SEPARATORS, {
            { name = L.OPT_G_MAP_BAR_SEPARATORS_NONE, value = "none" },
            { name = "5 %", value = "5" }, { name = "10 %", value = "10" },
        }, 36)
        o:Check("bars." .. key .. ".border", L.OPT_G_MAP_BAR_BORDER, 36)
        o:Check("bars." .. key .. ".clickThrough", L.OPT_G_MAP_BAR_CLICK_THROUGH, 36)
        o:Check("bars." .. key .. ".customColor", L.OPT_G_MAP_BAR_CUSTOM_COLOR, 36)
        o:Color("bars." .. key .. ".color", L.OPT_G_MAP_BAR_COLOR, 52)
        o:EndAdvanced()
    end
end
