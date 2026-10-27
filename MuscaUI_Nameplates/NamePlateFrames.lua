-- MuscaUI_Nameplates/NamePlateFrames.lua
-- Plaques de nom MuscaUI : sur chaque plaque Blizzard, un cadre MuscaUI (santé, nom, niveau,
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
local NS = MuscaUI
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
        glow = false, glowStyle = "classic", scale = 1, alpha = 1, hide = false,
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
    defaults = {
        enabled = false,
        width = 120, height = 10, castbarHeight = 10, auraSize = 18,
        showName = true, showLevel = true, showCastbar = true, showAuras = true,
        showBuffs = true,            -- buffs de l'unité en ligne au-dessus des débuffs
        friendlyHealth = false,      -- alliés : nom seul
        targetHighlight = true, threatColor = true, classColor = true,
        threatRole = "auto",         -- menace lue comme "tank" ou "dps" ; "auto" : rôle du groupe
        threatColors = {
            tankSecure = { r = 0.2, g = 0.75, b = 0.3 }, tankLosing = { r = 0.95, g = 0.55, b = 0.1 },
            tankLost = { r = 0.85, g = 0.2, b = 0.2 }, offTank = { r = 0.55, g = 0.4, b = 0.9 },
            dpsHigh = { r = 0.95, g = 0.85, b = 0.2 }, dpsGaining = { r = 0.95, g = 0.55, b = 0.1 },
            dpsAggro = { r = 0.85, g = 0.2, b = 0.2 },
        },
        comboPoints = true,          -- points de combo sur la plaque de la cible
        ccSlot = true,               -- premier contrôle dans un emplacement à droite de la plaque
        hideBlizzard = true,
        healthText = "none",         -- préréglage : UnitFrameElements.TEXT_PRESETS
        healthFormat = "",           -- format à jetons, prime sur healthText
        auraFilter = "mine",         -- NS.AURA_FILTERS : sur une plaque, tes débuffs d'abord
        auraLists = { whitelist = "", blacklist = "" }, -- ID de sorts propres aux plaques
        whitelistAnyCaster = false,  -- liste blanche : sorts de tout lanceur, pas seulement les tiens
        fontDelta = -1,              -- taille des textes de plaque par rapport au thème (-4 à +4)
        classificationColors = false, -- ennemis colorés par type : boss, élite, rare, lanceur de sorts
        classificationColor = {
            boss = { r = 0.65, g = 0.3, b = 0.9 }, elite = { r = 0.9, g = 0.5, b = 0.15 },
            rare = { r = 0.75, g = 0.78, b = 0.85 }, caster = { r = 0.3, g = 0.55, b = 0.95 },
        },
        darkenOutOfCombat = false,   -- ennemis hors combat : couleur de vie assombrie
        rangeFade = false,           -- ennemis hors de portée d'attaque atténués
        rangeAlpha = 0.5,
        questIcon = true,            -- icône sur les unités liées à une quête en cours
        castTarget = true,           -- barre d'incantation : cible du sort après son nom
        castTimer = false,           -- barre d'incantation : temps restant à droite (lu par UnitFrameElements)
        targetScale = 1,             -- échelle de la plaque de la cible (1 à 1,5), multipliée à celle d'une règle
        nonTargetAlpha = 0.7,        -- opacité des autres plaques quand une cible existe (avec la surbrillance)
        interruptReady = true,       -- barre d'incantation colorée quand ton interruption est prête
        interruptReadyColor = { r = 0.2, g = 0.85, b = 0.35 },
        importantCast = true,        -- barre d'incantation colorée quand le sort est marqué important
        importantCastColor = { r = 0.9, g = 0.3, b = 0.9 },
        styleRules = STYLE_RULES,    -- filtres de style, dans l'ordre de priorité
        friendlyNpcs = true,         -- plaques sur les PNJ alliés
        pets = true,                 -- plaques sur les familiers et gardiens
        maxDistance = 60,            -- portée d'affichage des plaques, en mètres
        hideWorldNames = false,      -- noms flottants Blizzard masqués (visibles au-delà de la portée)
        nameOffset = 0,              -- distance du nom (et du niveau) à la barre, en pixels
        nameFormat = "full",         -- "full" | "first" | "last" : mot du nom affiché
        nameColorCustom = false, nameColorValue = { r = 1, g = 1, b = 1 },
        levelColorCustom = false, levelColorValue = { r = 1, g = 0.82, b = 0 },
        hideNameWhileCasting = false, -- ennemi : nom masqué pendant son incantation
        castScale = 1,               -- échelle de la plaque d'un ennemi qui incante (1 à 1,5)
        castIconScale = 1, castIconRight = false, castSpark = false,
        targetOverlay = false, targetOverlayColor = { r = 1, g = 1, b = 1 },
        focusOverlay = false, focusOverlayColor = { r = 0.4, g = 0.7, b = 1 },
        hoverOverlay = false, hoverOverlayColor = { r = 1, g = 1, b = 1 },
        targetGlow = false, targetGlowStyle = "pixel",
        healthMarker = 0,            -- trait de seuil sur la barre de vie, en % (0 = aucun)
        raidIconSize = 0,            -- 0 : taille d'origine
        raidIconSide = "top",        -- "top" | "left" | "right"
        borderNone = false,          -- plaque sans bordure
        neutralColor = false, neutralColorValue = { r = 0.95, g = 0.85, b = 0.3 },
    },
})

local active = false
local plates = {}      -- [plate Blizzard] = cadre MuscaUI (pool, réutilisé)
local byUnit = {}      -- [jeton nameplateN] = cadre monté
local hiddenBlizzard = setmetatable({}, { __mode = "k" })   -- [plate.UnitFrame] = true

NamePlateFrames.byUnit = byUnit

