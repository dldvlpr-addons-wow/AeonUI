-- tests/test_install.lua : installation un clic v2 et préréglages de rôle (étapes 7 et 8).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("installation : préréglage complet allume les modules AeonUI, pose les ancrages, les CVars, le rôle", function()
    reset()
    truthy(NS.Install:ApplyPreset("complete", "heal"))
    for _, name in ipairs(NS.Install.NEW_MODULES) do
        truthy(NS.Modules:Get(name).enabled, name .. " allumé")
    end
    eq(NS.Modules:Get("frames").enabled, false, "retouches Blizzard coupées : redondantes")
    eq(NS.db.anchors.uf_player.point, "CENTER")
    eq(NS.db.anchors.uf_player.x, -520, "soigneur : joueur écarté du centre")
    local _, _, _, x = NS.Modules:Get("unitframes"):GetFrame("player"):GetPoint()
    eq(x, -520, "cadre posé sur l'ancrage du rôle")
    eq(NS.db.modules.groupframes.power, true, "rôle soigneur : puissance sur les cadres de groupe")
    eq(NS.db.modules.groupframes.horizontal, true, "soigneur : groupe en ligne")
    eq(NS.db.anchors.uf_party.relPoint, "CENTER", "soigneur : groupe sous le personnage")
    eq(NS.db.anchors.uf_party.point, "TOP", "haut du groupe gardé")
    eq(NS.db.anchors.cdm_essential.y, -120, "soigneur : recharges sous le personnage")
    eq(NS.db.anchors.buffs.x, -230, "ancrage du préréglage gardé quand le rôle ne le couvre pas")
    truthy(NS.Modules:Get("blizzardframes").enabled)
    eq(NS.db.modules.groupframes.healthText, "percent")
    eq(NS.db.modules.groupframes.spacing, 3, "clé non couverte par le rôle : inchangée")
    eq(Mock.cvars.nameplateMaxDistance, "60")
    eq(NS.global.firstRunDone, true)
    truthy(Mock.FindPrinted("Install"))
    truthy(NS.Install:ApplyPreset("light"))
    for _, name in ipairs(NS.Install.NEW_MODULES) do
        eq(NS.Modules:Get(name).enabled, false, name .. " coupé")
    end
    eq(NS.Modules:Get("frames").enabled, true)
end)

test("installation : rôle tank allume le co-tank ; module cédé à un addon tiers : réglage gardé, pas allumé", function()
    reset()
    NS.Install:ApplyPreset("complete", "tank")
    eq(NS.Modules:Get("cotank").enabled, true)
    eq(NS.db.modules.groupframes.aggro, true)
    eq(NS.db.anchors.cotank.x, -560)
    eq(NS.db.anchors.uf_party.point, "TOPLEFT", "tank : groupe en colonne à gauche")
    eq(NS.db.modules.unitframes.units.player.castbarDetached, true, "tank : barre d'incantation détachée")
    eq(NS.db.anchors.uf_castbar_player.y, -260)
    NS.Install:ApplyPreset("light")
    Mock.loadedAddons.Bartender4 = true
    NS.Install:ApplyPreset("complete")
    eq(NS.db.modules.actionbars.enabled, true, "réglage mémorisé")
    eq(NS.Modules:Get("actionbars").enabled, false, "cédé : pas allumé")
    Mock.loadedAddons.Bartender4 = nil
    NS.Install:ApplyPreset("light")
end)

test("installation : /aeon install avec arguments, usage sur argument inconnu", function()
    reset()
    SlashCmdList.AEONUI("install complete dps")
    truthy(NS.Modules:Get("unitframes").enabled)
    eq(NS.db.modules.groupframes.power, false, "rôle DPS")
    SlashCmdList.AEONUI("install nimportequoi")
    truthy(Mock.FindPrinted("Usage"))
    SlashCmdList.AEONUI("install light")
    eq(NS.Modules:Get("unitframes").enabled, false)
end)

