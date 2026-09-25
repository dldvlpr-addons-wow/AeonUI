-- Modules/DataPanels.lua
-- Panneaux de données : jusqu'à trois bandeaux libres, chacun sur son mover, découpés en
-- emplacements de largeur égale. Chaque emplacement montre un data text du registre
-- NS.DataTexts (ceux de la barre du haut, plus coordonnées, quêtes, régénération, vitesse, DPS).
--
-- Module `secure` : le masquage en combat passe par un state driver, interdit à poser ou retirer
-- en combat ; réglages, activation et agencement attendent donc la sortie du combat. Les textes,
-- eux, suivent événements et minuterie en combat. Largeurs fixes : un texte secret (DPS du
-- compteur natif) s'affiche sans que sa largeur soit mesurée.
local _, NS = ...
local L = NS.L
local Media = NS.Media
local DataTexts = NS.DataTexts

local NUM_PANELS = 3        -- ponytail: panneaux fixes, liste dynamique si trois ne suffisent pas
local MAX_SLOTS = 6
local TICK = 0.5

-- Clés chaînes (panel1, slot1…) : l'export de profil et le miroir CVar n'aplatissent que celles-là.
local function Panel(enabled, keys)
    local slots = {}
    for s = 1, MAX_SLOTS do slots["slot" .. s] = keys[s] or "none" end
    return {
        enabled = enabled, width = 360, height = 22, slotCount = #keys,
        backgroundAlpha = 0.75, hideInCombat = false, slots = slots,
    }
end

local DataPanels = NS.Modules:Register("datapanels", {
    titleKey = "DATAPANELS_TITLE",
    descKey = "DATAPANELS_DESC",
    secure = true,
    defaults = {
        enabled = false,
        panels = {
            panel1 = Panel(true, { "coords", "speed", "regen", "quests" }),
            panel2 = Panel(false, { "gold", "durability", "bags" }),
            panel3 = Panel(false, { "dps", "perf" }),
        },
    },
})

local MOVER_DEFAULTS = {
    { "BOTTOMLEFT", 380, 4 },
    { "BOTTOMRIGHT", -380, 4 },
    { "TOPLEFT", 20, -40 },
}

local active = false
local frames = {}          -- [i] = cadre de panneau
local byEvent = {}         -- [événement] = { bouton, ... }
local ticker
local events = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- Emplacements
--------------------------------------------------------------------------------

local function SlotDef(button)
    local key = button.dataKey
    return key and key ~= "none" and DataTexts:Get(key) or nil
end

local function UpdateSlot(button)
    local def = SlotDef(button)
    if def then DataTexts.Render(def, button.label) else button.label:SetText("") end
end

local function ShowTooltip(button)
    local def = SlotDef(button)
    if not (def and def.tooltip) then return end
    if NS.InCombat() and def.noCombatTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    def.tooltip(GameTooltip)
    GameTooltip:Show()
end

local function OnClick(button, mouseButton)
    local def = SlotDef(button)
    if def and def.click then def.click(button, mouseButton) end
    UpdateSlot(button)
end

local function NewSlot(panel)
    local button = CreateFrame("Button", nil, panel)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.label = Media:CreateText(button, "OVERLAY")
    button.label:SetPoint("CENTER")
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", OnClick)
    button.elapsed = 0
    return button
end

local function Build(i)
    local panel = CreateFrame("Frame", "AeonUIDataPanel" .. i, UIParent)
    panel:SetFrameStrata("LOW")
    panel.bg = Media:CreateBackdrop(panel)
    panel.slots = {}
    for s = 1, MAX_SLOTS do panel.slots[s] = NewSlot(panel) end
    frames[i] = panel
    return panel
end

--------------------------------------------------------------------------------
-- Agencement
--------------------------------------------------------------------------------

local function MoverKey(i) return "datapanel" .. i end

