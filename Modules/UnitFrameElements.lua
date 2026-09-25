-- Modules/UnitFrameElements.lua
-- Éléments d'un cadre d'unité AeonUI : santé, puissance, nom, niveau, barre d'incantation,
-- indicateurs, marqueur de raid, points de combo, auras. Partagés par les cadres d'unité
-- (étape 2) et les plaques de nom (étape 3).
--
-- Règle Midnight : aucune valeur d'unité n'est comparée ni calculée ici. Santé, puissance et
-- durées vont telles quelles aux widgets (SetMinMaxValues, SetValue, SetTimerDuration,
-- AbbreviateNumbers), qui acceptent les valeurs secrètes. Quand une comparaison est inévitable
-- (classe, réaction, niveau, combat), Known() rend nil pour une valeur secrète et l'élément
-- prend un repli neutre.
--
-- frame.unit   : jeton d'unité ("player", "target", "nameplate3"…)
-- frame.cfg    : réglages de l'unité (width, height, powerHeight, castbar, castbarHeight,
--                auras, auraSize, power, name, level, combo)
-- frame.global : réglages communs (classColor, healthText, powerText : préréglages de format)
-- frame.cfg.healthFormat, powerFormat : format personnalisé du cadre (jetons, prime sur le préréglage)
local _, NS = ...
local Media = NS.Media
local L = NS.L

local Elements = {}
NS.UnitFrameElements = Elements

local isSecret = NS.IsSecret
local function Known(value)
    if isSecret(value) or value == nil then return nil end
    return value
end

local STATE_ICON = "Interface\\CharacterFrame\\UI-StateIcon"
local LEADER_ICON = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local GREY = { 0.6, 0.6, 0.6 }
local MANA = { r = 0, g = 0.44, b = 0.87 }
local MAX_AURAS = 16
local MAX_AURA_INDEX = 40      -- auras lues au plus par sorte, filtre compris
local AURA_KINDS_DEBUFFS = { "HARMFUL" }
local AURA_KINDS_ALL = { "HARMFUL", "HELPFUL" }

local function S(n) return NS.Pixel:Scale(n) end

--------------------------------------------------------------------------------
-- Fonctions pures (testées hors jeu)
--------------------------------------------------------------------------------

--- Couleur de la barre de vie : classe (joueur connu), sinon réaction, sinon gris.
local function SurelyPlayer(unit)
    return unit == "player" or unit:find("^party%d") ~= nil or unit:find("^raid%d") ~= nil
end

function Elements.HealthColor(unit, classColor)
    if classColor and not NS.IsSecretUnit(unit) and (SurelyPlayer(unit) or Known(UnitIsPlayer(unit))) then
        local _, classFile = UnitClass(unit)
        classFile = Known(classFile)
        if classFile then return NS.ClassColor(classFile) end
    end
    local reaction = _G.UnitReaction and Known(UnitReaction(unit, "player")) or nil
    if reaction then
        if reaction >= 5 then return 0.2, 0.75, 0.2 end
        if reaction == 4 then return 0.9, 0.8, 0.2 end
        return 0.85, 0.2, 0.2
    end
    return GREY[1], GREY[2], GREY[3]
end

--- Couleur de la barre de puissance d'après le type courant (table Blizzard PowerBarColor).
function Elements.PowerColor(unit)
    local colors = _G.PowerBarColor
    local c
    if _G.UnitPowerType then
        local id, token = UnitPowerType(unit)
        token, id = Known(token), Known(id)
        if colors then c = (token and colors[token]) or (id and colors[id]) end
    end
    c = c or MANA
    return c.r, c.g, c.b
end

--- Texte du niveau : "" si secret, "??" pour un niveau inconnu (-1).
function Elements.LevelText(unit)
    local level = _G.UnitLevel and Known(UnitLevel(unit)) or nil
    if not level then return "" end
    if level < 0 then return "??" end
    return tostring(level)
end

local function Short(n)
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e4 then return string.format("%.0fk", n / 1e3) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return tostring(math.floor(n + 0.5))
end

--- Texte d'une valeur possiblement secrète : AbbreviateNumbers (secret-safe) si présent,
-- sinon la valeur connue formatée, sinon "".
local function ValueText(value)
    if _G.AbbreviateNumbers then
        local ok, text = pcall(AbbreviateNumbers, value)
        if ok and (isSecret(text) or text ~= nil) then return text end
    end
    value = Known(value)
    return value and Short(value) or ""
end

--------------------------------------------------------------------------------
-- Formats de texte
--------------------------------------------------------------------------------
-- Un format mêle du texte libre et des jetons : « [cur] / [max] », « [perc] », « [status] ».
-- Il est compilé une fois en motif %s ; les valeurs, peut-être secrètes, vont à SetFormattedText,
-- qui les accepte : le Lua ne les compare ni ne les concatène jamais.

Elements.TEXT_PRESETS = {
    current = "[cur]", percent = "[perc]", none = "", curperc = "[cur] | [perc]",
    curmax = "[cur] / [max]", missing = "[missing]",
    both = "[cur] | [perc]",   -- ancien mode de l'étape 2, gardé pour les profils existants
}
Elements.TEXT_PRESET_ORDER = { "current", "percent", "curperc", "curmax", "missing", "none" }

