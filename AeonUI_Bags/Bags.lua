-- AeonUI_Bags/Bags.lua
-- Sacs tout-en-un léger : une seule fenêtre pour le sac à dos et les sacs équipés, sur son mover.
-- Recherche par nom, tri par l'API du client, niveau d'objet sur l'équipement, objets gris
-- signalés (pièce), bordure de qualité, recharges, emplacements libres et or.
--
-- Les cases sont les boutons des sacs Blizzard eux-mêmes, posés dans notre fenêtre : leur sac et
-- leur case sont écrits par Blizzard, donc l'utilisation en combat n'est pas bloquée (un SetID fait
-- par l'addon marque la case et bloque UseContainerItem). Les fenêtres de sacs Blizzard restent
-- ouvertes, invisibles et hors écran : leurs ouvertures et fermetures (touche B, marchand,
-- courrier) pilotent la nôtre, et fermer la nôtre les ferme. Banque : fenêtre Blizzard.
local NS = AeonUI
local L = NS.L
local Media = NS.Media

local Bags = NS.Modules:Register("bags", {
    titleKey = "BAGS_TITLE",
    descKey = "BAGS_DESC",
    defaults = {
        enabled = false,
        columns = 12,
        buttonSize = 34,
        itemLevel = true,
        junk = true,
        detachReagents = false,   -- sac de réactifs dans sa propre fenêtre (sur son mover)
        upgrade = true,           -- flèche sur l'équipement d'un niveau supérieur à la pièce portée
        newFirst = true,          -- objets arrivés depuis la dernière ouverture en tête
        pinned = "",              -- identifiants d'objets toujours en tête (« 6948, 2901 »)
        layout = "grid",          -- "grid" (ordre des sacs) ou "categories" (sections titrées)
        categoryOrder = "pinned, custom, new, equipment, consumable, tradegoods, quest, recipe, junk, other, empty",
        categoryNames = {},       -- [clé] = libellé choisi (vide : libellé par défaut)
        categoryShown = { pinned = true, new = true, equipment = true, consumable = true, tradegoods = true,
                          quest = true, recipe = true, junk = true },   -- décochée : objets rangés dans « Divers »
        customCategories = "",    -- une ligne par groupe : « Potions = 118, 858 »
    },
})

local MAX_CONTAINER_FRAMES = 13
local SPACING = 3
local COIN = "Interface\\Buttons\\UI-GroupLoot-Coin-Up"
-- Emplacements d'équipement sans niveau utile.
local NO_LEVEL = { [""] = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_TABARD = true,
                   INVTYPE_BODY = true, INVTYPE_AMMO = true, INVTYPE_NON_EQUIP_IGNORE = true }

-- Emplacement d'équipement -> emplacements portés comparés (le plus faible compte).
local EQUIP_SLOTS = {
    INVTYPE_HEAD = { "Head" }, INVTYPE_NECK = { "Neck" }, INVTYPE_SHOULDER = { "Shoulder" },
    INVTYPE_CHEST = { "Chest" }, INVTYPE_ROBE = { "Chest" }, INVTYPE_WAIST = { "Waist" }, INVTYPE_LEGS = { "Legs" },
    INVTYPE_FEET = { "Feet" }, INVTYPE_WRIST = { "Wrist" }, INVTYPE_HAND = { "Hands" },
    INVTYPE_FINGER = { "Finger0", "Finger1" }, INVTYPE_TRINKET = { "Trinket0", "Trinket1" }, INVTYPE_CLOAK = { "Back" },
    INVTYPE_WEAPON = { "MainHand", "SecondaryHand" }, INVTYPE_2HWEAPON = { "MainHand" },
    INVTYPE_WEAPONMAINHAND = { "MainHand" }, INVTYPE_WEAPONOFFHAND = { "SecondaryHand" },
    INVTYPE_SHIELD = { "SecondaryHand" }, INVTYPE_HOLDABLE = { "SecondaryHand" },
    INVTYPE_RANGED = { "Ranged" }, INVTYPE_RANGEDRIGHT = { "Ranged" }, INVTYPE_THROWN = { "Ranged" },
    INVTYPE_RELIC = { "Ranged" },
}

-- Catégories : ordre par défaut, et classe d'objet (GetItemInfoInstant) -> catégorie.
local CATEGORY_KEYS = { "pinned", "custom", "new", "equipment", "consumable", "tradegoods", "quest", "recipe",
                        "junk", "other", "empty" }
local CLASS_CATEGORY = { [0] = "consumable", [2] = "equipment", [4] = "equipment", [5] = "tradegoods",
                         [7] = "tradegoods", [9] = "recipe", [12] = "quest" }
local HEADER_HEIGHT = 16

local active = false
local window, reagentWindow
local buttons = {}          -- [bag] = { [slot] = bouton Blizzard }
local blizzardFrames = {}   -- [cadre Blizzard] = true : cadres pris en main
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
    return type(id) == "number" and ((id >= 0 and id <= NS.NUM_BAGS) or (NS.REAGENT_BAG ~= nil and id == NS.REAGENT_BAG))
end

local function BlizzardOpen()
    for _, frame in ipairs(BlizzardFrames()) do
        if frame:IsShown() and IsInventoryFrame(frame) then return true end
    end
    return false
end

--- Sacs d'inventaire invisibles et hors écran (ouverts quand même) ; trousseau et banque visibles.
local function ConcealBlizzard()
    -- Relevé à chaque passage : un cadre créé après l'activation (sac de réactifs) resterait
    -- sinon sous notre fenêtre, ses boutons masqués par notre fond.
    for _, frame in ipairs(BlizzardFrames()) do blizzardFrames[frame] = true end
    for frame in pairs(blizzardFrames) do
        if IsInventoryFrame(frame) then
            -- Strate au-dessus de notre fenêtre : ses boutons (enfants) passent devant notre fond.
            frame:SetFrameStrata("DIALOG")
            frame:SetAlpha(0)
            frame:SetClampedToScreen(false)
            frame:ClearAllPoints()
            frame:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -10000, 0)
        else
            frame:SetFrameStrata("MEDIUM")
            frame:SetAlpha(1)
        end
    end
