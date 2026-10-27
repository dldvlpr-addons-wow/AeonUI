-- tests/test_g_ressources.lua : barres de ressources (orientation propre, mana forcé, texte, absorptions),
-- barres d'auras (tri), rappels (son d'équipement), gestionnaire de recharges (opacité, strate, liseré).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("ressources : orientation propre à une barre, strate et ancre du texte", function()
    reset()
    local RB = NS.Modules:Get("resourcebars")
    Mock.units.player.power, Mock.units.player.powerMax, Mock.units.player.powerType = 40, 100, "MANA"
    local db = NS.db.modules.resourcebars
    db.orientation, db.healthOrientation, db.health = "HORIZONTAL", "VERTICAL", true
    db.strata, db.powerTextAnchor, db.powerTextX = "HIGH", "LEFT", 5
    NS.Modules:SetEnabled("resourcebars", true)
    local bars = RB:GetBars()
    eq(bars.health.vertical, true, "vie verticale")
    eq(bars.power.vertical, false, "puissance : orientation commune")
    eq(bars.health.holder:GetWidth(), db.healthHeight, "épaisseur en largeur")
    eq(bars.power.holder:GetFrameStrata(), "HIGH")
    local point, _, relative, x = bars.power.text:GetPoint(bars.power.text:GetNumPoints())
    eq(point, "LEFT"); eq(relative, "LEFT"); eq(x, 5)
    eq(bars.power.text:GetNumPoints(), 1, "ancre remplacée, pas ajoutée")
    NS.Modules:SetEnabled("resourcebars", false)
    db.healthOrientation, db.health, db.strata, db.powerTextAnchor, db.powerTextX = "inherit", false, "MEDIUM", "CENTER", 0
end)

test("ressources : mana forcé en forme féline, repli sans mana, absorptions sans fond opaque", function()
    reset()
    local RB = NS.Modules:Get("resourcebars")
    local u = Mock.units.player
    u.power, u.powerMax, u.powerType = 30, 100, "ENERGY"
    local manaMax = 200
    local oldPower, oldMax, oldAbsorbs = UnitPower, UnitPowerMax, _G.UnitGetTotalAbsorbs
    _G.UnitPower = function(unit, kind) if kind == 0 then return 77 end return oldPower(unit, kind) end
    _G.UnitPowerMax = function(unit, kind) if kind == 0 then return manaMax end return oldMax(unit, kind) end
    _G.UnitGetTotalAbsorbs = function() return 42 end
    local db = NS.db.modules.resourcebars
    db.powerForceMana, db.powerText, db.health, db.healthAbsorb = true, "current", true, true
    NS.Modules:SetEnabled("resourcebars", true)
    local bars = RB:GetBars()
    eq(bars.power:GetValue(), 77, "valeur de mana")
    eq(select(2, bars.power:GetMinMaxValues()), 200, "maximum de mana")
    truthy(bars.power.text:GetText() ~= nil, "texte posé")
    truthy(bars.health.absorb:IsShown(), "absorption affichée")
    eq(bars.health.absorb:GetValue(), 42, "montant d'absorption")
    eq(bars.health.absorb.bg, nil, "overlay sans fond opaque")
    -- Classe sans mana : l'option est ignorée, la puissance propre reste.
    manaMax = 0
    NS.Modules:Refresh("resourcebars")
    eq(bars.power:GetValue(), 30, "guerrier : puissance conservée")
    truthy(bars.power.holder:IsShown(), "barre de puissance visible")
    db.healthAbsorb = false
    NS.Modules:Refresh("resourcebars")
    eq(bars.health.absorb:IsShown(), false, "absorption coupée")
    NS.Modules:SetEnabled("resourcebars", false)
    _G.UnitPower, _G.UnitPowerMax, _G.UnitGetTotalAbsorbs = oldPower, oldMax, oldAbsorbs
    db.powerForceMana, db.health, db.powerText = false, false, "current"
end)