local API = {
    health = { cur = "UnitHealth", max = "UnitHealthMax", percent = "UnitHealthPercent", missing = "UnitHealthMissing" },
    power = { cur = "UnitPower", max = "UnitPowerMax", percent = "UnitPowerPercent" },
}

local function Call(name, ...)
    local fn = _G[name]
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

--- Pourcentage : moteur à l'échelle 0-100 (valeur secrète acceptée par string.format), sinon
-- calcul sur valeurs lisibles, sinon la valeur courante (comme l'ancien mode « pourcentage »).
-- Sans ScaleTo100, UnitHealthPercent rend une fraction 0-1 : pas utilisée, 1 serait ambigu.
local function PercentText(unit, kind)
    local api = API[kind]
    local scale = _G.CurveConstants and CurveConstants.ScaleTo100
    if scale then
        local percent
        if kind == "health" then percent = Call(api.percent, unit, true, scale)
        else percent = Call(api.percent, unit, nil, true, scale) end
        if isSecret(percent) or percent ~= nil then return string.format("%.0f%%", percent) end
    end
    local cur, max = Known(Call(api.cur, unit)), Known(Call(api.max, unit))
    if cur and max and max > 0 then return string.format("%d%%", math.floor(cur / max * 100 + 0.5)) end
    return ValueText(Call(api.cur, unit))
end

--- Manque : API moteur (secret, zéro tronqué) si présente, sinon calcul lisible ; "" à plein.
local function MissingText(unit, kind)
    local api = API[kind]
    local missing = api.missing and Call(api.missing, unit)
    if isSecret(missing) or missing ~= nil then
        local truncate = _G.C_StringUtil and C_StringUtil.TruncateWhenZero
        if truncate then return truncate(missing) end
        missing = Known(missing)
        return missing and missing > 0 and ValueText(missing) or ""
    end
    local cur, max = Known(Call(api.cur, unit)), Known(Call(api.max, unit))
    if not (cur and max) or max - cur <= 0 then return "" end
    return ValueText(max - cur)
end

local function StatusText(unit)
    local connected = _G.UnitIsConnected and Known(UnitIsConnected(unit))
    if connected == false then return L.TEXT_STATUS_OFFLINE end
    local ghost = _G.UnitIsGhost and Known(UnitIsGhost(unit))
    if ghost then return L.TEXT_STATUS_GHOST end
    local dead = Known(UnitIsDead(unit))
    if dead then return L.TEXT_STATUS_DEAD end
    return ""
end

Elements.TOKENS = {
    cur = function(unit, kind) return ValueText(Call(API[kind].cur, unit)) end,
    max = function(unit, kind) return ValueText(Call(API[kind].max, unit)) end,
    perc = PercentText,
    missing = MissingText,
    status = StatusText,
}

local compiled, compiledCount = {}, 0
--- Format -> { pattern, tokens }. Un jeton inconnu reste écrit tel quel.
function Elements.CompileFormat(format)
    local entry = compiled[format]
    if entry then return entry end
    if compiledCount >= 64 then compiled, compiledCount = {}, 0 end   -- saisie en cours dans les options
    entry = { tokens = {} }
    entry.pattern = (format:gsub("%%", "%%%%"):gsub("%[(%a+)%]", function(name)
        if Elements.TOKENS[name] then
            entry.tokens[#entry.tokens + 1] = name
            return "%s"
        end
    end))
    compiled[format], compiledCount = entry, compiledCount + 1
    return entry
end

--- Choix des préréglages pour un o:Dropdown.
function Elements.TextModeChoices()
    local list = {}
    for _, mode in ipairs(Elements.TEXT_PRESET_ORDER) do
        list[#list + 1] = { name = L["TEXT_MODE_" .. mode:upper()], value = mode }
    end
    return list
end

--- Format effectif : personnalisé s'il est rempli, sinon le préréglage du mode.
function Elements.TextFormat(custom, mode)
    if type(custom) == "string" and custom ~= "" then return custom end
    return Elements.TEXT_PRESETS[mode or "none"] or ""
end

--- Écrit un format sur un FontString pour l'unité (kind : "health" ou "power").
function Elements.SetUnitText(fontString, unit, kind, format)
    if not format or format == "" then fontString:SetText("") return end
    local entry = Elements.CompileFormat(format)
    local count = #entry.tokens
    if count == 0 then fontString:SetText(format) return end
    local values = {}
    for i, name in ipairs(entry.tokens) do
        local value = Elements.TOKENS[name](unit, kind)   -- chaîne peut-être secrète : jamais testée
        if not isSecret(value) and value == nil then value = "" end
        values[i] = value
    end
    fontString:SetFormattedText(entry.pattern, unpack(values, 1, count))
end

--- Texte rendu d'un mode ou format (tests, aperçus).
function Elements.RenderText(unit, kind, format)
    local probe = { SetText = function(self, t) self.text = t end,
                    SetFormattedText = function(self, fmt, ...) self.text = string.format(fmt, ...) end }
    Elements.SetUnitText(probe, unit, kind, format)
    return probe.text
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function Icon(parent, texture, layer)
    local tex = parent:CreateTexture(nil, layer or "OVERLAY")
    tex:SetTexture(texture)
    tex:Hide()
    return tex
end

--- Crée toutes les régions une fois. Les tailles viennent de Layout.
function Elements.Build(frame)
    if frame.health then return end
    frame.health = Media:CreateStatusBar(frame)
    frame.health.text = Media:CreateText(frame.health, "OVERLAY", -1)
    frame.name = Media:CreateText(frame.health, "OVERLAY", 0)
    frame.name:SetJustifyH("LEFT")
    if frame.name.SetWordWrap then frame.name:SetWordWrap(false) end
    frame.level = Media:CreateText(frame.health, "OVERLAY", -2)

    frame.power = Media:CreateStatusBar(frame)
    frame.power.text = Media:CreateText(frame.power, "OVERLAY", -3)

    -- Prédiction de soins et absorptions : barres filles de la vie, accrochées au bout de sa
    -- texture (le moteur place, même avec des valeurs secrètes), rognées par un cadre dédié :
    -- la barre de vie elle-même ne rogne pas, ses icônes débordent du cadre.
    local health = frame.health
    local clip = CreateFrame("Frame", nil, health)
    clip:SetAllPoints(health)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    frame.healPrediction = CreateFrame("StatusBar", nil, clip)
    frame.healPrediction:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.healPrediction:SetStatusBarColor(0.2, 0.9, 0.3, 0.45)
    frame.absorb = CreateFrame("StatusBar", nil, clip)
    frame.absorb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.absorb:SetStatusBarColor(1, 1, 1, 0.35)
    frame.healPrediction:Hide()
    frame.absorb:Hide()
    -- Textes et icônes au-dessus des barres de prédiction.
    frame.overlay = CreateFrame("Frame", nil, health)
    frame.overlay:SetAllPoints(health)
    frame.overlay:SetFrameLevel(health:GetFrameLevel() + 3)
    for _, region in ipairs({ health.text, frame.name, frame.level }) do region:SetParent(frame.overlay) end

    -- Portrait 2D, hors du cadre (cfg.portrait, côté cfg.portraitSide).
    frame.portrait = CreateFrame("Frame", nil, frame)
    Media:CreateBackdrop(frame.portrait)
    frame.portrait.texture = frame.portrait:CreateTexture(nil, "ARTWORK")
    frame.portrait.texture:SetAllPoints(frame.portrait)
    frame.portrait.texture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    frame.portrait:Hide()

    frame.combat = Icon(frame.overlay, STATE_ICON)
    frame.combat:SetTexCoord(0.5, 1, 0, 0.5)
    frame.resting = Icon(frame.overlay, STATE_ICON)
    frame.resting:SetTexCoord(0, 0.5, 0, 0.5)
    frame.leader = Icon(frame.overlay, LEADER_ICON)
    frame.raidIcon = Icon(frame.overlay, RAID_ICONS)

    -- Points de combo : une seule barre de 0 à max, graduée. Aucun « si cur >= i » en Lua :
    -- la valeur peut rester secrète.
    frame.combo = Media:CreateStatusBar(frame)
    Media:CreateBackdrop(frame.combo)
    frame.combo.ticks = {}
    frame.combo:Hide()

    local castbar = Media:CreateStatusBar(frame)
    Media:CreateBackdrop(castbar)
    -- L'icône a son propre cadre : sa bordure 1 px suit le thème et l'échelle toute seule.
    castbar.iconFrame = CreateFrame("Frame", nil, castbar)
    castbar.icon = castbar.iconFrame:CreateTexture(nil, "ARTWORK")
    castbar.icon:SetAllPoints(castbar.iconFrame)
    castbar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Media:CreateBackdrop(castbar.iconFrame)
    castbar.text = Media:CreateText(castbar, "OVERLAY", -1)
    castbar.text:SetJustifyH("LEFT")
    castbar.holdTime = 0
    castbar:SetScript("OnUpdate", function(bar, elapsed) Elements.CastOnUpdate(bar, elapsed) end)
    castbar:Hide()
    frame.castbar = castbar
end

--------------------------------------------------------------------------------
-- Disposition
--------------------------------------------------------------------------------

local function Place(region, point, relTo, relPoint, x, y)
    region:ClearAllPoints()
    region:SetPoint(point, relTo, relPoint, x, y)
end

--- Pose tailles et positions d'après frame.cfg. Le cadre lui-même est dimensionné ici.
function Elements.Layout(frame)
    local cfg = frame.cfg
    local px = S(1)
    local width, height = S(cfg.width or 200), S(cfg.height or 40)
    frame:SetSize(width, height)

    local powerHeight = (cfg.power and (cfg.powerHeight or 0) > 0) and S(cfg.powerHeight) or 0
    Place(frame.health, "TOPLEFT", frame, "TOPLEFT", px, -px)
    frame.health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, powerHeight > 0 and (powerHeight + 2 * px) or px)
    if powerHeight > 0 then
        Place(frame.power, "BOTTOMLEFT", frame, "BOTTOMLEFT", px, px)
        frame.power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
        frame.power:SetHeight(powerHeight)
        frame.power:Show()
    else
        frame.power:Hide()
    end

    local inset = S(4)
    Place(frame.name, "LEFT", frame.health, "LEFT", inset, 0)
    frame.name:SetWidth(width * 0.6)
    frame.name:SetShown(cfg.name ~= false)
    Place(frame.level, "TOPRIGHT", frame.health, "TOPRIGHT", -inset, -px)
    Place(frame.health.text, "BOTTOMRIGHT", frame.health, "BOTTOMRIGHT", -inset, px)
    Place(frame.power.text, "RIGHT", frame.power, "RIGHT", -inset, 0)

    local tip = frame.health:GetStatusBarTexture()
    for _, bar in ipairs({ frame.healPrediction, frame.absorb }) do
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", tip, "TOPRIGHT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", tip, "BOTTOMRIGHT", 0, 0)
        bar:SetWidth(width - 2 * px)
    end
    -- L'absorption suit la prédiction : les deux s'additionnent au bout de la vie.
    frame.absorb:ClearAllPoints()
    frame.absorb:SetPoint("TOPLEFT", frame.healPrediction:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    frame.absorb:SetPoint("BOTTOMLEFT", frame.healPrediction:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    frame.absorb:SetWidth(width - 2 * px)

    if cfg.portrait then
        frame.portrait:SetSize(height, height)
        if cfg.portraitSide == "RIGHT" then
            Place(frame.portrait, "LEFT", frame, "RIGHT", S(2), 0)
        else
            Place(frame.portrait, "RIGHT", frame, "LEFT", -S(2), 0)
        end
        frame.portrait:Show()
    else
        frame.portrait:Hide()
    end

    local icon = S(16)
    frame.combat:SetSize(icon, icon)
    Place(frame.combat, "CENTER", frame, "TOPLEFT", 0, 0)
    frame.resting:SetSize(icon, icon)
    Place(frame.resting, "CENTER", frame, "TOPLEFT", 0, 0)
    frame.leader:SetSize(S(14), S(14))
    Place(frame.leader, "CENTER", frame, "TOPLEFT", S(18), 0)
    frame.raidIcon:SetSize(S(18), S(18))
    Place(frame.raidIcon, "CENTER", frame, "TOP", 0, 0)

    local gap = S(4)
    local below = frame
    if cfg.combo then
        local comboHeight = S((cfg.powerHeight or 0) > 0 and cfg.powerHeight or 6)
        Place(frame.combo, "TOPLEFT", frame, "BOTTOMLEFT", 0, -gap)
        frame.combo:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -gap)
        frame.combo:SetHeight(comboHeight)
        frame.combo.width = width
        below = frame.combo
    end
    frame.comboAllowed = cfg.combo and true or false

    local castbar = frame.castbar
    local castHeight = S(cfg.castbarHeight or 18)
    castbar.enabled = cfg.castbar and true or false
    castbar.detached = cfg.castbarDetached and true or false
    if castbar.detached then
        -- Sur son propre mover : le module le pose (Movers:Load), ici seulement la taille.
        castbar:ClearAllPoints()
        castbar:SetSize(S(cfg.castbarWidth or width), castHeight)
    else
        Place(castbar, "TOPLEFT", below, "BOTTOMLEFT", castHeight + gap, -gap)
        castbar:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -gap)
        castbar:SetHeight(castHeight)
    end
    castbar.iconFrame:SetSize(castHeight, castHeight)
    Place(castbar.iconFrame, "RIGHT", castbar, "LEFT", -gap, 0)
    Place(castbar.text, "LEFT", castbar, "LEFT", inset, 0)
    castbar.text:SetWidth((castbar.detached and S(cfg.castbarWidth or width) or width) - castHeight - gap - 2 * inset)
    if not castbar.enabled then castbar:Hide() end
    if castbar.enabled and not castbar.detached then below = castbar end

    frame.aurasAnchor = below
    Elements.LayoutAuras(frame)
end

--------------------------------------------------------------------------------
-- Mises à jour
--------------------------------------------------------------------------------

function Elements.UpdateHealth(frame)
    local unit = frame.unit
    local bar = frame.health
    bar:SetMinMaxValues(0, UnitHealthMax(unit))
    bar:SetValue(UnitHealth(unit))
    local global = frame.global
    local applied, r, g, b = false
    if global and global.healthGradient then applied, r, g, b = NS.HealthGradient(unit) end
    if applied then bar:SetStatusBarColor(r, g, b)   -- r, g, b peut-être secrets : jamais testés
    else bar:SetStatusBarColor(Elements.HealthColor(unit, global and global.classColor)) end
    Elements.SetUnitText(bar.text, unit, "health",
        Elements.TextFormat(frame.cfg and frame.cfg.healthFormat, global and global.healthText or "current"))
    Elements.UpdateHealPrediction(frame)
end

--- Montant d'une API de prédiction : secret passé tel quel, absent = 0.
local function Amount(name, unit)
    local value = Call(name, unit)
    if isSecret(value) then return value end
    return value or 0
end

local function UpdatePredictionBar(bar, api, on, unit)
    if on and _G[api] then
        bar:SetMinMaxValues(0, UnitHealthMax(unit))
        bar:SetValue(Amount(api, unit))
        bar:Show()
    else
        bar:Hide()
    end
end

--- Soins entrants et absorptions (global.healPrediction), valeurs peut-être secrètes : les barres
-- les reçoivent sans comparaison. Sans l'API du client, barre cachée.
function Elements.UpdateHealPrediction(frame)
    if not frame.healPrediction then return end
    local on = frame.global and frame.global.healPrediction
    UpdatePredictionBar(frame.healPrediction, "UnitGetIncomingHeals", on, frame.unit)
    UpdatePredictionBar(frame.absorb, "UnitGetTotalAbsorbs", on, frame.unit)
end

--- Portrait 2D de l'unité (cfg.portrait).
function Elements.UpdatePortrait(frame)
    if not (frame.portrait and frame.cfg and frame.cfg.portrait) or not _G.SetPortraitTexture then return end
    pcall(SetPortraitTexture, frame.portrait.texture, frame.unit)
end

function Elements.UpdatePower(frame)
    local unit = frame.unit
    local bar = frame.power
    if not (frame.cfg.power and (frame.cfg.powerHeight or 0) > 0) then bar:Hide() return end
    local max = UnitPowerMax(unit)
    local knownMax = Known(max)
    if knownMax and knownMax <= 0 then bar:Hide() return end
    bar:SetMinMaxValues(0, max)
    bar:SetValue(UnitPower(unit))
    bar:SetStatusBarColor(Elements.PowerColor(unit))
    Elements.SetUnitText(bar.text, unit, "power",
        Elements.TextFormat(frame.cfg and frame.cfg.powerFormat, frame.global and frame.global.powerText))
    bar:Show()
end

--- Les `count` premiers caractères UTF-8 (jamais coupés au milieu d'un caractère).
function Elements.TruncateName(name, count)
    if not count or count <= 0 or not name then return name end
    local out, n = {}, 0
    for char in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
        if n > count then break end
        out[n] = char
    end
    return table.concat(out)
end

function Elements.UpdateName(frame)
    local unit = frame.unit
    if frame.cfg.name == false then frame.name:Hide() return end
    -- Nom secret (identité masquée) : aucun test booléen dessus, il part tel quel au widget.
    local name = UnitName(unit)
    if not isSecret(name) and name == nil then name = "" end
    if frame.cfg.nameLength and not NS.IsSecret(name) then name = Elements.TruncateName(name, frame.cfg.nameLength) end
    frame.name:SetText(name)
    if frame.global and frame.global.classColor then
        frame.name:SetTextColor(Elements.HealthColor(unit, true))
    else
        frame.name:SetTextColor(1, 1, 1)
    end
    frame.name:Show()
end

function Elements.UpdateLevel(frame)
    local unit = frame.unit
    local text = frame.level
    if frame.cfg.level == false then text:Hide() return end
    local value = Elements.LevelText(unit)
    if unit == "player" and _G.GetMaxPlayerLevel then
        local level, max = Known(UnitLevel(unit)), Known(GetMaxPlayerLevel())
        if level and max and level >= max then value = "" end
    end
    text:SetText(value)
    local numeric = tonumber(value)
    if numeric and _G.GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(numeric)
        if c then text:SetTextColor(c.r, c.g, c.b) end
    else
        text:SetTextColor(1, 0.82, 0)
    end
    text:SetShown(value ~= "")
end

function Elements.UpdateIndicators(frame)
    local unit = frame.unit
    local inCombat = Known(UnitAffectingCombat(unit))
    frame.combat:SetShown(inCombat and true or false)
    if unit == "player" then
        local resting = not inCombat and IsResting() and true or false
        frame.resting:SetShown(resting)
        local leader = _G.UnitIsGroupLeader and Known(UnitIsGroupLeader(unit)) or nil
        frame.leader:SetShown(leader and true or false)
    else
        frame.resting:Hide()
        frame.leader:Hide()
    end
end

function Elements.UpdateRaidIcon(frame)
    local index = _G.GetRaidTargetIndex and Known(GetRaidTargetIndex(frame.unit)) or nil
    if index and _G.SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(frame.raidIcon, index)
        frame.raidIcon:Show()
    else
        frame.raidIcon:Hide()
    end
end

local function ComboPowerType()
    return Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
end

function Elements.UpdateCombo(frame)
    local bar = frame.combo
    if not frame.comboAllowed or frame.unit ~= "player" then bar:Hide() return end
    local max = UnitPowerMax("player", ComboPowerType())
    local knownMax = Known(max)
    if not knownMax or knownMax <= 0 then bar:Hide() return end
    bar:SetMinMaxValues(0, max)
    bar:SetValue(UnitPower("player", ComboPowerType()))
    bar:SetStatusBarColor(1, 0.82, 0)
    -- Graduations : une par point, épaisseur 1 px (barre verticale : graduations horizontales).
    local px = S(1)
    local length = bar.vertical and (bar:GetHeight() or 0) or (bar.width or bar:GetWidth() or 0)
    for i = 1, knownMax - 1 do
        local tick = bar.ticks[i]
        if not tick then
            tick = bar:CreateTexture(nil, "OVERLAY")
            NS.SetSolidColor(tick, 0, 0, 0, 1)
            bar.ticks[i] = tick
        end
        local offset = length * i / knownMax
        tick:ClearAllPoints()
        if bar.vertical then
            tick:SetHeight(px)
            tick:SetPoint("LEFT", bar, "BOTTOMLEFT", 0, offset)
            tick:SetPoint("RIGHT", bar, "BOTTOMRIGHT", 0, offset)
        else
            tick:SetWidth(px)
            tick:SetPoint("TOP", bar, "TOPLEFT", offset, 0)
            tick:SetPoint("BOTTOM", bar, "BOTTOMLEFT", offset, 0)
        end
        tick:Show()
    end
    for i = knownMax, #bar.ticks do bar.ticks[i]:Hide() end
    bar:Show()
end

--------------------------------------------------------------------------------
-- Barre d'incantation
--------------------------------------------------------------------------------

local function Interpolation()
    return Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or nil
end

local function Direction(channeling)
    local dirs = Enum and Enum.StatusBarTimerDirection
    if not dirs then return nil end
    return channeling and dirs.RemainingTime or dirs.ElapsedTime
end

--- (Re)dérive l'incantation en cours et montre la barre, ou la cache.
function Elements.StartCast(frame)
    local bar = frame.castbar
    if not bar.enabled then bar:Hide() return end
    local unit = frame.unit
    local name, text, texture, startTime, endTime, _, _, notInterruptible = UnitCastingInfo(unit)
    -- Incantation secrète possible : tester la présence sans test booléen sur la valeur.
    local channeling = false
    if not isSecret(name) and name == nil and _G.UnitChannelInfo then
        name, text, texture, startTime, endTime, _, notInterruptible = UnitChannelInfo(unit)
        channeling = true
    end
    if not isSecret(name) and name == nil then bar:Hide() return end

    bar.holdTime = 0
    bar.manual = nil
    if isSecret(text) or text ~= nil then bar.text:SetText(text) else bar.text:SetText(name) end
    if isSecret(texture) or texture ~= nil then bar.icon:SetTexture(texture) else bar.icon:SetTexture(QUESTION_ICON) end
    if Known(notInterruptible) then
        bar:SetStatusBarColor(0.6, 0.6, 0.6)
    else
        bar:SetStatusBarColor(Media:Accent())
    end

    local durationApi = channeling and _G.UnitChannelDuration or _G.UnitCastingDuration
    if bar.SetTimerDuration and durationApi then
        -- Le moteur anime la barre : aucune lecture d'horloge, la fin peut rester secrète.
        bar:SetTimerDuration(durationApi(unit), Interpolation(), Direction(channeling))
    else
        local s, e = Known(startTime), Known(endTime)
        if s and e and e > s then
            bar.manual = { start = s / 1000, finish = e / 1000, channeling = channeling }
            bar:SetMinMaxValues(0, (e - s) / 1000)
            bar:SetValue(channeling and (e - s) / 1000 or 0)
        else
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(1)
        end
    end
    bar:Show()
end

function Elements.StopCast(frame, interrupted)
    local bar = frame.castbar
    if not bar:IsShown() then return end
    if interrupted then
        bar.manual = nil
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar:SetStatusBarColor(0.9, 0.2, 0.2)
        bar.holdTime = 0.5
    else
        bar:Hide()
    end
end

function Elements.CastOnUpdate(bar, elapsed)
    if bar.holdTime > 0 then
        bar.holdTime = bar.holdTime - elapsed
        if bar.holdTime <= 0 then bar:Hide() end
        return
    end
    local manual = bar.manual
    if not manual then return end
    local now = GetTime()
    if now >= manual.finish then bar:Hide() return end
    if manual.channeling then
        bar:SetValue(manual.finish - now)
    else
        bar:SetValue(now - manual.start)
    end
end

local CAST_START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true,
                     UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true,
                     UNIT_SPELLCAST_INTERRUPTIBLE = true, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true }
local CAST_STOP = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_FAILED = true }

Elements.CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

--- Route un événement d'incantation. Retourne true s'il en était un.
function Elements.HandleCast(frame, event)
    if CAST_START[event] then Elements.StartCast(frame) return true end
    if CAST_STOP[event] then
        -- Un STOP peut arriver alors qu'une canalisation continue : on redérive plutôt que de cacher.
        Elements.StartCast(frame)
        return true
    end
    if event == "UNIT_SPELLCAST_INTERRUPTED" then Elements.StopCast(frame, true) return true end
    return false
end

--------------------------------------------------------------------------------
-- Auras
--------------------------------------------------------------------------------

local function SetupNative(container, frame)
    local cfg = frame.cfg
    local size = S(cfg.auraSize or 22)
    local width = S(cfg.width or 200)
    container:SetUnit(frame.unit)
    if container.SetFlowLayoutAnchorPoint then container:SetFlowLayoutAnchorPoint("TOPLEFT") end
    if container.SetFlowLayoutGrowthDirection and _G.AnchorUtil and AnchorUtil.FlowDirection then
        container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    end
    if container.SetFlowLayoutMaximumLineSize then container:SetFlowLayoutMaximumLineSize(width) end
    local layout = { elementWidth = size, elementHeight = size, elementSpacing = S(2), lineSpacing = S(2) }
    local function init(button) button:SetSize(size, size) end
    local harmful = cfg.auraFilter == "mine" and "HARMFUL|PLAYER" or "HARMFUL"
    container:AddAuraGroup("debuffs", harmful, { maxFrameCount = MAX_AURAS, layout = layout, initializeFrame = init })
    container:AddAuraGroup("buffs", "HELPFUL", { maxFrameCount = MAX_AURAS, layout = layout, initializeFrame = init })
    container.native = true
end

local function ManualContainer(frame)
    local container = CreateFrame("Frame", nil, frame)
    container.buttons = {}
    container.native = false
    return container
end

local function ManualButton(container, index)
    local button = container.buttons[index]
    if button then return button end
    button = CreateFrame("Frame", nil, container)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.border = Media:CreateBorder(button)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button)
    NS.RegisterCooldown(button.cooldown)
    button.count = Media:CreateText(button, "OVERLAY", -2, "OUTLINE")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    container.buttons[index] = button
    return button
