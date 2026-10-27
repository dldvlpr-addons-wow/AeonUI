-- Modules/ActiveForm.lua
-- Icône de la posture, forme ou aura active (barre de postures), cachée sans forme.
-- Affichage seul : aucun clic, aucune frame sécurisée. Source : NS.GetActiveFormIcon.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local ActiveForm = NS.Modules:Register("activeform", {
    titleKey = "ACTIVE_FORM_TITLE",
    descKey = "ACTIVE_FORM_DESC",
    defaults = {
        enabled = false,
        size = 36,
    },
})

local PREVIEW_ICON = 134400   -- point d'interrogation, déverrouillé sans forme

local active = false
local holder

local function Build()
    holder = CreateFrame("Frame", "MuscaUIActiveForm", UIParent)
    Media:CreateBackdrop(holder)
    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetAllPoints()
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    holder:Hide()
end

function ActiveForm:Update()
    if not holder then return end
    local texture = active and NS.GetActiveFormIcon() or nil
    if not texture and active and NS:Previewing() then texture = PREVIEW_ICON end
    if texture then holder.icon:SetTexture(texture) end
    holder:SetShown(texture and true or false)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() ActiveForm:Update() end)

function ActiveForm:OnEnable()
    if not holder then Build() end
    active = true
    NS.RegisterEventSafe(events, "UPDATE_SHAPESHIFT_FORM")
    NS.RegisterEventSafe(events, "UPDATE_SHAPESHIFT_FORMS")
    NS.RegisterEventSafe(events, "PLAYER_ENTERING_WORLD")
    holder:SetSize(self.db.size, self.db.size)
    NS.Movers:Register("activeForm", holder, L.ACTIVE_FORM_TITLE, "CENTER", 0, -200)
    NS.Movers:Load("activeForm")
    self:Update()
end

function ActiveForm:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("activeForm")
    self:Update()
end

function ActiveForm:OnRefresh()
    if not holder then return end
    holder:SetSize(self.db.size, self.db.size)
    self:Update()
end

NS:On("PREVIEW", function() ActiveForm:Update() end)

function ActiveForm:BuildOptions(o)
    o:Slider("size", L.OPT_CURSOR_SIZE, 16, 96, 2)
end
