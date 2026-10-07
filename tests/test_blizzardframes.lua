-- tests/test_blizzardframes.lua : cadres Blizzard déplaçables (recharges, buffs).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("cadres Blizzard : viewers et buffs adoptés par des movers, laissés à Edit Mode sur option, rendus au disable", function()
    reset()
    NS.Modules:SetEnabled("blizzardframes", true)
    local point, relTo = EssentialCooldownViewer:GetPoint()
    eq(point, "CENTER"); eq(relTo, AeonUI_Holder_cdm_essential)
    eq(EssentialCooldownViewer:GetParent(), UIParent, "jamais reparenté")
    local bpoint, brel = BuffFrame:GetPoint()
    eq(bpoint, "TOPRIGHT"); eq(brel, AeonUI_Holder_buffs)
    truthy(NS.Movers:Anchor("cdm_buffbar") and NS.Movers:Anchor("debuffs"))
    EssentialCooldownViewer:ClearAllPoints()
    EssentialCooldownViewer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    local _, again = EssentialCooldownViewer:GetPoint()
    eq(again, AeonUI_Holder_cdm_essential, "Edit Mode le replace : le hook reprend la main")
    NS.db.modules.blizzardframes.buffs = "keep"
    NS.Modules:Refresh("blizzardframes")
    eq(AeonUI_Holder_buffs:IsShown(), false)
    eq(NS.Movers:List()[1] ~= nil, true)
    NS.db.modules.blizzardframes.buffs = "move"
    NS.Modules:SetEnabled("blizzardframes", false)
    eq(AeonUI_Holder_cdm_essential:IsShown(), false)
    eq(NS.Modules:Get("blizzardframes").reloadOnDisable, true, "les options proposent /reload à la coupure")
end)

test("gestionnaire de recharges : sort masqué rendu transparent, les suivants remontent, lueur quand prêt", function()
    reset()
    local viewer = EssentialCooldownViewer
    local items = {}
    for i, spellID in ipairs({ 100, 200, 300 }) do
        local item = CreateFrame("Frame", nil, viewer)
        item.layoutIndex, item.cooldownID = i, spellID
        items[i] = item
    end
    viewer.itemFramePool = { EnumerateActive = function() local i = 0 return function() i = i + 1 return items[i] end end }
    viewer.Layout = function()
        for i, item in ipairs(items) do item:ClearAllPoints() item:SetPoint("LEFT", viewer, "LEFT", (i - 1) * 40, 0) item:Show() end
    end
    _G.C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id) return { spellID = id } end }
    C_Spell.GetSpellCooldown = function(id) return { isActive = id ~= 300, isOnGCD = false } end
    NS.db.modules.cooldownmanager.spells = { [100] = { hidden = true }, [300] = { glow = "ready" } }
    NS.Modules:SetEnabled("cooldownmanager", true)
    viewer:Layout()
    eq(items[1]:GetAlpha(), 0, "masqué")
    eq(select(4, items[2]:GetPoint()), 0, "le deuxième prend la première place")
    eq(select(4, items[3]:GetPoint()), 40, "le troisième remonte")
    eq(select(2, items[1]:GetPoint()), UIParent, "le masqué est parqué hors de la barre")
    items[1]:SetAlpha(1)   -- Blizzard relève l'alpha
    NS.Modules:Refresh("cooldownmanager")
    eq(items[1]:GetAlpha(), 0, "remasqué")
    eq(select(4, items[3]:GetPoint()), 40, "nouveau passage sans Layout : places inchangées")
    eq(NS.Glow.Current(items[3]), "classic", "prêt : lueur")
    eq(NS.Glow.Current(items[2]), nil, "sans réglage : aucune lueur")
    NS.Modules:SetEnabled("cooldownmanager", false)
    eq(items[1]:GetAlpha(), 1, "rendu au disable")
    eq(select(4, items[1]:GetPoint()), 0, "place d'origine rendue")
    eq(NS.Glow.Current(items[3]), nil)
    viewer.itemFramePool, viewer.Layout, _G.C_CooldownViewer, C_Spell.GetSpellCooldown = nil, nil, nil, nil
end)