end

--- Conteneur voulu : moteur pour « tout » et « les miens » (filtre HARMFUL|PLAYER natif),
-- maison pour les autres filtres, qui lisent chaque aura.
-- ponytail: les listes blanche et noire du profil ne s'appliquent qu'au conteneur maison.
local function AuraKind(cfg)
    local filter = cfg.auraFilter or "all"
    if cfg.aurasManual or not (filter == "all" or filter == "mine") then return "manual" end
    return "native:" .. filter
end

--- Crée le conteneur d'auras si l'unité en veut. Voie moteur d'abord, repli maison.
-- Un conteneur par sorte, gardé sur le cadre (un cadre ne se détruit pas) : changer de filtre
-- cache l'ancien, en coupe l'unité s'il est moteur, et réutilise celui de la nouvelle sorte.
function Elements.BuildAuras(frame)
    if not frame.cfg.auras then return end
    local kind = AuraKind(frame.cfg)
    if frame.auras then
        if frame.auras.kind == kind then return end
        frame.auras:Hide()
        if frame.auras.native then pcall(frame.auras.SetUnit, frame.auras, nil) end
    end
    frame.auraContainers = frame.auraContainers or {}
    local container = frame.auraContainers[kind]
    if container then
        if container.native then pcall(container.SetUnit, container, frame.unit) end
        frame.auras = container
        return
    end
    -- cfg.aurasManual : cadre dont l'unité change (plaques) ; le conteneur moteur veut un SetUnit fixe.
    if kind ~= "manual" and NS.AuraContainerAvailable() then
        local created, native = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
        if created then
            local ok, err = pcall(SetupNative, native, frame)
            if ok then container = native
            else
                native:Hide()   -- conteneur partiel : caché, jamais réutilisé
                if NS.Print then NS.Print("AuraContainer : " .. tostring(err)) end
            end
        end
    end
    container = container or ManualContainer(frame)
    container.kind = kind
    frame.auraContainers[kind] = container
    frame.auras = container
