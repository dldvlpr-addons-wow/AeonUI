-- tests/test_reminders.lua : buffs de classe, posture, familier, Bien nourri, équipement.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Reminders = NS.Modules:Get("reminders")

local function Keys(list)
    local keys = {}
    for _, entry in ipairs(list) do keys[entry.key] = entry.text end
    return keys
end

test("buff de classe : seulement si le sort est connu", function()
    reset()
    eq(Keys(Reminders:Collect()).mageArmor, nil, "inconnu")
    Mock.knownSpells[168] = true
    eq(Keys(Reminders:Collect()).mageArmor, "Missing: Mage armor")
    Mock.buffs = { "Ice Armor" }
    eq(Keys(Reminders:Collect()).mageArmor, nil, "une variante satisfait la règle")
end)

test("rien en combat, en ville, ni sur valeur secrète", function()
    reset()
    Mock.knownSpells[168] = true
    Mock.SetCombat(true)
    eq(#Reminders:Collect(), 0, "combat")
    Mock.SetCombat(false)
    Mock.resting = true
    eq(Keys(Reminders:Collect()).mageArmor, nil, "repos")
    Mock.resting = false
    Mock.buffs = { "Buff secret" }
    Mock.secret["Buff secret"] = true
    eq(Keys(Reminders:Collect()).mageArmor, nil, "secret")
end)

test("règles optionnelles : Forme d'Ombre seulement si demandée", function()
    reset()
    Mock.units.player.class = "PRIEST"
    Mock.spells[15473] = "Shadowform"
    Mock.knownSpells[15473] = true
    eq(Keys(Reminders:Collect()).shadowform, nil, "option coupée")
    NS.db.modules.reminders.shadowform = true
    eq(Keys(Reminders:Collect()).shadowform, "Missing: Shadowform")
    NS.db.modules.reminders.shadowform = false
end)

test("posture attendue du guerrier", function()
    reset()
    Mock.units.player.class = "WARRIOR"
    Mock.spells[71] = "Defensive Stance"
    Mock.knownSpells[71] = true
    Mock.shapeshiftForm = 1
    eq(Keys(Reminders:Collect()).stance, nil, "pas de posture choisie")
    NS.db.modules.reminders.expectedStance = "defensive"
    eq(Keys(Reminders:Collect()).stance, "Wrong stance: Defensive Stance expected")
    Mock.shapeshiftForm = 2
    eq(Keys(Reminders:Collect()).stance, nil, "bonne posture")
    NS.db.modules.reminders.expectedStance = "none"
end)

test("forme du druide : les formes de voyage ne déclenchent rien", function()
    reset()
    Mock.units.player.class = "DRUID"
    Mock.spells[5487] = "Bear Form"
    Mock.knownSpells[5487] = true
    NS.db.modules.reminders.expectedStance = "bear"
    Mock.formID = 1
    eq(Keys(Reminders:Collect()).stance, "Wrong stance: Bear Form expected", "félin au lieu d'ours")
    Mock.formID = 3
    eq(Keys(Reminders:Collect()).stance, nil, "forme de voyage")
    Mock.formID = 8
    eq(Keys(Reminders:Collect()).stance, nil, "ours redoutable (niveau 40 et plus)")
    NS.db.modules.reminders.expectedStance = "none"
end)

test("familier absent (chasseur)", function()
    reset()
    Mock.units.player.class = "HUNTER"
    Mock.spells[883] = "Call Pet"
    Mock.knownSpells[883] = true
    eq(Keys(Reminders:Collect()).pet, "No pet")
    Mock.units.pet = { name = "Loup" }
    eq(Keys(Reminders:Collect()).pet, nil)
end)

test("Bien nourri : seulement en instance et si activé", function()
    reset()
    Mock.spells[19705] = "Well Fed"
    NS.db.modules.reminders.wellFed = true
    eq(Keys(Reminders:Collect()).wellFed, nil, "monde ouvert")
    Mock.instanceType = "raid"
    eq(Keys(Reminders:Collect()).wellFed, "Not Well Fed")
    Mock.buffs = { "Well Fed" }
    eq(Keys(Reminders:Collect()).wellFed, nil)
    NS.db.modules.reminders.wellFed = false
end)

test("poison : arme enchantée ou non", function()
    reset()
    Mock.units.player.class = "ROGUE"
    Mock.knownSpells[2842] = true
    eq(Keys(Reminders:Collect()).roguePoison, "Missing: Weapon poison")
    Mock.mainHandEnchant = true
    eq(Keys(Reminders:Collect()).roguePoison, nil)
end)

test("durabilité et sacs pleins, un seul son à l'apparition", function()
    reset()
    Mock.Advance(2.1)
    Mock.sounds = {}
    Mock.durability[1] = { 10, 100 }
    for bag = 0, 4 do
        for slot = 1, Mock.bagSize do Mock.bags[bag][slot] = { itemID = 1, quality = 1 } end
    end
    local keys = Keys(Reminders:Evaluate())
    truthy(keys.durability, "durabilité")
    truthy(keys.bags, "sacs")
    eq(#Mock.sounds, 1)
    Reminders:Evaluate()
    eq(#Mock.sounds, 1, "pas de son pour un rappel déjà affiché")
end)

test("camouflage : texte et couleur personnalisés, partout sur option, son répété", function()
    reset()
    Mock.units.player.class = "ROGUE"
    Mock.spells[1784] = "Stealth"
    Mock.knownSpells[1784] = true
    local db = NS.db.modules.reminders
    db.stealth = true
    Mock.Advance(3.5)
    eq(Keys(Reminders:Collect()).stealth, nil, "hors instance : rien")
    db.stealthEverywhere = true
    eq(Keys(Reminders:Collect()).stealth, "Stealth!", "partout")
    db.stealthText = "Vanish!"
    db.stealthColor = { r = 0.2, g = 0.4, b = 1 }
    Reminders:Evaluate()
    local _, lines = Reminders:GetFrame()
    eq(lines[1]:GetText(), "Vanish!", "texte personnalisé")
    eq(lines[1].textColor[3], 1, "couleur personnalisée")
    Mock.sounds = {}
    db.repeatSound = 5
    Reminders:Evaluate()
    Mock.Advance(11)
    eq(#Mock.sounds, 2, "répété deux fois en 11 s")
    db.stealth = false
    Reminders:Evaluate()
    Mock.Advance(11)
    eq(#Mock.sounds, 2, "plus de son une fois le rappel parti")
    db.stealthEverywhere, db.stealthText, db.repeatSound = false, "", 0
    db.stealthColor = { r = 1, g = 0.55, b = 0.15 }
end)

test("posture : gabarit personnalisé, gabarit invalide ignoré", function()
    reset()
    Mock.units.player.class = "WARRIOR"
    Mock.spells[71] = "Defensive Stance"
    Mock.knownSpells[71] = true
    Mock.shapeshiftForm = 1
    local db = NS.db.modules.reminders
    db.expectedStance = "defensive"
    db.stanceText = "Go %s"
    eq(Keys(Reminders:Collect()).stance, "Go Defensive Stance")
    db.stanceText = "%d"
    eq(Keys(Reminders:Collect()).stance, "Wrong stance: Defensive Stance expected", "repli locale")
    db.expectedStance, db.stanceText = "none", ""
end)
