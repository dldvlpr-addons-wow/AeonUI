-- Modules/DataPanels.lua
-- Panneaux de données : jusqu'à douze bandeaux libres (panelCount), chacun sur son mover, découpés en
-- emplacements de largeur égale (un seul emplacement : un bloc libre). Chaque emplacement montre
-- un data text du registre NS.DataTexts (ceux de la barre du haut, plus coordonnées, quêtes,
-- régénération, vitesse, DPS, LibDataBroker…). Maj + glisser un emplacement sur un autre, d'un
-- panneau à l'autre compris, échange leurs textes.
--
-- Module `secure` : le masquage en combat passe par un state driver, interdit à poser ou retirer
-- en combat ; réglages, activation et agencement attendent donc la sortie du combat. Les textes,
-- eux, suivent événements et minuterie en combat. Largeurs fixes : un texte secret (DPS du
-- compteur natif) s'affiche sans que sa largeur soit mesurée.
local _, NS = ...
local L = NS.L
local Media = NS.Media
local DataTexts = NS.DataTexts

local MAX_PANELS = 12       -- réglage panelCount ; au-delà des six par défaut, créés à la demande (taille de l'export)
local MAX_SLOTS = 10
local TICK = 0.5

-- Clés chaînes (panel1, slot1…) : l'export de profil et le miroir CVar n'aplatissent que celles-là.
local function Panel(enabled, keys)
    local slots = {}
    for s = 1, MAX_SLOTS do slots["slot" .. s] = keys[s] or "none" end
    return {
        enabled = enabled, width = 360, height = 22, slotCount = #keys,
        backgroundAlpha = 0.75, slots = slots,
        visibility = NS.Visibility.Spec(),   -- conditions communes (Core/Visibility)
    }
end

local DataPanels = NS.Modules:Register("datapanels", {
    titleKey = "DATAPANELS_TITLE",
    descKey = "DATAPANELS_DESC",
    secure = true,
    defaults = {
        enabled = false,
        panelCount = 6,           -- panneaux proposés (1 à MAX_PANELS) ; chacun reste activable
        panels = {
            panel1 = Panel(true, { "coords", "speed", "regen", "quests" }),
            panel2 = Panel(false, { "gold", "durability", "bags" }),
            panel3 = Panel(false, { "dps", "perf" }),
            panel4 = Panel(false, { "clock" }),
            panel5 = Panel(false, { "itemlevel" }),
            panel6 = Panel(false, { "combat" }),
        },
    },
})

local MOVER_DEFAULTS = {
    { "BOTTOMLEFT", 380, 4 },
    { "BOTTOMRIGHT", -380, 4 },
    { "TOPLEFT", 20, -40 },
    { "TOPRIGHT", -20, -40 },
    { "LEFT", 20, 0 },
    { "RIGHT", -20, 0 },
}
-- Panneaux ajoutés : empilés au centre, à déplacer ensuite.
for i = #MOVER_DEFAULTS + 1, MAX_PANELS do MOVER_DEFAULTS[i] = { "CENTER", 0, 180 - (i - 7) * 30 } end

local DEFAULT_PANELS = 6   -- panel1 à panel6 dans les défauts ; les suivants créés à la demande

--- Nombre de panneaux proposés, borné. `db` : réglages lus (par défaut ceux du module).
local function Count(db)
    db = db or DataPanels.db
    return math.max(1, math.min(MAX_PANELS, math.floor(tonumber(db.panelCount) or DEFAULT_PANELS)))
end

--- Réglages du panneau `i`, créés (ou complétés, profil importé) au-delà des six par défaut.
local function PanelConfig(i, db)
    local panels = (db or DataPanels.db).panels
    local key = "panel" .. i
    if type(panels[key]) ~= "table" then panels[key] = {} end
    NS.Database.MergeDefaults(Panel(false, { "none" }), panels[key])
    return panels[key]
end

-- Défauts des panneaux ajoutés, pour le miroir (Database:MirrorTable) : ce qui vaut le défaut
-- n'y est pas écrit. Hors des `defaults` : l'export complet du profil les écrirait tous.
DataPanels.mirrorDefaults = NS.Database.DeepCopy(DataPanels.defaults)
for i = DEFAULT_PANELS + 1, MAX_PANELS do DataPanels.mirrorDefaults.panels["panel" .. i] = Panel(false, { "none" }) end

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

--------------------------------------------------------------------------------
-- Glisser-déposer : Maj + glisser un emplacement sur un autre échange leurs textes
--------------------------------------------------------------------------------

local dragSource

local function FocusedSlot()
    local foci = _G.GetMouseFoci and GetMouseFoci()
    local focus = (foci and foci[1]) or (_G.GetMouseFocus and GetMouseFocus())
    return type(focus) == "table" and focus.slotIndex and focus or nil
end

--- Échange les textes de deux emplacements (panneaux différents compris) ; false sinon.
function DataPanels.SwapSlots(source, target)
    if not (source and target and source.slotIndex and target.slotIndex) or source == target then return false end
    local a, b = PanelConfig(source.panelIndex).slots, PanelConfig(target.panelIndex).slots
    local keyA, keyB = "slot" .. source.slotIndex, "slot" .. target.slotIndex
    a[keyA], b[keyB] = b[keyB], a[keyA]
    NS:RunOutOfCombat(function() if active then DataPanels:Reconcile() end end)
    return true
end

local function NewSlot(panel)
    local button = CreateFrame("Button", nil, panel)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        if not IsShiftKeyDown() then return end
        dragSource = self
        self.label:SetAlpha(0.4)
    end)
    button:SetScript("OnDragStop", function()
        local source = dragSource
        if not source then return end
        dragSource = nil
        source.label:SetAlpha(1)
        DataPanels.SwapSlots(source, FocusedSlot())
    end)
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
    local cfg = i <= Count() and PanelConfig(i) or nil
    local panel = frames[i]
    if not (active and cfg and cfg.enabled) then
        if not panel then return end
        NS.Visibility:Unregister(MoverKey(i))
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
            button.panelIndex, button.slotIndex = i, s
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
    panel:Show()
    NS.Visibility:Register(MoverKey(i), panel, function() return PanelConfig(i).visibility end,
        { secure = true, forceVisible = function() return NS.unlocked end })
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
    for i = 1, MAX_PANELS do Layout(i) end   -- au-delà de Count() : cachés s'ils existent
    -- Panneaux retirés au-delà des six par défaut : réglages effacés (taille du profil exporté).
    for i = math.max(Count(), DEFAULT_PANELS) + 1, MAX_PANELS do self.db.panels["panel" .. i] = nil end
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
    o.layout:Note(L.NOTE_DATAPANELS_DRAG, 20)
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
    local choices = function() return DataTexts:Choices(false) end
    -- Un seul jeu de widgets qui suit le panneau choisi : pas une page à reconstruire quand le
    -- nombre de panneaux change.
    local editing = 1
    -- Réglages de la page (o:DB()) : au changement de profil, DataPanels.db suit un peu plus tard.
    local function Editing()
        editing = math.min(editing, Count(o:DB()))
        PanelConfig(editing, o:DB())
        return editing
    end
    NS.Database.bounds["modules.datapanels.panelCount"] = { 1, MAX_PANELS }
    o.layout:Slider(L.OPT_DATAPANEL_COUNT, 1, MAX_PANELS, 1, o:Getter("panelCount"),
        o:Setter("panelCount", function() o.layout:Refresh() end), 20)
    o.layout:Dropdown(L.OPT_DATAPANEL_EDITING, function()
            local list = {}
            for i = 1, Count() do list[i] = { name = string.format(L.OPT_DATAPANEL, i), value = i } end
            return list
        end,
        Editing, function(value) editing = value o.layout:Refresh() end, 20)
    local function Key(suffix) return function() return "panels.panel" .. Editing() .. "." .. suffix end end
    o:Check(Key("enabled"), L.OPT_DATAPANEL_ENABLED)
    o:Slider(Key("width"), L.OPT_UF_WIDTH, 60, 1200, 10, 36)
    o:Slider(Key("height"), L.OPT_UF_HEIGHT, 14, 40, 1, 36)
    o:Slider(Key("slotCount"), L.OPT_DATAPANEL_SLOTS, 1, MAX_SLOTS, 1, 36)
    o:Advanced()
    o:Slider(Key("backgroundAlpha"), L.OPT_TOPBAR_ALPHA, 0, 1, 0.05, 36, "%.2f")
    o:EndAdvanced()
    for s = 1, MAX_SLOTS do
        o:Dropdown(Key("slots.slot" .. s), string.format(L.OPT_DATAPANEL_SLOT, s), choices, 36)
    end
    o:Visibility(Key("visibility"), L.OPT_VISIBILITY, { secure = true })
end

-- Bornes gardées pour l'import (les curseurs à clé calculée ne les posent pas eux-mêmes).
for i = 1, MAX_PANELS do
    local prefix = "modules.datapanels.panels.panel" .. i .. "."
    NS.Database.bounds[prefix .. "width"] = { 60, 1200 }
    NS.Database.bounds[prefix .. "height"] = { 14, 40 }
    NS.Database.bounds[prefix .. "slotCount"] = { 1, MAX_SLOTS }
    NS.Database.bounds[prefix .. "backgroundAlpha"] = { 0, 1 }
end
