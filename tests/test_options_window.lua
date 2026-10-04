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
    local overlay = Mock.popups.AEONUI_RELOAD.AeonUIReload
    truthy(overlay and overlay:IsShown(), "bouton d'action posé sur « Recharger »")
    eq(overlay:GetAttribute("macrotext"), "/reload", "ReloadUI() bloqué sur Forever : macro")
    eq(StaticPopupDialogs.AEONUI_RELOAD.OnAccept, nil, "aucun appel direct à ReloadUI")
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
    -- Clic droit sur un mover : page du module, onglet désigné par le mover.
    NS.Modules:SetEnabled("unitframes", true)
    NS:SetUnlocked(true)
    local overlay = NS.Movers.registry.uf_target.overlay
    overlay:GetScript("OnMouseUp")(overlay, "RightButton")
    eq(Window:Selected(), "unitframes")
    local layout = Options:GetLayout("unitframes")
    eq(layout.tabs[layout.selectedTab].label, L.UF_UNIT_TARGET, "onglet de la cible")
    truthy(layout.flash and layout.flash:IsShown(), "réglage surligné")
    NS:SetUnlocked(false)
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

test("options : en combat, /reload proposé par message seul, sans calque d'action", function()
    reset()
    Mock.SetCombat(true)
    Options.AskReload("x")
    truthy(Mock.popups.AEONUI_RELOAD_COMBAT, "message")
    eq(Mock.popups.AEONUI_RELOAD, nil, "pas de popup à calque")
    Mock.SetCombat(false)
    Mock.popups.AEONUI_RELOAD_COMBAT = nil
end)

test("options : export du compte collé, import après confirmation seulement", function()
    reset()
    local layout = Options:GetLayout("profiles")
    NS.db.theme.fontSize = 15
    Find(layout, L.OPT_PROFILE_EXPORT_ACCOUNT):Click()
    NS.db.theme.fontSize = 12
    Find(layout, L.OPT_PROFILE_IMPORT):Click()
    truthy(Mock.popups.AEONUI_IMPORT_ACCOUNT, "confirmation demandée")
    eq(NS.db.theme.fontSize, 12, "rien avant confirmation")
    Mock.acceptPopups = true
    Find(layout, L.OPT_PROFILE_IMPORT):Click()
    Mock.acceptPopups = false
    eq(NS.db.theme.fontSize, 15, "profil actif remplacé")
    NS.db.theme.fontSize = 12
    Mock.popups.AEONUI_IMPORT_ACCOUNT = nil
end)

test("options : page construite à sa première ouverture, recherche qui construit le reste", function()
    reset()
    local builds = 0
    Window:AddPage("lazyTest", "Page paresseuse", function()
        builds = builds + 1
        return CreateFrame("Frame")
    end, "modules")
    eq(builds, 0, "inscrite sans être construite")
    eq(Window:IsBuilt("lazyTest"), false)
    Window:Show("lazyTest")
    eq(builds, 1, "construite à l'ouverture")
    Window:Show("lazyTest")
    eq(builds, 1, "une seule fois")
    Window:AddPage("lazyTest2", "Seconde", function() builds = builds + 1 return CreateFrame("Frame") end, "modules")
    Options.Search("zz")
    eq(builds, 2, "recherche : toutes les pages construites")
    Window:Hide()
    for _, key in ipairs({ "lazyTest", "lazyTest2" }) do
        Window.pages[key] = nil
        for i, other in ipairs(Window.order) do if other == key then table.remove(Window.order, i) break end end
    end
    Window.selected = nil
end)

test("grille : deux réglages par rangée, réglages moins courants affichés en fin de bloc", function()
    NS.global.optionsMode = "advanced"
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400, { grid = true })
    local state = { a = false }
    local a = layout:Check("A", function() return state.a end, function(v) state.a = v end)
    local b = layout:Check("B", function() return true end, noop)
    local child = layout:Slider("Enfant de B", 0, 10, 1, function() return 1 end, noop, 16)
    layout:Title("Section")
    layout:Advanced("Plus (%d)")
    local rare = layout:Slider("Rare", 0, 10, 1, function() return 1 end, noop)
    layout.advancedGroup = nil   -- comme ModuleOptions:Visibility
    local common = layout:Check("Courant", function() return true end, noop)
    layout:Finish()
    truthy(common.gridRow.layoutY > rare.gridRow.layoutY, "réglage courant remonté au-dessus des avancés")
    eq(a.gridRow.layoutY, b.gridRow.layoutY, "même rangée")
    truthy(select(4, b.gridRow:GetPoint()) > select(4, a.gridRow:GetPoint()), "B dans la seconde colonne")
    truthy(child.gridRow.layoutY < a.gridRow.layoutY, "rangée suivante")
    eq(child:IsEnabled(), true, "B cochée : enfant actif")
    eq(rare.gridRow:IsShown(), true, "réglage moins courant affiché")
    truthy(rare.gridRow.layoutY < child.gridRow.layoutY, "en fin de bloc")
    eq(layout.groups[1].count, 1, "compté dans l'intertitre")
    a:SetChecked(true)
    a:Click()
    eq(state.a, true, "interrupteur")
