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

-- Couleurs de vie par réaction : défauts des cadres d'unité, repli quand AeonUI_UnitFrames est désactivé.
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

function Elements.HealthColor(unit, classColor)
    if classColor and not NS.IsSecretUnit(unit) and (SurelyPlayer(unit) or Known(UnitIsPlayer(unit))) then
        local _, classFile = UnitClass(unit)
        classFile = Known(classFile)
        if classFile then return NS.ClassColor(classFile) end
    end
    local unitFrames = NS.db.modules.unitframes
    local colors = unitFrames and unitFrames.reactionColors or Elements.REACTION_COLORS
    if _G.UnitIsTapDenied and Known(UnitIsTapDenied(unit)) then
        return colors.tapped.r, colors.tapped.g, colors.tapped.b
    end
    local reaction = _G.UnitReaction and Known(UnitReaction(unit, "player")) or nil
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
        if isSecret(percent) or percent ~= nil then return string.format("%.0f%%", percent) end
    end
    local cur, max = Known(Call(api.cur, unit, api.powerType)), Known(Call(api.max, unit, api.powerType))
    if cur and max and max > 0 then return string.format("%d%%", math.floor(cur / max * 100 + 0.5)) end
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
    Media:CreateBackdrop(castbar)
    -- L'icône a son propre cadre : sa bordure 1 px suit le thème et l'échelle toute seule.
    castbar.iconFrame = CreateFrame("Frame", nil, castbar)
    castbar.icon = castbar.iconFrame:CreateTexture(nil, "ARTWORK")
    castbar.icon:SetAllPoints(castbar.iconFrame)
    castbar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Media:CreateBackdrop(castbar.iconFrame)
    castbar.text = Media:CreateText(castbar, "OVERLAY", -1)
    castbar.text:SetJustifyH("LEFT")
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

    local icon = S(16)
    frame.combat:SetSize(icon, icon)
    Place(frame.combat, "CENTER", frame, "TOPLEFT", 0, 0)
    frame.resting:SetSize(icon, icon)
    Place(frame.resting, "CENTER", frame, "TOPLEFT", 0, 0)
    frame.leader:SetSize(S(14), S(14))
    Place(frame.leader, "CENTER", frame, "TOPLEFT", S(18), 0)
    frame.raidIcon:SetSize(S(18), S(18))
    Place(frame.raidIcon, "CENTER", frame, "TOP", 0, 0)
    frame.classification:SetSize(icon, icon)
    Place(frame.classification, "CENTER", frame, "TOPRIGHT", 0, 0)
    frame.pvp:SetSize(S(20), S(20))
    Place(frame.pvp, "CENTER", frame, "BOTTOMLEFT", 0, 0)
    frame.happiness:SetSize(height, height)
    Place(frame.happiness, "LEFT", frame, "RIGHT", S(2), 0)

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
    -- Détachée : hors du cadre, qui peut être caché par sa visibilité (pilote d'état).
    castbar:SetParent(castbar.detached and UIParent or frame)
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
            line = bar:CreateTexture(nil, "OVERLAY")
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
    Elements.SetUnitText(bar.text, frame.unit, "health",
        Elements.TextFormat(frame.cfg and frame.cfg.healthFormat, global and global.healthText or "current"))
    if bar.centerText then Elements.SetUnitText(bar.centerText, frame.unit, "health", frame.cfg and frame.cfg.centerFormat) end
end

function Elements.UpdateHealth(frame)
    local unit = frame.unit
    local bar = frame.health
    bar:SetMinMaxValues(0, UnitHealthMax(unit))
    bar:SetValue(UnitHealth(unit))
    local global = frame.global
    local applied, r, g, b = false
    if global and global.healthGradient then applied, r, g, b = NS.HealthGradient(unit) end
    if applied then Media:SetHealthColor(bar, r, g, b)   -- r, g, b peut-être secrets : jamais testés
    else
        r, g, b = Elements.HealthColor(unit, global and global.classColor)
        if global and (global.lowHealth or 0) > 0 then
            r, g, b = Elements.BandColor(unit, "health", Elements.Bands(global.lowHealth, global.lowHealthColor), r, g, b)
        end
        Media:SetHealthColor(bar, r, g, b)
    end
    Elements.UpdateHealthTexts(frame)
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
    Elements.UpdateHealthTexts(frame)
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
    Elements.UpdateHealthTexts(frame)
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
    if not frame.comboAllowed or frame.unit ~= "player" then bar:Hide() return end
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
    -- Cible du sort (cadres autres que le joueur) : son nom après celui du sort, peut-être secret.
    local global = frame.global
    local targetName = global and global.castTarget and unit ~= "player" and UnitName(unit .. "target")
    if isSecret(targetName) or targetName then
        bar.text:SetFormattedText("%s > %s", text, targetName)
    else
        bar.text:SetText(text)
    end
    if isSecret(texture) or texture ~= nil then bar.icon:SetTexture(texture) else bar.icon:SetTexture(QUESTION_ICON) end
    bar.notInterruptible = notInterruptible
    bar.spellID = spellID
    Elements.UpdateCastColor(frame)

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
    local locked = bar.notInterruptible
    if not isSecret(locked) and locked == nil then locked = false end
    local u = UNINTERRUPTIBLE
    bar:SetStatusBarColor(NS.ColorFromBoolean(locked, u[1], u[2], u[3], r, g, b))
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
        container:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, gap + (cfg.plate and S(14) or 0))
    else
        container:SetPoint("TOPLEFT", frame.aurasAnchor or frame, "BOTTOMLEFT", 0, -gap)
    end
    local size = S(cfg.auraSize or 22)
    local spacing = S(2)
    local perRow = math.max(1, math.floor((width + spacing) / (size + spacing)))
    container.step, container.perRow, container.above = size + spacing, perRow, cfg.aurasAbove
    container.inside = cfg.aurasInside
    container:SetSize(width, (size + spacing) * math.ceil(MAX_AURAS / perRow))
    for i = 1, MAX_AURAS do ManualButton(container, i):SetSize(size, size) end
    -- Sans auras (plaque alliée), rien à configurer : la signature reste celle des plaques hostiles.
    if container.engine and cfg.auras then Elements.ConfigureAuraEngine(frame, size, spacing, perRow) end
