-- AeonUI_Bags/Bank.lua
-- Banque AeonUI : une fenêtre au thème à la place de la banque Blizzard, un onglet par coffre
-- acheté (moteur retail : CharacterBankTab_1..6), sinon la banque classique et ses sacs. Cases
-- décorées comme celles des sacs (niveau, camelote, bordure, recherche des sacs).
--
-- Cases créées par l'addon (ContainerFrameItemButtonTemplate, sac porté par le parent) : pas de
-- combat au guichet, le marquage des SetID ne gêne pas. La banque Blizzard est reparentée sur un
-- cadre caché (jamais Hide ni SetScript, qui couperaient ses événements), rendue au disable.
local NS = AeonUI
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
local active = false
local open = false          -- guichet ouvert (BANKFRAME_OPENED .. BANKFRAME_CLOSED)
local window, hiddenParent, originalParent
local tabButtons, slots, tabFrames = {}, {}, {}
local selected = 1

local function S(n) return NS.Pixel:Scale(n) end

--- Coffres de la banque : { { bag, name } } (onglets retail achetés, sinon banque classique).
function Bank.Tabs()
    local tabs = {}
    local index = _G.Enum and Enum.BagIndex
    local names = {}
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
        for i, data in ipairs(C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character) or {}) do names[i] = data.name end
    end
    for i = 1, 6 do
        local bag = index and index["CharacterBankTab_" .. i]
        if bag and NS.GetBagSlots(bag) > 0 then
            tabs[#tabs + 1] = { bag = bag, name = names[i] or string.format(L.BANK_TAB, i) }
        end
    end
    if #tabs > 0 then return tabs end
    local bank = index and index.Bank or _G.BANK_CONTAINER or -1
    tabs[1] = { bag = bank, name = L.BANK_TITLE }
    for i = 1, _G.NUM_BANKBAGSLOTS or 7 do
        local bag = index and index["BankBag_" .. i] or (NS.NUM_BAGS + i)
        if NS.GetBagSlots(bag) > 0 then tabs[#tabs + 1] = { bag = bag, name = string.format(L.BANK_BAG, i) } end
    end
    return tabs
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
    button = CreateFrame("ItemButton", "AeonUIBankSlot" .. index, window, "ContainerFrameItemButtonTemplate")
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
    selected = math.min(selected, #tabs)
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
        button:SetSize(math.max(S(60), (button.label:GetStringWidth() or 0) + S(12)), S(18))
        button:ClearAllPoints()
        if index == 1 then button:SetPoint("TOPLEFT", window, "TOPLEFT", S(8), -S(6))
        else button:SetPoint("LEFT", tabButtons[index - 1], "RIGHT", S(4), 0) end
        local accent = index == selected and NS.db.theme.accent or NS.db.theme.border
        for _, edge in pairs(button.edges or {}) do NS.SetSolidColor(edge, accent.r, accent.g, accent.b, 1) end
        button.label:SetTextColor(index == selected and 1 or 0.65, index == selected and 1 or 0.65, index == selected and 1 or 0.65)
        button:Show()
    end
    for index = #tabs + 1, #tabButtons do tabButtons[index]:Hide() end

    local tab = tabs[selected]
    local count = tab and NS.GetBagSlots(tab.bag) or 0
    local size, columns = S(db.buttonSize), math.max(4, math.min(24, db.columns))
    local parent = tab and TabFrame(tab.bag)
    for slot = 1, count do
        local button = Slot(slot)
        button:SetParent(parent)
        button:SetID(slot)
        button:SetSize(size, size)
        button:ClearAllPoints()
        local row, column = math.floor((slot - 1) / columns), (slot - 1) % columns
        button:SetPoint("TOPLEFT", window, "TOPLEFT", S(8) + column * (size + S(SPACING)), -S(30) - row * (size + S(SPACING)))
        Paint(button, NS.GetBagItem(tab.bag, slot))
        NS.Modules:Get("bags").UpdateButton(button, tab.bag, slot)
        button:Show()
    end
    for slot = count + 1, #slots do slots[slot]:Hide() end
    local rows = math.max(1, math.ceil(count / columns))
    window:SetSize(S(16) + columns * (size + S(SPACING)) - S(SPACING), S(30) + rows * (size + S(SPACING)) + S(26))
    window.footer:SetText(tab and string.format(L.BAGS_FREE, NS.GetBagFreeSlots(tab.bag), count) or "")
end

local function Build()
    window = CreateFrame("Frame", "AeonUIBank", UIParent)
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    Media:CreateBackdrop(window)
    window:Hide()
    tinsert(UISpecialFrames, "AeonUIBank")
    window.close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    window.close:SetSize(S(20), S(20))
    window.close:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
    -- Fermer la nôtre (Échap, croix) ferme le guichet.
    window:SetScript("OnHide", function()
        if not open then return end
        if C_Bank and C_Bank.CloseBankFrame then C_Bank.CloseBankFrame() elseif _G.CloseBankFrame then CloseBankFrame() end
    end)
    window.footer = Media:CreateText(window, "OVERLAY")
    window.footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", S(8), S(6))
    local deposit = C_Bank and C_Bank.AutoDepositItemsIntoBank and Enum.BankType
    if deposit then
        window.deposit = CreateFrame("Button", nil, window)
        window.deposit:SetSize(S(110), S(18))
        window.deposit:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -S(8), S(4))
        Media:CreateBackdrop(window.deposit)
        window.deposit.label = Media:CreateText(window.deposit, "OVERLAY")
        window.deposit.label:SetPoint("CENTER")
        window.deposit.label:SetText(L.BANK_DEPOSIT_REAGENTS)
        window.deposit:SetScript("OnClick", function() C_Bank.AutoDepositItemsIntoBank(Enum.BankType.Character) end)
    end
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
    if event == "BANKFRAME_OPENED" then
        open = true
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
                             "ITEM_LOCK_CHANGED", "BANK_TABS_CHANGED" }) do
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
