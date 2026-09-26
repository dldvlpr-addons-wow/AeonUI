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
    NS.db.modules.resourcebars.visibility = "combat"
    RB:OnRefresh()
    eq(bars.power.holder:IsShown(), false, "hors combat sans cible")
    Mock.SetCombat(true)
    RB:Update("PLAYER_REGEN_DISABLED")
    truthy(bars.power.holder:IsShown(), "en combat")
    Mock.units.player.power = Mock.SetSecret(12)
    Mock.FireEvent("UNIT_POWER_FREQUENT", "player")
    truthy(NS.IsSecret(bars.power.value), "secret transmis sans comparaison")
    Mock.SetCombat(false)
    NS.db.modules.resourcebars.visibility = "always"
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
