-- Modules/LootFeed.lua
-- Flux de butin : objets, or, monnaies et réputation gagnés, en lignes brèves qui s'effacent.
-- Un même gain répété (même objet, or, même monnaie ou faction) s'additionne sur sa ligne et en
-- prolonge l'affichage. Six lignes au plus, sans OnUpdate (minuterie et fondu animé).
-- Texte secret : rien d'affiché, une note dans les options.
-- Option : or ramassé par heure depuis l'activation, sur une ligne fixe au-dessus du flux.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local LootFeed = NS.Modules:Register("lootfeed", {
    titleKey = "LOOTFEED_TITLE",
    descKey = "LOOTFEED_DESC",
    defaults = {
        enabled = true,
        size = 20,              -- hauteur d'une ligne et taille de l'icône
        duration = 5,           -- secondes d'affichage après le dernier gain
        faction = true,         -- gains de réputation
        maxLines = 6,           -- lignes affichées en même temps (1 à 6)
        growUp = false,         -- la ligne la plus récente en bas, le flux monte
        backgroundOpacity = 0,  -- fond noir derrière chaque ligne
        minQuality = 0,         -- objets sous cette qualité ignorés (0 : tous)
        itemLevel = false,      -- niveau d'objet après le nom d'un équipement
        itemPrice = false,      -- prix de vente du lot après le nom
        goldPerHour = false,    -- ligne fixe : or ramassé par heure
    },
})

local MAX_LINES = 6
local SPACING = 2
local FADE_SECONDS = 0.5
local ICON_RETRY_SECONDS = 1
local RATE_REFRESH_SECONDS = 30
local MIN_RATE_SECONDS = 60     -- pas d'extrapolation sur les premières secondes
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local active = false
local holder
local lines = {}
local born = 0              -- ordre d'arrivée des lignes
local rate, rateTicker      -- ligne d'or par heure et sa minuterie
local sessionStart, sessionCopper = 0, 0

local function Line(index)
    if lines[index] then return lines[index] end
    local line = CreateFrame("Frame", nil, holder)
    line.background = line:CreateTexture(nil, "BACKGROUND")
    line.background:SetAllPoints()
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    line.text = Media:CreateText(line, "OVERLAY", 0, "OUTLINE")
    line.text:SetJustifyH("LEFT")
    line.fade = line:CreateAnimationGroup()
    local alpha = line.fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetDuration(FADE_SECONDS)
    line.fade:SetScript("OnFinished", function() line:Hide() end)
    line.generation = 0
    line:Hide()
    lines[index] = line
    return line
end

-- Lignes vivantes, la plus récente en haut.
local function Layout()
    local size = LootFeed.db.size
    local _, themeSize = Media:Font()
    local fontDelta = math.floor(size * 0.6 + 0.5) - (themeSize or 12)   -- police à 60 % de la ligne
    local live = {}
    for _, line in ipairs(lines) do
        if line.key then live[#live + 1] = line end
    end
    table.sort(live, function(a, b) return a.born > b.born end)
    for index, line in ipairs(live) do
        line:ClearAllPoints()
        local offset = (index - 1) * (size + SPACING)
        if LootFeed.db.growUp then
            line:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, offset)
        else
            line:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -offset)
        end
        line.background:SetColorTexture(0, 0, 0, LootFeed.db.backgroundOpacity)
        line:SetSize(holder:GetWidth(), size)
        line.icon:ClearAllPoints()
        line.icon:SetPoint("LEFT", line, "LEFT", 0, 0)
        line.icon:SetSize(size, size)
        Media:SetTextSizeDelta(line.text, fontDelta)
        line.text:ClearAllPoints()
        line.text:SetPoint("LEFT", line, "LEFT", size + 4, 0)
    end
end

local function Render(line)
    local entry = line.entry
    local text
    if entry.kind == "money" then
        text = NS.FormatMoney(entry.quantity)
    elseif entry.kind == "faction" then
        text = entry.name .. " +" .. entry.quantity
    else
        text = entry.label
        if entry.level then text = text .. " [" .. entry.level .. "]" end
        if entry.quantity > 1 then text = text .. " x" .. entry.quantity end
        if entry.price and entry.price > 0 then text = text .. "  " .. NS.FormatMoney(entry.price * entry.quantity) end
    end
    line.text:SetText(text)
    line.icon:SetTexture(entry.icon)
    line.icon:SetShown(entry.icon ~= nil)
end

local function Expire(line)
    line.key = nil
    line.fade:Play()
    Layout()
end

local function Arm(line)
    line.generation = line.generation + 1
    if line.key:find("^preview") then return end   -- aperçu : affiché tant qu'il est actif
    local generation = line.generation
    C_Timer.After(LootFeed.db.duration, function()
        if line.generation == generation and line.key then Expire(line) end
    end)