end

function Elements.LayoutAuras(frame)
    local container = frame.auras
    if not container then return end
    local cfg = frame.cfg
    local width = S(cfg.width or 200)
    local gap = S(4)
    container:ClearAllPoints()
    if cfg.aurasAbove then
        -- Plaque : nom et niveau au-dessus de la barre, les auras passent au-dessus d'eux.
        container:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, gap + (cfg.plate and S(14) or 0))
    else
        container:SetPoint("TOPLEFT", frame.aurasAnchor or frame, "BOTTOMLEFT", 0, -gap)
    end
    if container.native then
        pcall(function()
            if container.SetFlowLayoutAnchorPoint then container:SetFlowLayoutAnchorPoint(cfg.aurasAbove and "BOTTOMLEFT" or "TOPLEFT") end
            if container.SetFlowLayoutGrowthDirection and _G.AnchorUtil and AnchorUtil.FlowDirection then
                local flow = AnchorUtil.FlowDirection
                container:SetFlowLayoutGrowthDirection(flow.Right, cfg.aurasAbove and flow.Up or flow.Down)
            end
            if container.SetFlowLayoutMaximumLineSize then container:SetFlowLayoutMaximumLineSize(width) end
            local size = S(cfg.auraSize or 22)
            local layout = { elementWidth = size, elementHeight = size, elementSpacing = S(2), lineSpacing = S(2) }
            if container.SetAuraGroupLayout then
                container:SetAuraGroupLayout("debuffs", layout)
                container:SetAuraGroupLayout("buffs", layout)
            end
        end)
        return
    end
    local size = S(cfg.auraSize or 22)
    local spacing = S(2)
    local perRow = math.max(1, math.floor((width + spacing) / (size + spacing)))
    container.step, container.perRow, container.above = size + spacing, perRow, cfg.aurasAbove
    container:SetSize(width, (size + spacing) * math.ceil(MAX_AURAS / perRow))
    for i = 1, MAX_AURAS do ManualButton(container, i):SetSize(size, size) end
