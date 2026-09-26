-- tests/test_movers.lua
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Movers = NS.Movers

local function approx(a, b, message)
    if math.abs(a - b) > 0.0001 then
        error(string.format("%s : attendu %.4f, obtenu %.4f", message or "valeur", b, a), 2)
    end
end

local function newFrame(name, secure)
    local frame = CreateFrame(secure and "Button" or "Frame", name, UIParent,
        secure and "SecureUnitButtonTemplate" or nil)
    frame:SetSize(100, 20)
    return frame
end

test("movers : PointFor par tiers d'écran", function()
    eq(Movers.PointFor(960, 540, 1920, 1080), "CENTER")
    eq(Movers.PointFor(100, 1000, 1920, 1080), "TOPLEFT")
    eq(Movers.PointFor(1800, 50, 1920, 1080), "BOTTOMRIGHT")
    eq(Movers.PointFor(960, 1000, 1920, 1080), "TOP")
    eq(Movers.PointFor(100, 540, 1920, 1080), "LEFT")
end)

test("movers : OffsetFor donne le décalage relatif au même point d'UIParent", function()
    local x, y = Movers.OffsetFor("TOPLEFT", 10, 1040, 100, 20, 1920, 1080)
    eq(x, 10); eq(y, -20)
    x, y = Movers.OffsetFor("CENTER", 910, 530, 100, 20, 1920, 1080)
    eq(x, 0); eq(y, 0)
    x, y = Movers.OffsetFor("BOTTOMRIGHT", 1820, 0, 100, 20, 1920, 1080)
    eq(x, 0); eq(y, 0)
end)

test("movers : SnapDelta accroche sous le seuil, au plus proche, sinon 0", function()
    local dx, dy = Movers.SnapDelta(5, 300, 100, 20, { 0 }, {}, 8)
    eq(dx, -5, "bord gauche à 5 px : collé")
    eq(dy, 0)
    dx = Movers.SnapDelta(12, 300, 100, 20, { 0 }, {}, 8)
    eq(dx, 0, "à 12 px : pas d'aimant")
    dx = Movers.SnapDelta(5, 300, 100, 20, { 0, 3 }, {}, 8)
    eq(dx, -2, "candidat le plus proche")
    -- centre du cadre (55) contre ligne centrale 60
    dx = Movers.SnapDelta(5, 300, 100, 20, { 60 }, {}, 8)
    eq(dx, 5, "le centre accroche aussi")
end)

test("movers : Register + Load pose le défaut, Save puis Load repose, Reset revient au défaut", function()
    reset()
    UIParent:SetScale(768 / 1080)   -- mult = 1 : positions entières
    NS.Pixel:Update()
    NS.db.anchors.testA = nil
    local frame = newFrame("AeonUITestMoverA")
    Movers:Register("testA", frame, "Test A", "TOP", 0, -50)
    truthy(Movers:Load("testA"))
    local point, rel, relPoint, x, y = frame:GetPoint()
    eq(point, "TOP"); eq(rel, UIParent); eq(relPoint, "TOP"); eq(x, 0); eq(y, -50)
    Movers:Save("testA", "CENTER", "CENTER", 10, 30)
    Movers:Load("testA")
    point, _, _, x, y = frame:GetPoint()
    eq(point, "CENTER"); eq(x, 10); eq(y, 30)
    eq(frame:GetNumPoints(), 1, "un seul ancrage")
    Movers:Reset("testA")
    eq(NS.db.anchors.testA, nil)
    point = frame:GetPoint()
    eq(point, "TOP", "défaut repris")
    truthy(Movers:Anchor("testA").y == -50)
    Movers:Unregister("testA")
    eq(Movers:Anchor("testA"), nil)
end)

