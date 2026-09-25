-- tests/test_raidcooldowns.lua : minuteur d'attaque, rez en combat, Furie sanguinaire.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("recharges de raid : format du temps", function()
    local RC = NS.Modules:Get("raidcooldowns")
    eq(RC.FormatTime(42.4), "42")
    eq(RC.FormatTime(125), "2:05")
    eq(RC.FormatTime(-3), "0")
end)

test("recharges de raid : rez en combat en instance si le client donne des charges, verrou de Furie", function()
    reset()
    local RC = NS.Modules:Get("raidcooldowns")
    NS.Modules:SetEnabled("raidcooldowns", true)
    local icons = RC:GetIcons()
    eq(icons.battleRes:IsShown(), false, "pas de charges : rien")
    eq(icons.bloodlust:IsShown(), false, "pas d'affaiblissement : rien")
    C_Spell.GetSpellCharges = function(id)
        if id ~= 20484 then return nil end
        return { currentCharges = 2, maxCharges = 5, cooldownStartTime = GetTime(), cooldownDuration = 90 }
    end
    Mock.FireEvent("SPELL_UPDATE_CHARGES")
    eq(icons.battleRes:IsShown(), false, "hors instance : rien")
    Mock.instanceType = "raid"
    Mock.FireEvent("SPELL_UPDATE_CHARGES")
    truthy(icons.battleRes:IsShown(), "en raid")
    eq(icons.battleRes.text.text, "2 | 1:30")
    Mock.debuffs.player = { { icon = 99, duration = 600, expirationTime = GetTime() + 300, spellId = 57724 } }
    Mock.FireEvent("UNIT_AURA", "player")
    truthy(icons.bloodlust:IsShown(), "Rassasié")
    eq(icons.bloodlust.text.text, "5:00")
    C_Spell.GetSpellCharges = nil
    Mock.debuffs.player = nil
    NS.Modules:SetEnabled("raidcooldowns", false)
    eq(icons.battleRes:IsShown(), false)
    eq(NS.Movers.registry.battleRes, nil, "mover retiré")
end)

test("minuteur d'attaque : inerte sans C_SwingTimer, barre remplie puis vidée au coup", function()
    reset()
    local Swing = NS.Modules:Get("swingtimer")
    eq(Swing.Available(), false, "client sans C_SwingTimer")
    NS.Modules:SetEnabled("swingtimer", true)
    eq(NS.Movers.registry.swingTimer, nil, "inerte : pas de mover")
    NS.Modules:SetEnabled("swingtimer", false)
    _G.C_SwingTimer = {}
    NS.db.modules.swingtimer.combatOnly = false
    NS.Modules:SetEnabled("swingtimer", true)
    truthy(NS.Movers.registry.swingTimer, "mover")
    local container, bar = _G.AeonUISwingTimer, nil
    truthy(container:IsShown())
    Mock.FireEvent("PLAYER_SWING", 2.6, 0)
    for _, frame in ipairs(Mock.frames) do
        if frame.hand == "mainHand" then bar = frame end
    end
    eq(bar.value, 2.6, "barre pleine au coup")
    Mock.Advance(1)
    truthy(bar.value < 2.6 and bar.value > 0, "se vide")
    Mock.Advance(2)
    eq(bar.value, 0, "vide au coup suivant")
    NS.Modules:SetEnabled("swingtimer", false)
    NS.db.modules.swingtimer.combatOnly = true
    _G.C_SwingTimer = nil
end)
