-- MuscaUI_Bags/Bank.lua
-- Banque MuscaUI : une fenêtre au thème à la place de la banque Blizzard, un onglet par coffre
-- acheté du personnage puis du bataillon (moteur retail, sac lu dans l'ID de l'onglet), plus un
-- onglet « Tous » par type ; sinon la banque classique et ses sacs. Cases décorées comme celles
-- des sacs, recherche propre à la banque, tri du client.
--
-- Cases créées par l'addon (ContainerFrameItemButtonTemplate, sac porté par le parent) : pas de
-- combat au guichet, le marquage des SetID ne gêne pas. La banque Blizzard est reparentée sur un
-- cadre caché (jamais Hide ni SetScript, qui couperaient ses événements), rendue au disable.
local NS = MuscaUI
local L = NS.L
local Media = NS.Media

local Bank = NS.Modules:Register("bank", {
    titleKey = "BANK_TITLE",
    descKey = "BANK_DESC",
    defaults = {
        enabled = false,
        columns = 14,
        buttonSize = 34,
    },
})

local SPACING = 3
local SORT_SETTLE = 1       -- tri fini : aucun BAG_UPDATE_DELAYED depuis ce délai (réarmé à chaque événement)
local active = false
local open = false          -- guichet ouvert (BANKFRAME_OPENED .. BANKFRAME_CLOSED)
local window, hiddenParent, originalParent
local tabButtons, slots, tabFrames = {}, {}, {}
local selected = 1
local sorting, sortToken = false, 0

local function S(n) return NS.Pixel:Scale(n) end

