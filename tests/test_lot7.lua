-- tests/test_lot7.lua : rangs supérieurs, camelote marquée, minuteur de vol, alerte de menace,
-- flux de butin, statistiques des textes de données.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

-- Globales absentes du mock : posées pour un test, rendues à la fin.
local saved = {}
local function Set(name, value)
    if not saved[name] then saved[name] = { rawget(_G, name) } end
    _G[name] = value
end
local function Restore()
    for name, old in pairs(saved) do _G[name] = old[1] end
    saved = {}
end

--------------------------------------------------------------------------------
-- Ticket 02 : rangs supérieurs sur les barres
--------------------------------------------------------------------------------

test("rangs : remplacés hors combat, curseur vide, un seul message", function()
    reset()
    local actions = { [1] = 1001, [7] = 1001, [8] = 2001 }
    local cursorSpell
    Set("GetActionInfo", function(slot) if actions[slot] then return "spell", actions[slot] end end)
    Set("PlaceAction", function(slot) actions[slot] = cursorSpell end)
    Set("C_SpellBook", {
        FindSpellBookSlotForSpell = function(id) if id == 1002 then return 1, 0 end end,
        IsSpellBookItemLowRank = function() return false end,
    })
    local bank = Enum and Enum.SpellBookSpellBank
    if bank then bank.Player = bank.Player or 0 end
    if bank and bank.Player ~= 0 then
        C_SpellBook.FindSpellBookSlotForSpell = function(id) if id == 1002 then return 1, bank.Player end end
    end
    C_Spell.PickupSpell = function(id) cursorSpell = id end
    C_Spell.GetSpellSubtext = function() return "Rank 2" end
    Mock.spells[1001], Mock.spells[1002], Mock.spells[2001] = "Frostbolt", "Frostbolt", "Blink"

    Mock.SetCombat(true)
    Mock.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 1002)
    eq(actions[1], 1001, "rien en combat")
    Mock.cursorItem = "item"
    Mock.SetCombat(false)
    eq(actions[1], 1001, "curseur occupé : attente")
    ClearCursor()
    Mock.FireEvent("CURSOR_CHANGED")
    eq(actions[1], 1002, "emplacement 1")
    eq(actions[7], 1002, "emplacement 7")
    eq(actions[8], 2001, "autre sort intact")
    eq(Mock.FindPrinted("Frostbolt (Rank 2)"), nil, "message différé")
    Mock.Advance(2.5, 0.5)
    truthy(Mock.FindPrinted("Frostbolt (Rank 2)"), "message groupé")

    C_Spell.PickupSpell, C_Spell.GetSpellSubtext = nil, nil
    Restore()
end)

--------------------------------------------------------------------------------
-- Ticket 03 : camelote marquée
--------------------------------------------------------------------------------

