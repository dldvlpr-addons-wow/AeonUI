-- tests/test_quality_of_life.lua : dialogue à option unique, tout apprendre, conteneurs, journal de combat,
-- carte du monde, rappel de talents, cadres Blizzard butin et alertes.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Automation = NS.Modules:Get("automation")
local db = function() return NS.db.modules.automation end

test("dialogue : l'unique option est choisie, une fois, sauf Maj / instance / quête / texte forcé", function()
    reset()
    db().autoGossip = true
    Mock.Advance(60)
    Mock.gossip.options = { { gossipOptionID = 55, status = 0 } }
    Mock.shift = true
    Mock.FireEvent("GOSSIP_SHOW")
    eq(#Mock.questLog, 0, "Maj : suspendu")
    Mock.shift = false
    Mock.instanceType = "party"
    Mock.FireEvent("GOSSIP_SHOW")
    eq(#Mock.questLog, 0, "instance : coupé")
    Mock.instanceType = "none"
    Mock.gossip.available = { { questID = 9 } }
    Mock.FireEvent("GOSSIP_SHOW")
    eq(#Mock.questLog, 0, "quête proposée : au joueur")
    Mock.gossip.available = {}
    Mock.gossip.force = true
    Mock.FireEvent("GOSSIP_SHOW")
    eq(#Mock.questLog, 0, "ForceGossip : texte à lire")
    Mock.gossip.force = false
    Mock.gossip.options = { { gossipOptionID = 55 }, { gossipOptionID = 56 } }
    Mock.FireEvent("GOSSIP_SHOW")
    eq(#Mock.questLog, 0, "deux options")
    Mock.gossip.options = { { gossipOptionID = 55, selectOptionWhenOnlyOption = true } }
    Mock.FireEvent("GOSSIP_SHOW")
    eq(#Mock.questLog, 0, "Blizzard la choisit déjà")
    Mock.gossip.options = { { gossipOptionID = 55, status = 0 } }
    Mock.FireEvent("GOSSIP_SHOW")
    Mock.FireEvent("GOSSIP_SHOW")
    eq(table.concat(Mock.questLog, ","), "gossip-option:55", "une seule fois (anti-double)")
    db().autoGossip = false
end)

test("entraîneur : prochain service payable, achats un par TRAINER_UPDATE, budget tenu", function()
    reset()
    Mock.trainer.services = { { type = "used", cost = 1 }, { type = "available", cost = 40 },
        { type = "available", cost = 5, isProfession = true }, { type = "available", cost = 30 },
        { type = "available", cost = 50 } }
    eq(Automation.NextTrainable(100), 2, "saute appris et métier")
    eq(Automation.NextTrainable(35), 4, "saute le trop cher")
    eq(Automation.NextTrainable(10), nil)
    Mock.money = 80
    db().trainAll = true
    Mock.FireEvent("TRAINER_SHOW")
    local button = MuscaUITrainAll
    truthy(button, "bouton créé")
    truthy(button:IsShown(), "visible")
    ClassTrainerTrainButton:Hide()
    eq(button:IsVisible(), false, "caché avec le bouton Blizzard (mode manette)")
    ClassTrainerTrainButton:Show()
    button:GetScript("OnClick")(button)
    eq(table.concat(Mock.trainer.bought, ","), "2", "un achat par clic")
    Mock.FireEvent("TRAINER_UPDATE")
    eq(table.concat(Mock.trainer.bought, ","), "2,4", "suivant à la mise à jour")
    Mock.FireEvent("TRAINER_UPDATE")
    eq(#Mock.trainer.bought, 2, "budget épuisé (80 - 40 - 30 = 10)")
    Mock.trainer.tradeskill = true
    Mock.FireEvent("TRAINER_SHOW")
    eq(button:IsShown(), false, "pas chez un entraîneur de métier")
    Mock.trainer.tradeskill = false
    db().trainAll = false
    Mock.FireEvent("TRAINER_SHOW")
    eq(button:IsShown(), false, "option coupée")
    Mock.money = 100000
end)

test("conteneurs : un par passage, hors combat, pas devant un marchand, anti-double par pile", function()
    reset()
    db().openContainers = true
    if _G.BankFrame then BankFrame:Hide() end   -- laissé ouvert par le test des sacs
    Mock.Advance(60)
    Mock.bags[0][1] = { itemID = 700, quality = 1, hasLoot = true }
    Mock.bags[0][2] = { itemID = 701, quality = 1, hasLoot = true }
    Mock.bags[0][3] = { itemID = 702, quality = 1 }
    Mock.SetCombat(true)
    Mock.FireEvent("BAG_UPDATE_DELAYED"); Mock.Advance(1)
    eq(#Mock.used, 0, "combat")
    Mock.SetCombat(false)
    _G.MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
    MerchantFrame:Show()
    Mock.FireEvent("BAG_UPDATE_DELAYED"); Mock.Advance(1)
    eq(#Mock.used, 0, "marchand ouvert")
    MerchantFrame:Hide()
    Mock.FireEvent("BAG_UPDATE_DELAYED"); Mock.FireEvent("BAG_UPDATE_DELAYED"); Mock.Advance(1)
    eq(#Mock.used, 1, "un seul objet par passage")
    eq(Mock.used[1].slot, 1)
    Mock.FireEvent("BAG_UPDATE_DELAYED"); Mock.Advance(1)
    eq(Mock.used[2] and Mock.used[2].slot, 2, "puis le suivant, pas deux fois le premier")
    Mock.Advance(31)
    Mock.cursorItem = "item"
    Mock.FireEvent("BAG_UPDATE_DELAYED"); Mock.Advance(1)
    eq(#Mock.used, 2, "curseur chargé")
    Mock.cursorItem = nil
    for bag = 0, 4 do for slot = 1, Mock.bagSize do Mock.bags[bag][slot] = Mock.bags[bag][slot] or { itemID = 9, quality = 1 } end end
    Mock.FireEvent("BAG_UPDATE_DELAYED"); Mock.Advance(1)
    eq(#Mock.used, 2, "sacs pleins")
    db().openContainers = false
    _G.MerchantFrame = nil
end)

test("journal de combat : lancé en raid, arrêté à la sortie, jamais coupé s'il était déjà actif", function()
    reset()
    db().logRaid = true
    Mock.instanceType = "raid"
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    eq(Mock.logging, true, "démarré")
    Mock.instanceType = "none"
    Mock.FireEvent("ZONE_CHANGED_NEW_AREA")
    eq(Mock.logging, false, "arrêté")
    Mock.logging = true   -- lancé à la main
    Mock.instanceType = "raid"
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    Mock.instanceType = "none"
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    eq(Mock.logging, true, "journal manuel conservé")
    Mock.logging = false
    Mock.instanceType = "party"
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    eq(Mock.logging, false, "donjon non demandé")
    -- /reload en raid : le drapeau persiste, la sortie arrête quand même le journal
    Mock.instanceType = "raid"
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    eq(db().logStarted, true)
    Mock.instanceType = "none"
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    eq(Mock.logging, false)
    eq(db().logStarted, false)
    -- journal coupé à la main : le drapeau est abandonné
    db().logStarted = true
    Mock.logging = false
    Mock.instanceType = "raid"
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    eq(Mock.logging, true, "relancé")
    Mock.instanceType = "none"
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    db().logRaid = false
end)

test("carte du monde : texte des coordonnées et des niveaux, valeurs hors carte en --", function()
    reset()
    local Interface = NS.Modules:Get("interface")
    Mock.mapLevels[12] = { 10, 20 }
    local text = Interface.MapText({ mapCoords = true, mapLevels = true }, 12, 0.5, 0.25, 0.1, 0.2)
    truthy(text:find("10-20", 1, true), "niveaux")
    truthy(text:find("10.0, 20.0", 1, true), "joueur")
    truthy(text:find("50.0, 25.0", 1, true), "curseur")
    eq(Interface.MapText({ mapCoords = true }, 12, 2, 0.5, nil, nil):find("--", 1, true) ~= nil, true, "hors carte")
    eq(Interface.MapText({ mapLevels = true }, 13, 0, 0), "", "zone sans niveaux")
    NS.db.modules.interface.mapCoords = true
    Mock.mapID, Mock.mapPosition = 12, { 0.3, 0.4 }
    WorldMapFrame:Show()
    NS.Modules:Refresh("interface")
    Mock.Advance(0.2)
    local panel
    for _, child in ipairs({ WorldMapFrame:GetChildren() }) do if child.text and child.text.SetText then panel = child end end
    truthy(panel, "encart créé sur la carte")
    truthy(panel:IsShown(), "option active")
    truthy(panel.text.text and panel.text.text:find("30.0, 40.0", 1, true), "position du joueur affichée")
    NS.db.modules.interface.mapCoords = false
    NS.Modules:Refresh("interface")
    eq(panel:IsShown(), false, "option coupée")
    WorldMapFrame:Hide()
    Mock.mapID, Mock.mapPosition = nil, nil
end)

test("rappel : points de talent non dépensés", function()
    reset()
    local Reminders = NS.Modules:Get("reminders")
    local function Talents()
        for _, entry in ipairs(Reminders:Collect()) do if entry.key == "talents" then return entry.text end end
    end
    eq(Talents(), nil, "aucun point")
    NS.db.modules.reminders.talents = true
    eq(Talents(), nil, "aucun point")
    Mock.talentPoints = { 1, 2 }
    eq(Talents(), "3 unspent talent point(s)")
    NS.db.modules.reminders.talents = false
    eq(Talents(), nil, "option coupée")
    NS.db.modules.reminders.talents = false
end)

test("cadres Blizzard : alertes adoptées, fenêtre de butin « keep » d'office et jamais sous la souris", function()
    reset()
    NS.Modules:SetEnabled("blizzardframes", true)
    local _, relTo = AlertFrame:GetPoint()
    eq(relTo, MuscaUI_Holder_toasts, "toasts sur leur support")
    eq(MuscaUI_Holder_toasts:GetWidth(), 300, "support saisissable")
    eq(NS.db.modules.blizzardframes.lootframe, "keep", "butin Blizzard : par défaut laissé à Edit Mode")
    eq(MuscaUI_Holder_lootframe == nil or not MuscaUI_Holder_lootframe:IsShown(), true)
    NS.db.modules.blizzardframes.lootframe = "move"
    NS.Modules:SetEnabled("loot", true)
    NS.Modules:Refresh("blizzardframes")
    eq(MuscaUI_Holder_lootframe == nil or not MuscaUI_Holder_lootframe:IsShown(), true, "module Butin MuscaUI actif : pas d'adoption")
    NS.Modules:SetEnabled("loot", false)
    NS.Modules:Refresh("blizzardframes")
    truthy(MuscaUI_Holder_lootframe and MuscaUI_Holder_lootframe:IsShown(), "sinon adoptée")
    NS.db.modules.blizzardframes.lootframe = "keep"
    NS.Modules:SetEnabled("blizzardframes", false)
end)
