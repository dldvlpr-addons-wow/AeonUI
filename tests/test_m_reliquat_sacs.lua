-- tests/test_m_reliquat_sacs.lua : strate et poignée de la fenêtre des sacs, emplacements-sacs des onglets
-- de banque Forever, repère d'enchantement sur la fiche d'inspection.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Bags = NS.Modules:Get("bags")
local Gear = NS.Modules:Get("gear")

test("sacs : strate réglable, cadres Blizzard cachés une strate au-dessus", function()
    reset()
    local db = NS.db.modules.bags
    NS.Modules:SetEnabled("bags", true)
    OpenAllBags()
    Bags:Update()
    eq(Bags:GetWindow():GetFrameStrata(), "HIGH", "défaut")
    eq(ContainerFrame1:GetFrameStrata(), "DIALOG")
    db.windowStrata = "LOW"
    Bags:OnRefresh()
    eq(Bags:GetWindow():GetFrameStrata(), "LOW")
    eq(_G.MuscaUIBagsReagents:GetFrameStrata(), "LOW", "fenêtre des réactifs")
    eq(ContainerFrame1:GetFrameStrata(), "MEDIUM", "boutons Blizzard devant notre fond")
    db.windowStrata = "n'importe quoi"
    Bags:OnRefresh()
    eq(Bags:GetWindow():GetFrameStrata(), "HIGH", "valeur inconnue : défaut")
    CloseAllBags()
    NS.Modules:SetEnabled("bags", false)
end)

test("sacs : poignée de redimensionnement (verrou) qui règle les colonnes", function()
    reset()
    local db = NS.db.modules.bags
    NS.Modules:SetEnabled("bags", true)
    OpenAllBags()
    Bags:Update()
    local window = Bags:GetWindow()
    local handle = window.resizeHandle
    eq(handle:IsShown(), false, "verrouillée par défaut")
    db.lockSize = false
    Bags:OnRefresh()
    truthy(handle:IsShown(), "déverrouillée : poignée visible")
    -- Écart depuis le clic, pas depuis le bord gauche (qui bouge si la fenêtre est ancrée à droite).
    local start = db.columns
    Mock.cursorX = 500
    handle:GetScript("OnMouseDown")(handle)
    window.GetLeft = function() return -9999 end
    Mock.cursorX = 500 + 2 * 37   -- cellule : 34 + 3
    handle:GetScript("OnUpdate")(handle)
    eq(db.columns, start + 2, "colonnes suivent l'écart du curseur")
    Mock.cursorX = 0
    handle:GetScript("OnUpdate")(handle)
    eq(db.columns, 4, "plancher à 4")
    Mock.cursorX = 5000
    handle:GetScript("OnUpdate")(handle)
    eq(db.columns, 24, "plafond à 24")
    handle:GetScript("OnMouseUp")(handle)
    eq(handle:GetScript("OnUpdate"), nil, "suivi arrêté au relâchement")
    Mock.cursorX = nil
    CloseAllBags()
    NS.Modules:SetEnabled("bags", false)
end)

test("banque Forever : emplacements-sacs des onglets, prise au curseur", function()
    reset()
    local Bank = NS.Modules:Get("bank")
    local previousBank, previousType, previousIndex = _G.C_Bank, Enum.BankType, Enum.BagIndex
    local previousPickup, picked = C_Container.PickupContainerItem, nil
    Enum.BankType = { Character = 0, Account = 2 }
    Enum.BagIndex = setmetatable({ Characterbanktab = -2, Accountbanktab = -3 }, { __index = previousIndex })
    _G.C_Bank = {
        CanViewBank = function() return true end,
        FetchBankLockedReason = function() return nil end,
        FetchPurchasedBankTabData = function(bankType)
            if bankType == 0 then return { { ID = 6, name = "A" }, { ID = 7, name = "B" } } end
            return { { ID = 15, name = "C" } }
        end,
        FetchMaxNumBankTabs = function(bankType) return bankType == 0 and 4 or 3 end,
        FetchNumPurchasedBankTabs = function(bankType) return bankType == 0 and 2 or 1 end,
        CanPurchaseBankTab = function() return false end,
        CloseBankFrame = function() end,
        DoesBankTypeSupportAutoDeposit = function() return false end,
    }
    C_Container.PickupContainerItem = function(bag, slot) picked = { bag, slot } end
    local list = NS.GetBankBagSlots(0)
    eq(#list, 3, "onglets 2 à 4 (le premier ne porte pas de sac)")
    eq(list[1].slot, 2); eq(list[1].bag, -2)
    eq(list[1].purchased, true); eq(list[2].purchased, false)
    eq(NS.GetBankBagSlots(2)[1].bag, -3, "pseudo-sac du bataillon")
    eq(#NS.GetBankBagSlots(99), 0, "type inconnu")
    Mock.bags[6], Mock.bags[7], Mock.bags[15] = {}, {}, {}
    Mock.bags[-2] = { [2] = { itemID = 40, quality = 2 } }
    NS.Modules:SetEnabled("bank", true)
    Mock.FireEvent("BANKFRAME_OPENED")
    local window = Bank:GetWindow()
    local buttons = {}
    for _, child in ipairs({ window:GetChildren() }) do
        if child.slot then buttons[child.slot] = child end
    end
    truthy(buttons[2] and buttons[2]:IsShown(), "emplacement de l'onglet 2")
    truthy(buttons[4] and buttons[4]:IsShown(), "emplacement de l'onglet 4")
    eq(buttons[3].purchased, false, "onglet non acheté")
    buttons[2]:GetScript("OnClick")(buttons[2])
    eq(picked and picked[1], -2, "prise dans le pseudo-sac")
    eq(picked[2], 2)
    picked = nil
    buttons[3]:GetScript("OnClick")(buttons[3])
    eq(picked, nil, "onglet non acheté : rien")
    Mock.FireEvent("BANKFRAME_CLOSED")
    NS.Modules:SetEnabled("bank", false)
    Mock.bags[6], Mock.bags[7], Mock.bags[15], Mock.bags[-2] = nil, nil, nil, nil
    C_Container.PickupContainerItem = previousPickup
    _G.C_Bank, Enum.BankType, Enum.BagIndex = previousBank, previousType, previousIndex
end)

test("inspection : repère d'enchantement manquant comme sur la fiche", function()
    reset()
    Mock.equipped[1] = { link = "item:100:0:0", level = 60, quality = 4 }
    Mock.equipped[15] = { link = "item:100:0:0", level = 60, quality = 4 }
    Mock.equipped[5] = { link = "item:200:1891:0", level = 58, quality = 3 }
    InspectFrame.unit = "target"
    Mock.units.target = { guid = "Player-9", name = "Zed", isPlayer = true }
    InspectFrame:Show()
    local function Warning(slot)
        for _, region in ipairs({ _G["Inspect" .. slot .. "Slot"]:GetRegions() }) do
            if region.text == "!" then return region end
        end
    end
    NS.db.modules.gear.missingEnchant = true
    Gear:UpdateInspect()
    truthy(Warning("Back"):IsShown(), "cape inspectée sans enchantement")
    eq(Warning("Chest"):IsShown(), false, "plastron enchanté")
    NS.db.modules.gear.missingEnchant = false
    Gear:UpdateInspect()
    eq(Warning("Back"):IsShown(), false, "option coupée")
    InspectFrame:Hide()
    Mock.equipped[1], Mock.equipped[5], Mock.equipped[15] = nil, nil, nil
end)