-- Sans plaque, le moteur n'affiche que le nom Blizzard : ces CVars décident quelles unités en
-- reçoivent une et jusqu'où. NS.CVars garde l'origine, rendue quand le module est coupé.
local CVAR_RULES = {
    nameplateShowFriendlyNpcs = function(db) return db.friendlyNpcs and "1" or nil end,
    nameplateMaxDistance = function(db) return tostring(db.maxDistance) end,
}
for _, name in ipairs({ "nameplateShowFriendlyPlayerMinions", "nameplateShowFriendlyPlayerPets",
                        "nameplateShowFriendlyPlayerGuardians", "nameplateShowEnemyMinions",
                        "nameplateShowEnemyPets", "nameplateShowEnemyGuardians" }) do
    CVAR_RULES[name] = function(db) return db.pets and "1" or nil end
end
for _, name in ipairs({ "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
                        "UnitNameFriendlySpecialNPCName", "UnitNameNonCombatCreatureName",
                        "UnitNameFriendlyPetName", "UnitNameFriendlyGuardianName",
                        "UnitNameFriendlyMinionName", "UnitNameFriendlyTotemName",
                        "UnitNameEnemyPetName", "UnitNameEnemyGuardianName",
                        "UnitNameEnemyMinionName", "UnitNameEnemyTotemName" }) do
    CVAR_RULES[name] = function(db) return db.hideWorldNames and "0" or nil end
end
NamePlateFrames.CVAR_RULES = CVAR_RULES

local function ApplyCVars()
    for name, rule in pairs(CVAR_RULES) do
        local wanted = active and rule(NamePlateFrames.db) or nil
        if wanted then
            NS.CVars:Set(name, wanted)
        elseif NS.CVars:IsChanged(name) then
            NS.CVars:Restore(name)
        end
    end
end

local function Known(value)
    if NS.IsSecret(value) or value == nil then return nil end
    return value
end

NamePlateFrames.THREAT_STATES = { "tankSecure", "tankLosing", "tankLost", "offTank", "dpsHigh", "dpsGaining", "dpsAggro" }
local DPS_THREAT = { [1] = "dpsHigh", [2] = "dpsGaining", [3] = "dpsAggro" }

--- État de menace du joueur sur `unit` selon son rôle, ou nil (hors liste de menace, secret, API absente).
-- Tank : agro tenue, en train de la perdre, perdue (au profit d'un autre tank : co-tank).
-- DPS et soigneur : menace élevée, agro presque prise, agro prise.
function NamePlateFrames.ThreatState(unit, tank)
    if not _G.UnitThreatSituation then return nil end
    local ok, status = pcall(UnitThreatSituation, "player", unit)
    if not ok or NS.IsSecret(status) or status == nil then return nil end
    if not tank then return DPS_THREAT[status] end
    if status == 3 then return "tankSecure" end
    if status == 2 then return "tankLosing" end
    return NS.OtherTankHasAggro(unit) and "offTank" or "tankLost"
end

--- Couleur de menace connue, ou nil.
function NamePlateFrames.ThreatColor(unit)
    local db = NamePlateFrames.db
    local role = db.threatRole
    local tank = role == "tank" or (role == "auto" and NS.IsTankUnit("player"))
    local state = NamePlateFrames.ThreatState(unit, tank)
    local c = state and db.threatColors[state]
    if c then return c.r, c.g, c.b end
    return nil
end

local CLASSIFICATION_COLOR_KEYS = { worldboss = "boss", elite = "elite", rareelite = "rare", rare = "rare" }

--- Couleur de type d'un PNJ (boss, élite, rare, sinon lanceur de sorts s'il a du mana), ou nil.
function NamePlateFrames.ClassificationColor(unit)
    local player = _G.UnitIsPlayer and UnitIsPlayer(unit)
    if NS.IsSecret(player) or player then return nil end
    local key
    if _G.UnitLevel and Known(UnitLevel(unit)) == -1 then
        key = "boss"
    else
        key = CLASSIFICATION_COLOR_KEYS[_G.UnitClassification and Known(UnitClassification(unit)) or ""]
    end
    if not key and _G.UnitPowerType and Known((UnitPowerType(unit))) == 0 then key = "caster" end   -- 0 : mana
    local c = key and NamePlateFrames.db.classificationColor[key]
    if c then return c.r, c.g, c.b end
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
    local scale = rule and tonumber(rule.scale) or 1
    if IsTarget(frame.unit) then scale = scale * math.max(1, math.min(1.5, tonumber(self.db.targetScale) or 1)) end
    if not frame.friendly and (tonumber(self.db.castScale) or 1) > 1 and IsCasting(frame.unit) then
        scale = scale * math.min(1.5, tonumber(self.db.castScale))
    end
    scale = math.max(0.5, math.min(2, scale))
    if frame.styleScale ~= scale then
        frame.styleScale = scale
        frame:SetScale(scale)
    end
    -- Lueur de la cible : sous celle d'une règle, qui prime.
    local targetGlow = self.db.targetGlow and IsTarget(frame.unit) and not frame.cfg.healthHidden
    local accent
    if targetGlow then
        accent = { a = 0.6 }
        accent.r, accent.g, accent.b = NS.Media:Accent()
    end
    if not rule then NS.Glow.Set(frame, targetGlow, self.db.targetGlowStyle, accent) return end
    local c = rule.colorValue
    if rule.color then frame.health:SetStatusBarColor(c.r, c.g, c.b) end
    -- Allié en nom seul : pas de lueur autour du nom.
    if rule.glow and not frame.cfg.healthHidden then
        NS.Glow.Show(frame, rule.glowStyle, { r = c.r, g = c.g, b = c.b, a = 0.6 })
    else
        NS.Glow.Set(frame, targetGlow, self.db.targetGlowStyle, accent)
    end
    local alpha = math.max(0, math.min(1, tonumber(rule.alpha) or 1))
    if rule.hide then alpha = 0 end
    if alpha < 1 then
        frame:SetAlpha(alpha)
        return alpha
    end
