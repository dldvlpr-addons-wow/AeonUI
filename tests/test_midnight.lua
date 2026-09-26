-- tests/test_midnight.lua : étape 10, afficher une valeur secrète sans la lire (texte de recharge
-- coloré, dégradé de vie par courbe, portée par booléen, identité secrète).
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset
local Elements = NS.UnitFrameElements

local function NewCooldown() return CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate") end

--------------------------------------------------------------------------------
-- Texte de recharge
--------------------------------------------------------------------------------

test("recharges : paliers croissants, couleurs posées, seuil d'expiration optionnel", function()
    local colors = { expiring = { r = 1, g = 0, b = 0 }, seconds = { r = 1, g = 1, b = 0 }, minutes = { r = 1, g = 1, b = 1 } }
    local points = NS.CooldownBreakpoints({ expiring = 3, colors = colors })
    eq(#points, 5)
    eq(points[1].threshold, 0)
    truthy(points[1].format:find("|cffff0000%.1f", 1, true), "rouge avec décimale")
    eq(points[2].threshold, 3)
    truthy(points[2].format:find("|cffffff00%.0f", 1, true), "secondes en jaune")
    eq(points[3].components[1].div, 60, "minutes")
    for i = 2, #points do truthy(points[i].threshold > points[i - 1].threshold, "croissant " .. i) end
    eq(#NS.CooldownBreakpoints({ expiring = 0, colors = colors }), 4, "seuil 0 : pas de palier rouge")
end)

test("recharges : l'option pose le formateur sur les recharges enregistrées, le retire à la coupure", function()
    reset()
    local db = NS.db.modules.interface
    NS.Modules:SetEnabled("interface", true)
    local cooldown = NewCooldown()
    NS.RegisterCooldown(cooldown)
    eq(cooldown.countdownFormatter, nil, "coupé par défaut")
    db.cooldownColors = true
    NS.Modules:Refresh("interface")
    truthy(cooldown.countdownFormatter and cooldown.countdownFormatter.breakpoints, "formateur posé")
    eq(Mock.cvars.countdownForCooldowns, "1", "compte à rebours natif allumé pour le texte coloré")
    eq(cooldown.hideCountdown, false, "chiffres affichés")
    local late = NewCooldown()
    NS.RegisterCooldown(late)
    truthy(late.countdownFormatter, "recharge créée après coup : stylée à l'enregistrement")
    db.cooldownExpiring = 0
    NS.Modules:Refresh("interface")
    eq(#cooldown.countdownFormatter.breakpoints, 4, "réglage suivi sans /reload")
    db.cooldownColors, db.cooldownExpiring = false, 3
    NS.Modules:Refresh("interface")
    eq(cooldown.countdownFormatter, nil, "retiré")
    eq(Mock.cvars.countdownForCooldowns, "0", "CVar rendue")
    eq(cooldown.hideCountdown, false, "valeur par défaut du modèle : la CVar décide")
end)

test("recharges : sans formateur natif, rien n'est touché", function()
    reset()
    local saved = _G.C_StringUtil
    _G.C_StringUtil = nil
    NS.db.modules.interface.cooldownColors = true
    NS.Modules:Refresh("interface")
    local cooldown = NewCooldown()
    NS.RegisterCooldown(cooldown)
    eq(cooldown.countdownFormatter, nil)
    _G.C_StringUtil = saved
    NS.db.modules.interface.cooldownColors = false
    NS.Modules:Refresh("interface")
end)

test("recharges : les barres d'action AeonUI s'enregistrent", function()
    reset()
    NS.db.modules.interface.cooldownColors = true
    NS.Modules:Refresh("interface")
    NS.Modules:SetEnabled("actionbars", true)
    local button = NS.Modules:Get("actionbars"):GetBar(1).buttons[1]
    truthy(button.cooldown.countdownFormatter, "bouton de barre stylé")
    NS.Modules:SetEnabled("actionbars", false)
    NS.db.modules.interface.cooldownColors = false
    NS.Modules:Refresh("interface")
end)

--------------------------------------------------------------------------------
-- Dégradé de vie
--------------------------------------------------------------------------------

test("vie en dégradé : courbe moteur malgré une vie secrète, repli Lua, sinon couleur de classe", function()
    reset()
    local curveSeen
    _G.UnitHealthPercent = function(unit, _, curve)
        curveSeen = curve
        return Mock.EvaluateCurve(curve, 0.2)
    end
    Mock.units.player.health = Mock.SetSecret(20)
    local applied, r, g, b = NS.HealthGradient("player")
    truthy(curveSeen and #curveSeen.points == 3, "courbe à trois points passée au moteur")
    eq(applied, true) eq(r, 0.85) eq(g, 0.2) eq(b, 0.2)
    _G.UnitHealthPercent = nil
    eq(NS.HealthGradient("player"), false, "sans moteur et vie secrète : rien")
    Mock.units.player.health = 50
    applied, r, g = NS.HealthGradient("player")
    eq(applied, true) eq(r, 0.9) eq(g, 0.8)
    local frame = { unit = "player", global = { healthGradient = true, classColor = true, healthText = "none" },
                    health = CreateFrame("StatusBar") }
    frame.health.text = frame.health:CreateFontString()
    frame.health.SetStatusBarColor = function(self, ...) self.color = { ... } end
    Elements.UpdateHealth(frame)
    eq(frame.health.color[1], 0.9, "dégradé posé sur la barre")
    frame.global.healthGradient = false
    Elements.UpdateHealth(frame)
    eq(frame.health.color[1], select(1, NS.ClassColor("MAGE")), "option coupée : classe")
    Mock.units.player.health = 100
end)

--------------------------------------------------------------------------------
-- Portée
--------------------------------------------------------------------------------

test("portée : booléen secret confié au moteur, repli plein si pas d'API", function()
    reset()
    Mock.units.party1 = { name = "Ami", class = "PRIEST", isPlayer = true, inRange = false }
    local frame = CreateFrame("Frame")
    NS.SetRangeAlpha(frame, "party1", 0.4)
    eq(frame:GetAlpha(), 0.4, "hors de portée lisible")
    local realInRange = _G.UnitInRange
    _G.UnitInRange = function() return Mock.SetSecret("portée"), true end
    NS.SetRangeAlpha(frame, "party1", 0.4)
    eq(frame:GetAlpha(), 1, "secret sans API : plein")
    frame.SetAlphaFromBoolean = function(self, value, a, b) self.fromBoolean = { value, a, b } end
    NS.SetRangeAlpha(frame, "party1", 0.4)
    eq(frame.fromBoolean[2], 1) eq(frame.fromBoolean[3], 0.4, "le moteur choisit")
    _G.UnitInRange = function() return Mock.SetSecret("portée"), Mock.SetSecret("vérifiée") end
    frame.fromBoolean = nil
    NS.SetRangeAlpha(frame, "player", 0.4)
    eq(frame.fromBoolean, nil, "vérification secrète, soi-même : plein")
    eq(frame:GetAlpha(), 1)
    _G.UnitInRange = function() return false, false end
    frame.fromBoolean = nil
    NS.SetRangeAlpha(frame, "party1", 0.4)
    eq(frame.fromBoolean, nil, "portée non vérifiée : pas de décision")
    eq(frame:GetAlpha(), 1)
    _G.UnitInRange = realInRange
end)

--------------------------------------------------------------------------------
-- Identité secrète
--------------------------------------------------------------------------------

test("identité secrète : pas de couleur de classe, infobulle sans détails", function()
    reset()
    Mock.units.mouseover = { name = "Thrall", class = "SHAMAN", isPlayer = true }
    Mock.units.mouseovertarget = Mock.units.player
    local r = Elements.HealthColor("mouseover", true)
    eq(r, select(1, NS.ClassColor("SHAMAN")), "identité lisible : classe")
    Mock.secretUnits.mouseover = true
    eq(NS.IsSecretUnit("mouseover"), true)
    r = Elements.HealthColor("mouseover", true)
    truthy(r ~= select(1, NS.ClassColor("SHAMAN")), "identité secrète : pas de classe")
    Mock.ShowUnitTooltip("mouseover")
    eq(#(GameTooltip.lines or {}), 0, "infobulle : aucune ligne ajoutée")
    Mock.secretUnits = {}
end)

test("diagnostic : ligne Midnight", function()
    reset()
    SlashCmdList.AEONUI("diag")
    truthy(Mock.FindPrinted("Midnight : formateur de recharge oui"), "ligne Midnight")
end)
