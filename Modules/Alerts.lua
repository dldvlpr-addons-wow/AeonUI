-- Modules/Alerts.lua
-- Alertes à l'écran, sans journal de combat (interdit sur Forever) :
--   * entrée / sortie de combat (« +Combat » / « -Combat ») ;
--   * mort d'un membre du groupe, annoncée une fois par mort (UnitIsDeadOrGhost sur les
--     events d'unité ; une réponse secrète est ignorée) ;
--   * chronomètre de combat, qui reste affiché quelques secondes après la fin.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local FADE_DURATION = 1.5
local TIMER_LINGER = 4

local Alerts = NS.Modules:Register("alerts", {
    titleKey = "ALERTS_TITLE",
    descKey = "ALERTS_DESC",
    defaults = {
        enabled = true,
        combat = true,
        combatShow = "both",       -- "both" | "enter" | "leave"
        combatInText = "",         -- vide = texte de la locale
        combatOutText = "",
        combatInColor = { r = 1, g = 0.3, b = 0.3 },
        combatOutColor = { r = 0.3, g = 1, b = 0.3 },
        combatSound = false,
        combatSoundPreset = "ping",
        combatSoundFile = "",      -- son importé, prioritaire sur le preset
        deaths = true,
        deathSound = true,
        deathSoundPreset = "raidwarning",
        deathSoundFile = "",
        deathTextSize = 22,
        combatTimer = false,
        textSize = 22,
    },
})

local active = false
local flash, timerFrame
local combatStart
local dead = {}        -- [guid] = true pour les membres déjà annoncés morts

--------------------------------------------------------------------------------
-- Texte flash (apparaît, reste, s'efface)
--------------------------------------------------------------------------------

local function BuildFlash()
    flash = CreateFrame("Frame", "AeonUIAlerts", UIParent)
    flash:SetSize(400, 40)
    flash:SetFrameStrata("HIGH")
    flash.text = Media:CreateText(flash, "OVERLAY")   -- police posée dès la création : l'aperçu /aeon unlock est lisible
    flash.text:SetPoint("CENTER")
    flash.text:SetShadowOffset(1, -1)
    flash.bg = flash:CreateTexture(nil, "BACKGROUND")
    flash.bg:SetAllPoints()
    flash:SetScript("OnUpdate", function(self, elapsed)
        if NS.unlocked then return end
        self.remaining = (self.remaining or 0) - elapsed
        if self.remaining <= 0 then
            self:Hide()
        elseif self.remaining < FADE_DURATION then
            self:SetAlpha(self.remaining / FADE_DURATION)
        end
    end)
    flash:Hide()
end

function Alerts:Flash(text, r, g, b, sound, size, soundFile)
    if not flash then return end
    flash.text:SetFont(Media:Font(), size or self.db.textSize, "OUTLINE")
    flash.text:SetText(text)
    flash.text:SetTextColor(r, g, b)
    flash.remaining = 2.5
    flash:SetAlpha(1)
    flash:Show()
    if sound then NS.PlayPreset(sound, soundFile) end
end

function Alerts:GetFlash() return flash end

--------------------------------------------------------------------------------
-- Chronomètre de combat
--------------------------------------------------------------------------------

local function BuildTimer()
    timerFrame = CreateFrame("Frame", "AeonUICombatTimer", UIParent)
    timerFrame:SetSize(90, 24)
    timerFrame.text = Media:CreateText(timerFrame, "OVERLAY", 4, "OUTLINE")
    timerFrame.text:SetPoint("CENTER")
    timerFrame.bg = timerFrame:CreateTexture(nil, "BACKGROUND")
    timerFrame.bg:SetAllPoints()
    timerFrame:SetScript("OnUpdate", function(self)
        if combatStart then
            self.text:SetText(NS.FormatDuration(GetTime() - combatStart))
        elseif not NS.unlocked and self.hideAt and GetTime() >= self.hideAt then
            self:Hide()
        end
    end)
    timerFrame:Hide()
end

--------------------------------------------------------------------------------
-- Morts du groupe
--------------------------------------------------------------------------------

local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
    end
    return units
end

--- Vérifie une unité ; annonce sa mort une seule fois. Retourne true si annoncée.
function Alerts:CheckDeath(unit)
    if not self.db.deaths or not UnitExists(unit) then return false end
    local guid = UnitGUID(unit)
    local isDead = UnitIsDeadOrGhost(unit)
    if NS.IsSecret(guid) or NS.IsSecret(isDead) or not guid then return false end
    -- Pas UnitIsUnit(unit, "player") : secret en combat. Le GUID, lui, vient d'être vérifié.
    if guid == UnitGUID("player") then return false end
    if not isDead then
        dead[guid] = nil
        return false
    end
    if dead[guid] then return false end
    dead[guid] = true
    local name = UnitName(unit)
    if NS.IsSecret(name) then name = nil end
    local _, classFile = UnitClass(unit)
    local r, g, b = NS.ClassColor(not NS.IsSecret(classFile) and classFile or nil)
    self:Flash(string.format(L.ALERTS_DIED, name or "?"), r, g, b,
        self.db.deathSound and self.db.deathSoundPreset or nil, self.db.deathTextSize, self.db.deathSoundFile)
    return true
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    local db = Alerts.db
    if event == "PLAYER_REGEN_DISABLED" then
        if db.combat and db.combatShow ~= "leave" then
            local c = db.combatInColor
            Alerts:Flash(db.combatInText ~= "" and db.combatInText or L.ALERTS_COMBAT_IN, c.r, c.g, c.b,
                db.combatSound and db.combatSoundPreset or nil, nil, db.combatSoundFile)
        end
        if db.combatTimer then
            combatStart = GetTime()
            timerFrame.text:SetTextColor(1, 1, 1)
            timerFrame:Show()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if db.combat and db.combatShow ~= "enter" then
            local c = db.combatOutColor
            Alerts:Flash(db.combatOutText ~= "" and db.combatOutText or L.ALERTS_COMBAT_OUT, c.r, c.g, c.b,
                db.combatSound and db.combatSoundPreset or nil, nil, db.combatSoundFile)
        end
        if combatStart then
            combatStart = nil
            timerFrame.text:SetTextColor(0.6, 0.6, 0.6)
            timerFrame.hideAt = GetTime() + TIMER_LINGER
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Seuls les partis sont oubliés : vider tout rejouerait « X est mort » à chaque arrivée.
        -- GUID secret (combat) : on garde tout, la mémoire sera triée au prochain changement.
        local still, secret = {}, false
        for _, member in ipairs(GroupUnits()) do
            local guid = UnitGUID(member)
            if NS.IsSecret(guid) then secret = true break end
            if guid and dead[guid] then still[guid] = true end
        end
        if not secret then dead = still end
    elseif unit and (unit:match("^party%d") or unit:match("^raid%d")) then
        Alerts:CheckDeath(unit)
    end
end)