local function Layout(i)
    local cfg = DataPanels.db.panels["panel" .. i]
    local panel = frames[i]
    if not (active and cfg.enabled) then
        if not panel then return end
        UnregisterStateDriver(panel, "visibility")
        panel:Hide()
        NS.Movers:Unregister(MoverKey(i))
        for _, button in ipairs(panel.slots) do button.dataKey = nil end
        return
    end
    panel = panel or Build(i)
    local S = function(n) return NS.Pixel:Scale(n) end
    panel:SetSize(S(cfg.width), S(cfg.height))
    local c = NS.db.theme.backdrop
    NS.SetSolidColor(panel.bg, c.r, c.g, c.b, cfg.backgroundAlpha)
    local count = math.max(1, math.min(MAX_SLOTS, tonumber(cfg.slotCount) or 1))
    local width = S(cfg.width) / count
    for s, button in ipairs(panel.slots) do
        button:ClearAllPoints()
        if s <= count then
            button:SetSize(width, S(cfg.height))
            button:SetPoint("LEFT", panel, "LEFT", (s - 1) * width, 0)
            button.label:SetWidth(width - S(4))
            button.dataKey = cfg.slots["slot" .. s]
            button.elapsed = 0
            button:Show()
            UpdateSlot(button)
        else
            button.dataKey = nil
            button:Hide()
        end
    end
    local d = MOVER_DEFAULTS[i]
    NS.Movers:Register(MoverKey(i), panel, string.format(L.MOVER_DATAPANEL, i), d[1], d[2], d[3])
    NS.Movers:Load(MoverKey(i))
    if cfg.hideInCombat then
        RegisterStateDriver(panel, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(panel, "visibility")
        panel:Show()
    end
end

--- Événements : l'union de ceux des data texts affichés ; « UNIT_* » limités au joueur.
local function RegisterEvents()
    events:UnregisterAllEvents()
    byEvent = {}
    for _, panel in pairs(frames) do
        for _, button in ipairs(panel.slots) do
            local def = SlotDef(button)
            for _, event in ipairs(def and def.events or {}) do
                if not byEvent[event] then
                    byEvent[event] = {}
                    if event:find("^UNIT_") then NS.RegisterEventSafe(events, event, "player")
                    else NS.RegisterEventSafe(events, event) end
                end
                table.insert(byEvent[event], button)
            end
        end
    end
end

events:SetScript("OnEvent", function(_, event)
    if not active then return end
    for _, button in ipairs(byEvent[event] or {}) do UpdateSlot(button) end
end)

--- Minuterie : data texts à intervalle (coordonnées, vitesse, horloge…).
local function Tick()
    if not active then return end
    for _, panel in pairs(frames) do
        for _, button in ipairs(panel.slots) do
            local def = SlotDef(button)
            if def and def.interval then
                button.elapsed = button.elapsed + TICK
                if button.elapsed >= def.interval then
                    button.elapsed = 0
                    UpdateSlot(button)
                end
            end
        end
    end
end

function DataPanels:Reconcile()
    for i = 1, NUM_PANELS do Layout(i) end
    RegisterEvents()
end

function DataPanels:GetPanel(i) return frames[i] end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function DataPanels:OnEnable()
    active = true
    self:Reconcile()
    if not ticker then ticker = C_Timer.NewTicker(TICK, Tick) end
end

function DataPanels:OnDisable()
    active = false
    if ticker then ticker:Cancel() ticker = nil end
    self:Reconcile()   -- active = false : tout caché, movers retirés
    events:UnregisterAllEvents()
end

function DataPanels:OnRefresh() self:Reconcile() end

NS:On("PIXEL_CHANGED", function()
    if active then NS:RunOutOfCombat(function() if active then DataPanels:Reconcile() end end) end
end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function DataPanels:BuildOptions(o)
    o.layout:Note(L.NOTE_DATAPANELS, 20)
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
    local choices = function() return DataTexts:Choices(false) end
    for i = 1, NUM_PANELS do
        local key = "panels.panel" .. i .. "."
        o:Tab(string.format(L.OPT_DATAPANEL, i))
        o:Check(key .. "enabled", L.OPT_DATAPANEL_ENABLED)
        o:Slider(key .. "width", L.OPT_UF_WIDTH, 60, 1200, 10, 36)
        o:Slider(key .. "height", L.OPT_UF_HEIGHT, 14, 40, 1, 36)
        o:Slider(key .. "slotCount", L.OPT_DATAPANEL_SLOTS, 1, MAX_SLOTS, 1, 36)
        o:Slider(key .. "backgroundAlpha", L.OPT_TOPBAR_ALPHA, 0, 1, 0.05, 36, "%.2f")
        o:Check(key .. "hideInCombat", L.OPT_DATAPANEL_HIDE_COMBAT, 36)
        for s = 1, MAX_SLOTS do
            o:Dropdown(key .. "slots.slot" .. s, string.format(L.OPT_DATAPANEL_SLOT, s), choices, 36)
        end
    end
end
