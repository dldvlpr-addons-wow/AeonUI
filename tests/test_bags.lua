-- tests/test_bags.lua : étape 17, sacs tout-en-un.
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset
local Bags = NS.Modules:Get("bags")

test("sacs : fenêtre pilotée par les sacs Blizzard, ouverts mais invisibles hors écran", function()
    reset()
    CloseAllBags()
    NS.Modules:SetEnabled("bags", true)
    local window = Bags:GetWindow()
    eq(window:IsShown(), false)
    OpenAllBags()
    truthy(window:IsShown(), "B ouvre la nôtre")
    eq(ContainerFrame1:GetAlpha(), 0, "sac Blizzard invisible")
    eq(ContainerFrame1:GetFrameStrata(), "DIALOG", "ses boutons passent devant notre fenêtre")
    eq(ContainerFrame1:GetParent(), UIParent, "parent Blizzard gardé")
    CloseAllBags()
    eq(window:IsShown(), false, "B la ferme")
    OpenAllBags()
    window:Hide()
    eq(ContainerFrame1:IsShown(), false, "Échap : sacs Blizzard fermés aussi")
    OpenAllBags()
    NS.Modules:SetEnabled("bags", false)
    eq(ContainerFrame1:GetAlpha(), 1, "sac Blizzard de nouveau visible")
    eq(ContainerFrame1:GetFrameStrata(), "MEDIUM")
    eq(window:IsShown(), false)
    truthy(ContainerFrame1:IsShown(), "sacs Blizzard toujours ouverts")
    CloseAllBags()
    NS.Modules:SetEnabled("bags", true)
    ContainerFrame2:SetID(-2)   -- même cadre, réutilisé pour le trousseau
    OpenAllBags()
    eq(ContainerFrame2:GetAlpha(), 1, "trousseau : cadre Blizzard visible")
    eq(ContainerFrame1:GetAlpha(), 0, "sac à dos : caché")
    CloseAllBags()
    ContainerFrame2:SetID(1)
    NS.Modules:SetEnabled("bags", false)
end)

