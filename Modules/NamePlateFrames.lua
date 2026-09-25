-- Modules/NamePlateFrames.lua
-- Plaques de nom AeonUI : sur chaque plaque Blizzard, un cadre AeonUI (santé, nom, niveau,
-- barre d'incantation, marqueur de raid, débuffs, surbrillance de la cible, couleur de menace).
--
-- Nos cadres sont des enfants d'UIParent ancrés sur la plaque, jamais reparentés sous elle : une
-- plaque est protégée en combat, un enfant hériterait de la protection. L'habillage Blizzard de
-- la plaque (plate.UnitFrame) est rendu invisible (alpha 0) et coupé de ses événements ; il
-- revient au /reload après désactivation. Le module « Barres de nom » (chevrons) reste compatible.
--
-- Filtres de style : règles « si (cible, incantation, combat, réaction, classification, quête,
-- vie sous x %, nom) alors (couleur, lueur, taille, opacité, masquer) ». La première règle active
-- qui correspond s'applique. Une condition illisible (valeur secrète) fait échouer la règle.
local _, NS = ...
local L = NS.L
local Elements = NS.UnitFrameElements

local NUM_STYLE_RULES = 5   -- ponytail: emplacements fixes, liste dynamique si 5 ne suffit pas

local function StyleRule()
    return {
        enabled = false,
        -- Conditions : "any" | "yes" | "no" (réaction : "any" | "hostile" | "friendly").
        target = "any", casting = "any", combat = "any", reaction = "any",
        classification = "any",   -- "any" | "normal" | "elite" | "rare" | "boss"
        quest = false,            -- unité liée à une quête en cours
        healthBelow = 0,          -- vie sous ce pourcentage (0 = ignoré)
        names = "",               -- noms séparés par des virgules (vide = ignoré)
        -- Actions.
        color = false, colorValue = { r = 1, g = 0.5, b = 0 },
        glow = false, scale = 1, alpha = 1, hide = false,
    }
end
-- Clés chaînes (rule1…rule5) : l'export de profil et le miroir CVar n'aplatissent que celles-là.
local STYLE_RULES, RULE_KEYS = {}, {}
for i = 1, NUM_STYLE_RULES do
    RULE_KEYS[i] = "rule" .. i
    STYLE_RULES[RULE_KEYS[i]] = StyleRule()
end

local NamePlateFrames = NS.Modules:Register("nameplateframes", {
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    titleKey = "NPF_TITLE",
    descKey = "NPF_DESC",
    yieldsTo = { "ElvUI" },
    defaults = {
        enabled = false,
        width = 120, height = 10, castbarHeight = 10, auraSize = 18,
        showName = true, showLevel = true, showCastbar = true, showAuras = true,
        showBuffs = true,            -- buffs de l'unité en ligne au-dessus des débuffs
        friendlyHealth = false,      -- alliés : nom seul
        targetHighlight = true, threatColor = true, classColor = true,
        hideBlizzard = true,
        healthText = "none",         -- préréglage : UnitFrameElements.TEXT_PRESETS
        healthFormat = "",           -- format à jetons, prime sur healthText
        auraFilter = "mine",         -- NS.AURA_FILTERS : sur une plaque, tes débuffs d'abord
        fontDelta = -1,              -- taille des textes de plaque par rapport au thème (-4 à +4)
        styleRules = STYLE_RULES,    -- filtres de style, dans l'ordre de priorité
    },
})

local active = false
local plates = {}      -- [plate Blizzard] = cadre AeonUI (pool, réutilisé)
local byUnit = {}      -- [jeton nameplateN] = cadre monté
local hiddenBlizzard = setmetatable({}, { __mode = "k" })   -- [plate.UnitFrame] = true

NamePlateFrames.byUnit = byUnit

local THREAT_COLORS = {
    [3] = { 0.85, 0.2, 0.2 },    -- agro sur toi
    [2] = { 0.95, 0.55, 0.1 },   -- en train de la perdre / de la prendre
    [1] = { 0.95, 0.85, 0.2 },   -- menace élevée sans agro
}

--- Couleur de menace connue, ou nil (pas de menace, valeur secrète, API absente).
function NamePlateFrames.ThreatColor(unit)
    if not _G.UnitThreatSituation then return nil end
    local ok, status = pcall(UnitThreatSituation, "player", unit)
    if not ok or NS.IsSecret(status) or status == nil then return nil end
    local c = THREAT_COLORS[status]
    if c then return c[1], c[2], c[3] end
    return nil
end

--------------------------------------------------------------------------------
-- Cadres
--------------------------------------------------------------------------------

local function IsFriendly(unit)
    if not _G.UnitCanAttack then return false end
    local canAttack = UnitCanAttack("player", unit)
    if NS.IsSecret(canAttack) then return false end   -- dans le doute : traité en hostile (barre visible)
    return not canAttack
end

local function IsTarget(unit)
    local same = NS.IsTarget(unit)
    return same == true
end

--------------------------------------------------------------------------------
-- Filtres de style
--------------------------------------------------------------------------------

local function Known(value)
    if NS.IsSecret(value) or value == nil then return nil end
    return value
end

--- Condition tri-état : "any" passe, sinon compare au booléen connu (nil = illisible, échoue).
local function TriState(setting, value)
    if setting == "any" then return true end
    if value == nil then return false end
    return (setting == "yes") == value
end

local CAST_APIS = { "UnitCastingInfo", "UnitChannelInfo" }

local function IsCasting(unit)
    for _, api in ipairs(CAST_APIS) do
        if _G[api] then
            local name = _G[api](unit)
            if NS.IsSecret(name) or name ~= nil then return true end   -- secret : une incantation existe
        end
    end
    return false
end

local CLASSIFICATIONS = {
    normal = { normal = true, trivial = true, minus = true },
    elite = { elite = true, rareelite = true, worldboss = true },
    rare = { rare = true, rareelite = true },
    boss = { worldboss = true },
}

local function Classification(setting, unit)
    if setting == "any" then return true end
    if setting == "boss" and _G.UnitLevel and Known(UnitLevel(unit)) == -1 then return true end
    local class = _G.UnitClassification and Known(UnitClassification(unit))
    return class ~= nil and CLASSIFICATIONS[setting] ~= nil and CLASSIFICATIONS[setting][class] == true
end

local function IsQuestUnit(unit)
    local api = _G.C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest or _G.UnitIsQuestBoss
    if not api then return nil end
    local ok, related = pcall(api, unit)
    return ok and Known(related) or nil
end

local function HealthBelow(threshold, unit)
    if (tonumber(threshold) or 0) <= 0 then return true end
    local cur, max = Known(UnitHealth(unit)), Known(UnitHealthMax(unit))
    if not (cur and max) or max <= 0 then return false end
    return cur / max * 100 < threshold
end

-- string.lower ne connaît que l'ASCII : capitales accentuées du français abaissées à la main.
local ACCENTED = { ["À"] = "à", ["Â"] = "â", ["Ä"] = "ä", ["Ç"] = "ç", ["É"] = "é", ["È"] = "è", ["Ê"] = "ê",
                   ["Ë"] = "ë", ["Î"] = "î", ["Ï"] = "ï", ["Ô"] = "ô", ["Ö"] = "ö", ["Ù"] = "ù", ["Û"] = "û",
                   ["Ü"] = "ü", ["Œ"] = "œ" }

local function Lower(text)
    return (text:gsub("\195[\128-\159]", ACCENTED):gsub("\197\146", ACCENTED):lower())
end

local function NameMatches(names, unit)
    if type(names) ~= "string" or not names:find("%S") then return true end
    local name = Known(UnitName(unit))
    if not name then return false end
    name = Lower(name)
    for raw in names:gmatch("[^,]+") do
        local entry = Lower(raw:match("^%s*(.-)%s*$"))
        if entry ~= "" and name:find(entry, 1, true) then return true end
    end
    return false
end

--- La règle correspond-elle à l'unité ? Conditions évaluées de la moins coûteuse à la plus coûteuse.
function NamePlateFrames.RuleMatches(rule, unit)
    if not rule.enabled then return false end
    if rule.reaction ~= "any" then
        -- Lecture directe : IsFriendly traite un secret en hostile, une règle doit échouer.
        local canAttack = _G.UnitCanAttack and UnitCanAttack("player", unit)
        if NS.IsSecret(canAttack) or canAttack == nil then return false end
        if (rule.reaction == "friendly") ~= not canAttack then return false end
    end
    if rule.target ~= "any" and not TriState(rule.target, NS.IsTarget(unit)) then return false end   -- nil si secret
    if rule.casting ~= "any" and not TriState(rule.casting, IsCasting(unit)) then return false end
    if rule.combat ~= "any" and not TriState(rule.combat, Known(UnitAffectingCombat(unit))) then return false end
    if not Classification(rule.classification, unit) then return false end
    if rule.quest and IsQuestUnit(unit) ~= true then return false end
    if not HealthBelow(rule.healthBelow, unit) then return false end
    return NameMatches(rule.names, unit)
end

--- Première règle active qui correspond, ou nil.
function NamePlateFrames:MatchStyle(unit)
    local rules = self.db.styleRules
    for _, key in ipairs(RULE_KEYS) do
        local rule = rules[key]
        if rule and NamePlateFrames.RuleMatches(rule, unit) then return rule end
    end
    return nil
end

--- Une règle active teste-t-elle la quête ? (QUEST_LOG_UPDATE arrive en rafales.)
function NamePlateFrames:HasQuestRule()
    for _, key in ipairs(RULE_KEYS) do
        local rule = self.db.styleRules[key]
        if rule and rule.enabled and rule.quest then return true end
    end
    return false
end

--- Applique la règle par-dessus la couleur de vie et l'opacité déjà posées. Appelée en dernier
-- par UpdateHighlight, lui-même appelé par UpdateHealth : couleur et opacité sont reposées avant,
-- donc une règle qui cesse de correspondre ne laisse rien derrière elle.
function NamePlateFrames:ApplyStyle(frame)
    if not frame.unit then return end
    local rule = self:MatchStyle(frame.unit)
    frame.styleRule = rule
    -- Bornes : une valeur importée d'une chaîne tierce ne doit pas lever d'erreur (SetScale(0)).
    local scale = math.max(0.5, math.min(2, rule and tonumber(rule.scale) or 1))
    if frame.styleScale ~= scale then
        frame.styleScale = scale
        frame:SetScale(scale)
    end
    if not rule then frame.styleGlow:Hide() return end
    local c = rule.colorValue
    if rule.color then frame.health:SetStatusBarColor(c.r, c.g, c.b) end
    if rule.glow and not frame.cfg.healthHidden then   -- allié en nom seul : pas d'aplat sous le nom
        NS.SetSolidColor(frame.styleGlow, c.r, c.g, c.b, 0.6)
        frame.styleGlow:Show()
    else
        frame.styleGlow:Hide()
    end
    local alpha = math.max(0, math.min(1, tonumber(rule.alpha) or 1))
    if rule.hide then frame:SetAlpha(0)
    elseif alpha < 1 then frame:SetAlpha(alpha) end
end

local function Config(unit)
    local db = NamePlateFrames.db
    local friendly = IsFriendly(unit)
    return {
        plate = true,
        width = db.width, height = db.height,
        power = false, powerHeight = 0, combo = false,
        castbar = db.showCastbar, castbarHeight = db.castbarHeight,
        auras = db.showAuras and not friendly, auraSize = db.auraSize, aurasAbove = true, aurasManual = true,
        buffs = db.showBuffs,
        auraFilter = db.auraFilter, healthFormat = db.healthFormat,
        name = db.showName, level = db.showLevel,
        healthHidden = friendly and not db.friendlyHealth,
    }
end

local function NewFrame()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("BACKGROUND")
    frame.border = NS.Media:CreateBorder(frame)
    -- Lueur des filtres de style : aplat coloré qui déborde, sous la barre.
    frame.styleGlow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.styleGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
    frame.styleGlow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
    frame.styleGlow:Hide()
    frame.global = NamePlateFrames.db
    frame.cfg = Config("player")
    Elements.Build(frame)
    return frame
end

--- Nom et niveau au-dessus de la barre : une plaque de 10 px n'a pas la place dedans.
local function PlateLayout(frame)
    Elements.Layout(frame)
    local px = NS.Pixel:Scale(1)
    local delta = tonumber(frame.global.fontDelta) or -1
    if frame.fontDelta ~= delta then
        frame.fontDelta = delta
        NS.Media:SetTextSizeDelta(frame.name, delta)
        NS.Media:SetTextSizeDelta(frame.level, delta - 1)
        NS.Media:SetTextSizeDelta(frame.health.text, delta - 1)
        NS.Media:SetTextSizeDelta(frame.castbar.text, delta - 1)
    end
    -- Nom et niveau sont créés enfants de la barre de vie : cacher la barre (alliés) les cacherait.
    frame.name:SetParent(frame)
    frame.level:SetParent(frame)
    frame.name:ClearAllPoints()
    frame.name:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, px + 1)
    frame.name:SetWidth(frame:GetWidth() * 0.75)
    frame.level:ClearAllPoints()
    frame.level:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, px + 1)
    frame.health.text:ClearAllPoints()
    frame.health.text:SetPoint("CENTER", frame.health, "CENTER", 0, 0)
    if frame.cfg.healthHidden then
        frame.health:Hide()
        for _, edge in pairs(frame.border) do edge:Hide() end
    else
        frame.health:Show()
        for _, edge in pairs(frame.border) do edge:Show() end
    end