test("movers : positions sauvées arrondies au pixel physique", function()
    reset()
    UIParent:SetScale(768 / 1080)
    NS.Pixel:Update()
    local mult = NS.Pixel.mult
    local frame = newFrame("AeonUITestMoverB")
    Movers:Register("testB", frame, "Test B", "CENTER", 0, 0)
    Movers:Save("testB", "CENTER", "CENTER", 10.3, 7.77)
    local a = NS.db.anchors.testB
    approx(a.x / mult, math.floor(a.x / mult + 0.5), "x multiple de mult")
    approx(a.y / mult, math.floor(a.y / mult + 0.5), "y multiple de mult")
    Movers:Unregister("testB")
    NS.db.anchors.testB = nil
    UIParent:SetScale(768 / 1080)
    NS.Pixel:Update()
end)

test("movers : Nudge déplace de 1 puis de 10 avec Maj et sauvegarde", function()
    reset()
    local frame = newFrame("AeonUITestMoverC")
    UIParent:SetScale(768 / 1080)   -- mult = 1 : les décalages sont entiers
    NS.Pixel:Update()
    Movers:Register("testC", frame, "Test C", "CENTER", 0, 0)
    Movers:Load("testC")
    NS:SetUnlocked(true)
    local overlay = Movers.registry.testC.overlay
    truthy(overlay and overlay:IsShown(), "calque visible en mode déverrouillé")
    Movers:Select("testC")
    eq(overlay.keyboard, true, "clavier actif sur le calque sélectionné")
    overlay:GetScript("OnKeyDown")(overlay, "RIGHT")
    eq(NS.db.anchors.testC.x, 1, "1 px à droite")
    Mock.shift = true
    overlay:GetScript("OnKeyDown")(overlay, "UP")
    Mock.shift = false
    eq(NS.db.anchors.testC.y, 10, "10 px vers le haut avec Maj")
    eq(overlay.propagateKeyboard, false, "la flèche est consommée")
    overlay:GetScript("OnKeyDown")(overlay, "ESCAPE")
    eq(overlay.propagateKeyboard, true, "les autres touches passent")
    local _, _, _, x, y = frame:GetPoint()
    eq(x, 1); eq(y, 10)
    NS:SetUnlocked(false)
    eq(overlay:IsShown(), false, "calque caché au verrouillage")
    Movers:Unregister("testC")
    NS.db.anchors.testC = nil
    UIParent:SetScale(768 / 1080)
    NS.Pixel:Update()
end)

test("movers : Drop aimante sur le bord de l'écran et convertit en point", function()
    reset()
    UIParent:SetScale(768 / 1080)
    NS.Pixel:Update()
    Mock.SetRect(UIParent, 0, 0, 1920, 1080)
    local frame = newFrame("AeonUITestMoverD")
    Movers:Register("testD", frame, "Test D", "CENTER", 0, 0)
    NS:SetUnlocked(true)
    local overlay = Movers.registry.testD.overlay
    -- Le joueur a lâché le calque à 5 px du bord gauche, en haut de l'écran.
    Mock.SetRect(overlay, 5, 1000, 100, 20)
    Movers:Drop("testD")
    local a = NS.db.anchors.testD
    eq(a.point, "TOPLEFT", "point choisi par tiers d'écran")
    eq(a.x, 0, "collé au bord gauche")
    eq(a.y, -60, "1080 - (1000 + 20)")
    local point, _, _, x, y = frame:GetPoint()
    eq(point, "TOPLEFT"); eq(x, 0); eq(y, -60)
    -- Maj : pas d'aimant.
    Mock.shift = true
    Mock.SetRect(overlay, 5, 1000, 100, 20)
    Movers:Drop("testD")
    Mock.shift = false
    eq(NS.db.anchors.testD.x, 5, "sans aimant, la position brute est gardée")
    NS:SetUnlocked(false)
    Movers:Unregister("testD")
    NS.db.anchors.testD = nil
    UIParent:SetScale(768 / 1080)
    NS.Pixel:Update()
end)