end

--- Pose le bouton en (colonne, ligne) : ligne 0 contre le cadre, les suivantes s'en éloignent.
local function PlaceManualButton(container, button, col, row)
    local step = container.step
    button:ClearAllPoints()
    if container.above then
        button:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", col * step, row * step)
    else
        button:SetPoint("TOPLEFT", container, "TOPLEFT", col * step, -row * step)
    end
end

function Elements.UpdateAuras(frame)
    local container = frame.auras
    if not container then return end
    if container.native then
        if not frame.cfg.auras then container:Hide() return end
        container:Show()
        pcall(function() if container.UpdateAllAuras then container:UpdateAllAuras() end end)
        return
    end
    if not frame.cfg.auras then container:Hide() return end
    container:Show()
    local unit = frame.unit
    local perRow = container.perRow or MAX_AURAS
    local shown, slot = 0, 0   -- slot : position dans la grille (les buffs commencent une ligne neuve)
    -- Débuffs (filtre du cadre), puis buffs (listes du profil seulement) si cfg.buffs.
    for _, kind in ipairs(frame.cfg.buffs and AURA_KINDS_ALL or AURA_KINDS_DEBUFFS) do
        if kind == "HELPFUL" and slot % perRow ~= 0 then slot = slot + perRow - slot % perRow end
        local filter = kind == "HARMFUL" and frame.cfg.auraFilter or "all"
        for index = 1, MAX_AURA_INDEX do
            if shown >= MAX_AURAS then break end
            local icon, duration, expiration, count, dispel, isBoss, spellId, isMine = NS.GetAura(unit, index, kind)
            if not isSecret(icon) and icon == nil then break end
            if NS.AuraPasses(filter, spellId, dispel, isBoss, isMine) then
                shown, slot = shown + 1, slot + 1
                local button = ManualButton(container, shown)
                PlaceManualButton(container, button, (slot - 1) % perRow, math.floor((slot - 1) / perRow))
                button.icon:SetTexture(icon)
                local d, e = Known(duration), Known(expiration)
                if d and e and d > 0 then button.cooldown:SetCooldown(e - d, d) else button.cooldown:Clear() end
                local n = Known(count)
                button.count:SetText(n and n > 1 and tostring(n) or "")
                local color = kind == "HARMFUL" and not isSecret(dispel) and dispel and _G.DebuffTypeColor
                    and DebuffTypeColor[dispel] or nil
                if color then
                    for _, edge in pairs(button.border) do NS.SetSolidColor(edge, color.r, color.g, color.b, 1) end
                else
                    local c = NS.db.theme.border
                    for _, edge in pairs(button.border) do NS.SetSolidColor(edge, c.r, c.g, c.b, c.a or 1) end
                end
                button:Show()
            end
        end
    end
    for i = shown + 1, #container.buttons do container.buttons[i]:Hide() end