end

local function Config(unit)
    local db = NamePlateFrames.db
    local friendly = IsFriendly(unit)
    return {
        plate = true,
        width = db.width, height = db.height,
        power = false, powerHeight = 0, combo = false,
        castbar = db.showCastbar, castbarHeight = db.castbarHeight,
        auras = db.showAuras and not friendly, auraSize = db.auraSize, aurasAbove = true,
        debuffsOnly = not db.showBuffs,
        auraFilter = db.auraFilter, healthFormat = db.healthFormat,
        auraLists = db.auraLists, whitelistAnyCaster = db.whitelistAnyCaster,
        ccSlot = db.ccSlot and db.showAuras and not friendly,
        name = db.showName, level = db.showLevel,
        healthHidden = friendly and not db.friendlyHealth,
        nameColor = db.nameColorCustom and db.nameColorValue or nil,
    }
end

local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

local function NewFrame()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("BACKGROUND")
    frame.border = NS.Media:CreateBorder(frame)
    -- Lueur des filtres de style : aplat coloré qui déborde, sous la barre.
    -- Unité liée à une quête en cours : atlas du moteur, sinon l'icône de quête classique.
    frame.questIcon = frame:CreateTexture(nil, "OVERLAY")
    if not frame.questIcon:SetAtlas("QuestNormal") then frame.questIcon:SetTexture(QUEST_ICON) end
    frame.questIcon:Hide()
    frame.global = NamePlateFrames.db
    frame.cfg = Config("player")
    Elements.Build(frame)
    Elements.BuildCrowdControlSlot(frame)
    frame.plateComboPips = {}
    -- Recouvrements (cible/focus, survol) et trait de seuil, au-dessus de la couleur de la barre.
    frame.tint = frame.health:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.tint:SetAllPoints(frame.health)
    frame.tint:Hide()
    frame.hoverTint = frame.health:CreateTexture(nil, "OVERLAY", nil, 3)
    frame.hoverTint:SetAllPoints(frame.health)
    frame.hoverTint:Hide()
    frame.marker = frame.health:CreateTexture(nil, "OVERLAY", nil, 4)
    frame.marker:Hide()
    frame.castbar.spark = frame.castbar:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.castbar.spark:Hide()
    return frame
end

--- Points de combo du joueur sur la plaque de sa cible : une pastille par point, au bas de la vie.
function NamePlateFrames:UpdateCombo(frame)
    local points, max
    if self.db.comboPoints and frame.unit and IsTarget(frame.unit) then points, max = NS.GetComboPoints() end
    local pips = frame.plateComboPips
    if not points then
        for _, pip in ipairs(pips) do pip:Hide() end
        return
    end
    local px = NS.Pixel:Scale(1)
    local width = ((frame:GetWidth() or 0) - (max - 1) * px) / max
    for i = 1, max do
        local pip = pips[i]
        if not pip then
            pip = frame:CreateTexture(nil, "OVERLAY", nil, 7)
            pips[i] = pip
        end
        pip:ClearAllPoints()
        pip:SetSize(math.max(1, width), NS.Pixel:Scale(3))
        pip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", (i - 1) * (width + px), 0)
        if i <= points then NS.SetSolidColor(pip, 1, 0.82, 0, 1) else NS.SetSolidColor(pip, 0, 0, 0, 0.6) end
        pip:Show()
    end
    for i = max + 1, #pips do pips[i]:Hide() end
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
    end
    -- Elements.Layout remet ces deux textes à leur taille d'origine à chaque appel : reposés à chaque fois.
    local castDelta = delta - 1 + (tonumber(frame.global.castTextSize) or 0)
    NS.Media:SetTextSizeDelta(frame.castbar.text, castDelta)
    NS.Media:SetTextSizeDelta(frame.castbar.timeText, castDelta)
    -- Nom et niveau sont créés enfants de la barre de vie : cacher la barre (alliés) les cacherait.
    frame.name:SetParent(frame)
    frame.level:SetParent(frame)
    frame.name:ClearAllPoints()
    local nameOffset = tonumber(frame.global.nameOffset) or 0
    frame.name:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, px + 1 + nameOffset)
    frame.name:SetWidth(frame:GetWidth() * 0.75)
    frame.level:ClearAllPoints()
    frame.level:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, px + 1 + nameOffset)
    frame.health.text:ClearAllPoints()
    frame.health.text:SetPoint("CENTER", frame.health, "CENTER", 0, 0)
    local quest = NS.Pixel:Scale(14)
    frame.questIcon:SetSize(quest, quest)
    frame.questIcon:ClearAllPoints()
    frame.questIcon:SetPoint("RIGHT", frame, "LEFT", -NS.Pixel:Scale(2), 0)
    local ccSize = NS.Pixel:Scale(math.floor((frame.cfg.auraSize or 18) * 1.3))
    frame.ccSlot:SetSize(ccSize, ccSize)
    frame.ccSlot:ClearAllPoints()
    frame.ccSlot:SetPoint("LEFT", frame, "RIGHT", NS.Pixel:Scale(3), 0)
    frame.ccSlot:SetShown(frame.cfg.ccSlot and true or false)
    local global = frame.global
    -- Marqueur de raid : taille et côté (Elements.Layout le pose au centre haut, 18 px).
    local raidSize = tonumber(global.raidIconSize) or 0
    if raidSize > 0 then frame.raidIcon:SetSize(NS.Pixel:Scale(raidSize), NS.Pixel:Scale(raidSize)) end
    if global.raidIconSide == "left" then
        frame.raidIcon:ClearAllPoints()
        frame.raidIcon:SetPoint("RIGHT", frame, "LEFT", -NS.Pixel:Scale(18), 0)
    elseif global.raidIconSide == "right" then
        frame.raidIcon:ClearAllPoints()
        frame.raidIcon:SetPoint("LEFT", frame, "RIGHT", ccSize + NS.Pixel:Scale(6), 0)
    end
    -- Icône d'incantation : échelle et côté ; étincelle au bout du remplissage.
    local castbar = frame.castbar
    local iconSize = NS.Pixel:Scale(frame.cfg.castbarHeight or 18) * math.max(0.5, math.min(2, tonumber(global.castIconScale) or 1))
    castbar.iconFrame:SetSize(iconSize, iconSize)
    if global.castIconRight then
        castbar.iconFrame:ClearAllPoints()
        castbar.iconFrame:SetPoint("LEFT", castbar, "RIGHT", NS.Pixel:Scale(4), 0)
        -- La réserve de gauche de la barre revient à droite, où se trouve l'icône.
        if not castbar.detached then
            local point, relative, relativePoint, x, y = castbar:GetPoint(1)
            if point == "TOPLEFT" then
                castbar:ClearAllPoints()
                castbar:SetPoint(point, relative, relativePoint, 0, y)
                castbar:SetPoint("TOPRIGHT", relative, "BOTTOMRIGHT", -(iconSize + NS.Pixel:Scale(4)), y)
            end
        end
    end
    local fill = castbar.GetStatusBarTexture and castbar:GetStatusBarTexture()
    if global.castSpark and fill then
        NS.SetSolidColor(castbar.spark, 1, 1, 1, 0.8)
        castbar.spark:ClearAllPoints()
        castbar.spark:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
        castbar.spark:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
        castbar.spark:SetWidth(px * 2)
        castbar.spark:Show()
    else
        castbar.spark:Hide()
    end
    -- Trait de seuil de vie : position seulement, sans lire la vie (secrète).
    local threshold = math.max(0, math.min(100, tonumber(global.healthMarker) or 0))
    if threshold > 0 then
        local x = (frame.cfg.width or frame:GetWidth() or 0) * threshold / 100
        NS.SetSolidColor(frame.marker, 1, 1, 1, 0.9)
        frame.marker:ClearAllPoints()
        frame.marker:SetPoint("TOPLEFT", frame.health, "TOPLEFT", x, 0)
        frame.marker:SetPoint("BOTTOMLEFT", frame.health, "BOTTOMLEFT", x, 0)
        frame.marker:SetWidth(px)
        frame.marker:Show()
    else
        frame.marker:Hide()
    end
    if frame.cfg.healthHidden then
        frame.health:Hide()
        for _, edge in pairs(frame.border) do edge:Hide() end
    else
        frame.health:Show()
        for _, edge in pairs(frame.border) do edge:SetShown(not global.borderNone) end
    end