test("camelote : marquage, vente des marqués, exclusions comptées", function()
    reset()
    local Bags = NS.Modules:Get("bags")
    local text, added = Bags.ToggleListID("1, 2", 3)
    eq(text, "1, 2, 3", "ajout")
    truthy(added, "ajouté")
    text, added = Bags.ToggleListID(text, 2)
    eq(text, "1, 3", "retrait")
    eq(added, false, "retiré")

    local bags = NS.db.modules.bags
    local oldMarked, oldPinned = bags.junkMarked, bags.pinned
    bags.junkMarked, bags.pinned = "300, 301, 302, 304", "303"
    for id = 300, 303 do Mock.items[id] = { sellPrice = 500 } end
    Mock.bags[0][1] = { itemID = 300, quality = 1 }        -- marqué : vendu
    Mock.bags[0][2] = { itemID = 301, quality = 1 }        -- ensemble d'équipement
    Mock.bags[0][3] = { itemID = 302, quality = 2 }        -- remboursable
    Mock.bags[0][4] = { itemID = 303, quality = 0 }        -- gris épinglé
    Mock.bags[0][5] = { itemID = 304, quality = 1 }        -- marqué sans prix
    C_Container.GetContainerItemEquipmentSetInfo = function(bag, slot) return bag == 0 and slot == 2 end
    C_Container.GetContainerItemPurchaseInfo = function(_, slot) return { refundSeconds = slot == 3 and 3600 or 0 } end

    local junk, kept = NS.Modules:Get("automation"):FindJunk()
    eq(#junk, 1, "un seul objet vendu")
    eq(junk[1].itemID, 300, "le marqué")
    eq(kept, 4, "gardés")

    C_Container.GetContainerItemEquipmentSetInfo, C_Container.GetContainerItemPurchaseInfo = nil, nil
    bags.junkMarked, bags.pinned = oldMarked, oldPinned
end)

--------------------------------------------------------------------------------
-- Ticket 04 : minuteur de vol
--------------------------------------------------------------------------------

test("vol : apprentissage, lissage, trajet inconnu, vol interrompu", function()
    reset()
    local FlightTimer = NS.Modules:Get("flighttimer")
    local oldTimes = NS.global.flightTimes
    NS.global.flightTimes = {}
    FlightTimer.Learn(1, 2, 100)
    eq(FlightTimer.KnownDuration(1, 2), 100, "première mesure")
    FlightTimer.Learn(1, 2, 200)
    eq(FlightTimer.KnownDuration(1, 2), 130, "moyenne mobile")
    FlightTimer.Learn(1, 2, 3)
    eq(FlightTimer.KnownDuration(1, 2), 130, "trop court : ignoré")
    eq(FlightTimer.KnownDuration(3, 4), nil, "trajet inconnu")

    FlightTimer.Start({ from = 3, to = 4, name = "Hurlevent" })
    Mock.FireEvent("PLAYER_DEAD")
    Mock.Advance(60, 1)
    FlightTimer.Stop(true)
    eq(FlightTimer.KnownDuration(3, 4), nil, "vol interrompu : rien appris")
    eq(NS.global.flightInProgress, false, "vol effacé")

    FlightTimer.Start({ from = 3, to = 4, name = "Hurlevent" })
    truthy(NS.global.flightInProgress, "vol en cours sauvegardé")
    Mock.Advance(60, 1)
    FlightTimer.Stop(true)
    local learned = FlightTimer.KnownDuration(3, 4)
    truthy(learned and math.abs(learned - 60) < 1.5, "vol complet appris (" .. tostring(learned) .. ")")
    NS.global.flightTimes = oldTimes

    local db = NS.Database:Init({ version = NS.Database.VERSION,
                                  flightInProgress = { from = 1, to = 2, start = 0 } })
    eq(type(db.flightInProgress), "table", "vol sauvegardé gardé au chargement (reprise après /reload)")
end)

--------------------------------------------------------------------------------
-- Ticket 05 : alerte de menace
--------------------------------------------------------------------------------

test("menace : alerte au seuil, réarmée sous seuil - 10", function()
    reset()
    local ThreatWarning = NS.Modules:Get("threatwarning")
    ThreatWarning.db.threshold, ThreatWarning.db.sound = 80, false
    ThreatWarning:Check(0)
    eq(ThreatWarning:Check(79), false, "sous le seuil")
    eq(ThreatWarning:Check(80), true, "seuil atteint")
    eq(ThreatWarning:Check(95), false, "une seule alerte")
    eq(ThreatWarning:Check(75), false, "75 : pas réarmée")
    eq(ThreatWarning:Check(85), false, "toujours désarmée")
    eq(ThreatWarning:Check(69), false, "69 : réarmée")
    eq(ThreatWarning:Check(82), true, "nouvelle alerte")
    ThreatWarning.db.sound = true

    -- Joueur qui a déjà l'aggro (statut 3, 100 %) : aucune alerte ; menace haute sans aggro : alerte.
    local status, scaled = 3, 100
    Set("UnitDetailedThreatSituation", function() return status >= 2, status, scaled end)
    Mock.sounds = {}
    Mock.SetCombat(true)
    eq(#Mock.sounds, 0, "aggro déjà prise")
    Mock.SetCombat(false)
    status, scaled = 1, 90
    Mock.SetCombat(true)
    eq(#Mock.sounds, 1, "alerte avant la reprise d'aggro")
    Mock.SetCombat(false)
    Restore()
end)

--------------------------------------------------------------------------------
-- Ticket 06 : flux de butin
--------------------------------------------------------------------------------

test("butin : phrases de format, arguments inversés, secret", function()
    reset()
    Set("LOOT_ITEM_SELF", "You receive loot: %s.")
    Set("LOOT_ITEM_SELF_MULTIPLE", "You receive loot: %sx%d.")
    Set("LOOT_ITEM_PUSHED_SELF_MULTIPLE", "%2$d x %1$s reçu.")
    Set("YOU_LOOT_MONEY", "You loot %s")
    Set("GOLD_AMOUNT", "%d Gold")
    Set("SILVER_AMOUNT", "%d Silver")
    Set("COPPER_AMOUNT", "%d Copper")
    Set("FACTION_STANDING_INCREASED", "Reputation with %s increased by %d.")

    local parsed = NS.ParseLootLine("You receive loot: |cff9d9d9d|Hitem:1234::|h[Rag]|h|rx3.")
    eq(parsed.kind, "item", "objet")
    eq(parsed.itemID, 1234, "itemID")
    eq(parsed.quantity, 3, "quantité")
    parsed = NS.ParseLootLine("You receive loot: |Hitem:9|h[A]|h.")
    eq(parsed.quantity, 1, "simple")
    parsed = NS.ParseLootLine("4 x |Hitem:55|h[X]|h reçu.")
    eq(parsed.itemID, 55, "inversé : lien")
    eq(parsed.quantity, 4, "inversé : quantité")
    parsed = NS.ParseLootLine("You loot 1 Gold, 2 Silver, 3 Copper")
    eq(parsed.copper, 10203, "argent")
    parsed = NS.ParseLootLine("Reputation with Darnassus increased by 25.")
    eq(parsed.name, "Darnassus", "faction")
    eq(parsed.quantity, 25, "réputation")
    Set("FACTION_STANDING_INCREASED_ACH_BONUS", "Reputation with %s increased by %d. (+%.1f bonus)")
    parsed = NS.ParseLootLine("Reputation with Darnassus increased by 30. (+2.5 bonus)")
    eq(parsed and parsed.quantity, 30, "réputation avec bonus")
    eq(NS.ParseLootLine(Mock.SetSecret("You loot 1 Gold")), nil, "texte secret")
    eq(NS.ParseLootLine("Bob receives loot: x."), nil, "autre joueur")

    -- Cumul : même objet deux fois, une seule ligne.
    local LootFeed = NS.Modules:Get("lootfeed")
    Mock.FireEvent("CHAT_MSG_LOOT", "You receive loot: |Hitem:1234|h[Rag]|hx2.")
    Mock.FireEvent("CHAT_MSG_LOOT", "You receive loot: |Hitem:1234|h[Rag]|hx3.")
    local count, quantity = 0, nil
    for _, line in ipairs(LootFeed.Lines()) do
        if line.key == "item:1234" then count, quantity = count + 1, line.entry.quantity end
    end
    eq(count, 1, "une ligne")
    eq(quantity, 5, "quantités additionnées")
    Mock.Advance(LootFeed.db.duration + 1, 0.5)
    for _, line in ipairs(LootFeed.Lines()) do eq(line.key, nil, "ligne expirée") end
    Restore()
end)

--------------------------------------------------------------------------------
-- Ticket 07 : statistiques
--------------------------------------------------------------------------------

test("statistiques : côté selon la classe, nil sur secret", function()
    reset()
    eq(NS.GetStatSide("WARRIOR"), "melee", "guerrier")
    eq(NS.GetStatSide("HUNTER"), "ranged", "chasseur")
    eq(NS.GetStatSide("MAGE"), "spell", "mage")
    eq(NS.GetStatSide("DRUID", "NONE", 1), "melee", "druide félin")
    eq(NS.GetStatSide("DRUID", "NONE", 31), "spell", "druide hors forme de combat")
    eq(NS.GetStatSide("SHAMAN", "HEALER"), "spell", "chaman soigneur")
    eq(NS.GetStatSide("SHAMAN", "DAMAGER"), "melee", "chaman dégâts")
    eq(NS.GetStatSide("PALADIN", "HEALER"), "spell", "paladin soigneur")
    eq(NS.GetStatSide("PALADIN", "TANK"), "melee", "paladin tank")

    Set("GetCritChance", function() return 12.5 end)
    eq(NS.GetStat("crit", "melee"), 12.5, "lisible")
    Set("GetCritChance", function() return Mock.SetSecret(5) end)
    eq(NS.GetStat("crit", "melee"), nil, "secret")
    eq(NS.GetStat("haste", "melee"), nil, "API absente")
    local crit = { [2] = 4, [3] = 9.5, [4] = 6, [5] = 6, [6] = 6, [7] = 6 }
    Set("GetSpellCritChance", function(school) return crit[school] end)
    eq(NS.GetStat("crit", "spell"), 9.5, "critique des sorts : meilleure école")
    crit[6] = Mock.SetSecret(7)
    eq(NS.GetStat("crit", "spell"), nil, "critique des sorts : une école secrète")
    Restore()
end)
