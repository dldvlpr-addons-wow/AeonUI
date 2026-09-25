-- Modules/Bags.lua
-- Sacs tout-en-un léger : une seule fenêtre pour le sac à dos et les sacs équipés, sur son mover.
-- Recherche par nom, tri par l'API du client, niveau d'objet sur l'équipement, objets gris
-- signalés (pièce), bordure de qualité, recharges, emplacements libres et or.
--
-- Les boutons reprennent le modèle ContainerFrameItemButtonTemplate : clic, infobulle,
-- glisser-déposer et utilisation (en combat aussi) restent le code Blizzard. Les fenêtres de sacs
-- Blizzard sont rattachées à un parent caché : leurs ouvertures et fermetures (touche B, marchand,
-- courrier) pilotent la nôtre, et fermer la nôtre les ferme. Banque : fenêtre Blizzard.
-- Cède à ElvUI.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local Bags = NS.Modules:Register("bags", {
    titleKey = "BAGS_TITLE",
    descKey = "BAGS_DESC",
    yieldsTo = { "ElvUI" },
    defaults = {
        enabled = false,
        columns = 12,
        buttonSize = 34,
        itemLevel = true,
        junk = true,
    },
})

local MAX_CONTAINER_FRAMES = 13
local SPACING = 3
local COIN = "Interface\\Buttons\\UI-GroupLoot-Coin-Up"
-- Emplacements d'équipement sans niveau utile.
local NO_LEVEL = { [""] = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_TABARD = true,
                   INVTYPE_BODY = true, INVTYPE_AMMO = true, INVTYPE_NON_EQUIP_IGNORE = true }

local active = false
local window
local buttons = {}          -- [bag] = { [slot] = bouton }
local holders = {}          -- [bag] = cadre porteur de l'ID du sac
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local blizzardParents = {}  -- [cadre Blizzard] = parent d'origine
local syncing = false
local events = CreateFrame("Frame")

local function S(n) return NS.Pixel:Scale(n) end

--------------------------------------------------------------------------------
-- Fenêtres Blizzard
--------------------------------------------------------------------------------