end

-- Icône d'objet absente du cache : une relecture, puis le lien seul.
local function RetryIcon(line, key, itemID)
    C_Timer.After(ICON_RETRY_SECONDS, function()
        if line.key ~= key then return end
        line.entry.icon = NS.GetItemIcon(itemID)
        Render(line)
    end)
end

--- Ajoute un gain `entry` { key, kind, quantity, label, name, icon, itemID } : additionné à la
-- ligne de même clé, sinon nouvelle ligne (la plus ancienne cède sa place).
function LootFeed:Add(entry)
    if not active then return end
    local target, free, oldest
    for index = 1, LootFeed.db.maxLines do
        local line = Line(index)
        if line.key == entry.key then target = line break end
        if not line.key and not free then free = line end
        if line.key and (not oldest or line.born < oldest.born) then oldest = line end
    end
    if target then
        target.entry.quantity = target.entry.quantity + entry.quantity
    else
        target = free or oldest
        target.key, target.entry = entry.key, entry
        born = born + 1
        target.born = born
        if entry.kind == "item" and not entry.icon then RetryIcon(target, entry.key, entry.itemID) end
    end
    target.fade:Stop()
    target:SetAlpha(1)
    target:Show()
    Render(target)
    Arm(target)
    Layout()
    return target
end

--- Lignes affichées (tests) : { [index] = ligne }, `key` nil pour une ligne libre.
function LootFeed.Lines() return lines end

local function UpdateRate()
    if not rate then return end
    local show = active and LootFeed.db.goldPerHour
    if show then
        local elapsed = math.max(GetTime() - sessionStart, MIN_RATE_SECONDS)
        rate:SetFormattedText(L.LOOTFEED_GOLD_PER_HOUR, NS.FormatMoney(sessionCopper * 3600 / elapsed))
        rate:ClearAllPoints()
        if LootFeed.db.growUp then
            rate:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -SPACING)
        else
            rate:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, SPACING)
        end
    end
    rate:SetShown(show and true or false)
    if show and not rateTicker then
        rateTicker = C_Timer.NewTicker(RATE_REFRESH_SECONDS, UpdateRate)
    elseif not show and rateTicker then
        rateTicker:Cancel()
        rateTicker = nil
    end
end

--- Or ramassé par heure depuis l'activation (tests), en cuivre.
function LootFeed.GoldPerHour()
    return sessionCopper * 3600 / math.max(GetTime() - sessionStart, MIN_RATE_SECONDS)
end

-- Équipement seulement : un composant a aussi un niveau d'objet, sans intérêt ici.
local function EquipmentLevel(link)
    local equipLoc = NS.GetItemEquipInfo(link)
    if equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then return nil end
    return NS.GetItemLevel(link)
end

local function OnChatLine(text)
    if text == nil then return end
    if NS.IsSecret(text) then
        LootFeed.masked = true
        return
    end
    local parsed = NS.ParseLootLine(text)
    if not parsed then return end
    local db = LootFeed.db
    if parsed.kind == "item" and parsed.itemID then
        local quality = NS.GetItemQuality(parsed.link)   -- inconnue (hors cache) : affichée
        if quality and quality < db.minQuality then return end
        LootFeed:Add({ key = "item:" .. parsed.itemID, kind = "item", quantity = parsed.quantity,
                       label = parsed.link, itemID = parsed.itemID, icon = NS.GetItemIcon(parsed.itemID),
                       level = db.itemLevel and EquipmentLevel(parsed.link) or nil,
                       price = db.itemPrice and NS.GetItemSellPrice(parsed.link) or nil })
    elseif parsed.kind == "money" then
        sessionCopper = sessionCopper + parsed.copper
        UpdateRate()
        LootFeed:Add({ key = "money", kind = "money", quantity = parsed.copper, icon = MONEY_ICON })
    elseif parsed.kind == "faction" and LootFeed.db.faction then
        LootFeed:Add({ key = "faction:" .. parsed.name, kind = "faction", quantity = parsed.quantity,
                       name = parsed.name })
    end
end

local function OnCurrency(currencyType, _, change)
    if currencyType == nil or change == nil or NS.IsSecret(currencyType) or NS.IsSecret(change) then return end
    if type(change) ~= "number" or change <= 0 then return end
    local name, icon = NS.GetCurrencyDisplay(currencyType)
    if not name then return end
    LootFeed:Add({ key = "currency:" .. currencyType, kind = "currency", quantity = change, label = name,
                   icon = icon })
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CURRENCY_DISPLAY_UPDATE" then OnCurrency(...) else OnChatLine((...)) end
end)

