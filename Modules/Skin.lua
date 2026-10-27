-- Modules/Skin.lua
-- Habillage léger et réversible :
--   * infobulles sombres, nom et bordure à la couleur de classe pour les joueurs ;
--   * infobulles au curseur, cible de l'unité, rang de guilde, identifiants, barre de vie masquable ;
--   * masquer en combat les infobulles d'unité, ou toutes les infobulles ;
--   * icônes d'aura (buffs du joueur) et du gestionnaire de temps de recharge recadrées :
--     on retire le liseré intégré aux icônes Blizzard (zoom réglable) ;
--   * une quarantaine de fenêtres, popups et menus Blizzard, un style chacune (défaut commun,
--     exceptions par fenêtre) sous un interrupteur général : « thème » (art effacé à alpha 0,
--     fond plat et bordure 1 px ; emplacements d'équipement recadrés, bordure de qualité),
--     « sombre » (même art, teinté) ou « Blizzard » (intact). Tout est rendu au décochage.
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
    defaults = {
        enabled = true,
        tooltips = true,
        classColors = true,
        hideUnitTooltipInCombat = false,
        hideAllTooltipsInCombat = false,
        iconZoom = true,
        iconZoomAmount = 8,        -- en % de chaque bord (0-20)
        skinWindows = false,       -- interrupteur général de l'habillage des fenêtres Blizzard
        windowStyle = "theme",     -- style par défaut : "theme" | "dark" | "blizzard"
        windowStyles = {},         -- [nom du cadre] = style propre à cette fenêtre
        anchorCursor = false,      -- infobulles par défaut (monde, cadres) collées au curseur
        anchorFixed = false,       -- infobulles par défaut sur un mover (prioritaire sur le curseur)
        anchorGrowth = "UP_LEFT",  -- sens de croissance depuis le mover : UP_LEFT, UP_RIGHT, DOWN_LEFT, DOWN_RIGHT
        anchorOffsetX = 0,
        anchorOffsetY = 0,
        tooltipTarget = true,      -- ligne « Cible : » sur les infobulles d'unité
        guildRank = true,          -- rang de guilde après le nom de guilde
        tooltipIDs = false,        -- identifiant des sorts, objets et auras
        hideHealthBar = false,     -- barre de vie sous les infobulles d'unité
        tooltipOpacity = 94,       -- opacité du fond des infobulles, en %
        tooltipBorder = "accent",  -- bordure : "accent" (teinte de l'accent), "theme" (couleur de bordure du thème), "none"
        tooltipIDModifier = "always", -- identifiants et pile max : "always", "shift", "ctrl", "alt"
        tooltipIconID = false,     -- ajoute l'identifiant d'icône (sorts, objets)
        tooltipStackSize = false,  -- ligne « pile max » des objets empilables
        healthBarHeight = 0,       -- hauteur de la barre de vie, 0 : celle de Blizzard
        healthBarTexture = false,  -- barre de vie à la texture du thème
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

--- Fond (opacité réglée) et bordure (style réglé) des infobulles.
local function TooltipColors()
    local db = Skin.db
    local background = { BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], (tonumber(db.tooltipOpacity) or 94) / 100 }
    local border
    if db.tooltipBorder == "none" then
        border = { 0, 0, 0, 0 }
    elseif db.tooltipBorder == "theme" then
        local c = NS.db.theme.border
        border = { c.r, c.g, c.b, 1 }
    else
        local r, g, b = Media:Accent()
        border = { r * 0.6, g * 0.6, b * 0.6, 1 }
    end
    return background, border
end

local function StyleTooltip(tooltip)
    if not active or not Skin.db.tooltips then return end
    -- Infobulle interdite (boutique, protégée) : y toucher lève une erreur.
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    SetColors(tooltip, TooltipColors())
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

--- Le modificateur choisi est-il tenu ? (« always » : toujours.)
function Skin.ModifierHeld()
    local modifier = Skin.db.tooltipIDModifier
    if modifier == "shift" then return IsShiftKeyDown() == true end
    if modifier == "ctrl" then return IsControlKeyDown() == true end
    if modifier == "alt" then return IsAltKeyDown() == true end
    return true
end

local function IconID(kind, id)
    if kind == "Item" then
        local getInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
        return getInstant and select(5, getInstant(id))
    end
    local getTexture = C_Spell and C_Spell.GetSpellTexture or _G.GetSpellTexture
    return getTexture and getTexture(id)
end

--- Identifiant (et icône, pile max) d'un sort, d'un objet ou d'une aura (post-call TooltipDataProcessor : data.id).
local function AddID(tooltip, data, kind)
    local db = Skin.db
    if not active or type(data) ~= "table" or not Known(data.id) then return end
    if not (db.tooltipIDs or db.tooltipIconID or (kind == "Item" and db.tooltipStackSize)) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not Skin.ModifierHeld() then return end
    if db.tooltipIDs then tooltip:AddLine(string.format(L.TOOLTIP_ID, tostring(data.id)), 0.6, 0.6, 0.6) end
    if db.tooltipIconID then
        local icon = IconID(kind, data.id)
        if Known(icon) and icon then tooltip:AddLine(string.format(L.OPT_G_SKIN_LINE_ICON_ID, tostring(icon)), 0.6, 0.6, 0.6) end
    end
    if kind == "Item" and db.tooltipStackSize then
        local max = NS.GetItemMaxStack(data.id)
        if Known(max) and type(max) == "number" and max > 1 then
            tooltip:AddLine(string.format(L.OPT_G_SKIN_LINE_STACK_SIZE, max), 0.6, 0.6, 0.6)
        end
    end
    tooltip:Show()
end

-- Barre de vie des infobulles d'unité : hauteur et texture réglables, état d'origine capturé.
local healthBarOriginal
function Skin:ApplyHealthBar()
    local bar = _G.GameTooltipStatusBar
    if not bar then return end
    if not healthBarOriginal then
        local texture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        healthBarOriginal = { height = bar:GetHeight(), texture = texture and texture:GetTexture() }
    end
    local db = self.db
    local height = active and tonumber(db.healthBarHeight) or 0
    if height and height > 0 then bar:SetHeight(height)
    elseif healthBarOriginal.height and healthBarOriginal.height > 0 then bar:SetHeight(healthBarOriginal.height) end
    if bar.SetStatusBarTexture then
        if active and db.healthBarTexture then bar:SetStatusBarTexture(Media:StatusBarTexture())
        elseif healthBarOriginal.texture then bar:SetStatusBarTexture(healthBarOriginal.texture) end
    end
end

--- Nom et bordure à la couleur de classe. Toute valeur secrète (unité en combat) : on s'abstient.
local function OnTooltipUnit(tooltip)
    if not active then return end
    if Skin.db.hideHealthBar and _G.GameTooltipStatusBar then GameTooltipStatusBar:Hide() end   -- même unité secrète
    Skin:ApplyHealthBar()
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
    if Skin.db.tooltips then
        local background = TooltipColors()
        SetColors(tooltip, background, { r, g, b, 1 })
    end
end

-- Sens de croissance -> coin de l'infobulle posé sur le même coin du mover.
local GROWTH_POINTS = { UP_LEFT = "BOTTOMRIGHT", UP_RIGHT = "BOTTOMLEFT", DOWN_LEFT = "TOPRIGHT", DOWN_RIGHT = "TOPLEFT" }
local tooltipAnchor

--- Mover de l'infobulle, présent seulement quand la position fixe est choisie.
function Skin:UpdateTooltipAnchor()
    if active and self.db.anchorFixed then
        if not tooltipAnchor then
            tooltipAnchor = CreateFrame("Frame", "MuscaUITooltipAnchor", UIParent)
            tooltipAnchor:SetSize(160, 40)
        end
        NS.Movers:Register("tooltip", tooltipAnchor, L.MOVER_TOOLTIP, "BOTTOMRIGHT", -80, 180)
        NS.Movers:Load("tooltip")
    elseif tooltipAnchor then
        NS.Movers:Unregister("tooltip")
    end
end

function Skin:GetTooltipAnchor() return tooltipAnchor end

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
            if not active or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
            local db = Skin.db
            if db.anchorFixed and tooltipAnchor then
                local point = GROWTH_POINTS[db.anchorGrowth] or "BOTTOMRIGHT"
                tooltip:SetOwner(parent, "ANCHOR_NONE")
                tooltip:ClearAllPoints()
                tooltip:SetPoint(point, tooltipAnchor, point, db.anchorOffsetX, db.anchorOffsetY)
            elseif db.anchorCursor then
                tooltip:SetOwner(parent, "ANCHOR_CURSOR")
            end
        end)
    end
    if _G.TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            if tooltip == GameTooltip then OnTooltipUnit(tooltip) end
        end)
        for _, kind in ipairs({ "Spell", "Item", "UnitAura" }) do
            if Enum.TooltipDataType[kind] then
                TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType[kind], function(tooltip, data) AddID(tooltip, data, kind) end)
            end
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

