-- tests/test_topbar.lua : barre du haut, menu Voyage, minimap.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local TopBar = NS.Modules:Get("topbar")

test("barre : textes, bouton foyer sécurisé", function()
    reset()
    local bar, elements, hearth = TopBar:GetFrame()
    truthy(bar:IsShown(), "barre visible")
    eq(hearth:GetAttribute("type"), "item")
    eq(hearth:GetAttribute("item"), "item:6948")
    truthy(elements.friends.label:GetText():find("2", 1, true), "2 amis Battle.net")
    Mock.money = 123456
    Mock.FireEvent("PLAYER_MONEY")
    truthy(elements.gold.label:GetText():find("12|cffffd700g", 1, true), "or")
    truthy(hearth.label:GetText():find("Orgrimmar", 1, true), "destination du foyer")
end)

test("barre : un élément masqué disparaît et revient", function()
    reset()
    local _, elements = TopBar:GetFrame()
    NS.db.modules.topbar.show.perf = false
    NS.Modules:Refresh("topbar")
    eq(elements.perf:IsShown(), false)
    NS.db.modules.topbar.show.perf = true
    NS.Modules:Refresh("topbar")
    eq(elements.perf:IsShown(), true)
end)

test("horloge 12 h / 24 h et indicateur de repos", function()
    eq(TopBar.FormatClock(0, 5, true), "00:05")
    eq(TopBar.FormatClock(0, 5, false), "12:05 AM")
    eq(TopBar.FormatClock(13, 37, false), "1:37 PM")
    reset()
    Mock.resting = true
    Mock.FireEvent("PLAYER_UPDATE_RESTING")
    local _, elements = TopBar:GetFrame()
    truthy(elements.clock.label:GetText():find("zzz", 1, true), "zzz au repos")
end)

test("couleur des mesures (FPS, latence)", function()
    eq(TopBar.Grade(60, 50, 30, true), "|cffffffff")
    eq(TopBar.Grade(40, 50, 30, true), "|cffffc040")
    eq(TopBar.Grade(20, 50, 30, true), "|cffff4040")
    eq(TopBar.Grade(250, 100, 200, false), "|cffff4040")
end)

