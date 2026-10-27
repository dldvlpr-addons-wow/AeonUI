-- Modules/Cursor.lua
-- Aides visuelles de visée :
--   * un anneau autour du curseur (retrouver sa souris en plein combat) ;
--   * un réticule au centre de l'écran.
-- L'anneau peut porter la recharge globale et le sort en cours (objets durée, lisibles en combat).
-- Chacun peut ne s'afficher qu'en combat. Aucune frame sécurisée : tout est permis en combat.
local _, NS = ...
local L = NS.L

local RING = "Interface\\AddOns\\MuscaUI\\Media\\Ring"

local Cursor = NS.Modules:Register("cursor", {
    titleKey = "CURSOR_TITLE",
    descKey = "CURSOR_DESC",
    defaults = {
        enabled = false,
        ring = true,
        ringSize = 48,
        ringCombatOnly = true,
        ringColor = { r = 0.25, g = 0.66, b = 0.96 },
        ringClassColor = false,   -- anneau à la couleur de la classe (prioritaire sur ringColor)
        ringOpacity = 1,
        gcdRing = false,    -- recharge globale tracée sur l'anneau
        castRing = false,   -- sort en cours tracé autour de l'anneau
        crosshair = false,
        crosshairSize = 20,
        crosshairThickness = 2,
        crosshairCombatOnly = true,
        crosshairColor = { r = 1, g = 1, b = 1 },
        crosshairOpacity = 0.9,
        crosshairOffsetX = 0,
        crosshairOffsetY = 0,
    },
})

local active = false
local ring, crosshair

local function Build()
    ring = CreateFrame("Frame", "MuscaUICursorRing", UIParent)
    ring:SetFrameStrata("TOOLTIP")
    ring.texture = ring:CreateTexture(nil, "OVERLAY")
    ring.texture:SetAllPoints()
    ring.texture:SetTexture(RING)
    ring:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end)
    -- Cadrans en forme d'anneau : la texture de l'anneau sert de balayage.
    local function Dial(inset)
        local dial = CreateFrame("Cooldown", nil, ring, "CooldownFrameTemplate")
        dial:SetPoint("TOPLEFT", -inset, inset)
        dial:SetPoint("BOTTOMRIGHT", inset, -inset)
        dial:SetSwipeTexture(RING)
        dial:SetDrawEdge(false)
        dial:SetDrawBling(false)
        dial:SetHideCountdownNumbers(true)
        dial:Hide()
        return dial
    end
    ring.gcd = Dial(0)
    ring.cast = Dial(8)
    ring:Hide()

    crosshair = CreateFrame("Frame", "MuscaUICrosshair", UIParent)
    crosshair:SetFrameStrata("BACKGROUND")
    crosshair:SetPoint("CENTER")
    crosshair.h = crosshair:CreateTexture(nil, "OVERLAY")
    crosshair.h:SetPoint("CENTER")
    crosshair.v = crosshair:CreateTexture(nil, "OVERLAY")
    crosshair.v:SetPoint("CENTER")
    crosshair:Hide()
end

function Cursor:Update(event)
    if not ring then return end
    local db = self.db
    -- InCombatLockdown est encore faux pendant PLAYER_REGEN_DISABLED : l'événement fait foi.
    local inCombat = event == "PLAYER_REGEN_DISABLED" or (event ~= "PLAYER_REGEN_ENABLED" and NS.InCombat())

    local showRing = active and db.ring and (inCombat or not db.ringCombatOnly)
    ring:SetSize(db.ringSize, db.ringSize)
    local ringColor = db.ringColor
    if db.ringClassColor then
        local r, g, b = NS.ClassColor(select(2, UnitClass("player")))
        ringColor = { r = r, g = g, b = b }
    end
    ring.texture:SetVertexColor(ringColor.r, ringColor.g, ringColor.b, db.ringOpacity)
    ring:SetShown(showRing and true or false)
    -- Même taille et texture que l'anneau : un balayage sombre, sinon invisible par-dessus.
    ring.gcd:SetSwipeColor(0, 0, 0, 0.6)
    ring.cast:SetSwipeColor(ringColor.r, ringColor.g, ringColor.b, db.ringOpacity)
    ring.gcd:SetShown(active and db.gcdRing and true or false)
    if not (active and db.castRing) then ring.cast:Hide() end

    local showCross = active and db.crosshair and (inCombat or not db.crosshairCombatOnly)
    local c = db.crosshairColor
    crosshair:SetSize(db.crosshairSize, db.crosshairSize)
    crosshair:ClearAllPoints()
    crosshair:SetPoint("CENTER", UIParent, "CENTER", db.crosshairOffsetX, db.crosshairOffsetY)
    crosshair.h:SetSize(db.crosshairSize, db.crosshairThickness)
    crosshair.v:SetSize(db.crosshairThickness, db.crosshairSize)
    NS.SetSolidColor(crosshair.h, c.r, c.g, c.b, db.crosshairOpacity)
    NS.SetSolidColor(crosshair.v, c.r, c.g, c.b, db.crosshairOpacity)
    crosshair:SetShown(showCross and true or false)
