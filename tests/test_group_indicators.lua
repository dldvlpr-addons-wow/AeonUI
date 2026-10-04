-- tests/test_group_indicators.lua : étape 12, indicateurs de groupe (appel, invocation, résurrection,
-- prédiction de soins, portrait, menace en bordure ou lueur, tanks et assistants principaux).
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset
local GF = NS.Modules:Get("groupframes")
local Elements = NS.UnitFrameElements

local function Enable() NS.Modules:SetEnabled("groupframes", true) end
local function Disable() NS.Modules:SetEnabled("groupframes", false) end

test("indicateurs : appel prêt affiché puis effacé après le délai", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    Mock.SetGroup(3, false)
    local absent = GF:GetButton("party2")
    local states = { party1 = "waiting", party2 = "waiting" }
    _G.GetReadyCheckStatus = function(unit) return states[unit] end
    Mock.FireEvent("READY_CHECK")
    truthy(ami.status:IsShown())
    truthy(ami.status.texture:find("Waiting"), "en attente")
    states.party1 = "ready"
    Mock.FireEvent("READY_CHECK_CONFIRM", "party1")
    truthy(ami.status.texture:find("Ready"), "prêt")
    states = {}   -- l'API ne répond plus après la fin : état mémorisé
    Mock.FireEvent("READY_CHECK_FINISHED")
    truthy(ami.status:IsShown(), "résultat encore affiché")
    truthy(ami.status.texture:find("Ready"), "prêt mémorisé")
    truthy(absent.status.texture:find("NotReady"), "en attente à la fin : pas prêt")
    Mock.Advance(7)
    eq(ami.status:IsShown(), false, "effacé après le délai")
    _G.GetReadyCheckStatus = nil
    Disable()
end)

test("indicateurs : invocation puis résurrection ; secret ou option coupée = rien", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    local summon = 1
    _G.C_IncomingSummon = { IncomingSummonStatus = function() return summon end }
    Mock.missingAtlas["Raid-Icon-SummonPending"] = true
    Mock.FireEvent("INCOMING_SUMMON_CHANGED", "party1")
    eq(ami.status:IsShown(), false, "atlas absent : rien")
    Mock.missingAtlas = {}
    Mock.FireEvent("INCOMING_SUMMON_CHANGED", "party1")
    eq(ami.status.atlas, "Raid-Icon-SummonPending")
    truthy(ami.status:IsShown())
    summon = 0
    local rez = true
    _G.UnitHasIncomingResurrection = function() return rez end
    Mock.FireEvent("INCOMING_RESURRECT_CHANGED", "party1")
    truthy(ami.status.texture:find("Rez"), "résurrection")
    rez = Mock.SetSecret("rez?")
    Mock.FireEvent("INCOMING_RESURRECT_CHANGED", "party1")
    eq(ami.status:IsShown(), false, "secret : rien")
    rez = true
    GF.db.statusIcons = false
    NS.Modules:Refresh("groupframes")
    eq(ami.status:IsShown(), false, "option coupée")
    GF.db.statusIcons = true
    _G.C_IncomingSummon, _G.UnitHasIncomingResurrection = nil, nil
    Disable()
end)

test("indicateurs : menace orange ou rouge, en bordure ou en lueur", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    GF.db.aggroStyle = "border"
    NS.Modules:Refresh("groupframes")
    Mock.units.party1.threat = 2
    Mock.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "party1")
    eq(ami.border.top.color[1], 1, "orange en bordure")
    eq(ami.border.top.color[2], 0.6)
    eq(ami.glow:IsShown(), false)
    GF.db.aggroStyle = "glow"
    NS.Modules:Refresh("groupframes")
    truthy(ami.glow:IsShown(), "lueur")
    eq(ami.border.top.color[1], NS.db.theme.border.r, "bordure au thème en mode lueur")
    Mock.units.party1.threat = Mock.SetSecret(3)
    Mock.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "party1")
    eq(ami.glow:IsShown(), false, "menace secrète : rien")
    Disable()
end)

