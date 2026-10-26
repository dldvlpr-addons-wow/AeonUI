-- tests/test_blizzardframes.lua : cadres Blizzard déplaçables (recharges, buffs).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("cadres Blizzard : viewers et buffs adoptés par des movers, laissés à Edit Mode sur option, rendus au disable", function()
    reset()
    NS.Modules:SetEnabled("blizzardframes", true)
    local point, relTo = EssentialCooldownViewer:GetPoint()
    eq(point, "CENTER"); eq(relTo, MuscaUI_Holder_cdm_essential)
    eq(EssentialCooldownViewer:GetParent(), UIParent, "jamais reparenté")
    local bpoint, brel = BuffFrame:GetPoint()
    eq(bpoint, "TOPRIGHT"); eq(brel, MuscaUI_Holder_buffs)
    truthy(NS.Movers:Anchor("cdm_buffbar") and NS.Movers:Anchor("debuffs"))
    EssentialCooldownViewer:ClearAllPoints()
    EssentialCooldownViewer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    local _, again = EssentialCooldownViewer:GetPoint()
    eq(again, MuscaUI_Holder_cdm_essential, "Edit Mode le replace : le hook reprend la main")
    NS.db.modules.blizzardframes.buffs = "keep"
    NS.Modules:Refresh("blizzardframes")
    eq(MuscaUI_Holder_buffs:IsShown(), false)
    eq(NS.Movers:List()[1] ~= nil, true)
    NS.db.modules.blizzardframes.buffs = "move"
    NS.Modules:SetEnabled("blizzardframes", false)
    eq(MuscaUI_Holder_cdm_essential:IsShown(), false)
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
    truthy(icon.muscaBorder, "bordure posée")
    eq(icon.ChargeCount.Current.fontSize, 18, "compteur à la taille choisie")
    eq(barItem.Bar.barColor[3], skin.buffbar.barColor.b, "couleur de barre du thème")
    eq(barItem.Bar.BarBG:GetAlpha(), 0, "fond Blizzard effacé")
    eq(barItem.Bar.Name:GetAlpha(), 0, "nom masqué")
    eq(barItem.Bar.Duration:GetAlpha(), 1, "durée gardée")
    truthy(barItem.Icon.muscaBorder, "bordure sur l'icône de la barre")
    NS.Modules:SetEnabled("cooldownmanager", false)
    eq(icon.ChargeCount.Current.fontSize, 14, "police Blizzard rendue")
    eq(barItem.Bar.barColor[2], 0.5, "couleur Blizzard rendue")
    eq(barItem.Bar.Name:GetAlpha(), 1)
    local shown = false
    for _, edge in pairs(icon.muscaBorder) do shown = shown or edge:IsShown() end
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
    local holder = _G.MuscaUICooldownBar1
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
    max = Mock.SetSecret(3)
    NS.Modules:Refresh("cooldownbars")
    eq(first.count.text, "", "maximum secret : écarté par NS.GetSpellCharges, aucune comparaison")
    C_Spell.GetSpellCharges, Mock.secret = nil, {}
    cfg.hideReady = true
    NS.Modules:Refresh("cooldownbars")
    eq(first.texture.desaturatedTexture, true, "prêts masqués : Transfert seul, en tête")
    eq(second:IsShown(), false)
    eq(_G.MuscaUICooldownBar2:IsShown(), false, "barre 2 coupée par défaut")
    NS.Modules:SetEnabled("cooldownbars", false)
    eq(holder:IsShown(), false)
    cfg.spells, cfg.hideReady = "", false
    C_Spell.GetSpellCooldown = nil
    Mock.spells[1953], Mock.spells[122], Mock.spells[2139] = nil, nil, nil
    Mock.knownSpells[1953], Mock.knownSpells[2139] = nil, nil
end)

local function Pool(items)
    return { EnumerateActive = function() local i = 0 return function() i = i + 1 return items[i] end end }
end

local function CooldownItems(viewer, ids)
    local items = {}
    for i, id in ipairs(ids) do
        local item = CreateFrame("Frame", nil, viewer)
        item.layoutIndex, item.cooldownID = i, id
        items[i] = item
    end
    viewer.itemFramePool = Pool(items)
    return items
end