end)

test("mode simple : réglages avancés masqués, bloc qui n'a qu'eux masqué, rien de perdu en avancé", function()
    NS.global.optionsMode = "simple"
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400, { grid = true })
    layout:Title("Courants")
    local common = layout:Check("Courant", function() return true end, noop)
    layout:Advanced("Plus (%d)")
    local rare = layout:Slider("Rare", 0, 10, 1, function() return 1 end, noop)
    local onlyTitle = layout:Title("Seulement avancés")
    layout:Advanced("Plus (%d)")
    local hidden = layout:Check("Caché", function() return true end, noop)
    layout:Finish()
    eq(common.gridRow:IsShown(), true, "réglage courant affiché")
    eq(rare.gridRow:IsShown(), false, "réglage avancé masqué")
    eq(onlyTitle:IsShown(), false, "bloc sans réglage courant masqué")
    eq(hidden.gridRow:IsShown(), false, "son réglage aussi")
    local simpleHeight = layout:Height()
    NS.global.optionsMode = "advanced"
    layout:Reflow()
    eq(rare.gridRow:IsShown(), true, "avancé : réglage affiché")
    eq(onlyTitle:IsShown(), true, "avancé : bloc affiché")
    truthy(layout:Height() > simpleHeight, "page plus haute en avancé")
end)

test("avancés en plusieurs morceaux d'un bloc : un seul intertitre, courants avant lui", function()
    NS.global.optionsMode = "advanced"
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400, { grid = true })
    layout:Title("Bloc")
    local first = layout:Check("Premier", function() return true end, noop)
    layout:Advanced("Plus (%d)")
    local rare1 = layout:Check("Rare 1", function() return true end, noop)
    layout:EndAdvanced()
    local middle = layout:Check("Milieu", function() return true end, noop)
    layout:Advanced("Plus (%d)")
    local rare2 = layout:Check("Rare 2", function() return true end, noop)
    layout:Finish()
    eq(#layout.groups, 1, "un seul intertitre")
    eq(layout.groups[1].count, 2, "deux réglages avancés")
    truthy(middle.gridRow.layoutY > rare1.gridRow.layoutY, "courant avant les avancés")
    truthy(first.gridRow.layoutY >= middle.gridRow.layoutY, "ordre des courants gardé")
    truthy(rare1.gridRow.layoutY >= rare2.gridRow.layoutY, "ordre des avancés gardé")
end)

test("mode simple : un réglage avancé trouvé par la recherche passe la fenêtre en avancé", function()
    Options.SetMode("simple")
    Window:Show("swingtimer")
    local layout = Options:GetLayout("swingtimer")
    local target
    for _, entry in ipairs(layout.labels) do
        if layout:ModeHidden(entry) then target = entry break end
    end
    truthy(target, "bloc Visibilité masqué en simple")
    eq(Window:GetFrame().mode:GetText(), L.OPT_MODE_SIMPLE, "libellé de la bascule")
    Options.Reveal({ module = "swingtimer", entry = target })
    eq(NS.global.optionsMode, "advanced", "mode avancé")
    eq(layout:ModeHidden(target), false, "réglage affiché")
    eq(Window:GetFrame().mode:GetText(), L.OPT_MODE_ADVANCED, "libellé de la bascule")
    Window:Hide()
end)