end

-- Rafales d'événements (GET_ITEM_INFO_RECEIVED, recharges, mise en page Blizzard) : une mise à
-- jour par image au plus.
local updateQueued = false
local function QueueUpdate()
    if not (active and window and window:IsShown()) or updateQueued then return end
    updateQueued = true
    C_Timer.After(0, function()
        updateQueued = false
        if active and window:IsShown() then Bags:Update() end
    end)
end

--- Notre fenêtre suit l'état des sacs Blizzard (ouverts, mais invisibles).
local function Sync()
    if not active or syncing or not window then return end
    ConcealBlizzard()
    syncing = true
    local wasShown = window:IsShown()
    local ok, err = pcall(window.SetShown, window, BlizzardOpen())
    syncing = false
    if not ok then geterrorhandler()(err) end
    if wasShown then QueueUpdate() end   -- sacs rouverts : Blizzard a refait ses boutons
end

-- Fonctions d'ouverture et de fermeture suivies (appelées par Blizzard : B, marchand, courrier).
local TOGGLES = { "OpenAllBags", "CloseAllBags", "ToggleAllBags", "OpenBackpack", "CloseBackpack",
                  "ToggleBackpack", "OpenBag", "CloseBag", "ToggleBag" }
local hooked = false
local function TakeBlizzard()
    ConcealBlizzard()
    if hooked then return end
    hooked = true
    for _, name in ipairs(TOGGLES) do
        if _G[name] then hooksecurefunc(name, Sync) end
    end
    if _G.UpdateContainerFrameAnchors then
        hooksecurefunc("UpdateContainerFrameAnchors", function() if active then ConcealBlizzard() end end)
    end
end

