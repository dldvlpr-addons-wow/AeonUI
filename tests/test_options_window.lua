-- tests/test_options_window.lua : fenêtre d'options, mise en page des widgets (colonnes, boutons
-- côte à côte, dépendances, onglets), liste déroulante, saisie des curseurs, confirmations,
-- « Copier depuis », recherche, clic droit et filtre du mode déplacement.
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset
local Options, Window = NS.Options, NS.OptionsWindow

local function noop() end

--- Widget d'une page par son libellé (dans l'onglet `tab` si donné).
local function Find(layout, text, tab)
    for _, entry in ipairs(layout.labels) do
        if entry.text == text and (tab == nil or entry.tab == tab) then return entry.frame, entry end
    end
end

local function MenuRow(value)
    for _, row in ipairs(NS.Widgets.GetMenu().rows) do
        if row:IsShown() and row.value == value then return row end
    end
end

test("widgets : deux cases par ligne, la case dont dépend un réglage repasse seule, réglage grisé", function()
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400)
    local state = { a = true, b = false }
    local a = layout:Check("A", function() return state.a end, function(v) state.a = v end)
    local b = layout:Check("B", function() return state.b end, function(v) state.b = v end)
    eq(a.layoutY, b.layoutY, "même ligne")
    local child = layout:Slider("Enfant", 0, 10, 1, function() return 1 end, noop, 16)
    truthy(b.layoutY < a.layoutY, "B, parente de l'enfant, passe sous A")
    layout:Refresh()
    eq(child:IsEnabled(), false, "B décochée : enfant grisé")
    b:SetChecked(true)
    b:Click()
    eq(state.b, true)
    eq(child:IsEnabled(), true, "B cochée : enfant rendu")
end)

test("widgets : boutons côte à côte, à la ligne quand la largeur manque", function()
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400)
    local one, two, three = layout:Button("Un", noop), layout:Button("Deux", noop), layout:Button("Trois", noop)
    eq(one.layoutY, two.layoutY, "côte à côte")
    truthy(three.layoutY < one.layoutY, "troisième à la ligne")
end)

test("widgets : liste déroulante, choix au clic, menu refermé", function()
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400)
    local value = "b"
    local dropdown = layout:Dropdown("Choix", { { name = "A", value = "a" }, { name = "B", value = "b" } },
        function() return value end, function(v) value = v end)
    eq(dropdown:GetText(), "Choix : B")
    dropdown:Click()
    local menu = NS.Widgets.GetMenu()
    eq(menu:IsShown(), true, "menu ouvert")
    MenuRow("a"):Click()
    eq(value, "a")
    eq(dropdown:GetText(), "Choix : A")
    eq(menu:IsShown(), false, "menu fermé")
end)

test("widgets : valeur de curseur tapée, bornée ; saisie invalide ignorée", function()
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400)
    local value = 5
    local slider = layout:Slider("Taille", 0, 10, 1, function() return value end, function(v) value = v end)
    layout:Refresh()
    local box = slider.valueBox
    eq(box:GetText(), "5")
    box:SetText("42")
    box:GetScript("OnEnterPressed")(box)
    eq(value, 10, "borné au maximum")
    box:SetText("abc")
    box:GetScript("OnEnterPressed")(box)
    eq(value, 10, "inchangé")
    eq(box:GetText(), "10", "case repeinte")
end)

test("widgets : onglets, un seul visible, changement au clic", function()
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400)
    layout:Check("Commun", function() return true end, noop)
    layout:Tab("Un")
    local one = layout:Check("Dans un", function() return true end, noop)
    layout:Tab("Deux")
    local two = layout:Check("Dans deux", function() return true end, noop)
    layout:Finish()
    eq(one:IsVisible(), true)
    eq(two:IsVisible(), false)
    layout.tabs[2].button:Click()
    eq(one:IsVisible(), false)
    eq(two:IsVisible(), true)
end)

test("options : page d'un module coupé grisée, rendue une fois activé", function()
    reset()
    local layout = Options:GetLayout("cursor")
    local ring = Find(layout, L.OPT_CURSOR_RING_SHOW)
    NS.Modules:SetEnabled("cursor", false)
    Options:Refresh()
    eq(ring:IsEnabled(), false, "module coupé")
    NS.Modules:SetEnabled("cursor", true)
    eq(ring:IsEnabled(), true, "module actif")
    NS.Modules:SetEnabled("cursor", false)
end)

