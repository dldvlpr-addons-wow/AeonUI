-- tests/test_bars_bags_extensions.lua : lot 6, paging de la barre 1, flèches de page, échelle des sacs,
-- trousseau, police du chat, enchantements des mains.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local AB = NS.Modules:Get("actionbars")
local Bags = NS.Modules:Get("bags")
local Gear = NS.Modules:Get("gear")

test("barre 1 : paging par forme coupé, véhicule et pages manuelles gardés", function()
    reset()
    local db = NS.db.modules.actionbars
    truthy(AB.PageDriver(db.bars):find("bonusbar:1", 1, true), "formes suivies par défaut")
    local driver = AB.PageDriver(db.bars, true)
    eq(driver:find("bonusbar", 1, true), nil, "plus de page de forme")
    truthy(driver:find("^%[overridebar%]%[vehicleui%]%[possessbar%] 12;"), "véhicule gardé")
    truthy(driver:find("[bar:2] 2;", 1, true), "pages manuelles gardées")
    db.formPaging = false
    NS.Modules:SetEnabled("actionbars", true)
    eq(Mock.attributeDrivers[AB:GetBar(1).buttons[1]].actionpage:find("bonusbar", 1, true), nil, "pilote posé sans formes")
    db.formPaging = true
    NS.Modules:Refresh("actionbars")
    truthy(Mock.attributeDrivers[AB:GetBar(1).buttons[1]].actionpage:find("bonusbar:1", 1, true), "réglage repris")
    NS.Modules:SetEnabled("actionbars", false)
end)

test("barre 1 : flèches de page sécurisées, numéro qui suit la page", function()
    reset()
    local db = NS.db.modules.actionbars
    NS.Modules:SetEnabled("actionbars", true)
    local bar = AB:GetBar(1)
    eq(bar.pageArrows, nil, "absentes par défaut")
    db.pageArrows = true
    NS.Modules:Refresh("actionbars")
    eq(bar.pageArrows[1]:GetAttribute("type"), "actionbar")
    eq(bar.pageArrows[1]:GetAttribute("musca-step"), 1)
    eq(bar.pageArrows[2]:GetAttribute("musca-step"), -1)
    -- Barres 2 (page 6) et 3 (page 5) allumées : le cycle saute 5 et 6 ; 3 et 4 libres.
    eq(bar.pageArrows[1]:GetAttribute("musca-pages"), "1,2,3,4")
    local function Click(arrow, current)
        local split = function(delimiter, text)
            local values = {}
            for value in text:gmatch("[^" .. delimiter .. "]+") do values[#values + 1] = value end
            return unpack(values)
        end
        Mock.RunSecure(arrow, arrow.wrapped.OnClick, { GetActionBarPage = function() return current end,
            select = select, tonumber = tonumber, strsplit = split })
        return arrow:GetAttribute("action")
    end
    eq(Click(bar.pageArrows[1], 1), 2, "suivante")
    eq(Click(bar.pageArrows[1], 4), 1, "boucle en haut")
    eq(Click(bar.pageArrows[1], 12), 1, "page de véhicule : retour à 1")
    eq(Click(bar.pageArrows[2], 3), 2, "précédente")
    eq(Click(bar.pageArrows[2], 1), 4, "boucle en bas, sans 5 ni 6")
    truthy(bar.pageArrows[1]:IsShown() and bar.pageNumber:IsShown(), "affichées")
    bar.buttons[1]:SetAttribute("actionpage", 4)
    eq(bar.pageNumber.text, "4", "numéro de page")
    Mock.mouseOver = bar.pageArrows[1]
    local hover = NS.Visibility.entries.actionbar1.opts.hoverExtra
    truthy(hover(), "flèche survolée : la barre en fondu reste visible")
    Mock.mouseOver = nil
    eq(hover(), false)
    db.pageArrows = false
    NS.Modules:Refresh("actionbars")
    eq(bar.pageArrows[1]:IsShown() or bar.pageNumber:IsShown(), false, "cachées")
    NS.Modules:SetEnabled("actionbars", false)
end)

test("sacs : échelle de la fenêtre, des réactifs et des cadres Blizzard", function()
    reset()
    local db = NS.db.modules.bags
    db.windowScale = 1.5
    NS.Modules:SetEnabled("bags", true)
    OpenAllBags()
    Bags:Update()
    eq(Bags:GetWindow():GetScale(), 1.5, "fenêtre")
    eq(_G.MuscaUIBagsReagents:GetScale(), 1.5, "fenêtre des réactifs")
    eq(ContainerFrame1:GetScale(), 1.5, "boutons Blizzard à la même échelle")
    -- Movers : le support n'est pas mis à l'échelle, la fenêtre s'y ancre à décalage 0.
    local holder = NS.Movers.registry.bagWindow.frame
    eq(holder:GetScale(), 1, "support à l'échelle d'UIParent")
    eq(holder:GetWidth(), Bags:GetWindow():GetWidth() * 1.5, "support de la taille mise à l'échelle")
    local _, relative, _, x, y = Bags:GetWindow():GetPoint(1)
    truthy(relative == holder and x == 0 and y == 0, "fenêtre ancrée au support")
    NS.Movers:Save("bagWindow", "BOTTOMRIGHT", "BOTTOMRIGHT", -200, 120)
    NS.Movers:Load("bagWindow")
    db.windowScale = 2
    Bags:OnRefresh()
    NS.Movers:Load("bagWindow")
    local point, _, relPoint, px, py = holder:GetPoint(1)
    truthy(point == "BOTTOMRIGHT" and relPoint == "BOTTOMRIGHT" and px == -200 and py == 120,
        "position Movers inchangée par l'échelle")
    eq(holder:GetWidth(), Bags:GetWindow():GetWidth() * 2, "support suit l'échelle")
    db.windowScale = 1.5
    db.windowScale = 1
    Bags:OnRefresh()
    eq(Bags:GetWindow():GetScale(), 1, "échelle reprise")
    CloseAllBags()
    NS.Modules:SetEnabled("bags", false)
end)

test("sacs : trousseau ajouté sur demande, en dernier, hors places libres", function()
    reset()
    local savedActionBar, savedEnum = _G.C_ActionBar, _G.Enum
    _G.C_ActionBar = { ShouldShowKeyring = function() return true end }
    _G.Enum = setmetatable({ BagIndex = { Keyring = -1 } }, { __index = savedEnum })
    local keyring = CreateFrame("Frame", "ContainerFrame9", UIParent)
    keyring:SetID(-1)
    local key = CreateFrame("Button", nil, keyring)
    key.bagID = -1
    key:SetID(1)
    function key:GetBagID() return self.bagID end
    function keyring:EnumerateValidItems() return ipairs({ key }) end
    function keyring:UpdateItemLayout() key:ClearAllPoints(); key:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0) end
    keyring:Show()
    local db = NS.db.modules.bags
    NS.Modules:SetEnabled("bags", true)
    OpenAllBags()
    Bags:Update()
    local window = Bags:GetWindow()
    truthy(select(2, key:GetPoint(1)) ~= window, "trousseau absent par défaut")
    db.keyring = true
    Bags:Update()
    eq(select(2, key:GetPoint(1)), window, "trousseau dans la fenêtre")
    eq(NS.IsGeneralBag(-1), false, "les clés ne comptent pas dans les places libres")
    eq(keyring:GetAlpha(), 0, "trousseau caché hors écran")
    eq(keyring:GetScale(), db.windowScale)
    db.keyring = false
    Bags:OnRefresh()
    eq(keyring:GetAlpha(), 1, "trousseau décoché ouvert : rendu à Blizzard")
    eq(keyring:GetScale(), 1)
    eq(keyring:GetFrameStrata(), "MEDIUM")
    truthy(select(2, key:GetPoint(1)) ~= window, "clé plus ancrée à notre fenêtre")
    CloseAllBags()
    NS.Modules:SetEnabled("bags", false)
    _G.ContainerFrame9, _G.C_ActionBar, _G.Enum = nil, savedActionBar, savedEnum
end)

