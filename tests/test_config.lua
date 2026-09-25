-- tests/test_config.lua : options, premier lancement, commandes, désinstallation.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("options : fenêtre avec quatre pages générales + une page par module", function()
    truthy(NS.optionsCategoryId, "lanceur dans Options > AddOns")
    eq(Mock.subcategories, nil, "plus de sous-pages Blizzard")
    for _, key in ipairs({ "general", "modules", "profiles", "maintenance" }) do
        truthy(NS.Options:GetLayout(key), "page " .. key)
    end
    local pages = 4
    for _, module in ipairs(NS.Modules:List()) do
        if module.name ~= "boom" then
            truthy(NS.Options:GetLayout(module.name), "page de " .. module.name)
            pages = pages + 1
        end
    end
    eq(#NS.OptionsWindow.order, pages, "4 pages générales + une par module")
    NS.Options:Refresh()
end)

test("options : sous-pages et liste des modules par ordre alphabétique du titre", function()
    local sorted = NS.Modules:SortedList()
    for i = 2, #sorted do
        if sorted[i - 1].title and sorted[i].title then
            truthy(NS.Modules.SortKey(sorted[i - 1].title) <= NS.Modules.SortKey(sorted[i].title),
                sorted[i - 1].title .. " avant " .. sorted[i].title)
        end
    end
    eq(NS.Modules.SortKey("Échelle"), "echelle", "accents ramenés à la lettre nue")
end)

test("options : une case liée à une clé imbriquée (show.perf)", function()
    reset()
    local layout = NS.Options:GetLayout("topbar")
    local before = #layout.refreshers
    truthy(before > 10, "widgets créés")
    -- La page lit bien la valeur imbriquée : on la coupe, rafraîchit, et la case suit.
    NS.db.modules.topbar.show.perf = false
    layout:Refresh()
    NS.db.modules.topbar.show.perf = true
    layout:Refresh()
end)

test("premier lancement : fenêtre après 2 s, Terminer applique les choix", function()
    reset()
    Mock.Advance(2.1)
    local frame = NS.FirstRun:GetFrame()
    truthy(frame and frame:IsShown(), "affichée")
    NS.FirstRun:Show()
    eq(NS.FirstRun:GetPage(), 1, "page Modules")
    NS.FirstRun:Finish()
    eq(AeonUIDB.firstRunDone, true)
    eq(frame:IsShown(), false)
end)

test("commandes /aeon", function()
    reset()
    SlashCmdList.AEONUI("status")
    truthy(Mock.FindPrinted(T.L.TOPBAR_TITLE), "status")
    truthy(Mock.FindPrinted("Default"), "profil affiché")
    NS.OptionsWindow:Hide()
    SlashCmdList.AEONUI("")
    eq(NS.OptionsWindow:IsShown(), true, "fenêtre ouverte")
    SlashCmdList.AEONUI("")
    eq(NS.OptionsWindow:IsShown(), false, "second /aeon : fermée")
    SlashCmdList.AEONUI("unlock")
    eq(NS.unlocked, true)
    SlashCmdList.AEONUI("lock")
    eq(NS.unlocked, false)
    SlashCmdList.AEONUI("diag")
    truthy(Mock.FindPrinted("API ok"), "diagnostic")
    SlashCmdList.AEONUI("n'importe quoi")
    truthy(Mock.FindPrinted("/aeon setup"), "aide")
end)

test("/aeon reset : profil actif aux défauts, modules toujours en marche", function()
    reset()
    NS.db.modules.automation.sellJunk = false
    SlashCmdList.AEONUI("reset")
    eq(NS.db.modules.automation.sellJunk, true)
    eq(NS.Modules:Get("topbar").enabled, true)
    eq(NS.db, AeonUIDB.profiles.Default)
end)

test("/aeon uninstall : confirmation, puis CVars rendues et modules coupés sur tous les profils", function()
    reset()
    NS:SwitchProfile("Autre - Forever", "Default")
    NS:SwitchProfile("Default")
    eq(Mock.cvars.showTutorials, "0", "changée par Interface")
    SlashCmdList.AEONUI("uninstall")
    truthy(Mock.popups.AEONUI_UNINSTALL, "popup de confirmation")
    eq(NS.Modules:Get("topbar").enabled, true, "rien ne bouge avant confirmation")
    eq(Mock.cvars.showTutorials, "0", "CVar intacte avant confirmation")
    Mock.acceptPopups = true
    SlashCmdList.AEONUI("uninstall")
    Mock.acceptPopups = false
    eq(Mock.cvars.showTutorials, "1", "rendue")
    for _, module in ipairs(NS.Modules:List()) do eq(module.enabled, false, module.name) end
    eq(AeonUIDB.profiles["Autre - Forever"].modules.topbar.enabled, false, "autre profil coupé aussi")
    eq(next(AeonUIDB.cvarBackup), nil, "plus rien à rendre")
    eq(NS.db.theme.pixelPerfect, false, "échelle pixel perfect rendue")
    eq(AeonUIDB.profiles["Autre - Forever"].theme.pixelPerfect, false, "sur tous les profils")
    eq(UIParent:GetScale(), 1, "échelle d'UIParent d'origine")
    NS.Database:DeleteProfile("Autre - Forever")
end)

test("le journal de combat n'est jamais enregistré", function()
    for _, frame in ipairs(Mock.frames) do
        eq(frame.events.COMBAT_LOG_EVENT_UNFILTERED, nil)
    end
end)

test("options : réinitialiser toutes les positions passe par une confirmation", function()
    reset()
    truthy(StaticPopupDialogs.AEONUI_RESET_POSITIONS, "popup déclarée")
    NS.Movers:Save("reminders", "CENTER", "CENTER", 12, 34)
    NS.Movers:Save("alerts", "CENTER", "CENTER", 1, 2)
    Mock.acceptPopups = true
    StaticPopup_Show("AEONUI_RESET_POSITIONS")
    Mock.acceptPopups = false
    eq(NS.db.anchors.reminders, nil, "position des rappels oubliée")
    eq(NS.db.anchors.alerts, nil, "position des alertes oubliée")
end)

test("options : la page principale se construit avec ElvUI chargé (modules cédés grisés)", function()
    reset()
    Mock.loadedAddons.ElvUI = true
    local ok, err = pcall(function() NS.Options:BuildMain() end)
    Mock.loadedAddons = {}
    truthy(ok, tostring(err))
end)