local function ApplyUnlock(unlocked)
    for _, frame in ipairs({ flash, timerFrame }) do
        if frame then NS.SetSolidColor(frame.bg, 0.25, 0.66, 0.96, unlocked and 0.25 or 0) end
    end
    if not active then return end
    if unlocked then
        flash.text:SetText(L.ALERTS_PREVIEW)
        flash:SetAlpha(1)
        flash:Show()
        timerFrame.text:SetText("0:42")
        timerFrame:Show()
    else
        flash:Hide()
        if not combatStart then timerFrame:Hide() end
    end
end

function Alerts:OnEnable()
    if not flash then
        BuildFlash()
        BuildTimer()
    end
    active = true
    -- Movers liés au module : coupé, ils n'apparaissent plus au déverrouillage.
    NS.Movers:Register("alerts", flash, L.MOVER_ALERTS, "CENTER", 0, 220)
    NS.Movers:Register("combatTimer", timerFrame, L.MOVER_COMBAT_TIMER, "CENTER", 0, 180)
    NS.Movers:Load("alerts")
    NS.Movers:Load("combatTimer")
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
                             "UNIT_HEALTH", "UNIT_FLAGS" }) do
        NS.RegisterEventSafe(events, event)
    end
    ApplyUnlock(NS.unlocked)
end

function Alerts:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("alerts")
    NS.Movers:Unregister("combatTimer")
    combatStart = nil
    if flash then flash:Hide() end
    if timerFrame then timerFrame:Hide() end
end

function Alerts:OnRefresh()
    if not self.db.combatTimer and not NS.unlocked then
        combatStart = nil
        timerFrame:Hide()
    end
end

Alerts.GroupUnits = GroupUnits

NS:On("UNLOCK", ApplyUnlock)

function Alerts:BuildOptions(o)
    o:Check("combat", L.OPT_ALERTS_COMBAT)
    o:Dropdown("combatShow", L.OPT_ALERTS_SHOW, {
        { name = L.ALERTS_SHOW_BOTH, value = "both" },
        { name = L.ALERTS_SHOW_ENTER, value = "enter" },
        { name = L.ALERTS_SHOW_LEAVE, value = "leave" },
    }, 36)
    o:EditBox("combatInText", L.OPT_ALERTS_IN_TEXT, 1, 36)
    o:Color("combatInColor", L.OPT_ALERTS_IN_COLOR, 36)
    o:EditBox("combatOutText", L.OPT_ALERTS_OUT_TEXT, 1, 36)
    o:Color("combatOutColor", L.OPT_ALERTS_OUT_COLOR, 36)
    o:Slider("textSize", L.OPT_ALERTS_SIZE, 12, 48, 2, 36)
    o:Check("combatSound", L.OPT_ALERTS_COMBAT_SOUND, 36)
    o:Sound("combatSoundPreset", "combatSoundFile", 52)
    o:Check("deaths", L.OPT_ALERTS_DEATHS)
    o:Slider("deathTextSize", L.OPT_ALERTS_SIZE, 12, 48, 2, 36)
    o:Check("deathSound", L.OPT_ALERTS_DEATH_SOUND, 36)
    o:Sound("deathSoundPreset", "deathSoundFile", 52)
    o:Check("combatTimer", L.OPT_ALERTS_TIMER)
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end)
end