test("profils de base : /aeon install heal bascule sur « Soigneur », Default intact ; dps et tank pareil", function()
    reset()
    local before = NS.db.modules.groupframes.width
    SlashCmdList.AEONUI("install heal")
    eq(NS.Database:ActiveProfileName(), NS.Install.ProfileName("heal"))
    eq(NS.db.modules.groupframes.width, 110)
    eq(NS.db.modules.groupframes.horizontal, true)
    eq(NS.db.modules.unitframes.units.player.castbarDetached, false, "soigneur : barre sous le cadre du joueur")
    eq(NS.db.anchors.uf_raid.relPoint, "CENTER", "raid en grille sous les recharges")
    eq(NS.db.anchors.uf_raid.grow, "TOP", "haut du raid gardé de 10 à 40")
    truthy(NS.Modules:Get("unitframes").enabled, "interface complète allumée")
    truthy(NS.Install:Apply("dps"))
    eq(NS.Database:ActiveProfileName(), NS.Install.ProfileName("dps"))
    eq(NS.db.modules.groupframes.power, false)
    eq(NS.db.anchors.uf_player.x, -330, "dégâts : disposition de base")
    truthy(NS.Install:Apply("tank"))
    eq(NS.Database:ActiveProfileName(), NS.Install.ProfileName("tank"))
    eq(NS.Modules:Get("cotank").enabled, true)
    eq(NS.Install:Apply("nimportequoi"), false)
    NS:SwitchProfile(NS.Database.DEFAULT_PROFILE)
    eq(NS.db.modules.groupframes.width, before, "Default inchangé")
    eq(#NS.Database:ListProfiles(), 4, "Default + trois profils de base")
    for _, role in ipairs({ "heal", "dps", "tank" }) do NS.Database:DeleteProfile(NS.Install.ProfileName(role)) end
end)

test("installation : chat réorganisé, ForeverMeter, KickAlert, DBM et BigWigs posés ; DBM reposé à la connexion", function()
    reset()
    local calls = {}
    local right = CreateFrame("Frame", "ChatFrame4", UIParent)
    right.GetID = function() return 4 end
    _G.FCF_ResetChatWindows = function() calls.reset = true end
    _G.FCF_OpenNewWindow = function(name) calls.name = name return right end
    _G.FCF_UnDockFrame = function(frame) calls.undocked = frame end
    _G.ChatFrame_RemoveAllMessageGroups = function() end
    _G.ChatFrame_AddMessageGroup = function(frame, group) calls[group .. tostring(frame == right)] = true end
    _G.ChatFrame_AddChannel = function(frame, channel) calls[channel] = frame end
    _G.ChatFrame_RemoveChannel = function() end
    _G.GENERAL, _G.TRADE, _G.LOOT = "Général", "Commerce", "Butin"
    _G.ForeverMeterDB = { windows = { { point = { "CENTER", nil, "CENTER", 300, 0 }, anchor = { to = 2 } } } }
    CreateFrame("Frame", "ForeverMeterFrame", UIParent)
    _G.KickAlertDB = { anchors = {} }
    CreateFrame("Frame", "KickAlertText", UIParent)
    local rearranged, repositioned = false, false
    _G.DBM = { Options = {}, RepositionFrames = function() repositioned = true end }
    _G.DBT = { Options = {}, Rearrange = function() rearranged = true end }
    local sent
    -- GetPlugin rend une copie réduite ({ db }) : message envoyé par le cœur.
    local barsPlugin, messagesPlugin = { db = { profile = {} } }, { db = { profile = {} } }
    _G.BigWigs = {
        GetPlugin = function(_, name) return ({ Bars = barsPlugin, Messages = messagesPlugin })[name] end,
        SendMessage = function(_, message) sent = message end,
    }

    truthy(NS.Install:ApplyPreset("complete", "dps"))
    truthy(calls.reset, "fenêtres remises à zéro")
    eq(calls.name, "Butin / Commerce")
    eq(calls.undocked, right, "chat butin/commerce détaché")
    local point, _, _, x, y = right:GetPoint()
    eq(point, "BOTTOMRIGHT") eq(x, -10) eq(y, 100) eq(right:GetWidth(), 320)
    truthy(calls.LOOTtrue, "butin à droite") truthy(calls.GUILDfalse, "guilde à gauche")
    eq(calls["Commerce"], right) eq(calls["Général"], ChatFrame1)
    eq(ForeverMeterDB.windows[1].point[1], "BOTTOMRIGHT")
    eq(ForeverMeterDB.windows[1].anchor, nil, "détachée des autres fenêtres")
    local _, _, _, meterX = ForeverMeterFrame:GetPoint()
    eq(meterX, -450)
    eq(KickAlertDB.anchors.Text.y, 130, "sous le chrono de combat AeonUI")
    eq(DBM.Options.WarningY, 330) eq(DBT.Options.TimerX, -300)
    truthy(repositioned and rearranged, "DBM replacé tout de suite")
    eq(barsPlugin.db.profile.normalPosition[3], -300) eq(sent, "BigWigs_ProfileUpdate")
    eq(messagesPlugin.db.profile.emphPosition[4], 75, "clé des messages mis en avant : emphPosition")
    truthy(Mock.popups.AEONUI_RELOAD, "rechargement proposé après le chat")
    eq(NS.global.chatSetupDone, true)
    calls.reset = nil
    NS.Install:ApplyPreset("complete", "heal")
    eq(calls.reset, nil, "changement de rôle : onglets du joueur gardés")
    eq(NS.global.addonPlacements, true)

    -- Session suivante : DBM repart de ses défauts, AeonUI le repose à la connexion.
    DBM.Options.WarningY = 260
    Mock.FireEvent("PLAYER_LOGIN")
    eq(DBM.Options.WarningY, 330)

    NS.global.addonPlacements = nil   -- ce que fait /aeon uninstall
    DBM.Options.WarningY = 260
    Mock.FireEvent("PLAYER_LOGIN")
    eq(DBM.Options.WarningY, 260, "désinstallé : plus rien de reposé")

    for _, name in ipairs({ "FCF_ResetChatWindows", "FCF_OpenNewWindow", "FCF_UnDockFrame", "ChatFrame_RemoveAllMessageGroups",
        "ChatFrame_AddMessageGroup", "ChatFrame_AddChannel", "ChatFrame_RemoveChannel", "ForeverMeterDB", "KickAlertDB",
        "DBM", "DBT", "BigWigs" }) do _G[name] = nil end
    NS.global.chatSetupDone, NS.global.addonPlacements = nil, nil
end)

test("assistant : page Style, looks AeonUI, Classic (art vanilla) et Blizzard", function()
    reset()
    local Install = NS.Install
    NS.FirstRun:Show()
    NS.FirstRun:SetPage(3)
    eq(NS.FirstRun:GetPage(), 3, "page Style construite")
    truthy(Install:ApplyStyle("classic"))
    eq(NS.db.theme.font, "Fonts\\FRIZQT__.TTF")
    eq(NS.Media:StatusBarTexture(), "Interface\\TargetingFrame\\UI-StatusBar", "texture de barre vanilla")
    eq(NS.db.modules.unitframes.enabled, true)
    eq(NS.db.modules.skin.skinWindows, false, "fenêtres Blizzard intactes")
    truthy(Install:ApplyStyle("blizzard"))
    eq(NS.db.modules.unitframes.enabled, false, "cadres Blizzard")
    eq(NS.db.theme.font, "Fonts\\FRIZQT__.TTF", "thème inchangé")
    truthy(Install:ApplyStyle("aeon"))
    eq(NS.db.theme.font, NS.Database.PROFILE_DEFAULTS.theme.font, "thème par défaut")
    eq(NS.db.theme.statusbar, "")
    eq(NS.db.modules.skin.skinWindows, true)
    eq(Install:ApplyStyle("inconnu"), false)
    Install:ApplyStyle("blizzard")
    NS.db.modules.skin.skinWindows = false
    NS.Modules:Refresh("skin")
    NS.FirstRun:Finish()
end)

test("profils de classe : druide tank, mage lanceur, chasseur distance ; style hors classe refusé", function()
    reset()
    local Install = NS.Install
    Mock.units.player.class = "DRUID"
    eq(table.concat(Install.ClassStyles(), ","), "caster,melee,heal,tank")
    eq(Install:ApplyClass("ranged"), false, "pas de distance pour un druide")
    SlashCmdList.AEONUI("install class tank")
    eq(NS.Database:ActiveProfileName(), Install.ClassProfileName("tank"))
    eq(NS.Modules:Get("cotank").enabled, true, "rôle tank posé")
    eq(NS.db.modules.reminders.expectedStance, "bear", "classe : forme d'ours")
    eq(NS.db.modules.resourcebars.health, true, "style tank : vie sous le personnage")
    eq(NS.db.modules.resourcebars.druidMana, true)
    eq(NS.db.modules.swingtimer.enabled, true)
    eq(NS.db.modules.swingtimer.offHand, false, "classe passe après le style")
    eq(NS.db.modules.nameplateframes.threatRole, "tank")
    eq(NS.db.anchors.resourcePower.y, -242)
    eq(NS.db.anchors.uf_castbar_player.y, -280, "style passe après le rôle")
    NS.db.modules.swingtimer.queueColor.r = 0
    eq(Install.CLASSES.WARRIOR.all.swingtimer.queueColor.r, 1, "tables de profil copiées, pas partagées")
    SlashCmdList.AEONUI("install class ranged")
    truthy(Mock.FindPrinted("caster, melee, heal, tank"), "usage avec les styles de la classe")
    Mock.units.player.class = "MAGE"
    truthy(Install:ApplyClass("caster"))
    eq(NS.Database:ActiveProfileName(), Install.ClassProfileName("caster"))
    eq(NS.Modules:Get("gcdbar").enabled, true)
    eq(NS.db.modules.unitframes.units.player.castbarWidth, 300)
    eq(NS.db.modules.movementalert.enabled, true)
    eq(Install:ApplyClass("heal"), false)
    Mock.units.player.class = "HUNTER"
    truthy(Install:ApplyClass("ranged"))
    eq(NS.db.modules.unitframes.units.pet.width, 160, "familier mis en avant")
    eq(NS.db.modules.swingtimer.ranged, true)
    eq(NS.db.modules.swingtimer.mainHand, false)
    eq(NS.db.anchors.uf_pet.x, -360)
    Mock.units.player.class = "PRIEST"
    truthy(Install:ApplyClass("heal"))
    eq(NS.Modules:Get("clickcast").enabled, true, "soins au clic allumés")
    eq(NS.db.modules.groupframes.horizontal, true, "rôle soigneur posé")
    NS:SwitchProfile(NS.Database.DEFAULT_PROFILE)
    for _, name in ipairs({ "DRUID - Tank", "MAGE - " .. NS.L.INSTALL_ROLE_CASTER, "HUNTER - " .. NS.L.INSTALL_ROLE_RANGED,
                            "PRIEST - " .. NS.L.INSTALL_ROLE_HEAL }) do
        NS.Database:DeleteProfile(name)
    end
    eq(#NS.Database:ListProfiles(), 1, "profils de classe supprimés")
end)

test("profils de classe sur le profil actuel : pas de résidu d'un autre style, liaisons du joueur gardées", function()
    reset()
    local Install = NS.Install
    local origin = NS.Database:ActiveProfileName()
    Mock.units.player.class = "DRUID"
    truthy(Install:ApplyClassSettings("melee"))
    eq(NS.Database:ActiveProfileName(), origin, "profil actuel gardé")
    eq(NS.db.modules.reminders.expectedStance, "cat")
    eq(NS.Modules:Get("swingtimer").enabled, true)
    truthy(Install:ApplyClassSettings("caster"))
    eq(NS.db.modules.reminders.expectedStance, "none", "plus de rappel de félin en lanceur")
    eq(NS.Modules:Get("swingtimer").enabled, false, "coups blancs du style mêlée coupés")
    eq(NS.Modules:Get("resourcebars").enabled, false)
    eq(NS.Modules:Get("gcdbar").enabled, true)
    eq(Install:ApplyClassSettings("ranged"), false)
    Mock.units.player.class = "WARRIOR"
    truthy(Install:ApplyClassSettings("melee"))
    eq(NS.Modules:Get("gcdbar").enabled, false, "profil partagé : rien du druide lanceur ne reste")
    eq(NS.db.modules.unitframes.units.player.castbarWidth, 260)
    Mock.units.player.class = "PRIEST"
    NS.db.modules.groupframes.indicators.TOPLEFT = "Perso"
    truthy(Install:ApplyClassSettings("heal"))
    eq(NS.db.modules.groupframes.indicators.TOPLEFT, "Perso", "coins du joueur gardés")
    eq(NS.Modules:Get("clickcast").enabled, true)
end)

test("assistant : profil de classe déjà là, réinstallé seulement après confirmation, sinon simple bascule", function()
    reset()
    local Install = NS.Install
    Mock.units.player.class = "WARRIOR"
    local origin = NS.Database:ActiveProfileName()
    local name = Install.ClassProfileName("tank")
    local function Click() NS.FirstRun.InstallProfile(name, function() Install:ApplyClass("tank") end) end
    Click()
    eq(NS.Database:ActiveProfileName(), name, "profil neuf : installé sans question")
    NS.db.modules.swingtimer.width = 123
    NS:SwitchProfile(origin)
    Click()
    truthy(Mock.popups.AEONUI_PROFILE_EXISTS, "profil existant : confirmation")
    eq(NS.Database:ActiveProfileName(), origin, "rien avant la réponse")
    StaticPopupDialogs.AEONUI_PROFILE_EXISTS.OnCancel(nil, nil, "override")
    eq(NS.Database:ActiveProfileName(), origin, "popup annulée par le jeu : rien")
    StaticPopupDialogs.AEONUI_PROFILE_EXISTS.OnCancel(nil, nil, "clicked")
    eq(NS.Database:ActiveProfileName(), name, "refus : bascule")
    eq(NS.db.modules.swingtimer.width, 123, "réglages du joueur gardés")
    NS:SwitchProfile(origin)
    Mock.acceptPopups = true
    Click()
    Mock.acceptPopups = false
    eq(NS.db.modules.swingtimer.width, 220, "confirmé : profil réinstallé")
    NS:SwitchProfile(origin)
    NS.Database:DeleteProfile(name)
end)
