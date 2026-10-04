-- tests/test_data_panels.lua : étape 14, registre de data texts, panneaux de données, emplacements
-- libres de la barre du haut.
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset
local DataTexts = NS.DataTexts
local Panels = NS.Modules:Get("datapanels")
local TopBar = NS.Modules:Get("topbar")

local function Text(key)
    local label = { SetText = function(self, t) self.text = t end,
                    SetFormattedText = function(self, fmt, ...) self.text = string.format(fmt, ...) end }
    DataTexts.Render(DataTexts:Get(key), label)
    return label.text
end

test("data texts : registre commun, textes de la barre du haut inscrits, choix", function()
    for _, key in ipairs({ "friends", "guild", "clock", "gold", "durability", "bags", "perf",
                           "coords", "quests", "regen", "speed", "dps" }) do
        truthy(DataTexts:Get(key), "inscrit : " .. key)
        truthy(L["DATATEXT_" .. key:upper()], "libellé : " .. key)
    end
    local all, sized = DataTexts:Choices(false), DataTexts:Choices(true)
    eq(all[1].value, "none")
    eq(#all, #sized + 1, "DPS (secret) exclu des emplacements dimensionnés")
    for _, choice in ipairs(sized) do truthy(choice.value ~= "dps") end
end)

test("data texts : coordonnées, quêtes, régénération, vitesse ; secret = tiret", function()
    reset()
    Mock.mapID, Mock.mapPosition = 1411, { 0.523, 0.4461 }
    eq(Text("coords"), "52.3, 44.6")
    Mock.mapPosition = { 0, 0 }
    truthy(Text("coords"):find("-", 1, true), "instance : pas de position")
    Mock.mapPosition = { Mock.SetSecret(0.31), 0.2 }
    truthy(Text("coords"):find("-", 1, true), "position secrète")
    Mock.mapID, Mock.mapPosition = nil, nil
    _G.GetNumQuestLogEntries = function() return 25, 20 end
    truthy(Text("quests"):find("|cffff4040" .. "20/20", 1, true), "journal plein en rouge")
    _G.GetNumQuestLogEntries = nil
    _G.GetManaRegen = function() return 2, 0.5 end
    truthy(Text("regen"):find("10", 1, true) and Text("regen"):find("3", 1, true), "10 hors incantation, 3 en incantation")
    _G.GetManaRegen = function() return Mock.SetSecret(4), 1 end
    truthy(Text("regen"):find("-", 1, true), "régénération secrète")
    _G.GetManaRegen = nil
    _G.GetUnitSpeed = function() return 0, 7 end
    truthy(Text("speed"):find("100%", 1, true), "à l'arrêt : vitesse de course")
    _G.GetUnitSpeed = function() return 9.8, 7 end
    truthy(Text("speed"):find("140%", 1, true), "monté")
    _G.GetUnitSpeed = nil
end)

test("data texts : DPS natif, valeur secrète passée sans être lue", function()
    reset()
    truthy(Text("dps"):find("-", 1, true), "sans C_DamageMeter")
    local secret = Mock.SetSecret(1234)
    _G.Enum.DamageMeterSessionType = { Current = 1 }
    _G.Enum.DamageMeterType = { DamageDone = 0 }
    _G.C_DamageMeter = { GetCombatSessionFromType = function()
        return { combatSources = { { isLocalPlayer = false, amountPerSecond = 9 },
                                   { isLocalPlayer = true, amountPerSecond = secret } } }
    end }
    truthy(Text("dps"):find("***", 1, true), "secret abrégé par le moteur")
    local abbreviate = _G.AbbreviateNumbers
    local secretText = Mock.SetSecret("1.2k secret")
    _G.AbbreviateNumbers = function() return secretText end
    -- Le mock ne détecte pas un test booléen : ce test vérifie le chemin motif + valeur.
    eq(Text("dps"), "|cff9d9d9d" .. L.DATATEXT_DPS_SHORT .. "|r 1.2k secret", "chaîne secrète passée au motif")
    _G.AbbreviateNumbers = abbreviate
    _G.C_DamageMeter, _G.Enum.DamageMeterSessionType, _G.Enum.DamageMeterType = nil, nil, nil
end)

test("panneaux : panneau 1 sur son mover, emplacements, événements, minuterie, désactivation", function()
    reset()
    Mock.mapID, Mock.mapPosition = 1411, { 0.1, 0.2 }
    NS.Modules:SetEnabled("datapanels", true)
    local panel = Panels:GetPanel(1)
    truthy(panel and panel:IsShown(), "panneau 1 affiché")
    eq(Panels:GetPanel(2), nil, "panneau 2 coupé : jamais construit")
    truthy(NS.Movers:Anchor("datapanel1"), "mover")
    eq(panel.slots[1].dataKey, "coords")
    eq(panel.slots[1].label:GetText(), "10.0, 20.0")
    eq(panel.slots[5]:IsShown(), false, "quatre emplacements")
    Mock.mapPosition = { 0.3, 0.4 }
    Mock.Advance(0.6)
    eq(panel.slots[1].label:GetText(), "30.0, 40.0", "minuterie")
    _G.GetNumQuestLogEntries = function() return 3, 2 end
    Mock.FireEvent("QUEST_LOG_UPDATE")
    truthy(panel.slots[4].label:GetText():find("2/", 1, true), "événement")
    _G.GetNumQuestLogEntries = nil
    Panels.db.panels.panel1.slotCount = 2
    Panels.db.panels.panel1.visibility = NS.Visibility.Spec({ combat = "no" })
    NS.Modules:Refresh("datapanels")
    eq(panel.slots[3]:IsShown(), false, "deux emplacements")
    eq(Mock.stateDrivers[panel].visibility, "[nocombat] show; hide", "masqué en combat")
    Mock.SetCombat(true)
    Panels.db.panels.panel1.slotCount = 3
    NS.Modules:Refresh("datapanels")
    eq(Panels.failed, nil, "réglage en combat : différé, pas d'erreur")
    eq(panel.slots[3]:IsShown(), false, "pas encore appliqué")
    Mock.SetCombat(false)
    truthy(panel.slots[3]:IsShown(), "appliqué à la sortie du combat")
    Panels.db.panels.panel1.slotCount, Panels.db.panels.panel1.visibility = 4, NS.Visibility.Spec()
    local copy = NS.Database.Deserialize(NS.Database.Serialize(NS.db))
    eq(copy.modules.datapanels.panels.panel1.slots.slot1, "coords", "panneaux exportés avec le profil")
    NS.Modules:SetEnabled("datapanels", false)
    eq(panel:IsShown(), false)
    eq(NS.Movers:Anchor("datapanel1"), nil, "mover retiré")
    Mock.mapID, Mock.mapPosition = nil, nil
end)

test("panneaux de données : nombre réglable, panneaux créés au-delà de six, dix emplacements", function()
    reset()
    Panels.db.panelCount = 8
    NS.Modules:SetEnabled("datapanels", true)
    local cfg = Panels.db.panels.panel8
    truthy(cfg and cfg.slots.slot10 == "none", "panneau 8 créé, complet")
    eq(Panels:GetPanel(8), nil, "créé désactivé")
    cfg.enabled, cfg.slotCount, cfg.slots.slot10 = true, 10, "clock"
    NS.Modules:Refresh("datapanels")
    local panel = Panels:GetPanel(8)
    truthy(panel:IsShown(), "panneau 8 affiché")
    truthy(NS.Movers:Anchor("datapanel8"), "son mover")
    eq(panel.slots[10].dataKey, "clock")
    local mirrored = NS.Database:MirrorTable().profiles[NS.Database:ActiveProfileName()].modules.datapanels.panels
    eq(mirrored.panel7, nil, "miroir : panneau 7 aux défauts, non écrit")
    eq(mirrored.panel8.slots.slot10, "clock", "miroir : seul ce qui diffère")
    Panels.db.panelCount = 6
    NS.Modules:Refresh("datapanels")
    eq(panel:IsShown(), false, "au-delà du nombre : caché")
    eq(NS.Movers:Anchor("datapanel8"), nil)
    eq(Panels.db.panels.panel8, nil, "réglages du panneau retiré effacés")
    -- Réinitialisation du module avec un panneau 8 affiché : aucune erreur, la visibilité des autres modules tient.
    Panels.db.panelCount = 8
    NS.Modules:Refresh("datapanels")
    Panels.db.panels.panel8.enabled = true
    NS.Modules:Refresh("datapanels")
    NS.Options.ResetModule("datapanels")
    eq(Panels:GetPanel(8):IsShown(), false, "réinitialisé : panneau 8 caché")
    NS.Visibility:Refresh()
    NS.Modules:SetEnabled("datapanels", false)
end)

test("barre du haut : emplacements libres, data text secret refusé", function()
    reset()
    Mock.mapID, Mock.mapPosition = 1411, { 0.5, 0.5 }
    local _, elements = TopBar:GetFrame()
    eq(elements.extraLeft:IsShown(), false, "vide par défaut")
    TopBar.db.extraLeft, TopBar.db.extraRight = "coords", "dps"
    NS.Modules:Refresh("topbar")
    truthy(elements.extraLeft:IsShown())
    eq(elements.extraLeft.label:GetText(), "50.0, 50.0")
    eq(elements.extraRight:IsShown(), false, "DPS secret : pas dans la barre")
    TopBar.db.extraLeft, TopBar.db.extraRight = "none", "none"
    NS.Modules:Refresh("topbar")
    Mock.mapID, Mock.mapPosition = nil, nil
end)

test("data texts : métiers, niveau d'objet, durée du combat, monnaies, or de tous les personnages", function()
    reset()
    _G.GetProfessions = function() return 1, nil, nil, 4 end
    _G.GetProfessionInfo = function(index)
        if index == 1 then return "Alchimie", nil, 150, 225 end
        return "Pêche", nil, 75, 150
    end
    truthy(Text("professions"):find("150/225", 1, true), "premier métier")
    truthy(Text("professions"):find("75/150", 1, true), "trou de GetProfessions sauté")
    _G.GetProfessions, _G.GetProfessionInfo = nil, nil
    _G.GetAverageItemLevel = function() return 48, 45.25 end
    truthy(Text("itemlevel"):find("45.3", 1, true), "moyenne équipée")
    _G.GetAverageItemLevel = nil
    Mock.SetCombat(true)
    Mock.Advance(65.5)   -- pas du mock : 65 tomberait à 64,99
    truthy(Text("combat"):find("1:05", 1, true), "combat en cours")
    Mock.SetCombat(false)
    Mock.Advance(30)
    truthy(Text("combat"):find("1:05", 1, true), "dernier combat gardé")
    _G.C_CurrencyInfo = { GetBackpackCurrencyInfo = function(index)
        if index == 1 then return { name = "Honneur", quantity = 1200, iconFileID = 42 } end
    end }
    eq(Text("currency"), "|T42:0|t 1200")
    _G.C_CurrencyInfo = nil
    NS.global.goldLedger = { ["Autre - Royaume"] = 50000 }
    Mock.FireEvent("PLAYER_MONEY")
    eq(NS.global.goldLedger[NS.Database.CharacterKey()], Mock.money, "or du personnage relevé")
    local lines = {}
    local tooltip = { AddLine = function(_, text) lines[#lines + 1] = text end,
                      AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. "=" .. right end }
    DataTexts.GoldLedgerTooltip(tooltip)
    eq(lines[2], NS.Database.CharacterKey() .. "=" .. NS.FormatMoney(Mock.money), "le plus riche d'abord")
    eq(lines[4], L.DATATEXT_GOLD_TOTAL .. "=" .. NS.FormatMoney(Mock.money + 50000), "total")
    NS.global.goldLedger = {}
end)

test("data texts : textes LibDataBroker repris, créés avant ou après la connexion", function()
    local previous = _G.LibStub
    local objects, created = { Horloge = { text = "12:00", icon = "icone" } }, nil
    local broker = {
        DataObjectIterator = function() return pairs(objects) end,
        RegisterCallback = function(_, _, handler) created = handler end,
    }
    _G.LibStub = function(name, silent)
        if name == "LibDataBroker-1.1" then return broker end
        return previous and previous(name, silent)
    end
    DataTexts.RegisterBrokers()
    eq(Text("ldb:Horloge"), "|Ticone:0|t 12:00")
    local clicked
    created("LibDataBroker_DataObjectCreated", "Minuteur", { label = "Minuteur", OnClick = function(_, b) clicked = b end })
    eq(Text("ldb:Minuteur"), "Minuteur")
    DataTexts:Get("ldb:Minuteur").click(nil, "RightButton")
    eq(clicked, "RightButton")
    local found
    for _, choice in ipairs(DataTexts:Choices(false)) do if choice.value == "ldb:Horloge" then found = choice.name end end
    eq(found, "LDB : Horloge", "nommé dans les listes")
    DataTexts.registry["ldb:Horloge"], DataTexts.registry["ldb:Minuteur"] = nil, nil
    _G.LibStub = previous
end)

test("panneaux de données : six panneaux, Maj + glisser échange deux emplacements d'un panneau à l'autre", function()
    reset()
    local panels = NS.db.modules.datapanels.panels
    panels.panel4.enabled = true
    NS.Modules:SetEnabled("datapanels", true)
    local first, fourth = Panels:GetPanel(1), Panels:GetPanel(4)
    truthy(fourth and fourth:IsShown(), "quatrième panneau")
    truthy(NS.Movers.registry.datapanel4, "sur son mover")
    local source, target = first.slots[1], fourth.slots[1]
    eq(source.dataKey, "coords"); eq(target.dataKey, "clock")
    source:GetScript("OnDragStart")(source)
    source:GetScript("OnDragStop")(source)
    eq(panels.panel1.slots.slot1, "coords", "sans Maj : rien")
    _G.GetMouseFoci = function() return { target } end
    Mock.shift = true
    source:GetScript("OnDragStart")(source)
    Mock.shift = false
    source:GetScript("OnDragStop")(source)
    eq(panels.panel1.slots.slot1, "clock", "échangés")
    eq(panels.panel4.slots.slot1, "coords")
    eq(source.dataKey, "clock", "emplacement remis en page")
    _G.GetMouseFoci = nil
    panels.panel1.slots.slot1, panels.panel4.slots.slot1, panels.panel4.enabled = "coords", "clock", false
    NS.Modules:SetEnabled("datapanels", false)
end)
