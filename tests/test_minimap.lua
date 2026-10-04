-- tests/test_minimap.lua : minimap AeonUI (étape 6).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local MM = NS.Modules:Get("minimap")

local function Enable() NS.Modules:SetEnabled("minimap", true) end
local function Disable() NS.Modules:SetEnabled("minimap", false) end

test("minimap : carrée, réancrée sur le support, décor caché, zone colorée, mover", function()
    reset()
    Mock.zoneText, Mock.pvpType = "Orgrimmar", "sanctuary"
    Enable()
    local holder = _G.AeonUI_Minimap
    truthy(holder and holder:IsShown())
    eq(Minimap.mask, 130937)
    eq(Minimap:GetWidth(), 180)
    local _, relTo = Minimap:GetPoint()
    eq(relTo, holder, "ancrée sur le support")
    eq(Minimap:GetParent(), MinimapCluster.MinimapContainer, "reparentage différé d'une image")
    Mock.Advance(0.1)
    eq(Minimap:GetParent(), holder, "sortie du cluster : sinon rendu découpé, carte visible après un ping seulement")
    Minimap:SetParent(MinimapCluster.MinimapContainer)
    Mock.Advance(0.1)
    eq(Minimap:GetParent(), holder, "Blizzard la replace : reprise")
    eq(MinimapCluster.BorderTop:IsShown(), false)
    eq(MinimapCluster.ZoneTextButton:IsShown(), false, "zone Blizzard cachée : AeonUI la dessine")
    eq(holder.zone:GetText(), "Orgrimmar")
    eq(holder.zone.textColor[1], 0.41)
    local _, tracking = MinimapCluster.Tracking:GetPoint()
    eq(tracking, Minimap, "bouton de suivi réancré sur la carte")
    truthy(NS.Movers:Anchor("minimap"))
    -- Blizzard réancre la carte : le hook reprend la main.
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", MinimapCluster, "CENTER", 0, 0)
    local _, again = Minimap:GetPoint()
    eq(again, holder)
    -- Molette.
    Mock.Advance(0.1)   -- rendu forcé à l'activation terminé
    Minimap:GetScript("OnMouseWheel")(Minimap, 1)
    eq(Minimap:GetZoom(), 1)
    Minimap:GetScript("OnMouseWheel")(Minimap, -1)
    eq(Minimap:GetZoom(), 0)
    NS.db.modules.minimap.wheelZoom = false
    NS.Modules:Refresh("minimap")
    Mock.Advance(0.1)
    truthy(Minimap:GetScript("OnMouseWheel"), "molette coupée : notre gestionnaire reste, jamais celui de Blizzard")
    Minimap:GetScript("OnMouseWheel")(Minimap, 1)
    eq(Minimap:GetZoom(), 0, "molette coupée : pas de zoom")
    NS.db.modules.minimap.wheelZoom = true
    Disable()
    eq(Minimap:GetParent(), MinimapCluster.MinimapContainer, "parent d'origine rendu")
    eq(holder:IsShown(), false)
    truthy(MinimapCluster.BorderTop:IsShown())
    eq(Minimap.mask, 186178)
    eq(Minimap:GetScript("OnMouseWheel"), nil)
    truthy(Mock.FindPrinted("/reload"))
    Mock.zoneText, Mock.pvpType = nil, nil
end)

test("minimap : boutons d'addons regroupés sous la carte, rendus au disable ; coordonnées", function()
    reset()
    local libButton = CreateFrame("Button", "LibDBIcon10_Recount", Minimap)
    local blizzardButton = CreateFrame("Button", "MiniMapMailFrame", Minimap)
    local other = CreateFrame("Button", "SomeAddonMinimapButton", Minimap)
    NS.db.modules.minimap.coords, NS.db.modules.minimap.buttonBar = true, "hover"
    Mock.mapID, Mock.mapPosition = 1, { 0.5, 0.25 }
    Enable()
    local bar = _G.AeonUI_MinimapButtons
    eq(libButton:GetParent(), bar)
    eq(other:GetParent(), bar)
    eq(blizzardButton:GetParent(), Minimap, "bouton Blizzard laissé en place")
    eq(bar:GetAlpha(), 0, "mode survol : caché au repos")
    Minimap.scripts.OnEnter(Minimap)
    eq(bar:GetAlpha(), 1)
    eq(_G.AeonUI_Minimap.coords:GetText(), "50.0, 25.0")
    NS.db.modules.minimap.buttonBar = "always"
    NS.Modules:Refresh("minimap")
    eq(bar:GetAlpha(), 1)
    Disable()
    eq(libButton:GetParent(), Minimap, "rendu à la carte")
    NS.db.modules.minimap.coords, NS.db.modules.minimap.buttonBar = false, "button"
    Mock.mapID, Mock.mapPosition = nil, nil
end)