test("fenêtre : catégories en onglets, point d'état, interrupteur dans l'en-tête, outils qui suivent la page", function()
    reset()
    Window:Show("cursor")
    eq(Window.category, "interface", "curseur rangé dans Interface")
    local rows, cursorRow, generalRow = Window.rows, nil, nil
    for i, row in ipairs(rows) do
        if row:IsShown() and row.key == "cursor" then cursorRow = i end
        if row:IsShown() and row.key == "general" then generalRow = i end
    end
    truthy(cursorRow, "curseur dans la liste")
    eq(generalRow, nil, "pages générales dans leur onglet")
    eq(rows[cursorRow].dot:IsShown(), true, "point d'état")
    local tabs, interfaceTab = Window:GetFrame().categoryTabs, nil
    for _, tab in ipairs(tabs) do
        if tab:GetText() == L.OPT_GROUP_INTERFACE then interfaceTab = tab end
    end
    eq(interfaceTab and interfaceTab.selected, true, "onglet Interface choisi")
    tabs[1]:GetScript("OnClick")(tabs[1])
    eq(Window:CategoryOf(Window:Selected()), "general", "onglet Général : première page générale")
    Window:Show("cursor")
    local layout = Options:GetLayout("cursor")
    local enable = Find(layout, string.format(L.OPT_ENABLE, NS.Modules:Get("cursor").title))
    local before = NS.db.modules.cursor.enabled
    enable:SetChecked(not before)
    enable:Click()
    eq(NS.db.modules.cursor.enabled, not before, "interrupteur de l'en-tête")
    enable:SetChecked(before)
    enable:Click()
    eq(NS.db.modules.cursor.enabled, before)
    local tools = Window:GetFrame().tools
    eq(tools.reset:IsShown(), true, "réinitialiser le module")
    eq(tools.reset.tooltip, L.OPT_RESET_MODULE)
    eq(tools.reload:GetAttribute("macrotext"), "/reload", "recharger par macro")
    Window:Show("general")
    eq(tools.reset:IsShown(), false, "page générale : rien à réinitialiser")
    Window:Hide()
end)

test("aperçu : un clic sur la barre 2 ouvre son onglet", function()
    reset()
    local layout = Options:GetLayout("actionbars")
    local label = string.format(L.MOVER_ACTIONBAR, 2)
    local spot
    for _, frame in ipairs(Mock.frames) do
        if frame.hint == label and frame:IsShown() then spot = frame end
    end
    truthy(spot, "zone cliquable de la barre 2")
    spot:Click()
    eq(Window:Selected(), "actionbars")
    eq(layout.tabs[layout.selectedTab].label, label, "onglet de la barre 2")
    Window:Hide()
end)

test("recherche dans la page : premier réglage amené, Entrée passe au suivant", function()
    reset()
    local panel = Window:Ensure("unitframes")
    local layout = Options:GetLayout("unitframes")
    panel.search:Type(L.OPT_UF_CASTBAR_WIDTH)
    eq(Window:Selected(), "unitframes")
    local first = layout.selectedTab
    truthy(first, "onglet ouvert")
    panel.search:GetScript("OnEnterPressed")(panel.search)
    truthy(layout.selectedTab ~= first, "réglage suivant, dans un autre onglet")
    Window:Hide()
end)

test("bulle d'aide : montrée une fois, fermée et retenue au premier clic", function()
    reset()
    NS.global.tipsSeen.testTip = nil
    NS.Widgets.HideTip()
    local anchor = CreateFrame("Frame", nil, UIParent)
    local tip = NS.Widgets.Tip(anchor, "testTip", "texte")
    truthy(tip and tip:IsShown(), "bulle montrée")
    tip:GetScript("OnEvent")(tip, "GLOBAL_MOUSE_DOWN")
    eq(tip:IsShown(), false, "fermée par un clic")
    eq(NS.global.tipsSeen.testTip, true, "retenue")
    eq(NS.Widgets.Tip(anchor, "testTip", "texte"), nil, "plus montrée")
    NS.global.tipsSeen.testTip = nil
end)

test("options : profils de classe, style appliqué au profil actuel ou profil de classe créé puis gardé", function()
    reset()
    local layout = Options:GetLayout("profiles")
    local origin = NS.Database:ActiveProfileName()
    Find(layout, L.OPT_PROFILE_CLASS_APPLY):Click()        -- mage : style lanceur par défaut
    eq(NS.Database:ActiveProfileName(), origin, "profil actuel gardé")
    eq(NS.db.modules.unitframes.units.player.castbarWidth, 300, "style appliqué")
    local switch = Find(layout, L.OPT_PROFILE_CLASS_SWITCH)
    switch:Click()
    local name = NS.Install.ClassProfileName("caster")
    eq(NS.Database:ActiveProfileName(), name, "profil de classe créé")
    eq(NS.Modules:Get("gcdbar").enabled, true)
    NS.db.modules.gcdbar.width = 123
    NS:SwitchProfile(origin)
    switch:Click()
    eq(NS.Database:ActiveProfileName(), name, "second clic : bascule")
    eq(NS.db.modules.gcdbar.width, 123, "réglage du joueur gardé")
    NS:SwitchProfile(origin)
    NS.global.profiles[name] = nil
end)
