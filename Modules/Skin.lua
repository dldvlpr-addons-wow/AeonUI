-- Modules/Skin.lua
-- Habillage léger et réversible :
--   * infobulles sombres, nom et bordure à la couleur de classe pour les joueurs ;
--   * infobulles au curseur, cible de l'unité, rang de guilde, identifiants, barre de vie masquable ;
--   * masquer en combat les infobulles d'unité, ou toutes les infobulles ;
--   * icônes d'aura (buffs du joueur) et du gestionnaire de temps de recharge recadrées :
--     on retire le liseré intégré aux icônes Blizzard (zoom réglable) ;
--   * fiche de personnage et fenêtre d'amis au thème : art Blizzard effacé (alpha 0, rendu
--     au décochage), fond plat et bordure 1 px, emplacements d'équipement
--     recadrés avec une bordure à la couleur de qualité.
-- Blizzard réapplique le fond des infobulles à chaque affichage : on repasse derrière
-- (hooks), et au disable on rend le style d'origine. Les hooks ne se retirent pas,
-- d'où le test `active` en tête de chacun.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local BACKGROUND = { 0.05, 0.06, 0.08, 0.94 }

local Skin = NS.Modules:Register("skin", {
    titleKey = "SKIN_TITLE",
    descKey = "SKIN_DESC",
    yieldsTo = { "ElvUI" },   -- ElvUI remplace ces cadres : le module cède sans toucher au réglage
    defaults = {
        enabled = true,
        tooltips = true,
        classColors = true,
        hideUnitTooltipInCombat = false,
        hideAllTooltipsInCombat = false,
        iconZoom = true,
        iconZoomAmount = 8,        -- en % de chaque bord (0-20)
        darkPanels = false,        -- panneaux Blizzard (personnage, grimoire, marchand…) assombris
        skinWindows = false,       -- fiche de personnage et amis : fond plat du thème
        anchorCursor = false,      -- infobulles par défaut (monde, cadres) collées au curseur
        tooltipTarget = true,      -- ligne « Cible : » sur les infobulles d'unité
        guildRank = true,          -- rang de guilde après le nom de guilde
        tooltipIDs = false,        -- identifiant des sorts, objets et auras
        hideHealthBar = false,     -- barre de vie sous les infobulles d'unité
    },
})

local active = false
local hooked = false

--------------------------------------------------------------------------------
-- Infobulles
--------------------------------------------------------------------------------