test("mémoire : addons triés, les plus gourmands d'abord", function()
    local list = TopBar.ScanMemory(2)
    eq(#list, 2)
    eq(list[1].name, "Gros")
    eq(list[2].name, "AeonUI")
end)

test("menu Voyage : sorts connus seulement, boutons sécurisés, fermé en combat", function()
    reset()
    local _, elements, _, menu = TopBar:GetFrame()
    Mock.FireEvent("SPELLS_CHANGED")
    eq(elements.travel:IsShown(), false, "aucun sort de voyage : élément masqué")
    Mock.knownSpells[3561] = true
    Mock.spells[3561] = "Teleport: Stormwind"
    Mock.FireEvent("SPELLS_CHANGED")
    eq(elements.travel:IsShown(), true, "élément affiché")
    local button = _G.AeonUITravelButton1
    eq(button:GetAttribute("type"), "spell")
    eq(button:GetAttribute("spell"), 3561)
    eq(Mock.stateDrivers[menu].visibility, "[combat] hide", "state driver de combat")
    elements.travel.scripts.OnClick()
    eq(menu:IsShown(), true, "ouvert au clic")
    elements.travel.scripts.OnClick()
    eq(menu:IsShown(), false, "refermé")
    Mock.SetCombat(true)
    elements.travel.scripts.OnClick()
    eq(menu:IsShown(), false, "jamais ouvert en combat")
    Mock.SetCombat(false)
    Mock.knownSpells[3561] = nil
    Mock.FireEvent("SPELLS_CHANGED")
end)

test("masquer en combat : state driver sur la barre, retiré sinon", function()
    reset()
    local bar = TopBar:GetFrame()
    NS.db.modules.topbar.hideInCombat = true
    NS.Modules:Refresh("topbar")
    eq(Mock.stateDrivers[bar].visibility, "[combat] hide; show")
    NS.db.modules.topbar.hideInCombat = false
    NS.Modules:Refresh("topbar")
    eq(Mock.stateDrivers[bar].visibility, nil)
end)

test("perf en combat : reste visible par défaut, masquée sur option", function()
    reset()
    local bar, elements = TopBar:GetFrame()
    local db = NS.db.modules.topbar
    eq(elements.perf:GetParent(), UIParent, "pas fille de la barre")
    db.hideInCombat = true
    NS.Modules:Refresh("topbar")
    eq(Mock.stateDrivers[elements.perf] and Mock.stateDrivers[elements.perf].visibility, nil, "perf sans driver")
    db.perfInCombat = false
    NS.Modules:Refresh("topbar")
    eq(Mock.stateDrivers[elements.perf].visibility, "[combat] hide; show")
    db.hideInCombat, db.perfInCombat = false, true
    NS.Modules:Refresh("topbar")
    eq(Mock.stateDrivers[elements.perf].visibility, nil)
    NS.Modules:SetEnabled("topbar", false)
    eq(elements.perf:IsShown(), false, "masquée avec le module")
    NS.Modules:SetEnabled("topbar", true)
    eq(elements.perf:IsShown(), true)
end)

test("position libre : largeur ajustée, ancrage sauvé, réinitialisation", function()
    reset()
    local bar = TopBar:GetFrame()
    local db = NS.db.modules.topbar
    db.position = "FREE"
    UIParent:SetScale(768 / 1080)   -- mult = 1 : positions entières
    NS.Pixel:Update()
    NS.Modules:Refresh("topbar")
    local point, _, _, _, y = bar:GetPoint()
    eq(point, "TOP")
    eq(y, -20, "ancrage par défaut")
    truthy(bar:GetWidth() > 0, "largeur ajustée")
    eq(bar:GetNumPoints(), 1, "un seul ancrage")
    NS.Movers:Save("topbar", "CENTER", "CENTER", 10, 30)
    eq(NS.db.anchors.topbar.y, 30, "position sauvée")
    NS.Modules:Refresh("topbar")
    local _, _, _, x = bar:GetPoint()
    eq(x, 10, "position relue")
    NS.Movers:Reset("topbar")
    eq(NS.db.anchors.topbar, nil)
    db.position = "TOP"
    NS.Modules:Refresh("topbar")
    point = bar:GetPoint()
    eq(point, "TOPLEFT", "retour pleine largeur")
    eq(bar:GetNumPoints(), 2, "deux ancrages")
end)

test("minimap : jamais déplacée quand Edit Mode gère le cadre", function()
    reset()
    eq(select(5, MinimapCluster:GetPoint(1)), 0, "Edit Mode présent : intouchée")
end)

test("minimap : descend sous la barre, suit Blizzard, revient au disable", function()
    -- Client sans Edit Mode : rendu quoi qu'il arrive, les tests suivants en dépendent.
    local editMode = C_EditMode
    C_EditMode = nil
    local ok, err = pcall(function()
    reset()
    NS.Modules:Refresh("topbar")
    local function y() return select(5, MinimapCluster:GetPoint(1)) end
    eq(y(), -20, "décalée")
    NS.db.modules.topbar.position = "BOTTOM"
    NS.Modules:Refresh("topbar")
    eq(y(), 0, "barre en bas")
    NS.db.modules.topbar.position = "TOP"
    NS.Modules:Refresh("topbar")
    MinimapCluster:ClearAllPoints()
    MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -5)
    eq(y(), -25, "nouvelle base + décalage")
    NS.Modules:SetEnabled("topbar", false)
    eq(y(), -5, "rendue")
    NS.Modules:SetEnabled("topbar", true)
    MinimapCluster:ClearAllPoints()
    MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    end)
    C_EditMode = editMode
    if not ok then error(err, 0) end
end)

test("formatage : or et classe localisée", function()
    eq(NS.FormatMoney(5), "5|cffeda55fc|r")
    eq(NS.FormatMoney(10203), "1|cffffd700g|r 2|cffc7c7cfs|r 3|cffeda55fc|r")
    eq(NS.ClassTokenFromLocalized("Guerrière"), "WARRIOR")
    eq(NS.ClassTokenFromLocalized("Inconnu"), nil)
end)
