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
    GF.db.aggroStyle = "border"
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
