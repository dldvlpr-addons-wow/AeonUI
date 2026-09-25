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
    eq(NS.db.anchors.uf_party.point, "CENTER", "soigneur : groupe sous le personnage")
    eq(NS.db.anchors.cdm_essential.y, -120, "soigneur : recharges sous le personnage")
    eq(NS.db.anchors.buffs.x, -230, "ancrage du préréglage gardé quand le rôle ne le couvre pas")
    truthy(NS.Modules:Get("blizzardframes").enabled)
    eq(NS.db.modules.groupframes.healthText, "percent")
    eq(NS.db.modules.groupframes.spacing, 4, "clé non couverte par le rôle : inchangée")
    eq(Mock.cvars.nameplateMaxDistance, "60")
    eq(NS.global.firstRunDone, true)
    truthy(Mock.FindPrinted("Install"))
    truthy(NS.Install:ApplyPreset("light"))
    for _, name in ipairs(NS.Install.NEW_MODULES) do
        eq(NS.Modules:Get(name).enabled, false, name .. " coupé")
    end
    eq(NS.Modules:Get("frames").enabled, true)
end)

test("installation : rôle tank allume le co-tank ; module cédé à ElvUI : réglage gardé, pas allumé", function()
    reset()
    NS.Install:ApplyPreset("complete", "tank")
    eq(NS.Modules:Get("cotank").enabled, true)
    eq(NS.db.modules.groupframes.aggro, true)
    eq(NS.db.anchors.cotank.x, -560)
    eq(NS.db.anchors.uf_party.point, "TOPLEFT", "tank : groupe en colonne à gauche")
    eq(NS.db.modules.unitframes.units.player.castbarDetached, true, "tank : barre d'incantation détachée")
    eq(NS.db.anchors.uf_castbar_player.y, -260)
    NS.Install:ApplyPreset("light")
    Mock.loadedAddons.ElvUI = true
    NS.Install:ApplyPreset("complete")
    eq(NS.db.modules.unitframes.enabled, true, "réglage mémorisé")
    eq(NS.Modules:Get("unitframes").enabled, false, "cédé : pas allumé")
    eq(NS.Modules:Get("actionbars").enabled, false, "cédé aussi (ElvUI)")
    Mock.loadedAddons.ElvUI = nil
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
    eq(NS.db.modules.groupframes.width, 72)
    eq(NS.db.modules.groupframes.horizontal, true)
    eq(NS.db.modules.unitframes.units.player.castbarDetached, false, "soigneur : barre sous le cadre du joueur")
    eq(NS.db.anchors.uf_raid.point, "CENTER", "raid en grille sous les recharges")
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

test("installation : chat à la ElvUI, ForeverMeter, KickAlert, DBM et BigWigs posés ; DBM reposé à la connexion", function()
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
