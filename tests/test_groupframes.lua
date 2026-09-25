-- tests/test_groupframes.lua : cadres de groupe et de raid AeonUI (étape 4).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local GF = NS.Modules:Get("groupframes")
local Elements = NS.UnitFrameElements

local function Enable() NS.Modules:SetEnabled("groupframes", true) end
local function Disable() NS.Modules:SetEnabled("groupframes", false) end

test("groupe : activation, en-têtes, groupe de trois, désactivation", function()
    reset()
    Enable()
    local party, raid = GF.headers.party, GF.headers.raid
    truthy(party and raid)
    eq(party:GetAttribute("showParty"), true)
    eq(party:GetAttribute("showRaid"), false)
    eq(raid:GetAttribute("showRaid"), true)
    eq(raid:GetAttribute("groupBy"), "GROUP")
    truthy(Mock.stateDrivers[party].visibility:find("group:party"), "state driver groupe")
    truthy(NS.Movers:Anchor("uf_party") and NS.Movers:Anchor("uf_raid"))
    truthy(NS.IsBlizzardFrameHidden("CompactRaidFrameContainer"))
    Mock.SetGroup(3, false)
    eq(#party.children, 3)
    eq(GF:GetButton("player"):GetAttribute("unit"), "player")
    local ami = GF:GetButton("party1")
    truthy(ami, "party1 stylé")
    eq(ami.health:GetValue(), 800)
    eq(ami.name:GetText(), "Ami1")
    eq(ami.health.barColor[1], RAID_CLASS_COLORS.PRIEST.r, "couleur de classe")
    truthy(ami.power:IsShown())
    Disable()
    eq(party:IsShown(), false)
    eq(NS.IsBlizzardFrameHidden("CompactRaidFrameContainer"), false)
    truthy(Mock.FindPrinted("/reload"))
end)

test("groupe : raid de dix, tri par classe", function()
    reset()
    Enable()
    Mock.SetGroup(10, true)
    eq(#GF.headers.raid.children, 10)
    truthy(GF:GetButton("raid7"))
    GF.db.raidSortBy = "CLASS"
    NS.Modules:Refresh("groupframes")
    eq(GF.headers.raid:GetAttribute("groupBy"), "CLASS")
    GF.db.raidSortBy = "GROUP"
    Disable()
end)

test("groupe : bordure dispel selon la classe du joueur, agro rouge", function()
    reset()
    Mock.units.player.class = "PRIEST"
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    Mock.debuffs.party1 = { { icon = "p", dispelName = "Poison" } }
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.border.top.color[1], NS.db.theme.border.r, "poison : prêtre ne dissipe pas")
    Mock.debuffs.party1 = { { icon = "m", dispelName = "Magic" } }
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.border.top.color[3], 1, "magie : bordure bleue")
    Mock.debuffs.party1 = { { icon = "s", dispelName = Mock.SetSecret("Curse") } }
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.border.top.color[1], NS.db.theme.border.r, "type secret : rien")
    Mock.units.party1.threat = 3
    Mock.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "party1")
    eq(ami.border.top.color[1], 0.9, "agro : rouge")
    Mock.units.player.class = "MAGE"
    Disable()
end)

test("groupe : portée, rôle, chef", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    Mock.units.party1.inRange = false
    Mock.Advance(0.3)
    eq(ami:GetAlpha(), 0.4, "hors de portée")
    Mock.units.party1.inRange = true
    Mock.Advance(0.3)
    eq(ami:GetAlpha(), 1)
    Mock.roles.party1 = "HEALER"
    Mock.units.party1.leader = true
    Mock.FireEvent("PLAYER_ROLES_ASSIGNED")
    truthy(ami.role:IsShown(), "icône de rôle")
    truthy(ami.leader:IsShown(), "icône de chef")
    Mock.roles.party1 = "NONE"
    Mock.FireEvent("PLAYER_ROLES_ASSIGNED")
    eq(ami.role:IsShown(), false)
    Disable()
end)

test("groupe : en combat différé, ElvUI cède, options construites", function()
    reset()
    Mock.SetCombat(true)
    eq(NS.Modules:SetEnabled("groupframes", true), "deferred")
    Mock.SetCombat(false)
    truthy(GF.enabled)
    NS.Options:BuildMain()
    Disable()
    Mock.loadedAddons.ElvUI = true
    Enable()
    eq(GF.enabled, false)
    Mock.loadedAddons.ElvUI = nil
    NS.db.modules.groupframes.enabled = false
end)

test("groupe : nom tronqué (UTF-8), tri par rôle, seuil raid 10", function()
    reset()
    eq(Elements.TruncateName("Élodiebrune", 6), "Élodie")
    eq(Elements.TruncateName("Bob", 8), "Bob")
    eq(Elements.TruncateName("Bob", 0), "Bob", "0 = entier")
    Enable()
    Mock.SetGroup(3)
    Mock.units.party1.name = "Aurelienlelong"
    Mock.FireEvent("UNIT_NAME_UPDATE", "party1")
    eq(GF:GetButton("party1").name:GetText(), "Aurelien", "8 caractères par défaut")
    GF.db.raidSortBy = "ROLE"
    GF.db.raidThreshold = 10
    NS.Modules:Refresh("groupframes")
    eq(GF.headers.raid:GetAttribute("groupBy"), "ASSIGNEDROLE")
    eq(GF.headers.party:GetAttribute("showRaid"), true, "seuil 10 : l'en-tête de groupe montre un petit raid")
    eq(GF.headers.party:GetAttribute("maxColumns"), 2)
    truthy(Mock.stateDrivers[GF.headers.raid].visibility:find("@raid11", 1, true), "raid visible à partir de 11 membres")
    GF.db.raidSortBy, GF.db.raidThreshold = "GROUP", 5
    NS.Modules:Refresh("groupframes")
    eq(GF.headers.party:GetAttribute("showRaid"), false)
    Disable()
end)
