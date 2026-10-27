-- tests/test_group_nameplate_extensions.lua : lot 5, cadres de groupe, plaques, rappels.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local GF = NS.Modules:Get("groupframes")
local NPF = NS.Modules:Get("nameplateframes")
local Reminders = NS.Modules:Get("reminders")

test("groupes : nom placé, décalé, dimensionné et coloré selon les réglages", function()
    reset()
    GF.db.namePosition, GF.db.nameOffsetX, GF.db.nameOffsetY = "BOTTOMRIGHT", 5, -3
    GF.db.nameCustomColor, GF.db.nameColor = true, { r = 0.1, g = 0.2, b = 0.3 }
    NS.Modules:SetEnabled("groupframes", true)
    Mock.SetGroup(2, false)
    local button = GF:GetButton("party1")
    eq(button.name.points[1][1], "BOTTOMRIGHT", "point du nom")
    eq(button.name.points[1][4] > 0, true, "décalage X vers l'intérieur")
    eq(button.cfg.nameColor.g, 0.2, "couleur propre transmise")
    local baseSize = button.name.fontSize
    GF.db.nameSize = 4
    NS.Modules:Refresh("groupframes")
    eq(button.name.fontSize, baseSize + 4, "taille du nom")
    GF.db.nameSize = 0
    eq(button.cfg.nameColor.r, 0.1, "couleur propre transmise au cadre")
    GF.db.nameCustomColor, GF.db.namePosition, GF.db.nameOffsetX, GF.db.nameOffsetY = false, "TOPLEFT", 0, 0
    NS.Modules:Refresh("groupframes")
    eq(button.cfg.nameColor, nil, "couleur propre coupée : couleur automatique")
    NS.Modules:SetEnabled("groupframes", false)
end)

test("groupes : indicateur carré ou barre sur l'emplacement du moteur, icône par défaut", function()
    reset()
    Mock.spells[139] = "Renew"
    GF.db.indicators[4].spells = "139"
    NS.Modules:SetEnabled("groupframes", true)
    Mock.SetGroup(2, false)
    local button = GF:GetButton("party1")
    Mock.auraContainer = true
    button.auraSlots = nil
    NS.Modules:Refresh("groupframes")
    local holder = button.indicatorHolders[4]
    truthy(holder, "emplacement du moteur")
    eq(holder.fill:IsShown(), false, "icône par défaut : pas d'aplat")
    eq(holder.icon.alpha, 1, "icône par défaut : visible")
    eq(holder.bar:IsShown(), false, "icône par défaut : pas de barre")
    GF.db.indicators[4].style, GF.db.indicators[4].color = "square", { r = 0.5, g = 0.6, b = 0.7 }
    NS.Modules:Refresh("groupframes")
    eq(holder.fill:IsShown(), true, "carré : aplat")
    eq(holder.fill.color[1], 0.5, "couleur de l'aplat")
    eq(holder.bar:IsShown(), false)
    GF.db.indicators[4].style = "bar"
    NS.Modules:Refresh("groupframes")
    eq(holder.bar:IsShown(), true, "barre")
    eq(holder.bar.barColor[1], 0.5, "couleur de la barre")
    eq(holder.icon.alpha, 0, "barre : icône du moteur invisible")
    eq(holder.cooldown.alpha, 0, "barre : balayage invisible")
    eq(holder.top.alpha, 0, "barre : bordure et piles invisibles")
    eq(holder.fill:IsShown(), false)
    -- Icône de rôle : décalée de la largeur réelle de la barre.
    GF.db.roleIconPosition, GF.db.indicators[4].point = "BOTTOMRIGHT", "BOTTOMRIGHT"
    GF.db.indicators[4].spells, GF.db.indicators[4].style = "139", "icon"
    NS.Modules:Refresh("groupframes")
    local iconOffset = math.abs(button.role.points[1][4])
    GF.db.indicators[4].style = "bar"
    NS.Modules:Refresh("groupframes")
    truthy(math.abs(button.role.points[1][4]) > iconOffset, "barre : icône de rôle plus loin")
    GF.db.roleIconPosition, GF.db.indicators[4].point, GF.db.indicators[4].spells, GF.db.indicators[4].style = "TOPLEFT", "BOTTOMRIGHT", "", "icon"
    button.auraSlots, button.indicatorHolders = nil, nil
    NS.Modules:SetEnabled("groupframes", false)
end)

