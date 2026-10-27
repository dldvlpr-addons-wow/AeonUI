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
    local reagents = _G.MuscaUIBagsReagents
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
    truthy(junk.muscaJunk:IsShown(), "camelote signalée")
    eq(helm.muscaJunk:IsShown(), false)
    eq(helm.muscaLevel.text, "45", "niveau sur l'équipement")
    eq(stack.muscaLevel:IsShown(), false, "pas de niveau hors équipement")
    eq(helm.muscaBorder.top.color[1], select(1, NS.QualityColor(3)), "bordure de qualité")
    ContainerFrame1:UpdateItemLayout()
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.Advance(0.1)
    eq(select(2, junk:GetPoint(1)), window, "remis dans la grille au changement de sac")
    local points = junk.points
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.Advance(0.1)
    eq(junk.points, points, "mise en page inchangée : case pas replacée")
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
    eq(junk.muscaJunk:IsShown(), false, "case vidée")
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
    truthy(helm.muscaUpgrade:IsShown(), "50 au-dessus du casque porté (45)")
    truthy(ring.muscaUpgrade:IsShown(), "second anneau vide : amélioration")
    eq(buttons[1][1].muscaUpgrade:IsShown(), false, "pas d'équipement")
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

test("banque : onglets personnage et bataillon par ID, « Tous », recherche, tri et dépôt", function()
    reset()
    local Bank = NS.Modules:Get("bank")
    local bankFrame = _G.BankFrame or CreateFrame("Frame", "BankFrame", UIParent)
    local previousBank, previousType, previousInteraction = _G.C_Bank, Enum.BankType, Enum.PlayerInteractionType
    local previousManager = _G.C_PlayerInteractionManager
    local closed, deposited, banker = 0, nil, false
    Enum.BankType = { Character = 0, Account = 2 }
    Enum.PlayerInteractionType = { AccountBanker = 68 }
    _G.C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function(kind) return banker and kind == 68 end }
    _G.C_Bank = {
        CanViewBank = function() return true end,
        FetchBankLockedReason = function() return nil end,
        -- Onglets non contigus : le sac vient de l'ID, pas de la position.
        FetchPurchasedBankTabData = function(bankType)
            if bankType == 0 then return { { ID = 6, name = "Métiers" }, { ID = 8, name = "" } } end
            return { { ID = 15, name = "Commun" } }
        end,
        CloseBankFrame = function() closed = closed + 1 end,
        DoesBankTypeSupportAutoDeposit = function() return true end,
        AutoDepositItemsIntoBank = function(bankType) deposited = bankType end,
        DoesBankTypeSupportMoneyTransfer = function(bankType) return bankType == 2 end,
        FetchDepositedMoney = function() return 12345 end,
        FetchNumPurchasedBankTabs = function(bankType) return bankType == 0 and 2 or 1 end,
        CanPurchaseBankTab = function(bankType) return bankType == 0 end,
    }
    local previousDialog = StaticPopupDialogs.CONFIRM_BUY_BANK_TAB
    local bought
    StaticPopupDialogs.CONFIRM_BUY_BANK_TAB = { OnAccept = function(_, data) bought = data.bankType end }
    Mock.bags[6], Mock.bags[8], Mock.bags[15] = { [1] = { itemID = 10, quality = 0 } }, { [2] = { itemID = 20, quality = 3 } }, {}
    Mock.items[10], Mock.items[20] = { sellPrice = 5 }, { sellPrice = 5 }
    NS.Modules:SetEnabled("bank", true)
    local tabs = Bank.Tabs()
    eq(#tabs, 4)
    eq(tabs[1].name, L.BANK_ALL); eq(table.concat(tabs[1].bags, ","), "6,8")
    eq(tabs[2].name, "Métiers"); eq(tabs[3].name, string.format(L.BANK_TAB, 2)); eq(tabs[3].bags[1], 8)
    eq(tabs[4].name, "Commun"); eq(tabs[4].bankType, 2)
    Mock.FireEvent("BANKFRAME_OPENED")
    local window, slots, tabButtons = Bank:GetWindow()
    truthy(window:IsShown(), "notre banque ouverte")
    truthy(bankFrame:GetParent() ~= UIParent, "banque Blizzard mise de côté")
    eq(#slots, 2 * Mock.bagSize, "« Tous » : les deux coffres empilés")
    eq(slots[1]:GetParent():GetID(), 6, "sac porté par le parent")
    eq(slots[Mock.bagSize + 2]:GetParent():GetID(), 8)
    eq(slots[Mock.bagSize + 2]:GetID(), 2)
    truthy(slots[1].muscaJunk:IsShown(), "camelote signalée comme dans les sacs")
    window.search:Type("item20")
    eq(slots[1]:GetAlpha(), 0.25, "recherche propre à la banque")
    eq(slots[Mock.bagSize + 2]:GetAlpha(), 1)
    window.search:Type("")
    eq(slots[1]:GetAlpha(), 1)
    truthy(window.purchase:IsShown(), "achat d'onglet proposé")
    Mock.acceptPopups = true
    window.purchase:GetScript("OnClick")(window.purchase)
    Mock.acceptPopups = nil
    eq(bought, 0, "confirmation Blizzard, onglet du personnage")
    tabButtons[4]:GetScript("OnClick")(tabButtons[4])
    eq(window.purchase:IsShown(), false, "bataillon plein : pas d'achat d'un autre type")
    eq(slots[1]:GetParent():GetID(), 15, "onglet de bataillon")
    truthy(window.footer:GetText():find(NS.FormatMoney(12345), 1, true), "or de bataillon au pied")
    window.deposit:GetScript("OnClick")(window.deposit)
    eq(deposited, 2, "dépôt du type affiché")
    window.sort:GetScript("OnClick")(window.sort)
    eq(Mock.sortedBank, 2, "tri du type affiché")
    eq(window.sort:IsEnabled(), false, "verrou pendant le rangement")
    Mock.Advance(0.6)
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.Advance(0.6)
    eq(window.sort:IsEnabled(), false, "réarmé par le dernier BAG_UPDATE_DELAYED")
    Mock.Advance(0.6)
    truthy(window.sort:IsEnabled(), "rendu quand les sacs se taisent")
    banker = true
    tabs = Bank.Tabs()
    eq(#tabs, 1, "banquier de bataillon : onglets de compte seuls"); eq(tabs[1].bankType, 2)
    banker = false
    window:Hide()
    eq(closed, 1, "fermer la nôtre ferme le guichet")
    Mock.FireEvent("BANKFRAME_CLOSED")
    NS.Modules:SetEnabled("bank", false)
    eq(bankFrame:GetParent(), UIParent, "banque Blizzard rendue")
    Mock.bags[6], Mock.bags[8], Mock.bags[15], Mock.items[10], Mock.items[20], Mock.sortedBank = nil, nil, nil, nil, nil, nil
    _G.C_Bank, Enum.BankType, Enum.PlayerInteractionType = previousBank, previousType, previousInteraction
    _G.C_PlayerInteractionManager = previousManager
    StaticPopupDialogs.CONFIRM_BUY_BANK_TAB = previousDialog
end)

test("sacs : liaison non faite (texte, recherche localisée) et section des sacs spéciaux", function()
    reset()
    Mock.items[30], Mock.items[31], Mock.items[32] = { bindType = 2 }, { bindType = 9 }, { bindType = 1 }
    Mock.bags[0][1], Mock.bags[0][2], Mock.bags[0][3] = { itemID = 30 }, { itemID = 31 }, { itemID = 32, isBound = true }
    local boe, boa = NS.GetBagItem(0, 1), NS.GetBagItem(0, 2)
    local bound = NS.GetBagItem(0, 3)
    eq(Bags.BindKind(boe), "boe"); eq(Bags.BindKind(boa), "boa"); eq(Bags.BindKind(bound), nil, "déjà lié")
    truthy(Bags.MatchesSearch(boe, "bo"), "mot-clé anglais")
    truthy(Bags.MatchesSearch(boe, L.BAGS_SEARCH_BOE:upper()), "mot-clé localisé, casse ignorée")
    eq(Bags.MatchesSearch(boa, "boe"), false)
    eq(Bags.MatchesSearch(bound, "bop"), false, "lié : plus de mot-clé")
    eq(Bags.MatchesSearch(boe, "b"), false, "une lettre : nom seulement")
    truthy(Bags.MatchesSearch(boe, "item30"), "nom")
    -- Texte sous l'icône : option activée par défaut.
    eq(Bags.defaults.bindText, true)
    -- Sac spécial : toutes ses cases dans « special », groupe libre gardé.
    local custom = { [30] = "Perso" }
    eq(Bags.Category(boa, 1, 2, {}, {}, false), "special")
    eq(Bags.Category(nil, 1, 3, {}, {}, false), "special", "case vide d'un sac spécial")
    eq(Bags.Category(boe, 1, 1, {}, custom, false), "custom:Perso")
    eq(Bags.Category(nil, 0, 3, {}, {}, true), "empty")
    NS.db.modules.bags.categoryShown.special = false
    eq(Bags.Category(nil, 1, 3, {}, {}, false), "empty", "section décochée")
    NS.db.modules.bags.categoryShown.special = true
    Mock.bagFamily[1] = 1
    eq(NS.IsGeneralBag(1), false); eq(NS.IsGeneralBag(0), true)
    Mock.bagFamily[1] = nil
    Mock.items[30], Mock.items[31], Mock.items[32] = nil, nil, nil
end)

test("sacs : « special » absent d'un ordre enregistré, inséré avant « other »", function()
    local order = table.concat(Bags.CategoryOrder("pinned, junk, other, empty"), ",")
    truthy(order:find("junk,special,other,empty", 1, true), order)
end)