end

function NamePlateFrames:UpdateHealth(frame)
    Elements.UpdateHealth(frame)
    if self.db.threatColor and not IsFriendly(frame.unit) then
        local r, g, b = NamePlateFrames.ThreatColor(frame.unit)
        if r then frame.health:SetStatusBarColor(r, g, b) end
    end
    self:UpdateHighlight(frame)   -- opacité, puis filtres de style
end

function NamePlateFrames:UpdateHighlight(frame)
    local highlighted = self.db.targetHighlight and IsTarget(frame.unit)
    if highlighted then
        local r, g, b = NS.Media:Accent()
        for _, edge in pairs(frame.border) do NS.SetSolidColor(edge, r, g, b, 1) end
        frame:SetAlpha(1)
    else
        local c = NS.db.theme.border
        for _, edge in pairs(frame.border) do NS.SetSolidColor(edge, c.r, c.g, c.b, c.a or 1) end
        local hasTarget = UnitExists("target")
        frame:SetAlpha((self.db.targetHighlight and hasTarget) and 0.7 or 1)
    end
    self:ApplyStyle(frame)
end

function NamePlateFrames:UpdateAll(frame)
    Elements.UpdateName(frame)
    Elements.UpdateLevel(frame)
    Elements.UpdateRaidIcon(frame)
    Elements.StartCast(frame)
    Elements.UpdateAuras(frame)
    self:UpdateHealth(frame)      -- en dernier : couleur, opacité, filtres de style