test("movers : Load d'un cadre protégé en combat attend la fin du combat", function()
    reset()
    UIParent:SetScale(768 / 1080)
    NS.Pixel:Update()
    local frame = newFrame("AeonUITestMoverE", true)
    Movers:Register("testE", frame, "Test E", "CENTER", 0, 0)
    Movers:Load("testE")
    Movers:Save("testE", "CENTER", "CENTER", 40, 0)
    Mock.SetCombat(true)
    eq(Movers:Load("testE"), false, "différé")
    local _, _, _, x = frame:GetPoint()
    eq(x, 0, "pas encore déplacé")
    Mock.SetCombat(false)
    _, _, _, x = frame:GetPoint()
    eq(x, 40, "déplacé à la sortie du combat")
    Movers:Unregister("testE")
    NS.db.anchors.testE = nil
end)

test("movers : les modules existants sont enregistrés avec leurs clés historiques", function()
    reset()
    NS.db.modules.topbar.position = "FREE"
    NS.Modules:Refresh("topbar")
    local cotankWasEnabled = NS.db.modules.cotank.enabled
    NS.Modules:SetEnabled("cotank", true)
    local keys = table.concat(Movers:List(), ",")
    for _, key in ipairs({ "alerts", "combatTimer", "cotank", "reminders", "topbar" }) do
        truthy(keys:find(key, 1, true), key .. " enregistré")
    end
    NS.db.modules.topbar.position = "TOP"
    NS.Modules:Refresh("topbar")
    truthy(not table.concat(Movers:List(), ","):find("topbar", 1, true), "topbar retiré hors mode libre")
    NS.Modules:SetEnabled("cotank", cotankWasEnabled)
end)

test("movers : grille dessinée au déverrouillage si le thème la demande", function()
    reset()
    NS.db.theme.grid = 32
    NS:SetUnlocked(true)
    local count = 0
    for _, frame in ipairs(Mock.frames) do
        if frame.lines then count = #frame.lines end
    end
    truthy(count > 10, "des lignes de grille existent")
    NS:SetUnlocked(false)
    NS.db.theme.grid = 0
end)

test("movers : Reset efface une clé non enregistrée (barre du haut hors mode libre)", function()
    reset()
    NS.db.modules.topbar.position = "TOP"
    NS.Modules:Refresh("topbar")
    NS.db.anchors.topbar = { point = "CENTER", relPoint = "CENTER", x = 5, y = 5 }
    Movers:Reset("topbar")
    eq(NS.db.anchors.topbar, nil, "position oubliée même sans calque")
    NS.db.anchors.topbar = { point = "CENTER", relPoint = "CENTER", x = 5, y = 5 }
    Movers:ResetAll()
    eq(NS.db.anchors.topbar, nil, "ResetAll aussi")
end)

test("movers : en combat, le clavier des calques se coupe et OnKeyDown ne touche à rien", function()
    reset()
    local frame = newFrame("AeonUITestMoverF")
    Movers:Register("testF", frame, "Test F", "CENTER", 0, 0)
    NS:SetUnlocked(true)
    local overlay = Movers.registry.testF.overlay
    Movers:Select("testF")
    eq(overlay.keyboard, true)
    Mock.SetCombat(true)
    eq(overlay.keyboard, false, "clavier coupé à l'entrée en combat")
    overlay.propagateKeyboard = nil
    overlay:GetScript("OnKeyDown")(overlay, "LEFT")
    eq(overlay.propagateKeyboard, nil, "SetPropagateKeyboardInput jamais appelé en combat")
    eq(NS.db.anchors.testF, nil, "rien déplacé")
    -- Glisser refusé sur un cadre protégé : le lâcher ne sauve rien.
    Mock.SetCombat(false)
    NS:SetUnlocked(false)
    Movers:Unregister("testF")
    local secure = newFrame("AeonUITestMoverG", true)
    Movers:Register("testG", secure, "Test G", "CENTER", 0, 0)
    NS:SetUnlocked(true)
    local o = Movers.registry.testG.overlay
    Mock.SetCombat(true)
    o:GetScript("OnDragStart")(o)
    Mock.SetRect(o, 300, 300, 100, 20)
    o:GetScript("OnDragStop")(o)
    eq(NS.db.anchors.testG, nil, "glisser refusé : pas de sauvegarde")
    Mock.SetCombat(false)
    NS:SetUnlocked(false)
    Movers:Unregister("testG")
end)