end

--------------------------------------------------------------------------------
-- Tout
--------------------------------------------------------------------------------

--- Rafraîchit chaque élément (changement d'unité, entrée en jeu, réglage).
function Elements.UpdateAll(frame)
    Elements.UpdateHealth(frame)
    Elements.UpdatePower(frame)
    Elements.UpdateName(frame)
    Elements.UpdateLevel(frame)
    Elements.UpdateIndicators(frame)
    Elements.UpdateRaidIcon(frame)
    Elements.UpdateCombo(frame)
    Elements.StartCast(frame)
    Elements.UpdateAuras(frame)
    Elements.UpdatePortrait(frame)
end

-- Événement d'unité -> mise à jour ciblée.
Elements.UNIT_EVENTS = {
    UNIT_HEALTH = "UpdateHealth", UNIT_MAXHEALTH = "UpdateHealth", UNIT_FACTION = "UpdateHealth",
    UNIT_CONNECTION = "UpdateHealth",
    UNIT_POWER_UPDATE = "UpdatePower", UNIT_MAXPOWER = "UpdatePower", UNIT_DISPLAYPOWER = "UpdatePower",
    UNIT_POWER_FREQUENT = "UpdatePower",
    UNIT_NAME_UPDATE = "UpdateName", UNIT_LEVEL = "UpdateLevel", UNIT_FLAGS = "UpdateIndicators",
    UNIT_AURA = "UpdateAuras",
    UNIT_HEAL_PREDICTION = "UpdateHealPrediction", UNIT_ABSORB_AMOUNT_CHANGED = "UpdateHealPrediction",
    UNIT_PORTRAIT_UPDATE = "UpdatePortrait", UNIT_MODEL_CHANGED = "UpdatePortrait",
}

--- Route un événement reçu par le cadre. Retourne true s'il a été traité.
function Elements.OnEvent(frame, event)
    local method = Elements.UNIT_EVENTS[event]
    if method then
        Elements[method](frame)
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then Elements.UpdateCombo(frame) end
        return true
    end
    return Elements.HandleCast(frame, event)
end