test("groupes : texte des auras du profil de groupe transmis au moteur", function()
    reset()
    GF.db.auraDuration, GF.db.auraCountShow = "text", false
    NS.Modules:SetEnabled("groupframes", true)
    Mock.SetGroup(2, false)
    local button = GF:GetButton("party1")
    Mock.auraContainer = true
    NS.auraContainerProbe = nil
    button.auras = nil
    NS.Modules:Refresh("groupframes")
    local style = button.auras and button.auras.auraStyle
    truthy(style, "style d'aura posé sur le conteneur du groupe")
    eq(style.duration, "text", "durée")
    eq(style.count, false, "piles masquées")
    GF.db.auraDuration, GF.db.auraCountShow = "swipe", true
    button.auras = nil
    NS.Modules:SetEnabled("groupframes", false)
end)

test("plaques : minuteur de l'incantation, échelle de la cible, opacité des autres", function()
    reset()
    NS.Modules:SetEnabled("nameplateframes", true)
    Mock.units.nameplate1 = { name = "Loup", health = 300, healthMax = 400, level = 12, hostile = true }
    Mock.AddNamePlate("nameplate1")
    local frame = NPF:GetFrame("nameplate1")
    eq(frame.castbar.showTimer, false, "minuteur coupé par défaut")
    NPF.db.castTimer = true
    NS.Modules:Refresh("nameplateframes")
    eq(frame.castbar.showTimer, true, "minuteur demandé")
    NPF.db.castTimer = false
    -- Échelle de la cible.
    NPF.db.targetScale = 1.3
    Mock.units.target = Mock.units.nameplate1
    NPF:UpdateHighlight(frame)
    eq(frame.scale, 1.3, "cible agrandie")
    Mock.units.target = nil
    NPF:UpdateHighlight(frame)
    eq(frame.scale, 1, "plus la cible : taille normale")
    NPF.db.targetScale = 1
    -- Opacité des non-ciblées.
    Mock.units.nameplate2 = { name = "Ours", health = 100, healthMax = 100, level = 12, hostile = true }
    Mock.AddNamePlate("nameplate2")
    local other = NPF:GetFrame("nameplate2")
    NPF.db.nonTargetAlpha = 0.4
    Mock.units.target = Mock.units.nameplate1
    NPF:UpdateHighlight(other)
    eq(other:GetAlpha(), 0.4, "non ciblée : opacité réglée")
    NPF:UpdateHighlight(frame)
    eq(frame:GetAlpha(), 1, "cible : pleine opacité")
    -- Focus : gardé opaque comme la cible.
    Mock.units.focus = Mock.units.nameplate2
    NPF:UpdateHighlight(other)
    eq(other:GetAlpha(), 1, "focus : pleine opacité")
    Mock.units.focus = nil
    NPF.db.nonTargetAlpha = 0.7
    Mock.units.target = nil
    NS.Modules:SetEnabled("nameplateframes", false)
    Mock.namePlates = {}
end)

test("plaques : plaque recyclée, textes de la barre d'incantation à la même taille", function()
    reset()
    NS.Modules:SetEnabled("nameplateframes", true)
    Mock.units.nameplate1 = { name = "Loup", health = 300, healthMax = 400, level = 12, hostile = true }
    local plate = Mock.AddNamePlate("nameplate1")
    local frame = NPF:GetFrame("nameplate1")
    local first = frame.castbar.text.fontSize
    local firstTimer = frame.castbar.timeText.fontSize
    truthy(first and firstTimer, "tailles lisibles dans le mock")
    Mock.RemoveNamePlate("nameplate1")
    Mock.namePlates["nameplate1"] = plate
    Mock.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(frame.castbar.text.fontSize, first, "texte du sort : même taille au second montage")
    eq(frame.castbar.timeText.fontSize, firstTimer, "minuteur : même taille au second montage")
    NS.Modules:SetEnabled("nameplateframes", false)
    Mock.namePlates = {}
end)

test("rappels : clic du milieu masque jusqu'à l'écran de chargement suivant", function()
    reset()
    Mock.knownSpells[168] = true
    NS.Modules:SetEnabled("reminders", true)
    Reminders:Evaluate()
    local _, lines = Reminders:GetFrame()
    truthy(lines[1]:GetText(), "rappel affiché")
    local pass = lines[1].catcher.passThrough
    truthy(pass and table.concat(pass, ",") == "LeftButton,RightButton,Button4,Button5", "clics gauche et droit laissés passer")
    local text = lines[1]:GetText()
    lines[1].catcher.scripts.OnClick(lines[1].catcher, "MiddleButton")
    truthy(lines[1]:GetText() ~= text, "rappel masqué par le clic")
    Reminders:Evaluate()
    truthy(lines[1]:GetText() ~= text, "reste masqué à la réévaluation")
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    Mock.Advance(4)
    eq(lines[1]:GetText(), text, "écran de chargement : rappel rétabli")
    NS.Modules:SetEnabled("reminders", false)
end)
