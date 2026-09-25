-- tests/test_transverse.lua : recherche dans les options, envoi de profil au groupe, molette et
-- coordonnées sur les movers.
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset
local Options, Share, Movers = NS.Options, NS.ProfileShare, NS.Movers

test("options : recherche par titre, libellé, sans accents, ouverture de la sous-page", function()
    reset()
    local results = Options.Search(L.OPT_LOOT_WINDOW)
    truthy(#results >= 1, "libellé du module Butin trouvé")
    eq(results[1].module, "loot")
    eq(#Options.Search("x"), 0, "une lettre : rien")
    local titles = Options.Search(L.BAGS_TITLE)
    local found = false
    for _, result in ipairs(titles) do if result.module == "bags" then found = true end end
    truthy(found, "titre")
    -- Mots dans le désordre, en majuscules : le libellé est retrouvé quand même.
    local reversed = {}
    for word in L.OPT_TOPBAR_PERF_COMBAT:gmatch("%S+") do table.insert(reversed, 1, word:upper()) end
    local hit = Options.Search(table.concat(reversed, " "))[1]
    truthy(hit and hit.module == "topbar" and hit.label == L.OPT_TOPBAR_PERF_COMBAT, "mots dans le désordre")
    Options.OpenModule("bags")
    eq(NS.OptionsWindow:Selected(), "bags", "page du module ouverte")
    NS.OptionsWindow:Hide()
end)

test("profil au groupe : découpage, envoi limité par le débit, réception, confirmation", function()
    reset()
    eq(Share:Send(), false, "hors groupe")
    -- Groupe quitté pendant l'envoi (Classic : faux) : envoi arrêté, pas de boucle.
    Mock.groupSize = 2
    local send = C_ChatInfo.SendAddonMessage
    C_ChatInfo.SendAddonMessage = function() return false end
    truthy(Share:Send())
    Mock.groupSize = 0
    Mock.Advance(1)
    eq(Share:Send(), false, "envoi précédent terminé, hors groupe")
    -- Verrouillage (code 11) : morceau rejoué, pas d'abandon.
    Mock.groupSize = 2
    local locked = 2
    C_ChatInfo.SendAddonMessage = function(...)
        if locked > 0 then locked = locked - 1 return 11 end
        return send(...)
    end
    Mock.addonMessages = {}
    truthy(Share:Send())
    Mock.Advance(60)
    eq(#Mock.addonMessages, #Share.Split(NS.Database.Export(NS.db)), "verrouillage rejoué")
    C_ChatInfo.SendAddonMessage = send
    Mock.addonMessages = {}
    Mock.addonThrottle = 1
    truthy(Share:Send())
    Mock.Advance(60)
    local expected = #Share.Split(NS.Database.Export(NS.db))
    eq(#Mock.addonMessages, expected, "tous les morceaux, un refus de débit rejoué")
    eq(Mock.addonMessages[1][3], "PARTY")
    -- Réception chez un autre joueur : morceaux dans le désordre, expéditeur du groupe.
    Mock.groupMembers.Alice = true
    for i = #Mock.addonMessages, 1, -1 do
        Mock.FireEvent("CHAT_MSG_ADDON", "AeonUI", Mock.addonMessages[i][2], "PARTY", "Alice-Forever")
    end
    local profile = NS.Database.Export(NS.db)
    truthy(Mock.popups.AEONUI_PROFILE_RECEIVED, "confirmation demandée")
    truthy(StaticPopupDialogs.AEONUI_PROFILE_RECEIVED.text:find("Alice", 1, true))
    Mock.popups = {}
    Share.Receive("1/1:" .. NS.Database.Serialize(NS.db), "Mallory-Forever")
    eq(Mock.popups.AEONUI_PROFILE_RECEIVED, nil, "hors groupe : ignoré")
    Share.Receive("1/1:pas un profil", "Alice-Forever")
    eq(Mock.popups.AEONUI_PROFILE_RECEIVED, nil, "chaîne invalide : ignorée")
    -- Seconde réception pendant la question : le profil suit la fenêtre (data), rien n'est perdu.
    Share.Receive("1/1:" .. NS.Database.Serialize(NS.db), "Alice-Forever")
    truthy(Mock.popups.AEONUI_PROFILE_RECEIVED.data, "profil passé à la fenêtre")
    Mock.popups = {}
    Share.Receive(Mock.SetSecret("1/1:" .. NS.Database.Serialize(NS.db)), "Alice")
    eq(Mock.popups.AEONUI_PROFILE_RECEIVED, nil, "message secret : ignoré")
    Mock.groupSize, Mock.groupMembers = 0, {}
end)

test("movers : molette, Maj et Ctrl, coordonnées saisies", function()
    reset()
    local frame = CreateFrame("Frame", "AeonUITestMover", UIParent)
    frame:SetSize(50, 20)
    Movers:Register("testWheel", frame, "Test", "CENTER", 0, 0)
    Movers:SetUnlocked(true)
    local overlay = Movers.overlays.testWheel
    overlay:GetScript("OnMouseWheel")(overlay, 1)
    eq(Movers:Anchor("testWheel").y, NS.Pixel:Scale(1))
    Mock.shift = true
    overlay:GetScript("OnMouseWheel")(overlay, -1)
    Mock.shift = false
    eq(Movers:Anchor("testWheel").x, NS.Pixel:Scale(-1), "Maj : horizontal")
    Mock.ctrl = true
    overlay:GetScript("OnMouseWheel")(overlay, 1)
    Mock.ctrl = false
    eq(Movers:Anchor("testWheel").y, NS.Pixel:Scale(NS.Pixel:Scale(1) + 10), "Ctrl : 10")
    local panel = Movers:GetCoordsPanel()
    truthy(panel:IsShown(), "case des coordonnées")
    eq(panel.title.text, "Test")
    panel.x:SetText("120")
    panel.y:SetText("-40")
    panel.x:GetScript("OnEnterPressed")(panel.x)
    eq(Movers:Anchor("testWheel").x, NS.Pixel:Scale(120))
    eq(Movers:Anchor("testWheel").y, NS.Pixel:Scale(-40))
    eq(Movers:ApplyCoords("abc", 1), false, "saisie invalide")
    eq(Movers:ApplyCoords("nan", 1), false, "NaN")
    eq(Movers:ApplyCoords(1e6, 1), false, "hors écran")
    eq(panel.y.text, string.format("%.1f", NS.Pixel:Scale(-40)), "une décimale")
    Mock.combat = true
    Movers:Select("testWheel")
    eq(overlay.keyboard, false, "combat : pas de clavier sur le calque")
    Mock.combat = false
    Movers:SetUnlocked(false)
    eq(panel:IsShown(), false)
    Movers:Unregister("testWheel")
    NS.db.anchors.testWheel = nil
end)

test("profil importé : valeurs bornées, couleurs, ancres, réglages sensibles gardés", function()
    reset()
    local range = NS.Database.bounds["modules.cotank.debuffMax"]
    truthy(range, "borne inscrite par le curseur")
    NS.db.modules.automation.repairGuild = false
    NS.db.modules.automation.acceptInvites = false
    eq(NS:ImportProfile("AEON1:modules.cotank.debuffMax=n10000000;theme.fontSize=n-50;"
        .. "theme.accent.r=n99;anchors.x.point=sCENTER;anchors.x.relPoint=sCENTER;anchors.x.x=n1e9;anchors.x.y=n0;"
        .. "modules.automation.repairGuild=b1;modules.automation.acceptInvites=b1"), true)
    eq(NS.db.modules.cotank.debuffMax, range[2], "ramené au maximum du curseur")
    eq(NS.db.theme.fontSize, 9, "ramené au minimum")
    eq(NS.db.theme.accent.r, 1, "couleur entre 0 et 1")
    eq(NS.db.anchors.x, nil, "ancre hors limites retirée")
    eq(NS.db.modules.automation.repairGuild, false, "banque de guilde : réglage du joueur gardé")
    eq(NS.db.modules.automation.acceptInvites, false, "invitations : réglage du joueur gardé")
end)

test("profil importé : point d'ancrage inconnu retiré, annonce au groupe gardée", function()
    reset()
    NS.db.modules.automation.announceReset = false
    eq(NS:ImportProfile("AEON1:anchors.x.point=sFOO;anchors.x.relPoint=sCENTER;anchors.x.x=n0;anchors.x.y=n0;"
        .. "anchors.y.point=sTOP;anchors.y.relPoint=sTOP;anchors.y.x=n0;anchors.y.y=n0;"
        .. "anchors.y.fallback.point=sBAR;anchors.y.fallback.relPoint=sTOP;anchors.y.fallback.x=n0;anchors.y.fallback.y=n0;"
        .. "modules.automation.announceReset=b1"), true)
    eq(NS.db.anchors.x, nil, "point inconnu : ancre retirée")
    eq(NS.db.anchors.y.point, "TOP", "ancre valide gardée")
    eq(NS.db.anchors.y.fallback, nil, "secours au point inconnu retiré")
    eq(NS.db.modules.automation.announceReset, false, "annonce au groupe : réglage du joueur gardé")
end)

test("movers : grille au pas infime (profil importé) ne fige pas le jeu", function()
    reset()
    NS.db.theme.grid = 1e-9
    NS:SetUnlocked(true)   -- sans plancher : ~1e12 tours de boucle
    NS:SetUnlocked(false)
    NS.db.theme.grid = 0
end)
