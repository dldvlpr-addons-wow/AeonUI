-- Modules/UnitFrameElements.lua
-- Éléments d'un cadre d'unité MuscaUI : santé, puissance, nom, niveau, barre d'incantation,
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

-- Couleurs de vie par réaction : défauts des cadres d'unité, repli quand MuscaUI_UnitFrames est désactivé.
Elements.REACTION_COLORS = {
    hostile  = { r = 0.85, g = 0.2, b = 0.2 },
    neutral  = { r = 0.9, g = 0.8, b = 0.2 },
    friendly = { r = 0.2, g = 0.75, b = 0.2 },
    tapped   = { r = 0.5, g = 0.5, b = 0.5 },
}

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

--- Classe d'un joueur lisible, sinon nil.
local function PlayerClass(unit)
    if NS.IsSecretUnit(unit) or not (SurelyPlayer(unit) or Known(UnitIsPlayer(unit))) then return nil end
    local _, classFile = UnitClass(unit)
    return Known(classFile)
end

--- Réaction lisible de l'unité, sinon nil.
local function ReadableReaction(unit)
    return _G.UnitReaction and Known(UnitReaction(unit, "player")) or nil
end

--- `reactionCache` : table { reaction } d'un cadre (FrameHealthColor), sinon la réaction est relue.
function Elements.HealthColor(unit, classColor, reactionCache)
    local classFile = classColor and PlayerClass(unit)
    if classFile then return NS.ClassColor(classFile) end
    local unitFrames = NS.db.modules.unitframes
    local colors = unitFrames and unitFrames.reactionColors or Elements.REACTION_COLORS
    -- Engagé par un autre : relu à chaque appel, aucun événement écouté ne le signale.
    if _G.UnitIsTapDenied and Known(UnitIsTapDenied(unit)) then
        return colors.tapped.r, colors.tapped.g, colors.tapped.b
    end
    local reaction
    if reactionCache then
        reaction = reactionCache.reaction
        if reaction == nil then reaction = ReadableReaction(unit) or false reactionCache.reaction = reaction end
    else
        reaction = ReadableReaction(unit)
    end
    if reaction then
        local c = reaction >= 5 and colors.friendly or reaction == 4 and colors.neutral or colors.hostile
        return c.r, c.g, c.b
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
    mana = { cur = "UnitPower", max = "UnitPowerMax", percent = "UnitPowerPercent", powerType = 0 },   -- mana même en forme
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
        else percent = Call(api.percent, unit, api.powerType, true, scale) end
        if isSecret(percent) or percent ~= nil then return string.format("%." .. (Elements.percentDecimals or 0) .. "f%%", percent) end
    end
    local cur, max = Known(Call(api.cur, unit, api.powerType)), Known(Call(api.max, unit, api.powerType))
    if cur and max and max > 0 then
        if Elements.percentDecimals then return string.format("%." .. Elements.percentDecimals .. "f%%", cur / max * 100) end
        return string.format("%d%%", math.floor(cur / max * 100 + 0.5))
    end
    return ValueText(Call(api.cur, unit, api.powerType))
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
    name = function(unit)
        local name = UnitName(unit)   -- secret passé tel quel
        if not isSecret(name) and name == nil then return "" end
        return name
    end,
    level = function(unit)
        local level = UnitLevel(unit)
        if Known(level) and level <= 0 then return "??" end
        return level
    end,
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

--- Choix du texte de durée des auras (balayage, texte propre, rien) pour un o:Dropdown.
function Elements.AuraDurationChoices()
    return { { name = L.UF_AURA_DURATION_SWIPE, value = "swipe" }, { name = L.UF_AURA_DURATION_TEXT, value = "text" },
             { name = L.UF_AURA_DURATION_NONE, value = "none" } }
end