test("sacs : sac de réactifs détaché dans sa propre fenêtre", function()
    reset()
    NS.REAGENT_BAG = 5
    NS.db.modules.bags.detachReagents = true
    NS.Modules:SetEnabled("bags", true)
    OpenAllBags()
    local reagent = CreateFrame("Button", nil, ContainerFrame1)
    reagent.bagID = 5
    reagent:SetID(1)
    function reagent:GetBagID() return self.bagID end
    ContainerFrame1.Items[#ContainerFrame1.Items + 1] = reagent
    Bags:Update()
    local window = Bags:GetWindow()
    local reagents = _G.AeonUIBagsReagents
    truthy(reagents:IsShown(), "fenêtre des réactifs ouverte avec la nôtre")
    eq(select(2, reagent:GetPoint(1)), reagents, "case posée dans la fenêtre des réactifs")
    eq(select(2, ContainerFrame1.Items[1]:GetPoint(1)), window, "les autres restent dans la principale")
    truthy(NS.Movers.registry.bagReagents, "mover des réactifs")
    NS.db.modules.bags.detachReagents = false
    Bags:Update()
    eq(select(2, reagent:GetPoint(1)), window, "rattaché : dans la principale")
    eq(reagents:IsShown(), false)
    -- Cadre du sac de réactifs créé après l'activation : ses boutons passent quand même devant.
    NS.db.modules.bags.detachReagents = true
    local late = CreateFrame("Frame", "ContainerFrame3", UIParent)
    late:SetID(5)
    local lateButton = CreateFrame("Button", nil, late)
    lateButton.bagID = 5
    lateButton:SetID(2)
    function lateButton:GetBagID() return self.bagID end
    function late:EnumerateValidItems() return ipairs({ lateButton }) end
    window:Show()
    Bags:Update()
    eq(late:GetFrameStrata(), "DIALOG", "cadre tardif au-dessus de la fenêtre des réactifs")
    eq(select(2, lateButton:GetPoint(1)), reagents)
    NS.db.modules.bags.detachReagents = false
    window:Hide()
    NS.Modules:SetEnabled("bags", false)
    eq(late:GetFrameStrata(), "MEDIUM", "rendu à Blizzard")
    _G.ContainerFrame3 = nil
    NS.REAGENT_BAG = nil
end)

test("sacs : boutons Blizzard dans la grille (case écrite par Blizzard), niveau, camelote, recherche, tri", function()
    reset()
    Mock.items[10] = { sellPrice = 5 }
    Mock.items[20] = { sellPrice = 900, equipLoc = "INVTYPE_HEAD" }
    Mock.items[30] = { sellPrice = 0 }
    Mock.equipped[1] = { link = 20, level = 45, quality = 3 }
    Mock.bags[0][1] = { itemID = 10, quality = 0 }
    Mock.bags[0][2] = { itemID = 20, quality = 3 }
    Mock.bags[1][1] = { itemID = 30, quality = 1, stackCount = 5 }
    NS.Modules:SetEnabled("bags", true)
    OpenAllBags()
    local window, buttons = Bags:GetWindow()
    eq(#buttons[0], Mock.bagSize)
    eq(#buttons[NS.NUM_BAGS], Mock.bagSize)
    local junk, helm, stack = buttons[0][1], buttons[0][2], buttons[1][1]
    eq(junk:GetParent(), ContainerFrame1, "bouton Blizzard, parent Blizzard gardé")
    eq(junk:GetBagID(), 0); eq(junk:GetID(), 1)
    eq(junk.ignoreParentAlpha, true, "visible malgré le cadre Blizzard invisible")
    local _, relativeTo = junk:GetPoint(1)
    eq(relativeTo, window, "posé dans notre fenêtre")
    truthy(junk.aeonJunk:IsShown(), "camelote signalée")
    eq(helm.aeonJunk:IsShown(), false)
    eq(helm.aeonLevel.text, "45", "niveau sur l'équipement")
    eq(stack.aeonLevel:IsShown(), false, "pas de niveau hors équipement")
    eq(helm.aeonBorder.top.color[1], select(1, NS.QualityColor(3)), "bordure de qualité")
    ContainerFrame1:UpdateItemLayout()
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.Advance(0.1)
    eq(select(2, junk:GetPoint(1)), window, "remis dans la grille au changement de sac")
    local slots = (NS.NUM_BAGS + 1) * Mock.bagSize
    eq(window.footer.text, string.format(L.BAGS_FREE, slots - 3, slots))
    window.search:SetText("item2")
    window.search:GetScript("OnTextChanged")(window.search)
    eq(helm.alpha, 1); eq(junk.alpha, 0.25, "recherche : autres atténués")
    window.search:SetText("")
    window.search:GetScript("OnTextChanged")(window.search)
    eq(junk.alpha, 1)
    window.sort:GetScript("OnClick")(window.sort)
    eq(Mock.sorted, 1, "tri du client")
    Mock.bags[0][1] = nil
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.FireEvent("GET_ITEM_INFO_RECEIVED")
    Mock.Advance(0.1)
    eq(junk.aeonJunk:IsShown(), false, "case vidée")
    NS.db.modules.bags.junk = false
    NS.Modules:Refresh("bags")
    NS.Modules:SetEnabled("bags", false)
    eq(junk.ignoreParentAlpha, false, "bouton rendu à Blizzard")
    eq(select(2, junk:GetPoint(1)), ContainerFrame1)
    NS.db.modules.bags.junk = true
    CloseAllBags()
end)

test("sacs : épinglés puis récents en tête, flèche d'amélioration, fusion des piles", function()
    reset()
    Mock.items[40] = { sellPrice = 1, equipLoc = "INVTYPE_HEAD", level = 50 }
    Mock.items[41] = { sellPrice = 1, equipLoc = "INVTYPE_FINGER", level = 20 }
    Mock.items[50] = { sellPrice = 1, maxStack = 20 }
    Mock.equipped[1] = { link = 99, level = 45, quality = 3 }
    Mock.equipped[11] = { link = 98, level = 30, quality = 3 }
    Mock.bags[0][1] = { itemID = 40, quality = 3 }
    Mock.bags[0][2] = { itemID = 41, quality = 2 }
    Mock.bags[1][1] = { itemID = 50, quality = 1, stackCount = 15 }
    Mock.bags[1][2] = { itemID = 50, quality = 1, stackCount = 8 }
    Mock.bags[2][1] = { itemID = 50, quality = 1, stackCount = 20 }
    NS.Modules:SetEnabled("bags", true)
    OpenAllBags()
    local _, buttons = Bags:GetWindow()
    local helm, ring = buttons[0][1], buttons[0][2]
    truthy(helm.aeonUpgrade:IsShown(), "50 au-dessus du casque porté (45)")
    truthy(ring.aeonUpgrade:IsShown(), "second anneau vide : amélioration")
    eq(buttons[1][1].aeonUpgrade:IsShown(), false, "pas d'équipement")
    local firstX, firstY = select(4, helm:GetPoint(1))
    NS.db.modules.bags.pinned = "50"
    Mock.newItems["0:2"] = true
    Bags:Update()
    eq(select(4, buttons[1][1]:GetPoint(1)), firstX, "épinglé en tête")
    eq(select(5, buttons[1][1]:GetPoint(1)), firstY)
    eq(select(4, buttons[2][1]:GetPoint(1)) > select(4, buttons[1][2]:GetPoint(1)), true, "ordre des sacs gardé entre épinglés")
    eq(select(4, ring:GetPoint(1)) > select(4, buttons[2][1]:GetPoint(1)), true, "récent après les épinglés")
    eq(select(4, ring:GetPoint(1)) < select(4, helm:GetPoint(1)), true, "récent avant le reste")
    Bags:GetWindow().stack:GetScript("OnClick")()
    eq(Mock.bags[1][1].stackCount, 20, "pile 15 complétée")
    eq(Mock.bags[1][2].stackCount, 3, "reste dans sa case")
    eq(Mock.cursorItem, nil, "curseur vidé")
    truthy(Bags.merging, "fusion en cours")
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    eq(Bags.merging, false, "plus rien à fusionner : une seule pile partielle")
    NS.db.modules.bags.pinned = ""
    NS.Modules:SetEnabled("bags", false)
    CloseAllBags()
end)

test("sacs : sections par catégorie, ordre, groupe libre, renommage, catégorie décochée dans Divers", function()
    reset()
    local db = NS.db.modules.bags
    Mock.items[60] = { sellPrice = 1, classID = 0 }                             -- consommable
    Mock.items[61] = { sellPrice = 1, classID = 4, equipLoc = "INVTYPE_HEAD" }   -- armure
    Mock.items[62] = { sellPrice = 1, classID = 12 }                            -- quête
    Mock.items[63] = { sellPrice = 1, classID = 0 }                             -- groupe libre
    Mock.bags[0][1] = { itemID = 60, quality = 1 }
    Mock.bags[0][2] = { itemID = 61, quality = 2 }
    Mock.bags[0][3] = { itemID = 62, quality = 1 }
    Mock.bags[0][4] = { itemID = 63, quality = 1 }
    db.layout = "categories"
    db.categoryOrder = "custom, quest, equipment"
    db.customCategories = "Potions = 63"
    db.categoryNames.quest = "Missions"
    NS.Modules:SetEnabled("bags", true)
    OpenAllBags()
    local window, buttons = Bags:GetWindow()
    local labels = {}
    for _, header in ipairs(window.headers) do if header:IsShown() then labels[#labels + 1] = header.text end end
    eq(table.concat(labels, ","), "Potions,Missions," .. L.BAGS_CATEGORY_EQUIPMENT .. "," .. L.BAGS_CATEGORY_CONSUMABLE
        .. "," .. L.BAGS_CATEGORY_EMPTY, "ordre choisi, groupe libre, renommage, clés oubliées ensuite")
    local potionY, questY = select(5, buttons[0][4]:GetPoint(1)), select(5, buttons[0][3]:GetPoint(1))
    truthy(potionY > questY, "groupe libre au-dessus de la quête")
    db.categoryShown.equipment = false
    Bags:Update()
    labels = {}
    for _, header in ipairs(window.headers) do if header:IsShown() then labels[#labels + 1] = header.text end end
    truthy(table.concat(labels, ","):find(L.BAGS_CATEGORY_OTHER, 1, true), "équipement décoché : dans Divers")
    eq(table.concat(labels, ","):find(L.BAGS_CATEGORY_EQUIPMENT, 1, true), nil)
    db.layout = "grid"
    Bags:Update()
    local shown = 0
    for _, header in ipairs(window.headers) do if header:IsShown() then shown = shown + 1 end end
    eq(shown, 0, "grille : pas de titres")
    db.categoryShown.equipment, db.categoryOrder, db.customCategories, db.categoryNames.quest =
        true, Bags.defaults.categoryOrder, "", nil
    NS.Modules:SetEnabled("bags", false)
    CloseAllBags()
end)

test("banque : fenêtre au thème à l'ouverture du guichet, onglets retail, cases décorées, Blizzard rendu", function()
    reset()
    local Bank = NS.Modules:Get("bank")
    local bankFrame = _G.BankFrame or CreateFrame("Frame", "BankFrame", UIParent)
    local previousIndex, previousBank, previousType = Enum.BagIndex, _G.C_Bank, Enum.BankType
    Enum.BagIndex = { CharacterBankTab_1 = 6, CharacterBankTab_2 = 7 }
    local closed = 0
    _G.C_Bank = {
        FetchPurchasedBankTabData = function() return { { name = "Métiers" }, { name = "Divers" } } end,
        CloseBankFrame = function() closed = closed + 1 end,
    }
    Enum.BankType = Enum.BankType or { Character = 0 }
    Mock.bags[6], Mock.bags[7] = { [1] = { itemID = 10, quality = 0 } }, { [2] = { itemID = 20, quality = 3 } }
    Mock.items[10] = { sellPrice = 5 }
    NS.Modules:SetEnabled("bank", true)
    local tabs = Bank.Tabs()
    eq(#tabs, 2); eq(tabs[1].name, "Métiers"); eq(tabs[2].bag, 7)
    Mock.FireEvent("BANKFRAME_OPENED")
    local window, slots, tabButtons = Bank:GetWindow()
    truthy(window:IsShown(), "notre banque ouverte")
    truthy(bankFrame:GetParent() ~= UIParent, "banque Blizzard mise de côté")
    eq(#slots, Mock.bagSize)
    eq(slots[1]:GetParent():GetID(), 6, "sac porté par le parent")
    eq(slots[1]:GetID(), 1)
    truthy(slots[1].aeonJunk:IsShown(), "camelote signalée comme dans les sacs")
    tabButtons[2]:GetScript("OnClick")(tabButtons[2])
    eq(slots[2]:GetParent():GetID(), 7, "second onglet")
    eq(slots[1].aeonJunk:IsShown(), false)
    window:Hide()
    eq(closed, 1, "fermer la nôtre ferme le guichet")
    Mock.FireEvent("BANKFRAME_CLOSED")
    NS.Modules:SetEnabled("bank", false)
    eq(bankFrame:GetParent(), UIParent, "banque Blizzard rendue")
    Mock.bags[6], Mock.bags[7] = nil, nil
    Enum.BagIndex, _G.C_Bank, Enum.BankType = previousIndex, previousBank, previousType
end)
