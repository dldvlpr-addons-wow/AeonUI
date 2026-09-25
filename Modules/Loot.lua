-- Modules/Loot.lua
-- Butin AeonUI : fenêtre de butin au thème (au curseur ou sur son mover) et barres de jets de
-- groupe (besoin, cupidité, désenchantement, passer) avec le temps restant.
--
-- Blizzard : la fenêtre LootFrame et l'ouverture des GroupLootFrame (UIParent, START_LOOT_ROLL)
-- sont coupées de leurs événements tant que le module est actif, et les retrouvent à la coupure.
-- La confirmation d'un objet lié (CONFIRM_LOOT_ROLL, CONFIRM_LOOT_SLOT) reste à Blizzard.
-- Maître du butin : le clic prépare les champs que MasterLooterFrame lit sur LootFrame (seulement
-- quand le joueur l'est), puis la liste Blizzard s'ouvre (OPEN_MASTER_LOOT_LIST). Cède à ElvUI.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local Loot = NS.Modules:Register("loot", {
    titleKey = "LOOT_TITLE",
    descKey = "LOOT_DESC",
    yieldsTo = { "ElvUI" },
    defaults = {
        enabled = false,
        window = true,          -- fenêtre de butin AeonUI
        atCursor = true,        -- s'ouvre sous le curseur (sinon sur le mover « loot »)
        rolls = true,           -- barres de jets de groupe
        rollWidth = 300,
    },
})

local LOOT_EVENTS = { "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED",
                      "OPEN_MASTER_LOOT_LIST", "UPDATE_MASTER_LOOT_LIST" }
local SLOT_HEIGHT = 30
local WINDOW_WIDTH = 220
local ROLL_HEIGHT = 26
-- RollOnLoot : 0 passer, 1 besoin, 2 cupidité, 3 désenchanter.
local ROLL_BUTTONS = {
    { type = 1, key = "need", texture = "Interface\\Buttons\\UI-GroupLoot-Dice-Up" },
    { type = 2, key = "greed", texture = "Interface\\Buttons\\UI-GroupLoot-Coin-Up" },
    { type = 3, key = "disenchant", texture = "Interface\\Buttons\\UI-GroupLoot-DE-Up" },
    { type = 0, key = "pass", texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
}

local active = false
local window, rollAnchor
local rollBars = {}             -- pool de barres
local blizzardLoot = {}         -- événements retirés à LootFrame
local rollEventTaken = false    -- START_LOOT_ROLL retiré à UIParent
local events = CreateFrame("Frame")
local closing = false           -- LOOT_CLOSED en cours : OnHide ne rappelle pas CloseLoot

local function Known(value)
    if NS.IsSecret(value) or value == nil then return nil end
    return value
end

local function S(n) return NS.Pixel:Scale(n) end

--------------------------------------------------------------------------------
-- Fenêtre de butin
--------------------------------------------------------------------------------

--- Contenu d'un emplacement : icône, nom, quantité, qualité, objet de quête.
function Loot.SlotInfo(slot)
    if not _G.GetLootSlotInfo then return nil end
    local texture, name, quantity, _, quality, _, isQuestItem = GetLootSlotInfo(slot)
    if NS.IsSecret(texture) or texture == nil then return nil end
    return texture, Known(name) or "", Known(quantity) or 1, Known(quality), Known(isQuestItem) == true
end

local function SlotButton(index)
    window.slots = window.slots or {}
    local button = window.slots[index]
    if button then return button end
    button = CreateFrame("Button", nil, window)
    button:SetHeight(S(SLOT_HEIGHT))
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.iconFrame = CreateFrame("Frame", nil, button)
    button.iconFrame:SetSize(S(SLOT_HEIGHT - 4), S(SLOT_HEIGHT - 4))
    button.iconFrame:SetPoint("LEFT", button, "LEFT", S(2), 0)
    local _, edges = Media:CreateBackdrop(button.iconFrame)
    button.iconBorder = edges
    button.icon = button.iconFrame:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button.iconFrame)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.count = Media:CreateText(button.iconFrame, "OVERLAY", -2, "OUTLINE")
    button.count:SetPoint("BOTTOMRIGHT", button.iconFrame, "BOTTOMRIGHT", 0, 0)
    button.name = Media:CreateText(button, "OVERLAY")
    button.name:SetPoint("LEFT", button.iconFrame, "RIGHT", S(6), 0)
    button.name:SetPoint("RIGHT", button, "RIGHT", -S(4), 0)
    button.name:SetJustifyH("LEFT")
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    NS.SetSolidColor(button.highlight, 1, 1, 1, 0.1)
    button:SetScript("OnEnter", function(self)
        if not self.slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetLootItem then GameTooltip:SetLootItem(self.slot) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self)
        if not self.slot then return end
        if _G.IsModifiedClick and IsModifiedClick() and _G.GetLootSlotLink and _G.HandleModifiedItemClick then
            HandleModifiedItemClick(GetLootSlotLink(self.slot))   -- lier dans le chat, essayer
            return
        end
        -- Maître du butin : MasterLooterFrame lit ces champs sur LootFrame. Écrits seulement dans
        -- ce cas (ou si le client ne sait pas le dire) : une table Blizzard écrite par un addon est
        -- contaminée, inutile de le faire à chaque butin.
        local lootFrame = _G.LootFrame
        if lootFrame and NS.IsMasterLooter() ~= false then
            lootFrame.selectedSlot, lootFrame.selectedQuality = self.slot, self.quality
            lootFrame.selectedItemName, lootFrame.selectedTexture = self.itemName, self.texture
            lootFrame.selectedLootButton = self
        end
        if _G.LootSlot then LootSlot(self.slot) end
    end)
    window.slots[index] = button
    return button
