-- Modules/Gear.lua
-- Fiche de personnage : niveau d'objet sur chaque emplacement (couleur de qualité),
-- niveau moyen, et repère sur les pièces enchantables sans enchantement.
-- Rien n'est calculé fenêtre fermée : mise à jour à l'ouverture et quand l'équipement change.
-- Inspection : mêmes niveaux sur la fenêtre d'inspection, et niveau moyen d'un joueur survolé dans
-- son infobulle (inspection demandée hors combat, résultat gardé deux minutes par GUID). La ligne
-- d'infobulle s'efface devant ElvUI, qui a la sienne.
local _, NS = ...
local L = NS.L
local Media = NS.Media

-- Emplacements affichés (chemise et tabard n'ont pas de niveau utile).
local SLOTS = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged",
}
-- Emplacements qu'un enchanteur Classic peut enchanter.
local ENCHANTABLE = {
    Head = true, Shoulder = true, Back = true, Chest = true, Wrist = true, Hands = true,
    Legs = true, Feet = true, MainHand = true,
}

local Gear = NS.Modules:Register("gear", {
    titleKey = "GEAR_TITLE",
    descKey = "GEAR_DESC",
    defaults = {
        enabled = true,
        itemLevel = true,
        average = true,
        missingEnchant = false,
        textSize = 11,
        inspect = true,         -- niveaux sur la fenêtre d'inspection
        tooltip = true,         -- niveau moyen d'un joueur dans son infobulle
    },
})

local INSPECT_CACHE_SECONDS = 120
local INSPECT_THROTTLE = 1.5
-- Emplacement -> identifiant d'inventaire (chemise 4 et tabard 19 exclus).
local SLOT_IDS = {
    Head = 1, Neck = 2, Shoulder = 3, Chest = 5, Waist = 6, Legs = 7, Feet = 8, Wrist = 9, Hands = 10,
    Finger0 = 11, Finger1 = 12, Trinket0 = 13, Trinket1 = 14, Back = 15, MainHand = 16,
    SecondaryHand = 17, Ranged = 18,
}

local active = false
local overlays = {}   -- [préfixe .. slot] = { level, enchant }
local averageText, inspectAverageText
local inspectCache = {}   -- [guid] = { level, time }
local pendingGUID, pendingUnit, lastRequest = nil, nil, -1000
local requesting = false   -- NotifyInspect lancé par ce module

local function Known(value)
    if NS.IsSecret(value) or value == nil then return nil end
    return value
end

--- Identifiant d'enchantement lu dans le lien : "item:ID:ENCHANT:…". 0 = aucun.
function Gear.EnchantID(link)
    local enchant = link and link:match("item:%d+:(%d*)")
    return tonumber(enchant) or 0
end

local function Overlay(slot, prefix)
    prefix = prefix or "Character"
    local entry = overlays[prefix .. slot]
    if entry then return entry end
    local button = _G[prefix .. slot .. "Slot"]
    if not button then return nil end
    entry = { button = button }
    -- Pas Media:CreateText : la taille vient du réglage du module, pas du thème.
    entry.level = button:CreateFontString(nil, "OVERLAY")
    entry.level:SetFont(Media:Font(), Gear.db.textSize, "OUTLINE")
    entry.level:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
    entry.enchant = Media:CreateText(button, "OVERLAY", 2, "OUTLINE")
    entry.enchant:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    entry.enchant:SetText("!")
    entry.enchant:SetTextColor(1, 0.25, 0.25)
    overlays[prefix .. slot] = entry
    return entry
end

--- Lien et qualité d'un emplacement d'une unité inspectée ; valeurs secrètes : nil.
local function UnitSlot(unit, slot)
    local id = SLOT_IDS[slot]
    local link = Known(GetInventoryItemLink(unit, id))
    if not link then return nil end
    return link, Known(_G.GetInventoryItemQuality and GetInventoryItemQuality(unit, id))
end