local function BlizzardFrames()
    local list = {}
    for i = 1, MAX_CONTAINER_FRAMES do
        if _G["ContainerFrame" .. i] then list[#list + 1] = _G["ContainerFrame" .. i] end
    end
    if _G.ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
    return list
end

--- Cadre qui montre un sac d'inventaire (sac à dos, sacs équipés). Un même ContainerFrameN sert
-- aussi au trousseau et aux sacs de banque : ceux-là restent visibles, chez Blizzard.
local function IsInventoryFrame(frame)
    if frame == _G.ContainerFrameCombinedBags then return true end
    local id = frame:GetID()
    return type(id) == "number" and id >= 0 and id <= NS.NUM_BAGS
end

local function BlizzardOpen()
    for _, frame in ipairs(BlizzardFrames()) do
        if frame:IsShown() and IsInventoryFrame(frame) then return true end
    end
    return false
end

--- Parent de chaque cadre Blizzard selon le sac qu'il montre à cet instant.
local function PlaceBlizzard()
    for frame, parent in pairs(blizzardParents) do
        local target = IsInventoryFrame(frame) and hiddenParent or parent
        if frame:GetParent() ~= target then frame:SetParent(target) end
    end
end

--- Notre fenêtre suit l'état des sacs Blizzard (ouverts, mais sous un parent caché).
local function Sync()
    if not active or syncing or not window then return end
    PlaceBlizzard()
    syncing = true
    local ok, err = pcall(window.SetShown, window, BlizzardOpen())
    syncing = false
    if not ok then geterrorhandler()(err) end
end

-- Sous un parent caché, les sacs Blizzard ne reçoivent plus OnShow ni OnHide : on suit les
-- fonctions d'ouverture et de fermeture à la place.
local TOGGLES = { "OpenAllBags", "CloseAllBags", "ToggleAllBags", "OpenBackpack", "CloseBackpack",
                  "ToggleBackpack", "OpenBag", "CloseBag", "ToggleBag" }
local hooked = false
local function TakeBlizzard()
    for _, frame in ipairs(BlizzardFrames()) do
        if not blizzardParents[frame] then blizzardParents[frame] = frame:GetParent() or UIParent end
    end
    PlaceBlizzard()
    if hooked then return end
    hooked = true
    for _, name in ipairs(TOGGLES) do
        if _G[name] then hooksecurefunc(name, Sync) end
    end
end

local function RestoreBlizzard()
    for frame, parent in pairs(blizzardParents) do
        frame:SetParent(parent)
        blizzardParents[frame] = nil
    end
end

--------------------------------------------------------------------------------
-- Boutons
--------------------------------------------------------------------------------

local function Holder(bag)
    local holder = holders[bag]
    if holder then return holder end
    holder = CreateFrame("Frame", "AeonUIBagHolder" .. (bag + 1), window)
    holder:SetID(bag)
    holder:SetAllPoints(window)
    holders[bag] = holder
    return holder
end

local function NewButton(bag, slot)
    local name = "AeonUIBag" .. (bag + 1) .. "Slot" .. slot
    local button = CreateFrame("ItemButton", name, Holder(bag), "ContainerFrameItemButtonTemplate")
    button:SetID(slot)   -- sac lu par le modèle sur le porteur (GetParent():GetID())
    local _, edges = Media:CreateBackdrop(button)
    button.border = edges
    button.fuiIcon = button.icon or _G[name .. "IconTexture"]
    if not button.fuiIcon then
        button.fuiIcon = button:CreateTexture(nil, "ARTWORK")
        button.fuiIcon:SetAllPoints()
    end
    button.fuiIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.fuiCooldown = button.Cooldown or _G[name .. "Cooldown"]
    if not button.fuiCooldown then
        button.fuiCooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        button.fuiCooldown:SetAllPoints()
    end
    button.level = Media:CreateText(button, "OVERLAY", -1, "OUTLINE")
    button.level:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.junk = button:CreateTexture(nil, "OVERLAY")
    button.junk:SetTexture(COIN)
    button.junk:SetSize(S(12), S(12))
    button.junk:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
    return button
end

--- Quantité : SetItemButtonCount renseigne aussi `.count`, lu par Blizzard pour diviser une pile.
local function SetCount(button, count)
    if _G.SetItemButtonCount then SetItemButtonCount(button, count) return end
    if not button.fuiCount then
        button.fuiCount = Media:CreateText(button, "OVERLAY", 0, "OUTLINE")
        button.fuiCount:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
    end
    button.count = count
    button.fuiCount:SetText(count > 1 and count or "")
end

--- Libellé de recherche d'un objet : nom en minuscules, lu dans le lien.
local function ItemName(item)
    local link = item.link
    local name = type(link) == "string" and link:match("%[(.-)%]")
    if not name then
        local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
        name = getInfo and getInfo(link or item.itemID)
    end
    return type(name) == "string" and NS.Modules.SortKey(name) or ""
end

local function EquipLocation(item)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if not getInstant then return "" end
    local _, _, _, equipLoc = getInstant(item.link or item.itemID)
    return type(equipLoc) == "string" and equipLoc or ""
end

function Bags.UpdateButton(button, bag, slot)
    local db = Bags.db
    local item = NS.GetBagItem(bag, slot)
    button.fuiItem = item
    local r, g, b = 0, 0, 0
    if not item then
        button.fuiIcon:SetTexture(nil)
        SetCount(button, 0)
        button.level:Hide()
        button.junk:Hide()
        button.fuiCooldown:Hide()
        local c = NS.db.theme.border
        r, g, b = c.r, c.g, c.b
    else
        button.fuiIcon:SetTexture(item.icon)
        if button.fuiIcon.SetDesaturated then button.fuiIcon:SetDesaturated(item.isLocked and true or false) end
        SetCount(button, item.stackCount)
        local level = db.itemLevel and not NO_LEVEL[EquipLocation(item)] and item.link
            and NS.GetItemLevel(item.link)
        button.level:SetText(level and tostring(level) or "")
        button.level:SetTextColor(NS.QualityColor(item.quality))
        button.level:SetShown(level and true or false)
        button.junk:SetShown(db.junk and item.quality == 0 and not item.hasNoValue)
        if item.quality and item.quality >= 2 then r, g, b = NS.QualityColor(item.quality)
        else local c = NS.db.theme.border r, g, b = c.r, c.g, c.b end
        local getCooldown = C_Container and C_Container.GetContainerItemCooldown
        if getCooldown and _G.CooldownFrame_Set then
            local start, duration, enable = getCooldown(bag, slot)
            if NS.IsSecret(start) or NS.IsSecret(duration) or NS.IsSecret(enable) then
                button.fuiCooldown:Clear()
            else
                CooldownFrame_Set(button.fuiCooldown, start, duration, enable)
            end
        end
    end
    for _, edge in pairs(button.border) do NS.SetSolidColor(edge, r, g, b, 1) end
    Bags.ApplySearch(button)
end

--- Recherche : objets qui ne correspondent pas atténués.
function Bags.ApplySearch(button)
    local query = window and window.search and window.search:GetText() or ""
    query = NS.Modules.SortKey(query):match("^%s*(.-)%s*$")
    local match = query == "" or (button.fuiItem and ItemName(button.fuiItem):find(query, 1, true) ~= nil)
    button:SetAlpha(match and 1 or 0.25)
end

--------------------------------------------------------------------------------
-- Fenêtre
--------------------------------------------------------------------------------

local function Build()
    window = CreateFrame("Frame", "AeonUIBags", UIParent)
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    Media:CreateBackdrop(window)
    window:Hide()
    tinsert(UISpecialFrames, "AeonUIBags")
    -- Fermer la nôtre (Échap, croix) ferme les sacs Blizzard, pour que B rouvre ensuite.
    window:SetScript("OnHide", function()
        if not syncing and BlizzardOpen() and _G.CloseAllBags then CloseAllBags() end
    end)
    window:SetScript("OnShow", function() Bags:Update() end)

    window.close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    window.close:SetSize(S(20), S(20))
    window.close:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)

    window.search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    window.search:SetAutoFocus(false)
    window.search:SetHeight(S(18))
    window.search:SetPoint("TOPLEFT", window, "TOPLEFT", S(10), -S(5))
    window.search:SetPoint("RIGHT", window, "RIGHT", -S(90), 0)
    window.search:SetScript("OnTextChanged", function()
        for _, bagButtons in pairs(buttons) do
            for _, button in pairs(bagButtons) do if button:IsShown() then Bags.ApplySearch(button) end end
        end
    end)
    window.search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)

    local sort = (C_Container and C_Container.SortBags) or _G.SortBags
    window.sort = CreateFrame("Button", nil, window)
    window.sort:SetSize(S(50), S(18))
    window.sort:SetPoint("LEFT", window.search, "RIGHT", S(6), 0)
    Media:CreateBackdrop(window.sort)
    window.sort.label = Media:CreateText(window.sort, "OVERLAY")
    window.sort.label:SetPoint("CENTER")
    window.sort.label:SetText(L.BAGS_SORT)
    window.sort:SetScript("OnClick", function() if sort then sort() end end)
    if not sort then window.sort:Disable() window.sort:SetAlpha(0.4) end

    window.footer = Media:CreateText(window, "OVERLAY")
    window.footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", S(8), S(6))
    window.money = Media:CreateText(window, "OVERLAY")
    window.money:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -S(8), S(6))
