-- tests/test_g_barres_action.lua : lot G « barres d'action » (apparence des boutons, fond et bordure de barre).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local AB = NS.Modules:Get("actionbars")

test("barres G : fond, bordure et gryphons de barre suivent le réglage", function()
    reset()
    NS.Modules:SetEnabled("actionbars", true)
    local bar = AB:GetBar(1)
    eq(bar.muscaBackground, nil, "rien par défaut")
    local cfg = AB.db.bars[1]
    cfg.background, cfg.border, cfg.endCaps = true, true, true
    NS.Modules:Refresh("actionbars")
    truthy(bar.muscaBackground and bar.muscaBackground:IsShown(), "fond")
    truthy(bar.muscaBarBorder.top:IsShown(), "bordure")
    truthy(bar.muscaEndCaps.left:IsShown() and bar.muscaEndCaps.right:IsShown(), "gryphons")
    cfg.background, cfg.border, cfg.endCaps = false, false, false
    NS.Modules:Refresh("actionbars")
    eq(bar.muscaBackground:IsShown(), false, "fond retiré")
    eq(bar.muscaBarBorder.top:IsShown(), false, "bordure retirée")
    eq(bar.muscaEndCaps.left:IsShown(), false, "gryphons retirés")
    NS.Modules:SetEnabled("actionbars", false)
end)

test("barres G : compteur à 0 masqué, teintes et animations d'un bouton, état d'origine rendu", function()
    reset()
    NS.Modules:SetEnabled("actionbars", true)
    local button = AB:GetBar(1).buttons[1]
    local pushed = { SetVertexColor = function(self, r, g, b) self.rgb = { r, g, b } end }
    local castFrame = { SetAlpha = function(self, a) self.alpha = a end }
    local zero = "0"
    button.Count = { GetText = function() return zero end, SetAlpha = function(self, a) self.alpha = a end }
    button.GetPushedTexture = function() return pushed end
    button.SpellCastAnimFrame = castFrame
    button.action = 1
    AB.db.hideZeroCharges, AB.db.interactionColors, AB.db.hideCastAnimations = true, true, true
    AB.db.pushedColor = { r = 1, g = 0, b = 0 }
    AB.ApplyButtonLook(button)
    AB.UpdateButtonExtras(button)
    eq(button.Count.alpha, 0, "0 caché")
    eq(pushed.rgb[2], 0, "teinte posée")
    eq(castFrame.alpha, 0, "animation cachée")
    zero = "3"
    AB.UpdateButtonExtras(button)
    eq(button.Count.alpha, 1, "3 visible")
    AB.db.interactionColors, AB.db.hideCastAnimations = false, false
    AB.ApplyButtonLook(button)
    eq(pushed.rgb[2], 1, "teinte retirée")
    eq(castFrame.alpha, 1, "animation rendue")
    NS.Modules:SetEnabled("actionbars", false)
end)

test("barres G : flyout stylé seulement en style MuscaUI, icône d'origine rendue", function()
    reset()
    NS.Modules:SetEnabled("actionbars", true)
    local icon = { coords = { 0, 1, 0, 1 }, SetTexCoord = function(self, ...) self.coords = { ... } end,
                   GetTexCoord = function(self) return unpack(self.coords) end, SetDesaturated = function() end }
    local button = CreateFrame("CheckButton", nil, UIParent)   -- Forever : bouton de pool, sans nom
    button.icon = icon
    local savedFlyout = _G.SpellFlyout
    _G.SpellFlyout = { buttons = { button } }
    AB.db.iconStyle, AB.db.styleFlyout = "aeon", true
    AB.StyleFlyoutButtons()
    truthy(icon.coords[1] > 0, "recadrée")
    AB.db.styleFlyout = false
    AB.StyleFlyoutButtons()
    eq(icon.coords[1], 0, "rendue")
    _G.SpellFlyout = savedFlyout
    NS.Modules:SetEnabled("actionbars", false)
end)