test("options : un onglet par unité, « Copier depuis » recopie sans toucher à enabled", function()
    reset()
    local units = NS.Modules:Get("unitframes").SETTINGS_UNITS
    local layout = Options:GetLayout("unitframes")
    eq(#layout.tabs, #units, "un onglet par unité")
    local targetTab
    for i, unit in ipairs(units) do if unit == "target" then targetTab = i end end
    local db = NS.db.modules.unitframes.units
    db.player.width, db.target.enabled = 222, false
    local copy = Find(layout, L.OPT_COPY_FROM, targetTab)
    copy:Click()
    eq(MenuRow("units.target"), nil, "l'unité elle-même n'est pas proposée")
    MenuRow("units.player"):Click()
    eq(db.target.width, 222, "largeur copiée")
    eq(db.target.enabled, false, "enabled gardé")
    NS.Options.ResetModule("unitframes")
end)

test("options : réinitialiser un module sur place, activation gardée", function()
    reset()
    local module = NS.Modules:Get("automation")
    local db = NS.db.modules.automation
    db.sellJunk = false
    Options.ResetModule("automation")
    eq(db.sellJunk, true, "défaut rendu")
    eq(NS.db.modules.automation, db, "même table : le module garde sa référence")
    eq(db.enabled, module.enabled, "activation inchangée")
end)

test("options : profil remis par défaut seulement après confirmation", function()
    reset()
    local layout = Options:GetLayout("profiles")
    local button = Find(layout, L.OPT_PROFILE_RESET)
    NS.db.modules.automation.sellJunk = false
    button:Click()
    truthy(Mock.popups.AEONUI_PROFILE_RESET, "confirmation demandée")
    eq(NS.db.modules.automation.sellJunk, false, "rien avant confirmation")
    Mock.acceptPopups = true
    button:Click()
    Mock.acceptPopups = false
    eq(NS.db.modules.automation.sellJunk, true, "profil remis par défaut")
end)

test("options : profil de rôle pour ce personnage, copie de l'actuel puis rôle, jamais écrasé", function()
    reset()
    local layout = Options:GetLayout("profiles")
    local button = Find(layout, L.OPT_PROFILE_ROLE_CHARACTER)
    local origin = NS.Database:ActiveProfileName()
    NS.db.modules.automation.sellJunk = false          -- réglage propre au profil d'origine
    button:Click()                                     -- rôle choisi par défaut : soigneur
    local name = NS.Database.CharacterKey() .. " - " .. L.INSTALL_ROLE_HEAL
    eq(NS.Database:ActiveProfileName(), name, "profil du personnage actif")
    eq(NS.db.modules.automation.sellJunk, false, "copie du profil actuel")
    eq(NS.db.modules.groupframes.horizontal, true, "rôle appliqué (groupe en ligne)")
    NS.db.modules.groupframes.width = 99
    NS:SwitchProfile(origin)
    button:Click()
    eq(NS.Database:ActiveProfileName(), name, "second clic : bascule")
    eq(NS.db.modules.groupframes.width, 99, "réglage du joueur gardé")
    NS:SwitchProfile(origin)
    NS.global.profiles[name] = nil
    NS.db.modules.automation.sellJunk = true
end)

test("options : couper un module aux cadres Blizzard propose /reload", function()
    reset()
    NS.Modules:SetEnabled("minimap", true)
    local layout = Options:GetLayout("minimap")
    local enable = Find(layout, string.format(L.OPT_ENABLE, NS.Modules:Get("minimap").title))
    enable:SetChecked(false)
    enable:Click()
    eq(NS.db.modules.minimap.enabled, false)
    truthy(Mock.popups.AEONUI_RELOAD, "rechargement proposé")
end)

test("options : un résultat de recherche ouvre la page sur l'onglet du réglage", function()
    reset()
    local result = Options.Search(L.OPT_UF_CASTBAR_WIDTH)[1]
    eq(result.module, "unitframes")
    truthy(result.entry.tab, "réglage dans un onglet")
    Options.Reveal(result)
    eq(Window:Selected(), "unitframes")
    eq(Options:GetLayout("unitframes").selectedTab, result.entry.tab)
    Window:Hide()
end)

test("mode déplacement : clic droit = options du module, Maj + clic droit = position par défaut, filtre", function()
    reset()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(100, 20)
    NS.Modules.calling = "loot"
    NS.Movers:Register("testOptions", frame, "Test", "CENTER", 0, 0)
    NS.Modules.calling = nil
    NS:SetUnlocked(true)
    local toolbar = NS.Movers:GetToolbar()
    eq(toolbar:IsShown(), true, "barre d'outils")
    local overlay = NS.Movers.overlays.testOptions
    NS.Movers:Save("testOptions", "CENTER", "CENTER", 50, 50)
    overlay:GetScript("OnMouseUp")(overlay, "RightButton")
    eq(Window:Selected(), "loot", "options du module")
    truthy(NS.db.anchors.testOptions, "position gardée")
    Mock.shift = true
    overlay:GetScript("OnMouseUp")(overlay, "RightButton")
    Mock.shift = false
    eq(NS.db.anchors.testOptions, nil, "position par défaut")
    NS.Movers.filter = "bags"
    NS.Movers:SetUnlocked(true)
    eq(overlay:IsShown(), false, "filtré")
    NS.Movers.filter = "loot"
    NS.Movers:SetUnlocked(true)
    eq(overlay:IsShown(), true, "module choisi")
    NS:SetUnlocked(false)
    eq(NS.Movers.filter, nil, "filtre oublié au verrouillage")
    eq(toolbar:IsShown(), false)
    NS.Movers:Unregister("testOptions")
    Window:Hide()
end)

test("options : « Copier depuis » entre barres d'action (clés numériques)", function()
    reset()
    local layout = Options:GetLayout("actionbars")
    local bars = NS.db.modules.actionbars.bars
    bars[1].size = 50
    Find(layout, L.OPT_COPY_FROM, 2):Click()
    MenuRow("bars.1"):Click()
    eq(bars[2].size, 50, "taille copiée")
    Options.ResetModule("actionbars")
end)

test("widgets : la première case d'un onglet ne rejoint pas la ligne de l'onglet précédent", function()
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400)
    layout:Tab("Un")
    layout:Check("A", function() return true end, noop)
    layout:Tab("Deux")
    local first = layout:Check("B", function() return true end, noop)
    eq(first.layoutY, 0, "en haut de l'onglet")
end)

