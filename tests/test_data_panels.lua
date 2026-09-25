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
    Panels.db.panels.panel1.hideInCombat = true
    NS.Modules:Refresh("datapanels")
    eq(panel.slots[3]:IsShown(), false, "deux emplacements")
    truthy(Mock.stateDrivers[panel].visibility:find("combat"), "masqué en combat")
    Mock.SetCombat(true)
    Panels.db.panels.panel1.slotCount = 3
    NS.Modules:Refresh("datapanels")
    eq(Panels.failed, nil, "réglage en combat : différé, pas d'erreur")
    eq(panel.slots[3]:IsShown(), false, "pas encore appliqué")
    Mock.SetCombat(false)
    truthy(panel.slots[3]:IsShown(), "appliqué à la sortie du combat")
    Panels.db.panels.panel1.slotCount, Panels.db.panels.panel1.hideInCombat = 4, false
    local copy = NS.Database.Deserialize(NS.Database.Serialize(NS.db))
    eq(copy.modules.datapanels.panels.panel1.slots.slot1, "coords", "panneaux exportés avec le profil")
    NS.Modules:SetEnabled("datapanels", false)
    eq(panel:IsShown(), false)
    eq(NS.Movers:Anchor("datapanel1"), nil, "mover retiré")
    Mock.mapID, Mock.mapPosition = nil, nil
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