end

--- Couleur de vie d'un ennemi : type (boss, élite…), puis menace par-dessus, assombrie hors combat.
-- `baseFresh` : Elements.UpdateHealth vient de poser la couleur de base. Sinon (menace, drapeaux,
-- combat), la vie n'est pas relue : la base n'est refaite que si une teinte (type, menace, règle de
-- style) était posée, `frame.tinted` (booléen, jamais une valeur secrète).
function NamePlateFrames:ApplyHealthColor(frame, baseFresh)
    local db, unit = self.db, frame.unit
    local r, g, b
    if not IsFriendly(unit) then
        if db.neutralColor and _G.UnitReaction and Known(UnitReaction(unit, "player")) == 4 then
            local c = db.neutralColorValue
            r, g, b = c.r, c.g, c.b
        end
        if db.classificationColors then
            local cr, cg, cb = NamePlateFrames.ClassificationColor(unit)
            if cr then r, g, b = cr, cg, cb end
        end
        if db.threatColor then
            local tr, tg, tb = NamePlateFrames.ThreatColor(unit)
            if tr then r, g, b = tr, tg, tb end
        end
        if db.darkenOutOfCombat and Known(UnitAffectingCombat(unit)) == false then
            if not r then r, g, b = Elements.HealthColor(unit, db.classColor) end
            r, g, b = r * 0.5, g * 0.5, b * 0.5
        end
    end
    if r then NS.Media:SetHealthColor(frame.health, r, g, b)
    elseif not baseFresh and frame.tinted then Elements.UpdateHealth(frame) end
    self:UpdateHighlight(frame)   -- opacité, puis filtres de style
    frame.tinted = r ~= nil or (frame.styleRule ~= nil and frame.styleRule.color == true)
end

--- Vie, couleur et textes : UNIT_HEALTH, changement de réaction, montage.
function NamePlateFrames:UpdateHealth(frame)
    Elements.UpdateHealth(frame)
    self:ApplyHealthColor(frame, true)
end

--- Couleur seule (menace, drapeaux, classification, combat) : la vie n'est pas relue.
function NamePlateFrames:UpdateHealthColor(frame)
    self:ApplyHealthColor(frame, false)
end

--- Icône de quête : unité liée à une quête en cours (nil si illisible : rien).
function NamePlateFrames:UpdateQuestIcon(frame)
    frame.questIcon:SetShown(self.db.questIcon and IsQuestUnit(frame.unit) == true)
end

--- Portée d'attaque : l'opacité posée par la surbrillance et les règles, réduite au-delà.
function NamePlateFrames:ApplyRange(frame)
    local base = frame.baseAlpha
    if not (self.db.rangeFade and frame.unit and base) or base <= 0 or IsFriendly(frame.unit) then return end
    NS.SetAttackRangeAlpha(frame, frame.unit, base, base * self.db.rangeAlpha)
end

local function IsMouseover(unit)
    if not _G.UnitIsUnit then return false end
    local same = UnitIsUnit(unit, "mouseover")
    return not NS.IsSecret(same) and same and true or false
end

local hoverTicker

