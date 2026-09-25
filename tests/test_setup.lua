-- tests/test_setup.lua : zone de texte, assistant d'installation, dispositions, CVars
-- recommandées, export/import de profil, désinstallation automatique, compartiment.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("zone de texte : la saisie remonte au setter, Refresh ne le redéclenche pas", function()
    reset()
    local holder = { value = "" }
    local calls = 0
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400)
    local box = layout:EditBox("Test", function() return holder.value end,
        function(v) holder.value = v; calls = calls + 1 end, 3)
    box:Type("bonjour")
    eq(holder.value, "bonjour")
    eq(calls, 1)
    holder.value = "autre"
    layout:Refresh()
    eq(box:GetText(), "autre", "repeint depuis le getter")
    eq(calls, 1, "Refresh ne rappelle pas le setter")
end)

test("assistant : cinq pages, Précédent/Suivant bornés, une seule page visible", function()
    reset()
    NS.FirstRun:Show()
    local frame = NS.FirstRun:GetFrame()
    eq(NS.FirstRun:GetPage(), 1)
    eq(frame.previous:IsEnabled(), false, "Précédent grisé en page 1")
    eq(frame.next:IsEnabled(), true)
    frame.next:Click()
    frame.next:Click()
    frame.next:Click()
    frame.next:Click()
    eq(NS.FirstRun:GetPage(), 5)
    eq(frame.next:IsEnabled(), false, "Suivant grisé en page 5")
    frame.next:Click()
    eq(NS.FirstRun:GetPage(), 5, "borné")
    frame.previous:Click()
    eq(NS.FirstRun:GetPage(), 4)
    truthy(frame.progress:GetText():find("4"), "compteur")
    NS.FirstRun:SetPage(0)
    eq(NS.FirstRun:GetPage(), 4, "index hors bornes ignoré")
    NS.FirstRun:Finish()
end)

test("assistant : bouton Léger, confort seulement, cadres Blizzard conservés", function()
    local L = T.L
    reset()
    NS.FirstRun:Show()
    local light
    for _, frame in ipairs(Mock.frames) do
        if frame.GetText and frame:GetText() == L.INSTALL_PRESET_LIGHT and frame.Click then light = frame end
    end
    truthy(light, "bouton Léger en page 1")
    light:Click()
    eq(NS.db.modules.unitframes.enabled, false, "cadres d'unité AeonUI coupés")
    eq(NS.db.modules.groupframes.enabled, false)
    eq(NS.db.modules.actionbars.enabled, false)
    eq(NS.db.modules.frames.enabled, true, "habillage des cadres Blizzard")
    NS.FirstRun:Finish()
    eq(NS.Modules:Get("unitframes").enabled, false, "Terminer ne rallume rien")
    NS.Modules:SetEnabled("frames", false)
end)

test("assistant : la page Modules applique les choix à Terminer", function()
    reset()
    NS.FirstRun:Show()
    NS.Modules:SetEnabled("cursor", false)
    NS.FirstRun:Show()
    -- On coche « curseur » via la case de la page 1 : le layout de la première colonne.
    local page = NS.FirstRun:GetFrame()
    truthy(page, "cadre")
    NS.db.modules.cursor.enabled = false
    NS.FirstRun:Finish()
    eq(NS.Modules:Get("cursor").enabled, false, "choix conservé = coupé")
    eq(AeonUIDB.firstRunDone, true)
end)