end

function Cursor:GetFrames() return ring, crosshair end

-- Fin d'incantation : le cadran se cache (un Cooldown nourri d'un secret ne se relit pas).
local CAST_END = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_CHANNEL_STOP = true }
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP" }

function Cursor:UpdateCast(event)
    if not (ring and active and self.db.castRing) then return end
    if CAST_END[event] then ring.cast:Hide() return end
    local channeling = event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
    ring.cast:SetShown(NS.SetCastCooldown(ring.cast, "player", channeling))
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "SPELL_UPDATE_COOLDOWN" then
        if ring and active and Cursor.db.gcdRing then NS.SetGlobalCooldown(ring.gcd) end
    elseif event:find("^UNIT_SPELLCAST") then
        Cursor:UpdateCast(event)
    else
        Cursor:Update(event)
    end
end)

function Cursor:OnEnable()
    if not ring then Build() end
    active = true
    NS.RegisterEventSafe(events, "PLAYER_REGEN_DISABLED")
    NS.RegisterEventSafe(events, "PLAYER_REGEN_ENABLED")
    NS.RegisterEventSafe(events, "SPELL_UPDATE_COOLDOWN")
    for _, event in ipairs(CAST_EVENTS) do NS.RegisterEventSafe(events, event, "player") end
    self:Update()
end

function Cursor:OnDisable()
    active = false
    events:UnregisterAllEvents()
    self:Update()
end

function Cursor:OnRefresh() self:Update() end

function Cursor:BuildOptions(o)
    o:Title(L.OPT_CURSOR_RING)
    o:Check("ring", L.OPT_CURSOR_RING_SHOW)
    o:Check("ringCombatOnly", L.OPT_CURSOR_COMBAT_ONLY, 36)
    o:Slider("ringSize", L.OPT_CURSOR_SIZE, 24, 128, 4, 36)
    o:Color("ringColor", L.OPT_CURSOR_COLOR, 36)
    o:Check("ringClassColor", L.OPT_G_QOL_CURSOR_CLASS_COLOR, 36)
    o:Slider("ringOpacity", L.OPT_G_QOL_OPACITY, 0.1, 1, 0.05, 36, "%.2f")
    o:Check("gcdRing", L.OPT_M_QOL_CURSOR_GCD, 36)
    o:Check("castRing", L.OPT_M_QOL_CURSOR_CAST, 36)
    o:Title(L.OPT_CURSOR_CROSSHAIR)
    o:Check("crosshair", L.OPT_CURSOR_CROSSHAIR_SHOW)
    o:Check("crosshairCombatOnly", L.OPT_CURSOR_COMBAT_ONLY, 36)
    o:Slider("crosshairSize", L.OPT_CURSOR_SIZE, 8, 64, 2, 36)
    o:Advanced()
    o:Slider("crosshairThickness", L.OPT_CURSOR_THICKNESS, 1, 6, 1, 36)
    o:EndAdvanced()
    o:Color("crosshairColor", L.OPT_CURSOR_COLOR, 36)
    o:Slider("crosshairOpacity", L.OPT_G_QOL_OPACITY, 0.1, 1, 0.05, 36, "%.2f")
    o:Slider("crosshairOffsetX", L.OPT_G_QOL_OFFSET_X, -200, 200, 1, 36)
    o:Slider("crosshairOffsetY", L.OPT_G_QOL_OFFSET_Y, -200, 200, 1, 36)
end