--- Niveau moyen des objets équipés d'une unité, et nombre d'emplacements encore sans lien
-- (objet pas encore en cache client). nil si rien n'est lisible.
-- ponytail: moyenne des objets portés, arme à deux mains comptée une fois ; règle Blizzard exacte
-- (deux mains doublée, diviseur fixe) si l'écart gêne.
function Gear.UnitAverage(unit)
    local total, count, missing = 0, 0, 0
    for slot, id in pairs(SLOT_IDS) do
        local link = UnitSlot(unit, slot)
        local level = link and Known(NS.GetItemLevel(link))
        if level then
            total, count = total + level, count + 1
        elseif link or (_G.GetInventoryItemTexture and Known(GetInventoryItemTexture(unit, id))) then
            -- Lien sans niveau (objet hors cache client) ou objet porté sans lien encore
            missing = missing + 1
        end
    end
    if count == 0 then return nil, missing end
    return total / count, missing
end

function Gear:Update()
    local db = self.db
    local total, count = 0, 0
    for _, slot in ipairs(SLOTS) do
        local entry = Overlay(slot)
        if entry then
            local link, quality
            if active then link, quality = NS.GetEquipped(slot) end
            local level = link and NS.GetItemLevel(link)
            if level and db.itemLevel then
                entry.level:SetFont(Media:Font(), db.textSize, "OUTLINE")
                entry.level:SetText(tostring(level))
                entry.level:SetTextColor(NS.QualityColor(quality))
                entry.level:Show()
            else
                entry.level:Hide()
            end
            local missing = active and db.missingEnchant and link and ENCHANTABLE[slot] and Gear.EnchantID(link) == 0
            entry.enchant:SetShown(missing and true or false)
            if level then total, count = total + level, count + 1 end
        end
    end
    if averageText then
        local average = NS.GetAverageItemLevel()
        if not average and count > 0 then average = total / count end
        if active and db.average and average and average > 0 then
            averageText:SetText(string.format(L.GEAR_AVERAGE, average))
            averageText:Show()
        else
            averageText:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Inspection
--------------------------------------------------------------------------------

function Gear:UpdateInspect()
    local frame = _G.InspectFrame
    local unit = frame and frame:IsShown() and Known(frame.unit)
    local show = active and self.db.inspect and unit
    for _, slot in ipairs(SLOTS) do
        local entry = Overlay(slot, "Inspect")
        if entry then
            local link, quality
            if show then link, quality = UnitSlot(unit, slot) end
            local level = link and Known(NS.GetItemLevel(link))
            if level then
                entry.level:SetFont(Media:Font(), self.db.textSize, "OUTLINE")
                entry.level:SetText(tostring(level))
                entry.level:SetTextColor(NS.QualityColor(quality))
                entry.level:Show()
            else
                entry.level:Hide()
            end
            local missing = show and self.db.missingEnchant and link and ENCHANTABLE[slot] and Gear.EnchantID(link) == 0
            entry.enchant:SetShown(missing and true or false)
        end
    end
    if not frame then return end
    if not inspectAverageText then
        inspectAverageText = Media:CreateText(frame, "OVERLAY", 0, "OUTLINE")
        inspectAverageText:SetPoint("TOP", frame, "TOP", 0, -40)
    end
    local average, missing
    if show and self.db.average then average, missing = Gear.UnitAverage(unit) end
    if average and missing == 0 then
        inspectAverageText:SetText(string.format(L.GEAR_AVERAGE, average))
        inspectAverageText:Show()
    else
        inspectAverageText:Hide()
    end
end

--- Niveau moyen connu pour ce GUID (cache frais), sinon nil.
function Gear.CachedLevel(guid)
    local entry = inspectCache[guid]
    if entry and GetTime() - entry.time < INSPECT_CACHE_SECONDS then return entry.level end
    return nil
end

local function ElvUILoaded()
    local api = _G.C_AddOns and C_AddOns.IsAddOnLoaded
    if not api then return false end
    local ok, loaded = pcall(api, "ElvUI")
    return ok and loaded == true
end

