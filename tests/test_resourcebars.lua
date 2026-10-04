-- tests/test_resourcebars.lua
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local RB = NS.Modules:Get("resourcebars")

local function enable()
    reset()
    local u = Mock.units.player
    u.power, u.powerMax, u.powerType = 40, 100, "MANA"
    NS.Modules:SetEnabled("resourcebars", true)
    return RB:GetBars()
end

local function disable()
    NS.Modules:SetEnabled("resourcebars", false)
    for _, key in ipairs({ "resourceHealth", "resourcePower", "resourceCombo", "resourceDruidMana" }) do
        NS.db.anchors[key] = nil
    end
end

test("barres de ressources : puissance suivie, un mover par barre, retirés à la désactivation", function()
    local bars = enable()
    truthy(bars.power.holder:IsShown(), "puissance affichée")
    eq(bars.power.value, 40)
    eq(bars.health.holder:IsShown(), false, "vie désactivée par défaut")
    truthy(NS.Movers.registry.resourcePower, "mover enregistré")
    Mock.units.player.power = 75
    Mock.FireEvent("UNIT_POWER_FREQUENT", "player")
    eq(bars.power.value, 75, "mise à jour à l'événement")
    eq(bars.power.holder:GetWidth(), NS.db.modules.resourcebars.width)
    disable()
    eq(bars.power.holder:IsShown(), false)
    eq(NS.Movers.registry.resourcePower, nil, "mover retiré")
end)

test("barres de ressources : combo seulement si la classe en a, mana de druide seulement en forme", function()
    local bars = enable()
    eq(bars.combo.holder:IsShown(), false, "pas de points de combo")
    eq(bars.druidMana.holder:IsShown(), false, "puissance = mana : pas de barre de mana en plus")
    Mock.units.player.comboMax, Mock.units.player.combo = 5, 3
    Mock.units.player.powerType = "ENERGY"
    Mock.FireEvent("UPDATE_SHAPESHIFT_FORM")
    truthy(bars.combo.holder:IsShown(), "points de combo")
    eq(bars.combo.value, 3)
    truthy(bars.druidMana.holder:IsShown(), "forme féline : mana affiché")
    disable()
end)

test("barres de ressources : « en combat » masque hors combat, valeur secrète passée telle quelle", function()
    local bars = enable()
    NS.db.modules.resourcebars.visibility = NS.Visibility.Spec({ match = "any", combat = "yes", target = "yes" })
    RB:OnRefresh()
    eq(bars.power.holder:IsShown(), false, "hors combat sans cible")
    Mock.SetCombat(true)
    RB:Update("PLAYER_REGEN_DISABLED")
    truthy(bars.power.holder:IsShown(), "en combat")
    Mock.units.player.power = Mock.SetSecret(12)
    Mock.FireEvent("UNIT_POWER_FREQUENT", "player")
    truthy(NS.IsSecret(bars.power.value), "secret transmis sans comparaison")
    Mock.SetCombat(false)
    NS.db.modules.resourcebars.visibility = NS.Visibility.Spec()
    disable()
end)

test("barres de ressources : verticales, longueur en hauteur et graduations couchées", function()
    local bars = enable()
    local db = NS.db.modules.resourcebars
    db.orientation = "VERTICAL"
    Mock.units.player.comboMax, Mock.units.player.combo = 5, 2
    Mock.units.player.powerType = "ENERGY"
    RB:OnRefresh()
    eq(bars.power.holder:GetWidth(), db.powerHeight, "épaisseur en largeur")
    eq(bars.power.holder:GetHeight(), db.width, "longueur en hauteur")
    eq(bars.power:GetOrientation(), "VERTICAL")
    eq(bars.combo.ticks[1].points[1][1], "LEFT", "graduation horizontale")
    db.orientation = "HORIZONTAL"
    RB:OnRefresh()
    eq(bars.power.holder:GetWidth(), db.width, "retour à l'horizontale")
    eq(bars.combo.ticks[1].points[1][1], "TOP")
    Mock.units.player.comboMax, Mock.units.player.combo, Mock.units.player.powerType = nil, nil, "MANA"
    disable()
end)

test("barres de ressources : paliers de couleur, repères, courbe du moteur si secret", function()
    local bars = enable()
    local db = NS.db.modules.resourcebars
    db.powerLow, db.powerMid, db.threshold, db.powerHashLines = 30, 50, 50, "25, 75, 120"
    RB:OnRefresh()
    local mid = db.powerMidColor
    eq(bars.power.barColor[1], mid.r, "40 % : second palier")
    Mock.units.player.power = 20
    Mock.FireEvent("UNIT_POWER_FREQUENT", "player")
    eq(bars.power.barColor[1], db.powerLowColor.r, "20 % : premier palier")
    Mock.units.player.power = 90
    Mock.FireEvent("UNIT_POWER_FREQUENT", "player")
    eq(bars.power.barColor[3], 1, "au-dessus : couleur de mana")
    local lines = 0
    for _, line in ipairs(bars.power.hashLines) do if line:IsShown() then lines = lines + 1 end end
    eq(lines, 3, "25, 75 et le repère à 50 ; 120 ignoré")
    -- Valeur secrète : le moteur évalue la courbe en paliers.
    _G.UnitPowerPercent = function(_, _, _, curve) return Mock.EvaluateCurve(curve, 0.2) end
    Mock.units.player.power = Mock.SetSecret(20)
    Mock.FireEvent("UNIT_POWER_FREQUENT", "player")
    eq(bars.power.barColor[1], db.powerLowColor.r, "courbe : premier palier")
    _G.UnitPowerPercent = nil
    db.powerLow, db.powerMid, db.threshold, db.powerHashLines = 0, 0, 0, ""
    disable()
end)

test("barre de recharge globale : montrée pendant la recharge, cachée à la fin, placée déverrouillée", function()
    reset()
    local cooldown
    C_Spell.GetSpellCooldown = function(id) if id == 61304 then return cooldown end end
    NS.Modules:SetEnabled("gcdbar", true)
    local holder = _G.AeonUIGCDBar
    eq(holder:IsShown(), false, "hors recharge : cachée")
    truthy(NS.Movers.registry.gcdBar, "mover enregistré")
    cooldown = { startTime = GetTime(), duration = 1.5 }
    Mock.FireEvent("SPELL_UPDATE_COOLDOWN")
    truthy(holder:IsShown(), "recharge : montrée")
    cooldown = nil
    Mock.Advance(1.6)
    eq(holder:IsShown(), false, "cachée à la fin")
    cooldown = { startTime = GetTime(), duration = Mock.SetSecret(1.5) }
    Mock.FireEvent("SPELL_UPDATE_COOLDOWN")
    eq(holder:IsShown(), false, "durée secrète : rien")
    cooldown = nil
    NS:SetUnlocked(true)
    truthy(holder:IsShown(), "déverrouillée : visible")
    NS:SetUnlocked(false)
    eq(holder:IsShown(), false)
    NS.Modules:SetEnabled("gcdbar", false)
    eq(NS.Movers.registry.gcdBar, nil)
    NS.db.anchors.gcdBar = nil
    C_Spell.GetSpellCooldown = nil
end)