end

local function HideBlizzard(plate)
    local unitFrame = plate and plate.UnitFrame
    if not unitFrame or not NamePlateFrames.db.hideBlizzard then return end
    if unitFrame.SetAlpha then unitFrame:SetAlpha(0) end
    if unitFrame.UnregisterAllEvents then unitFrame:UnregisterAllEvents() end
    hiddenBlizzard[unitFrame] = true
end

local function RestoreBlizzard()
    local any = false
    for unitFrame in pairs(hiddenBlizzard) do
        if unitFrame.SetAlpha then unitFrame:SetAlpha(1) end
        hiddenBlizzard[unitFrame] = nil
        any = true
    end
    return any
end

function NamePlateFrames:Mount(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return nil end
    local frame = plates[plate]
    if not frame then
        frame = NewFrame()
        plates[plate] = frame
    end
    frame.unit = unit
    frame.plate = plate
    frame.cfg = Config(unit)
    frame.global = self.db
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", plate, "CENTER", 0, 0)
    PlateLayout(frame)
    Elements.BuildAuras(frame)
    Elements.LayoutAuras(frame)
    byUnit[unit] = frame
    HideBlizzard(plate)
    self:UpdateAll(frame)
    frame:Show()
    -- Chevrons : leur barre d'ancrage devient la nôtre (l'événement a pu leur parvenir avant).
    local chevrons = NS.Modules:Get("nameplates")
    if chevrons and chevrons.enabled then chevrons:Update() end
    return frame