end

local function BuildWindow()
    window = CreateFrame("Frame", "AeonUILootFrame", UIParent)
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    Media:CreateBackdrop(window)
    window.title = Media:CreateText(window, "OVERLAY")
    window.title:SetPoint("TOPLEFT", window, "TOPLEFT", S(6), -S(4))
    window.close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    window.close:SetSize(S(20), S(20))
    window.close:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
    window:SetScript("OnHide", function()
        if not closing and _G.CloseLoot then CloseLoot() end   -- Échap ou croix : fermer le butin
    end)
    window:Hide()
    tinsert(UISpecialFrames, "AeonUILootFrame")
end

local function RegisterWindowMover()
    NS.Movers:Register("loot", window, L.MOVER_LOOT, "LEFT", 300, 100)
    NS.Movers:Load("loot")
end

--- Place la fenêtre : sous le curseur, ou sur son mover.
local function PlaceWindow()
    if Loot.db.atCursor then
        NS.Movers:Unregister("loot")
        local x, y = GetCursorPosition()
        local scale = window:GetEffectiveScale()
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - S(30), y / scale + S(20))
    else
        RegisterWindowMover()
    end
end

--- Remplit la fenêtre ; `place` la replace (ouverture seulement, pas à chaque changement).
function Loot:OpenWindow(place)
    if not window then BuildWindow() end
    local count = _G.GetNumLootItems and GetNumLootItems() or 0
    local shown = 0
    for slot = 1, count do
        local texture, name, quantity, quality, quest = Loot.SlotInfo(slot)
        if texture then
            shown = shown + 1
            local button = SlotButton(shown)
            button.slot, button.quality, button.itemName, button.texture = slot, quality, name, texture
            button.icon:SetTexture(texture)
            button.count:SetText(quantity > 1 and quantity or "")
            local r, g, b = NS.QualityColor(quality)
            button.name:SetText(name)
            button.name:SetTextColor(r, g, b)
            if quest then r, g, b = 1, 0.82, 0 end   -- objet de quête : bordure dorée
            for _, edge in pairs(button.iconBorder) do NS.SetSolidColor(edge, r, g, b, 1) end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", window, "TOPLEFT", S(4), -S(22) - (shown - 1) * S(SLOT_HEIGHT))
            button:SetPoint("RIGHT", window, "RIGHT", -S(4), 0)
            button:Show()
        end
    end
    for i = shown + 1, #(window.slots or {}) do
        window.slots[i].slot = nil
        window.slots[i]:Hide()
    end
    if shown == 0 then
        window:Hide()   -- OnHide : CloseLoot, le corps n'est pas bloqué pour le groupe
        return
    end
    window.title:SetText(L.LOOT_WINDOW_TITLE)
    window:SetSize(S(WINDOW_WIDTH), S(26) + shown * S(SLOT_HEIGHT))
    if place or not window:IsShown() then PlaceWindow() end
    window:Show()
end

local function ClearSlot(slot)
    for _, button in ipairs(window and window.slots or {}) do
        if button.slot == slot then
            button.slot = nil
            button.icon:SetTexture(nil)
            button.name:SetText("")
            button.count:SetText("")
            button:Hide()
        end
    end
end

local function CloseWindow()
    if not window then return end
    closing = true
    window:Hide()
    closing = false
end

--------------------------------------------------------------------------------
-- Jets de groupe
--------------------------------------------------------------------------------