local function Tooltips()
    local list = {}
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
        if _G[name] then list[#list + 1] = _G[name] end
    end
    return list
end

local function SetColors(tooltip, bg, border)
    local slice = tooltip.NineSlice
    if slice and slice.SetCenterColor then
        slice:SetCenterColor(bg[1], bg[2], bg[3], bg[4])
        slice:SetBorderColor(border[1], border[2], border[3], border[4] or 1)
    elseif tooltip.SetBackdropColor then
        tooltip:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        tooltip:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end
end

local function StyleTooltip(tooltip)
    if not active or not Skin.db.tooltips then return end
    -- Infobulle interdite (boutique, protégée) : y toucher lève une erreur.
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local r, g, b = Media:Accent()
    SetColors(tooltip, BACKGROUND, { r * 0.6, g * 0.6, b * 0.6, 1 })
end

local function RestoreTooltip(tooltip)
    if _G.SharedTooltip_SetBackdropStyle and _G.GAME_TOOLTIP_BACKDROP_STYLE_DEFAULT then
        SharedTooltip_SetBackdropStyle(tooltip, GAME_TOOLTIP_BACKDROP_STYLE_DEFAULT)
        return
    end
    local bg = _G.TOOLTIP_DEFAULT_BACKGROUND_COLOR
    local border = _G.TOOLTIP_DEFAULT_COLOR
    SetColors(tooltip,
        bg and { bg.r, bg.g, bg.b, 1 } or { 0, 0, 0, 0.8 },
        border and { border.r, border.g, border.b, 1 } or { 1, 1, 1, 1 })
end

--- OnShow : masquage en combat, puis style.
local function OnTooltipShow(tooltip)
    if not active then return end
    if Skin.db.hideAllTooltipsInCombat and NS.InCombat() then
        tooltip:Hide()
        return
    end
    StyleTooltip(tooltip)
end

local function Known(value) return not NS.IsSecret(value) and value ~= nil end

--- Rang de guilde, cible de l'unité, barre de vie. Une valeur secrète : la ligne est omise.
function Skin.AddUnitDetails(tooltip, unit)
    local db = Skin.db
    if db.guildRank and _G.GetGuildInfo then
        local guild, rank = GetGuildInfo(unit)
        local line = _G[tooltip:GetName() .. "TextLeft2"]
        local text = line and line:GetText()
        if Known(guild) and Known(rank) and Known(text) and text:find(guild, 1, true) and not text:find("[" .. rank .. "]", 1, true) then
            line:SetText(text .. " |cffa0a0a0[" .. rank .. "]|r")
        end
    end
    if db.tooltipTarget then
        local target = unit .. "target"
        local exists = UnitExists(target)
        local name = Known(exists) and exists and UnitName(target)
        if Known(name) and name then
            local r, g, b = 1, 1, 1
            local isYou = UnitIsUnit(target, "player")
            local isPlayer = UnitIsPlayer(target)
            if Known(isYou) and isYou then
                name, r, g, b = L.TOOLTIP_TARGET_YOU, 1, 0.3, 0.3
            elseif Known(isPlayer) and isPlayer then
                local _, classFile = UnitClass(target)
                if Known(classFile) then r, g, b = NS.ClassColor(classFile) end
            end
            tooltip:AddLine(string.format(L.TOOLTIP_TARGET, name), r, g, b)
            tooltip:Show()   -- recalcule la taille après la ligne ajoutée
        end
    end
end

--- Identifiant de sort, d'objet ou d'aura (post-call TooltipDataProcessor : data.id).
local function AddID(tooltip, data)
    if not active or not Skin.db.tooltipIDs or type(data) ~= "table" or not Known(data.id) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    tooltip:AddLine(string.format(L.TOOLTIP_ID, tostring(data.id)), 0.6, 0.6, 0.6)
    tooltip:Show()
end

--- Nom et bordure à la couleur de classe. Toute valeur secrète (unité en combat) : on s'abstient.
local function OnTooltipUnit(tooltip)
    if not active then return end
    if Skin.db.hideHealthBar and _G.GameTooltipStatusBar then GameTooltipStatusBar:Hide() end   -- même unité secrète
    local unit = NS.TooltipUnit(tooltip)
    if NS.IsSecret(unit) or not unit then return end
    if Skin.db.hideUnitTooltipInCombat and NS.InCombat() then
        tooltip:Hide()
        return
    end
    if NS.IsSecretUnit(unit) then return end   -- identité masquée : ni rang, ni cible, ni classe
    Skin.AddUnitDetails(tooltip, unit)
    if not Skin.db.classColors then return end
    local isPlayer = UnitIsPlayer(unit)
    if NS.IsSecret(isPlayer) or not isPlayer then return end
    local _, classFile = UnitClass(unit)
    if NS.IsSecret(classFile) or not classFile then return end
    local r, g, b = NS.ClassColor(classFile)
    local nameLine = _G[tooltip:GetName() .. "TextLeft1"]
    if nameLine then nameLine:SetTextColor(r, g, b) end
    if Skin.db.tooltips then SetColors(tooltip, BACKGROUND, { r, g, b, 1 }) end
end

local function HookTooltips()
    for _, tooltip in ipairs(Tooltips()) do
        tooltip:HookScript("OnShow", OnTooltipShow)
    end
    if _G.SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip) StyleTooltip(tooltip) end)
    end
    -- Infobulles « par défaut » (unités du monde, cadres) : au curseur plutôt qu'en bas à droite.
    if _G.GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
            if active and Skin.db.anchorCursor and not (tooltip.IsForbidden and tooltip:IsForbidden()) then
                tooltip:SetOwner(parent, "ANCHOR_CURSOR")
            end
        end)
    end
    if _G.TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            if tooltip == GameTooltip then OnTooltipUnit(tooltip) end
        end)
        for _, kind in ipairs({ "Spell", "Item", "UnitAura" }) do
            if Enum.TooltipDataType[kind] then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType[kind], AddID) end
        end
    else
        GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipUnit)
    end
end

