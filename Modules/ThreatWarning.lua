-- Modules/ThreatWarning.lua
-- Alerte de menace : son et texte bref quand la menace du joueur sur sa cible atteint le seuil,
-- réarmée sous le seuil moins 10 points. Les tanks en sont exemptés. Événements de menace écoutés
-- seulement en combat. Menace secrète : aucune alerte, une note dans les options.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local ThreatWarning = NS.Modules:Register("threatwarning", {
    titleKey = "THREAT_TITLE",
    descKey = "THREAT_DESC",
    defaults = {
        enabled = true,
        threshold = 80,
        sound = true,
        soundPreset = "raidwarning",
        soundFile = "",
    },
})

local REARM_GAP = 10
local TEXT_SECONDS = 2

local armed = true
local alertText
local textToken = 0

local function ShowAlert()
    if not alertText then
        alertText = Media:CreateText(UIParent, "OVERLAY", 8, "OUTLINE")
        alertText:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
        alertText:SetTextColor(1, 0.3, 0.2)
    end
    alertText:SetText(L.THREAT_ALERT)
    alertText:Show()
    textToken = textToken + 1
    local token = textToken
    C_Timer.After(TEXT_SECONDS, function() if token == textToken then alertText:Hide() end end)
end

--- Applique un relevé de menace (pourcentage lisible) : alerte au seuil, réarme sous seuil - 10.
-- Rend vrai quand l'alerte part.
function ThreatWarning:Check(percent)
    local threshold = self.db.threshold
    if percent < threshold - REARM_GAP then
        armed = true
        return false
    end
    if not armed or percent < threshold then return false end
    armed = false
    if self.db.sound then NS.PlayPreset(self.db.soundPreset, self.db.soundFile) end
    ShowAlert()
    return true
end

local function Read()
    if NS.IsTankUnit("player") then return end
    local percent, status, masked = NS.GetThreatPercent("target")
    if masked then ThreatWarning.masked = true end
    -- Statut 2 ou 3 : le joueur a déjà l'aggro (solo compris), rien à prévenir.
    if percent and not (status and status >= 2) then ThreatWarning:Check(percent) end
end

local THREAT_EVENTS = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }

local threat = CreateFrame("Frame")
threat:SetScript("OnEvent", Read)

local function Listen(on)
    for _, event in ipairs(THREAT_EVENTS) do
        if on then NS.RegisterEventSafe(threat, event, "player", "target") else threat:UnregisterEvent(event) end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        armed = true
        Listen(true)
        Read()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Listen(false)
    elseif event == "PLAYER_TARGET_CHANGED" then
        armed = true
        if NS.InCombat() then Read() end
    end
end)

function ThreatWarning:OnEnable()
    armed = true
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED" }) do
        NS.RegisterEventSafe(events, event)
    end
    Listen(NS.InCombat())
end

function ThreatWarning:OnDisable()
    events:UnregisterAllEvents()
    Listen(false)
    if alertText then alertText:Hide() end
end

function ThreatWarning:BuildOptions(o)
    if self.masked then o:Note(L.THREAT_MASKED) end
    o:Slider("threshold", L.OPT_THREAT_THRESHOLD, 50, 100, 5)
    o:Check("sound", L.OPT_THREAT_SOUND)
    o:Sound("soundPreset", "soundFile", 36)
end
