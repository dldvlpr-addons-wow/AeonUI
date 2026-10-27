-- tests/test_g_chat_minimap.lua : chat (canaux en lettres), minimap (performance, difficulté, bordure),
-- barres de données (graduations, couleur), panneaux (alignement), barre du haut (latence), volume.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Chat = NS.Modules:Get("chat")
local MinimapFrame = NS.Modules:Get("minimap")
local DataBars = NS.Modules:Get("databars")
local DataPanels = NS.Modules:Get("datapanels")
local TopBar = NS.Modules:Get("topbar")

test("chat : canaux en une lettre (initiale UTF-8, idempotent)", function()
    eq(Chat.ShortenChannels("|Hchannel:channel:2|h[2. Commerce]|h Bob", true), "|Hchannel:channel:2|h[C]|h Bob")
    eq(Chat.ShortenChannels("|Hchannel:PARTY|h[Groupe]|h x", true), "|Hchannel:PARTY|h[G]|h x")
    eq(Chat.ShortenChannels("|Hchannel:GUILD|h[Édition]|h", true), "|Hchannel:GUILD|h[É]|h", "initiale accentuée entière")
    local once = Chat.ShortenChannels("|Hchannel:channel:2|h[2. Commerce]|h", true)
    eq(Chat.ShortenChannels(once, true), once, "idempotent")
    eq(Chat.ShortenChannels("|Hchannel:channel:2|h[2. Commerce]|h"), "|Hchannel:channel:2|h[2]|h", "mode chiffre inchangé")
end)

test("minimap : texte FPS et latence selon le mode", function()
    local format = MinimapFrame.FormatPerformance
    local worst = format(60, 40, 120, "worst")
    truthy(worst:find("120", 1, true) and not worst:find("40", 1, true), "la pire")
    truthy(format(60, 40, 120, "home"):find("40", 1, true), "domicile")
    truthy(format(60, 40, 120, "world"):find("120", 1, true), "monde")
    truthy(format(60, 40, 120, "both"):find("/", 1, true), "les deux")
    truthy(format(60, 40, 120, "worst", "ff112233"):find("|cff112233fps|r", 1, true), "suffixe à l'accent")
end)

test("minimap : difficulté colorée par palier, bordure selon le mode", function()
    eq(MinimapFrame.ColorDifficulty("5H"), "|cffff80405H|r")
    eq(MinimapFrame.ColorDifficulty("25M"), "|cffa335ee25M|r")
    eq(MinimapFrame.ColorDifficulty("10"), "10", "normal inchangé")
    eq(MinimapFrame.BorderColor({ borderMode = "theme" }), nil, "thème : pas de couleur")
    local r, g, b = MinimapFrame.BorderColor({ borderMode = "custom", borderColor = { r = .1, g = .2, b = .3 } })
    truthy(math.abs(r + g + b - .6) < 1e-9, "personnalisée")
end)

test("barres de données : graduations 5 et 10 %, couleur de remplissage", function()
    eq(DataBars.SeparatorStep("5"), 5)
    eq(DataBars.SeparatorStep("10"), 10)
    eq(DataBars.SeparatorStep("none"), nil)
    local frame = CreateFrame("Frame")
    frame.bar, frame.separators = CreateFrame("StatusBar", nil, frame), {}
    local function visible()
        local count = 0
        for _, line in ipairs(frame.separators) do if line:IsShown() then count = count + 1 end end
        return count
    end
    DataBars.LayoutSeparators(frame, { separators = "5", width = 200, orientation = "HORIZONTAL" })
    eq(visible(), 19, "5 %")
    DataBars.LayoutSeparators(frame, { separators = "10", width = 200, orientation = "HORIZONTAL" })
    eq(visible(), 9, "10 %")
    DataBars.LayoutSeparators(frame, { separators = "none", width = 200, orientation = "HORIZONTAL" })
    eq(visible(), 0, "aucune")
    local r = DataBars.FillColor({ customColor = true, color = { r = .5, g = .6, b = .7 } }, { 1, 1, 1 })
    eq(r, .5, "personnalisée")
    eq((DataBars.FillColor({ customColor = false }, { .1, .2, .3 })), .1, "défaut")
end)

test("panneaux : alignement du texte", function()
    local button = CreateFrame("Button")
    button.label = button:CreateFontString()
    local justify
    button.label.SetJustifyH = function(_, value) justify = value end
    DataPanels.AlignLabel(button, "LEFT")
    eq(justify, "LEFT")
    DataPanels.AlignLabel(button, "bidon")
    eq(justify, "CENTER", "repli centre")
end)

