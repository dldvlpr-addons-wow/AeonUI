-- Modules/AFK.lua
-- Écran d'absence : quand le personnage passe « absent » hors combat, l'interface se retire,
-- la caméra tourne lentement autour du personnage et un bandeau montre son nom, sa classe,
-- sa guilde et le temps d'absence. Tout revient au retour, à l'entrée en combat ou sur un clic.
--
-- UIParent est caché hors combat seulement ; PLAYER_REGEN_DISABLED arrive avant le verrouillage
-- du combat, donc l'interface revient à temps. Le bandeau est un enfant de WorldFrame : il reste
-- visible quand UIParent est caché.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local AFK = NS.Modules:Register("afk", {
    titleKey = "AFK_TITLE",
    descKey = "AFK_DESC",
    yieldsTo = { "ElvUI" },
    defaults = {
        enabled = false,         -- allumé par l'installation complète
        spin = true,             -- caméra qui tourne
        spinSpeed = 0.035,
    },
})

local active = false
local panel

local function FormatElapsed(seconds)
    seconds = math.floor(seconds)
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end
AFK.FormatElapsed = FormatElapsed

local function Build()
    panel = CreateFrame("Frame", "AeonUI_AFK", WorldFrame)
    panel:SetFrameStrata("FULLSCREEN")
    panel:SetPoint("BOTTOMLEFT", WorldFrame, "BOTTOMLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", WorldFrame, "BOTTOMRIGHT", 0, 0)
    panel:SetHeight(110)
    Media:CreateBackdrop(panel)
    panel:EnableMouse(true)
    panel:SetScript("OnMouseDown", function() AFK:SetShown(false) end)   -- clic : retour anticipé

    panel.name = Media:CreateText(panel, "OVERLAY", 10)
    panel.name:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -20)
    panel.info = Media:CreateText(panel, "OVERLAY", 2)
    panel.info:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -8)
    panel.guild = Media:CreateText(panel, "OVERLAY", 0)
    panel.guild:SetPoint("TOPLEFT", panel.info, "BOTTOMLEFT", 0, -4)
    panel.timer = Media:CreateText(panel, "OVERLAY", 12)
    panel.timer:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    panel.brand = Media:CreateText(panel, "OVERLAY", 4)
    panel.brand:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 10)
    panel.brand:SetText("|cff3fa9f5Aeon|rUI")

    panel.elapsed = 0
    panel:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < 1 then return end
        self.elapsed = 0
        self.timer:SetText(FormatElapsed(GetTime() - self.since))
    end)
    panel:Hide()
end

local function Fill()
    local name = UnitName("player")
    local localizedClass, classFile = UnitClass("player")
    local r, g, b = NS.ClassColor(classFile)
    panel.name:SetText(name or "")
    panel.name:SetTextColor(r, g, b)
    panel.info:SetText(string.format(L.AFK_INFO, UnitLevel("player") or 0, localizedClass or ""))
    local guild = _G.GetGuildInfo and GetGuildInfo("player")
    panel.guild:SetText(guild and ("<" .. guild .. ">") or "")
    panel.timer:SetText(FormatElapsed(0))
end

function AFK:IsShown() return panel ~= nil and panel:IsShown() end

--- Entre (on) ou sort de l'écran d'absence. Jamais d'entrée en combat.
function AFK:SetShown(on)
    if on then
        if self:IsShown() or NS.InCombat() then return end
        if not panel then Build() end
        panel.since, panel.elapsed = GetTime(), 0
        Fill()
        panel:Show()
        UIParent:Hide()
        if self.db.spin and _G.MoveViewLeftStart then MoveViewLeftStart(self.db.spinSpeed) end
    elseif self:IsShown() then
        panel:Hide()
        UIParent:Show()
        if _G.MoveViewLeftStop then MoveViewLeftStop() end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if not active then return end
    if event == "PLAYER_REGEN_DISABLED" then AFK:SetShown(false) return end
    if event == "PLAYER_FLAGS_CHANGED" and unit ~= "player" then return end
    local afk = UnitIsAFK("player")
    if NS.IsSecret(afk) then return end
    AFK:SetShown(afk and true or false)
end)

function AFK:OnEnable()
    active = true
    NS.RegisterEventSafe(events, "PLAYER_FLAGS_CHANGED")
    NS.RegisterEventSafe(events, "PLAYER_REGEN_DISABLED")
    NS.RegisterEventSafe(events, "PLAYER_REGEN_ENABLED")   -- absent pendant le combat : écran à la sortie
end

function AFK:OnDisable()
    self:SetShown(false)
    active = false
    events:UnregisterAllEvents()
end

function AFK:BuildOptions(o)
    o:Check("spin", L.OPT_AFK_SPIN)
    o:Slider("spinSpeed", L.OPT_AFK_SPIN_SPEED, 0.01, 0.1, 0.005, 36, "%.3f")
end