test("chat : police propre au module, repli sur le thème", function()
    reset()
    local Chat = NS.Modules:Get("chat")
    NS.Modules:SetEnabled("chat", true)
    eq(ChatFrame1.font, NS.db.theme.font, "thème par défaut")
    NS.db.theme.moduleMedia.chat = { font = "Fonts\\MORPHEUS.TTF" }
    Chat:OnRefresh()
    eq(ChatFrame1.font, "Fonts\\MORPHEUS.TTF", "police du chat")
    NS.db.theme.moduleMedia.chat = nil
    NS.Modules:SetEnabled("chat", false)
end)

test("fiche : main gauche enchantable seulement pour bouclier et armes, pas la canne à pêche", function()
    reset()
    Mock.items = Mock.items or {}
    local saved = { Mock.items["item:300:0"], Mock.items["item:301:0"], Mock.items["item:302:0"], Mock.items["item:303:0"] }
    Mock.items["item:300:0"] = { equipLoc = "INVTYPE_SHIELD", classID = 4 }
    Mock.items["item:301:0"] = { equipLoc = "INVTYPE_HOLDABLE", classID = 4 }
    Mock.items["item:302:0"] = { equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 20 }
    Mock.items["item:303:0"] = { equipLoc = "INVTYPE_WEAPON", classID = 2 }
    truthy(Gear.IsEnchantable("SecondaryHand", "item:300:0"), "bouclier")
    eq(Gear.IsEnchantable("SecondaryHand", "item:301:0"), false, "objet de main gauche")
    eq(Gear.IsEnchantable("MainHand", "item:300:0"), false, "bouclier pas en main droite")
    truthy(Gear.IsEnchantable("MainHand", "item:303:0"), "arme")
    eq(Gear.IsEnchantable("MainHand", "item:302:0"), false, "canne à pêche")
    truthy(Gear.IsEnchantable("Chest", "item:1:0"), "torse")
    eq(Gear.IsEnchantable("Head", "item:1:0"), false, "casque : enchant de réputation")
    eq(Gear.IsEnchantable("Waist", "item:1:0"), false, "ceinture")
    for index, id in ipairs({ 300, 301, 302, 303 }) do Mock.items["item:" .. id .. ":0"] = saved[index] end
end)