test("disposition Edit Mode : import idempotent, refus au-delà de 5, export", function()
    reset()
    local ok = NS.ImportEditModeLayout("BLOB", "AeonUI")
    eq(ok, true)
    local list = Mock.editMode.layouts.layouts
    eq(#list, 1)
    eq(list[1].layoutName, "AeonUI")
    eq(list[1].layoutType, 0, "compte entier")
    eq(Mock.editMode.added[1], 3, "index = prédéfinies + position")
    eq(Mock.editMode.layouts.activeLayout, 3, "activée")
    NS.ImportEditModeLayout("BLOB2", "AeonUI")
    eq(#list, 1, "ré-import remplace l'homonyme")
    eq(list[1].blob, "BLOB2")
    -- Export de l'active.
    eq(NS.ExportEditModeLayout(), "BLOB2")
    Mock.editMode.layouts.activeLayout = 1
    eq(NS.ExportEditModeLayout(), nil, "prédéfinie : rien à exporter")
    -- Chaîne invalide.
    local bad, reason = NS.ImportEditModeLayout("cassé", "Autre")
    eq(bad, false)
    eq(reason, "invalid")
    -- Plafond.
    for i = 1, 4 do list[#list + 1] = { layoutName = "L" .. i, blob = "x" } end
    local full, why = NS.ImportEditModeLayout("BLOB", "Encore")
    eq(full, false)
    eq(why, "full")
end)

test("disposition Cooldown Manager : import active la première, export sondé", function()
    reset()
    eq(NS.CanExportCooldownLayout(), true)
    Mock.cooldownLayouts.active = 3   -- disposition perso active : exportable
    eq(NS.ExportCooldownLayout(), "CDM-BLOB")
    local ok = NS.ImportCooldownLayout("CDM-IMPORT")
    eq(ok, true)
    eq(Mock.cooldownLayouts.created[1], "CDM-IMPORT")
    eq(Mock.cooldownLayouts.active, 1)
    eq(Mock.cooldownLayouts.saved, 1)
    local bad, reason = NS.ImportCooldownLayout("cassé")
    eq(bad, false)
    eq(reason, "invalid")
end)

test("assistant : la CVar du Cooldown Manager et les CVars recommandées sont réversibles", function()
    reset()
    NS.FirstRun:Show()
    NS.FirstRun:SetPage(4)
    local cdm
    for _, frame in ipairs(Mock.frames) do
        -- case > contenu > ScrollFrame de page > fenêtre
        local scroll = frame.parent and frame.parent.parent
        if frame.frameType == "CheckButton" and scroll and scroll.parent == NS.FirstRun:GetFrame()
                and _G[frame:GetName() .. "Text"].text == T.L.SETUP_CDM_ENABLE then cdm = frame end
    end
    truthy(cdm, "case Cooldown Manager")
    cdm:SetChecked(true)
    cdm.scripts.OnClick(cdm)
    eq(Mock.cvars.cooldownViewerEnabled, "1")
    eq(AeonUIDB.cvarBackup.cooldownViewerEnabled, "0", "origine gardée")
    cdm:SetChecked(false)
    cdm.scripts.OnClick(cdm)
    eq(Mock.cvars.cooldownViewerEnabled, "0", "rendue")
    eq(AeonUIDB.cvarBackup.cooldownViewerEnabled, nil)
    -- Page 5 : toutes appliquées puis rendues.
    NS.FirstRun:SetPage(5)
    for _, entry in ipairs(NS.FirstRun.RECOMMENDED_CVARS) do
        truthy(NS.Modules:Get("interface").CVAR_RULES[entry.name] == nil, entry.name .. " déjà gérée par Interface")
        NS.CVars:Set(entry.name, entry.value)
        eq(Mock.cvars[entry.name], entry.value, entry.name)
        NS.CVars:Restore(entry.name)
    end
    eq(Mock.cvars.nameplateMaxDistance, "40", "rendue")
    NS.FirstRun:Finish()
end)

test("profil : aller-retour export/import à l'identique, une ligne, préfixe", function()
    reset()
    local db = NS.db
    db.theme.fontSize = 13.5
    db.theme.font = "Fonts\\FRIZQT__.TTF"
    db.modules.topbar.show.perf = false
    db.modules.interface.hideProcClasses.WARRIOR = true
    db.modules.groupfinder.note = "tank; exp=ok. 100%"
    db.anchors["clé.piégée=x"] = { point = "TOP", x = -12.5 }
    local text = NS.Database.Serialize(db)
    truthy(text:match("^AEON1:"), "préfixe")
    eq(text:find("\n"), nil, "une ligne")
    truthy(not text:find("[%c]"), "imprimable")
    local back, reason = NS.Database.Deserialize(text)
    truthy(back, tostring(reason))
    eq(back.theme.fontSize, 13.5)
    eq(back.theme.font, "Fonts\\FRIZQT__.TTF")
    eq(back.modules.topbar.show.perf, false)
    eq(back.modules.interface.hideProcClasses.WARRIOR, true)
    eq(back.modules.groupfinder.note, "tank; exp=ok. 100%")
    eq(back.anchors["clé.piégée=x"].point, "TOP")
    eq(back.anchors["clé.piégée=x"].x, -12.5)
    db.anchors["clé.piégée=x"] = nil
end)

test("profil : chaîne invalide refusée sans toucher le profil, clés absentes = défauts", function()
    reset()
    local before = NS.db
    eq(NS:ImportProfile("n'importe quoi"), false)
    truthy(Mock.FindPrinted(T.L.MSG_IMPORT_FAILED), "message")
    eq(NS.db, before, "profil intact")
    local bad, reason = NS.Database.Deserialize("AEON1:cassé")
    eq(bad, nil)
    eq(reason, "parse")
    -- Import d'une chaîne partielle : un module coupé, tout le reste par défaut.
    NS.db.modules.automation.skipCinematics = true
    NS.db.modules.automation.sellJunk = false
    eq(NS:ImportProfile("AEON1:modules.cursor.enabled=b0;modules.automation.quickLoot=b0;modules.automation.repair=b0"), true)
    eq(NS.db.modules.automation.quickLoot, false, "valeur importée")
    eq(NS.db.modules.automation.skipCinematics, false, "clé absente = défaut")
    eq(NS.db.modules.automation.repair, true, "réglage sensible : le sien gardé")
    eq(NS.db.modules.automation.sellJunk, false, "réglage sensible absent : le sien gardé")
    eq(NS.Modules:Get("cursor").enabled, false, "module rebranché coupé")
    eq(NS.Modules:Get("topbar").enabled, true, "module rebranché actif")
    eq(NS.db, AeonUIDB.profiles.Default, "profil actif remplacé")
end)

test("déconnexion : addon désactivé => CVars rendues et modules coupés ; actif => rien", function()
    reset()
    NS.Modules:SetEnabled("interface", true)
    eq(Mock.cvars.showTutorials, "0", "changée par Interface")
    Mock.addonEnableState = 2
    Mock.FireEvent("PLAYER_LOGOUT")
    eq(Mock.cvars.showTutorials, "0", "addon actif : rien ne bouge")
    Mock.addonEnableState = 0
    Mock.FireEvent("PLAYER_LOGOUT")
    eq(Mock.cvars.showTutorials, "1", "rendue")
    for _, module in ipairs(NS.Modules:List()) do eq(module.enabled, false, module.name) end
    eq(Mock.FindPrinted(T.L.MSG_UNINSTALLED), nil, "silencieux")
    -- Remise en marche pour la suite.
    for _, name in ipairs({ "topbar", "automation", "reminders", "alerts", "nameplates", "gear", "skin", "interface" }) do
        NS.Modules:SetEnabled(name, true)
    end
end)

test("déconnexion : sans ordre d'arguments reconnu au login, l'interrupteur reste désarmé", function()
    reset()
    -- Rejouer le login avec un GetAddOnEnableState muet, puis avec l'ordre inversé.
    Mock.addonArgOrder = 0
    Mock.FireEvent("PLAYER_LOGIN")
    Mock.addonEnableState = 0
    Mock.FireEvent("PLAYER_LOGOUT")
    eq(NS.Modules:Get("interface").enabled, true, "rien sans sondage concluant")
    Mock.addonEnableState, Mock.addonArgOrder = 2, 2
    Mock.FireEvent("PLAYER_LOGIN")
    Mock.addonEnableState = 0
    Mock.FireEvent("PLAYER_LOGOUT")
    eq(NS.Modules:Get("interface").enabled, false, "ordre inversé reconnu")
    Mock.addonEnableState, Mock.addonArgOrder = 2, 1
    Mock.FireEvent("PLAYER_LOGIN")
    NS.Modules:SetEnabled("interface", true)
    C_AddOns.DisableAddOn("AeonUI")
    truthy(Mock.FindPrinted(T.L.MSG_WILL_RESTORE), "prévenu")
end)

test("compartiment d'addons : clic gauche = options, clic droit = déverrouiller", function()
    reset()
    NS.OptionsWindow:Hide()
    AeonUI_AddonCompartmentFunc(nil, "LeftButton")
    eq(NS.OptionsWindow:IsShown(), true, "fenêtre d'options")
    NS.OptionsWindow:Hide()
    AeonUI_AddonCompartmentFunc(nil, "RightButton")
    eq(NS.unlocked, true)
    AeonUI_AddonCompartmentFunc(nil, "RightButton")
    eq(NS.unlocked, false)
end)

test("profil : chaîne hostile (scalaire à la place d'une table, chemin vide) refusée ou assainie", function()
    reset()
    local bad, reason = NS.Database.Deserialize("AEON1:.=b1")
    eq(bad, nil)
    eq(reason, "parse")
    eq(NS:ImportProfile("AEON1:modules.topbar=sfoo;anchors.cotank=sx;modules.cursor.enabled=b1"), true)
    eq(type(NS.db.modules.topbar), "table", "module remis en table")
    eq(NS.db.modules.topbar.enabled, true, "défauts posés")
    eq(NS.db.anchors.cotank, nil, "ancre invalide écartée")
    eq(NS.Modules:Get("cursor").enabled, true)
    NS.Modules:SetEnabled("cursor", false)
end)

test("profil : scalaire mal typé et ancrage incomplet remis aux défauts, sans erreur", function()
    reset()
    eq(NS:ImportProfile("AEON1:theme.fontSize=sabc;theme.accent.r=sboom;anchors.reminders.point=sTOP;anchors.reminders.x=szzz"), true)
    eq(NS.db.theme.fontSize, NS.Database.PROFILE_DEFAULTS.theme.fontSize, "chaîne à la place d'un nombre : défaut")
    eq(NS.db.theme.accent.r, NS.Database.PROFILE_DEFAULTS.theme.accent.r)
    eq(NS.db.anchors.reminders, nil, "ancrage sans relPoint/x/y numériques : écarté")
    NS.Options:Refresh()   -- Widgets:Refresh divisait fontSize : ne doit plus lever
end)

test("profil : clés numériques exportées, | et # échappés et rendus", function()
    local text = NS.Database.Serialize({ list = { "a", "b" }, note = "|cffff0000rouge|r", map = { x = 1 } })
    eq(text, "AEON1:list.#1=sa;list.#2=sb;map.x=n1;note=s%7Ccffff0000rouge%7Cr")
    eq(NS.Database.Deserialize(text).note, "|cffff0000rouge|r")
    eq(NS.Database.Deserialize(text).list[2], "b")
    -- Clé chaîne "#1" : échappée, jamais confondue avec l'index 1.
    local hashed = NS.Database.Deserialize(NS.Database.Serialize({ t = { ["#1"] = "s", [1] = "n" } }))
    eq(hashed.t["#1"], "s")
    eq(hashed.t[1], "n")
    -- `"` et `\` : le miroir CVar vit entre guillemets dans config-cache.wtf.
    local quoted = NS.Database.Serialize({ note = 'dit "heal" \\ ok' })
    eq(quoted, "AEON1:note=sdit %22heal%22 %5C ok")
    eq(NS.Database.Deserialize(quoted).note, 'dit "heal" \\ ok')
end)

test("déconnexion en combat : les CVars sont rendues tout de suite", function()
    reset()
    NS.Modules:SetEnabled("interface", true)
    eq(Mock.cvars.showTutorials, "0")
    Mock.SetCombat(true)
    Mock.addonEnableState = 0
    Mock.FireEvent("PLAYER_LOGOUT")
    eq(Mock.cvars.showTutorials, "1", "rendue malgré le combat")
    eq(next(AeonUIDB.cvarBackup), nil)
    Mock.SetCombat(false)
    for _, name in ipairs({ "topbar", "automation", "reminders", "alerts", "nameplates", "gear", "skin", "interface" }) do
        NS.Modules:SetEnabled(name, true)
    end
end)

test("assistant : fermé par Échap (sans Terminer), il ne revient pas au prochain login", function()
    reset()
    AeonUIDB.firstRunDone = false
    NS.FirstRun:Show()
    NS.FirstRun:GetFrame():Hide()
    eq(AeonUIDB.firstRunDone, true)
end)

test("assistant : Terminer ne touche pas au réglage d'un module cédé à ElvUI", function()
    reset()
    NS.db.modules.skin.enabled = true
    Mock.loadedAddons.ElvUI = true
    NS.Modules:DisableAll()
    NS.Modules:EnableAll()
    NS.FirstRun:Show()
    NS.FirstRun:Finish()
    eq(NS.db.modules.skin.enabled, true, "réglage conservé malgré la case décochée")
    eq(NS.Modules:Get("skin").enabled, false, "toujours cédé")
    Mock.loadedAddons = {}
    NS.Modules:DisableAll()
    NS.Modules:EnableAll()
    eq(NS.Modules:Get("skin").enabled, true)
end)

test("preset Edit Mode livré : non vide, format v3, importable par l'assistant", function()
    reset()
    local preset = NS.PRESET_LAYOUTS.editMode
    truthy(#preset > 2000, "chaîne capturée en jeu")
    truthy(preset:match("^3 59 "), "format v3, 59 systèmes")
    truthy(NS.ImportEditModeLayout(preset, "AeonUI"), "import accepté")
    local list = Mock.editMode.layouts.layouts
    eq(list[#list].layoutName, "AeonUI")
end)

test("export Cooldown Manager : nil + default sur une disposition Blizzard, chaîne sinon", function()
    reset()
    Mock.cooldownLayouts.active = nil
    local text, reason = NS.ExportCooldownLayout()
    eq(text, nil); eq(reason, "default")
    Mock.cooldownLayouts.active = 7
    eq(NS.ExportCooldownLayout(), "CDM-BLOB")
end)

test("zone de texte multi-lignes : dans un ScrollFrame, une ligne : directe", function()
    reset()
    local layout = NS.Widgets.NewLayout(CreateFrame("Frame"), 0, 400)
    local multi = layout:EditBox("Multi", function() return "" end, function() end, 10)
    eq(multi.parent.frameType, "ScrollFrame", "multi-lignes défilable")
    local single = layout:EditBox("Une", function() return "" end, function() end, 1)
    eq(single.parent.frameType, "Frame", "une ligne : pas de ScrollFrame")
end)
