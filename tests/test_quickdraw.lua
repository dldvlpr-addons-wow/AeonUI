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