end

function Bags:Update()
    if not window then return end
    local db = self.db
    local size = S(db.buttonSize)
    local columns = math.max(4, math.min(24, tonumber(db.columns) or 12))
    local index, free, total = 0, 0, 0
    for bag = 0, NS.NUM_BAGS do
        buttons[bag] = buttons[bag] or {}
        local slots = NS.GetBagSlots(bag)
        for slot = 1, math.max(slots, #buttons[bag]) do
            local button = buttons[bag][slot]
            if slot <= slots then
                button = button or NewButton(bag, slot)
                buttons[bag][slot] = button
                button:SetSize(size, size)
                button:ClearAllPoints()
                local row, column = math.floor(index / columns), index % columns
                button:SetPoint("TOPLEFT", window, "TOPLEFT", S(8) + column * (size + S(SPACING)),
                    -S(30) - row * (size + S(SPACING)))
                button:Show()
                Bags.UpdateButton(button, bag, slot)
                if not button.fuiItem then free = free + 1 end
                index, total = index + 1, total + 1
            elseif button then
                button:Hide()
            end
        end
    end
    local rows = math.max(1, math.ceil(index / columns))
    window:SetSize(S(16) + columns * (size + S(SPACING)) - S(SPACING),
        S(30) + rows * (size + S(SPACING)) + S(22))
    window.footer:SetText(string.format(L.BAGS_FREE, free, total))
    window.money:SetText(NS.FormatMoney(GetMoney()))
end

-- Rafales d'événements (GET_ITEM_INFO_RECEIVED, recharges) : une mise à jour par image au plus.
local updateQueued = false
events:SetScript("OnEvent", function()
    if not (active and window and window:IsShown()) or updateQueued then return end
    updateQueued = true
    C_Timer.After(0, function()
        updateQueued = false
        if active and window:IsShown() then Bags:Update() end
    end)
end)

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function Bags:GetWindow() return window, buttons end

function Bags:OnEnable()
    active = true
    if not window then Build() end
    NS.Movers:Register("bagWindow", window, L.MOVER_BAG_WINDOW, "BOTTOMRIGHT", -60, 120)
    NS.Movers:Load("bagWindow")
    TakeBlizzard()
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
                             "PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED" }) do
        NS.RegisterEventSafe(events, event)
    end
    Sync()
end

function Bags:OnDisable()
    active = false
    events:UnregisterAllEvents()
    RestoreBlizzard()
    if window then
        syncing = true   -- les sacs Blizzard restent ouverts : ils redeviennent visibles
        window:Hide()
        syncing = false
    end
    NS.Movers:Unregister("bagWindow")
end

function Bags:OnRefresh() if window and window:IsShown() then self:Update() end end

function Bags:BuildOptions(o)
    o:Slider("columns", L.OPT_BAGS_COLUMNS, 4, 24, 1)
    o:Slider("buttonSize", L.OPT_BAGS_SIZE, 24, 48, 1)
    o:Check("itemLevel", L.OPT_BAGS_ITEM_LEVEL)
    o:Check("junk", L.OPT_BAGS_JUNK)
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
end