end

local ENGINE_GROUPS = { "listed", "crowdControl", "debuffs", "buffs" }
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

--- Groupes du conteneur du moteur d'après le réglage du cadre : liste blanche (toujours montrée),
-- contrôles (liseré de lueur), débuffs, puis buffs sur une ligne neuve. Emplacement de contrôle
-- (plaques) : les contrôles y vont, pas dans la grille. Liste noire : jamais montrée. Le moteur
-- n'applique les listes que là où il le permet (buffs d'alliés, sorts jamais secrets).
-- ponytail: auraMax borne chaque groupe, pas leur total ; le premier contrôle seul va dans l'emplacement.
function Elements.ConfigureAuraEngine(frame, size, spacing, perRow)
    local container, cfg, lists = frame.auras, frame.cfg, NS.db.auraLists
    local engine = container.engine
    -- Plaques : reposées à chaque apparition ; réglage inchangé, rien à redemander au moteur.
    local signature = table.concat({ size, spacing, perRow, tostring(cfg.aurasInside), tostring(cfg.aurasAbove),
        tostring(cfg.auraMax), tostring(cfg.auraFilter), tostring(cfg.debuffsOnly), tostring(cfg.ccSlot and frame.ccSlot ~= nil),
        lists.whitelist, lists.blacklist, tostring(lists.prioritize), tostring(lists.ccGlow) }, "\31")
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
    container.engineSignature = resized and signature or nil
    local init = container.engineInit or function(button) NS.InitAuraButton(button, { size = container.engineSize, dispel = true }) end
    local initCrowdControl = container.engineInitCrowdControl or function(button)
        NS.InitAuraButton(button, { size = container.engineSize, dispel = true, highlight = CC_HIGHLIGHT })
    end
    container.engineInit, container.engineInitCrowdControl = init, initCrowdControl

    local max = math.min(MAX_AURAS, cfg.auraMax or MAX_AURAS)
    local mode = cfg.auraFilter or "all"
    local blacklist = SpellSet(lists.blacklist)
    local whitelist = mode ~= "all" and SpellSet(lists.whitelist) or nil
    local slot = cfg.ccSlot and frame.ccSlot or nil
    local crowdControlGroup = not slot and lists.ccGlow ~= "none"
    local debuffCandidates = NS.AuraEngineCandidates(mode, Union(blacklist, whitelist))
    local notCrowdControl = (slot or crowdControlGroup) and "|!CROWD_CONTROL" or ""
    NS.SetAuraGroup(engine, "listed", { filter = "HARMFUL", max = whitelist and max or 0, index = 1, spacing = spacing,
        size = size, candidates = { includeSpellIDs = whitelist }, init = init })
    NS.SetAuraGroup(engine, "crowdControl", { filter = NS.AuraEngineFilter("HARMFUL|CROWD_CONTROL", mode),
        max = crowdControlGroup and max or 0, index = 2, spacing = spacing, size = size,
        candidates = debuffCandidates, init = initCrowdControl })
    NS.SetAuraGroup(engine, "debuffs", { filter = NS.AuraEngineFilter("HARMFUL", mode) .. notCrowdControl, max = max,
        index = 3, spacing = spacing, size = size, prioritize = lists.prioritize or mode == "important",
        candidates = debuffCandidates, init = init })
    NS.SetAuraGroup(engine, "buffs", { filter = "HELPFUL", max = cfg.debuffsOnly and 0 or max, index = 4,
        newLine = true, spacing = spacing, size = size, candidates = { excludeSpellIDs = blacklist }, init = init })
    if slot or engine.declared.ccSlot then
        NS.SetAuraSlot(engine, "ccSlot", NS.AuraEngineFilter("HARMFUL|CROWD_CONTROL", mode), slot ~= nil, function(button)
            NS.InitAuraButton(button, { dispel = true, highlight = lists.ccGlow ~= "none" and CC_HIGHLIGHT or nil })
            pcall(button.SetAllPoints, button, frame.ccSlot)
        end)
    end
    pcall(engine.UpdateAllAuras, engine)
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

