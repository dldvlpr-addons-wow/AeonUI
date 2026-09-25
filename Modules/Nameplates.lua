-- Modules/Nameplates.lua
-- Deux chevrons de part et d'autre de la barre de nom de la cible, pointés vers elle.
-- Hostiles seulement (réglable). Pendant une incantation de la cible, le chevron gauche
-- s'écarte pour ne pas masquer la barre d'incantation.
-- L'état « incante » vient des events START/STOP : en combat, UnitCastingInfo peut rendre
-- des valeurs secrètes, qu'on ne sait que tester pour « existe ».
local _, NS = ...
local L = NS.L

local CHEVRON = "Interface\\AddOns\\AeonUI\\Media\\Chevron"
-- Colonnes opaques de Chevron.tga (64 px de large : 8 à 53) : la texture est recadrée pour
-- qu'un écart de 0 colle la pointe à la barre.
local CHEVRON_LEFT, CHEVRON_RIGHT = 8 / 64, 54 / 64

local Nameplates = NS.Modules:Register("nameplates", {
    titleKey = "NP_TITLE",
    descKey = "NP_DESC",
    yieldsTo = { "ElvUI" },   -- ElvUI remplace ces cadres : le module cède sans toucher au réglage
    defaults = {
        enabled = true,
        size = 26,
        gap = 4,
        hostileOnly = true,
        castNudge = true,
        castKick = 8,
        color = { r = 1, g = 0.82, b = 0.1 },              -- hors combat
        combatColor = { r = 1, g = 0.3, b = 0.2 },         -- en combat
        otherTankColor = { r = 0.3, g = 0.6, b = 1 },      -- en combat, un autre tank a l'agro de la cible
    },
})

local active = false
local arrows
local targetCasting = false
local inCombat = false   -- InCombatLockdown est encore faux pendant PLAYER_REGEN_DISABLED

local function Build()
    -- Reste enfant d'UIParent : reparenté à une plaque protégée, il hériterait de la protection
    -- et ne pourrait plus bouger en combat. Ancrer sur la plaque suffit.
    arrows = CreateFrame("Frame", "AeonUITargetArrows", UIParent)
    arrows:SetFrameStrata("HIGH")
    arrows:SetSize(1, 1)
    arrows.left = arrows:CreateTexture(nil, "OVERLAY")
    arrows.left:SetTexture(CHEVRON)                 -- pointe à droite, donc vers la plaque
    arrows.left:SetTexCoord(CHEVRON_LEFT, CHEVRON_RIGHT, 0, 1)
    arrows.right = arrows:CreateTexture(nil, "OVERLAY")
    arrows.right:SetTexture(CHEVRON)
    arrows.right:SetTexCoord(CHEVRON_RIGHT, CHEVRON_LEFT, 0, 1)   -- miroir : pointe à gauche
    arrows:Hide()
end

--- La cible est-elle hostile ? Une réponse secrète compte comme hostile (on affiche).
local function TargetIsHostile()
    if not _G.UnitCanAttack then return true end
    local hostile = UnitCanAttack("player", "target")
    if NS.IsSecret(hostile) then return true end
    return hostile and true or false
end

--- La cible incante-t-elle ? Une valeur secrète n'existe que si l'incantation existe.
-- Aucune comparaison sur la valeur elle-même : on teste d'abord le secret.
local function Exists(value)
    if NS.IsSecret(value) then return true end
    return value ~= nil
end

local function ReadTargetCasting()
    if _G.UnitCastingInfo and Exists(UnitCastingInfo("target")) then return true end
    if _G.UnitChannelInfo and Exists(UnitChannelInfo("target")) then return true end
    return false
end

--- Barre de vie de la plaque : celle de AeonUI si le module de plaques la monte, sinon
-- celle de Blizzard, sinon la plaque entière.
local function HealthBar(plate)
    local plateFrames = NS.Modules:Get("nameplateframes")
    local frame = plateFrames and plateFrames.enabled and plateFrames:GetFrameForPlate(plate)
    if frame then return frame.health:IsShown() and frame.health or frame end
    local unitFrame = plate.UnitFrame
    local container = unitFrame and unitFrame.HealthBarsContainer
    return (container and (container.healthBar or container.HealthBar)) or (unitFrame and unitFrame.healthBar) or plate
end