--- Rend un bouton décoré à son état Blizzard (taille, fond, ajouts, alpha).
local function RestoreButton(button)
    if button.SetIgnoreParentAlpha then button:SetIgnoreParentAlpha(false) end
    button.aeonLevel:Hide()
    button.aeonJunk:Hide()
    button.aeonBg:Hide()
    for _, edge in pairs(button.aeonBorder) do edge:Hide() end
    button:SetAlpha(1)
    if button.aeonSize then button:SetSize(unpack(button.aeonSize)) end
end

local function RestoreBlizzard()
    for frame in pairs(blizzardFrames) do
        frame:SetFrameStrata("MEDIUM")
        frame:SetAlpha(1)
        frame:SetClampedToScreen(true)
    end
    for _, bagButtons in pairs(buttons) do
        for _, button in pairs(bagButtons) do RestoreButton(button) end
    end
    wipe(buttons)
    for frame in pairs(blizzardFrames) do
        if frame:IsShown() and frame.UpdateItemLayout then frame:UpdateItemLayout() end
    end
    if _G.UpdateContainerFrameAnchors then UpdateContainerFrameAnchors() end
end

--------------------------------------------------------------------------------
-- Boutons
--------------------------------------------------------------------------------

--- Nos ajouts sur un bouton Blizzard : champs préfixés, jamais lus par le code Blizzard.
local function Decorate(button)
    if button.aeonLevel then
        button.aeonBg:Show()
        for _, edge in pairs(button.aeonBorder) do edge:Show() end
        return
    end
    button.aeonSize = { button:GetWidth(), button:GetHeight() }   -- taille Blizzard, rendue par RestoreButton
    local bg, edges = Media:CreateBackdrop(button)
    button.aeonBg = bg
    button.aeonBorder = edges
    button.aeonLevel = Media:CreateText(button, "OVERLAY", -1, "OUTLINE")
    button.aeonLevel:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.aeonJunk = button:CreateTexture(nil, "OVERLAY")
    button.aeonJunk:SetTexture(COIN)
    button.aeonJunk:SetSize(S(12), S(12))
    button.aeonJunk:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
    button.aeonUpgrade = button:CreateTexture(nil, "OVERLAY")
    button.aeonUpgrade:SetSize(S(12), S(12))
    button.aeonUpgrade:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    if not button.aeonUpgrade:SetAtlas("bags-greenarrow") then NS.SetSolidColor(button.aeonUpgrade, 0.2, 0.9, 0.3, 1) end
end

Bags.Decorate = Decorate   -- repris par la banque (AeonUI_Bags/Bank.lua)

