-- Modules/LootFeed.lua
-- Flux de butin : objets, or, monnaies et réputation gagnés, en lignes brèves qui s'effacent.
-- Un même gain répété (même objet, or, même monnaie ou faction) s'additionne sur sa ligne et en
-- prolonge l'affichage. Six lignes au plus, sans OnUpdate (minuterie et fondu animé).
-- Texte secret : rien d'affiché, une note dans les options.
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
    },
})

local MAX_LINES = 6
local SPACING = 2
local FADE_SECONDS = 0.5
local ICON_RETRY_SECONDS = 1
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local active = false
local holder
local lines = {}
local born = 0              -- ordre d'arrivée des lignes

local function Line(index)
    if lines[index] then return lines[index] end
    local line = CreateFrame("Frame", nil, holder)
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
        line:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(index - 1) * (size + SPACING))
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
        text = entry.quantity > 1 and (entry.label .. " x" .. entry.quantity) or entry.label
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
    for index = 1, MAX_LINES do
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

local function OnChatLine(text)
    if text == nil then return end
    if NS.IsSecret(text) then
        LootFeed.masked = true
        return
    end
    local parsed = NS.ParseLootLine(text)
    if not parsed then return end
    if parsed.kind == "item" and parsed.itemID then
        LootFeed:Add({ key = "item:" .. parsed.itemID, kind = "item", quantity = parsed.quantity,
                       label = parsed.link, itemID = parsed.itemID, icon = NS.GetItemIcon(parsed.itemID) })
    elseif parsed.kind == "money" then
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
    if not holder then holder = CreateFrame("Frame", "MuscaUILootFeed", UIParent) end
    active = true
    LayoutHolder()
    for _, event in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CURRENCY_DISPLAY_UPDATE" }) do
        NS.RegisterEventSafe(events, event)
    end
    if self.db.faction then NS.RegisterEventSafe(events, "CHAT_MSG_COMBAT_FACTION_CHANGE") end
    NS.Movers:Register("lootFeed", holder, L.MOVER_LOOTFEED, "LEFT", 40, 0)
    NS.Movers:Load("lootFeed")
    holder:Show()
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
    if holder then holder:Hide() end
end

function LootFeed:OnRefresh()
    if not (active and holder) then return end
    LayoutHolder()
    if self.db.faction then NS.RegisterEventSafe(events, "CHAT_MSG_COMBAT_FACTION_CHANGE")
    else events:UnregisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE") end
    Layout()
end

NS:On("PREVIEW", ShowPreview)

function LootFeed:BuildOptions(o)
    if self.masked then o:Note(L.LOOTFEED_MASKED) end
    o:Slider("size", L.OPT_LOOTFEED_SIZE, 14, 32, 1)
    o:Slider("duration", L.OPT_LOOTFEED_DURATION, 2, 15, 1)
    o:Check("faction", L.OPT_LOOTFEED_FACTION)
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