--- Ligne « niveau d'objet » d'un joueur survolé ; inspection demandée si le cache est vide.
function Gear.OnTooltipUnit(tooltip)
    if not (active and Gear.db.tooltip) or ElvUILoaded() then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local unit = NS.TooltipUnit(tooltip)
    unit = Known(unit)
    if not unit or NS.IsSecretUnit(unit) then return end
    local isPlayer = UnitIsPlayer(unit)
    if NS.IsSecret(isPlayer) or not isPlayer then return end
    local guid = Known(UnitGUID(unit))
    if not guid then return end
    local level
    local isSelf = UnitIsUnit(unit, "player")
    if not NS.IsSecret(isSelf) and isSelf then
        local average = NS.GetAverageItemLevel()
        if average and average > 0 then level = average else level = Gear.UnitAverage("player") end
    else
        level = Gear.CachedLevel(guid)
    end
    if level then
        tooltip:AddLine(string.format(L.TOOLTIP_ITEM_LEVEL, level), 1, 0.82, 0)
        tooltip:Show()
        return
    end
    local inspectOpen = _G.InspectFrame and InspectFrame:IsShown()
    if NS.InCombat() or inspectOpen or not (_G.NotifyInspect and _G.CanInspect) then return end
    local canInspect = CanInspect(unit)
    if NS.IsSecret(canInspect) or not canInspect or GetTime() - lastRequest < INSPECT_THROTTLE then return end
    lastRequest, pendingGUID, pendingUnit = GetTime(), guid, unit
    requesting = true
    NotifyInspect(unit)
    requesting = false
end

local function OnInspectReady(guid)
    if NS.IsSecret(guid) then return end
    if guid == pendingGUID and pendingUnit and Known(UnitGUID(pendingUnit)) == guid then
        local level, missing = Gear.UnitAverage(pendingUnit)
        -- Objets pas encore en cache : pas de mémorisation, le prochain survol redemande.
        if level and missing == 0 then inspectCache[guid] = { level = level, time = GetTime() } end
        pendingGUID = nil
        -- Ligne ajoutée directement : un SetUnit depuis l'addon rejouerait l'infobulle Blizzard teintée.
        local unit = NS.TooltipUnit(GameTooltip)
        unit = Known(unit)
        if level and missing == 0 and unit and not NS.InCombat() and Known(UnitGUID(unit)) == guid then
            GameTooltip:AddLine(string.format(L.TOOLTIP_ITEM_LEVEL, level), 1, 0.82, 0)
            GameTooltip:Show()
        end
    end
    -- La fenêtre d'inspection s'affiche sur le même événement : mise à jour à l'image suivante.
    C_Timer.After(0, function() Gear:UpdateInspect() end)
end

local tooltipHooked = false
local function HookTooltip()
    if tooltipHooked then return end
    tooltipHooked = true
    -- Inspection demandée ailleurs (fenêtre Blizzard, autre addon) : on lui laisse la main.
    if _G.NotifyInspect then
        hooksecurefunc("NotifyInspect", function()
            if not requesting then lastRequest, pendingGUID = GetTime() + 3, nil end
        end)
    end
    if _G.TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            if tooltip == GameTooltip then Gear.OnTooltipUnit(tooltip) end
        end)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", Gear.OnTooltipUnit)
    end
end

local hooked = false
local function Hook()
    if hooked then return end
    local frame = _G.PaperDollFrame or _G.CharacterFrame
    if not frame then return end
    hooked = true
    frame:HookScript("OnShow", function() if active then Gear:Update() end end)
    local parent = _G.CharacterFrame or frame
    averageText = Media:CreateText(parent, "OVERLAY", 0, "OUTLINE")
    averageText:SetPoint("TOP", parent, "TOP", 0, -40)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_READY" then OnInspectReady(arg1) return end
    local frame = _G.PaperDollFrame or _G.CharacterFrame
    if frame and frame:IsVisible() then Gear:Update() end
end)

function Gear:OnEnable()
    active = true
    Hook()
    NS.RegisterEventSafe(events, "PLAYER_EQUIPMENT_CHANGED")
    NS.RegisterEventSafe(events, "UNIT_INVENTORY_CHANGED", "player")
    NS.RegisterEventSafe(events, "INSPECT_READY")
    HookTooltip()
    self:Update()
end

function Gear:OnDisable()
    active = false
    events:UnregisterAllEvents()
    self:Update()   -- active = false : tout se cache
    self:UpdateInspect()
end

function Gear:OnRefresh()
    self:Update()
    self:UpdateInspect()
end

function Gear:BuildOptions(o)
    o:Check("itemLevel", L.OPT_GEAR_ITEM_LEVEL)
    o:Check("average", L.OPT_GEAR_AVERAGE)
    o:Check("missingEnchant", L.OPT_GEAR_ENCHANT)
    o:Slider("textSize", L.OPT_GEAR_TEXT_SIZE, 6, 20, 1)
    o:Check("inspect", L.OPT_GEAR_INSPECT)
    o:Check("tooltip", L.OPT_GEAR_TOOLTIP)
end