--- Recouvrement de survol : l'unité sous la souris (UPDATE_MOUSEOVER_UNIT). L'événement ne part
-- pas à la fin du survol : un ticker unique relance le calcul tant que la souris est sur une unité.
function NamePlateFrames:ApplyHover(frame)
    local c = self.db.hoverOverlayColor
    local on = self.db.hoverOverlay and frame.unit and not frame.cfg.healthHidden and IsMouseover(frame.unit)
    if on then
        NS.SetSolidColor(frame.hoverTint, c.r, c.g, c.b, 0.2)
        if not hoverTicker then
            hoverTicker = C_Timer.NewTicker(0.1, function()
                for _, plate in pairs(byUnit) do NamePlateFrames:ApplyHover(plate) end
                if not (_G.UnitExists and UnitExists("mouseover")) then
                    hoverTicker:Cancel()
                    hoverTicker = nil
                end
            end)
        end
    end
    frame.hoverTint:SetShown(on and true or false)
end

--- Format du nom, nom masqué en incantation, couleur du niveau, recouvrements cible/focus.
-- Posés après UpdateName et UpdateLevel, qui remettent texte et couleurs d'origine.
function NamePlateFrames:ApplyExtras(frame)
    local db, unit = self.db, frame.unit
    if not unit then return end
    if db.nameFormat ~= "full" then
        local name = Known(UnitName(unit))   -- nom secret : laissé entier
        if type(name) == "string" then
            frame.name:SetText(db.nameFormat == "first" and name:match("^(%S+)") or name:match("(%S+)$") or name)
        end
    end
    if db.hideNameWhileCasting or frame.nameCastHidden then
        local hide = db.hideNameWhileCasting and not frame.friendly and IsCasting(unit)
        frame.nameCastHidden = hide or nil
        frame.name:SetShown(db.showName and not hide)
    end
    if db.levelColorCustom then
        local c = db.levelColorValue
        frame.level:SetTextColor(c.r, c.g, c.b)
    end
    local tint
    if not frame.cfg.healthHidden then
        if db.targetOverlay and IsTarget(unit) then tint = db.targetOverlayColor
        elseif db.focusOverlay and NS.IsFocus(unit) == true then tint = db.focusOverlayColor end
    end
    if tint then NS.SetSolidColor(frame.tint, tint.r, tint.g, tint.b, 0.3) end
    frame.tint:SetShown(tint ~= nil)
    self:ApplyHover(frame)
end

function NamePlateFrames:UpdateHighlight(frame)
    frame.isTarget = NS.IsTarget(frame.unit) ~= false   -- secret : peut-être la cible, refaite au changement
    local highlighted = self.db.targetHighlight and IsTarget(frame.unit) and true or false
    if frame.highlighted ~= highlighted then   -- bords réécrits au changement seulement (Mount remet à nil)
        frame.highlighted = highlighted
        if highlighted then
            local r, g, b = NS.Media:Accent()
            for _, edge in pairs(frame.border) do NS.SetSolidColor(edge, r, g, b, 1) end
        else
            local c = NS.db.theme.border
            for _, edge in pairs(frame.border) do NS.SetSolidColor(edge, c.r, c.g, c.b, c.a or 1) end
        end
    end
    -- Opacité gardée en Lua : relire GetAlpha après SetAlphaFromBoolean (portée) rendrait un secret.
    local focused = NS.IsFocus(frame.unit) == true   -- le focus reste opaque comme la cible ; secret : traité en non-focus
    local alpha = (not highlighted and not focused and self.db.targetHighlight and UnitExists("target")) and math.max(0, math.min(1, tonumber(self.db.nonTargetAlpha) or 0.7)) or 1
    frame:SetAlpha(alpha)
    frame.baseAlpha = self:ApplyStyle(frame) or alpha
    self:ApplyRange(frame)
    self:ApplyExtras(frame)
end

--- `refreshAuras` : montage ou changement de réglage ; sans lui, le conteneur ne relit que si l'unité change.
function NamePlateFrames:UpdateAll(frame, refreshAuras)
    Elements.UpdateName(frame, true)
    Elements.UpdateLevel(frame, true)   -- textes de vie : refaits par UpdateHealth, en dernier
    Elements.UpdateRaidIcon(frame)
    Elements.StartCast(frame)
    Elements.UpdateAuras(frame, refreshAuras)
    self:UpdateQuestIcon(frame)
    self:UpdateCombo(frame)
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
        frame = NS.Modules:Within("nameplateframes", NewFrame)
        plates[plate] = frame
    end
    frame.unit = unit
    frame.plate = plate
    frame.friendly = IsFriendly(unit)
    frame.cfg = Config(unit)
    frame.global = self.db
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", plate, "CENTER", 0, 0)
    PlateLayout(frame)
    Elements.BuildAuras(frame)
    Elements.LayoutAuras(frame)
    byUnit[unit] = frame
    HideBlizzard(plate)
    frame.highlighted = nil   -- réglages ou thème changés : bords à réécrire
    self:UpdateAll(frame, true)
    frame:Show()
    -- Chevrons : leur barre d'ancrage devient la nôtre (l'événement a pu leur parvenir avant).
    local chevrons = NS.Modules:Get("nameplates")
    if chevrons and chevrons.enabled and NS.IsTarget(unit) ~= false then chevrons:Update() end
    return frame
end

function NamePlateFrames:Unmount(unit)
    local frame = byUnit[unit]
    if not frame then return end
    frame:Hide()
    frame.castbar:Hide()
    NS.Glow.Hide(frame)   -- hors du pilote d'animation tant que la plaque est libre
    byUnit[unit] = nil
end

function NamePlateFrames:GetFrame(unit) return byUnit[unit] end

--- Cadre MuscaUI monté sur une plaque Blizzard, ou nil (chevrons du module « Barres de nom »).
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

-- Points de combo : puissance du joueur, à part des événements d'unité des plaques ; plaque de
-- la cible seule, et seulement pour une classe qui en a.
local COMBO_CLASSES = { ROGUE = true, DRUID = true }
local comboEvents = CreateFrame("Frame")
comboEvents:SetScript("OnEvent", function()
    for _, frame in pairs(byUnit) do
        if frame.isTarget then NamePlateFrames:UpdateCombo(frame) end
    end
end)