test("gestionnaire de recharges : effets d'état, lueur au maximum de charges, proc, bijou reconnu par emplacement", function()
    reset()
    local items = CooldownItems(EssentialCooldownViewer, { 100, 200, 300, 400, 500, 600 })
    _G.C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id) return id == 500 and { equipSlot = 13 } or { spellID = id } end }
    local cooling = { [100] = true, [300] = true }
    C_Spell.GetSpellCooldown = function(id) return { isActive = cooling[id] == true, isOnGCD = false } end
    C_Spell.GetSpellCharges = function(id) if id == 400 then return { currentCharges = 1, maxCharges = 2, isActive = true } end end
    C_Spell.IsSpellUsable = function(id) return id ~= 600 end
    _G.C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return id == 100 end }
    items[1].SpellActivationAlert = CreateFrame("Frame", nil, items[1])
    NS.db.modules.cooldownmanager.spells = { [100] = { state = "dim" }, [200] = { state = "hideReady" },
        [300] = { state = "hideCooldown" }, [400] = { glow = "maxcharges" }, slot13 = { hidden = true },
        [600] = { state = "hideUnusable" } }
    NS.Modules:SetEnabled("cooldownmanager", true)
    eq(items[1]:GetAlpha(), 0.5, "en recharge : estompé")
    eq(items[2]:GetAlpha(), 0, "prêt : masqué")
    eq(items[3]:GetAlpha(), 0, "en recharge : masqué")
    eq(items[5]:GetAlpha(), 0, "bijou 13 reconnu par son emplacement")
    eq(items[6]:GetAlpha(), 0, "inutilisable : masqué")
    eq(NS.Glow.Current(items[4]), nil, "une charge sur deux : pas au maximum")
    eq(NS.Glow.Current(items[1]), "button", "proc : lueur de proc")
    eq(items[1].SpellActivationAlert:GetAlpha(), 0, "alerte Blizzard effacée")
    cooling[300] = nil
    C_Spell.GetSpellCharges = function(id) if id == 400 then return { currentCharges = 2, maxCharges = 2, isActive = false } end end
    _G.C_SpellActivationOverlay = nil
    Mock.FireEvent("SPELL_UPDATE_COOLDOWN")
    Mock.Advance(0.1)
    eq(items[3]:GetAlpha(), 1, "prêt : rendu")
    eq(NS.Glow.Current(items[4]), "classic", "charges au maximum : lueur")
    eq(NS.Glow.Current(items[1]), nil, "proc fini")
    eq(items[1].SpellActivationAlert:GetAlpha(), 1, "alerte Blizzard rendue")
    NS.Modules:SetEnabled("cooldownmanager", false)
    eq(items[1]:GetAlpha(), 1, "rendu au disable")
    EssentialCooldownViewer.itemFramePool, _G.C_CooldownViewer = nil, nil
    C_Spell.GetSpellCooldown, C_Spell.GetSpellCharges, C_Spell.IsSpellUsable = nil, nil, nil
end)

