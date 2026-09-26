-- tests/test_databars.lua : barres de données AeonUI (étape 6).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local DB = NS.Modules:Get("databars")

local function Enable() NS.Modules:SetEnabled("databars", true) end
local function Disable() NS.Modules:SetEnabled("databars", false) end

test("data bars : XP avec repos, réputation cachée sans faction, Blizzard caché sans reparentage", function()
    reset()
    Mock.units.player.level = 12
    Enable()
    local xp = DB.frames.xp
    truthy(xp:IsShown())
    eq(xp.bar:GetValue(), 250)
    eq(xp.rested:GetValue(), 350)
    truthy(xp.text:GetText():find("25.0 %%"))
    truthy(xp.text:GetText():find("+100", 1, true))
    eq(DB.frames.rep:IsShown(), false, "aucune faction suivie")
    truthy(NS.IsBlizzardFrameHidden("MainStatusTrackingBarContainer"))
    eq(MainStatusTrackingBarContainer:GetParent(), UIParent)
    truthy(NS.Movers:Anchor("databar_xp"))
    Mock.watchedFaction = { name = "Orgrimmar", standing = 5, min = 3000, max = 9000, value = 4500 }
    Mock.FireEvent("UPDATE_FACTION")
    local rep = DB.frames.rep
    truthy(rep:IsShown())
    eq(rep.bar:GetValue(), 1500)
    truthy(rep.text:GetText():find("Orgrimmar: Amical", 1, true))
    Disable()
    eq(xp:IsShown(), false)
    eq(NS.IsBlizzardFrameHidden("MainStatusTrackingBarContainer"), false)
    truthy(Mock.FindPrinted("/reload"))
end)

test("data bars : cachée au niveau max, valeurs secrètes acceptées", function()
    reset()
    Mock.units.player.level = 60
    Enable()
    eq(DB.frames.xp:IsShown(), false, "niveau max")
    Mock.units.player.level = 12
    Mock.xp.rested = Mock.SetSecret(100)
    Mock.FireEvent("PLAYER_XP_UPDATE")
    truthy(DB.frames.xp:IsShown())
    eq(DB.frames.xp.rested:IsShown(), false, "repos secret : pas de comparaison, barre de repos cachée")
    Disable()
end)