local cropped = setmetatable({}, { __mode = "k" })   -- icônes déjà recadrées (réglage inchangé)

local function Crop(icon, force)
    if not icon or not icon.SetTexCoord then return end
    if cropped[icon] and not force then return end
    cropped[icon] = true
    if not originalCoords[icon] then originalCoords[icon] = { icon:GetTexCoord() } end
    local db = Skin.db
    if active and db.iconZoom then
        local z = db.iconZoomAmount / 100
        icon:SetTexCoord(z, 1 - z, z, 1 - z)
    else
        icon:SetTexCoord(unpack(originalCoords[icon]))
    end
end

-- Parcours en varargs : évite la table temporaire de { viewer:GetChildren() }.
local function AppendChildIcons(icons, ...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        icons[#icons + 1] = child.Icon or child.icon
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
            AppendChildIcons(icons, viewer:GetChildren())
        end
    end
    return icons
end

--- `force` : réglage changé, toutes les icônes sont recadrées ; sinon seulement les nouvelles.
function Skin:ApplyIcons(force)
    for _, icon in ipairs(self.CollectIcons()) do Crop(icon, force) end
end

-- Aucun hook sur BuffFrame ni les viewers (cadres Edit Mode : un hook sur leurs méthodes
-- contamine la mise en page, « attempt to call a nil value ») : recadrage l'image qui suit
-- les événements qui les remettent à jour.
local iconsQueued = false
local function QueueIcons()
    if iconsQueued then return end
    iconsQueued = true
    C_Timer.After(0, function()
        iconsQueued = false
        if active then Skin:ApplyIcons() end
    end)
end

--------------------------------------------------------------------------------
-- Fenêtres Blizzard : style « sombre »
--------------------------------------------------------------------------------
-- Style sombre : les panneaux (NineSlice, fond, barre de titre) sont teintés, même art, plus
-- sombre. Réversible (teinte 1,1,1). Les Blizzard_* chargés à la demande sont rattrapés sur
-- ADDON_LOADED. Les fenêtres non listées restent telles quelles.
-- ponytail: menus contextuels Blizzard_Menu (11.0+) non habillés, seulement les DropDownList
-- d'UIDropDownMenu ; hook de Menu.GetManager si le besoin se confirme.

local WINDOWS = {
    "CharacterFrame", "InspectFrame", "SpellBookFrame", "PlayerSpellsFrame", "ClassTalentFrame", "TalentFrame",
    "FriendsFrame", "QuestLogFrame", "MerchantFrame", "GameMenuFrame", "MailFrame", "OpenMailFrame", "DressUpFrame",
    "TradeFrame", "TaxiFrame", "GossipFrame", "QuestFrame", "LootFrame", "BankFrame", "PVEFrame", "PVPFrame",
    "GuildFrame", "ItemTextFrame", "TabardFrame", "PetStableFrame", "MacroFrame", "KeyBindingFrame",
    "AuctionHouseFrame", "ProfessionsFrame", "EncounterJournal", "AchievementFrame", "CalendarFrame",
    "CollectionsJournal", "AddonList", "HelpFrame", "ChannelFrame", "RaidParentFrame", "CommunitiesFrame",
    "WorldMapFrame", "ReadyCheckFrame", "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
    "DropDownList1", "DropDownList2", "DropDownList3",
    "QuickKeybindFrame", "LFGDungeonReadyDialog", "LFGListApplicationDialog",   -- dialogues (absents : ignorés)
}
Skin.WINDOWS = WINDOWS
local STYLES = { theme = true, dark = true, blizzard = true }
-- Border, BG : popups et menus déroulants.
local DARK_KEYS = { "Bg", "TitleBg", "TopTileStreaks", "Inset", "TitleContainer", "Border", "BG" }   -- jamais le portrait
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

--- Style de la fenêtre `name` : exception, sinon défaut ; "blizzard" sans l'interrupteur.
function Skin:WindowStyle(name)
    if not (active and self.db.skinWindows) then return "blizzard" end
    local style = self.db.windowStyles[name]
    if STYLES[style] then return style end
    return STYLES[self.db.windowStyle] and self.db.windowStyle or "blizzard"
end

--------------------------------------------------------------------------------
-- Fenêtres Blizzard : style « thème »
--------------------------------------------------------------------------------

-- Parties d'art des fenêtres Blizzard (jamais TitleContainer : il porte le titre). Onglets laissés
-- à Blizzard : effacés, ils perdraient la marque de l'onglet actif.
local WINDOW_PARTS = { "NineSlice", "Bg", "TitleBg", "TopTileStreaks", "Inset", "PortraitContainer", "portrait",
                       "Border", "BG" }
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

--- Bordure de qualité et icône recadrée d'un emplacement d'équipement. prefix « Character »
-- (défaut) ou « Inspect » avec l'unité inspectée.
function Skin.PaintSlot(slot, on, prefix, unit)
    local button = _G[(prefix or "Character") .. slot .. "Slot"]
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
    if on then
        quality = select(2, NS.GetEquipped(slot, unit))
        if NS.IsSecret(quality) then quality = nil end
    end
    if quality and not edges then
        edges = Media:CreateBorder(button)
        slotBorders[button] = edges
    end
    if not edges then return end
    local r, g, b = 0, 0, 0
    if quality then r, g, b = NS.QualityColor(quality) end
    for _, edge in pairs(edges) do
        NS.SetSolidColor(edge, r, g, b, 1)
        edge:SetShown(quality ~= nil)
    end
end

function Skin:ApplyWindows()
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if type(frame) == "table" then
            local style = self:WindowStyle(name)
            local theme, dark = style == "theme", style == "dark"
            if theme or windowBackdrops[frame] then Skin.SkinFrame(frame, theme) end
            if dark or darkenedPanels[frame] then
                Skin.DarkenPanel(frame, dark)
                darkenedPanels[frame] = dark or nil
            end
        end
    end
    local character = self:WindowStyle("CharacterFrame") == "theme"
    if _G.CharacterFrame and (character or next(slotBorders)) then
        for _, slot in ipairs(EQUIPMENT_SLOTS) do Skin.PaintSlot(slot, character) end
    end
    local inspect = _G.InspectFrame
    local unit = inspect and inspect.unit
    if NS.IsSecret(unit) then unit = nil end
    local inspected = self:WindowStyle("InspectFrame") == "theme"
    if inspect and (inspected or next(slotBorders)) then
        for _, slot in ipairs(EQUIPMENT_SLOTS) do Skin.PaintSlot(slot, inspected and unit ~= nil, "Inspect", unit) end
    end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "ADDON_LOADED" then Skin:ApplyWindows() QueueIcons() return end
    if event == "PLAYER_EQUIPMENT_CHANGED" or event == "INSPECT_READY" then Skin:ApplyWindows() return end
    QueueIcons()
end)

-- Les événements d'aura et de recharge ne servent qu'au zoom d'icône.
local function UpdateIconEvents()
    if active and Skin.db.iconZoom then
        events:UnregisterEvent("UNIT_AURA")   -- remplacement du filtre d'unité non prouvé sur Forever
        NS.RegisterEventSafe(events, "UNIT_AURA", "player")
        NS.RegisterEventSafe(events, "SPELL_UPDATE_COOLDOWN")   -- items des viewers de recharge
    else
        events:UnregisterEvent("UNIT_AURA")
        events:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end
end

function Skin:OnEnable()
    active = true
    if not hooked then
        hooked = true
        HookTooltips()
    end
    if self.db.tooltips then
        for _, tooltip in ipairs(Tooltips()) do StyleTooltip(tooltip) end
    end
    self:UpdateTooltipAnchor()
    self:ApplyHealthBar()
    UpdateIconEvents()
    NS.RegisterEventSafe(events, "PLAYER_ENTERING_WORLD")
    NS.RegisterEventSafe(events, "ADDON_LOADED")
    NS.RegisterEventSafe(events, "PLAYER_EQUIPMENT_CHANGED")
    NS.RegisterEventSafe(events, "INSPECT_READY")
    self:ApplyIcons(true)
    self:ApplyWindows()
end

function Skin:OnDisable()
    active = false
    events:UnregisterAllEvents()
    for _, tooltip in ipairs(Tooltips()) do RestoreTooltip(tooltip) end
    self:ApplyHealthBar()
    self:UpdateTooltipAnchor()
    self:ApplyIcons(true)   -- active = false : rognage Blizzard d'origine
    self:ApplyWindows()
end

function Skin:OnRefresh()
    for _, tooltip in ipairs(Tooltips()) do
        if self.db.tooltips then StyleTooltip(tooltip) else RestoreTooltip(tooltip) end
    end
    self:UpdateTooltipAnchor()
    self:ApplyHealthBar()
    UpdateIconEvents()
    self:ApplyIcons(true)
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
    o:Advanced()
    o:Check("anchorFixed", L.OPT_SKIN_ANCHOR_FIXED)
    o:Dropdown("anchorGrowth", L.OPT_SKIN_ANCHOR_GROWTH, {
        { name = L.OPT_SKIN_GROWTH_UP_LEFT, value = "UP_LEFT" }, { name = L.OPT_SKIN_GROWTH_UP_RIGHT, value = "UP_RIGHT" },
        { name = L.OPT_SKIN_GROWTH_DOWN_LEFT, value = "DOWN_LEFT" }, { name = L.OPT_SKIN_GROWTH_DOWN_RIGHT, value = "DOWN_RIGHT" },
    }, 36)
    o:Slider("anchorOffsetX", L.OPT_SKIN_ANCHOR_OFFSET_X, -100, 100, 1, 36)
    o:Slider("anchorOffsetY", L.OPT_SKIN_ANCHOR_OFFSET_Y, -100, 100, 1, 36)
    o:EndAdvanced()
    o:Check("tooltipTarget", L.OPT_SKIN_TOOLTIP_TARGET)
    o:Check("guildRank", L.OPT_SKIN_GUILD_RANK)
    o:Advanced()
    o:Check("tooltipIDs", L.OPT_SKIN_TOOLTIP_IDS)
    o:EndAdvanced()
    o:Check("hideHealthBar", L.OPT_SKIN_HIDE_HEALTHBAR)
    o:Advanced()
    o:Slider("tooltipOpacity", L.OPT_G_SKIN_TOOLTIP_OPACITY, 0, 100, 1, 36, "%d %%")
    o:Dropdown("tooltipBorder", L.OPT_G_SKIN_TOOLTIP_BORDER, {
        { name = L.OPT_G_SKIN_BORDER_ACCENT, value = "accent" }, { name = L.OPT_G_SKIN_BORDER_THEME, value = "theme" },
        { name = L.OPT_G_SKIN_BORDER_NONE, value = "none" },
    }, 36)
    o:Dropdown("tooltipIDModifier", L.OPT_G_SKIN_ID_MODIFIER, {
        { name = L.OPT_G_SKIN_MODIFIER_ALWAYS, value = "always" }, { name = "Shift", value = "shift" },
        { name = "Ctrl", value = "ctrl" }, { name = "Alt", value = "alt" },
    }, 36)
    o:Check("tooltipIconID", L.OPT_G_SKIN_ICON_ID, 36)
    o:Check("tooltipStackSize", L.OPT_G_SKIN_STACK_SIZE, 36)
    o:Slider("healthBarHeight", L.OPT_G_SKIN_HEALTHBAR_HEIGHT, 0, 20, 1, 36)
    o:Check("healthBarTexture", L.OPT_G_SKIN_HEALTHBAR_TEXTURE, 36)
    o:EndAdvanced()
    o:Title(L.OPT_SKIN_ICONS_TITLE)
    o:Check("iconZoom", L.OPT_SKIN_ICON_ZOOM)
    o:Advanced()
    o:Slider("iconZoomAmount", L.OPT_SKIN_ICON_ZOOM_AMOUNT, 0, 20, 1, 36, "%d %%")
    o:Tab(L.OPT_SKIN_PANELS_TITLE)
    o:Check("skinWindows", L.OPT_SKIN_WINDOWS)
    local styles = { { name = L.OPT_SKIN_STYLE_THEME, value = "theme" }, { name = L.OPT_SKIN_STYLE_DARK, value = "dark" },
                     { name = L.OPT_SKIN_STYLE_BLIZZARD, value = "blizzard" } }
    o:Dropdown("windowStyle", L.OPT_SKIN_WINDOW_STYLE, styles, 36)
    local perWindow = { { name = L.OPT_SKIN_STYLE_DEFAULT, value = "" } }
    for _, choice in ipairs(styles) do perWindow[#perWindow + 1] = choice end
    o:Title(L.OPT_SKIN_PER_WINDOW)
    o:Advanced()
    for _, name in ipairs(WINDOWS) do
        o:Dropdown("windowStyles." .. name, name, perWindow, 36)
    end
end