test("gestionnaire de recharges : raccourci de nos barres, lueur de buff actif, fenêtre après lancement, visibilité", function()
    reset()
    NS.Modules:SetEnabled("actionbars", true)
    local essential = CooldownItems(EssentialCooldownViewer, { 100, 400 })
    local buffs = CooldownItems(BuffIconCooldownViewer, { 700 })
    _G.C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id) return { spellID = id } end }
    _G.C_ActionBar = { FindSpellActionButtons = function(id) if id == 100 then return { 1 } end end }
    NS.db.modules.cooldownmanager.spells = { [100] = { window = 5 }, [400] = { window = 5 }, [700] = { buffGlow = 100 } }
    NS.Modules:SetEnabled("cooldownmanager", true)
    eq(essential[1].muscaOverlay.text.text, "1", "touche du bouton de nos barres qui porte le sort")
    eq(essential[2].muscaOverlay, nil, "sort absent des barres : rien")
    eq(NS.Glow.Current(essential[1]), nil, "buff absent : aucune lueur")
    buffs[1].auraInstanceID = 5
    Mock.FireEvent("UNIT_AURA", "player")
    Mock.Advance(0.1)
    eq(NS.Glow.Current(essential[1]), "pixel", "buff actif : lueur sur le sort lié")
    local button = NS.Modules:Get("actionbars").bars[1].buttons[1]
    eq(NS.Glow.Current(button.muscaBuffGlow), "pixel", "et sur notre bouton qui le porte")
    buffs[1].auraInstanceID = nil
    Mock.FireEvent("UNIT_AURA", "player")
    Mock.Advance(0.1)
    eq(NS.Glow.Current(button.muscaBuffGlow), nil, "buff fini : éteint")
    Mock.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 100)
    truthy(essential[1].muscaWindow:IsShown(), "fenêtre ouverte au lancement")
    eq(essential[1].muscaWindow.cooldown.cooldownDuration, 5)
    eq(NS.Glow.Current(essential[1].muscaWindow), "classic", "lueur de fenêtre par défaut")
    NS.db.modules.cooldownmanager.spells[100].windowNoGlow = true
    Mock.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 100)
    eq(NS.Glow.Current(essential[1].muscaWindow), nil, "lueur coupée par le réglage")
    Mock.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", Mock.SetSecret(400))
    eq(essential[2].muscaWindow, nil, "identifiant secret : rien")
    Mock.secret = {}
    NS.db.modules.cooldownmanager.visibility.essential = NS.Visibility.Spec({ combat = "yes" })
    NS.Modules:Refresh("cooldownmanager")
    eq(EssentialCooldownViewer:GetAlpha(), 0, "hors combat : viewer caché")
    NS.db.modules.cooldownmanager.visibility.essential = NS.Visibility.Spec()
    NS.Modules:Refresh("cooldownmanager")
    eq(EssentialCooldownViewer:GetAlpha(), 1)
    NS.Modules:SetEnabled("cooldownmanager", false)
    eq(essential[1].muscaWindow:IsShown(), false, "fenêtre fermée au disable")
    NS.Modules:SetEnabled("actionbars", false)
    EssentialCooldownViewer.itemFramePool, BuffIconCooldownViewer.itemFramePool, _G.C_CooldownViewer = nil, nil, nil
end)

test("barres de recharges : bijou par emplacement, liste par clic, son à la fin de recharge, visibilité", function()
    reset()
    local Bars = NS.Modules:Get("cooldownbars")
    eq(Bars.Toggle("2139 slot13", 2139), "slot13", "clic sur un sort présent : retiré")
    eq(Bars.Toggle("slot13", "slot14"), "slot13 slot14", "clic sur un absent : ajouté")
    Mock.equipped[13] = { link = "[Bijou]", texture = "bijou", cooldown = { Mock.now, 30 } }
    local cfg = NS.db.modules.cooldownbars.bars.bar1
    cfg.spells = "slot13, slot14"
    NS.Modules:SetEnabled("cooldownbars", true)
    local holder = _G.MuscaUICooldownBar1
    local first, second = holder:GetChildren()
    truthy(holder:IsShown())
    eq(first.texture.texture, "bijou", "bijou porté affiché")
    eq(first.cooldown.cooldownDuration, 30, "recharge de l'emplacement")
    truthy(not (second and second:IsShown()), "emplacement vide : rien")
    eq(#Mock.sounds, 0)
    Mock.Advance(31)
    Mock.FireEvent("SPELL_UPDATE_COOLDOWN")
    eq(#Mock.sounds, 1, "recharge terminée : son")
    Mock.equipped[13].cooldown = { Mock.now, 30 }
    Mock.FireEvent("LOADING_SCREEN_ENABLED")
    Mock.Advance(31)
    Mock.FireEvent("SPELL_UPDATE_COOLDOWN")
    eq(#Mock.sounds, 1, "pendant un chargement : aucun son")
    Mock.FireEvent("LOADING_SCREEN_DISABLED")
    cfg.visibility = NS.Visibility.Spec({ combat = "yes" })
    NS.Modules:Refresh("cooldownbars")
    eq(holder:IsShown(), false, "hors combat : barre cachée")
    cfg.visibility = NS.Visibility.Spec()
    NS.Modules:Refresh("cooldownbars")
    truthy(holder:IsShown())
    NS.Modules:SetEnabled("cooldownbars", false)
    cfg.spells = ""
end)

test("barres de recharges : clic droit avance le sort d'une place", function()
    local Bars = NS.Modules:Get("cooldownbars")
    eq(Bars.MoveEarlier("2139 slot13 1953", 1953), "2139 1953 slot13")
    eq(Bars.MoveEarlier("2139 slot13", "slot13"), "slot13 2139")
    eq(Bars.MoveEarlier("2139 slot13", 2139), "2139 slot13", "premier : inchangé")
end)