test("indicateurs : prédiction de soins et absorption, valeurs secrètes passées au widget", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    eq(ami.healPrediction:IsShown(), false, "client sans API : caché")
    _G.UnitGetIncomingHeals = function() return 150 end
    local secret = Mock.SetSecret(40)
    _G.UnitGetTotalAbsorbs = function() return secret end
    Mock.FireEvent("UNIT_HEAL_PREDICTION", "party1")
    truthy(ami.healPrediction:IsShown())
    eq(ami.healPrediction:GetValue(), 150)
    eq(ami.absorb:GetValue(), secret, "absorption secrète posée telle quelle")
    _G.UnitGetIncomingHeals = function() return nil end
    Mock.FireEvent("UNIT_HEAL_PREDICTION", "party1")
    eq(ami.healPrediction:GetValue(), 0, "rien d'entrant : 0")
    GF.db.healPrediction = false
    NS.Modules:Refresh("groupframes")
    eq(ami.healPrediction:IsShown(), false, "option coupée")
    GF.db.healPrediction = true
    _G.UnitGetIncomingHeals, _G.UnitGetTotalAbsorbs = nil, nil
    Disable()
end)

test("indicateurs : cadres des tanks principaux, unité présente deux fois", function()
    reset()
    Enable()
    truthy(not (GF.headers.tank and GF.headers.tank:IsShown()), "coupés par défaut")
    GF.db.mainTanks = true
    NS.Modules:Refresh("groupframes")
    local tank = GF.headers.tank
    truthy(tank)
    eq(tank:GetAttribute("groupFilter"), "MAINTANK")
    truthy(Mock.stateDrivers[tank].visibility:find("group:raid"))
    truthy(NS.Movers:Anchor("uf_tank"))
    Mock.SetGroup(10, true)
    Mock.units.raid3.assignment = "MAINTANK"
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    eq(#tank.children, 1)
    local inRaid, inTank = GF:GetButton("raid3"), GF:GetButton("raid3", "tank")
    truthy(inRaid and inTank and inRaid ~= inTank, "deux boutons pour raid3")
    Mock.units.raid3.health = 300
    Mock.FireEvent("UNIT_HEALTH", "raid3")
    eq(inRaid.health:GetValue(), 300)
    eq(inTank.health:GetValue(), 300, "les deux suivent")
    GF.db.mainTanks = false
    NS.Modules:Refresh("groupframes")
    eq(tank:IsShown(), false)
    Disable()
end)

test("indicateurs : portrait des cadres d'unité en option", function()
    reset()
    local db = NS.db.modules.unitframes
    local calls = 0
    _G.SetPortraitTexture = function() calls = calls + 1 end
    NS.Modules:SetEnabled("unitframes", true)
    local frame = NS.Modules:Get("unitframes").frames.player
    eq(frame.portrait:IsShown(), false, "coupé par défaut")
    db.units.player.portrait = true
    NS.Modules:Refresh("unitframes")
    truthy(frame.portrait:IsShown())
    Elements.UpdatePortrait(frame)
    truthy(calls > 0, "portrait posé")
    db.units.player.portrait = false
    NS.Modules:SetEnabled("unitframes", false)
    _G.SetPortraitTexture = nil
end)

test("indicateurs : croissance du raid, groupes affichés, groupe inversé", function()
    reset()
    Enable()
    local raid, party = GF.headers.raid, GF.headers.party
    eq(raid:GetAttribute("point"), "TOP"); eq(raid:GetAttribute("columnAnchorPoint"), "LEFT")
    eq(raid:GetAttribute("groupFilter"), nil, "8 groupes : pas de filtre")
    GF.db.raidUnitGrowth, GF.db.raidGroupGrowth, GF.db.raidGroups = "LEFT", "UP", 5
    NS.Modules:Refresh("groupframes")
    eq(raid:GetAttribute("point"), "RIGHT")
    truthy(raid:GetAttribute("xOffset") < 0 and raid:GetAttribute("yOffset") == 0)
    eq(raid:GetAttribute("columnAnchorPoint"), "BOTTOM")
    eq(raid:GetAttribute("groupFilter"), "1,2,3,4,5")
    GF.db.raidGroupGrowth = "RIGHT"
    NS.Modules:Refresh("groupframes")
    eq(raid:GetAttribute("columnAnchorPoint"), "TOP", "même axe que les membres : corrigé")
    local horizontal = GF.db.horizontal
    GF.db.reverse, GF.db.horizontal = true, false
    NS.Modules:Refresh("groupframes")
    eq(party:GetAttribute("point"), "BOTTOM")
    truthy(party:GetAttribute("yOffset") > 0)
    GF.db.horizontal = true
    NS.Modules:Refresh("groupframes")
    eq(party:GetAttribute("point"), "RIGHT", "ligne inversée : vers la gauche")
    eq(party:GetAttribute("columnAnchorPoint"), "TOP")
    GF.db.raidUnitGrowth, GF.db.raidGroupGrowth, GF.db.raidGroups, GF.db.reverse = "DOWN", "RIGHT", 8, false
    GF.db.horizontal = horizontal
    Disable()
end)

test("indicateurs : rôle par style, filtre par rôle, caché en combat", function()
    reset()
    Enable()
    Mock.SetGroup(3, false)
    Mock.roles.party1, Mock.roles.party2 = "TANK", "DAMAGER"
    GF.db.roleShowDamager = true
    NS.Modules:Refresh("groupframes")
    local tank, dps = GF:GetButton("party1"), GF:GetButton("party2")
    truthy(tank.role:IsShown() and dps.role:IsShown())
    GF.db.roleShowDamager = false
    GF.db.roleIconStyle = "tiny"
    NS.Modules:Refresh("groupframes")
    eq(dps.role:IsShown(), false, "dégâts masqués")
    eq(tank.role.atlas, "roleicon-tiny-tank")
    Mock.missingAtlas["roleicon-tiny-tank"] = true
    GF:UpdateRole(tank)
    eq(tank.role.texture, "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", "atlas absent : portrait")
    Mock.missingAtlas["roleicon-tiny-tank"] = nil
    GF.db.roleHideInCombat = true
    Mock.combat = true
    Mock.FireEvent("PLAYER_REGEN_DISABLED")
    eq(tank.role:IsShown(), false, "caché en combat")
    Mock.combat = false
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    truthy(tank.role:IsShown())
    GF.db.roleIconStyle, GF.db.roleHideInCombat = "portrait", false
    Disable()
end)

test("indicateurs : offre de résurrection gardée 60 s, icônes d'état séparées", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    local casting = true
    _G.UnitHasIncomingResurrection = function() return casting end
    Mock.units.party1.dead = true
    Mock.FireEvent("INCOMING_RESURRECT_CHANGED", "party1")
    truthy(ami.status:IsShown(), "incantation")
    casting = false
    Mock.FireEvent("INCOMING_RESURRECT_CHANGED", "party1")
    truthy(ami.status:IsShown(), "offre à accepter")
    GF.db.rezIcons = false
    GF:UpdateStatus(ami)
    eq(ami.status:IsShown(), false, "option coupée")
    GF.db.rezIcons = true
    Mock.units.party1.dead = false
    Mock.FireEvent("UNIT_HEALTH", "party1")
    eq(ami.status:IsShown(), false, "relevé : icône retirée")
    Mock.units.party1.dead = true
    casting = true
    Mock.FireEvent("INCOMING_RESURRECT_CHANGED", "party1")
    casting = false
    Mock.FireEvent("INCOMING_RESURRECT_CHANGED", "party1")
    Mock.Advance(61, 1)
    eq(ami.status:IsShown(), false, "offre expirée")
    _G.UnitHasIncomingResurrection = nil
    Disable()
end)

test("indicateurs : dispel de tout type avec lueur, soins absorbés", function()
    reset()
    Mock.units.player.class = "MAGE"
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    Mock.debuffs.party1 = { { icon = "p", dispelName = "Poison" } }
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.border.top.color[1], NS.db.theme.border.r, "mage : poison ignoré")
    GF.db.dispelMode, GF.db.dispelGlow = "all", true
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.border.top.color[2], DebuffTypeColor.Poison.g, "tout type : poison signalé")
    eq(NS.Glow.Current(ami), "pixel")
    Mock.debuffs.party1 = {}
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(NS.Glow.Current(ami), nil, "lueur éteinte")
    GF.db.dispelMode, GF.db.dispelGlow = "mine", false
    _G.UnitGetTotalHealAbsorbs = function() return 30 end
    Mock.FireEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "party1")
    truthy(ami.healAbsorb:IsShown())
    eq(ami.healAbsorb:GetValue(), 30)
    _G.UnitGetTotalHealAbsorbs = nil
    Disable()
end)

test("indicateurs : mana des soigneurs en texte", function()
    reset()
    GF.db.healerMana = "party"
    Enable()
    Mock.SetGroup(3, false)
    Mock.roles.party2 = "HEALER"
    Mock.FireEvent("PLAYER_ROLES_ASSIGNED")
    local row = GF.manaUnits.party2
    truthy(row and row.name:IsShown(), "ligne du soigneur")
    eq(GF.manaUnits.party1, nil)
    eq(row.name:GetText(), Mock.units.party2.name)
    truthy(NS.Movers:Anchor("uf_healermana"))
    GF.db.healerMana = "raid"
    NS.Modules:Refresh("groupframes")
    eq(GF.manaUnits.party2, nil, "raid seulement : rien en groupe")
    GF.db.healerMana = "none"
    Disable()
end)
