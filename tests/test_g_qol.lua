-- tests/test_g_qol.lua : lot G QoL : utilitaire de raid, flux de butin, alerte de mouvement,
-- couleur de classe des alertes, fond de la carte, gain de vente en icônes.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("raid : boutons du panneau masqués un par un, le reste remonte", function()
    reset()
    local Raid = NS.Modules:Get("raidutility")
    NS.Modules:SetEnabled("raidutility", true)
    local _, panel = Raid:GetFrames()
    local full = panel:GetHeight()
    truthy(panel.actions[2]:IsShown(), "rôles visibles par défaut")
    Raid.db.showRoleCheck = false
    Raid.db.showDisband = false
    Raid.db.panelScale = 1.5
    NS.Modules:Refresh("raidutility")
    eq(panel.actions[2]:IsShown(), false, "rôles masqués")
    eq(panel.actions[5]:IsShown(), false, "dissolution masquée")
    truthy(panel.actions[4]:IsShown(), "conversion gardée")
    truthy(panel:GetHeight() < full, "panneau raccourci")
    eq(panel:GetScale(), 1.5, "échelle")
    Raid.db.showRoleCheck, Raid.db.showDisband, Raid.db.panelScale = true, true, 1
    NS.Modules:Refresh("raidutility")
    eq(panel:GetHeight(), full, "taille d'origine rendue")
    NS.Modules:SetEnabled("raidutility", false)
end)

test("flux de butin : nombre de lignes limité par le réglage", function()
    reset()
    local LootFeed = NS.Modules:Get("lootfeed")
    NS.Modules:SetEnabled("lootfeed", true)
    LootFeed.db.maxLines = 2
    NS.Modules:Refresh("lootfeed")
    for id = 1, 4 do
        LootFeed:Add({ key = "item:" .. id, kind = "item", quantity = 1, label = "x" .. id })
    end
    local live = 0
    for _, line in ipairs(LootFeed.Lines()) do if line.key then live = live + 1 end end
    eq(live, 2, "deux lignes vivantes")
    LootFeed.db.maxLines = 6
    NS.Modules:SetEnabled("lootfeed", false)
end)

test("alerte de mouvement : en combat seulement", function()
    reset()
    local MovementAlert = NS.Modules:Get("movementalert")
    NS.Modules:SetEnabled("movementalert", true)
    MovementAlert.db.combatOnly = true
    NS.Modules:Refresh("movementalert")
    local holder = _G.MuscaUIMovementAlert
    eq(holder:IsShown(), false, "hors combat : caché")
    Mock.SetCombat(true)
    truthy(holder:IsShown(), "en combat : visible")
    Mock.SetCombat(false)
    eq(holder:IsShown(), false, "sortie de combat : caché")
    MovementAlert.db.combatOnly = false
    NS.Modules:SetEnabled("movementalert", false)
end)

test("alerte de combat : couleur de classe", function()
    reset()
    local Alerts = NS.Modules:Get("alerts")
    Alerts.db.combatClassColor = true
    _G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    Mock.SetCombat(true)
    local r, g, b = Alerts:GetFlash().text:GetTextColor()
    truthy(math.abs(r - 0.25) < 0.01 and math.abs(g - 0.78) < 0.01 and math.abs(b - 0.92) < 0.01, "couleur du mage")
    Mock.SetCombat(false)
    Alerts.db.combatClassColor = false
end)

test("carte du monde : fond noir allégé puis rendu", function()
    reset()
    local Interface = NS.Modules:Get("interface")
    local blackoutFrame = CreateFrame("Frame")
    blackoutFrame.Blackout = blackoutFrame:CreateTexture()
    local previous = _G.WorldMapFrame
    _G.WorldMapFrame = CreateFrame("Frame")
    _G.WorldMapFrame.BlackoutFrame = blackoutFrame
    Interface.db.mapFade = true
    NS.Modules:Refresh("interface")
    eq(blackoutFrame.Blackout:GetAlpha(), 0.2, "allégé")
    Interface.db.mapFade = false
    NS.Modules:Refresh("interface")
    eq(blackoutFrame.Blackout:GetAlpha(), 1, "opaque rendu")
    _G.WorldMapFrame = previous
end)

test("vente : gain en icônes de pièces seulement si demandé", function()
    reset()
    C_CurrencyInfo = C_CurrencyInfo or {}
    local previous = C_CurrencyInfo.GetCoinTextureString
    C_CurrencyInfo.GetCoinTextureString = function(copper) return "ICONS:" .. copper end
    eq(NS.FormatMoneyIcons(12345), "ICONS:12345", "icônes")
    C_CurrencyInfo.GetCoinTextureString = nil
    eq(NS.FormatMoneyIcons(12345), NS.FormatMoney(12345), "repli lettres")
    C_CurrencyInfo.GetCoinTextureString = previous
end)

test("/cd : enregistré seulement une fois coché, ouvre puis ferme le panneau", function()
    reset()
    local Interface = NS.Modules:Get("interface")
    local shown, hidden = 0, 0
    local open = false
    local previous = _G.CooldownViewerSettings
    _G.CooldownViewerSettings = {
        ShowUIPanel = function() shown = shown + 1 open = true end,
        Hide = function() hidden = hidden + 1 open = false end,
        IsShown = function() return open end,
    }
    eq(SlashCmdList.MUSCAUICOOLDOWNS, nil, "décoché : pas de commande")
    Interface.db.slashCooldowns = true
    NS.Modules:Refresh("interface")
    SlashCmdList.MUSCAUICOOLDOWNS("")
    eq(shown, 1, "coché : ouvert")
    SlashCmdList.MUSCAUICOOLDOWNS("")
    eq(hidden, 1, "déjà ouvert : fermé")
    Interface.db.slashCooldowns = false
    SlashCmdList.MUSCAUICOOLDOWNS("")
    eq(shown, 1, "décoché ensuite : rien")
    _G.CooldownViewerSettings = previous
end)

test("fenêtres déplaçables : sans modificateur, un simple clic ne garde rien", function()
    reset()
    local MovableWindows = NS.Modules:Get("movablewindows")
    local frame = _G.MerchantFrame or CreateFrame("Frame", "MerchantFrame", UIParent)
    NS.Modules:SetEnabled("movablewindows", true)
    MovableWindows.db.dragWithoutModifier = true
    local left, top = 100, 500
    frame.GetLeft, frame.GetTop = function() return left end, function() return top end
    local function Drag(deltaX)
        frame:GetScript("OnMouseDown")(frame, "LeftButton")
        left = left + deltaX
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        frame:GetScript("OnMouseUp")(frame, "LeftButton")
    end
    Drag(0)
    eq(MovableWindows.db.positions.MerchantFrame, nil, "clic : rien")
    Drag(40)
    eq(MovableWindows.db.positions.MerchantFrame[3], 140, "glissé : gardé")
    MovableWindows.db.positions, MovableWindows.db.dragWithoutModifier = {}, false
    frame.GetLeft, frame.GetTop = nil, nil
    NS.Modules:SetEnabled("movablewindows", false)
end)