end

function NamePlateFrames:Unmount(unit)
    local frame = byUnit[unit]
    if not frame then return end
    frame:Hide()
    frame.castbar:Hide()
    byUnit[unit] = nil
end

function NamePlateFrames:GetFrame(unit) return byUnit[unit] end

--- Cadre AeonUI monté sur une plaque Blizzard, ou nil (chevrons du module « Barres de nom »).
function NamePlateFrames:GetFrameForPlate(plate)
    local frame = plates[plate]
    return frame and frame:IsShown() and frame or nil
end

--------------------------------------------------------------------------------
-- Événements
--------------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
                      "UNIT_AURA", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_FLAGS",
                      "UNIT_CLASSIFICATION_CHANGED" }

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if not active then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        NamePlateFrames:Mount(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        NamePlateFrames:Unmount(unit)
    elseif event == "PLAYER_TARGET_CHANGED" or (event == "QUEST_LOG_UPDATE" and NamePlateFrames:HasQuestRule()) then
        for _, frame in pairs(byUnit) do NamePlateFrames:UpdateHealth(frame) end
    elseif event == "RAID_TARGET_UPDATE" then
        for _, frame in pairs(byUnit) do Elements.UpdateRaidIcon(frame) end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        for _, frame in pairs(byUnit) do NamePlateFrames:UpdateAll(frame) end
    else
        local frame = unit and byUnit[unit]
        if not frame then return end
        -- UNIT_FLAGS (combat) et classification : règles seulement, jamais les indicateurs de
        -- UnitFrameElements (l'icône de combat n'a pas sa place sur une plaque).
        if event == "UNIT_FACTION" then
            -- Allié devenu hostile (duel, JcJ) : réglages de la plaque (nom seul, auras) à refaire.
            NamePlateFrames:Mount(unit)
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
            or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE"
            or event == "UNIT_FLAGS" or event == "UNIT_CLASSIFICATION_CHANGED" then
            NamePlateFrames:UpdateHealth(frame)
        elseif not Elements.OnEvent(frame, event) then
            NamePlateFrames:UpdateAll(frame)
        elseif event ~= "UNIT_AURA" then
            NamePlateFrames:UpdateHealth(frame)   -- incantation : les règles peuvent changer
        end
    end
end)

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local function MountExisting()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then NamePlateFrames:Mount(unit) end
    end
