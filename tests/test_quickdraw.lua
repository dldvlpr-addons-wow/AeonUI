-- tests/test_quickdraw.lua
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Q = NS.Modules:Get("quickdraw")

test("menu radial : lecture des entrées, positions et entrée visée", function()
    local list = Q.ParseEntries("spell:133\nitem: 6948\nmacro:Ma macro\nfoo:1\nspell:abc\nmount:12")
    eq(#list, 4, "lignes invalides ignorées")
    eq(list[1].value, 133); eq(list[2].value, 6948); eq(list[3].value, "Ma macro"); eq(list[4].kind, "mount")
    local x, y = Q.SlotPosition("arc", 1, 4, 100, 36)
    truthy(math.abs(x) < 1e-9 and math.abs(y - 100) < 1e-9, "première en haut")
    x = Q.SlotPosition("arc", 2, 4, 100, 36)
    truthy(math.abs(x - 100) < 1e-9, "deuxième à droite")
    eq(Q.Pick("arc", 5, 5, 4, 100, 36), nil, "zone morte")
    eq(Q.Pick("arc", 300, 10, 4, 100, 36), 2, "vers la droite, même loin")
    eq(Q.Pick("grid", -40, 40, 4, 100, 36), 1, "grille : case la plus proche")
    x, y = Q.SlotPosition("fan", 1, 3, 100, 36)
    truthy(x < -90 and y > 0, "bande : première à gauche, au-dessus")
    x, y = Q.SlotPosition("fan", 2, 3, 100, 36)
    truthy(math.abs(x) < 1e-9 and math.abs(y - 100) < 1e-9, "bande : milieu en haut")
    eq(Q.Pick("fan", 200, 5, 3, 100, 36), 3, "bande : vers la droite")
    x, y = Q.SlotPosition("fan", 1, 1, 100, 36)
    truthy(math.abs(x) < 1e-9 and math.abs(y - 100) < 1e-9, "bande : entrée seule en haut")
end)

test("menu radial : couleur de sélection et libellé de l'entrée survolée", function()
    reset()
    NS.db.modules.quickdraw.key = "shift-q"
    NS.db.modules.quickdraw.entries = "macro:Gauche\nmacro:Droite"
    NS.Modules:SetEnabled("quickdraw", true)
    local button, palette = Q:GetButton()
    button:GetScript("PreClick")(button, "LeftButton", true)
    eq(palette.label:GetText(), "", "rien de visé")
    palette.cx, palette.cy = 500, 300   -- curseur (500, 400) : 100 au-dessus, vers l'entrée 1 (haut)
    palette:GetScript("OnUpdate")(palette)
    eq(palette.label:GetText(), "Gauche")
    local first, second = palette:GetChildren()
    eq(first.edges.top.color[2], 0.82, "entrée visée : bordure couleur de sélection")
    eq(second.edges.top.color[2], NS.db.theme.border.g, "autre entrée : bordure du thème")
    NS.db.modules.quickdraw.showLabel = false
    palette.cx = 400   -- 45° : toujours l'entrée du haut, le libellé suit le réglage
    palette:GetScript("OnUpdate")(palette)
    palette.cy = 500   -- vise le bas : l'entrée 2
    palette:GetScript("OnUpdate")(palette)
    eq(palette.label:GetText(), "", "libellé coupé")
    eq(first.edges.top.color[2], NS.db.theme.border.g, "sélection déplacée")
    NS.db.modules.quickdraw.showLabel = true
    button:GetScript("PostClick")(button, "LeftButton", false)
    NS.Modules:SetEnabled("quickdraw", false)
    NS.db.modules.quickdraw.key, NS.db.modules.quickdraw.entries = "", ""
end)

test("menu radial : touche liée, appui ouvre, relâcher arme le sort survolé, rien en combat", function()
    reset()
    NS.db.modules.quickdraw.key = "shift-q"
    NS.db.modules.quickdraw.entries = "spell:133\nitem:6948\nmacro:Test\nspell:2"
    NS.Modules:SetEnabled("quickdraw", true)
    local button, palette = Q:GetButton()
    eq(Mock.overrideBindings[button]["SHIFT-Q"], "AeonUIQuickdrawButton", "touche liée")
    local pre, post = button:GetScript("PreClick"), button:GetScript("PostClick")
    pre(button, "LeftButton", true)
    truthy(palette:IsShown(), "appui : palette ouverte")
    eq(button:GetAttribute("type"), nil, "appui : aucune action")
    -- Curseur à (500, 400) dans le mock : palette centrée dessus ; on vise la droite.
    palette.cx, palette.cy = 400, 400
    pre(button, "LeftButton", false)
    eq(button:GetAttribute("type"), "item", "relâcher : entrée de droite")
    eq(button:GetAttribute("item"), "item:6948")
    post(button, "LeftButton", false)
    eq(palette:IsShown(), false, "fermée")
    eq(button:GetAttribute("type"), nil, "action effacée")
    Mock.SetCombat(true)
    pre(button, "LeftButton", true)
    eq(palette:IsShown(), false, "combat : rien")
    Mock.SetCombat(false)
    NS.Modules:SetEnabled("quickdraw", false)
    eq(Mock.overrideBindings[button], nil, "touche rendue")
    NS.db.modules.quickdraw.key, NS.db.modules.quickdraw.entries = "", ""
end)

test("menu radial : marqueur de cible 0 à 8 et monture favorite au hasard", function()
    local list = Q.ParseEntries("marker:3\nmarker:9\nmount:0")
    eq(#list, 2, "marqueur hors limites ignoré")
    eq(list[1].kind, "marker") eq(list[1].value, 3)
    eq(Q.EntryName(list[2]), NS.L.QUICKDRAW_RANDOM_MOUNT)
    eq(Q.Attributes(list[1]), nil, "marqueur : appel direct, pas d'attribut sécurisé")
end)

test("menu radial : deuxième palette sur sa touche, sous-menu ouvert au survol", function()
    reset()
    local db = NS.db.modules.quickdraw
    db.key, db.entries = "shift-q", "menu:3\nmacro:Droite"
    db.palettes.palette2.key, db.palettes.palette2.entries = "shift-e", "macro:Deux"
    db.palettes.palette3.entries = "macro:Sous\nmacro:Autre"
    eq(Q.ParseEntries("menu:9\nmenu:2")[1].value, 2, "palette hors limites ignorée")
    NS.Modules:SetEnabled("quickdraw", true)
    local button, palette = Q:GetButton()
    eq(Mock.overrideBindings[button]["SHIFT-E"], "AeonUIQuickdrawButton", "touche de la palette 2")
    local pre, post = button:GetScript("PreClick"), button:GetScript("PostClick")
    pre(button, "Palette2", true)
    palette.cx, palette.cy = 500, 300          -- curseur (500, 400) : vise le haut
    pre(button, "Palette2", false)
    eq(button:GetAttribute("macro"), "Deux", "palette 2 : sa propre entrée")
    post(button, "Palette2", false)
    pre(button, "LeftButton", true)
    palette.cx, palette.cy = 500, 300          -- vise l'entrée 1 : le sous-menu
    palette:GetScript("OnUpdate")(palette)
    eq(palette.label:GetText(), string.format(NS.L.QUICKDRAW_SUBMENU, 3))
    Mock.Advance(0.5)
    palette:GetScript("OnUpdate")(palette)
    eq(palette.cy, 300 + db.radius, "sous-menu centré sur l'entrée")
    palette.cx, palette.cy = 500, 500          -- vise le bas du sous-menu : son entrée 2
    pre(button, "LeftButton", false)
    eq(button:GetAttribute("macro"), "Autre", "relâcher : entrée du sous-menu")
    post(button, "LeftButton", false)
    NS.Modules:SetEnabled("quickdraw", false)
    db.key, db.entries = "", ""
    db.palettes.palette2.key, db.palettes.palette2.entries, db.palettes.palette3.entries = "", "", ""
end)
