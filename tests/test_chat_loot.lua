-- tests/test_chat_loot.lua : étape 15, historique du chat, mots-clés, anti-spam, fenêtre de butin
-- et barres de jets.
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset
local Chat = NS.Modules:Get("chat")
local Loot = NS.Modules:Get("loot")

local function Filter(event, message, author, lineID)
    return Chat.MessageFilter(ChatFrame1, event, message, author, "", "", "", "", 0, 0, "", 0, lineID)
end

test("chat : historique mémorisé, borné, rejoué une fois, effacé", function()
    reset()
    ChatFrame1.messages = {}
    Chat:ClearHistory()
    NS.db.modules.chat.historyLines = 2
    NS.Modules:SetEnabled("chat", true)
    ChatFrame1:AddMessage("un", 1, 0, 0)
    ChatFrame1:AddMessage("deux")
    ChatFrame1:AddMessage("trois")
    ChatFrame1:AddMessage(Mock.SetSecret("secret"))
    local key = NS.Database.CharacterKey()
    local lines = NS.global.chatHistory[key].ChatFrame1
    eq(#lines, 2, "borné à historyLines, secret ignoré")
    eq(lines[1].text, "deux")
    ChatFrame1.messages = {}
    Chat.replayed = nil
    Chat:ReplayHistory({ ChatFrame1 })
    local shown = ChatFrame1.messages
    truthy(shown[1].text:find(L.CHAT_HISTORY_SEPARATOR, 1, true))
    eq(shown[2].text, "deux")
    eq(shown[3].text, "trois")
    truthy(shown[4].text:find(L.CHAT_HISTORY_END, 1, true))
    eq(#NS.global.chatHistory[key].ChatFrame1, 2, "le rejeu n'est pas remémorisé")
    Chat:ReplayHistory({ ChatFrame1 })
    eq(#ChatFrame1.messages, 4, "une fois par session")
    Chat:ClearHistory()
    eq(NS.global.chatHistory[key], nil)
    ChatFrame1:AddMessage("|Kf1|k ami BNet")
    eq(NS.global.chatHistory[key], nil, "code BNet non mémorisé")
    NS.db.modules.chat.historyLines = 100
    NS.Modules:SetEnabled("chat", false)
end)

test("chat : normalisation, mots-clés surlignés, son limité", function()
    reset()
    eq(Chat.Normalize("Heeeelp !! Moi"), Chat.Normalize("help moi"))
    eq(Chat.Normalize("|cffff0000|Hitem:1|h[Épée]|h|r"), Chat.Normalize("[Épée]"))
    NS.Modules:SetEnabled("chat", true)
    NS.db.modules.chat.keywords = " tank , heal"
    eq(Chat.HighlightKeywords("besoin TANK et heal", Chat.Keywords()),
        "besoin |cffff7f3fTANK|r et |cffff7f3fheal|r")
    eq(Chat.HighlightKeywords("rien", Chat.Keywords()), nil)
    local link = "|Hitem:1|h[tank]|h"
    eq(Chat.HighlightKeywords(link, Chat.Keywords()), link, "lien intact")
    local sounds = #Mock.sounds
    local hide, message = Filter("CHAT_MSG_SAY", "cherche tank", "Bob-Forever", 1)
    eq(hide, false)
    truthy(message:find("|cffff7f3ftank|r", 1, true))
    eq(#Mock.sounds, sounds + 1, "son joué")
    Filter("CHAT_MSG_SAY", "un tank ?", "Bob-Forever", 2)
    eq(#Mock.sounds, sounds + 1, "son limité à une fois par 5 s")
    eq(select(2, Filter("CHAT_MSG_SAY", "cherche tank", "Testeur", 3)), nil, "ses propres messages ignorés")
    eq(select(2, Filter("CHAT_MSG_SAY", "Testeur ?", "Bob", 4)) ~= nil, true, "nom du personnage")
    eq(Filter("CHAT_MSG_SAY", Mock.SetSecret("tank"), "Bob", 5), false, "message secret : laissé passer")
    NS.db.modules.chat.keywords = ""
    NS.Modules:SetEnabled("chat", false)
end)

test("chat : anti-spam tolérant, fenêtre de répétition, décision par lineID", function()
    reset()
    NS.Modules:SetEnabled("chat", true)
    NS.db.modules.chat.antiSpam = true
    NS.db.modules.chat.keywordName = false
    eq(Filter("CHAT_MSG_CHANNEL", "WTS épée !!!", "Spam", 10), false)
    eq(Filter("CHAT_MSG_CHANNEL", "WTS épée !!!", "Spam", 10), false, "même ligne, autre fenêtre")
    eq(Filter("CHAT_MSG_CHANNEL", "wts   ÉPÉE", "Spam", 11), false, "accents majuscules non repliés")
    eq(Filter("CHAT_MSG_CHANNEL", "w.t.s épéééée", "Spam", 12), true, "variante normalisée masquée")
    eq(Filter("CHAT_MSG_WHISPER", "WTS épée", "Spam", 13), false, "chuchotement jamais masqué")
    Mock.now = Mock.now + 61
    eq(Filter("CHAT_MSG_CHANNEL", "WTS épée", "Spam", 14), false, "fenêtre écoulée")
    NS.db.modules.chat.antiSpam = false
    NS.db.modules.chat.keywordName = true
    NS.Modules:SetEnabled("chat", false)
    eq(Filter("CHAT_MSG_CHANNEL", "WTS épée", "Spam", 15), false, "module coupé")
end)

local function Slots(...)
    Mock.lootSlots = { ... }
    Mock.lootCount = select("#", ...)
end

test("butin : fenêtre au thème, clic, emplacement vidé, fermeture, Blizzard rendu", function()
    reset()
    NS.Modules:SetEnabled("loot", true)
    eq(LootFrame:IsEventRegistered("LOOT_OPENED"), false, "LootFrame coupé")
    eq(UIParent:IsEventRegistered("START_LOOT_ROLL"), false, "jets Blizzard coupés")
    Slots({ "icone1", "Épée", 1, 4, false }, { "icone2", "Laine", 5, 1, false }, { "icone3", "Lettre", 1, 1, true })
    Loot:OpenWindow()
    local window = Loot:GetFrames()
    truthy(window:IsShown())
    eq(window.slots[1].name.text, "Épée")
    eq(window.slots[2].count.text, 5)
    eq(window.slots[1].name.textColor[1], NS.QualityColor(4))
    _G.GetLootMethod = function() return "group", nil, nil end
    LootFrame.selectedSlot = nil
    window.slots[1]:GetScript("OnClick")(window.slots[1])
    eq(LootFrame.selectedSlot, nil, "pas maître du butin : table Blizzard intacte")
    _G.GetLootMethod = function() return "master", 0, nil end
    window.slots[2]:GetScript("OnClick")(window.slots[2])
    eq(Mock.looted[2], 2)
    eq(LootFrame.selectedSlot, 2, "champs du maître du butin")
    _G.GetLootMethod = nil
    local _, onEvent = nil, NS.Modules:Get("loot")
    Mock.lootSlots[2] = nil
    Loot:OpenWindow()
    eq(window.slots[2].name.text, "Lettre", "emplacement vidé retiré")
    _G.IsModifiedClick = function() return true end
    _G.GetLootSlotLink = function(slot) return "lien" .. slot end
    local linked
    _G.HandleModifiedItemClick = function(link) linked = link end
    window.slots[1]:GetScript("OnClick")(window.slots[1])
    eq(linked, "lien1"); eq(#Mock.looted, 2, "clic modifié : lié, pas ramassé")
    _G.IsModifiedClick, _G.GetLootSlotLink, _G.HandleModifiedItemClick = nil, nil, nil
    local closed = Mock.closedLoot
    window:Hide()
    eq(Mock.closedLoot, closed + 1, "Échap : CloseLoot")
    Slots()
    closed = Mock.closedLoot
    Mock.FireEvent("LOOT_OPENED")
    eq(window:IsShown(), false, "rien à ramasser : pas de fenêtre")
    eq(Mock.closedLoot, closed + 1, "rien à ramasser : CloseLoot")
    NS.Modules:SetEnabled("loot", false)
    eq(LootFrame:IsEventRegistered("LOOT_OPENED"), true, "LootFrame rendu")
    eq(UIParent:IsEventRegistered("START_LOOT_ROLL"), true, "jets rendus")
end)

test("butin : barres de jets, choix interdits grisés, jet, annulation, secret ignoré", function()
    reset()
    NS.Modules:SetEnabled("loot", true)
    Mock.rollItems = {
        [7] = { "icone", "Bottes", 1, 3, false, true, true, false },
        [8] = { "icone", "Cape", 2, 2, false, false, true, true },
        [9] = { Mock.SetSecret("icone secrète"), "Secret", 1, 2 },
    }
    Loot:StartRoll(7, 60000)
    Loot:StartRoll(8, 60000)
    Loot:StartRoll(9, 60000)
    local _, _, bars = Loot:GetFrames()
    eq(#bars, 2, "jet à icône secrète ignoré")
    eq(bars[1].buttons.disenchant.disabled, true)
    eq(bars[2].buttons.need.disabled, true)
    eq(bars[2].name.text, "Cape x2")
    bars[1]:GetScript("OnUpdate")(bars[1])
    eq(bars[1].timer.value, 30000)
    bars[1].buttons.greed:GetScript("OnClick")(bars[1].buttons.greed)
    eq(Mock.rolls[1][1], 7); eq(Mock.rolls[1][2], 2)
    eq(bars[1].rollID, 7, "barre gardée jusqu'à CANCEL_LOOT_ROLL (confirmation)")
    Loot:CancelRoll(7)
    eq(bars[1].rollID, nil)
    Loot:CancelRoll(8)
    eq(bars[2]:IsShown(), false)
    NS.Modules:SetEnabled("loot", false)
end)