test("movers : le calque a sa propre taille, celle du cadre", function()
    reset()
    local frame = newFrame("AeonUITestMoverH")
    frame:SetSize(123, 45)
    Movers:Register("testH", frame, "Test H", "CENTER", 0, 0)
    NS:SetUnlocked(true)
    local overlay = Movers.registry.testH.overlay
    eq(overlay:GetWidth(), 123); eq(overlay:GetHeight(), 45)
    local point, rel = overlay:GetPoint()
    eq(point, "TOPLEFT"); eq(rel, frame)
    NS:SetUnlocked(false)
    Movers:Unregister("testH")
    Movers:Register("testH", frame, "Test H", "CENTER", 0, 0)
    eq(Movers.registry.testH.overlay, overlay, "calque réutilisé après ré-enregistrement")
    Movers:Unregister("testH")
end)

test("movers : Adopt pose le cadre sur son support ; en combat, un cadre protégé attend la sortie", function()
    reset()
    local Movers = NS.Movers
    local frame = CreateFrame("Frame", "AdoptedTest", UIParent)
    frame:SetSize(50, 20)
    frame:SetPoint("CENTER", UIParent, "CENTER", 5, 5)
    local holder = Movers:Adopt("adoptTest", frame, "Test", "CENTER", 100, 100)
    local _, rel = frame:GetPoint()
    eq(rel, holder, "réancré sur le support")
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)   -- Blizzard le replace : le hook reprend
    _, rel = frame:GetPoint()
    eq(rel, holder, "hook SetPoint : repris")
    frame.secure = true
    Mock.SetCombat(true)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    _, rel = frame:GetPoint()
    eq(rel, UIParent, "protégé en combat : pas touché")
    Mock.SetCombat(false)
    _, rel = frame:GetPoint()
    eq(rel, holder, "repris à la sortie du combat")
    eq(Movers.adopted.adoptTest.anchoring, false, "verrou rendu")
    Movers:Release("adoptTest")
    eq(Movers.registry.adoptTest, nil)
end)

test("HideRegion garde les événements et ShowRegion rend l'objet vivant", function()
    reset()
    local region = CreateFrame("Frame", "RegionTest", UIParent)
    region:RegisterEvent("PET_BAR_UPDATE")
    NS.HideRegion(region)
    eq(region:IsShown(), false)
    region:Show()
    eq(region:IsShown(), false, "Blizzard le remontre : recaché")
    truthy(region.events.PET_BAR_UPDATE, "événements intacts")
    NS.ShowRegion(region)
    eq(region:IsShown(), true)
    region.secure = true
    Mock.SetCombat(true)
    NS.HideRegion(region)
    eq(region:IsShown(), true, "protégé en combat : différé")
    Mock.SetCombat(false)
    eq(region:IsShown(), false, "caché à la sortie du combat")
end)

test("movers : SideFor, RelativeOffset et WouldCreateCycle", function()
    local target = { left = 100, bottom = 500, width = 200, height = 40 }
    local below = { left = 120, bottom = 440, width = 100, height = 20 }
    local p, rp = Movers.SideFor(below, target)
    eq(p, "TOP"); eq(rp, "BOTTOM")
    local x, y = Movers.RelativeOffset(p, rp, below, target)
    eq(x, -30, "centre 170 contre centre 200"); eq(y, -40, "haut 460 contre bas 500")
    p, rp = Movers.SideFor({ left = 320, bottom = 500, width = 50, height = 40 }, target)
    eq(p, "LEFT"); eq(rp, "RIGHT")
    local anchors = { b = { target = "a" }, c = { target = "b" } }
    eq(Movers.WouldCreateCycle("a", "c", anchors), true, "a -> c -> b -> a")
    eq(Movers.WouldCreateCycle("d", "c", anchors), false)
    eq(Movers.WouldCreateCycle("a", "a", anchors), true)
end)

