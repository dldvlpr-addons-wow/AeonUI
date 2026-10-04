-- AeonUI_Nameplates/NamePlateFrames.lua
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
local NS = AeonUI
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
        interruptReady = true,       -- barre d'incantation colorée quand ton interruption est prête
        interruptReadyColor = { r = 0.2, g = 0.85, b = 0.35 },
        styleRules = STYLE_RULES,    -- filtres de style, dans l'ordre de priorité
        friendlyNpcs = true,         -- plaques sur les PNJ alliés
        pets = true,                 -- plaques sur les familiers et gardiens
        maxDistance = 60,            -- portée d'affichage des plaques, en mètres
        hideWorldNames = false,      -- noms flottants Blizzard masqués (visibles au-delà de la portée)
    },
})

local active = false
local plates = {}      -- [plate Blizzard] = cadre AeonUI (pool, réutilisé)
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
    local scale = math.max(0.5, math.min(2, rule and tonumber(rule.scale) or 1))
    if frame.styleScale ~= scale then
        frame.styleScale = scale
        frame:SetScale(scale)
    end
    if not rule then NS.Glow.Hide(frame) return end
    local c = rule.colorValue
    if rule.color then frame.health:SetStatusBarColor(c.r, c.g, c.b) end
    -- Allié en nom seul : pas de lueur autour du nom.
    NS.Glow.Set(frame, rule.glow and not frame.cfg.healthHidden, rule.glowStyle, { r = c.r, g = c.g, b = c.b, a = 0.6 })
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
        ccSlot = db.ccSlot and db.showAuras and not friendly,
        name = db.showName, level = db.showLevel,
        healthHidden = friendly and not db.friendlyHealth,
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
    local quest = NS.Pixel:Scale(14)
    frame.questIcon:SetSize(quest, quest)
    frame.questIcon:ClearAllPoints()
    frame.questIcon:SetPoint("RIGHT", frame, "LEFT", -NS.Pixel:Scale(2), 0)
    local ccSize = NS.Pixel:Scale(math.floor((frame.cfg.auraSize or 18) * 1.3))
    frame.ccSlot:SetSize(ccSize, ccSize)
    frame.ccSlot:ClearAllPoints()
    frame.ccSlot:SetPoint("LEFT", frame, "RIGHT", NS.Pixel:Scale(3), 0)
    frame.ccSlot:SetShown(frame.cfg.ccSlot and true or false)
    if frame.cfg.healthHidden then
        frame.health:Hide()
        for _, edge in pairs(frame.border) do edge:Hide() end
    else
        frame.health:Show()
        for _, edge in pairs(frame.border) do edge:Show() end
    end
end

--- Couleur de vie d'un ennemi : type (boss, élite…), puis menace par-dessus, assombrie hors combat.
function NamePlateFrames:UpdateHealth(frame)
    Elements.UpdateHealth(frame)
    local db, unit = self.db, frame.unit
    if not IsFriendly(unit) then
        local r, g, b
        if db.classificationColors then r, g, b = NamePlateFrames.ClassificationColor(unit) end
        if db.threatColor then
            local tr, tg, tb = NamePlateFrames.ThreatColor(unit)
            if tr then r, g, b = tr, tg, tb end
        end
        if db.darkenOutOfCombat and Known(UnitAffectingCombat(unit)) == false then
            if not r then r, g, b = Elements.HealthColor(unit, db.classColor) end
            r, g, b = r * 0.5, g * 0.5, b * 0.5
        end
        if r then NS.Media:SetHealthColor(frame.health, r, g, b) end
    end
    self:UpdateHighlight(frame)   -- opacité, puis filtres de style
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

function NamePlateFrames:UpdateHighlight(frame)
    local highlighted = self.db.targetHighlight and IsTarget(frame.unit)
    if highlighted then
        local r, g, b = NS.Media:Accent()
        for _, edge in pairs(frame.border) do NS.SetSolidColor(edge, r, g, b, 1) end
    else
        local c = NS.db.theme.border
        for _, edge in pairs(frame.border) do NS.SetSolidColor(edge, c.r, c.g, c.b, c.a or 1) end
    end
    -- Opacité gardée en Lua : relire GetAlpha après SetAlphaFromBoolean (portée) rendrait un secret.
    local alpha = (not highlighted and self.db.targetHighlight and UnitExists("target")) and 0.7 or 1
    frame:SetAlpha(alpha)
    frame.baseAlpha = self:ApplyStyle(frame) or alpha
    self:ApplyRange(frame)
end

function NamePlateFrames:UpdateAll(frame)
    Elements.UpdateName(frame)
    Elements.UpdateLevel(frame)
    Elements.UpdateRaidIcon(frame)
    Elements.StartCast(frame)
    Elements.UpdateAuras(frame, true)
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
    NS.Glow.Hide(frame)   -- hors du pilote d'animation tant que la plaque est libre
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

-- Points de combo : puissance du joueur, à part des événements d'unité des plaques.
local comboEvents = CreateFrame("Frame")
comboEvents:SetScript("OnEvent", function()
    for _, frame in pairs(byUnit) do NamePlateFrames:UpdateCombo(frame) end
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if not active then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        NamePlateFrames:Mount(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        NamePlateFrames:Unmount(unit)
    elseif event == "PLAYER_TARGET_CHANGED" or (event == "QUEST_LOG_UPDATE" and NamePlateFrames:HasQuestRule()) then
        for _, frame in pairs(byUnit) do
            NamePlateFrames:UpdateHealth(frame)
            if event == "QUEST_LOG_UPDATE" then NamePlateFrames:UpdateQuestIcon(frame)
            else NamePlateFrames:UpdateCombo(frame) end
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if NamePlateFrames.db.questIcon then
            for _, frame in pairs(byUnit) do NamePlateFrames:UpdateQuestIcon(frame) end
        end
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
                             "QUEST_LOG_UPDATE" }) do
        NS.RegisterEventSafe(events, event)
    end
    for _, event in ipairs(UNIT_EVENTS) do NS.RegisterEventSafe(events, event) end
    NS.RegisterEventSafe(comboEvents, "UNIT_POWER_UPDATE", "player")
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
    o:Check("interruptReady", L.OPT_CAST_INTERRUPT_READY, 36)
    o:Advanced()
    o:Color("interruptReadyColor", L.OPT_CAST_INTERRUPT_READY_COLOR, 52)
    o:EndAdvanced()
    o:Check("showAuras", L.OPT_NPF_AURAS)
    o:Check("showBuffs", L.OPT_NPF_BUFFS, 36)
    o:Advanced()
    o:Slider("auraSize", L.OPT_UF_AURA_SIZE, 12, 32, 1, 36)
    o:Dropdown("auraFilter", L.OPT_AURA_FILTER, NS.AuraFilterChoices, 36)
    o:EndAdvanced()
    o:Check("friendlyHealth", L.OPT_NPF_FRIENDLY_HEALTH)
    o:Check("friendlyNpcs", L.OPT_NPF_FRIENDLY_NPCS)
    o:Check("pets", L.OPT_NPF_PETS)
    o:Slider("maxDistance", L.OPT_NPF_MAX_DISTANCE, 20, 60, 5)
    o:Check("hideWorldNames", L.OPT_NPF_HIDE_WORLD_NAMES)
    o:Check("targetHighlight", L.OPT_NPF_TARGET_HIGHLIGHT)
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
