-- tests/test_g_groupe.lua : cadres de groupe et clic-sort, lot G (clics natifs, liaison hors combat,
-- format du nom, cadres de cible et de survol, couleurs d'état, mana des soigneurs, icône de combat).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local GF = NS.Modules:Get("groupframes")
local clickCast = NS.Modules:Get("clickcast")
local Elements = NS.UnitFrameElements or GF.Elements

local function Setup()
    reset()
    NS.Modules:SetEnabled("groupframes", true)
    Mock.SetGroup(2, false)
end
local function Teardown()
    NS.Modules:SetEnabled("clickcast", false)
    Mock.SetGroup(0, false)
    NS.Modules:SetEnabled("groupframes", false)
end

test("clic-sort : clics natifs rendables inertes, liaison hors combat retirée le temps d'un clic en combat", function()
    Setup()
    local bindings = clickCast.db.bindings
    bindings.b1.spell, bindings.b1.mouse, bindings.b1.modifier, bindings.b1.oocOnly = "Heal", "1", "shift", true
    bindings.b2.spell, bindings.b2.mouse, bindings.b2.modifier = "Shield", "2", "shift"
    NS.Modules:SetEnabled("clickcast", true)
    local ami = GF:GetButton("party1")
    eq(ami:GetAttribute("*type1"), "target", "clic gauche : cible par défaut")
    eq(ami:GetAttribute("*type2"), "togglemenu", "clic droit : menu par défaut")
    clickCast.db.nativeClicks = false
    NS.Modules:Refresh("clickcast")
    eq(ami:GetAttribute("*type1"), nil, "clics natifs coupés")
    eq(ami:GetAttribute("*type2"), nil)
    eq(ami:GetAttribute("muscacast-ooccount"), 1, "une seule liaison hors combat")
    -- Clic hors combat : tout reste. En combat : le type de la liaison marquée disparaît pendant le clic.
    -- Le mock refuse SetAttribute en combat (le code sécurisé du jeu le permet) : seul PlayerInCombat change.
    local function Click(inCombat)
        local env = { PlayerInCombat = function() return inCombat end }
        Mock.RunSecure(ami, ami.wrapped.PreClick, env)
        local before, other = ami:GetAttribute("shift-type1"), ami:GetAttribute("shift-type2")
        Mock.RunSecure(ami, ami.wrapped.PostClick, env)
        return before, other
    end
    eq(Click(false), "spell", "hors combat : liaison active")
    local seen, other = Click(true)
    eq(seen, nil, "en combat : liaison hors combat retirée")
    eq(other, "spell", "l'autre liaison reste")
    eq(ami:GetAttribute("shift-type1"), "spell", "rendue après le clic")
    eq(ami:GetAttribute("muscacast-oocswapped"), nil, "marqueur retiré")
    clickCast.db.nativeClicks = true
    bindings.b1.oocOnly = false
    Teardown()
end)

test("groupes : format du nom (premier mot, dernier mot) et troncature après", function()
    eq(Elements.FormatName("Jean Dupont", "first"), "Jean")
    eq(Elements.FormatName("Jean Dupont", "last"), "Dupont")
    eq(Elements.FormatName("Jean Dupont", "full"), "Jean Dupont")
    eq(Elements.FormatName("Solo", "last"), "Solo", "un seul mot : inchangé")
    eq(Elements.FormatName(nil, "first"), nil)
end)

test("groupes : cadre de cible épais, couleur choisie, voile ou cadre au survol", function()
    Setup()
    Mock.units.target = Mock.units.party1
    local button = GF:GetButton("party1")
    GF:UpdateBorder(button)
    eq(button.edgeHosts and button.edgeHosts.target, nil, "taille 0 : aucun cadre épais")
    GF.db.highlightSize = 2
    GF.db.targetColorCustom, GF.db.targetColor = true, { r = 1, g = 0, b = 0 }
    GF:UpdateBorder(button)
    local host = button.edgeHosts and button.edgeHosts.target
    truthy(host and host:IsShown(), "cadre épais montré sur la cible")
    GF.db.highlightSize = 0
    GF:UpdateBorder(button)
    eq(host:IsShown(), false, "retour à la bordure du thème")
    -- Survol : voile par défaut, cadre sur demande.
    button.hovered = true
    GF:UpdateHighlight(button)
    eq(button.hover:IsShown(), true, "voile")
    GF.db.mouseoverStyle = "border"
    GF:UpdateHighlight(button)
    eq(button.hover:IsShown(), false, "plus de voile")
    truthy(button.edgeHosts.hover:IsShown(), "cadre de survol")
    button.hovered = false
    GF:UpdateHighlight(button)
    eq(button.edgeHosts.hover:IsShown(), false, "souris partie")
    GF.db.mouseoverStyle, GF.db.targetColorCustom = "veil", false
    Mock.units.target = nil
    Teardown()
end)

test("groupes : couleur d'état personnalisée et icône de combat", function()
    Setup()
    local button = GF:GetButton("party1")
    GF.db.stateColors.dead = { r = 0.5, g = 0.25, b = 0.1 }
    Mock.units.party1.dead = true
    GF:UpdateState(button)
    eq(button.stateTint:IsShown(), true, "teinte posée")
    GF.db.stateColors.dead = { r = 0.14, g = 0.09, b = 0.09 }
    Mock.units.party1.dead = nil
    GF:UpdateState(button)
    eq(button.stateTint:IsShown(), false)
    GF.db.combatIcon = true
    Mock.units.party1.combat = true
    local savedAffecting = _G.UnitAffectingCombat
    _G.UnitAffectingCombat = _G.UnitAffectingCombat or function(unit) return Mock.units[unit] and Mock.units[unit].combat end
    GF:UpdateCombat(button)
    eq(button.combatIcon:IsShown(), true, "membre en combat")
    GF.db.combatIcon = false
    GF:UpdateCombat(button)
    eq(button.combatIcon:IsShown(), false, "option coupée")
    Mock.units.party1.combat = nil
    _G.UnitAffectingCombat = savedAffecting
    Teardown()
end)

test("groupes : mana des soigneurs, sens vers le haut et interligne", function()
    Setup()
    Mock.units.party1.role = "HEALER"
    local savedRoles = _G.UnitGroupRolesAssigned
    _G.UnitGroupRolesAssigned = function(unit) return Mock.units[unit] and Mock.units[unit].role or "NONE" end
    GF.db.healerMana = "both"
    GF.db.healerManaGrow, GF.db.healerManaSpacing = "UP", 4
    GF:UpdateHealerMana()
    local row = GF.manaUnits.party1
    truthy(row, "ligne du soigneur")
    local point = row.name:GetPoint()
    eq(point, "BOTTOMLEFT", "ancrée en bas")
    GF.db.healerManaGrow = "DOWN"
    GF:UpdateHealerMana()
    eq((row.name:GetPoint()), "TOPLEFT", "ancrée en haut")
    GF.db.healerMana, GF.db.healerManaSpacing = "none", 0
    _G.UnitGroupRolesAssigned = savedRoles
    Teardown()
end)

test("groupes : indicateur ciblé par rôle, lueur, et indicateurs montrés dans l'aperçu", function()
    Setup()
    Mock.spells[139] = "Renew"
    local savedRoles = _G.UnitGroupRolesAssigned
    _G.UnitGroupRolesAssigned = function(unit) return Mock.units[unit] and Mock.units[unit].role or "NONE" end
    Mock.units.party1.role = "DAMAGER"
    GF.db.indicators[4].spells, GF.db.indicators[4].showIn, GF.db.indicators[4].glow = "139", "healer", "pixel"
    local ami = GF:GetButton("party1")
    Mock.auraContainer = true
    ami.auraSlots = nil
    NS.Modules:Refresh("groupframes")
    local engine = ami.auraSlots
    eq(engine.slots.indicator4, nil, "indicateur réservé aux soigneurs : pas d'emplacement sur un dégâts")
    Mock.units.party1.role = "HEALER"
    GF:UpdateAll(ami)
    eq(engine.slots.indicator4.enabled, true, "rôle changé : réactivé")
    truthy(ami.indicatorHolders[4].muscaGlow, "lueur posée sur l'indicateur")
    GF.db.indicators[4].showIn, GF.db.indicators[4].glow = "nonhealer", "none"
    NS.Modules:Refresh("groupframes")
    eq(engine.slots.indicator4.enabled, false, "tous sauf soigneurs : coupé sur un soigneur")
    eq(ami.indicatorHolders[4].muscaGlow, nil, "lueur retirée")
    ami.auraSlots = nil
    Mock.auraContainer = nil
    -- aperçu : l'indicateur ciblé « soigneur » n'apparaît que sur un membre fictif soigneur ; sans sorts, caché
    GF.db.indicators[4].spells, GF.db.indicators[4].showIn = "139", "healer"
    GF:SetPreview(5)
    local shownByRole = {}
    for _, previewButton in ipairs(GF:GetPreview().buttons) do
        local indicator = previewButton.fake and previewButton.indicators and previewButton.indicators[4]
        if indicator then shownByRole[previewButton.fake.role] = indicator:IsShown() end
    end
    eq(shownByRole.HEALER, true, "aperçu : montré sur un soigneur")
    eq(shownByRole.DAMAGER, false, "aperçu : caché sur un dégâts")
    GF.db.indicators[4].spells = ""
    GF:SetPreview(5)
    for _, previewButton in ipairs(GF:GetPreview().buttons) do
        if previewButton.indicators and previewButton.indicators[4] then
            eq(previewButton.indicators[4]:IsShown(), false, "aperçu : sans sorts, caché")
        end
    end
    GF:SetPreview(nil)
    GF.db.indicators[4].spells, GF.db.indicators[4].showIn = "", "all"
    _G.UnitGroupRolesAssigned = savedRoles
    Teardown()
end)

test("groupes : « Afficher sur » suit un changement de rôle sur le même membre", function()
    Setup()
    Mock.spells[139] = "Renew"
    local savedRoles = _G.UnitGroupRolesAssigned
    _G.UnitGroupRolesAssigned = function(unit) return Mock.units[unit] and Mock.units[unit].role or "NONE" end
    Mock.units.party1.role = "DAMAGER"
    GF.db.indicators[4].spells, GF.db.indicators[4].showIn = "139", "healer"
    local ami = GF:GetButton("party1")
    Mock.auraContainer = true
    NS.auraContainerProbe, ami.auraSlots = nil, nil
    NS.Modules:Refresh("groupframes")
    local engine = ami.auraSlots
    eq(engine.slots.indicator4, nil, "dégâts : pas d'emplacement")
    Mock.units.party1.role = "HEALER"
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    Mock.Advance(0.1)
    eq(engine.slots.indicator4 and engine.slots.indicator4.enabled, true, "même GUID, rôle changé : réactivé")
    Mock.units.party1.role = "DAMAGER"
    Mock.SetCombat(true)
    Mock.FireEvent("PLAYER_REGEN_DISABLED")
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    Mock.Advance(0.1)
    eq(engine.slots.indicator4.enabled, true, "en combat : emplacements gardés")
    eq(ami.indicatorsStale, true, "en combat : marqué périmé")
    Mock.SetCombat(false)
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    eq(engine.slots.indicator4.enabled, false, "sortie de combat : refait")
    ami.auraSlots = nil
    Mock.auraContainer = nil
    GF.db.indicators[4].spells, GF.db.indicators[4].showIn = "", "all"
    _G.UnitGroupRolesAssigned = savedRoles
    Teardown()
end)

test("groupes : bordure des icônes d'aura, réglage appliqué en direct", function()
    -- holder déjà créé par le moteur, puis réglage basculé et Refresh
    reset()
    NS.Modules:SetEnabled("groupframes", true)
    Mock.SetGroup(2, false)
    local button = GF:GetButton("party1")
    Mock.auraContainer = true
    NS.auraContainerProbe = nil
    button.auras = nil
    NS.Modules:Refresh("groupframes")
    local style = button.auras and button.auras.auraStyle
    truthy(style, "style posé")
    eq(style.border, true, "défaut : bordure gardée")
    eq(style.borderSize, 0, "défaut : épaisseur du thème")
    GF.db.auraBorder, GF.db.auraBorderSize = false, 3
    NS.Modules:Refresh("groupframes")
    style = button.auras.auraStyle
    eq(style.border, false, "bordure coupée transmise")
    eq(style.borderSize, 3, "épaisseur transmise")
    button.auras = nil
    Mock.auraContainer = nil
    GF.db.auraBorder, GF.db.auraBorderSize = true, 0
    NS.Modules:SetEnabled("groupframes", false)

    -- moteur : bords du thème masqués, bords de dissipation réépaissis ; sans champ, rendu inchangé
    local host = CreateFrame("Button", nil, UIParent)
    local holder = NS.InitAuraButton(host, { dispel = true })
    local base = holder.dispelEdges[1].height
    truthy(holder.borderEdges and holder.dispelEdges and holder.dispelHost, "bords mémorisés")
    NS.StyleAuraHolder(holder, { border = true })
    eq(holder.dispelEdges[1].height, base, "sans épaisseur : celle du thème")
    NS.StyleAuraHolder(holder, { border = true, borderSize = 3 })
    eq(holder.dispelEdges[1].height, NS.Pixel:Scale(3), "bord haut réépaissi")
    eq(holder.dispelEdges[3].width, NS.Pixel:Scale(3), "bord gauche réépaissi")
    eq(holder.dispelHost:IsShown(), true, "bords de dissipation montrés")
    NS.StyleAuraHolder(holder, { border = false })
    eq(holder.dispelHost:IsShown(), false, "bords de dissipation : cadre masqué")
    for _, edge in pairs(holder.borderEdges) do eq(edge:IsShown(), false, "bordure du thème masquée") end
end)

test("auras : les boutons maison suivent le réglage de bordure", function()
    reset()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame.global, frame.cfg, frame.isPreview = { auraBorder = false }, { auras = true }, true
    NS.UnitFrameElements.BuildAuras(frame)
    frame.auras.step = 16
    NS.UnitFrameElements.PreviewAuras(frame, { { icon = 1 } })
    for _, edge in pairs(frame.auras.buttons[1].border) do eq(edge:IsShown(), false, "aperçu : bordure coupée") end
    frame.global.auraBorder = true
    NS.UnitFrameElements.PreviewAuras(frame, { { icon = 1 } })
    for _, edge in pairs(frame.auras.buttons[1].border) do eq(edge:IsShown(), true, "aperçu : bordure rendue") end
end)