test("barre du haut : latence selon le mode", function()
    local worst = TopBar.LatencyText(40, 120, "worst")
    truthy(worst:find("120|r", 1, true) and not worst:find("40|r", 1, true), "la pire")
    truthy(TopBar.LatencyText(40, 120, "both"):find("40|r/", 1, true), "les deux")
    truthy(TopBar.LatencyText(40, 120, "home"):find("40|r", 1, true), "domicile")
end)

test("textes de données : volume principal borné par pas de 10 %", function()
    local DataTexts = NS.DataTexts
    eq(DataTexts.NextVolume(0.5, "LeftButton"), 0.6)
    eq(DataTexts.NextVolume(0.5, "RightButton"), 0.4)
    eq(DataTexts.NextVolume(1, "LeftButton"), 1, "plafond")
    eq(DataTexts.NextVolume(0, "RightButton"), 0, "plancher")
    eq(DataTexts.NextVolume(nil, "LeftButton"), nil, "illisible")
end)

test("chat : poignée de redimensionnement cachée seulement si fenêtres gérées et taille verrouillée", function()
    reset()
    NS.Modules:SetEnabled("chat", true)
    local handle = CreateFrame("Button", nil, ChatFrame1)
    ChatFrame1.ResizeButton = handle
    Chat.db.windows, Chat.db.lockSize = true, true
    handle:Show()
    Chat.ApplyLockSize(ChatFrame1)
    eq(handle:IsShown(), false, "verrouillée : cachée")
    Chat.db.windows = false
    handle:Show()
    Chat.ApplyLockSize(ChatFrame1)
    eq(handle:IsShown(), true, "fenêtres non gérées : Blizzard garde la main")
    Chat.db.lockSize = false
    ChatFrame1.ResizeButton = nil
    NS.Modules:SetEnabled("chat", false)
end)

test("bulles : CVars coupées en instance, origine gardée en base puis rendue", function()
    reset()
    local Bubbles = NS.Modules:Get("chatbubbles")
    Mock.cvars.chatBubbles, Mock.cvars.chatBubblesParty = "1", "0"
    Bubbles.db.hideInInstance = false
    NS.Modules:SetEnabled("chatbubbles", true)
    eq(NS.global.cvarBackup.chatBubbles, nil, "option jamais utilisée : rien écrit")
    Bubbles.db.hideInInstance = true
    Mock.instanceType = "party"
    Bubbles.ApplyInstanceCVars()
    eq(Mock.cvars.chatBubbles, "0", "coupée en instance")
    eq(NS.global.cvarBackup.chatBubbles, "1", "origine gardée en base")
    Mock.instanceType = "none"
    Bubbles.ApplyInstanceCVars()
    eq(Mock.cvars.chatBubbles, "1", "rendue à la sortie")
    eq(Mock.cvars.chatBubblesParty, "0", "valeur d'origine de l'autre CVar")
    eq(NS.global.cvarBackup.chatBubbles, nil, "sauvegarde effacée")
    Mock.instanceType = "party"
    Bubbles.ApplyInstanceCVars()
    Bubbles.db.hideInInstance = false
    Bubbles.ApplyInstanceCVars()
    eq(Mock.cvars.chatBubbles, "1", "option coupée : rendue")
    Mock.instanceType = "none"
    Bubbles.db.hideInInstance = true
    NS.Modules:SetEnabled("chatbubbles", false)
end)

test("minimap : échelle d'origine du bouton de file gardée puis rendue", function()
    reset()
    local queue = _G.QueueStatusButton or CreateFrame("Button", "QueueStatusButton", UIParent)
    queue:SetScale(0.8)
    MinimapFrame.db.decorScale = 1
    NS.Modules:SetEnabled("minimap", true)
    eq(queue:GetScale(), 0.8, "échelle 1 : celle d'Edit Mode intacte")
    MinimapFrame.db.decorScale = 1.5
    NS.Modules:Refresh("minimap")
    truthy(math.abs(queue:GetScale() - 1.2) < 1e-9, "origine x réglage")
    MinimapFrame.db.hideDecor = false
    NS.Modules:Refresh("minimap")
    eq(queue:GetScale(), 0.8, "décor non géré : origine rendue")
    MinimapFrame.db.hideDecor = true
    NS.Modules:Refresh("minimap")
    NS.Modules:SetEnabled("minimap", false)
    eq(queue:GetScale(), 0.8, "module coupé : origine rendue")
    MinimapFrame.db.decorScale = 1
end)