local function ShowPreview()
    for _, line in ipairs(lines) do
        if line.key and line.key:find("^preview") then line.key = nil line:Hide() end
    end
    if not (active and NS:Previewing()) then
        Layout()
        return
    end
    LootFeed:Add({ key = "preview:item", kind = "item", quantity = 3, label = L.LOOTFEED_SAMPLE_ITEM,
                   icon = "Interface\\Icons\\INV_Misc_Bag_08" })
    LootFeed:Add({ key = "preview:money", kind = "money", quantity = 12345, icon = MONEY_ICON })
    LootFeed:Add({ key = "preview:faction", kind = "faction", quantity = 25, name = L.LOOTFEED_SAMPLE_FACTION })
end

local function LayoutHolder()
    local size = LootFeed.db.size
    holder:SetSize(size * 12, MAX_LINES * (size + SPACING) - SPACING)
end

function LootFeed:OnEnable()
    if not holder then
        holder = CreateFrame("Frame", "MuscaUILootFeed", UIParent)
        rate = Media:CreateText(holder, "OVERLAY", 0, "OUTLINE")
        rate:SetJustifyH("LEFT")
    end
    active = true
    sessionStart, sessionCopper = GetTime(), 0
    LayoutHolder()
    for _, event in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CURRENCY_DISPLAY_UPDATE" }) do
        NS.RegisterEventSafe(events, event)
    end
    if self.db.faction then NS.RegisterEventSafe(events, "CHAT_MSG_COMBAT_FACTION_CHANGE") end
    NS.Movers:Register("lootFeed", holder, L.MOVER_LOOTFEED, "LEFT", 40, 0)
    NS.Movers:Load("lootFeed")
    holder:Show()
    UpdateRate()
    ShowPreview()
end

function LootFeed:OnDisable()
    active = false
    events:UnregisterAllEvents()
    for _, line in ipairs(lines) do
        line.key = nil
        line:Hide()
    end
    NS.Movers:Unregister("lootFeed")
    UpdateRate()
    if holder then holder:Hide() end
end

function LootFeed:OnRefresh()
    if not (active and holder) then return end
    LayoutHolder()
    for index = self.db.maxLines + 1, MAX_LINES do   -- lignes au-delà du maximum : retirées
        if lines[index] then lines[index].key = nil lines[index]:Hide() end
    end
    if self.db.faction then NS.RegisterEventSafe(events, "CHAT_MSG_COMBAT_FACTION_CHANGE")
    else events:UnregisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE") end
    UpdateRate()
    Layout()
end

NS:On("PREVIEW", ShowPreview)

function LootFeed:BuildOptions(o)
    if self.masked then o:Note(L.LOOTFEED_MASKED) end
    o:Slider("size", L.OPT_LOOTFEED_SIZE, 14, 32, 1)
    o:Slider("duration", L.OPT_LOOTFEED_DURATION, 2, 15, 1)
    o:Check("faction", L.OPT_LOOTFEED_FACTION)
    o:Slider("maxLines", L.OPT_G_QOL_LOOT_MAX_LINES, 1, MAX_LINES, 1)
    o:Check("growUp", L.OPT_G_QOL_LOOT_GROW_UP)
    o:Slider("backgroundOpacity", L.OPT_G_QOL_LOOT_BACKGROUND, 0, 0.8, 0.05, 20, "%.2f")
    local qualities = {}
    for quality = 0, 5 do
        qualities[#qualities + 1] = { name = _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality), value = quality }
    end
    o:Dropdown("minQuality", L.OPT_M_QOL_LOOT_MIN_QUALITY, qualities)
    o:Check("itemLevel", L.OPT_M_QOL_LOOT_ITEM_LEVEL)
    o:Check("itemPrice", L.OPT_M_QOL_LOOT_ITEM_PRICE)
    o:Check("goldPerHour", L.OPT_M_QOL_LOOT_GOLD_PER_HOUR)
end

function LootFeed:BuildPreview(p)
    return function()
        local db = p.DB()
        p.Begin()
        local samples = {
            { "Interface\\Icons\\INV_Misc_Bag_08", "|cff1eff00" .. L.LOOTFEED_SAMPLE_ITEM .. "|r x3" },
            { MONEY_ICON, NS.FormatMoney(12345) },
            { nil, L.LOOTFEED_SAMPLE_FACTION .. " +25" },
        }
        local size = db.size
        local scale, x, y = p.Fit(size * 10, 3 * (size + SPACING), 8)
        size = size * scale
        for index, sample in ipairs(samples) do
            local top = y + (index - 1) * (size + SPACING)
            if sample[1] then p.Icon("icon" .. index, x, top, size, sample[1]) end
            p.Text("text" .. index, x + size + 4, top + size / 2, sample[2], size * 0.6, "LEFT")
        end
    end
end
