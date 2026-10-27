-- tests/test_clickcast_extensions.lua : clic-sort étendu (molette, combinaisons de modificateurs,
-- 16 liaisons, sort glissé, rang épinglé, résurrection d'un membre mort).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local GF = NS.Modules:Get("groupframes")
local clickCast = NS.Modules:Get("clickcast")

local function Setup()
    reset()
    NS.Modules:SetEnabled("groupframes", true)
    Mock.SetGroup(2, false)
end
local function Teardown()
    NS.Modules:SetEnabled("clickcast", false)
    Mock.SetGroup(0, false)
    NS.Modules:SetEnabled("groupframes", false)
end

test("clic-sort : combinaisons de modificateurs dans l'ordre sécurisé, 16 liaisons", function()
    Setup()
    local bindings = clickCast.db.bindings
    bindings.b1.spell, bindings.b1.mouse, bindings.b1.modifier = "Soins", "1", "ctrl-alt-shift"   -- ordre libre
    bindings.b2.spell, bindings.b2.mouse, bindings.b2.modifier = "Bouclier", "2", "shift-ctrl"
    bindings.b16.spell, bindings.b16.mouse, bindings.b16.modifier, bindings.b16.key = "Rénovation", "3", "none", "MOUSEWHEELUP"
    NS.Modules:SetEnabled("clickcast", true)
    local ami = GF:GetButton("party1")
    eq(ami:GetAttribute("alt-ctrl-shift-type1"), "spell", "préfixe alt-ctrl-shift-")
    eq(ami:GetAttribute("alt-ctrl-shift-spell1"), "Soins")
    eq(ami:GetAttribute("ctrl-shift-spell2"), "Bouclier", "ctrl-shift-")
    eq(ami:GetAttribute("spell3"), "Rénovation", "seizième liaison, clic milieu")
    eq(ami:GetAttribute("muscacast-key16"), "MOUSEWHEELUP", "molette liée au survol")
    eq(ami:GetAttribute("*type-muscacast16"), "spell")
    truthy(ami.wrapped.OnEnter:find("for i = 1, 16"), "en-tête : 16 touches")
    bindings.b1.spell, bindings.b2.spell, bindings.b16.spell, bindings.b16.key = "", "", "", ""
    bindings.b1.modifier, bindings.b2.modifier = "shift", "shift"
    Teardown()
end)

test("clic-sort : la molette se capture comme une touche, modificateurs compris", function()
    reset()
    eq(clickCast.WheelKey(1), "MOUSEWHEELUP")
    eq(clickCast.WheelKey(-1), "MOUSEWHEELDOWN")
    Mock.ctrl, Mock.shift = true, true
    eq(clickCast.CaptureKey(clickCast.WheelKey(-1)), "CTRL-SHIFT-MOUSEWHEELDOWN")
    Mock.ctrl, Mock.shift = false, false
    -- Molette seule déjà liée au zoom caméra : acceptée (liaison locale au survol).
    Mock.bindings.CAMERAZOOMIN = "MOUSEWHEELUP"
    eq(clickCast.CaptureKey("MOUSEWHEELUP"), "MOUSEWHEELUP", "molette : contrôle de raccourci sauté")
    Mock.bindings.ACTIONBUTTON3 = "T"
    eq(clickCast.CaptureKey("T"), nil, "autre touche liée : refusée")
    Mock.bindings.CAMERAZOOMIN, Mock.bindings.ACTIONBUTTON3 = nil, nil
end)

test("clic-sort : sort glissé, rang inférieur épinglé, rang le plus haut sans rang", function()
    reset()
    Mock.spells[2050], Mock.spells[2052] = "Lesser Heal", "Lesser Heal"   -- rang 1, rang 2
    Mock.knownSpells[2050], Mock.knownSpells[2052] = true, true
    local ranks = { [2050] = "Rank 1", [2052] = "Rank 2" }
    C_Spell.GetSpellSubtext = function(id) return ranks[id] end
    Mock.FireEvent("SPELLS_CHANGED")   -- vide le cache de NS.KnownSpellID ; par nom : le plus haut id
    eq(clickCast.SpellText(2050), "Lesser Heal(Rank 1)", "rang 1 épinglé")
    eq(clickCast.SpellText(2052), "Lesser Heal", "rang le plus haut : nom seul")
    ranks[2050] = ""
    eq(clickCast.SpellText(2050), "Lesser Heal", "sans texte de rang : nom seul")
    -- Dépôt sur le champ.
    local box = CreateFrame("EditBox")
    local received
    clickCast.AcceptDrop(box, function(text) received = text end)
    Mock.cursorItem, Mock.cursorSpellID = "spell", 2052
    box.scripts.OnReceiveDrag(box)
    eq(received, "Lesser Heal")
    eq(Mock.cursorItem, nil, "curseur vidé")
    received = nil
    Mock.cursorItem = "item"
    box.scripts.OnReceiveDrag(box)
    eq(received, nil, "objet tenu : ignoré")
    Mock.spells[2050], Mock.spells[2052], Mock.knownSpells[2050], Mock.knownSpells[2052] = nil, nil, nil, nil
    Mock.cursorSpellID = nil
    -- Rang épinglé jusqu'à l'attribut sécurisé.
    Setup()
    clickCast.db.bindings.b1.spell = "Lesser Heal(Rank 1)"
    NS.Modules:SetEnabled("clickcast", true)
    eq(GF:GetButton("party1"):GetAttribute("shift-spell1"), "Lesser Heal(Rank 1)")
    clickCast.db.bindings.b1.spell = ""
    C_Spell.GetSpellSubtext = nil
    Teardown()
end)

test("clic-sort : résurrection d'un membre mort, échange sécurisé le temps du clic", function()
    Setup()
    Mock.spells[2006] = "Resurrection"
    Mock.knownSpells[2006] = true
    local class = Mock.units.player.class
    Mock.units.player.class = "PRIEST"
    local bindings = clickCast.db.bindings
    bindings.b1.spell, bindings.b1.mouse, bindings.b1.modifier = "Heal", "1", "shift"
    bindings.b2.kind, bindings.b2.spell, bindings.b2.mouse, bindings.b2.modifier = "macro", "Macro", "2", "shift"
    NS.Modules:SetEnabled("clickcast", true)
    local ami = GF:GetButton("party1")
    eq(ami:GetAttribute("muscacast-rez"), nil, "option éteinte : rien")
    eq(ami.wrapped.PreClick ~= nil, true, "PreClick posé")
    clickCast.db.resurrect = true
    NS.Modules:Refresh("clickcast")
    eq(ami:GetAttribute("muscacast-rez"), "Resurrection")
    eq(ami:GetAttribute("muscacast-rezcount"), 1, "seule la liaison sort est visée, pas la macro")
    eq(ami:GetAttribute("muscacast-rez1"), "shift-spell1")
    -- Clic fidèle : le sort vu par OnClick (attribut lu à ce moment), puis restauration.
    local function Click()
        local seen
        Mock.SimulateClick(ami, function() seen = ami:GetAttribute("shift-spell1") end)
        return seen
    end
    eq(Click(), "Heal", "vivant : sort lié lancé")
    Mock.units.party1.dead = true
    eq(Click(), "Resurrection", "mort : OnClick voit le rez")
    eq(ami:GetAttribute("shift-spell1"), "Heal", "après le clic : sort lié rendu")
    eq(ami:GetAttribute("muscacast-swapped"), nil, "marqueur retiré")
    Mock.units.party1.dead = nil
    eq(Click(), "Heal", "2e clic sur un vivant : sort d'origine")
    -- Druide : pas de rez (Renaissance consommé par un clic de soin).
    Mock.units.player.class = "DRUID"
    Mock.spells[20484], Mock.knownSpells[20484] = "Rebirth", true
    NS.Modules:Refresh("clickcast")
    eq(ami:GetAttribute("muscacast-rez"), nil, "druide : aucun rez")
    Mock.spells[20484], Mock.knownSpells[20484] = nil, nil
    Mock.units.player.class = "PRIEST"
    -- Sort appris après coup : SPELLS_CHANGED réapplique.
    clickCast.db.resurrect = false
    NS.Modules:Refresh("clickcast")
    Mock.knownSpells[2006] = nil
    clickCast.db.resurrect = true
    NS.Modules:Refresh("clickcast")
    eq(ami:GetAttribute("muscacast-rez"), nil, "rez non appris")
    Mock.knownSpells[2006] = true
    Mock.FireEvent("SPELLS_CHANGED")
    eq(ami:GetAttribute("muscacast-rez"), "Resurrection", "appris : réappliqué")
    -- Option coupée : attributs retirés.
    clickCast.db.resurrect = false
    NS.Modules:Refresh("clickcast")
    eq(ami:GetAttribute("muscacast-rez"), nil)
    eq(ami:GetAttribute("muscacast-rez1"), nil)
    Mock.units.party1.dead = nil
    Mock.units.player.class = class
    Mock.spells[2006], Mock.knownSpells[2006] = nil, nil
    bindings.b1.spell, bindings.b2.spell, bindings.b2.kind = "", "", "spell"
    Teardown()
end)