local function RegisterCombo()
    comboEvents:UnregisterAllEvents()
    local _, class = UnitClass("player")
    class = Known(class)
    if active and NamePlateFrames.db.comboPoints and class and COMBO_CLASSES[class] then
        NS.RegisterEventSafe(comboEvents, "UNIT_POWER_UPDATE", "player")
        -- Points déplacés vers une autre cible : aucun événement de puissance.
        NS.RegisterEventSafe(comboEvents, "COMBO_TARGET_CHANGED")
    end
end

-- Cible changée : ancienne et nouvelle cible seulement ; toutes les plaques quand une cible
-- apparaît ou disparaît avec la surbrillance (les autres plaques s'estompent).
local hadTarget

local function OnTargetChanged()
    local exists = UnitExists("target") and true or false
    local all = exists ~= hadTarget and NamePlateFrames.db.targetHighlight
    hadTarget = exists
    for _, frame in pairs(byUnit) do
        if all or frame.isTarget or NS.IsTarget(frame.unit) ~= false then
            NamePlateFrames:UpdateHealth(frame)
            NamePlateFrames:UpdateCombo(frame)
        end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if not active then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        NamePlateFrames:Mount(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        NamePlateFrames:Unmount(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
    elseif event == "QUEST_LOG_UPDATE" and NamePlateFrames:HasQuestRule() then
        for _, frame in pairs(byUnit) do
            NamePlateFrames:UpdateHealth(frame)
            NamePlateFrames:UpdateQuestIcon(frame)
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if NamePlateFrames.db.questIcon then
            for _, frame in pairs(byUnit) do NamePlateFrames:UpdateQuestIcon(frame) end
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        for _, frame in pairs(byUnit) do NamePlateFrames:ApplyHover(frame) end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        for _, frame in pairs(byUnit) do NamePlateFrames:ApplyExtras(frame) end
    elseif event == "RAID_TARGET_UPDATE" then
        for _, frame in pairs(byUnit) do Elements.UpdateRaidIcon(frame) end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- Entrée ou sortie de combat : couleur (assombrie hors combat) et règles ; à la sortie, les
        -- auras lues sans le moteur (secrètes en combat) sont relues.
        for _, frame in pairs(byUnit) do
            if event == "PLAYER_REGEN_ENABLED" and frame.auras and not frame.auras.engine then
                Elements.UpdateAuras(frame, true)
            end
            NamePlateFrames:UpdateHealthColor(frame)
        end
    else
        local frame = unit and byUnit[unit]
        if not frame then return end
        -- UNIT_FLAGS (combat) et classification : règles seulement, jamais les indicateurs de
        -- UnitFrameElements (l'icône de combat n'a pas sa place sur une plaque).
        if event == "UNIT_FACTION" then
            -- Allié devenu hostile (duel, JcJ) : réglages de la plaque (nom seul, auras) à refaire.
            -- Sinon neutre devenu hostile, ou mob marqué : couleur du nom et de la barre.
            if IsFriendly(unit) ~= frame.friendly then NamePlateFrames:Mount(unit)
            else
                frame.reactionGUID = nil   -- réaction en cache par GUID (FrameHealthColor) à relire
                Elements.UpdateName(frame, true) NamePlateFrames:UpdateHealth(frame)
            end
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            NamePlateFrames:UpdateHealth(frame)
        elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE"
            or event == "UNIT_FLAGS" or event == "UNIT_CLASSIFICATION_CHANGED" then
            NamePlateFrames:UpdateHealthColor(frame)   -- sans relire la vie
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

-- Portée : relue quatre fois par seconde, seulement quand l'option est active.
local rangeTicker

local function RangeTick()
    for _, frame in pairs(byUnit) do NamePlateFrames:ApplyRange(frame) end
end

local function RunRangeTicker()
    local wanted = active and NamePlateFrames.db.rangeFade
    if wanted and not rangeTicker then rangeTicker = C_Timer.NewTicker(0.25, RangeTick)
    elseif not wanted and rangeTicker then rangeTicker:Cancel() rangeTicker = nil end
end

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
                             "QUEST_LOG_UPDATE", "UPDATE_MOUSEOVER_UNIT", "PLAYER_FOCUS_CHANGED" }) do
        NS.RegisterEventSafe(events, event)
    end
    for _, event in ipairs(UNIT_EVENTS) do NS.RegisterEventSafe(events, event) end
    RegisterCombo()
    hadTarget = nil
    for _, event in ipairs(Elements.CAST_EVENTS) do NS.RegisterEventSafe(events, event) end
    ApplyCVars()
    MountExisting()
    RunRangeTicker()
end

function NamePlateFrames:OnDisable()
    active = false
    events:UnregisterAllEvents()
    comboEvents:UnregisterAllEvents()
    for unit in pairs(byUnit) do self:Unmount(unit) end
    RunRangeTicker()
    ApplyCVars()
    if RestoreBlizzard() then NS.Print(L.MSG_NPF_DISABLED_RELOAD) end
end

function NamePlateFrames:OnRefresh()
    ApplyCVars()
    for unit in pairs(byUnit) do self:Mount(unit) end
    RunRangeTicker()
    RegisterCombo()
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
    o:Advanced()
    o:Slider("fontDelta", L.OPT_NPF_FONT_DELTA, -4, 4, 1, nil, "%+d")
    o:Slider("nameOffset", L.OPT_NP_G_NAME_OFFSET, -6, 20, 1, 36, "%+d")
    o:Dropdown("nameFormat", L.OPT_NP_G_NAME_FORMAT, {
        { name = L.OPT_NP_G_NAME_FULL, value = "full" }, { name = L.OPT_NP_G_NAME_FIRST, value = "first" },
        { name = L.OPT_NP_G_NAME_LAST, value = "last" },
    }, 36)
    o:Check("nameColorCustom", L.OPT_NP_G_NAME_COLOR, 36)
    o:Color("nameColorValue", L.OPT_NP_G_NAME_COLOR_VALUE, 52)
    o:Check("levelColorCustom", L.OPT_NP_G_LEVEL_COLOR, 36)
    o:Color("levelColorValue", L.OPT_NP_G_LEVEL_COLOR_VALUE, 52)
    o:Check("hideNameWhileCasting", L.OPT_NP_G_HIDE_NAME_CAST, 36)
    o:Slider("raidIconSize", L.OPT_NP_G_RAID_SIZE, 0, 40, 2, 36)
    o:Dropdown("raidIconSide", L.OPT_NP_G_RAID_SIDE, {
        { name = L.OPT_NP_G_SIDE_TOP, value = "top" }, { name = L.OPT_NP_G_SIDE_LEFT, value = "left" },
        { name = L.OPT_NP_G_SIDE_RIGHT, value = "right" },
    }, 36)
    o:EndAdvanced()
    o:Dropdown("healthText", L.OPT_UF_HEALTH_TEXT, Elements.TextModeChoices)
    o:Advanced()
    o:EditBox("healthFormat", L.OPT_UF_HEALTH_FORMAT)
    o:EndAdvanced()
    o:Check("showCastbar", L.OPT_UF_UNIT_CASTBAR)
    o:Advanced()
    o:Slider("castbarHeight", L.OPT_UF_CASTBAR_HEIGHT, 6, 24, 1, 36)
    o:EndAdvanced()
    o:Check("castTarget", L.OPT_CAST_TARGET, 36)
    o:Check("castTimer", L.OPT_CAST_TIMER, 36)
    o:Check("interruptReady", L.OPT_CAST_INTERRUPT_READY, 36)
    o:Advanced()
    o:Slider("castScale", L.OPT_NP_G_CAST_SCALE, 1, 1.5, 0.05, 36, "%.2f")
    o:Slider("castIconScale", L.OPT_NP_G_CAST_ICON_SCALE, 0.5, 2, 0.1, 36, "%.1f")
    o:Check("castIconRight", L.OPT_NP_G_CAST_ICON_RIGHT, 36)
    o:Check("castSpark", L.OPT_NP_G_CAST_SPARK, 36)
    o:Color("interruptReadyColor", L.OPT_CAST_INTERRUPT_READY_COLOR, 52)
    o:EndAdvanced()
    o:Check("importantCast", L.OPT_CAST_IMPORTANT, 36)
    o:Advanced()
    o:Color("importantCastColor", L.OPT_CAST_IMPORTANT_COLOR, 52)
    o:EndAdvanced()
    o:Check("showAuras", L.OPT_NPF_AURAS)
    o:Check("showBuffs", L.OPT_NPF_BUFFS, 36)
    o:Advanced()
    o:Slider("auraSize", L.OPT_UF_AURA_SIZE, 12, 32, 1, 36)
    o:Dropdown("auraFilter", L.OPT_AURA_FILTER, NS.AuraFilterChoices, 36)
    o:EditBox("auraLists.whitelist", L.OPT_AURA_WHITELIST, 1, 36)
    o:EditBox("auraLists.blacklist", L.OPT_AURA_BLACKLIST, 1, 36)
    o:Check("whitelistAnyCaster", L.OPT_NPF_WHITELIST_ANY_CASTER, 36)
    o:Note(L.NOTE_NPF_AURA_LISTS, 36)
    o:EndAdvanced()
    o:Check("friendlyHealth", L.OPT_NPF_FRIENDLY_HEALTH)
    o:Check("friendlyNpcs", L.OPT_NPF_FRIENDLY_NPCS)
    o:Check("pets", L.OPT_NPF_PETS)
    o:Slider("maxDistance", L.OPT_NPF_MAX_DISTANCE, 20, 60, 5)
    o:Check("hideWorldNames", L.OPT_NPF_HIDE_WORLD_NAMES)
    o:Check("targetHighlight", L.OPT_NPF_TARGET_HIGHLIGHT)
    o:Slider("nonTargetAlpha", L.OPT_NPF_NON_TARGET_ALPHA, 0.1, 1, 0.05, 36, "%.2f")
    o:Slider("targetScale", L.OPT_NPF_TARGET_SCALE, 1, 1.5, 0.05, 36, "%.2f")
    o:Advanced()
    o:Check("targetOverlay", L.OPT_NP_G_TARGET_OVERLAY, 36)
    o:Color("targetOverlayColor", L.OPT_NP_G_TARGET_OVERLAY_COLOR, 52)
    o:Check("focusOverlay", L.OPT_NP_G_FOCUS_OVERLAY, 36)
    o:Color("focusOverlayColor", L.OPT_NP_G_FOCUS_OVERLAY_COLOR, 52)
    o:Check("hoverOverlay", L.OPT_NP_G_HOVER_OVERLAY, 36)
    o:Color("hoverOverlayColor", L.OPT_NP_G_HOVER_OVERLAY_COLOR, 52)
    o:Check("targetGlow", L.OPT_NP_G_TARGET_GLOW, 36)
    o:Dropdown("targetGlowStyle", L.OPT_GLOW_STYLE, NS.Glow.Choices(), 52)
    o:Slider("healthMarker", L.OPT_NP_G_HEALTH_MARKER, 0, 100, 5, 36)
    o:Check("borderNone", L.OPT_NP_G_BORDER_NONE, 36)
    o:EndAdvanced()
    o:Check("threatColor", L.OPT_NPF_THREAT)
    o:Advanced()
    o:Dropdown("threatRole", L.OPT_NPF_THREAT_ROLE, {
        { name = L.MOVER_AUTO, value = "auto" }, { name = L.INSTALL_ROLE_TANK, value = "tank" },
        { name = L.INSTALL_ROLE_DPS, value = "dps" },
    }, 36)
    for _, state in ipairs(NamePlateFrames.THREAT_STATES) do
        o:Color("threatColors." .. state, L["NPF_THREAT_" .. state:upper()], 52)
    end
    o:EndAdvanced()
    o:Check("comboPoints", L.OPT_NPF_COMBO)
    o:Check("ccSlot", L.OPT_NPF_CC_SLOT)
    o:Check("classificationColors", L.OPT_NPF_CLASSIFICATION_COLORS)
    o:Advanced()
    o:Color("classificationColor.boss", L.STYLE_CLASS_BOSS, 36)
    o:Color("classificationColor.elite", L.STYLE_CLASS_ELITE, 36)
    o:Color("classificationColor.rare", L.STYLE_CLASS_RARE, 36)
    o:Color("classificationColor.caster", L.NPF_CASTER, 36)
    o:EndAdvanced()
    o:Check("neutralColor", L.OPT_NP_G_NEUTRAL)
    o:Advanced()
    o:Color("neutralColorValue", L.OPT_NP_G_NEUTRAL_COLOR, 36)
    o:EndAdvanced()
    o:Check("darkenOutOfCombat", L.OPT_NPF_DARKEN_OOC)
    o:Check("rangeFade", L.OPT_NPF_RANGE_FADE)
    o:Advanced()
    o:Slider("rangeAlpha", L.OPT_SWING_RANGE_ALPHA, 0.1, 0.9, 0.05, 36, "%.2f")
    o:EndAdvanced()
    o:Check("questIcon", L.OPT_NPF_QUEST_ICON)
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
        o:Advanced()
        o:Dropdown(key .. "classification", L.OPT_NPF_STYLE_CLASSIFICATION, classes, 36)
        o:Check(key .. "quest", L.OPT_NPF_STYLE_QUEST, 36)
        o:Slider(key .. "healthBelow", L.OPT_NPF_STYLE_HEALTH_BELOW, 0, 100, 5, 36)
        o:EditBox(key .. "names", L.OPT_NPF_STYLE_NAMES, 1, 36)
        o:EndAdvanced()
        o:Check(key .. "color", L.OPT_NPF_STYLE_COLOR, 36)
        o:Color(key .. "colorValue", L.OPT_NPF_STYLE_COLOR_VALUE, 52)
        o:Check(key .. "glow", L.OPT_NPF_STYLE_GLOW, 36)
        o:Advanced()
        o:Dropdown(key .. "glowStyle", L.OPT_GLOW_STYLE, NS.Glow.Choices(), 52)
        o:EndAdvanced()
        o:Slider(key .. "scale", L.OPT_NPF_STYLE_SCALE, 0.5, 2, 0.05, 36, "%.2f")
        o:Advanced()
        o:Slider(key .. "alpha", L.OPT_NPF_STYLE_ALPHA, 0, 1, 0.05, 36, "%.2f")
        o:EndAdvanced()
        o:Check(key .. "hide", L.OPT_NPF_STYLE_HIDE, 36)
    end
end

--- Aperçu des options : une barre ennemie à sa taille, auras au-dessus, nom et niveau, texte de
-- vie, barre d'incantation ; un clic sur une partie ouvre son réglage.
NamePlateFrames.previewHeight = 150
local PREVIEW_AURAS = { "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", "Interface\\Icons\\Spell_Nature_FaerieFire",
                        "Interface\\Icons\\Ability_Hunter_SniperShot" }

function NamePlateFrames:BuildPreview(p)
    return function()
        local db = p.DB()
        p.Begin()
        local auraHeight = db.showAuras and (db.auraSize + 3) or 0
        local nameHeight = (db.showName or db.showLevel) and 14 or 0
        local castHeight = db.showCastbar and (db.castbarHeight + 2) or 0
        local scale, originX, originY = p.Fit(db.width, auraHeight + nameHeight + db.height + castHeight, 10)
        local x, y, width = originX, originY, db.width * scale
        if db.showAuras then
            local size = db.auraSize * scale
            for i, texture in ipairs(PREVIEW_AURAS) do
                p.Icon("aura" .. i, x + (i - 1) * (size + 2), y, size, texture)
            end
            p.Hotspot(p.Region("auras", x, y, #PREVIEW_AURAS * (size + 2), size), L.OPT_NPF_AURAS)
            y = y + auraHeight * scale
        end
        if nameHeight > 0 then
            local text = db.showName and L.UF_UNIT_TARGET or ""
            if db.showLevel then text = "|cffffcc0060|r " .. text end
            p.Text("name", x + width / 2, y, text, 11 * math.min(scale, 1.4) + (db.fontDelta or 0), "TOP")
            p.Hotspot(p.Region("namespot", x, y, width, nameHeight * scale), L.OPT_UF_UNIT_NAME)
            y = y + nameHeight * scale
        end
        local height = db.height * scale
        p.Edge("edge", x, y, width, height, 0, 0, 0, 1)
        p.Bar("health", x, y, width, height, 0.85, 0.2, 0.2, 0.62)
        if db.healthText ~= "none" then p.Text("healthText", x + width - 3, y + height / 2, "62%", math.max(8, height * 0.8), "RIGHT") end
        p.Hotspot(p.Region("healthspot", x, y, width, height), L.OPT_UF_WIDTH)
        y = y + height + 2 * scale
        if db.showCastbar then
            local castbar = db.castbarHeight * scale
            p.Icon("castIcon", x - castbar - 2, y, castbar, "Interface\\Icons\\Spell_Fire_Fireball02")
            p.Bar("cast", x, y, width, castbar, 1, 0.7, 0, 0.55)
            p.Hotspot(p.Region("castspot", x, y, width, castbar), L.OPT_UF_UNIT_CASTBAR)
        end
    end
end