end

function NamePlateFrames:OnEnable()
    active = true
    for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
                             "RAID_TARGET_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                             "QUEST_LOG_UPDATE" }) do
        NS.RegisterEventSafe(events, event)
    end
    for _, event in ipairs(UNIT_EVENTS) do NS.RegisterEventSafe(events, event) end
    for _, event in ipairs(Elements.CAST_EVENTS) do NS.RegisterEventSafe(events, event) end
    MountExisting()
end

function NamePlateFrames:OnDisable()
    active = false
    events:UnregisterAllEvents()
    for unit in pairs(byUnit) do self:Unmount(unit) end
    if RestoreBlizzard() then NS.Print(L.MSG_NPF_DISABLED_RELOAD) end
end

function NamePlateFrames:OnRefresh()
    for unit in pairs(byUnit) do self:Mount(unit) end
end

NS:On("PIXEL_CHANGED", function() if active then NamePlateFrames:OnRefresh() end end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function NamePlateFrames:BuildOptions(o)
    o.layout:Note(L.NOTE_NPF_RELOAD, 20)
    o:Slider("width", L.OPT_UF_WIDTH, 60, 250, 2)
    o:Slider("height", L.OPT_UF_HEIGHT, 4, 30, 1)
    o:Check("showName", L.OPT_UF_UNIT_NAME)
    o:Check("showLevel", L.OPT_UF_UNIT_LEVEL)
    o:Slider("fontDelta", L.OPT_NPF_FONT_DELTA, -4, 4, 1, nil, "%+d")
    o:Dropdown("healthText", L.OPT_UF_HEALTH_TEXT, Elements.TextModeChoices)
    o:EditBox("healthFormat", L.OPT_UF_HEALTH_FORMAT)
    o:Check("showCastbar", L.OPT_UF_UNIT_CASTBAR)
    o:Slider("castbarHeight", L.OPT_UF_CASTBAR_HEIGHT, 6, 24, 1, 36)
    o:Check("showAuras", L.OPT_NPF_AURAS)
    o:Check("showBuffs", L.OPT_NPF_BUFFS, 36)
    o:Slider("auraSize", L.OPT_UF_AURA_SIZE, 12, 32, 1, 36)
    o:Dropdown("auraFilter", L.OPT_AURA_FILTER, NS.AuraFilterChoices, 36)
    o:Check("friendlyHealth", L.OPT_NPF_FRIENDLY_HEALTH)
    o:Check("targetHighlight", L.OPT_NPF_TARGET_HIGHLIGHT)
    o:Check("threatColor", L.OPT_NPF_THREAT)
    o:Check("classColor", L.OPT_UF_CLASS_COLOR)
    o:Check("hideBlizzard", L.OPT_NPF_HIDE_BLIZZARD)
    local tri = { { name = L.STYLE_ANY, value = "any" }, { name = L.STYLE_YES, value = "yes" }, { name = L.STYLE_NO, value = "no" } }
    local reactions = { { name = L.STYLE_ANY, value = "any" }, { name = L.STYLE_HOSTILE, value = "hostile" },
                        { name = L.STYLE_FRIENDLY, value = "friendly" } }
    local classes = { { name = L.STYLE_ANY, value = "any" } }
    for _, class in ipairs({ "normal", "elite", "rare", "boss" }) do
        classes[#classes + 1] = { name = L["STYLE_CLASS_" .. class:upper()], value = class }
    end
    o.layout:Title(L.OPT_NPF_STYLE_FILTERS)
    o.layout:Note(L.NOTE_NPF_STYLE_FILTERS, 20)
    for i = 1, NUM_STYLE_RULES do
        local key = "styleRules." .. RULE_KEYS[i] .. "."
        o:Tab(string.format(L.OPT_NPF_STYLE_RULE, i))
        o:Check(key .. "enabled", L.OPT_NPF_STYLE_ENABLED)
        o:Dropdown(key .. "target", L.OPT_NPF_STYLE_TARGET, tri, 36)
        o:Dropdown(key .. "casting", L.OPT_NPF_STYLE_CASTING, tri, 36)
        o:Dropdown(key .. "combat", L.OPT_NPF_STYLE_COMBAT, tri, 36)
        o:Dropdown(key .. "reaction", L.OPT_NPF_STYLE_REACTION, reactions, 36)
        o:Dropdown(key .. "classification", L.OPT_NPF_STYLE_CLASSIFICATION, classes, 36)
        o:Check(key .. "quest", L.OPT_NPF_STYLE_QUEST, 36)
        o:Slider(key .. "healthBelow", L.OPT_NPF_STYLE_HEALTH_BELOW, 0, 100, 5, 36)
        o:EditBox(key .. "names", L.OPT_NPF_STYLE_NAMES, 1, 36)
        o:Check(key .. "color", L.OPT_NPF_STYLE_COLOR, 36)
        o:Color(key .. "colorValue", L.OPT_NPF_STYLE_COLOR_VALUE, 52)
        o:Check(key .. "glow", L.OPT_NPF_STYLE_GLOW, 36)
        o:Slider(key .. "scale", L.OPT_NPF_STYLE_SCALE, 0.5, 2, 0.05, 36, "%.2f")
        o:Slider(key .. "alpha", L.OPT_NPF_STYLE_ALPHA, 0, 1, 0.05, 36, "%.2f")
        o:Check(key .. "hide", L.OPT_NPF_STYLE_HIDE, 36)
    end
end
