-- Modules/Cursor.lua
-- Aides visuelles de visée :
--   * un anneau autour du curseur (retrouver sa souris en plein combat) ;
--   * un réticule au centre de l'écran.
-- Chacun peut ne s'afficher qu'en combat. Aucune frame sécurisée : tout est permis en combat.
local _, NS = ...
local L = NS.L

local RING = "Interface\\AddOns\\AeonUI\\Media\\Ring"

local Cursor = NS.Modules:Register("cursor", {
    titleKey = "CURSOR_TITLE",
    descKey = "CURSOR_DESC",
    defaults = {
        enabled = false,
        ring = true,
        ringSize = 48,
        ringCombatOnly = true,
        ringColor = { r = 0.25, g = 0.66, b = 0.96 },
        crosshair = false,
        crosshairSize = 20,
        crosshairThickness = 2,
        crosshairCombatOnly = true,
        crosshairColor = { r = 1, g = 1, b = 1 },
    },
})

local active = false
local ring, crosshair

local function Build()
    ring = CreateFrame("Frame", "AeonUICursorRing", UIParent)
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
    ring:Hide()

    crosshair = CreateFrame("Frame", "AeonUICrosshair", UIParent)
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
    ring.texture:SetVertexColor(db.ringColor.r, db.ringColor.g, db.ringColor.b, 1)
    ring:SetShown(showRing and true or false)

    local showCross = active and db.crosshair and (inCombat or not db.crosshairCombatOnly)
    local c = db.crosshairColor
    crosshair:SetSize(db.crosshairSize, db.crosshairSize)
    crosshair.h:SetSize(db.crosshairSize, db.crosshairThickness)
    crosshair.v:SetSize(db.crosshairThickness, db.crosshairSize)
    NS.SetSolidColor(crosshair.h, c.r, c.g, c.b, 0.9)
    NS.SetSolidColor(crosshair.v, c.r, c.g, c.b, 0.9)
    crosshair:SetShown(showCross and true or false)
end

function Cursor:GetFrames() return ring, crosshair end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event) Cursor:Update(event) end)

function Cursor:OnEnable()
    if not ring then Build() end
    active = true
    NS.RegisterEventSafe(events, "PLAYER_REGEN_DISABLED")
    NS.RegisterEventSafe(events, "PLAYER_REGEN_ENABLED")
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
    o:Title(L.OPT_CURSOR_CROSSHAIR)
    o:Check("crosshair", L.OPT_CURSOR_CROSSHAIR_SHOW)
    o:Check("crosshairCombatOnly", L.OPT_CURSOR_COMBAT_ONLY, 36)
    o:Slider("crosshairSize", L.OPT_CURSOR_SIZE, 8, 64, 2, 36)
    o:Slider("crosshairThickness", L.OPT_CURSOR_THICKNESS, 1, 6, 1, 36)
    o:Color("crosshairColor", L.OPT_CURSOR_COLOR, 36)
end