--- Coffres de la banque : { { bags, name, bankType } }. Moteur retail : onglets achetés du
-- personnage puis du bataillon (bataillon seul chez un banquier de bataillon), « Tous » en tête de
-- chaque type qui en a plusieurs. Sinon banque classique et ses sacs, sans bankType.
function Bank.Tabs()
    local tabs = {}
    local types = _G.Enum and Enum.BankType
    if types then
        local kinds = NS.IsAccountBanker() and { types.Account } or { types.Character, types.Account }
        for _, bankType in ipairs(kinds) do
            local warband = bankType == types.Account
            local list, bags = {}, {}
            for i, data in ipairs(NS.GetBankTabs(bankType)) do
                if NS.GetBagSlots(data.bag) > 0 then
                    local name = data.name ~= nil and data.name ~= "" and data.name
                        or string.format(warband and L.BANK_WARBAND_TAB or L.BANK_TAB, i)
                    list[#list + 1] = { bags = { data.bag }, name = name, bankType = bankType }
                    bags[#bags + 1] = data.bag
                end
            end
            if #list > 1 then tabs[#tabs + 1] = { bags = bags, name = warband and L.BANK_WARBAND or L.BANK_ALL, bankType = bankType } end
            for _, tab in ipairs(list) do tabs[#tabs + 1] = tab end
        end
    end
    if #tabs > 0 then return tabs end
    local index = _G.Enum and Enum.BagIndex
    local bank = index and index.Bank or _G.BANK_CONTAINER or -1
    tabs[1] = { bags = { bank }, name = L.BANK_TITLE }
    for i = 1, _G.NUM_BANKBAGSLOTS or 7 do
        local bag = index and index["BankBag_" .. i] or (NS.NUM_BAGS + i)
        if NS.GetBagSlots(bag) > 0 then tabs[#tabs + 1] = { bags = { bag }, name = string.format(L.BANK_BAG, i) } end
    end
    return tabs
end

-- Bouton Trier rendu quand les sacs se sont tus SORT_SETTLE secondes.
local function ArmSort()
    sortToken = sortToken + 1
    local token = sortToken
    C_Timer.After(SORT_SETTLE, function()
        if token ~= sortToken or not sorting then return end
        sorting = false
        Bank:Update()
    end)
end

local function TabFrame(bag)
    local frame = tabFrames[bag]
    if frame then return frame end
    frame = CreateFrame("Frame", nil, window)
    frame:SetAllPoints(window)
    frame:SetID(bag)   -- lu par ContainerFrameItemButtonTemplate (GetBagID = parent:GetID())
    tabFrames[bag] = frame
    return frame
end

local function Slot(index)
    local button = slots[index]
    if button then return button end
    button = CreateFrame("ItemButton", "MuscaUIBankSlot" .. index, window, "ContainerFrameItemButtonTemplate")
    if not button.GetBagID then function button:GetBagID() return self:GetParent():GetID() end end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    NS.Modules:Get("bags").Decorate(button)
    slots[index] = button
    return button
end

local function Paint(button, item)
    if _G.SetItemButtonTexture then SetItemButtonTexture(button, item and item.icon) end
    if _G.SetItemButtonCount then SetItemButtonCount(button, item and item.stackCount or 0) end
    if _G.SetItemButtonDesaturated then SetItemButtonDesaturated(button, item and item.isLocked) end
end

function Bank:Update()
    if not (window and window:IsShown()) then return end
    local db = self.db
    local tabs = self.Tabs()
    selected = math.max(1, math.min(selected, #tabs))
    local size, columns = S(db.buttonSize), math.max(4, math.min(24, db.columns))
    local width = S(16) + columns * (size + S(SPACING)) - S(SPACING)
    local x, y = S(8), -S(6)
    for index, tab in ipairs(tabs) do
        local button = tabButtons[index]
        if not button then
            button = CreateFrame("Button", nil, window)
            button.bg, button.edges = Media:CreateBackdrop(button)
            button.label = Media:CreateText(button, "OVERLAY")
            button.label:SetPoint("CENTER")
            button:SetScript("OnClick", function(self) selected = self.index Bank:Update() end)
            tabButtons[index] = button
        end
        button.index = index
        button.label:SetText(tab.name)
        local w = math.max(S(60), (button.label:GetStringWidth() or 0) + S(12))
        button:SetSize(w, S(18))
        -- Écart entre personnage et bataillon, retour à la ligne au bord de la fenêtre.
        if index > 1 and tab.bankType ~= tabs[index - 1].bankType then x = x + S(8) end
        if x > S(8) and x + w > width - (y == -S(6) and S(32) or S(8)) then x, y = S(8), y - S(22) end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", window, "TOPLEFT", x, y)
        x = x + w + S(4)
        local accent = index == selected and NS.db.theme.accent or NS.db.theme.border
        for _, edge in pairs(button.edges or {}) do NS.SetSolidColor(edge, accent.r, accent.g, accent.b, 1) end
        button.label:SetTextColor(index == selected and 1 or 0.65, index == selected and 1 or 0.65, index == selected and 1 or 0.65)
        button:Show()
    end
    for index = #tabs + 1, #tabButtons do tabButtons[index]:Hide() end

    local tab = tabs[selected]
    window.search:SetPoint("TOPLEFT", window, "TOPLEFT", S(10), y - S(24))
    local top = y - S(48)
    local query = window.search:GetText() or ""
    local count, free = 0, 0
    for _, bag in ipairs(tab and tab.bags or {}) do
        local parent = TabFrame(bag)
        free = free + NS.GetBagFreeSlots(bag)
        for slot = 1, NS.GetBagSlots(bag) do
            count = count + 1
            local button = Slot(count)
            button:SetParent(parent)
            button:SetID(slot)
            button:SetSize(size, size)
            button:ClearAllPoints()
            local row, column = math.floor((count - 1) / columns), (count - 1) % columns
            button:SetPoint("TOPLEFT", window, "TOPLEFT", S(8) + column * (size + S(SPACING)), top - row * (size + S(SPACING)))
            Paint(button, NS.GetBagItem(bag, slot))
            NS.Modules:Get("bags").UpdateButton(button, bag, slot, query)
            button:Show()
        end
    end
    for index = count + 1, #slots do slots[index]:Hide() end
    local rows = math.max(1, math.ceil(count / columns))
    window:SetSize(width, -top + rows * (size + S(SPACING)) + S(26))

    local bankType = tab and tab.bankType
    local text = tab and string.format(L.BAGS_FREE, free, count) or ""
    local money = bankType ~= nil and NS.GetBankMoney(bankType)
    if money then text = text .. "   " .. NS.FormatMoney(money) end
    window.footer:SetText(text)
    local deposit = bankType ~= nil and NS.BankSupportsAutoDeposit(bankType)
    if deposit then
        window.deposit.bankType = bankType
        window.deposit.label:SetText(bankType == Enum.BankType.Account and L.BANK_DEPOSIT_WARBAND or L.BANK_DEPOSIT_REAGENTS)
    end
    window.deposit:SetShown(deposit and true or false)
    window.sort.bankType = bankType
    window.sort:SetShown(bankType ~= nil)
    if sorting then window.sort:Disable() else window.sort:Enable() end
    window.sort:SetAlpha(sorting and 0.4 or 1)
end

local function TextButton(label, width)
    local button = CreateFrame("Button", nil, window)
    button:SetSize(S(width), S(18))
    Media:CreateBackdrop(button)
    button.label = Media:CreateText(button, "OVERLAY")
    button.label:SetPoint("CENTER")
    button.label:SetText(label)
    return button
end

local function Build()
    window = CreateFrame("Frame", "MuscaUIBank", UIParent)
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    Media:CreateBackdrop(window)
    window:Hide()
    tinsert(UISpecialFrames, "MuscaUIBank")
    window.close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    window.close:SetSize(S(20), S(20))
    window.close:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
    -- Fermer la nôtre (Échap, croix) ferme le guichet.
    window:SetScript("OnHide", function()
        if open then NS.CloseBank() end
    end)
    window.footer = Media:CreateText(window, "OVERLAY")
    window.footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", S(8), S(6))
    window.deposit = TextButton(L.BANK_DEPOSIT_REAGENTS, 130)
    window.deposit:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -S(8), S(4))
    window.deposit:SetScript("OnClick", function(self) NS.BankAutoDeposit(self.bankType) end)
    window.footer:SetPoint("RIGHT", window.deposit, "LEFT", -S(4), 0)
    window.footer:SetJustifyH("LEFT")
    -- Recherche propre à la banque : même comparateur que les sacs, filtrée par nous (pas SetItemSearch).
    window.search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    window.search:SetAutoFocus(false)
    window.search:SetHeight(S(18))
    window.search:SetPoint("RIGHT", window, "RIGHT", -S(66), 0)
    window.search:SetScript("OnTextChanged", function(self)
        local Bags = NS.Modules:Get("bags")
        for _, button in ipairs(slots) do if button:IsShown() then Bags.ApplySearch(button, self:GetText() or "") end end
    end)
    window.search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    -- Tri du client, sans la confirmation de Blizzard (dit dans l'infobulle).
    window.sort = TextButton(L.BAGS_SORT, 50)
    window.sort:SetPoint("LEFT", window.search, "RIGHT", S(6), 0)
    window.sort:SetScript("OnClick", function(self)
        if sorting or not NS.SortBank(self.bankType) then return end
        sorting = true
        ArmSort()
        Bank:Update()
    end)
    window.sort:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.BANK_SORT_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    window.sort:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hiddenParent = CreateFrame("Frame")
    hiddenParent:Hide()
end

local function TakeBlizzard()
    local frame = _G.BankFrame
    if not frame or frame:GetParent() == hiddenParent then return end
    originalParent = frame:GetParent()
    frame:SetParent(hiddenParent)
end

local function RestoreBlizzard()
    local frame = _G.BankFrame
    if frame and originalParent and frame:GetParent() == hiddenParent then frame:SetParent(originalParent) end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" and sorting then ArmSort() end
    if event == "BANKFRAME_OPENED" then
        open, selected, sorting = true, 1, false
        TakeBlizzard()
        window:Show()
        Bank:Update()
    elseif event == "BANKFRAME_CLOSED" then
        open = false
        window:Hide()
    else
        Bank:Update()
    end
end)

function Bank:GetWindow() return window, slots, tabButtons end

function Bank:OnEnable()
    if not window then Build() end
    active = true
    for _, event in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED",
                             "ITEM_LOCK_CHANGED", "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED",
                             "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" }) do
        NS.RegisterEventSafe(events, event)
    end
    NS.Movers:Register("bankWindow", window, L.BANK_TITLE, "TOPLEFT", 60, -120)
    NS.Movers:Load("bankWindow")
end

function Bank:OnDisable()
    active = false
    events:UnregisterAllEvents()
    open = false
    window:Hide()
    RestoreBlizzard()
    NS.Movers:Unregister("bankWindow")
end

function Bank:OnRefresh() self:Update() end

function Bank:BuildOptions(o)
    o.layout:Note(L.NOTE_BANK_BAGS, 20)
    o:Slider("columns", L.OPT_BAGS_COLUMNS, 4, 24, 1)
    o:Slider("buttonSize", L.OPT_BAGS_SIZE, 24, 48, 1)
end