--- Les neuf points du cadre d'une aura, pour le coin du texte des piles ou de la durée.
function Elements.AuraTextPointChoices()
    local list = {}
    for _, point in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
        list[#list + 1] = { name = L["POINT_" .. point], value = point }
    end
    return list
end

--- Format effectif : personnalisé s'il est rempli, sinon le préréglage du mode.
function Elements.TextFormat(custom, mode)
    if type(custom) == "string" and custom ~= "" then return custom end
    return Elements.TEXT_PRESETS[mode or "none"] or ""
end

--- Écrit un format sur un FontString pour l'unité (kind : "health" ou "power").
local textValues = {}   -- réutilisée : lue aussitôt par SetFormattedText

function Elements.SetUnitText(fontString, unit, kind, format)
    if not format or format == "" then fontString:SetText("") return end
    local entry = Elements.CompileFormat(format)
    local count = #entry.tokens
    if count == 0 then fontString:SetText(format) return end
    local values = textValues
    for i, name in ipairs(entry.tokens) do
        local value = Elements.TOKENS[name](unit, kind)   -- chaîne peut-être secrète : jamais testée
        if not isSecret(value) and value == nil then value = "" end
        values[i] = value
    end
    fontString:SetFormattedText(entry.pattern, unpack(values, 1, count))
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
    frame.health.centerText = Media:CreateText(frame.health, "OVERLAY", -1)   -- cfg.centerFormat
    frame.name =Media:CreateText(frame.health, "OVERLAY", 0)
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
    -- Soins absorbés : rongent la vie depuis son bout, remplis à rebours.
    frame.healAbsorb = CreateFrame("StatusBar", nil, clip)
    frame.healAbsorb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.healAbsorb:SetStatusBarColor(0.8, 0.15, 0.15, 0.6)
    if frame.healAbsorb.SetReverseFill then frame.healAbsorb:SetReverseFill(true) end
    frame.healPrediction:Hide()
    frame.absorb:Hide()
    frame.healAbsorb:Hide()
    -- Textes et icônes au-dessus des barres de prédiction.
    frame.overlay = CreateFrame("Frame", nil, health)
    frame.overlay:SetAllPoints(health)
    frame.overlay:SetFrameLevel(health:GetFrameLevel() + 3)
    for _, region in ipairs({ health.text, health.centerText, frame.name, frame.level }) do region:SetParent(frame.overlay) end

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
    frame.classification = Icon(frame.overlay)   -- élite, rare (cfg.classification)
    frame.pvp = Icon(frame.overlay)              -- faction ou mêlée générale, si marqué JcJ (cfg.pvp)
    frame.threat = Media:CreateText(frame.overlay, "OVERLAY", -2)   -- % de menace du joueur (cfg.threatPercent)

    -- Humeur du familier de chasseur (cfg.happiness) : cadre à part pour son infobulle.
    frame.happiness = CreateFrame("Frame", nil, frame)
    frame.happiness.texture = frame.happiness:CreateTexture(nil, "ARTWORK")
    frame.happiness.texture:SetAllPoints(frame.happiness)
    frame.happiness:EnableMouse(true)
    frame.happiness:SetScript("OnEnter", Elements.HappinessTooltip)
    frame.happiness:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.happiness:Hide()

    -- Points de combo : une seule barre de 0 à max, graduée. Aucun « si cur >= i » en Lua :
    -- la valeur peut rester secrète.
    frame.combo = Media:CreateStatusBar(frame)
    Media:CreateBackdrop(frame.combo)
    frame.combo.ticks = {}
    frame.combo:Hide()
    -- Variante en pastilles (cfg.comboPips) : une barre par point, bornée de i-1 à i, qui reçoit la
    -- même valeur : pleine ou vide sans comparaison en Lua. Posée sur l'emplacement de la barre.
    frame.comboPips = CreateFrame("Frame", nil, frame)
    frame.comboPips:SetAllPoints(frame.combo)
    frame.comboPips.pips = {}
    frame.comboPips.owner = NS.Modules.calling   -- pastilles créées plus tard, sur un événement
    frame.comboPips:Hide()

    local castbar = Media:CreateStatusBar(frame)
    castbar.backdropBackground, castbar.backdropEdges = Media:CreateBackdrop(castbar)   -- masquables (castBackground, castBorder)
    -- L'icône a son propre cadre : sa bordure 1 px suit le thème et l'échelle toute seule.
    castbar.iconFrame = CreateFrame("Frame", nil, castbar)
    castbar.icon = castbar.iconFrame:CreateTexture(nil, "ARTWORK")
    castbar.icon:SetAllPoints(castbar.iconFrame)
    castbar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Media:CreateBackdrop(castbar.iconFrame)
    castbar.text = Media:CreateText(castbar, "OVERLAY", -1)
    castbar.text:SetJustifyH("LEFT")
    castbar.timeText = Media:CreateText(castbar, "OVERLAY", -1)   -- temps restant, à droite
    castbar.timeText:SetJustifyH("RIGHT")
    castbar.timeText:Hide()
    -- Éclair blanc à l'interruption, estompé pendant la tenue rouge.
    castbar.flash = castbar:CreateTexture(nil, "OVERLAY")
    castbar.flash:SetAllPoints(castbar)
    NS.SetSolidColor(castbar.flash, 1, 1, 1, 1)
    if castbar.flash.SetBlendMode then castbar.flash:SetBlendMode("ADD") end
    castbar.flash:Hide()
    -- Latence du joueur : zone rouge au bout de l'incantation, où relancer ne sert plus.
    castbar.latency = castbar:CreateTexture(nil, "OVERLAY")
    NS.SetSolidColor(castbar.latency, 0.9, 0.15, 0.15, 0.45)
    castbar.latency:Hide()
    castbar.latencyText = Media:CreateText(castbar, "OVERLAY", -2)   -- « 45 ms » au bout de la barre (castLatencyText)
    castbar.latencyText:SetPoint("RIGHT", castbar.timeText, "LEFT", -4, 0)   -- dans la barre, à gauche du temps restant
    castbar.latencyText:Hide()
    castbar.owner = frame
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

--- Hauteur de la barre de combo du cadre (cfg.comboHeight, sinon celle de la puissance).
local function ComboHeight(cfg)
    if (cfg.comboHeight or 0) > 0 then return S(cfg.comboHeight) end
    return S((cfg.powerHeight or 0) > 0 and cfg.powerHeight or 6)
end

--- Place prise au-dessus du cadre par la barre de combo (cfg.comboAbove) : textes et auras du dessus la dépassent.
local function ComboAboveSpace(cfg)
    return (cfg.combo and cfg.comboAbove) and ComboHeight(cfg) + S(4) or 0
end

--- Pose tailles et positions d'après frame.cfg. Le cadre lui-même est dimensionné ici.
function Elements.Layout(frame)
    local cfg = frame.cfg
    local px = S(1)
    local width, height = S(cfg.width or 200), S(cfg.height or 40)
    frame:SetSize(width, height)

    local powerHeight = (cfg.power and (cfg.powerHeight or 0) > 0) and S(cfg.powerHeight) or 0
    -- Portrait dans le cadre (cadres de groupe serrés en grille) : les barres commencent après lui.
    local left = px
    if cfg.portrait and cfg.portraitInside then left = height end
    Place(frame.health, "TOPLEFT", frame, "TOPLEFT", left, -px)
    frame.health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, powerHeight > 0 and (powerHeight + 2 * px) or px)
    if powerHeight > 0 then
        Place(frame.power, "BOTTOMLEFT", frame, "BOTTOMLEFT", left, px)
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
    Place(frame.health.centerText, "CENTER", frame.health, "CENTER", 0, 0)
    Place(frame.power.text, "RIGHT", frame.power, "RIGHT", -inset, 0)

    -- L'absorption suit la prédiction : les deux s'additionnent au bout de la vie.
    local orientation = cfg.vertical and "VERTICAL" or "HORIZONTAL"
    frame.health:SetOrientation(orientation)
    local tip = frame.health:GetStatusBarTexture()
    local healAbsorb = frame.healAbsorb
    healAbsorb:SetOrientation(orientation)
    healAbsorb:ClearAllPoints()
    if cfg.vertical then
        healAbsorb:SetPoint("TOPLEFT", tip, "TOPLEFT", 0, 0)
        healAbsorb:SetPoint("TOPRIGHT", tip, "TOPRIGHT", 0, 0)
        healAbsorb:SetHeight(height - 2 * px - (powerHeight > 0 and (powerHeight + px) or 0))
    else
        healAbsorb:SetPoint("TOPRIGHT", tip, "TOPRIGHT", 0, 0)
        healAbsorb:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", 0, 0)
        healAbsorb:SetWidth(width - 2 * px)
    end
    for _, bar in ipairs({ frame.healPrediction, frame.absorb }) do
        bar:SetOrientation(orientation)
        bar:ClearAllPoints()
        if cfg.vertical then
            bar:SetPoint("BOTTOMLEFT", tip, "TOPLEFT", 0, 0)
            bar:SetPoint("BOTTOMRIGHT", tip, "TOPRIGHT", 0, 0)
            bar:SetHeight(height - 2 * px - (powerHeight > 0 and (powerHeight + px) or 0))
        else
            bar:SetPoint("TOPLEFT", tip, "TOPRIGHT", 0, 0)
            bar:SetPoint("BOTTOMLEFT", tip, "BOTTOMRIGHT", 0, 0)
            bar:SetWidth(width - 2 * px)
        end
        tip = frame.healPrediction:GetStatusBarTexture()
    end
    -- Couleurs et hauteur de l'absorption réglables (réglages communs du module, sinon ceux de Build).
    local global = frame.global or {}
    for bar, key in pairs({ [frame.healPrediction] = "healPredictionColor", [frame.absorb] = "absorbColor",
                            [frame.healAbsorb] = "healAbsorbColor" }) do
        local c = global[key]
        if c then bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1) end
    end
    local absorbHeight = global.absorbHeight or 100
    if not cfg.vertical and absorbHeight < 100 then
        local healthHeight = height - 2 * px - (powerHeight > 0 and (powerHeight + px) or 0)
        frame.absorb:ClearAllPoints()
        frame.absorb:SetPoint("BOTTOMLEFT", tip, "BOTTOMRIGHT", 0, 0)
        frame.absorb:SetWidth(width - 2 * px)
        frame.absorb:SetHeight(math.max(1, healthHeight * absorbHeight / 100))
    end

    if cfg.portrait and cfg.portraitInside then
        frame.portrait:SetSize(height - 2 * px, height - 2 * px)
        Place(frame.portrait, "TOPLEFT", frame, "TOPLEFT", px, -px)
        frame.portrait:Show()
    elseif cfg.portrait then
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

    -- Taille (0 : celle d'origine) et décalages réglables de chaque indicateur (cfg.<clé>Size, OffsetX, OffsetY).
    local function PlaceIndicator(region, key, defaultSize, point, relPoint, x, y)
        local size = (cfg[key .. "Size"] or 0) > 0 and S(cfg[key .. "Size"]) or defaultSize
        region:SetSize(size, size)
        Place(region, point, frame, relPoint, x + S(cfg[key .. "OffsetX"] or 0), y + S(cfg[key .. "OffsetY"] or 0))
    end
    local icon = S(16)
    PlaceIndicator(frame.combat, "combatIcon", icon, "CENTER", "TOPLEFT", 0, 0)
    PlaceIndicator(frame.resting, "combatIcon", icon, "CENTER", "TOPLEFT", 0, 0)
    frame.leader:SetSize(S(14), S(14))
    Place(frame.leader, "CENTER", frame, "TOPLEFT", S(18), 0)
    PlaceIndicator(frame.raidIcon, "raidIcon", S(18), "CENTER", "TOP", 0, 0)
    PlaceIndicator(frame.classification, "classificationIcon", icon, "CENTER", "TOPRIGHT", 0, 0)
    PlaceIndicator(frame.pvp, "pvpIcon", S(20), "CENTER", "BOTTOMLEFT", 0, 0)
    Place(frame.threat, "BOTTOMRIGHT", frame, "TOPRIGHT", 0, S(2) + ComboAboveSpace(cfg))
    PlaceIndicator(frame.happiness, "happinessIcon", height, "LEFT", "RIGHT", S(2), 0)

    local gap = S(4)
    local below = frame
    if cfg.combo then
        local comboHeight = ComboHeight(cfg)
        if cfg.comboAbove then   -- au-dessus du cadre : le reste (incantation, auras) reste sous le cadre
            Place(frame.combo, "BOTTOMLEFT", frame, "TOPLEFT", 0, gap)
            frame.combo:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, gap)
        else
            Place(frame.combo, "TOPLEFT", frame, "BOTTOMLEFT", 0, -gap)
            frame.combo:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -gap)
            below = frame.combo
        end
        frame.combo:SetHeight(comboHeight)
        frame.combo.width = width
    end
    frame.comboAllowed = cfg.combo and true or false

    local castbar = frame.castbar
    local castHeight = S(cfg.castbarHeight or 18)
    castbar.enabled = cfg.castbar and true or false
    castbar.detached = cfg.castbarDetached and true or false
    -- Détachée : hors du cadre, qui peut être caché par sa visibilité (pilote d'état).
    castbar:SetParent(castbar.detached and UIParent or frame)
    if castbar.detached then
        -- Sur son propre mover : le module le pose (Movers:Load), ici seulement la taille.
        castbar:ClearAllPoints()
        castbar:SetSize(S(cfg.castbarWidth or width), castHeight)
    else
        -- Icône à gauche (défaut), à droite ou absente (réglage commun castIcon) : la barre lui laisse la place.
        local iconSide = (frame.global or {}).castIcon or "left"
        local leftRoom = iconSide == "left" and castHeight + gap or 0
        local rightRoom = iconSide == "right" and castHeight + gap or 0
        Place(castbar, "TOPLEFT", below, "BOTTOMLEFT", leftRoom, -gap)
        castbar:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", -rightRoom, -gap)
        castbar:SetHeight(castHeight)
    end
    castbar.iconFrame:SetSize(castHeight, castHeight)
    local iconSide = (frame.global or {}).castIcon or "left"
    if iconSide == "right" then Place(castbar.iconFrame, "LEFT", castbar, "RIGHT", gap, 0)
    else Place(castbar.iconFrame, "RIGHT", castbar, "LEFT", -gap, 0) end
    castbar.iconFrame:SetShown(iconSide ~= "none")
    Place(castbar.text, "LEFT", castbar, "LEFT", inset, 0)
    -- Textes de la barre (réglages globaux, absents des plaques et groupes : comportement d'origine).
    local castGlobal = frame.global or {}
    local sizeDelta = castGlobal.castTextSize or 0
    Media:SetTextSizeDelta(castbar.text, -1 + sizeDelta)
    Media:SetTextSizeDelta(castbar.timeText, -1 + sizeDelta)
    castbar.text:SetShown(castGlobal.castText ~= false)
    -- Habillage (réglages communs, défauts = rendu d'origine) : fond, bordure, opacité, strate.
    castbar.bg:SetShown(castGlobal.castBackground ~= false)
    castbar.backdropBackground:SetShown(castGlobal.castBackground ~= false)
    for _, edge in pairs(castbar.backdropEdges) do edge:SetShown(castGlobal.castBorder ~= false) end
    castbar:SetAlpha(castGlobal.castAlpha or 1)
    local castStrata = castGlobal.castStrata
    if castStrata and castStrata ~= "" then castbar:SetFrameStrata(castStrata)
    else castbar:SetFrameStrata(castbar.detached and UIParent:GetFrameStrata() or frame:GetFrameStrata()) end
    castbar.showTimer = castGlobal.castTimer == true
    Place(castbar.timeText, "RIGHT", castbar, "RIGHT", -inset, 0)
    if not castbar.showTimer then castbar.timeText:Hide() end
    local shownIcon = ((frame.global or {}).castIcon or "left") ~= "none"
    local barWidth = (castbar.detached and S(cfg.castbarWidth or width) or width) - (shownIcon and castHeight + gap or 0) - 2 * inset
    castbar.text:SetWidth(math.max(1, barWidth - (castbar.showTimer and 40 or 0)))
    if not castbar.enabled then castbar:Hide() end
    if castbar.enabled and not castbar.detached then below = castbar end

    frame.aurasAnchor = below
    Elements.LayoutAuras(frame)
end

--------------------------------------------------------------------------------
-- Mises à jour
--------------------------------------------------------------------------------

--- Paliers pour NS.StepColor, tirés de couples (pourcentage, couleur) ; 0 = palier coupé.
function Elements.Bands(...)
    local steps = {}
    for i = 1, select("#", ...), 2 do
        local percent, color = select(i, ...)
        if (tonumber(percent) or 0) > 0 and color then
            steps[#steps + 1] = { percent / 100, color.r, color.g, color.b }
        end
    end
    table.sort(steps, function(a, b) return a[1] < b[1] end)
    return steps
end

--- Couleur r, g, b remplacée par celle du palier atteint (voir NS.StepColor), peut-être secrète.
function Elements.BandColor(unit, kind, steps, r, g, b)
    if #steps == 0 then return r, g, b end
    local applied, sr, sg, sb = NS.StepColor(unit, kind, steps, r, g, b)
    if applied then return sr, sg, sb end
    return r, g, b
end

--- Pourcentages (1 à 99) d'une saisie « 25, 50 », plus `extra` s'il est dans ces bornes.
function Elements.HashPercents(text, extra)
    local list = {}
    for percent in pairs(NS.ParseSpellList(text)) do
        if percent > 0 and percent < 100 then list[#list + 1] = percent end
    end
    extra = tonumber(extra)
    if extra and extra > 0 and extra < 100 then list[#list + 1] = extra end
    return list
end

--- Repères fins à chaque pourcentage de `percents` sur `bar` (textures réutilisées).
function Elements.SetHashLines(bar, percents, vertical, length)
    bar.hashLines = bar.hashLines or {}
    for i, percent in ipairs(percents) do
        local line = bar.hashLines[i]
        if not line then
            line = (bar.front or bar):CreateTexture(nil, "OVERLAY")
            NS.SetSolidColor(line, 1, 1, 1, 0.8)
            bar.hashLines[i] = line
        end
        local offset = length * percent / 100
        line:ClearAllPoints()
        if vertical then
            line:SetHeight(S(1))
            line:SetPoint("LEFT", bar, "BOTTOMLEFT", 0, offset)
            line:SetPoint("RIGHT", bar, "BOTTOMRIGHT", 0, offset)
        else
            line:SetWidth(S(1))
            line:SetPoint("TOP", bar, "TOPLEFT", offset, 0)
            line:SetPoint("BOTTOM", bar, "BOTTOMLEFT", offset, 0)
        end
        line:Show()
    end
    for i = #percents + 1, #bar.hashLines do bar.hashLines[i]:Hide() end
end

--- Textes de la barre de vie : ils peuvent porter [name] et [level], rafraîchis aussi sur ces événements.
function Elements.UpdateHealthTexts(frame)
    local bar, global = frame.health, frame.global
    -- Décimales du pourcentage (cadres d'unité) : posées le temps de ces deux textes, jamais pour les autres modules.
    Elements.percentDecimals = global and (global.percentDecimals or 0) > 0 and global.percentDecimals or nil
    Elements.SetUnitText(bar.text, frame.unit, "health",
        Elements.TextFormat(frame.cfg and frame.cfg.healthFormat, global and global.healthText or "current"))
    if bar.centerText then Elements.SetUnitText(bar.centerText, frame.unit, "health", frame.cfg and frame.cfg.centerFormat) end
    Elements.percentDecimals = nil
end

--- Classe en cache par cadre, clé = GUID lisible (la classe d'un GUID ne change pas) ; la couleur
-- est relue (CUSTOM_CLASS_COLORS peut changer). GUID secret ou absent : rien en cache.
-- Réaction en cache par cadre, même clé GUID, vidée par UpdateFaction (UNIT_FACTION).
local function FrameHealthColor(frame, unit, classColor)
    local guid = Known(UnitGUID(unit))
    if not guid then frame.reactionGUID = nil return Elements.HealthColor(unit, classColor) end
    if frame.reactionGUID ~= guid then frame.reactionGUID, frame.reactionCache = guid, {} end
    if not classColor then return Elements.HealthColor(unit, false, frame.reactionCache) end
    if frame.classGUID ~= guid then
        local classFile = PlayerClass(unit)
        if not classFile then return Elements.HealthColor(unit, false, frame.reactionCache) end
        frame.classGUID, frame.classFile = guid, classFile
    end
    return NS.ClassColor(frame.classFile)
end

-- Paliers de vie basse par table de réglages, refaits si le seuil ou la couleur change.
local lowHealthSteps = setmetatable({}, { __mode = "k" })
local function LowHealthSteps(global)
    local percent, c = global.lowHealth, global.lowHealthColor
    local r, g, b = c and c.r, c and c.g, c and c.b
    local cache = lowHealthSteps[global]
    if not cache or cache.percent ~= percent or cache.r ~= r or cache.g ~= g or cache.b ~= b then
        cache = { percent = percent, r = r, g = g, b = b, steps = Elements.Bands(percent, c) }
        lowHealthSteps[global] = cache
    end
    return cache.steps
end

--- Pose la valeur d'une barre ; animation douce si le réglage commun `smoothBars` est actif.
-- L'interpolation n'est jamais passée à nil : sans l'énumération, valeur directe.
local function SetBarValue(bar, value, global)
    local mode = global and global.smoothBars and Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut
    if mode then bar:SetValue(value, mode) else bar:SetValue(value) end
end

--- Vie, couleur et textes, sans la prédiction de soins (UpdateHealthAndPrediction).
-- `skipTexts` : l'appelant rafraîchit les textes lui-même (UpdateAll).
function Elements.UpdateHealth(frame, skipTexts)
    local unit = frame.unit
    local bar = frame.health
    bar:SetMinMaxValues(0, UnitHealthMax(unit))
    local global = frame.global
    SetBarValue(bar, UnitHealth(unit), global)
    local applied, r, g, b = false
    if global and global.healthGradient then applied, r, g, b = NS.HealthGradient(unit) end
    if applied then Media:SetHealthColor(bar, r, g, b)   -- r, g, b peut-être secrets : jamais testés
    else
        r, g, b = FrameHealthColor(frame, unit, global and global.classColor)
        if global and (global.lowHealth or 0) > 0 then
            r, g, b = Elements.BandColor(unit, "health", LowHealthSteps(global), r, g, b)
        end
        Media:SetHealthColor(bar, r, g, b)
    end
    if not skipTexts then Elements.UpdateHealthTexts(frame) end
end

--- Vie et prédiction : les montants du calculateur sont plafonnés par la vie courante et manquante.
function Elements.UpdateHealthAndPrediction(frame)
    Elements.UpdateHealth(frame)
    Elements.UpdateHealPrediction(frame)
end

--- Montant d'une API de prédiction : secret passé tel quel, absent = 0.
local function Amount(name, unit)
    local value = Call(name, unit)
    if isSecret(value) then return value end
    return value or 0
end

local function UpdatePredictionBar(bar, on, unit, amount)
    if on then
        bar:SetMinMaxValues(0, UnitHealthMax(unit))
        bar:SetValue(amount)
        bar:Show()
    else
        bar:Hide()
    end
end

local function UpdatePredictionBarFromApi(bar, api, on, unit)
    on = on and _G[api]
    UpdatePredictionBar(bar, on, unit, on and Amount(api, unit))
end

--- Soins entrants et absorptions (global.healPrediction), valeurs peut-être secrètes : les barres
-- les reçoivent sans comparaison. Calculateur du moteur si présent (montants plafonnés), sinon
-- les API simples ; sans aucune, barre cachée.
function Elements.UpdateHealPrediction(frame)
    if not frame.healPrediction then return end
    local on = frame.global and frame.global.healPrediction
    local unit = frame.unit
    local incoming, absorb, healAbsorb
    if on then incoming, absorb, healAbsorb = NS.GetHealPrediction(frame, unit) end
    if isSecret(incoming) or incoming ~= nil then
        UpdatePredictionBar(frame.healPrediction, on, unit, incoming)
        UpdatePredictionBar(frame.absorb, on, unit, absorb)
        if frame.healAbsorb then UpdatePredictionBar(frame.healAbsorb, on, unit, healAbsorb) end
        return
    end
    UpdatePredictionBarFromApi(frame.healPrediction, "UnitGetIncomingHeals", on, unit)
    UpdatePredictionBarFromApi(frame.absorb, "UnitGetTotalAbsorbs", on, unit)
    if frame.healAbsorb then UpdatePredictionBarFromApi(frame.healAbsorb, "UnitGetTotalHealAbsorbs", on, unit) end
end

--- Portrait 2D de l'unité (cfg.portrait).
function Elements.UpdatePortrait(frame)
    if not (frame.portrait and frame.cfg and frame.cfg.portrait) or not _G.SetPortraitTexture then return end
    local texture = frame.portrait.texture
    -- Style « classe » : icône de la classe d'un joueur ; autre unité : portrait habituel.
    local classFile = frame.cfg.portraitStyle == "class" and PlayerClass(frame.unit)
    local coords = classFile and _G.CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if coords then
        texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        texture:SetTexCoord(unpack(coords))
        return
    end
    texture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    pcall(SetPortraitTexture, texture, frame.unit)
end

function Elements.UpdatePower(frame)
    local unit = frame.unit
    local bar = frame.power
    if not (frame.cfg.power and (frame.cfg.powerHeight or 0) > 0) then bar:Hide() return end
    local max = UnitPowerMax(unit)
    local knownMax = Known(max)
    if knownMax and knownMax <= 0 then bar:Hide() return end
    bar:SetMinMaxValues(0, max)
    SetBarValue(bar, UnitPower(unit), frame.global)
    local custom = frame.cfg.powerColorCustom and frame.cfg.powerColor   -- couleur choisie, avant celle de la ressource
    if custom then bar:SetStatusBarColor(custom.r, custom.g, custom.b) else bar:SetStatusBarColor(Elements.PowerColor(unit)) end
    Elements.SetUnitText(bar.text, unit, "power",
        Elements.TextFormat(frame.cfg and frame.cfg.powerFormat, frame.global and frame.global.powerText))
    Elements.SetManaSpark(bar, unit == "player" and frame.cfg.manaSpark)
    Elements.SetManaCostPrediction(bar, unit == "player" and frame.cfg.manaCostPrediction)
    bar:Show()
end

--------------------------------------------------------------------------------
-- Règle des 5 secondes
--------------------------------------------------------------------------------
-- Après une dépense de mana, la régénération hors incantation ne reprend que 5 s plus tard.
-- Une étincelle parcourt la barre de mana du joueur pendant ces 5 s. Dépense = sort réussi qui
-- coûte du mana : le mana lui-même est secret sur Forever, son coût ne l'est pas.
-- ponytail: un sort rendu gratuit (Idées claires) compte aussi ; lire le mana s'il redevient lisible.

local FIVE_SECOND_RULE = 5
local sparkBars = {}             -- [StatusBar] = true : barres qui montrent l'étincelle
local sparkTracker
local spentAt

local function ManaType() return Enum and Enum.PowerType and Enum.PowerType.Mana or 0 end

local function ShowsMana() return Known(UnitPowerType("player")) == ManaType() end

local function MoveSparks()
    local progress = spentAt and (GetTime() - spentAt) / FIVE_SECOND_RULE
    if not progress or progress >= 1 then
        spentAt = nil
        sparkTracker:SetScript("OnUpdate", nil)
    end
    for bar in pairs(sparkBars) do
        local spark = bar.manaSpark
        if spentAt and bar:IsVisible() then
            local vertical = bar.GetOrientation and bar:GetOrientation() == "VERTICAL"
            spark:ClearAllPoints()
            if vertical then
                spark:SetSize(bar:GetWidth() * 2, 8)
                spark:SetPoint("CENTER", bar, "BOTTOM", 0, bar:GetHeight() * progress)
            else
                spark:SetSize(8, bar:GetHeight() * 2)
                spark:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * progress, 0)
            end
            spark:Show()
        else
            spark:Hide()
        end
    end
end

local function OnSparkEvent(_, _, _, _, spellID)
    spellID = Known(spellID)
    if not (spellID and NS.SpellCostsMana(spellID)) then return end
    spentAt = GetTime()
    sparkTracker:SetScript("OnUpdate", MoveSparks)
end

--- Montre ou non l'étincelle sur `bar` (barre de puissance du joueur) ; rien si elle n'affiche pas le mana.
function Elements.SetManaSpark(bar, on)
    on = on and ShowsMana() or nil
    if not on and not sparkBars[bar] then return end
    if on and not bar.manaSpark then
        bar.manaSpark = (bar.front or bar):CreateTexture(nil, "OVERLAY", nil, 7)
        bar.manaSpark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        bar.manaSpark:SetBlendMode("ADD")
        bar.manaSpark:Hide()
    end
    sparkBars[bar] = on
    if not on then bar.manaSpark:Hide() end
    if not sparkTracker then
        sparkTracker = CreateFrame("Frame")
        sparkTracker:SetScript("OnEvent", OnSparkEvent)
    end
    if next(sparkBars) then
        if not sparkTracker:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED") then
            NS.RegisterEventSafe(sparkTracker, "UNIT_SPELLCAST_SUCCEEDED", "player")
        end
    else
        sparkTracker:UnregisterAllEvents()
        sparkTracker:SetScript("OnUpdate", nil)
        spentAt = nil
    end
end

--------------------------------------------------------------------------------
-- Prédiction du coût en mana
--------------------------------------------------------------------------------
-- Pendant une incantation qui coûte du mana, un segment clair part du bord du remplissage vers
-- l'arrière, de la longueur du coût. Mana et maximum peuvent être secrets : le segment reprend les
-- bornes de la barre et reçoit le coût par SetValue, rogné par un cadre aux dimensions de la barre.
-- Incantation suivie par son castGUID : un sort instantané lancé entre-temps ne l'efface pas.

local costBars = {}              -- [StatusBar] = true : barres qui montrent la prédiction
local costTracker
local costCastGUID

local function HideCostSegments()
    costCastGUID = nil
    for bar in pairs(costBars) do bar.manaCost.segment:Hide() end
end

local function ShowCostSegment(bar, cost)
    local segment = bar.manaCost.segment
    local fill = bar:GetStatusBarTexture()
    local vertical = bar.GetOrientation and bar:GetOrientation() == "VERTICAL"
    segment:SetStatusBarTexture(Media:StatusBarTexture())
    segment:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    segment:ClearAllPoints()
    if vertical then
        segment:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
        segment:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
        segment:SetHeight(bar:GetHeight())
    else
        segment:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
        segment:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
        segment:SetWidth(bar:GetWidth())
    end
    -- Couleur du type de puissance : celle de la barre peut être secrète (dégradé par pourcentage).
    local r, g, b = Elements.PowerColor("player")
    segment:SetStatusBarColor((r + 1) / 2, (g + 1) / 2, (b + 1) / 2, 0.6)
    segment:SetMinMaxValues(bar:GetMinMaxValues())
    segment:SetValue(cost)
    segment:Show()
end

local function OnCostEvent(_, event, _, castGUID, spellID)
    if event ~= "UNIT_SPELLCAST_START" then
        -- GUID secret : rien à comparer, le segment s'efface plutôt que de rester affiché.
        if costCastGUID and (isSecret(castGUID) or castGUID == costCastGUID) then HideCostSegments() end
        return
    end
    castGUID, spellID = Known(castGUID), Known(spellID)
    local cost = spellID and NS.GetSpellManaCost(spellID)
    if not (castGUID and cost) or not ShowsMana() then HideCostSegments() return end
    costCastGUID = castGUID
    for bar in pairs(costBars) do
        if bar:IsVisible() then ShowCostSegment(bar, cost) end
    end
end

local COST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

--- Montre ou non la prédiction du coût sur `bar` (barre de puissance du joueur) ; rien si elle n'affiche pas le mana.
function Elements.SetManaCostPrediction(bar, on)
    on = on and ShowsMana() or nil
    if not on and not costBars[bar] then return end
    if on and not bar.manaCost then
        local clip = CreateFrame("Frame", nil, bar)
        clip:SetAllPoints(bar)
        clip:SetClipsChildren(true)
        -- Texte, étincelle et repères passent dans un cadre au-dessus du segment.
        local front = CreateFrame("Frame", nil, bar)
        front:SetAllPoints(bar)
        front:SetFrameLevel(clip:GetFrameLevel() + 1)
        if bar.text then bar.text:SetParent(front) end
        if bar.manaSpark then bar.manaSpark:SetParent(front) end
        for _, line in ipairs(bar.hashLines or {}) do line:SetParent(front) end
        bar.front = front
        clip.segment = CreateFrame("StatusBar", nil, clip)
        clip.segment:SetReverseFill(true)
        clip.segment:Hide()
        bar.manaCost = clip
    end
    costBars[bar] = on
    if not on then bar.manaCost.segment:Hide() end
    if not costTracker then
        costTracker = CreateFrame("Frame")
        costTracker:SetScript("OnEvent", OnCostEvent)
    end
    if next(costBars) then
        if not costTracker:IsEventRegistered(COST_EVENTS[1]) then
            for _, event in ipairs(COST_EVENTS) do NS.RegisterEventSafe(costTracker, event, "player") end
        end
    else
        costTracker:UnregisterAllEvents()
        costCastGUID = nil
    end
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

--- Mot du nom gardé selon `format` : "first" prénom, "last" dernier mot ; autre : nom entier.
function Elements.FormatName(name, format)
    if not name or (format ~= "first" and format ~= "last") then return name end
    return name:match(format == "first" and "^(%S+)" or "(%S+)$") or name
end

function Elements.UpdateName(frame, skipTexts)
    local unit = frame.unit
    if not skipTexts then Elements.UpdateHealthTexts(frame) end
    if frame.cfg.name == false then frame.name:Hide() return end
    -- Nom secret (identité masquée) : aucun test booléen dessus, il part tel quel au widget.
    local name = UnitName(unit)
    if not isSecret(name) and name == nil then name = "" end
    if not NS.IsSecret(name) then name = Elements.FormatName(name, frame.cfg.nameFormat) end
    if frame.cfg.nameLength and not NS.IsSecret(name) then name = Elements.TruncateName(name, frame.cfg.nameLength) end
    frame.name:SetText(name)
    if frame.cfg.nameTarget then   -- « nom > cible » ; valeurs secrètes passées au widget sans test
        local targetName = UnitName(unit .. "target")
        if isSecret(targetName) or (targetName and targetName ~= "") then
            frame.name:SetFormattedText("%s > %s", name, targetName)
        end
    end
    local custom = frame.cfg.nameColor   -- cadres de groupe : couleur choisie, avant celle de classe
    if custom then
        frame.name:SetTextColor(custom.r, custom.g, custom.b)
    elseif frame.global and frame.global.classColor then
        frame.name:SetTextColor(Elements.HealthColor(unit, true))
    else
        frame.name:SetTextColor(1, 1, 1)
    end
    frame.name:Show()
end

function Elements.UpdateLevel(frame, skipTexts)
    local unit = frame.unit
    local text = frame.level
    if not skipTexts then Elements.UpdateHealthTexts(frame) end
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
    Elements.UpdateClassification(frame)
    Elements.UpdatePvP(frame)
end

-- Atlas du moteur 12.x ; absent du client : SetAtlas rend false, rien n'est montré.
local CLASSIFICATION_ATLAS = {
    elite = "nameplates-icon-elite-gold", worldboss = "nameplates-icon-elite-gold",
    rareelite = "nameplates-icon-elite-silver", rare = "nameplates-icon-elite-silver",
}

function Elements.UpdateClassification(frame)
    local icon = frame.classification
    if not icon then return end
    local kind = frame.cfg.classification and _G.UnitClassification and Known(UnitClassification(frame.unit))
    local atlas = kind and CLASSIFICATION_ATLAS[kind]
    icon:SetShown(atlas and icon.SetAtlas and icon:SetAtlas(atlas) and true or false)
end

local PVP_TEXTURES = { Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
                       Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance" }
local FFA_TEXTURE = "Interface\\TargetingFrame\\UI-PVP-FFA"

--- Écusson JcJ : mêlée générale, sinon faction de l'unité marquée JcJ. Valeur secrète : rien.
function Elements.UpdatePvP(frame)
    local icon = frame.pvp
    if not icon then return end
    local unit, texture = frame.unit, nil
    if frame.cfg.pvp then
        if _G.UnitIsPVPFreeForAll and Known(UnitIsPVPFreeForAll(unit)) then
            texture = FFA_TEXTURE
        elseif _G.UnitIsPVP and Known(UnitIsPVP(unit)) and _G.UnitFactionGroup then
            texture = PVP_TEXTURES[Known(UnitFactionGroup(unit)) or ""]
        end
    end
    if texture then
        icon:SetTexture(texture)
        icon:SetTexCoord(0, 0.62, 0, 0.62)   -- l'écusson occupe le coin haut-gauche du fichier
        icon:Show()
    else
        icon:Hide()
    end
end

-- Menace de l'unité : 2 agro instable, 3 agro ferme (couleurs partagées avec les cadres de groupe).
Elements.THREAT_COLORS = { [2] = { 1, 0.6, 0 }, [3] = { 0.9, 0.2, 0.2 } }

--- Niveau de menace affichable (2 ou 3), sinon nil. Statut secret : rien.
function Elements.ThreatStatus(unit)
    if not _G.UnitThreatSituation then return nil end
    local ok, status = pcall(UnitThreatSituation, unit)
    status = ok and Known(status) or nil
    return status and Elements.THREAT_COLORS[status] and status or nil
end

--- Bordure du cadre à la couleur de la menace de son unité (cfg.threatBorder), sinon du thème.
-- Sans l'option, la bordure appartient à son module (plaques : surbrillance de la cible) : on ne
-- la repeint que pour effacer une couleur de menace posée ici.
function Elements.UpdateThreatBorder(frame)
    local edges = frame.border
    if not edges or not (frame.cfg.threatBorder or frame.threatPainted) then return end
    local status = frame.cfg.threatBorder and Elements.ThreatStatus(frame.unit)
    local c = status and Elements.THREAT_COLORS[status]
    frame.threatPainted = c and true or false
    for _, edge in pairs(edges) do
        if c then NS.SetSolidColor(edge, c[1], c[2], c[3], 1)
        else
            local theme = NS.db.theme.border
            NS.SetSolidColor(edge, theme.r, theme.g, theme.b, theme.a or 1)
        end
    end
end

local NEUTRAL_THREAT_COLOR = { 1, 1, 1 }

--- % de menace du joueur sur l'unité (cfg.threatPercent), au-dessus du cadre, à la couleur du
-- statut de menace. Rien hors liste de menace ou si la valeur est secrète.
function Elements.UpdateThreatPercent(frame)
    local percent, status
    if frame.cfg.threatPercent then percent, status = NS.GetThreatPercent(frame.unit) end
    if not percent then frame.threat:SetText("") return end
    local c = status and Elements.THREAT_COLORS[status] or NEUTRAL_THREAT_COLOR
    frame.threat:SetTextColor(c[1], c[2], c[3])
    frame.threat:SetFormattedText("%d%%", percent)
end

--- Bordure et % de menace.
function Elements.UpdateThreat(frame)
    Elements.UpdateThreatBorder(frame)
    Elements.UpdateThreatPercent(frame)
end

-- Atlas du moteur, comme l'icône du cadre de familier Blizzard.
local HAPPINESS_ATLAS = { "UI-PetMad", "UI-PetNeutral", "UI-PetHappiness" }

function Elements.UpdateHappiness(frame)
    local holder = frame.happiness
    if not holder then return end
    local happiness = frame.cfg.happiness and frame.unit == "pet" and NS.GetPetHappiness()
    local atlas = happiness and HAPPINESS_ATLAS[happiness]
    holder:SetShown(atlas and holder.texture:SetAtlas(atlas) and true or false)
end

--- Infobulle de l'humeur : état, part des dégâts, loyauté (libellés du client).
function Elements.HappinessTooltip(holder)
    local happiness, damage, loyalty = NS.GetPetHappiness()
    local label = happiness and _G["PET_HAPPINESS" .. happiness]
    if not label then return end
    GameTooltip:SetOwner(holder, "ANCHOR_RIGHT")
    GameTooltip:SetText(label)
    if damage and _G.PET_DAMAGE_PERCENTAGE then GameTooltip:AddLine(string.format(PET_DAMAGE_PERCENTAGE, damage), 1, 1, 1) end
    if loyalty and loyalty > 0 and _G.GAINING_LOYALTY then GameTooltip:AddLine(GAINING_LOYALTY, 0.2, 0.9, 0.2)
    elseif loyalty and loyalty < 0 and _G.LOSING_LOYALTY then GameTooltip:AddLine(LOSING_LOYALTY, 0.9, 0.2, 0.2) end
    GameTooltip:Show()
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
    -- Aussi appelé par des barres sans pastilles (ResourceBars) : ni holder ni cfg.
    local bar, holder, cfg = frame.combo, frame.comboPips, frame.cfg or {}
    if holder then holder:Hide() end
    -- Joueur ou cible : les points sont toujours ceux du joueur sur sa cible.
    if not frame.comboAllowed or (frame.unit ~= "player" and frame.unit ~= "target") then bar:Hide() return end
    local max = UnitPowerMax("player", ComboPowerType())
    local knownMax = Known(max)
    if not knownMax or knownMax <= 0 then bar:Hide() return end
    local color = cfg.comboColor or { r = 1, g = 0.82, b = 0 }
    if holder and cfg.comboPips then
        bar:Hide()
        local spacing = S(cfg.comboSpacing or 2)
        local width = ((bar.width or bar:GetWidth() or 0) - spacing * (knownMax - 1)) / knownMax
        local current = NS.ComboPointsRaw()
        for i = 1, knownMax do
            local pip = holder.pips[i]
            if not pip then
                pip = Media:CreateStatusBar(holder, holder.owner)
                Media:CreateBackdrop(pip)
                holder.pips[i] = pip
            end
            pip:ClearAllPoints()
            pip:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (width + spacing), 0)
            pip:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", (i - 1) * (width + spacing), 0)
            pip:SetWidth(math.max(1, width))
            pip:SetMinMaxValues(i - 1, i)
            pip:SetValue(current)
            pip:SetStatusBarColor(color.r, color.g, color.b)
            pip:Show()
        end
        for i = knownMax + 1, #holder.pips do holder.pips[i]:Hide() end
        holder:Show()
        return
    end
    bar:SetMinMaxValues(0, max)
    bar:SetValue(NS.ComboPointsRaw())
    bar:SetStatusBarColor(color.r, color.g, color.b)
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
-- Canalisations et nombre de tops (rang le plus haut), par sort de référence ; reconnues par nom,
-- tous rangs confondus. Arcane Missiles 5143, Drain de vie 689, Drain d'âme 1120, Drain de mana
-- 5138, Captation de vie 755, Fouet mental 15407, Blizzard 10, Ouragan 16914, Tranquillité 740,
-- Pluie de feu 5740, Salve 1510, Évocation 12051.
local CHANNEL_TICKS = { [5143] = 5, [689] = 5, [1120] = 5, [5138] = 5, [755] = 10, [15407] = 3, [10] = 8,
                        [16914] = 10, [740] = 5, [5740] = 4, [1510] = 6, [12051] = 4 }
local ticksByName
local GCD_FALLBACK = 1.5

--- Tops d'une canalisation du joueur, d'après l'identifiant ou le nom du sort ; nil si inconnu.
function Elements.ChannelTicks(spellID, name)
    if not isSecret(spellID) and CHANNEL_TICKS[spellID] then return CHANNEL_TICKS[spellID] end
    if isSecret(name) or type(name) ~= "string" then return nil end
    if not ticksByName then
        ticksByName = {}
        for id, ticks in pairs(CHANNEL_TICKS) do
            local spellName = NS.GetSpellName(id)
            if spellName then ticksByName[spellName] = ticks end
        end
    end
    return ticksByName[name]
end

--- Repères de la barre d'incantation du joueur : tops de canalisation, fin de la recharge globale
-- (incantation plus longue qu'elle) et zone de latence. Rien si la durée est secrète.
local function UpdateCastMarks(frame, name, startTime, endTime, channeling, spellID)
    local bar, global = frame.castbar, frame.global
    local s, e = Known(startTime), Known(endTime)
    local duration = s and e and e > s and (e - s) / 1000 or nil
    local percents = {}
    bar.latency:Hide()
    bar.latencyText:Hide()
    if frame.unit == "player" and global and duration then
        local width = bar:GetWidth() or 0
        if channeling and global.castTicks then
            local ticks = Elements.ChannelTicks(spellID, name)
            for i = 1, (ticks or 1) - 1 do percents[#percents + 1] = i * 100 / ticks end
        elseif not channeling then
            if global.castGCD then
                local _, gcd = NS.GetGlobalCooldown()
                gcd = gcd or GCD_FALLBACK
                if gcd < duration then percents[1] = gcd * 100 / duration end
            end
            local latency = global.castLatency and NS.WorldLatency() or 0
            if latency > 0 then
                bar.latency:ClearAllPoints()
                bar.latency:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
                bar.latency:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
                bar.latency:SetWidth(math.max(1, width * math.min(1, latency / duration)))
                bar.latency:Show()
                if global.castLatencyText then
                    bar.latencyText:SetFormattedText("%d ms", math.floor(latency * 1000 + 0.5))
                    bar.latencyText:Show()
                end
            end
        end
        Elements.SetHashLines(bar, percents, false, width)
    else
        Elements.SetHashLines(bar, percents, false, 0)
    end
end

function Elements.StartCast(frame)
    local bar = frame.castbar
    if not bar.enabled then bar:Hide() return end
    local unit = frame.unit
    local name, text, texture, startTime, endTime, _, _, notInterruptible, spellID = UnitCastingInfo(unit)
    -- Incantation secrète possible : tester la présence sans test booléen sur la valeur.
    local channeling = false
    if not isSecret(name) and name == nil and _G.UnitChannelInfo then
        name, text, texture, startTime, endTime, _, notInterruptible, spellID = UnitChannelInfo(unit)
        channeling = true
    end
    if not isSecret(name) and name == nil then bar:Hide() return end
    UpdateCastMarks(frame, name, startTime, endTime, channeling, spellID)

    bar.holdTime = 0
    bar.manual = nil
    bar.flash:Hide()
    if not (isSecret(text) or text ~= nil) then text = name end
    local global = frame.global
    -- Rang du sort (clients à rangs) : ajouté au libellé quand ni le libellé ni l'identifiant ne sont secrets.
    if global and global.castRank and spellID and not isSecret(spellID) and not isSecret(text)
        and type(text) == "string" then
        local rank = NS.GetSpellRankText(spellID)
        if rank then text = text .. " (" .. rank .. ")" end
    end
    -- Cible du sort (cadres autres que le joueur) : son nom après celui du sort, peut-être secret.
    local targetName = global and global.castTarget and unit ~= "player" and UnitName(unit .. "target")
    if isSecret(targetName) or targetName then
        bar.text:SetFormattedText("%s > %s", text, targetName)
    else
        bar.text:SetText(text)
    end
    if isSecret(texture) or texture ~= nil then bar.icon:SetTexture(texture) else bar.icon:SetTexture(QUESTION_ICON) end
    bar.notInterruptible = notInterruptible
    bar.spellID = spellID
    bar.channeling = channeling
    Elements.UpdateCastColor(frame)

    local durationApi = channeling and _G.UnitChannelDuration or _G.UnitCastingDuration
    bar.durationObject = nil
    bar.timerElapsed = 1   -- minuteur remis à jour au prochain OnUpdate
    if bar.SetTimerDuration and durationApi then
        -- Le moteur anime la barre : aucune lecture d'horloge, la fin peut rester secrète.
        local duration = durationApi(unit)
        bar.durationObject = duration
        bar:SetTimerDuration(duration, Interpolation(), Direction(channeling))
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

local UNINTERRUPTIBLE = { 0.6, 0.6, 0.6 }

--- Couleur de la barre : grise si non interruptible (drapeau peut-être secret : le moteur choisit),
-- sinon la couleur « sort important », sinon « interruption prête », sinon l'accent.
function Elements.UpdateCastColor(frame)
    local bar = frame.castbar
    local r, g, b = Media:Accent()
    local global = frame.global
    if global and global.interruptReady and frame.unit ~= "player" then
        r, g, b = NS.InterruptReadyColor(global.interruptReadyColor, r, g, b)
    end
    if global and global.importantCast and frame.unit ~= "player" then
        local important = NS.IsSpellImportant(bar.spellID)
        if isSecret(important) or important ~= nil then
            local c = global.importantCastColor
            r, g, b = NS.ColorFromBoolean(important, c.r, c.g, c.b, r, g, b)
        end
    end
    -- Canalisation : sa propre couleur (réglage global, désactivé par défaut).
    if global and global.castChannel and bar.channeling and global.castChannelColor then
        local c = global.castChannelColor
        r, g, b = c.r, c.g, c.b
    end
    local locked = bar.notInterruptible
    if not isSecret(locked) and locked == nil then locked = false end
    local u = global and global.castLockedColor
    local lr, lg, lb = UNINTERRUPTIBLE[1], UNINTERRUPTIBLE[2], UNINTERRUPTIBLE[3]
    if u then lr, lg, lb = u.r, u.g, u.b end
    bar:SetStatusBarColor(NS.ColorFromBoolean(locked, lr, lg, lb, r, g, b))
end

local INTERRUPT_HOLD = 0.5

function Elements.StopCast(frame, interrupted)
    local bar = frame.castbar
    if not bar:IsShown() then return end
    if interrupted then
        bar.manual = nil
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar:SetStatusBarColor(0.9, 0.2, 0.2)
        bar.holdTime = INTERRUPT_HOLD
        bar.flash:SetAlpha(0.8)
        bar.flash:Show()
    else
        bar:Hide()
    end
end

local TIMER_INTERVAL = 0.1

--- Temps restant écrit dans `bar.timeText` (toutes les 0,1 s). La durée du moteur peut être secrète :
-- elle n'est jamais comparée, seulement donnée au formateur du texte.
function Elements.UpdateCastTimer(bar, elapsed)
    if not bar.showTimer then return end
    bar.timerElapsed = (bar.timerElapsed or 0) + elapsed
    if bar.timerElapsed < TIMER_INTERVAL then return end
    bar.timerElapsed = 0
    local manual, duration = bar.manual, bar.durationObject
    if manual then
        bar.timeText:SetFormattedText("%.1f", math.max(0, manual.finish - GetTime()))
    elseif duration then
        local ok = pcall(function() bar.timeText:SetFormattedText("%.1f", duration:GetRemainingDuration()) end)
        if not ok then bar.timeText:SetText("") end
    else
        bar.timeText:SetText("")
        return
    end
    bar.timeText:Show()
end

local TINT_INTERVAL = 0.1   -- l'interruption du joueur peut revenir pendant l'incantation

function Elements.CastOnUpdate(bar, elapsed)
    if bar.holdTime > 0 then
        bar.holdTime = bar.holdTime - elapsed
        bar.flash:SetAlpha(math.max(0, bar.holdTime / INTERRUPT_HOLD) * 0.8)
        if bar.holdTime <= 0 then bar.flash:Hide() bar:Hide() end
        return
    end
    local owner = bar.owner
    if owner and owner.global and owner.global.interruptReady and owner.unit ~= "player" then
        bar.tintElapsed = (bar.tintElapsed or 0) + elapsed
        if bar.tintElapsed >= TINT_INTERVAL then
            bar.tintElapsed = 0
            Elements.UpdateCastColor(owner)
        end
    end
    local manual = bar.manual
    Elements.UpdateCastTimer(bar, elapsed)
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
    -- Verrouillage : lu par l'événement, valeur éventuellement secrète, jamais comparée.
    if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        local bar = frame.castbar
        if bar:IsShown() then
            bar.notInterruptible = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
            Elements.UpdateCastColor(frame)
            return true
        end
    end
    if CAST_START[event] then Elements.StartCast(frame) return true end
    if CAST_STOP[event] then
        -- Le STOP qui suit une interruption ne coupe pas la tenue rouge.
        if frame.castbar.holdTime > 0 then return true end
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
    if container.size then button:SetSize(container.size, container.size) end
    container.buttons[index] = button
    return button
end

--- Crée le conteneur d'auras si l'unité en veut. `frame.auras` reste un cadre simple, ancré par
-- les modules ; s'y ajoute le conteneur du moteur quand le client l'offre (`engine`) : le moteur
-- lit et affiche les auras, en combat compris, où l'addon ne peut plus les lire. Les boutons
-- maison servent alors seulement à l'aperçu.
function Elements.BuildAuras(frame)
    if not frame.cfg.auras or frame.auras then return end
    frame.auras = ManualContainer(frame)
    local engine = not frame.isPreview and NS.CreateAuraContainer(frame.auras)   -- aperçu : jamais d'unité
    if engine then frame.auras.engine, frame.auras.native = engine, true end
end

--- Emplacement à part pour le premier contrôle (plaques) : un bouton, placé par l'appelant.
function Elements.BuildCrowdControlSlot(frame)
    if frame.ccSlot then return frame.ccSlot end
    frame.ccSlot = ManualContainer(frame)
    ManualButton(frame.ccSlot, 1):SetAllPoints(frame.ccSlot)
    return frame.ccSlot
end

function Elements.LayoutAuras(frame)
    local container = frame.auras
    if not container then return end
    local cfg = frame.cfg
    local width = S(cfg.width or 200)
    local gap = S(4)
    container:ClearAllPoints()
    if cfg.aurasInside then
        -- Cadres de groupe : dans la vie, en bas à droite, rangées vers la gauche puis le haut.
        width = width - S(6) - ((cfg.portrait and cfg.portraitInside) and S(cfg.height or 40) or 0)
        container:SetPoint("BOTTOMRIGHT", frame.health, "BOTTOMRIGHT", -S(2), S(2))
        container:SetFrameLevel(frame.overlay:GetFrameLevel() + 1)
    elseif cfg.aurasAbove then
        -- Plaque : nom et niveau au-dessus de la barre, les auras passent au-dessus d'eux.
        container:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, gap + (cfg.plate and S(14) or 0) + ComboAboveSpace(cfg))
    else
        container:SetPoint("TOPLEFT", frame.aurasAnchor or frame, "BOTTOMLEFT", 0, -gap)
    end
    local size = S(cfg.auraSize or 22)
    local spacing = S(2)
    local perRow = math.max(1, math.floor((width + spacing) / (size + spacing)))
    container.step, container.perRow, container.above = size + spacing, perRow, cfg.aurasAbove
    container.inside, container.size = cfg.aurasInside, size
    container:SetSize(width, (size + spacing) * math.ceil(MAX_AURAS / perRow))
    -- Boutons maison créés à la demande (aperçu, client sans moteur) : seuls les existants sont retaillés.
    for _, button in ipairs(container.buttons) do button:SetSize(size, size) end
    -- Sans auras (plaque alliée), rien à configurer : la signature reste celle des plaques hostiles.
    if container.engine and cfg.auras then Elements.ConfigureAuraEngine(frame, size, spacing, perRow) end
    Elements.LayoutBuffAuras(frame, width, size, spacing, perRow)
end

local ENGINE_GROUPS = { "listed", "crowdControl", "debuffs", "buffs" }
-- Groupes de débuffs cumulables (cadres de groupe), dans l'ordre de la chaîne de négations : jeton
-- ajouté au filtre, filtres candidats du groupe, puis ce que les groupes suivants nient.
local DEBUFF_GROUPS = { "control", "boss", "dispellable", "nonPlayer", "duration" }
Elements.DEBUFF_GROUPS = DEBUFF_GROUPS
local DEBUFF_GROUP_SPECS = {
    control = { token = "|CROWD_CONTROL", negate = "|!CROWD_CONTROL" },
    boss = { candidates = { isBossAura = true }, negateCandidates = { isBossAura = false } },
    dispellable = { token = "|RAID", negate = "|!RAID" },
    nonPlayer = { candidates = { isFromPlayerOrPlayerPet = false }, negateCandidates = { isFromPlayerOrPlayerPet = true } },
    duration = { candidates = { maxDuration = 31536000 } },   -- le moteur écarte les permanents (durée 0)
}
local VALID_POINT = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
                      BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

--- Réglages de texte et de lueur des auras (globaux d'UnitFrames, ou du profil des cadres de groupe).
-- nil sur les plaques : boutons du moteur tels quels.
local function AuraStyle(frame, buffs)
    local global = frame.global
    if not (global and global.auraDuration) then return nil end
    -- Annuler au clic droit : buffs du cadre du joueur seulement.
    local cancel
    if buffs and frame.unit == "player" then cancel = global.auraCancel == true end
    return { cancel = cancel, count = global.auraCountShow ~= false, countSize = global.auraCountSize, countPoint = global.auraCountPoint,
             duration = global.auraDuration, durationSize = global.auraDurationSize,
             durationPoint = global.auraDurationPoint,
             countOffsetX = global.auraCountOffsetX, countOffsetY = global.auraCountOffsetY,
             durationOffsetX = global.auraDurationOffsetX, durationOffsetY = global.auraDurationOffsetY, stealable = global.auraStealGlow == true,
             border = global.auraBorder ~= false, borderSize = global.auraBorderSize }
end

local function StyleSignature(style)
    if not style then return "" end
    return table.concat({ tostring(style.cancel), tostring(style.count), tostring(style.countSize), tostring(style.countPoint),
        tostring(style.duration), tostring(style.durationSize), tostring(style.durationPoint),
        tostring(style.countOffsetX), tostring(style.countOffsetY), tostring(style.durationOffsetX),
        tostring(style.durationOffsetY), tostring(style.stealable), tostring(style.border), tostring(style.borderSize) }, ",")
end

--- Réapplique `style` aux boutons déjà créés des groupes `keys` du conteneur du moteur.
local function RestyleAuraButtons(engine, keys, style)
    if not style then return end
    for _, key in ipairs(keys) do
        for _, button in ipairs(NS.AuraGroupButtons(engine, key)) do NS.StyleAuraButton(button, style) end
    end
end

local function GroupSignature(groups)
    if not groups then return "" end
    local parts = {}
    for _, key in ipairs(DEBUFF_GROUPS) do
        local group = groups[key] or {}
        parts[#parts + 1] = table.concat({ tostring(group.enabled), tostring(group.point), tostring(group.size), tostring(group.max) }, ",")
    end
    return table.concat(parts, ";")
end
local CC_HIGHLIGHT = { r = 0.95, g = 0.95, b = 0.32, a = 1 }   -- couleur des lueurs (Core/Glow)

--- Ensemble d'identifiants d'une liste du profil, nil si vide.
local function SpellSet(text)
    local set = NS.ParseSpellList(text)
    return next(set) and set or nil
end

local function Union(a, b)
    if not (a and b) then return a or b end
    local set = {}
    for id in pairs(a) do set[id] = true end
    for id in pairs(b) do set[id] = true end
    return set
end

-- Débuffs de bruit : Rassasié et équivalents (RaidCooldowns.SATED), Longanimité (25771, vérifié dans
-- Blizzard_FrameXMLUtil/AuraUtil.lua), Âme affaiblie (6788, non vérifiable dans le source Forever).
local NOISE_EXTRA = { 25771, 6788 }
local FORBEARANCE = 25771   -- prioritaire pour un paladin (AuraUtil.lua:5) : gardé pour lui
local noiseSet
--- Ensemble des identifiants de bruit (le moteur écarte par identifiant, sans lire de valeur secrète).
function Elements.NoiseDebuffSet()
    if not noiseSet then
        noiseSet = {}
        local raidCooldowns = NS.Modules:Get("raidcooldowns")
        for _, id in ipairs(raidCooldowns and raidCooldowns.SATED or {}) do noiseSet[id] = true end
        local _, classFile = UnitClass("player")
        for _, id in ipairs(NOISE_EXTRA) do
            if not (id == FORBEARANCE and classFile == "PALADIN") then noiseSet[id] = true end
        end
    end
    return noiseSet
end

--- Groupes du conteneur du moteur d'après le réglage du cadre : liste blanche (toujours montrée),
-- contrôles (liseré de lueur), débuffs, puis buffs sur une ligne neuve. Emplacement de contrôle
-- (plaques) : les contrôles y vont, pas dans la grille. Liste noire : jamais montrée. Le moteur
-- n'applique les listes que là où il le permet (buffs d'alliés, sorts jamais secrets).
-- ponytail: auraMax borne chaque groupe, pas leur total ; le premier contrôle seul va dans l'emplacement.
function Elements.ConfigureAuraEngine(frame, size, spacing, perRow)
    local container, cfg, lists = frame.auras, frame.cfg, NS.db.auraLists
    local engine = container.engine
    -- Plaques : leurs propres listes ; le reste (priorité, lueur des contrôles) reste commun.
    local own = cfg.plate and cfg.auraLists or lists
    local whitelistText, blacklistText = own.whitelist or "", own.blacklist or ""
    -- Plaques : reposées à chaque apparition ; réglage inchangé, rien à redemander au moteur.
    local style, buffStyle = AuraStyle(frame), AuraStyle(frame, true)
    container.auraStyle, container.buffStyle = style, buffStyle
    local split = cfg.auraSplit and not cfg.aurasInside
    local signature = table.concat({ size, spacing, perRow, tostring(cfg.aurasInside), tostring(cfg.aurasAbove),
        tostring(split), StyleSignature(style), StyleSignature(buffStyle),
        tostring(cfg.auraMax), tostring(cfg.auraFilter), tostring(cfg.debuffsOnly), tostring(cfg.hideNoiseDebuffs), tostring(cfg.ccSlot and frame.ccSlot ~= nil),
        whitelistText, blacklistText, tostring(cfg.whitelistAnyCaster), tostring(lists.prioritize), tostring(lists.ccGlow),
        GroupSignature(cfg.debuffGroups) }, "\31")
    if container.engineSignature == signature then return end
    local anchor, horizontal, vertical = "TOPLEFT", "RIGHT", "DOWN"
    if cfg.aurasInside then anchor, horizontal, vertical = "BOTTOMRIGHT", "LEFT", "UP"
    elseif cfg.aurasAbove then anchor, vertical = "BOTTOMLEFT", "UP" end
    engine:ClearAllPoints()
    engine:SetPoint(anchor, container, anchor, 0, 0)
    NS.SetAuraContainerFlow(engine, anchor, horizontal, vertical, perRow * (size + spacing) - spacing + 0.5)
    container.engineSize = size
    local resized = true   -- taille refusée (auras secrètes) : signature non retenue, on réessaiera
    for _, key in ipairs(ENGINE_GROUPS) do
        for _, button in ipairs(NS.AuraGroupButtons(engine, key)) do resized = pcall(button.SetSize, button, size, size) and resized end
    end
    local groups = cfg.debuffGroups
    container.groupSizes = container.groupSizes or {}
    for _, key in ipairs(groups and DEBUFF_GROUPS or {}) do
        local groupSize = S((groups[key] or {}).size or cfg.auraSize or 22)
        container.groupSizes[key] = groupSize
        for _, button in ipairs(NS.AuraGroupButtons(engine, key)) do
            resized = pcall(button.SetSize, button, groupSize, groupSize) and resized
        end
    end
    container.engineSignature = resized and signature or nil
    RestyleAuraButtons(engine, { "listed", "crowdControl", "debuffs" }, style)
    RestyleAuraButtons(engine, { "buffs" }, buffStyle)
    local initBuffs = container.engineInitBuffs or function(button)
        NS.InitAuraButton(button, { size = container.engineSize, dispel = true, style = container.buffStyle })
    end
    container.engineInitBuffs = initBuffs
    local init = container.engineInit or function(button)
        NS.InitAuraButton(button, { size = container.engineSize, dispel = true, style = container.auraStyle })
    end
    local initCrowdControl = container.engineInitCrowdControl or function(button)
        NS.InitAuraButton(button, { size = container.engineSize, dispel = true, highlight = CC_HIGHLIGHT,
            style = container.auraStyle })
    end
    container.engineInit, container.engineInitCrowdControl = init, initCrowdControl

    local max = math.min(MAX_AURAS, cfg.auraMax or MAX_AURAS)
    local mode = cfg.auraFilter or "all"
    local blacklist = SpellSet(blacklistText)
    if cfg.hideNoiseDebuffs then blacklist = Union(blacklist, Elements.NoiseDebuffSet()) end
    local whitelist = mode ~= "all" and SpellSet(whitelistText) or nil
    local slot = cfg.ccSlot and frame.ccSlot or nil
    local crowdControlGroup = not slot and lists.ccGlow ~= "none"
    -- Liste blanche d'une plaque : tes sorts seulement, sauf « de tout lanceur ». Dans ce cas, l'aura
    -- listée d'un autre lanceur reste candidate des groupes suivants.
    local playerOnly = cfg.plate and not cfg.whitelistAnyCaster
    local listedFilter = playerOnly and "HARMFUL|PLAYER" or "HARMFUL"
    local debuffCandidates = NS.AuraEngineCandidates(mode, playerOnly and blacklist or Union(blacklist, whitelist))
    local notCrowdControl = (slot or crowdControlGroup) and "|!CROWD_CONTROL" or ""
    NS.SetAuraGroup(engine, "listed", { filter = listedFilter, max = whitelist and max or 0, index = 1, spacing = spacing,
        size = size, candidates = { includeSpellIDs = whitelist }, init = init })
    NS.SetAuraGroup(engine, "crowdControl", { filter = NS.AuraEngineFilter("HARMFUL|CROWD_CONTROL", mode),
        max = (crowdControlGroup and not groups) and max or 0, index = 2, spacing = spacing, size = size,
        candidates = debuffCandidates, init = initCrowdControl })
    NS.SetAuraGroup(engine, "debuffs", { filter = NS.AuraEngineFilter("HARMFUL", mode) .. notCrowdControl, max = groups and 0 or max,
        index = 3, spacing = spacing, size = size, prioritize = lists.prioritize or mode == "important",
        candidates = debuffCandidates, init = init })
    NS.SetAuraGroup(engine, "buffs", { filter = "HELPFUL", max = (cfg.debuffsOnly or split) and 0 or max, index = 4,
        newLine = true, spacing = spacing, size = size, candidates = { excludeSpellIDs = blacklist }, init = initBuffs })
    if groups then Elements.ConfigureDebuffGroups(frame, groups, mode, debuffCandidates.excludeSpellIDs, spacing) end
    if slot or engine.declared.ccSlot then
        NS.SetAuraSlot(engine, "ccSlot", NS.AuraEngineFilter("HARMFUL|CROWD_CONTROL", mode), slot ~= nil, function(button)
            NS.InitAuraButton(button, { dispel = true, highlight = lists.ccGlow ~= "none" and CC_HIGHLIGHT or nil })
            pcall(button.SetAllPoints, button, frame.ccSlot)
        end)
    end
    pcall(engine.UpdateAllAuras, engine)
end

--- Second conteneur du moteur quand les buffs ont leur emplacement (`cfg.auraSplit`) : du côté
-- opposé aux débuffs, au-dessus du cadre ou sous lui. Le premier conteneur ne montre alors que les
-- débuffs. Sans le moteur (aperçu, ancien client), rien : les buffs restent avec les débuffs.
function Elements.LayoutBuffAuras(frame, width, size, spacing, perRow)
    local cfg, container = frame.cfg, frame.auras
    local host = frame.buffAuras
    local wanted = container and container.engine and cfg.auras and cfg.auraSplit and not cfg.aurasInside
        and not cfg.debuffsOnly
    if not wanted then
        if host then host.engine:Hide() end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, frame)
        host.engine = NS.CreateAuraContainer(host)
        if not host.engine then return end
        frame.buffAuras = host
    end
    local engine, gap = host.engine, S(4)
    local above = not cfg.aurasAbove   -- côté opposé aux débuffs
    local max = math.min(MAX_AURAS, cfg.auraMax or MAX_AURAS)
    host:ClearAllPoints()
    local anchor, vertical = "TOPLEFT", "DOWN"
    if above then
        anchor, vertical = "BOTTOMLEFT", "UP"
        host:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, gap)
    else
        host:SetPoint("TOPLEFT", frame.aurasAnchor or frame, "BOTTOMLEFT", 0, -gap)
    end
    host:SetSize(width, (size + spacing) * math.ceil(max / perRow))
    host:SetFrameLevel(container:GetFrameLevel())
    local style = AuraStyle(frame, true)
    local lists = NS.db.auraLists
    local signature = table.concat({ size, spacing, perRow, max, tostring(above), StyleSignature(style),
        lists.blacklist or "" }, "\31")
    host.auraStyle, host.engineSize = style, size
    engine:Show()
    if host.engineSignature ~= signature then
        engine:ClearAllPoints()
        engine:SetPoint(anchor, host, anchor, 0, 0)
        NS.SetAuraContainerFlow(engine, anchor, "RIGHT", vertical, perRow * (size + spacing) - spacing + 0.5)
        local resized = true
        for _, button in ipairs(NS.AuraGroupButtons(engine, "buffs")) do
            resized = pcall(button.SetSize, button, size, size) and resized
        end
        host.engineSignature = resized and signature or nil
        RestyleAuraButtons(engine, { "buffs" }, style)
        host.engineInit = host.engineInit or function(button)
            NS.InitAuraButton(button, { size = host.engineSize, dispel = true, style = host.auraStyle })
        end
        NS.SetAuraGroup(engine, "buffs", { filter = "HELPFUL", max = max, index = 1, spacing = spacing, size = size,
            candidates = { excludeSpellIDs = SpellSet(lists.blacklist or "") }, init = host.engineInit })
        pcall(engine.UpdateAllAuras, engine)
    end
end

--- Clics d'annulation des buffs du joueur, coupés en combat (appelé à chaque changement de combat).
-- `inCombat` vient de l'événement : InCombatLockdown() est encore faux pendant PLAYER_REGEN_DISABLED.
function Elements.RefreshAuraCancel(frame, inCombat)
    local style = AuraStyle(frame, true)
    if not (style and style.cancel == true) then return end
    if inCombat == nil then inCombat = NS.InCombat() end
    for _, container in ipairs({ frame.auras or false, frame.buffAuras or false }) do
        if container and container.engine then
            for _, button in ipairs(NS.AuraGroupButtons(container.engine, "buffs")) do
                pcall(button.SetMouseClickEnabled, button, not inCombat)
            end
        end
    end
end

--- Groupes de débuffs cochés (cadres de groupe) : un groupe du moteur par case, chacun niant les
-- précédents pour qu'une aura soit rendue une fois. Dans le flux des auras, ou, ancré ailleurs, un
-- emplacement d'une aura sur un cadre d'ancrage à nous. « mine » : tes débuffs seulement.
function Elements.ConfigureDebuffGroups(frame, groups, mode, exclude, spacing)
    local container = frame.auras
    local engine, sizes = container.engine, container.groupSizes
    local highlight = NS.db.auraLists.ccGlow ~= "none" and CC_HIGHLIGHT or nil
    local own = mode == "mine" and "mine" or "all"
    local negate, negated = "", {}
    frame.debuffAnchors = frame.debuffAnchors or {}
    for order, key in ipairs(DEBUFF_GROUPS) do
        local group, spec = groups[key] or {}, DEBUFF_GROUP_SPECS[key]
        local filter = NS.AuraEngineFilter("HARMFUL" .. (spec.token or "") .. negate, own)
        local candidates = { excludeSpellIDs = exclude }
        for field, value in pairs(negated) do candidates[field] = value end
        for field, value in pairs(spec.candidates or {}) do candidates[field] = value end
        local function init(button)
            NS.InitAuraButton(button, { size = sizes[key], dispel = true, highlight = key == "control" and highlight or nil,
                style = container.auraStyle })
        end
        local point = VALID_POINT[group.point] and group.point or nil
        local enabled = group.enabled == true
        NS.SetAuraGroup(engine, key, { filter = filter, max = (enabled and not point) and math.min(MAX_AURAS, group.max or 3) or 0,
            index = 3 + order / 10, spacing = spacing, size = sizes[key], prioritize = NS.db.auraLists.prioritize,
            candidates = candidates, init = init })
        local anchor = frame.debuffAnchors[key]
        if point and not anchor then
            anchor = CreateFrame("Frame", nil, frame.overlay or frame)
            anchor:SetFrameLevel((frame.overlay or frame):GetFrameLevel() + 3)
            frame.debuffAnchors[key] = anchor
        end
        if anchor then
            anchor:SetSize(sizes[key], sizes[key])
            anchor:ClearAllPoints()
            anchor:SetPoint(point or "CENTER", frame.health, point or "CENTER", 0, 0)
            NS.SetAuraSlot(engine, key .. "Slot", filter, enabled and point ~= nil, function(button)
                init(button)
                pcall(button.ClearAllPoints, button)
                pcall(button.SetAllPoints, button, anchor)
            end, candidates)
        end
        -- Boutons déjà créés : texte des auras du réglage (la signature de ConfigureAuraEngine le porte).
        RestyleAuraButtons(engine, { key }, container.auraStyle)
        if type(engine.declared[key .. "Slot"]) == "table" then NS.StyleAuraButton(engine.declared[key .. "Slot"], container.auraStyle) end
        if enabled then
            negate = negate .. (spec.negate or "")
            for field, value in pairs(spec.negateCandidates or {}) do negated[field] = value end
        end
    end
end

--- Pose le bouton en (colonne, ligne) : ligne 0 contre le cadre, les suivantes s'en éloignent.
local function PlaceManualButton(container, button, col, row)
    local step = container.step
    button:ClearAllPoints()
    if container.inside then
        button:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -col * step, row * step)
    elseif container.above then
        button:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", col * step, row * step)
    else
        button:SetPoint("TOPLEFT", container, "TOPLEFT", col * step, -row * step)
    end
end

--- Rang d'un débuff quand ils sont priorisés : boss, puis contrôle, puis dissipable, puis le reste.
-- Un champ secret ne se compare pas : le débuff reste au rang commun.
local function DebuffRank(isBoss, cc, dispel)
    if not isSecret(isBoss) and isBoss == true then return 1 end
    if cc then return 2 end
    if NS.PlayerCanDispel(dispel) == true then return 3 end
    return 4
end

local function ByRank(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.index < b.index
end

--- Auras de `kind` qui passent le filtre, dans `list` (entrées réutilisées) ; rend leur nombre.
local function CollectAuras(list, unit, kind, filter, crowdControl, prioritize)
    local count = 0
    for index = 1, MAX_AURA_INDEX do
        local icon, duration, expiration, stacks, dispel, isBoss, spellId, isMine, instance = NS.GetAura(unit, index, kind)
        if not isSecret(icon) and icon == nil then break end
        if NS.AuraPasses(filter, spellId, dispel, isBoss, isMine) then
            count = count + 1
            local entry = list[count] or {}
            list[count] = entry
            entry.index, entry.icon, entry.duration, entry.expiration, entry.stacks, entry.dispel =
                index, icon, duration, expiration, stacks, dispel
            entry.cc = crowdControl ~= nil and instance ~= nil and not isSecret(instance) and crowdControl[instance] == true
            entry.rank = prioritize and DebuffRank(isBoss, entry.cc, dispel) or 0
        end
    end
    for i = count + 1, #list do list[i] = nil end
    if prioritize then table.sort(list, ByRank) end
    return count
end

local function ShowAura(button, entry, harmful, ccGlow, bordered)
    button.icon:SetTexture(entry.icon)
    local d, e = Known(entry.duration), Known(entry.expiration)
    if d and e and d > 0 then button.cooldown:SetCooldown(e - d, d) else button.cooldown:Clear() end
    local n = Known(entry.stacks)
    button.count:SetText(n and n > 1 and tostring(n) or "")
    local dispel = entry.dispel
    local color = harmful and not isSecret(dispel) and dispel and _G.DebuffTypeColor and DebuffTypeColor[dispel] or nil
    if color then
        for _, edge in pairs(button.border) do NS.SetSolidColor(edge, color.r, color.g, color.b, 1) end
    else
        local c = NS.db.theme.border
        for _, edge in pairs(button.border) do NS.SetSolidColor(edge, c.r, c.g, c.b, c.a or 1) end
    end
    for _, edge in pairs(button.border) do edge:SetShown(bordered ~= false) end   -- réglage « bordure des icônes d'aura »
    NS.Glow.Set(button, entry.cc and ccGlow ~= "none", ccGlow)
    button:Show()
end

--- `refresh` : tout relire (changement de cible, de plaque, entrée en jeu). Avec le conteneur du
-- moteur, UNIT_AURA ne demande rien : le moteur l'écoute lui-même.
function Elements.UpdateAuras(frame, refresh)
    local container = frame.auras
    if not container then return end
    local slot = frame.cfg.ccSlot and frame.ccSlot
    if frame.ccSlot then frame.ccSlot.buttons[1]:Hide() end
    if not frame.cfg.auras then
        container:Hide()
        if frame.buffAuras then frame.buffAuras:Hide() end
        return
    end
    container:Show()
    if frame.buffAuras then frame.buffAuras:Show() end
    if container.engine then
        local buffEngine = frame.buffAuras and frame.buffAuras.engine
        if buffEngine and buffEngine:IsShown() then NS.SetAuraContainerUnit(buffEngine, frame.unit, refresh) end
        if container.previewing then   -- sortie de l'aperçu : ses boutons manuels, une seule fois
            container.previewing = nil
            for _, button in ipairs(container.buttons) do button:Hide() end
        end
        container.engine:Show()
        NS.SetAuraContainerUnit(container.engine, frame.unit, refresh)
        return
    end
    local unit = frame.unit
    local lists = NS.db.auraLists
    local perRow = container.perRow or MAX_AURAS
    container.list = container.list or {}
    local shown, cell = 0, 0   -- cell : position dans la grille (les buffs commencent une ligne neuve)
    local max = math.min(MAX_AURAS, frame.cfg.auraMax or MAX_AURAS)
    -- Débuffs (filtre du cadre, priorisés au besoin), puis buffs, sauf cfg.debuffsOnly. Emplacement
    -- de contrôle (plaques) : le premier contrôle y va, hors de la grille.
    for _, kind in ipairs(frame.cfg.debuffsOnly and AURA_KINDS_DEBUFFS or AURA_KINDS_ALL) do
        if kind == "HELPFUL" and cell % perRow ~= 0 then cell = cell + perRow - cell % perRow end
        local harmful = kind == "HARMFUL"
        local crowdControl = harmful and (slot or lists.prioritize or lists.ccGlow ~= "none")
            and NS.CrowdControlAuras(unit) or nil
        local count = CollectAuras(container.list, unit, kind, harmful and frame.cfg.auraFilter or "all",
            crowdControl, harmful and lists.prioritize)
        for i = 1, count do
            local entry = container.list[i]
            if slot and harmful and entry.cc then
                ShowAura(slot.buttons[1], entry, true, lists.ccGlow, (frame.global or {}).auraBorder)
                slot = nil
            elseif shown < max then
                shown, cell = shown + 1, cell + 1
                local button = ManualButton(container, shown)
                PlaceManualButton(container, button, (cell - 1) % perRow, math.floor((cell - 1) / perRow))
                ShowAura(button, entry, harmful, lists.ccGlow, (frame.global or {}).auraBorder)
            end
        end
    end
    for i = shown + 1, #container.buttons do
        NS.Glow.Hide(container.buttons[i])
        container.buttons[i]:Hide()
    end
end

--- Aperçu : débuffs fictifs `entries` ({ icon, dispel }) posés comme de vrais, sans unité.
function Elements.PreviewAuras(frame, entries)
    local container = frame.auras
    if not container then return end
    if not frame.cfg.auras then container:Hide() return end
    container:Show()
    container.previewing = true
    if container.engine then container.engine:Hide() end
    local perRow = container.perRow or MAX_AURAS
    local max = math.min(MAX_AURAS, frame.cfg.auraMax or MAX_AURAS)
    local shown = 0
    for i = 1, max do
        local entry = entries[i]
        if not entry then break end
        local button = ManualButton(container, i)
        PlaceManualButton(container, button, (i - 1) % perRow, math.floor((i - 1) / perRow))
        ShowAura(button, entry, true, "none", (frame.global or {}).auraBorder)
        shown = i
    end
    for i = shown + 1, #container.buttons do container.buttons[i]:Hide() end
end

--------------------------------------------------------------------------------
-- Tout
--------------------------------------------------------------------------------

--- Rafraîchit chaque élément (changement d'unité, entrée en jeu, réglage).
function Elements.UpdateAll(frame)
    Elements.UpdateHealth(frame)
    Elements.UpdateHealPrediction(frame)
    Elements.UpdatePower(frame)
    Elements.UpdateName(frame, true)
    Elements.UpdateLevel(frame, true)
    Elements.UpdateIndicators(frame)
    Elements.UpdateRaidIcon(frame)
    Elements.UpdateCombo(frame)
    Elements.StartCast(frame)
    Elements.UpdateAuras(frame, true)
    Elements.UpdatePortrait(frame)
    Elements.UpdateThreat(frame)
    Elements.UpdateHappiness(frame)
    Elements.UpdateHighlight(frame)
end

--- Surbrillance : cible actuelle (cfg.targetHighlight) ou curseur dessus (cfg.hoverHighlight, frame.hovered).
function Elements.UpdateHighlight(frame)
    local cfg = frame.cfg
    if not (cfg.targetHighlight or cfg.hoverHighlight or frame.highlight) then return end
    local holder = frame.highlight
    if not holder then   -- créée à la première utilisation : plaques et cadres de groupe n'en paient pas le coût
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holder:SetFrameLevel(frame.overlay:GetFrameLevel() + 2)
        holder.edges = Media:CreateBorder(holder, { r = 1, g = 1, b = 1 })
        holder:Hide()
        frame.highlight = holder
    end
    local on = cfg.hoverHighlight and frame.hovered and true or false
    if not on and cfg.targetHighlight and frame.unit ~= "target" and _G.UnitIsUnit then
        on = Known(UnitIsUnit(frame.unit, "target")) and true or false
    end
    local c = (frame.global or {}).highlightColor
    if on and c then
        for _, edge in pairs(holder.edges) do NS.SetSolidColor(edge, c.r, c.g, c.b, c.a or 1) end
    end
    holder:SetShown(on)
end

--- Réaction ou marquage JcJ changé : couleur de vie et écusson.
function Elements.UpdateFaction(frame)
    frame.reactionGUID = nil   -- réaction à relire
    Elements.UpdateHealth(frame)
    Elements.UpdatePvP(frame)
end

-- Événement d'unité -> mise à jour ciblée.
Elements.UNIT_EVENTS = {
    UNIT_HEALTH = "UpdateHealthAndPrediction", UNIT_MAXHEALTH = "UpdateHealthAndPrediction",
    UNIT_FACTION = "UpdateFaction",
    UNIT_THREAT_SITUATION_UPDATE = "UpdateThreat", UNIT_THREAT_LIST_UPDATE = "UpdateThreat", UNIT_HAPPINESS = "UpdateHappiness",
    UNIT_CLASSIFICATION_CHANGED = "UpdateClassification",
    UNIT_CONNECTION = "UpdateHealthAndPrediction",
    UNIT_MAXPOWER = "UpdatePower", UNIT_DISPLAYPOWER = "UpdatePower", UNIT_POWER_FREQUENT = "UpdatePower",
    UNIT_NAME_UPDATE = "UpdateName", UNIT_LEVEL = "UpdateLevel", UNIT_FLAGS = "UpdateIndicators",
    UNIT_AURA = "UpdateAuras",
    UNIT_HEAL_PREDICTION = "UpdateHealPrediction", UNIT_ABSORB_AMOUNT_CHANGED = "UpdateHealPrediction",
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED = "UpdateHealPrediction",
    UNIT_PORTRAIT_UPDATE = "UpdatePortrait", UNIT_MODEL_CHANGED = "UpdatePortrait",
}

--- Route un événement reçu par le cadre. Retourne true s'il a été traité.
function Elements.OnEvent(frame, event)
    local method = Elements.UNIT_EVENTS[event]
    if method then
        Elements[method](frame)
        if event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
            Elements.UpdateCombo(frame)
        end
        return true
    end
    return Elements.HandleCast(frame, event)
end