--- Un autre tank a-t-il l'agro de la cible ? Toute réponse secrète vaut non.
local function OtherTankHasAggro()
    if not _G.UnitThreatSituation then return false end
    local ok, status = pcall(UnitThreatSituation, "player", "target")
    -- 2 et 3 : c'est toi qui tanks.
    if not ok or NS.IsSecret(status) or (status or 0) >= 2 then return false end
    local exists = UnitExists("targettarget")
    if NS.IsSecret(exists) or not exists then return false end
    local coTank = NS.Modules:Get("cotank")
    return coTank ~= nil and coTank.IsTank("targettarget")
end

function Nameplates:Color()
    local db = self.db
    if not (inCombat or NS.InCombat()) then return db.color end
    if OtherTankHasAggro() then return db.otherTankColor end
    return db.combatColor
end

function Nameplates:Update()
    if not arrows then return end
    local db = self.db
    local plate = active and NS.GetTargetNamePlate()
    if not plate or (db.hostileOnly and not TargetIsHostile()) then
        arrows:Hide()
        return
    end
    local c = self:Color()
    local bar = HealthBar(plate)
    arrows:ClearAllPoints()
    arrows:SetAllPoints(plate)
    for _, texture in ipairs({ arrows.left, arrows.right }) do
        texture:SetSize(db.size * (CHEVRON_RIGHT - CHEVRON_LEFT), db.size)
        texture:SetVertexColor(c.r, c.g, c.b, 1)
        texture:ClearAllPoints()
    end
    local gap = math.max(0, db.gap)   -- anciens profils : le curseur allait jusqu'à -30
    local kick = (db.castNudge and targetCasting) and db.castKick or 0
    arrows.left:SetPoint("RIGHT", bar, "LEFT", -gap - kick, 0)
    arrows.right:SetPoint("LEFT", bar, "RIGHT", gap, 0)
    arrows:Show()
end

function Nameplates:GetArrows() return arrows end

local CAST_START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }
local CAST_STOP = {
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_FAILED = true,
}

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        inCombat = event == "PLAYER_REGEN_DISABLED"
    elseif CAST_START[event] then
        targetCasting = true
    elseif CAST_STOP[event] then
        targetCasting = false
    elseif event == "PLAYER_TARGET_CHANGED" then
        targetCasting = ReadTargetCasting()
    elseif event == "NAME_PLATE_UNIT_REMOVED" and NS.IsTarget(unit) ~= false then
        -- Cible, ou réponse secrète (combat) : dans le doute on cache. Pendant l'event,
        -- GetNamePlateForUnit peut encore rendre la plaque, qui sera recyclée : on réexamine
        -- une frame plus tard (si ce n'était pas la cible, les chevrons reviennent).
        if arrows then arrows:Hide() end
        C_Timer.After(0, function() Nameplates:Update() end)
        return
    end
    Nameplates:Update()
end)

function Nameplates:OnEnable()
    if not arrows then Build() end
    active = true
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
                             "PLAYER_ENTERING_WORLD", "UNIT_FACTION", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        NS.RegisterEventSafe(events, event)
    end
    for event in pairs(CAST_START) do NS.RegisterEventSafe(events, event, "target") end
    for event in pairs(CAST_STOP) do NS.RegisterEventSafe(events, event, "target") end
    -- Couleur : agro de la cible (autre tank).
    for _, event in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_TARGET" }) do
        NS.RegisterEventSafe(events, event, "target")
    end
    targetCasting = ReadTargetCasting()
    self:Update()
end

function Nameplates:OnDisable()
    active = false
    events:UnregisterAllEvents()
    if arrows then arrows:Hide() end
end

function Nameplates:OnRefresh() self:Update() end

function Nameplates:BuildOptions(o)
    o:Check("hostileOnly", L.OPT_NP_HOSTILE)
    o:Slider("size", L.OPT_NP_SIZE, 8, 48, 2)
    o:Slider("gap", L.OPT_NP_GAP, 0, 40, 1)
    o:Color("color", L.OPT_NP_COLOR)
    o:Color("combatColor", L.OPT_NP_COMBAT_COLOR)
    o:Color("otherTankColor", L.OPT_NP_OTHER_TANK_COLOR)
    o:Check("castNudge", L.OPT_NP_CAST_NUDGE)
    o:Slider("castKick", L.OPT_NP_CAST_KICK, 0, 30, 1, 36)
end