test("barres d'auras : tri par durée restante décroissante ou par nom", function()
    reset()
    local AuraBars = NS.Modules:Get("aurabars")
    local previous = C_UnitAuras.GetAuraDataByIndex
    local auras = { HELPFUL = {
        { name = "Zeal", icon = 1, duration = 100, expirationTime = Mock.now + 90 },
        { name = "Aegis", icon = 2, duration = 30, expirationTime = Mock.now + 10 },
        { name = "Might", icon = 3, duration = 600, expirationTime = Mock.now + 500 } } }
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        return unit == "player" and auras[filter] and auras[filter][index] or nil
    end
    NS.Modules:SetEnabled("aurabars", true)
    local db = NS.db.modules.aurabars
    local function Names()
        local names = {}
        for _, entry in ipairs(AuraBars.Collect()) do names[#names + 1] = entry.name end
        return table.concat(names, ",")
    end
    eq(Names(), "Aegis,Zeal,Might", "défaut : la plus courte d'abord")
    db.sort = "longest"
    eq(Names(), "Might,Zeal,Aegis")
    db.sort = "name"
    eq(Names(), "Aegis,Might,Zeal")
    db.sort = "shortest"
    NS.Modules:SetEnabled("aurabars", false)
    C_UnitAuras.GetAuraDataByIndex = previous
end)

test("rappels : son propre aux rappels d'équipement", function()
    reset()
    local Reminders = NS.Modules:Get("reminders")
    local db = Reminders.db
    db.gearSoundOwn, db.gearSoundPreset, db.soundPreset = true, "readycheck", "alarm"
    NS.Modules:SetEnabled("reminders", true)
    Mock.durability[1] = nil
    Reminders:Evaluate()   -- vide la liste des rappels déjà affichés
    Mock.Advance(2.1)
    Mock.sounds = {}
    Mock.durability[1] = { 10, 100 }
    Reminders:Evaluate()
    eq(#Mock.sounds, 1, "un son")
    local gearKit = Mock.sounds[1].kit
    db.gearSoundOwn = false
    Mock.durability[1] = nil
    Reminders:Evaluate()
    Mock.Advance(2.1)
    Mock.sounds = {}
    Mock.durability[1] = { 10, 100 }
    Reminders:Evaluate()
    eq(#Mock.sounds, 1)
    truthy(Mock.sounds[1].kit ~= gearKit, "son principal sans option")
    db.soundPreset, db.gearSoundPreset = "ping", "ping"
    NS.Modules:SetEnabled("reminders", false)
    Mock.durability[1] = nil
end)

test("gestionnaire de recharges : opacité propre, strate rendue à la coupure, liseré permanent", function()
    reset()
    local CDM = NS.Modules:Get("cooldownmanager")
    local essential = EssentialCooldownViewer
    local cfg = NS.db.modules.cooldownmanager.skin.essential
    local item = CreateFrame("Frame", nil, essential)
    local drawEdge = false
    item.cooldownFrame = { SetDrawEdge = function(_, on) drawEdge = on end, GetDrawEdge = function() return drawEdge end }
    function item:GetCooldownFrame() return self.cooldownFrame end
    essential.itemFramePool = { EnumerateActive = function() local done = false return function() if not done then done = true return item end end end }
    cfg.opacity, cfg.strata, cfg.edge = 0.5, "HIGH", true
    local before = essential:GetFrameStrata()
    NS.Modules:SetEnabled("cooldownmanager", true)
    Mock.Advance(0.1)
    eq(essential:GetFrameStrata(), "HIGH", "strate posée")
    eq(drawEdge, true, "liseré forcé")
    eq(math.abs(essential:GetAlpha() - 0.5 * NS.GetCooldownViewerOpacity(essential)) < 0.001, true, "opacité multipliée")
    NS.Modules:SetEnabled("cooldownmanager", false)
    eq(essential:GetFrameStrata(), before, "strate d'origine rendue")
    eq(drawEdge, false, "liseré d'origine rendu")
    cfg.opacity, cfg.strata, cfg.edge = 1, "default", false
    essential.itemFramePool = nil
end)