test("gestionnaire de recharges : habillage par barre, bordure, compteurs, barre de buff au thème, rendu", function()
    reset()
    local CDM = NS.Modules:Get("cooldownmanager")
    local essential, buffbar = EssentialCooldownViewer, BuffBarCooldownViewer
    local icon = CreateFrame("Frame", nil, essential)
    icon.ChargeCount = CreateFrame("Frame", nil, icon)
    icon.ChargeCount.Current = icon.ChargeCount:CreateFontString()
    icon.ChargeCount.Current:SetFont("Fonts\FRIZQT__.TTF", 14, "")
    local barItem = CreateFrame("Frame", nil, buffbar)
    barItem.Icon = CreateFrame("Frame", nil, barItem)
    barItem.Bar = CreateFrame("StatusBar", nil, barItem)
    barItem.Bar.Name, barItem.Bar.Duration = barItem.Bar:CreateFontString(), barItem.Bar:CreateFontString()
    barItem.Bar.BarBG = barItem.Bar:CreateTexture()
    barItem.Bar:SetStatusBarColor(1, 0.5, 0)
    local function Pool(items)
        return { EnumerateActive = function() local i = 0 return function() i = i + 1 return items[i] end end }
    end
    essential.itemFramePool, buffbar.itemFramePool = Pool({ icon }), Pool({ barItem })
    local skin = NS.db.modules.cooldownmanager.skin
    skin.essential.fontSize = 18
    skin.buffbar.showName = false
    NS.Modules:SetEnabled("cooldownmanager", true)
    Mock.Advance(0.1)
    truthy(icon.aeonBorder, "bordure posée")
    eq(icon.ChargeCount.Current.fontSize, 18, "compteur à la taille choisie")
    eq(barItem.Bar.barColor[3], skin.buffbar.barColor.b, "couleur de barre du thème")
    eq(barItem.Bar.BarBG:GetAlpha(), 0, "fond Blizzard effacé")
    eq(barItem.Bar.Name:GetAlpha(), 0, "nom masqué")
    eq(barItem.Bar.Duration:GetAlpha(), 1, "durée gardée")
    truthy(barItem.Icon.aeonBorder, "bordure sur l'icône de la barre")
    NS.Modules:SetEnabled("cooldownmanager", false)
    eq(icon.ChargeCount.Current.fontSize, 14, "police Blizzard rendue")
    eq(barItem.Bar.barColor[2], 0.5, "couleur Blizzard rendue")
    eq(barItem.Bar.Name:GetAlpha(), 1)
    local shown = false
    for _, edge in pairs(icon.aeonBorder) do shown = shown or edge:IsShown() end
    eq(shown, false, "bordure cachée")
    skin.essential.fontSize, skin.buffbar.showName = 0, true
    essential.itemFramePool, buffbar.itemFramePool = nil, nil
end)

test("barres de recharges personnalisées : sorts connus dans l'ordre, grisés en recharge, prêts masquables", function()
    reset()
    local Bars = NS.Modules:Get("cooldownbars")
    Mock.spells[1953], Mock.spells[122], Mock.spells[2139] = "Blink", "Frost Nova", "Counterspell"
    Mock.knownSpells[1953], Mock.knownSpells[2139] = true, true
    C_Spell.GetSpellCooldown = function(spell) return { isActive = spell == 1953, isOnGCD = false } end
    local cfg = NS.db.modules.cooldownbars.bars.bar1
    cfg.spells = "2139, 122, 1953"
    NS.Modules:SetEnabled("cooldownbars", true)
    local holder = _G.AeonUICooldownBar1
    truthy(holder:IsShown())
    local first, second = holder:GetChildren()
    eq(select(4, second:GetPoint(1)), cfg.size + cfg.spacing, "Nova inconnue écartée : Transfert en second")
    eq(first.texture.desaturatedTexture, false, "Contresort prêt : en couleur")
    eq(second.texture.desaturatedTexture, true, "Transfert en recharge : grisé")
    local secret, max = Mock.SetSecret(2), 3
    C_Spell.GetSpellCharges = function(spell) if spell == 2139 then return { currentCharges = secret, maxCharges = max } end end
    NS.Modules:Refresh("cooldownbars")
    eq(first.count.text, secret, "charges secrètes en combat : nombre posé tel quel")
    max = 1
    NS.Modules:Refresh("cooldownbars")
    eq(first.count.text, "", "une seule charge : rien")
    C_Spell.GetSpellCharges, Mock.secret = nil, {}
    cfg.hideReady = true
    NS.Modules:Refresh("cooldownbars")
    eq(first.texture.desaturatedTexture, true, "prêts masqués : Transfert seul, en tête")
    eq(second:IsShown(), false)
    eq(_G.AeonUICooldownBar2:IsShown(), false, "barre 2 coupée par défaut")
    NS.Modules:SetEnabled("cooldownbars", false)
    eq(holder:IsShown(), false)
    cfg.spells, cfg.hideReady = "", false
    C_Spell.GetSpellCooldown = nil
    Mock.spells[1953], Mock.spells[122], Mock.spells[2139] = nil, nil, nil
    Mock.knownSpells[1953], Mock.knownSpells[2139] = nil, nil
end)