--- Boutons des sacs Blizzard ouverts, dans l'ordre sac puis case.
local function BlizzardButtons()
    local list = {}
    for _, frame in ipairs(BlizzardFrames()) do
        if frame:IsShown() and IsInventoryFrame(frame) and frame.EnumerateValidItems then
            for _, button in frame:EnumerateValidItems() do
                if button then list[#list + 1] = button end
            end
        end
    end
    table.sort(list, function(a, b)
        local bagA, bagB = a:GetBagID(), b:GetBagID()
        if bagA ~= bagB then return bagA < bagB end
        return a:GetID() < b:GetID()
    end)
    return list
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

--------------------------------------------------------------------------------
-- Catégories
--------------------------------------------------------------------------------

--- Groupes libres : { [itemID] = nom du groupe }, et les noms dans l'ordre des lignes.
function Bags.CustomCategories(text)
    local byItem, names = {}, {}
    for line in tostring(text or ""):gmatch("[^\n]+") do
        local name, ids = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if name and name ~= "" then
            names[#names + 1] = name
            for id in ids:gmatch("%d+") do byItem[tonumber(id)] = byItem[tonumber(id)] or name end
        end
    end
    return byItem, names
end

--- Ordre des sections : liste du joueur (mots inconnus écartés), clés oubliées ajoutées ensuite.
function Bags.CategoryOrder(text)
    local order, seen = {}, {}
    local known = {}
    for _, key in ipairs(CATEGORY_KEYS) do known[key] = true end
    for word in tostring(text or ""):lower():gmatch("%a+") do
        if known[word] and not seen[word] then seen[word] = true order[#order + 1] = word end
    end
    for _, key in ipairs(CATEGORY_KEYS) do
        if not seen[key] then order[#order + 1] = key end
    end
    return order
end

local function ItemClass(item)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if not getInstant then return nil end
    return select(6, getInstant(item.link or item.itemID))
end

--- Catégorie d'une case : « custom:<nom> » pour un groupe libre, sinon une clé de CATEGORY_KEYS.
-- Une catégorie décochée renvoie ses objets dans « other ».
function Bags.Category(item, bag, slot, pinned, custom)
    if not item then return "empty" end
    local db = Bags.db
    local shown = db.categoryShown
    if custom[item.itemID] then return "custom:" .. custom[item.itemID] end
    local key
    if pinned[item.itemID] then key = "pinned"
    elseif NS.IsNewBagItem(bag, slot) then key = "new"
    elseif item.quality == 0 and not item.hasNoValue then key = "junk"
    else key = CLASS_CATEGORY[ItemClass(item)] or "other" end
    if key ~= "other" and not shown[key] then
        -- Épinglé ou récent décoché : la catégorie de l'objet lui-même.
        if key == "pinned" or key == "new" then
            key = (item.quality == 0 and not item.hasNoValue and shown.junk) and "junk" or CLASS_CATEGORY[ItemClass(item)] or "other"
            if key ~= "other" and not shown[key] then key = "other" end
        else
            key = "other"
        end
    end
    return key
end

--- Libellé d'une section : nom choisi, sinon celui de la langue ; groupe libre : son nom.
function Bags.CategoryLabel(key)
    local custom = key:match("^custom:(.+)$")
    if custom then return custom end
    local name = Bags.db.categoryNames[key]
    if type(name) == "string" and name ~= "" then return name end
    return L["BAGS_CATEGORY_" .. key:upper()] or key
end

--- Sections dans l'ordre : { { key, label, buttons } }, sections vides écartées.
function Bags.Sections(list)
    local db = Bags.db
    local pinned = NS.ParseSpellList(db.pinned)
    local custom, customNames = Bags.CustomCategories(db.customCategories)
    local byKey = {}
    for _, button in ipairs(list) do
        local bag, slot = button:GetBagID(), button:GetID()
        local key = Bags.Category(NS.GetBagItem(bag, slot), bag, slot, pinned, custom)
        byKey[key] = byKey[key] or {}
        table.insert(byKey[key], button)
    end
    local sections = {}
    for _, key in ipairs(Bags.CategoryOrder(db.categoryOrder)) do
        local keys = { key }
        if key == "custom" then
            keys = {}
            for _, name in ipairs(customNames) do keys[#keys + 1] = "custom:" .. name end
        end
        for _, sectionKey in ipairs(keys) do
            if byKey[sectionKey] then
                sections[#sections + 1] = { key = sectionKey, label = Bags.CategoryLabel(sectionKey), buttons = byKey[sectionKey] }
                byKey[sectionKey] = nil
            end
        end
    end
    return sections
end

--- Équipement d'un niveau supérieur à la pièce portée la plus faible de son emplacement (case
-- vide : oui). ponytail: niveau seul, sans la maîtrise d'armure ; à croiser avec l'utilisable si besoin.
function Bags.IsUpgrade(item, level)
    local slots = level and EQUIP_SLOTS[EquipLocation(item)]
    if not slots then return false end
    local lowest
    for _, slotName in ipairs(slots) do
        local link = NS.GetEquipped(slotName)
        local worn = link and NS.GetItemLevel(link) or 0
        if not lowest or worn < lowest then lowest = worn end
    end
    return level > lowest
end

--- Icône, quantité et recharge : peintes par Blizzard. Ici niveau, camelote, bordure, recherche.
function Bags.UpdateButton(button, bag, slot)
    local db = Bags.db
    local item = NS.GetBagItem(bag, slot)
    button.aeonItem = item
    local r, g, b
    if not item then
        button.aeonLevel:Hide()
        button.aeonJunk:Hide()
        button.aeonUpgrade:Hide()
        local c = NS.db.theme.border
        r, g, b = c.r, c.g, c.b
    else
        local level = db.itemLevel and not NO_LEVEL[EquipLocation(item)] and item.link
            and NS.GetItemLevel(item.link)
        button.aeonLevel:SetText(level and tostring(level) or "")
        button.aeonLevel:SetTextColor(NS.QualityColor(item.quality))
        button.aeonLevel:SetShown(level and true or false)
        button.aeonJunk:SetShown(db.junk and item.quality == 0 and not item.hasNoValue)
        local itemLevel = db.upgrade and item.link and NS.GetItemLevel(item.link)
        button.aeonUpgrade:SetShown(itemLevel and Bags.IsUpgrade(item, itemLevel) or false)
        if item.quality and item.quality >= 2 then r, g, b = NS.QualityColor(item.quality)
        else local c = NS.db.theme.border r, g, b = c.r, c.g, c.b end
    end
    for _, edge in pairs(button.aeonBorder) do NS.SetSolidColor(edge, r, g, b, 1) end
    Bags.ApplySearch(button)
end

--- Recherche : objets qui ne correspondent pas atténués.
function Bags.ApplySearch(button)
    local query = window and window.search and window.search:GetText() or ""
    query = NS.Modules.SortKey(query):match("^%s*(.-)%s*$")
    local match = query == "" or (button.aeonItem and ItemName(button.aeonItem):find(query, 1, true) ~= nil)
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
        reagentWindow:Hide()
        if not syncing and BlizzardOpen() and _G.CloseAllBags then CloseAllBags() end
    end)

    reagentWindow = CreateFrame("Frame", "AeonUIBagsReagents", UIParent)
    reagentWindow:SetFrameStrata("HIGH")
    reagentWindow:SetClampedToScreen(true)
    reagentWindow:EnableMouse(true)
    Media:CreateBackdrop(reagentWindow)
    reagentWindow:Hide()
    reagentWindow.title = Media:CreateText(reagentWindow, "OVERLAY")
    reagentWindow.title:SetPoint("TOPLEFT", reagentWindow, "TOPLEFT", S(8), -S(8))
    reagentWindow.title:SetText(L.BAGS_REAGENTS)
    window:SetScript("OnShow", function() Bags:Update() end)

    window.close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    window.close:SetSize(S(20), S(20))
    window.close:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)

    window.search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    window.search:SetAutoFocus(false)
    window.search:SetHeight(S(18))
    window.search:SetPoint("TOPLEFT", window, "TOPLEFT", S(10), -S(5))
    window.search:SetPoint("RIGHT", window, "RIGHT", -S(146), 0)
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

    window.stack = CreateFrame("Button", nil, window)
    window.stack:SetSize(S(50), S(18))
    window.stack:SetPoint("LEFT", window.sort, "RIGHT", S(6), 0)
    Media:CreateBackdrop(window.stack)
    window.stack.label = Media:CreateText(window.stack, "OVERLAY")
    window.stack.label:SetPoint("CENTER")
    window.stack.label:SetText(L.BAGS_STACK)
    window.stack:SetScript("OnClick", function() Bags:StartMerge() end)

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
    ConcealBlizzard()
    local list = BlizzardButtons()
    -- Objets épinglés, puis arrivés récemment, puis l'ordre des sacs.
    local pinned = NS.ParseSpellList(db.pinned)
    if next(pinned) or db.newFirst then
        local rank, order = {}, {}
        for index, button in ipairs(list) do
            local bag, slot = button:GetBagID(), button:GetID()
            local item = NS.GetBagItem(bag, slot)
            order[button] = index
            rank[button] = (item and pinned[item.itemID]) and 1 or (db.newFirst and NS.IsNewBagItem(bag, slot)) and 2 or 3
        end
        table.sort(list, function(a, b)
            if rank[a] ~= rank[b] then return rank[a] < rank[b] end
            return order[a] < order[b]
        end)
    end
    -- Blizzard réutilise un ContainerFrame (trousseau, banque) : ses boutons décorés pour un
    -- sac d'inventaire qui ne sont plus dans la liste retrouvent leur état Blizzard.
    local kept = {}
    for _, button in ipairs(list) do kept[button] = true end
    for _, bagButtons in pairs(buttons) do
        for _, button in pairs(bagButtons) do
            if not kept[button] then RestoreButton(button) end
        end
    end
    wipe(buttons)
    -- Sac de réactifs détaché : ses cases dans la seconde fenêtre.
    local main, reagents = {}, {}
    for _, button in ipairs(list) do
        local detached = db.detachReagents and NS.REAGENT_BAG ~= nil and button:GetBagID() == NS.REAGENT_BAG
        if detached then reagents[#reagents + 1] = button else main[#main + 1] = button end
    end
    local free = 0
    -- Sections posées l'une sous l'autre, chacune sur des rangées neuves ; titre au besoin.
    local function Place(sections, parent)
        local top = S(30)
        parent.headers = parent.headers or {}
        local headerCount = 0
        for _, section in ipairs(sections) do
            if section.label then
                headerCount = headerCount + 1
                local header = parent.headers[headerCount]
                if not header then
                    header = Media:CreateText(parent, "OVERLAY")
                    parent.headers[headerCount] = header
                end
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", parent, "TOPLEFT", S(8), -top)
                header:SetText(section.label)
                header:Show()
                top = top + S(HEADER_HEIGHT)
            end
            for index, button in ipairs(section.buttons) do
                local bag, slot = button:GetBagID(), button:GetID()
                buttons[bag] = buttons[bag] or {}
                buttons[bag][slot] = button
                Decorate(button)
                -- Enfant du cadre Blizzard invisible (strate DIALOG, au-dessus de notre fenêtre) : visible quand même.
                if button.SetIgnoreParentAlpha then button:SetIgnoreParentAlpha(true) end
                button:SetSize(size, size)
                button:ClearAllPoints()
                local row, column = math.floor((index - 1) / columns), (index - 1) % columns
                button:SetPoint("TOPLEFT", parent, "TOPLEFT", S(8) + column * (size + S(SPACING)),
                    -top - row * (size + S(SPACING)))
                Bags.UpdateButton(button, bag, slot)
                if not button.aeonItem then free = free + 1 end
            end
            top = top + math.max(1, math.ceil(#section.buttons / columns)) * (size + S(SPACING))
        end
        for index = headerCount + 1, #parent.headers do parent.headers[index]:Hide() end
        if #sections == 0 then top = top + size + S(SPACING) end
        parent:SetSize(S(16) + columns * (size + S(SPACING)) - S(SPACING), top + S(22))
    end
    if db.layout == "categories" then Place(Bags.Sections(main), window)
    else Place({ { buttons = main } }, window) end
    Place({ { buttons = reagents } }, reagentWindow)
    reagentWindow:SetShown(window:IsShown() and #reagents > 0)
    window.footer:SetText(string.format(L.BAGS_FREE, free, #list))
    window.money:SetText(NS.FormatMoney(GetMoney()))
end

--------------------------------------------------------------------------------
-- Fusion des piles
--------------------------------------------------------------------------------
-- Une étape par BAG_UPDATE_DELAYED : une pile partielle versée sur une autre du même objet, hors
-- combat et curseur vide ; s'arrête quand plus rien n'est à fusionner.

--- Lance une étape ; false quand il n'y a plus rien à fusionner (ou combat, curseur chargé).
function Bags:MergeStep()
    if NS.InCombat() or (_G.GetCursorInfo and GetCursorInfo()) then return false end
    local partial = {}   -- [itemID] = { bag, slot }
    for bag = 0, NS.NUM_BAGS do
        for slot = 1, NS.GetBagSlots(bag) do
            local item = NS.GetBagItem(bag, slot)
            local max = item and not item.isLocked and item.itemID and NS.GetItemMaxStack(item.itemID)
            if max and max > 1 and item.stackCount < max then
                local target = partial[item.itemID]
                if target then
                    NS.PickupBagItem(bag, slot)
                    NS.PickupBagItem(target[1], target[2])
                    if _G.GetCursorInfo and GetCursorInfo() and _G.ClearCursor then ClearCursor() end   -- reste : rendu
                    return true
                end
                partial[item.itemID] = { bag, slot }
            end
        end
    end
    return false
end

function Bags:StartMerge()
    self.merging = self:MergeStep()
end

events:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" and Bags.merging then Bags.merging = Bags:MergeStep() end
    QueueUpdate()
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
    if NS.REAGENT_BAG then
        NS.Movers:Register("bagReagents", reagentWindow, L.MOVER_BAG_REAGENTS, "BOTTOMRIGHT", -500, 120)
        NS.Movers:Load("bagReagents")
    end
    TakeBlizzard()
    -- Pas de hook sur les méthodes des cadres Blizzard (mise en page contaminée) : leurs
    -- remises en grille suivent les ouvertures (Sync) et les changements de sacs.
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
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
    NS.Movers:Unregister("bagReagents")
end

function Bags:OnRefresh() if window and window:IsShown() then self:Update() end end

function Bags:BuildOptions(o)
    o:Slider("columns", L.OPT_BAGS_COLUMNS, 4, 24, 1)
    o:Slider("buttonSize", L.OPT_BAGS_SIZE, 24, 48, 1)
    o:Check("itemLevel", L.OPT_BAGS_ITEM_LEVEL)
    o:Check("junk", L.OPT_BAGS_JUNK)
    if NS.REAGENT_BAG then o:Check("detachReagents", L.OPT_BAGS_DETACH_REAGENTS) end
    o:Check("upgrade", L.OPT_BAGS_UPGRADE)
    o:Check("newFirst", L.OPT_BAGS_NEW_FIRST)
    o:Advanced()
    o:EditBox("pinned", L.OPT_BAGS_PINNED, 1)
    o:EndAdvanced()
    o:Title(L.OPT_BAGS_CATEGORIES_TITLE)
    o:Dropdown("layout", L.OPT_BAGS_LAYOUT, {
        { name = L.OPT_BAGS_LAYOUT_GRID, value = "grid" }, { name = L.OPT_BAGS_LAYOUT_CATEGORIES, value = "categories" },
    })
    o:Advanced()
    o:EditBox("categoryOrder", L.OPT_BAGS_CATEGORY_ORDER, 2, 36)
    o.layout:Hint(L.OPT_BAGS_CATEGORY_ORDER_HINT)
    o:EndAdvanced()
    for _, key in ipairs(CATEGORY_KEYS) do
        if Bags.defaults.categoryShown[key] ~= nil then
            o:Check("categoryShown." .. key, L["BAGS_CATEGORY_" .. key:upper()], 36)
        end
    end
    o:Advanced()
    o:EditBox("customCategories", L.OPT_BAGS_CUSTOM_CATEGORIES, 3, 36)
    o.layout:Hint(L.OPT_BAGS_CUSTOM_CATEGORIES_HINT)
    for _, key in ipairs(CATEGORY_KEYS) do
        if key ~= "custom" then
            o:EditBox("categoryNames." .. key, string.format(L.OPT_BAGS_CATEGORY_NAME, L["BAGS_CATEGORY_" .. key:upper()]), 1, 36)
        end
    end
    o:EndAdvanced()
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
end
