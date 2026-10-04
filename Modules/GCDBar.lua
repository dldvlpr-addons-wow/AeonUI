-- Modules/GCDBar.lua
-- Barre de recharge globale : se remplit pendant la recharge globale du joueur, cachée le reste
-- du temps. Source : NS.GetGlobalCooldown, relue à chaque changement de recharge et à chaque sort.
-- Le moteur anime la barre (SetTimerDuration) ; le Lua ne tourne que pendant la recharge, pour
-- cacher la barre à la fin (et l'animer lui-même sans l'API).
local _, NS = ...
local L = NS.L
local Media = NS.Media

local GCDBar = NS.Modules:Register("gcdbar", {
    titleKey = "GCD_TITLE",
    descKey = "GCD_DESC",
    defaults = {
        enabled = false,
        width = 220,
        height = 4,
        color = { r = 1, g = 0.82, b = 0.2 },
    },
})

local active = false
local holder, bar

local function Build()
    holder = CreateFrame("Frame", "AeonUIGCDBar", UIParent)
    Media:CreateBackdrop(holder)
    bar = Media:CreateStatusBar(holder)
    bar:SetAllPoints(holder)
    holder:Hide()
    holder:SetScript("OnUpdate", function()
        if not bar.finish then return end
        local now = GetTime()
        if now >= bar.finish then
            bar.finish, bar.manual = nil, nil
            GCDBar:Update()
        elseif bar.manual then
            bar:SetValue(now - bar.manual)
        end
    end)
end

function GCDBar:Update()
    if not holder then return end
    local start, duration = NS.GetGlobalCooldown()
    if not (active and start) then
        bar.finish, bar.manual = nil, nil
        -- Déverrouillé : barre pleine, visible pour être placée.
        if active and NS.unlocked then
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(1)
            holder:Show()
        else
            holder:Hide()
        end
        return
    end
    bar.finish = start + duration
    bar.manual = nil
    if not NS.SetBarTimer(bar, start, duration, false) then
        bar.manual = start
        bar:SetMinMaxValues(0, duration)
        bar:SetValue(GetTime() - start)
    end
    holder:Show()
end

function GCDBar:Layout()
    local db = self.db
    holder:SetSize(db.width, db.height)
    bar:SetStatusBarColor(db.color.r, db.color.g, db.color.b)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() GCDBar:Update() end)

function GCDBar:OnEnable()
    if not holder then Build() end
    active = true
    NS.RegisterEventSafe(events, "SPELL_UPDATE_COOLDOWN")
    NS.RegisterEventSafe(events, "UNIT_SPELLCAST_START", "player")
    NS.RegisterEventSafe(events, "UNIT_SPELLCAST_SUCCEEDED", "player")
    self:Layout()
    NS.Movers:Register("gcdBar", holder, L.MOVER_GCD, "CENTER", 0, -150)
    NS.Movers:Load("gcdBar")
    self:Update()
end

function GCDBar:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("gcdBar")
    self:Update()
end

function GCDBar:OnRefresh()
    if not holder then return end
    self:Layout()
    self:Update()
end

NS:On("UNLOCK", function() GCDBar:Update() end)

function GCDBar:BuildOptions(o)
    o:Slider("width", L.OPT_RESOURCE_WIDTH, 60, 500, 2)
    o:Slider("height", L.OPT_RESOURCE_HEIGHT, 2, 30, 1)
    o:Color("color", L.OPT_BAND_COLOR)
end