local function ShowAura(button, entry, harmful, ccGlow)
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
    if not frame.cfg.auras then container:Hide() return end
    container:Show()
    if container.engine then
        for _, button in ipairs(container.buttons) do button:Hide() end   -- boutons de l'aperçu
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
                ShowAura(slot.buttons[1], entry, true, lists.ccGlow)
                slot = nil
            elseif shown < max then
                shown, cell = shown + 1, cell + 1
                local button = ManualButton(container, shown)
                PlaceManualButton(container, button, (cell - 1) % perRow, math.floor((cell - 1) / perRow))
                ShowAura(button, entry, harmful, lists.ccGlow)
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
    if container.engine then container.engine:Hide() end
    local perRow = container.perRow or MAX_AURAS
    local max = math.min(MAX_AURAS, frame.cfg.auraMax or MAX_AURAS)
    for i, button in ipairs(container.buttons) do
        local entry = i <= max and entries[i]
        if entry then
            PlaceManualButton(container, button, (i - 1) % perRow, math.floor((i - 1) / perRow))
            ShowAura(button, entry, true, "none")
        else
            button:Hide()
        end
    end
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
    Elements.UpdateAuras(frame, true)
    Elements.UpdatePortrait(frame)
    Elements.UpdateThreatBorder(frame)
    Elements.UpdateHappiness(frame)
end

--- Réaction ou marquage JcJ changé : couleur de vie et écusson.
function Elements.UpdateFaction(frame)
    Elements.UpdateHealth(frame)
    Elements.UpdatePvP(frame)
end

-- Événement d'unité -> mise à jour ciblée.
Elements.UNIT_EVENTS = {
    UNIT_HEALTH = "UpdateHealth", UNIT_MAXHEALTH = "UpdateHealth", UNIT_FACTION = "UpdateFaction",
    UNIT_THREAT_SITUATION_UPDATE = "UpdateThreatBorder", UNIT_HAPPINESS = "UpdateHappiness",
    UNIT_CLASSIFICATION_CHANGED = "UpdateClassification",
    UNIT_CONNECTION = "UpdateHealth",
    UNIT_POWER_UPDATE = "UpdatePower", UNIT_MAXPOWER = "UpdatePower", UNIT_DISPLAYPOWER = "UpdatePower",
    UNIT_POWER_FREQUENT = "UpdatePower",
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
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then Elements.UpdateCombo(frame) end
        return true
    end
    return Elements.HandleCast(frame, event)
end