local function RollTooltip(icon)
    local bar = icon:GetParent()
    if not bar.rollID then return end
    GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
    if GameTooltip.SetLootRollItem then GameTooltip:SetLootRollItem(bar.rollID) end
    GameTooltip:Show()
end

local function LayoutRolls()
    local shown = 0
    for _, bar in ipairs(rollBars) do
        if bar.rollID then
            bar:ClearAllPoints()
            bar:SetPoint("TOP", rollAnchor, "TOP", 0, -shown * S(ROLL_HEIGHT + 4))
            shown = shown + 1
        end
    end
end

local function HideRoll(bar)
    bar.rollID = nil
    bar:Hide()
    LayoutRolls()
end

local function RollOnUpdate(bar)
    if not bar.rollID or not _G.GetLootRollTimeLeft then return end
    local left = Known(GetLootRollTimeLeft(bar.rollID))
    if left then bar.timer:SetValue(left) end
end

local function RollBar()
    for _, bar in ipairs(rollBars) do
        if not bar.rollID then return bar end
    end
    local bar = CreateFrame("Frame", nil, rollAnchor)
    Media:CreateBackdrop(bar)
    bar.iconButton = CreateFrame("Button", nil, bar)
    bar.iconButton:SetPoint("RIGHT", bar, "LEFT", -S(4), 0)
    Media:CreateBackdrop(bar.iconButton)
    bar.icon = bar.iconButton:CreateTexture(nil, "ARTWORK")
    bar.icon:SetAllPoints(bar.iconButton)
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.iconButton:SetScript("OnEnter", RollTooltip)
    bar.iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.timer = Media:CreateStatusBar(bar)
    bar.timer:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    bar.timer:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
    bar.name = Media:CreateText(bar.timer, "OVERLAY")
    bar.name:SetPoint("LEFT", bar.timer, "LEFT", S(4), 0)
    bar.name:SetJustifyH("LEFT")
    bar.buttons = {}
    local previous
    for i = #ROLL_BUTTONS, 1, -1 do
        local def = ROLL_BUTTONS[i]
        local button = CreateFrame("Button", nil, bar.timer)
        button.rollType = def.type
        button:SetNormalTexture(def.texture)
        button:SetSize(S(ROLL_HEIGHT - 4), S(ROLL_HEIGHT - 4))
        if previous then button:SetPoint("RIGHT", previous, "LEFT", -S(2), 0)
        else button:SetPoint("RIGHT", bar.timer, "RIGHT", -S(2), 0) end
        button:SetScript("OnClick", function(self)
            local rollID = bar.rollID
            if not rollID or not _G.RollOnLoot then return end
            RollOnLoot(rollID, self.rollType)   -- barre retirée par CANCEL_LOOT_ROLL (confirmation possible)
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["LOOT_ROLL_" .. def.key:upper()])
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.buttons[def.key] = button
        previous = button
    end
    bar.name:SetPoint("RIGHT", previous, "LEFT", -S(4), 0)
    bar:SetScript("OnUpdate", RollOnUpdate)
    rollBars[#rollBars + 1] = bar
    return bar
end

function Loot:StartRoll(rollID, rollTime)
    if not _G.GetLootRollItemInfo then return end
    local texture, name, count, quality, _, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
    if NS.IsSecret(texture) or texture == nil then return end
    local bar = RollBar()
    bar.rollID = rollID
    bar:SetSize(S(self.db.rollWidth), S(ROLL_HEIGHT))
    bar.iconButton:SetSize(S(ROLL_HEIGHT), S(ROLL_HEIGHT))
    bar.icon:SetTexture(texture)
    count = Known(count) or 1
    bar.name:SetText((Known(name) or "") .. (count > 1 and (" x" .. count) or ""))
    local r, g, b = NS.QualityColor(Known(quality))
    bar.timer:SetStatusBarColor(r, g, b)
    local duration = Known(rollTime) or 60000
    bar.timer:SetMinMaxValues(0, duration)
    bar.timer:SetValue(duration)
    -- Un choix refusé par le client reste visible mais grisé.
    local allowed = { need = Known(canNeed) ~= false, greed = Known(canGreed) ~= false,
                      disenchant = Known(canDisenchant) == true, pass = true }
    for key, button in pairs(bar.buttons) do
        if allowed[key] then button:Enable() button:SetAlpha(1) else button:Disable() button:SetAlpha(0.3) end
    end
    bar:Show()
    LayoutRolls()
end

function Loot:CancelRoll(rollID)
    for _, bar in ipairs(rollBars) do
        if bar.rollID == rollID then HideRoll(bar) end
    end
end

--------------------------------------------------------------------------------
-- Blizzard : prise et restitution des événements
--------------------------------------------------------------------------------

local function TakeBlizzard()
    local db = Loot.db
    local lootFrame = _G.LootFrame
    if db.window and lootFrame and not next(blizzardLoot) then
        for _, event in ipairs(LOOT_EVENTS) do
            if not lootFrame.IsEventRegistered or lootFrame:IsEventRegistered(event) then
                lootFrame:UnregisterEvent(event)
                blizzardLoot[event] = true
            end
        end
    end
    if db.rolls and not rollEventTaken and UIParent:IsEventRegistered("START_LOOT_ROLL") then
        UIParent:UnregisterEvent("START_LOOT_ROLL")
        rollEventTaken = true
    end
end

local function RestoreBlizzard()
    local lootFrame = _G.LootFrame
    for event in pairs(blizzardLoot) do
        if lootFrame then NS.RegisterEventSafe(lootFrame, event) end
        blizzardLoot[event] = nil
    end
    if rollEventTaken then
        UIParent:RegisterEvent("START_LOOT_ROLL")
        rollEventTaken = false
    end
end

--------------------------------------------------------------------------------
-- Événements
--------------------------------------------------------------------------------

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not active then return end
    local db = Loot.db
    if event == "START_LOOT_ROLL" then
        if db.rolls then Loot:StartRoll(arg1, arg2) end
    elseif event == "CANCEL_LOOT_ROLL" then
        Loot:CancelRoll(arg1)
    elseif not db.window then
        return
    elseif event == "LOOT_OPENED" then
        Loot:OpenWindow(true)
        -- Rien d'affichable : fermer le butin, comme Blizzard, sinon le corps reste bloqué.
        if not (window and window:IsShown()) and _G.CloseLoot then CloseLoot() end
    elseif event == "LOOT_SLOT_CLEARED" then
        ClearSlot(arg1)
    elseif event == "LOOT_SLOT_CHANGED" then
        Loot:OpenWindow()
    elseif event == "LOOT_CLOSED" then
        CloseWindow()
    elseif event == "OPEN_MASTER_LOOT_LIST" then
        if _G.MasterLooterFrame_Show and _G.LootFrame then
            pcall(MasterLooterFrame_Show, LootFrame.selectedLootButton)
        end
    elseif event == "UPDATE_MASTER_LOOT_LIST" then
        if _G.MasterLooterFrame_UpdatePlayers then pcall(MasterLooterFrame_UpdatePlayers) end
    end
end)

