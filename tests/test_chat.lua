-- tests/test_chat.lua : chat AeonUI (étape 6).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Chat = NS.Modules:Get("chat")

local function Fresh()
    reset()
    ChatFrame1.messages, ChatFrame1.fading, ChatFrame1Background.alpha = {}, nil, nil
end
local function Enable() NS.Modules:SetEnabled("chat", true) end
local function Disable() NS.Modules:SetEnabled("chat", false) end

test("chat : transformations pures (URL, canaux courts, nettoyage)", function()
    local linked = Chat.LinkURLs("regarde https://forever.gg/x, ok")
    eq(linked, "regarde |Hurl:https://forever.gg/x|h|cff3399ff[https://forever.gg/x]|r|h, ok")
    eq(Chat.LinkURLs(linked), linked, "pas de double enrobage")
    truthy(Chat.LinkURLs("voir www.wowhead.com/item=1"):find("|Hurl:www.wowhead.com/item=1|h", 1, true))
    eq(Chat.ShortenChannels("|Hchannel:channel:2|h[2. Commerce]|h Bob: salut"), "|Hchannel:channel:2|h[2]|h Bob: salut")
    eq(Chat.CleanLine("|TInterface\\Icons\\x:16|t |cffff0000|Hitem:1|h[Épée]|h|r ok"), " [Épée] ok")
    eq(Chat.CleanLine("|cnNORMAL_FONT_COLOR:Guilde|r ok"), "Guilde ok", "couleur nommée")
end)

test("chat : habillage, police, onglets, boutons, AddMessage enrobé, rendu au disable", function()
    Fresh()
    Enable()
    local frame = ChatFrame1
    eq(frame.font, NS.db.theme.font)
    eq(frame.fontSize, 12)
    eq(frame.fading, false)
    eq(frame:GetMaxLines(), 1000)
    eq(ChatFrame1Background.alpha, 0, "texture Blizzard invisible")
    eq(ChatFrame1TabLeft.alpha, 0, "onglet plat")
    truthy(NS.IsRegionHidden(ChatFrame1ButtonFrame))
    truthy(NS.IsRegionHidden(ChatFrameMenuButton))
    eq(ChatTypeInfo.SAY.colorNameByClass, true)
    eq(NS.global.chatClassColors[NS.Database.CharacterKey()].SAY, false, "origine gardée dans la base (/reload)")
    local _, relTo, relPoint = frame.editBox:GetPoint()
    eq(relTo, frame); eq(relPoint, "BOTTOMLEFT")
    frame:AddMessage("|Hchannel:channel:2|h[2. Commerce]|h Bob: https://a.b/c")
    eq(frame.messages[1].text, "|Hchannel:channel:2|h[2]|h Bob: |Hurl:https://a.b/c|h|cff3399ff[https://a.b/c]|r|h")
    NS.db.modules.chat.editBoxTop = true
    NS.Modules:Refresh("chat")
    local _, _, top = frame.editBox:GetPoint()
    eq(top, "TOPLEFT")
    NS.db.modules.chat.editBoxTop = false
    Disable()
    eq(frame.font, "Fonts\\FRIZQT__.TTF")
    eq(frame.fontSize, 14)
    eq(ChatFrame1Background.alpha, 1)
    eq(NS.IsRegionHidden(ChatFrameMenuButton), false)
    eq(ChatTypeInfo.SAY.colorNameByClass, false, "état Blizzard rendu")
    eq(NS.global.chatClassColors[NS.Database.CharacterKey()], nil, "sauvegarde effacée une fois rendue")
    frame:AddMessage("https://x.y")
    eq(frame.messages[2].text, "https://x.y", "plus de transformation")
end)

test("chat : copie de la fenêtre, clic sur une URL, horodatage par CVar", function()
    Fresh()
    Enable()
    ChatFrame1:AddMessage("|cff00ff00[Guilde]|r Alice: bonjour")
    ChatFrame1:AddMessage("Bob: ok")
    Chat:CopyWindow(ChatFrame1)
    truthy(AeonUI_ChatCopy:IsShown())
    eq(AeonUI_ChatCopy.edit:GetText(), "[Guilde] Alice: bonjour\nBob: ok")
    SetItemRef("url:https://forever.gg")
    eq(AeonUI_ChatCopy.edit:GetText(), "https://forever.gg")
    NS.db.modules.chat.timestamps = "%H:%M "
    NS.Modules:Refresh("chat")
    eq(C_CVar.GetCVar("showTimestamps"), "%H:%M ")
    NS.db.modules.chat.timestamps = "none"
    Disable()
    eq(C_CVar.GetCVar("showTimestamps"), "none")
end)

test("chat : cède à Prat", function()
    Fresh()
    Mock.loadedAddons["Prat-3.0"] = true
    Enable()
    eq(ChatFrame1.fading, nil)
    Mock.loadedAddons["Prat-3.0"] = nil
    Disable()
end)

test("chat : couleur et opacité du fond propres aux fenêtres", function()
    Fresh()
    NS.db.modules.chat.background = { r = 0.2, g = 0.3, b = 0.4, a = 0.25 }
    Enable()
    local bg
    -- Le fond est la texture BACKGROUND créée par Media:CreateBackdrop sur ChatFrame1.
    for _, region in ipairs(ChatFrame1.regions or {}) do
        if region.color and region.color[4] == 0.25 then bg = region end
    end
    truthy(bg, "fond peint avec l'alpha du réglage")
    eq(bg.color[1], 0.2)
    Disable()
end)