test("minimap : coordonnées au survol et précision, FPS/MS, difficulté compacte", function()
    reset()
    local db = NS.db.modules.minimap
    db.coords, db.coordsMode, db.coordsPrecision, db.performance, db.compactDifficulty = true, "hover", 2, true, true
    Mock.mapID, Mock.mapPosition = 1, { 0.5, 0.25 }
    local difficulty = CreateFrame("Frame", "MiniMapInstanceDifficulty", Minimap)
    _G.GetInstanceInfo = function() return "Donjon", "party", 2, "Héroïque", 5 end
    _G.GetDifficultyInfo = function() return "Héroïque", "party", true, false, true, false end
    Enable()
    local holder = _G.AeonUI_Minimap
    eq(holder.coords:GetText(), "50.00, 25.00", "deux décimales")
    eq(holder.coords:GetAlpha(), 0, "survol : cachées au repos")
    Minimap.scripts.OnEnter(Minimap)
    eq(holder.coords:GetAlpha(), 1)
    Minimap.scripts.OnLeave(Minimap)
    eq(holder.coords:GetAlpha(), 0)
    eq(holder.performance:GetText(), "60 fps  |cff33dd3350 ms|r")
    eq(MM.LatencyColor(300), "ffff3333")
    eq(holder.difficulty:GetText(), "5H")
    eq(difficulty:GetAlpha(), 0, "drapeau Blizzard masqué")
    _G.GetInstanceInfo = function() return "", "none", 0, "", 0 end
    Mock.FireEvent("ZONE_CHANGED_NEW_AREA")
    eq(holder.difficulty:GetText(), "", "hors instance : rien")
    Disable()
    eq(difficulty:GetAlpha(), 1, "drapeau rendu")
    _G.GetInstanceInfo, _G.GetDifficultyInfo, _G.MiniMapInstanceDifficulty = nil, nil, nil
    db.coords, db.coordsMode, db.coordsPrecision, db.performance, db.compactDifficulty = false, "always", 1, false, false
    Mock.mapID, Mock.mapPosition = nil, nil
end)

test("minimap : mode par défaut, un bouton dans la carte, un clic ouvre la grille d'addons à côté", function()
    reset()
    local first = CreateFrame("Button", "LibDBIcon10_Details", Minimap)
    local second = CreateFrame("Button", "LibDBIcon10_Recount", Minimap)
    Enable()
    local bar, toggle = _G.AeonUI_MinimapButtons, _G.AeonUI_MinimapButtonsToggle
    truthy(toggle:IsShown())
    eq(first:GetParent(), bar)
    eq(second:GetParent(), bar)
    truthy(toggle.text:GetText():find("^%d+$"), "compteur d'addons")
    local point, relativeTo, relativePoint = toggle:GetPoint(1)
    eq(point, "BOTTOM"); eq(relativeTo, _G.AeonUI_Minimap); eq(relativePoint, "BOTTOM")
    eq(bar:IsShown(), false, "grille fermée au repos")
    toggle:GetScript("OnClick")(toggle)
    eq(bar:IsShown(), true)
    eq(bar:GetAlpha(), 1)
    toggle:GetScript("OnClick")(toggle)
    eq(bar:IsShown(), false)
    NS.db.modules.minimap.buttonBar = "hover"
    NS.Modules:Refresh("minimap")
    eq(toggle:IsShown(), false, "autre mode : bouton caché")
    NS.db.modules.minimap.buttonBar = "button"
    Disable()
    eq(first:GetParent(), Minimap, "rendu à la carte")
end)

test("minimap : cède à SexyMap", function()
    reset()
    Mock.loadedAddons.SexyMap = true
    Enable()
    eq(_G.AeonUI_Minimap and _G.AeonUI_Minimap:IsShown() or false, false)
    Mock.loadedAddons.SexyMap = nil
    Disable()
end)

test("minimap : rendu forcé par un zoom décalé, rendu l'image suivante (sinon carte noire jusqu'au ping)", function()
    reset()
    Enable()
    Mock.Advance(0.1)
    Minimap.zoom = 2
    local log = {}
    local original = Minimap.SetZoom
    Minimap.SetZoom = function(self, z) log[#log + 1] = z original(self, z) end
    NS.db.modules.minimap.size = 240
    NS.Modules:Refresh("minimap")
    eq(#log, 1, "zoom décalé")
    eq(log[1], 3)
    Mock.Advance(0.1)
    eq(log[2], 2)
    eq(Minimap:GetZoom(), 2, "zoom d'origine rendu l'image suivante")
    log = {}
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
    Mock.Advance(0.1)
    eq(log[1], 3, "entrée en jeu : rendu forcé") eq(Minimap:GetZoom(), 2)
    Minimap.SetZoom = original
    Disable()
end)