function Loot:Reconcile()
    RestoreBlizzard()
    events:UnregisterAllEvents()
    if not active then return end
    TakeBlizzard()
    if self.db.window then
        for _, event in ipairs(LOOT_EVENTS) do NS.RegisterEventSafe(events, event) end
        if not self.db.atCursor then
            if not window then BuildWindow() end
            RegisterWindowMover()   -- mover disponible avant le premier butin
        end
    elseif window then
        window:Hide()   -- OnHide : CloseLoot, pas de butin ouvert sans fenêtre
    end
    if not rollAnchor then
        rollAnchor = CreateFrame("Frame", "AeonUILootRolls", UIParent)
        rollAnchor:SetFrameStrata("HIGH")
    end
    rollAnchor:SetSize(S(self.db.rollWidth), S(ROLL_HEIGHT))
    if self.db.rolls then
        NS.Movers:Register("lootroll", rollAnchor, L.MOVER_LOOT_ROLL, "TOP", 0, -220)
        NS.Movers:Load("lootroll")
        NS.RegisterEventSafe(events, "START_LOOT_ROLL")
        NS.RegisterEventSafe(events, "CANCEL_LOOT_ROLL")
    else
        NS.Movers:Unregister("lootroll")
        for _, bar in ipairs(rollBars) do HideRoll(bar) end
    end
end

function Loot:GetFrames() return window, rollAnchor, rollBars end

function Loot:OnEnable()
    active = true
    self:Reconcile()
end

function Loot:OnDisable()
    active = false
    if window then window:Hide() end   -- OnHide : CloseLoot
    for _, bar in ipairs(rollBars) do HideRoll(bar) end
    NS.Movers:Unregister("loot")
    NS.Movers:Unregister("lootroll")
    self:Reconcile()   -- active = false : événements rendus à Blizzard
end

function Loot:OnRefresh() self:Reconcile() end

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function Loot:BuildOptions(o)
    o:Check("window", L.OPT_LOOT_WINDOW)
    o:Check("atCursor", L.OPT_LOOT_AT_CURSOR, 36)
    o:Check("rolls", L.OPT_LOOT_ROLLS)
    o:Slider("rollWidth", L.OPT_UF_WIDTH, 200, 500, 10, 36)
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
end
