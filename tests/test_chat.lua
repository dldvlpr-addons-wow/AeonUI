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

test("chat : barre de défilement cachée puis rendue, fond texturé teinté", function()
    Fresh()
    ChatFrame1.ScrollBar = CreateFrame("Frame", nil, ChatFrame1)
    Chat.db.hideScrollBar, Chat.db.backgroundTexture = true, "aeon:smooth"
    Enable()
    eq(ChatFrame1.ScrollBar:IsShown(), false, "cachée")
    Chat.db.hideScrollBar = false
    Chat:OnRefresh()
    eq(ChatFrame1.ScrollBar:IsShown(), true, "rendue")
    Disable()
    ChatFrame1.ScrollBar, Chat.db.backgroundTexture = nil, ""
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
    NS.db.modules.chat.noFade, NS.db.modules.chat.fadeTime = false, 30
    NS.Modules:Refresh("chat")
    eq(frame.fading, true)
    eq(frame:GetTimeVisible(), 30, "fondu après 30 s")
    NS.db.modules.chat.noFade, NS.db.modules.chat.fadeTime = true, 120
    frame.timeVisible = 30
    Disable()
    eq(frame:GetTimeVisible(), 120, "durée Blizzard d'origine rendue")
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

test("chat : onglet actif coloré et souligné, barre de raccourcis dans l'ordre choisi", function()
    Fresh()
    local db = NS.db.modules.chat
    db.sidebar, db.sidebarButtons = "left", "options, copy, inconnu, copy"
    _G.SELECTED_CHAT_FRAME = ChatFrame2
    Enable()
    local color = db.tabActiveColor
    eq(ChatFrame2Tab.Text.textColor[1], color.r, "onglet actif")
    eq(ChatFrame1Tab.Text.textColor[1], 0.65, "onglet inactif atténué")
    local sidebar = Chat:GetSidebar()
    truthy(sidebar:IsShown())
    eq(select(3, sidebar:GetPoint(1)), "TOPLEFT", "à gauche de la fenêtre 1")
    eq(sidebar.buttons[1].action, "options", "ordre de la liste")
    eq(sidebar.buttons[2].action, "copy")
    eq(sidebar.buttons[3], nil, "inconnus et doublons écartés")
    sidebar.buttons[2]:GetScript("OnClick")(sidebar.buttons[2])
    truthy(AeonUI_ChatCopy:IsShown(), "copie de la fenêtre active")
    AeonUI_ChatCopy:Hide()
    Disable()
    eq(sidebar:IsShown(), false, "cachée au disable")
    db.sidebar, db.sidebarButtons = "none", "copy, friends, channels, options"
    _G.SELECTED_CHAT_FRAME = nil
end)

test("bulles : thème, bordure au canal, canal décoché masqué, bulle interdite laissée", function()
    reset()
    local Bubbles = NS.Modules:Get("chatbubbles")
    local function Bubble(text)
        local bubble = CreateFrame("Frame", nil, WorldFrame)
        local holder = CreateFrame("Frame", nil, bubble)
        holder.String = holder:CreateFontString()
        holder.String:SetText(text)
        holder.skin = holder:CreateTexture()
        return bubble, holder
    end
    local say, sayHolder = Bubble("bonjour")
    local yell = Bubble("À L'AIDE")
    local forbidden, forbiddenHolder = Bubble("secret")
    function forbidden:IsForbidden() return true end
    _G.C_ChatBubbles = { GetAllChatBubbles = function() return { say, yell, forbidden } end }
    ChatTypeInfo.SAY.r, ChatTypeInfo.SAY.g, ChatTypeInfo.SAY.b = 1, 1, 1
    NS.db.modules.chatbubbles.yell = false
    NS.Modules:SetEnabled("chatbubbles", true)
    Mock.FireEvent("CHAT_MSG_SAY", "bonjour", "Bob")
    Mock.FireEvent("CHAT_MSG_YELL", "À L'AIDE", "Bob")
    Mock.Advance(0.1)
    eq(sayHolder.skin.alpha, 0, "texture Blizzard cachée")
    eq(sayHolder.String.font, NS.db.theme.font, "police du thème")
    eq(Bubbles.ChannelOf("bonjour"), "say")
    eq(yell:GetAlpha(), 0, "crier décoché : masquée")
    eq(say:GetAlpha(), 1)
    eq(forbiddenHolder.skin.alpha, nil, "bulle interdite : intacte")
    NS.Modules:SetEnabled("chatbubbles", false)
    eq(sayHolder.skin.alpha, 1, "rendue au disable")
    eq(yell:GetAlpha(), 1)
    NS.db.modules.chatbubbles.yell = true
    _G.C_ChatBubbles = nil
end)

test("chat : fenêtres gauche et droite sur movers, tailles des options, redimensionnement repris", function()
    Fresh()
    Mock.chatWindows = { [2] = { shown = true, docked = true }, [3] = { shown = true, docked = false } }
    Enable()
    eq(Chat.RightWindow(), ChatFrame3, "première fenêtre détachée")
    eq(ChatFrame1:GetWidth(), 430)
    eq(ChatFrame3:GetHeight(), 160)
    truthy(NS.Movers.registry.chatLeft, "mover gauche")
    truthy(NS.Movers.registry.chatRight, "mover droite")
    local point, holder = ChatFrame1:GetPoint()
    eq(point, "BOTTOMLEFT")
    eq(holder, NS.Movers.adopted.chatLeft.holder, "posée sur son mover")
    Chat.db.rightWidth = 100
    NS.Modules:Refresh("chat")
    eq(ChatFrame3:GetWidth(), 296, "borne du client")
    ChatFrame1:SetSize(512, 200)
    ChatFrame2.isDocked = true
    FCF_SavePositionAndDimensions(ChatFrame2)          -- fenêtre dockée : redimensionne ChatFrame1
    eq(Chat.db.leftWidth, 512, "taille reprise dans les options")
    eq(Chat.db.leftHeight, 200)
    Mock.chatWindows[2] = { shown = true, docked = false }   -- ChatFrame2 sortie du dock
    ChatFrame2.isDocked = nil
    ChatFrame2:SetSize(430, 180)
    FCF_SavePositionAndDimensions(ChatFrame2)
    eq(Chat.RightWindow(), ChatFrame3, "fenêtre gérée gardée")
    eq(Chat.db.rightWidth, 100, "taille de droite intacte")
    eq(NS.Movers.registry.chatRight.module, "chat", "mover rattaché au module")
    Chat.db.windows = false
    NS.Modules:Refresh("chat")
    eq(NS.Movers.registry.chatLeft, nil, "option coupée : movers retirés")
    Chat.db.windows = true
    Disable()
    eq(NS.Movers.registry.chatRight, nil, "module coupé : movers retirés")
    Mock.chatWindows, ChatFrame2.isDocked = {}, nil
    Chat.db.leftWidth, Chat.db.leftHeight, Chat.db.rightWidth = 430, 180, 320
end)
