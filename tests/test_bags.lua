-- tests/test_bags.lua : étape 17, sacs tout-en-un.
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset
local Bags = NS.Modules:Get("bags")

test("sacs : fenêtre pilotée par les sacs Blizzard, cachés sous un parent masqué", function()
    reset()
    CloseAllBags()
    NS.Modules:SetEnabled("bags", true)
    local window = Bags:GetWindow()
    truthy(ContainerFrame1:GetParent() ~= UIParent, "sac Blizzard rattaché au parent caché")
    eq(window:IsShown(), false)
    OpenAllBags()
    truthy(window:IsShown(), "B ouvre la nôtre")
    CloseAllBags()
    eq(window:IsShown(), false, "B la ferme")
    OpenAllBags()
    window:Hide()
    eq(ContainerFrame1:IsShown(), false, "Échap : sacs Blizzard fermés aussi")
    OpenAllBags()
    NS.Modules:SetEnabled("bags", false)
    eq(ContainerFrame1:GetParent(), UIParent, "parent rendu")
    eq(window:IsShown(), false)
    truthy(ContainerFrame1:IsShown(), "sacs Blizzard toujours ouverts, de nouveau visibles")
    CloseAllBags()
    NS.Modules:SetEnabled("bags", true)
    ContainerFrame2:SetID(-2)   -- même cadre, réutilisé pour le trousseau
    OpenAllBags()
    eq(ContainerFrame2:GetParent(), UIParent, "trousseau : cadre Blizzard visible")
    truthy(ContainerFrame1:GetParent() ~= UIParent, "sac à dos : caché")
    CloseAllBags()
    ContainerFrame2:SetID(1)
    NS.Modules:SetEnabled("bags", false)
end)

test("sacs : grille, niveau d'objet, camelote, qualité, recherche, tri, libres", function()
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
    truthy(junk.junk:IsShown(), "camelote signalée")
    eq(helm.junk:IsShown(), false)
    eq(helm.level.text, "45", "niveau sur l'équipement")
    eq(stack.level:IsShown(), false, "pas de niveau hors équipement")
    eq(stack.count, 5, "quantité lue par Blizzard (division de pile)")
    eq(stack.fuiCount.text, 5)
    eq(helm.border.top.color[1], select(1, NS.QualityColor(3)), "bordure de qualité")
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
    eq(junk.junk:IsShown(), false, "case vidée")
    NS.db.modules.bags.junk = false
    NS.Modules:Refresh("bags")
    NS.Modules:SetEnabled("bags", false)
    NS.db.modules.bags.junk = true
    CloseAllBags()
end)