local function anchorPair()
    reset()
    UIParent:SetScale(768 / 1080)
    NS.Pixel:Update()
    Mock.SetRect(UIParent, 0, 0, 1920, 1080)
    local parent, child = newFrame("AeonUITestAnchorParent"), newFrame("AeonUITestAnchorChild")
    Mock.SetRect(parent, 100, 500, 200, 40)
    Mock.SetRect(child, 120, 440, 100, 20)
    Movers:Register("anchorParent", parent, "Parent", "CENTER", 0, 0)
    Movers:Register("anchorChild", child, "Child", "CENTER", 0, 0)
    return parent, child
end

local function anchorCleanup()
    NS:SetUnlocked(false)
    Movers:Unregister("anchorChild")
    Movers:Unregister("anchorParent")
    NS.db.anchors.anchorChild, NS.db.anchors.anchorParent = nil, nil
end

test("movers : AttachTo ancre sans déplacer, la cible absente rend la position de secours", function()
    local parent, child = anchorPair()
    truthy(Movers:AttachTo("anchorChild", "anchorParent"))
    local a = NS.db.anchors.anchorChild
    eq(a.target, "anchorParent"); eq(a.point, "TOP"); eq(a.relPoint, "BOTTOM")
    eq(a.x, -30); eq(a.y, -40)
    local point, rel, relPoint, x, y = child:GetPoint()
    eq(point, "TOP"); eq(rel, parent); eq(relPoint, "BOTTOM"); eq(x, -30); eq(y, -40)
    truthy(a.fallback and a.fallback.point, "secours mémorisé")
    Movers:Unregister("anchorParent")
    _, rel = child:GetPoint()
    eq(rel, UIParent, "cible partie : secours à l'écran")
    Movers:Register("anchorParent", parent, "Parent", "CENTER", 0, 0)
    Movers:Load("anchorParent")
    _, rel = child:GetPoint()
    eq(rel, parent, "cible revenue : l'enfant la suit de nouveau")
    eq(Movers:AttachTo("anchorParent", "anchorChild"), false, "boucle refusée")
    truthy(Movers:Detach("anchorChild"))
    eq(NS.db.anchors.anchorChild.target, nil)
    _, rel = child:GetPoint()
    eq(rel, UIParent)
    anchorCleanup()
end)

test("movers : largeur reprise de la cible, suivie quand la cible ou le module la change", function()
    local parent, child = anchorPair()
    Movers:AttachTo("anchorChild", "anchorParent")
    truthy(Movers:SetMatch("anchorChild", "width", true))
    eq(child:GetWidth(), 200, "largeur de la cible")
    parent:SetWidth(260)
    parent:GetScript("OnSizeChanged")(parent)
    eq(child:GetWidth(), 260, "suit la cible")
    child:SetWidth(90)   -- rafraîchissement du module
    eq(child:GetWidth(), 260, "reprise après le module")
    Movers:SetMatch("anchorChild", "width", false)
    child:SetWidth(90)
    eq(child:GetWidth(), 90, "rendue au module")
    anchorCleanup()
end)

test("movers : glisser un élément ancré change son décalage, pas son ancrage", function()
    local parent, child = anchorPair()
    Movers:AttachTo("anchorChild", "anchorParent")
    NS:SetUnlocked(true)
    Mock.SetRect(Movers.registry.anchorParent.overlay, 100, 500, 200, 40)
    Mock.SetRect(Movers.registry.anchorChild.overlay, 150, 400, 100, 20)
    Mock.shift = true   -- pas d'aimant
    Movers:Drop("anchorChild")
    Mock.shift = false
    local a = NS.db.anchors.anchorChild
    eq(a.target, "anchorParent"); eq(a.x, 0); eq(a.y, -80)
    local _, rel = child:GetPoint()
    eq(rel, parent)
    anchorCleanup()
end)

test("movers : axe fixé à l'écran garde son bord quand la cible bouge", function()
    local parent, child = anchorPair()
    Movers:AttachTo("anchorChild", "anchorParent")
    truthy(Movers:SetEdge("anchorChild", "y", true))
    eq(NS.db.anchors.anchorChild.edgeY, 440)
    Mock.SetRect(child, 120, 400, 100, 20)   -- rendu après que la cible a descendu de 40
    Movers:Load("anchorChild")
    local _, _, _, x, y = child:GetPoint()
    eq(x, -30, "X suit toujours la cible"); eq(y, 0, "Y compensé de 40 : bas gardé à 440")
    anchorCleanup()
end)