test("menu Échap : bouton AeonUI sous Options, sections suivantes décalées, clic ouvre la fenêtre", function()
    reset()
    local saved = _G.GameMenuFrame
    local menu = CreateFrame("Frame", nil, UIParent)
    local options = CreateFrame("Button", nil, menu)
    options:SetText(GAMEMENU_OPTIONS or "Options")
    _G.GAMEMENU_OPTIONS = options:GetText()
    local logout = CreateFrame("Button", nil, menu)
    logout:SetText("Déconnexion")
    menu:SetHeight(200)
    menu.buttonPool = { EnumerateActive = function() return next, { [options] = true, [logout] = true }, nil end }
    function menu:Layout()
        logout:ClearAllPoints()
        logout:SetPoint("TOP", options, "BOTTOM", 0, -20)
    end
    _G.GameMenuFrame = menu
    Options.SetupGameMenu()
    Options.SetupGameMenu()   -- une seule fois
    local button = menu.AeonUI
    truthy(button, "bouton créé")
    menu:Layout()
    local _, relTo, _, _, y = button:GetPoint()
    eq(relTo, options, "sous Options")
    eq(y, -10)
    eq(select(5, logout:GetPoint()), -20, "point d'origine conservé")
    eq(logout.points[#logout.points][5], -55, "section suivante décalée")
    eq(menu:GetHeight(), 235)
    Window:Hide()
    button.scripts.OnClick(button)
    eq(Window:IsShown(), true, "fenêtre ouverte")
    Window:Hide()
    _G.GameMenuFrame = saved
end)

test("boutons : largeur portée à celle du texte, jamais sous le minimum", function()
    local button = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    button:SetText("Réinitialiser absolument tous les éléments")
    NS.Widgets.FitText(button, 140)
    truthy(button:GetWidth() > 140, "élargi pour un texte long")
    button:SetText("OK")
    NS.Widgets.FitText(button, 140)
    eq(button:GetWidth(), 140, "minimum gardé")
end)