--------------------------------------------------------------------------------
-- Icônes recadrées
--------------------------------------------------------------------------------

local ICON_CONTAINERS = { "BuffFrame", "DebuffFrame" }
local COOLDOWN_VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }

-- Coordonnées d'origine de chaque icône (clés faibles : une icône recyclée disparaît seule).
local originalCoords = setmetatable({}, { __mode = "k" })

local function Crop(icon)
    if not icon or not icon.SetTexCoord then return end
    if not originalCoords[icon] then originalCoords[icon] = { icon:GetTexCoord() } end
    local db = Skin.db
    if active and db.iconZoom then
        local z = db.iconZoomAmount / 100
        icon:SetTexCoord(z, 1 - z, z, 1 - z)
    else
        icon:SetTexCoord(unpack(originalCoords[icon]))
    end
end

--- Icônes de toutes les frames connues : auras du joueur et gestionnaire de recharges.
function Skin.CollectIcons()
    local icons = {}
    for _, name in ipairs(ICON_CONTAINERS) do
        local container = _G[name]
        for _, button in ipairs(container and container.auraFrames or {}) do
            icons[#icons + 1] = button.Icon or button.icon
        end
    end
    for _, name in ipairs(COOLDOWN_VIEWERS) do
        local viewer = _G[name]
        if viewer and viewer.GetChildren then
            for _, child in ipairs({ viewer:GetChildren() }) do
                icons[#icons + 1] = child.Icon or child.icon
            end
        end
    end
    return icons
end

local HookIcons

function Skin:ApplyIcons()
    HookIcons()   -- Blizzard_CooldownViewer se charge à la demande : rattraper ses cadres
    for _, icon in ipairs(self.CollectIcons()) do Crop(icon) end
end

-- Un verrou par cadre : un cadre absent au premier passage est hooké dès qu'il existe.
local hookedFrames = {}
function HookIcons()
    for _, name in ipairs(ICON_CONTAINERS) do
        local container = _G[name]
        if container and container.UpdateAuraButtons and not hookedFrames[name] then
            hookedFrames[name] = true
            hooksecurefunc(container, "UpdateAuraButtons", function() if active then Skin:ApplyIcons() end end)
        end
    end
    for _, name in ipairs(COOLDOWN_VIEWERS) do
        local viewer = _G[name]
        if viewer and viewer.RefreshLayout and not hookedFrames[name] then
            hookedFrames[name] = true
            hooksecurefunc(viewer, "RefreshLayout", function() if active then Skin:ApplyIcons() end end)
        end
    end
end

--------------------------------------------------------------------------------
-- Panneaux sombres
--------------------------------------------------------------------------------
-- Les panneaux Blizzard (NineSlice, fond, barre de titre) sont teintés : même art, plus
-- sombre. Réversible (teinte 1,1,1). Les Blizzard_* chargés à la demande sont rattrapés sur
-- ADDON_LOADED. Les panneaux non listés restent tels quels.

local DARK_PANELS = {
    "CharacterFrame", "InspectFrame", "SpellBookFrame", "PlayerSpellsFrame", "ClassTalentFrame", "TalentFrame",
    "FriendsFrame", "QuestLogFrame", "MerchantFrame", "GameMenuFrame", "MailFrame", "OpenMailFrame", "DressUpFrame",
    "TradeFrame", "TaxiFrame", "GossipFrame", "QuestFrame", "LootFrame", "BankFrame", "PVEFrame", "PVPFrame",
    "GuildFrame", "ItemTextFrame", "TabardFrame", "PetStableFrame", "MacroFrame", "KeyBindingFrame",
    "AuctionHouseFrame", "ProfessionsFrame", "EncounterJournal", "AchievementFrame", "CalendarFrame",
    "CollectionsJournal", "AddonList", "HelpFrame", "ChannelFrame", "RaidParentFrame", "CommunitiesFrame",
}
local DARK_KEYS = { "Bg", "TitleBg", "TopTileStreaks", "Inset", "TitleContainer" }   -- jamais le portrait
local DARK_TINT = 0.25
local darkenedPanels = {}    -- [cadre] = true

-- Textures seulement : un texte teinté à 0,25 (titre du panneau) devient illisible.
local function TintRegions(frame, tint)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.SetVertexColor and not (region.GetObjectType and region:GetObjectType() == "FontString") then
            region:SetVertexColor(tint, tint, tint)
        end
    end
end

--- Teinte un panneau (on = sombre, off = art d'origine).
function Skin.DarkenPanel(frame, on)
    local tint = on and DARK_TINT or 1
    if frame.NineSlice then TintRegions(frame.NineSlice, tint) end
    for _, key in ipairs(DARK_KEYS) do
        local part = frame[key]
        if type(part) == "table" then
            if part.SetVertexColor then part:SetVertexColor(tint, tint, tint) end
            if part.GetRegions then TintRegions(part, tint) end
            if part.NineSlice then TintRegions(part.NineSlice, tint) end
        end
    end
end

function Skin:ApplyDarkPanels()
    local on = active and self.db.darkPanels
    for _, name in ipairs(DARK_PANELS) do
        local frame = _G[name]
        if type(frame) == "table" and (on or darkenedPanels[frame]) then
            Skin.DarkenPanel(frame, on)
            darkenedPanels[frame] = on or nil
        end
    end
end

--------------------------------------------------------------------------------
-- Fenêtres au thème : fiche de personnage et amis
--------------------------------------------------------------------------------

-- Onglets laissés à Blizzard : effacés, ils perdraient la marque de l'onglet actif.
local SKIN_WINDOWS = { "CharacterFrame", "FriendsFrame" }
-- Parties d'art des fenêtres Blizzard (jamais TitleContainer : il porte le titre).
local WINDOW_PARTS = { "NineSlice", "Bg", "TitleBg", "TopTileStreaks", "Inset", "PortraitContainer", "portrait" }
local EQUIPMENT_SLOTS = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged", "Ammo",
}
local SLOT_CROP = 0.08
local faded = setmetatable({}, { __mode = "k" })        -- [région] = alpha d'origine
local windowBackdrops = setmetatable({}, { __mode = "k" }) -- [cadre] = support du fond
local slotBorders = setmetatable({}, { __mode = "k" })     -- [bouton] = bordure

local function Fade(region, on)
    if on then
        if faded[region] == nil then faded[region] = region:GetAlpha() end
        region:SetAlpha(0)
    elseif faded[region] ~= nil then
        region:SetAlpha(faded[region])
        faded[region] = nil
    end
end

-- Textures posées directement sur le cadre (les FontString, qui ont SetText, restent).
local function FadeArt(frame, on)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.SetTexture and not region.SetText then Fade(region, on) end
    end
end

--- Habille (on) ou rend (off) un cadre : art effacé, fond plat du thème derrière.
function Skin.SkinFrame(frame, on)
    FadeArt(frame, on)
    for _, key in ipairs(WINDOW_PARTS) do
        local part = frame[key]
        if type(part) == "table" and part.SetAlpha then Fade(part, on) end
    end
    local holder = windowBackdrops[frame]
    if on and not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holder:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
        Media:CreateBackdrop(holder)
        windowBackdrops[frame] = holder
    end
    if holder then holder:SetShown(on) end
end

local function SlotButton(slot) return _G["Character" .. slot .. "Slot"] end

--- Bordure de qualité et icône recadrée d'un emplacement d'équipement.
function Skin.PaintSlot(slot, on)
    local button = SlotButton(slot)
    if not button then return end
    local icon = button.icon or _G[button:GetName() .. "IconTexture"]
    if icon and icon.SetTexCoord then
        if not originalCoords[icon] then originalCoords[icon] = { icon:GetTexCoord() } end
        if on then icon:SetTexCoord(SLOT_CROP, 1 - SLOT_CROP, SLOT_CROP, 1 - SLOT_CROP)
        else icon:SetTexCoord(unpack(originalCoords[icon])) end
    end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then Fade(normal, on) end
    local edges = slotBorders[button]
    local quality
    if on and _G.GetInventorySlotInfo and _G.GetInventoryItemQuality then
        local ok, id = pcall(GetInventorySlotInfo, slot .. "Slot")
        quality = ok and id and GetInventoryItemQuality("player", id) or nil
        if NS.IsSecret(quality) then quality = nil end
    end
    if quality and not edges then
        edges = Media:CreateBorder(button)
        slotBorders[button] = edges
    end
    if not edges then return end
    local r, g, b = 0, 0, 0
    if quality and C_Item and C_Item.GetItemQualityColor then r, g, b = C_Item.GetItemQualityColor(quality) end
    for _, edge in pairs(edges) do
        NS.SetSolidColor(edge, r, g, b, 1)
        edge:SetShown(quality ~= nil)
    end
end

function Skin:ApplyWindows()
    local on = active and self.db.skinWindows and true or false
    for _, name in ipairs(SKIN_WINDOWS) do
        local frame = _G[name]
        if type(frame) == "table" and (on or windowBackdrops[frame]) then Skin.SkinFrame(frame, on) end
    end
    if _G.CharacterFrame and (on or next(slotBorders)) then
        for _, slot in ipairs(EQUIPMENT_SLOTS) do Skin.PaintSlot(slot, on) end
    end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "ADDON_LOADED" then Skin:ApplyDarkPanels() Skin:ApplyWindows() return end
    if event == "PLAYER_EQUIPMENT_CHANGED" then Skin:ApplyWindows() return end
    Skin:ApplyIcons()
end)

function Skin:OnEnable()
    active = true
    if not hooked then
        hooked = true
        HookTooltips()
    end
    HookIcons()
    if self.db.tooltips then
        for _, tooltip in ipairs(Tooltips()) do StyleTooltip(tooltip) end
    end
    NS.RegisterEventSafe(events, "UNIT_AURA", "player")
    NS.RegisterEventSafe(events, "PLAYER_ENTERING_WORLD")
    NS.RegisterEventSafe(events, "ADDON_LOADED")
    NS.RegisterEventSafe(events, "PLAYER_EQUIPMENT_CHANGED")
    self:ApplyIcons()
    self:ApplyDarkPanels()
    self:ApplyWindows()
end

function Skin:OnDisable()
    active = false
    events:UnregisterAllEvents()
    for _, tooltip in ipairs(Tooltips()) do RestoreTooltip(tooltip) end
    self:ApplyIcons()   -- active = false : rognage Blizzard d'origine
    self:ApplyDarkPanels()
    self:ApplyWindows()
end

function Skin:OnRefresh()
    for _, tooltip in ipairs(Tooltips()) do
        if self.db.tooltips then StyleTooltip(tooltip) else RestoreTooltip(tooltip) end
    end
    self:ApplyIcons()
    self:ApplyDarkPanels()
    self:ApplyWindows()
end

-- Le thème repeint les bordures qu'il connaît à sa couleur : la qualité passe par-dessus.
NS:On("PIXEL_CHANGED", function() if active then Skin:ApplyWindows() end end)
NS:On("THEME_CHANGED", function() if active then Skin:ApplyWindows() end end)

function Skin:BuildOptions(o)
    o:Title(L.OPT_SKIN_TOOLTIPS_TITLE)
    o:Check("tooltips", L.OPT_SKIN_TOOLTIPS)
    o:Check("classColors", L.OPT_SKIN_CLASS_COLORS)
    o:Check("hideUnitTooltipInCombat", L.OPT_SKIN_HIDE_COMBAT)
    o:Check("hideAllTooltipsInCombat", L.OPT_SKIN_HIDE_ALL_COMBAT)
    o:Check("anchorCursor", L.OPT_SKIN_ANCHOR_CURSOR)
    o:Check("tooltipTarget", L.OPT_SKIN_TOOLTIP_TARGET)
    o:Check("guildRank", L.OPT_SKIN_GUILD_RANK)
    o:Check("tooltipIDs", L.OPT_SKIN_TOOLTIP_IDS)
    o:Check("hideHealthBar", L.OPT_SKIN_HIDE_HEALTHBAR)
    o:Title(L.OPT_SKIN_ICONS_TITLE)
    o:Check("iconZoom", L.OPT_SKIN_ICON_ZOOM)
    o:Slider("iconZoomAmount", L.OPT_SKIN_ICON_ZOOM_AMOUNT, 0, 20, 1, 36, "%d %%")
    o:Title(L.OPT_SKIN_PANELS_TITLE)
    o:Check("darkPanels", L.OPT_SKIN_DARK_PANELS)
    o:Check("skinWindows", L.OPT_SKIN_WINDOWS)
end