test("movers : centrer à l'écran décale d'un demi-pixel si la parité l'exige", function()
    reset()
    UIParent:SetScale(768 / 1080)
    NS.Pixel:Update()
    Mock.SetRect(UIParent, 0, 0, 1920, 1080)
    local frame = newFrame("AeonUITestCenter")
    frame:SetSize(101, 20)
    Movers:Register("center", frame, "Center", "TOP", 0, 0)
    truthy(Movers:CenterOnScreen("center"))
    local a = NS.db.anchors.center
    eq(a.point, "CENTER"); eq(a.x, -0.5, "1920 - 101 impair"); eq(a.y, 0, "1080 - 20 pair")
    Movers:Unregister("center")
    NS.db.anchors.center = nil
end)

test("movers : un ancrage mal typé venu d'un import est nettoyé", function()
    local profile = { anchors = {
        a = { point = "TOP", relPoint = "BOTTOM", x = 0, y = 0, target = 5, fallback = "x", edgeX = "y", matchWidth = 1 },
    }, modules = {}, theme = {} }
    NS.Database.FillProfile(profile)
    local a = profile.anchors.a
    eq(a.target, nil); eq(a.fallback, nil); eq(a.edgeX, nil); eq(a.matchWidth, nil)
    eq(a.point, "TOP", "position gardée")
end)

test("movers : boucle importée (A sur B, B sur A, A sur A) posée sur le secours, sans erreur", function()
    local parent, child = anchorPair()
    NS.db.anchors.anchorChild = { point = "TOP", relPoint = "BOTTOM", x = 0, y = 0, target = "anchorParent",
                                  fallback = { point = "CENTER", relPoint = "CENTER", x = 1, y = 1 } }
    NS.db.anchors.anchorParent = { point = "TOP", relPoint = "BOTTOM", x = 0, y = 0, target = "anchorChild" }
    truthy(Movers:Load("anchorChild"))
    local _, rel = child:GetPoint()
    eq(rel, UIParent, "boucle : secours")
    _, rel = parent:GetPoint()
    eq(rel, UIParent, "boucle : défaut sans secours")
    NS.db.anchors.anchorParent = { point = "TOP", relPoint = "BOTTOM", x = 0, y = 0, target = "anchorParent" }
    truthy(Movers:Load("anchorParent"), "ancré sur lui-même : posé quand même")
    anchorCleanup()
end)

test("movers : un cadre protégé ne suit pas une cible non protégée", function()
    reset()
    Mock.SetRect(UIParent, 0, 0, 1920, 1080)
    local target = newFrame("AeonUITestPlainTarget")
    local secure = newFrame("AeonUITestSecureChild", true)
    Mock.SetRect(target, 100, 500, 200, 40)
    Mock.SetRect(secure, 100, 440, 100, 20)
    Movers:Register("plainTarget", target, "T", "CENTER", 0, 0)
    Movers:Register("secureChild", secure, "S", "CENTER", 0, 0)
    eq(Movers:AttachTo("secureChild", "plainTarget"), false)
    eq(NS.db.anchors.secureChild, nil)
    Movers:Unregister("secureChild")
    Movers:Unregister("plainTarget")
end)

test("profil importé : la touche du menu radial reste celle du joueur", function()
    reset()
    NS.db.modules.quickdraw.key = "SHIFT-Q"
    local copy = NS.Database.DeepCopy(NS.db)
    copy.modules.quickdraw.key = "W"
    -- Même chemin que ImportProfile, sans remplacer le profil actif (les modules gardent leur table).
    local imported = NS.Database.Deserialize(NS.Database.Export(copy))
    local profile = NS.Database.Sanitize(NS.Database.FillProfile(imported), NS.db)
    eq(profile.modules.quickdraw.key, "SHIFT-Q")
    NS.db.modules.quickdraw.key = ""
end)
