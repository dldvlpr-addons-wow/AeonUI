-- tests/test_automation.lua : marchand, invitations, mort, suppression, butin, quêtes, reset.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Automation = NS.Modules:Get("automation")

local function FillJunk(count)
    Mock.items[100] = { sellPrice = 50 }
    Mock.items[200] = { sellPrice = 1000 }
    local bag, slot = 0, 1
    for _ = 1, count do
        Mock.bags[bag][slot] = { itemID = 100, quality = 0, stackCount = 2 }
        slot = slot + 1
        if slot > Mock.bagSize then bag, slot = bag + 1, 1 end
    end
    return bag, slot
end

test("vente : seulement les gris avec valeur, par lots de 10", function()
    reset()
    local bag, slot = FillJunk(12)
    Mock.bags[bag][slot] = { itemID = 200, quality = 1 }
    Mock.bags[bag][slot + 1] = { itemID = 100, quality = 0, hasNoValue = true }
    Mock.merchantOpen = true
    Mock.FireEvent("MERCHANT_SHOW")
    eq(#Mock.used, 10, "premier lot")
    Mock.Advance(0.25)
    eq(#Mock.used, 12, "second lot")
    truthy(Mock.bags[bag][slot], "blanc gardé")
    truthy(Mock.bags[bag][slot + 1], "gris sans valeur gardé")
    truthy(Mock.FindPrinted("12|cffc7c7cfs|r"), "total annoncé")
end)

test("vente : s'arrête quand le marchand se ferme", function()
    reset()
    FillJunk(25)
    Mock.merchantOpen = true
    Mock.FireEvent("MERCHANT_SHOW")
    Mock.merchantOpen = false
    Mock.FireEvent("MERCHANT_CLOSED")
    Mock.Advance(1)
    eq(#Mock.used, 10)
end)

test("réparation : guilde, puis or perso, puis rien", function()
    reset()
    Mock.merchantOpen = true
    Mock.repairCost = 500
    Mock.canGuildRepair, Mock.guildWithdraw = true, -1
    eq(Automation:Repair(), "guild")
    Mock.repairCost, Mock.guildWithdraw, Mock.money = 500, 100, 1000
    eq(Automation:Repair(), "self")
    Mock.repairCost, Mock.money = 500, 10
    eq(Automation:Repair(), "poor")
    eq(#Mock.repairs, 2)
    -- Maître de guilde (plafond -1) mais banque vide : repli sur l'or perso.
    Mock.repairCost, Mock.guildWithdraw, Mock.money, Mock.guildBankEmpty = 500, -1, 1000, true
    eq(Automation:Repair(), "guild", "guilde tentée d'abord")
    eq(#Mock.repairs, 3, "or perso seulement après la réponse du serveur")
    Mock.Advance(1)
    eq(Mock.repairs[3] .. "+" .. Mock.repairs[4], "guild+self", "banque vide : or perso")
    Mock.repairCost, Mock.money, Mock.guildBankEmpty = 0, 100000, false
end)

test("invitations : amis et guilde acceptés, inconnus et secrets ignorés", function()
    reset()
    Mock.friends["Player-2"] = "Ami"
    Mock.guildies["Player-3"] = true
    local before = Mock.acceptedGroup
    eq(Automation:OnInvite("Ami", "Player-2"), false, "option coupée par défaut")
    NS.db.modules.automation.acceptInvites = true
    eq(Automation:OnInvite("Ami", "Player-2"), true)
    eq(Automation:OnInvite("Guildeux", "Player-3"), true)
    eq(Automation:OnInvite("Inconnu", "Player-9"), false)
    Mock.secret["Player-2"] = true
    eq(Automation:OnInvite("Ami", "Player-2"), false, "GUID secret")
    Mock.secret = {}
    Mock.groupSize = 2
    eq(Automation:OnInvite("Ami", "Player-2"), false, "déjà en groupe")
    eq(Mock.acceptedGroup - before, 2)
    NS.db.modules.automation.acceptInvites = false
end)

test("invitations : popup marqué accepté avant fermeture (sinon Blizzard refuse)", function()
    reset()
    Mock.friends["Player-2"] = "Ami"
    NS.db.modules.automation.acceptInvites = true
    local popup = StaticPopup_Show("PARTY_INVITE")
    eq(Automation:OnInvite("Ami", "Player-2"), true)
    eq(popup.inviteAccepted, 1)
    NS.db.modules.automation.acceptInvites = false
end)

test("libération protégée : instance seulement, levée après ALT maintenu", function()
    reset()
    Mock.units.player.dead = true
    StaticPopup_Show("DEATH")
    Mock.FireEvent("PLAYER_DEAD")
    Mock.Advance(0.1)
    eq(Automation:IsReleaseBlocked(), false, "monde ouvert")
    Mock.instanceType = "party"
    Mock.FireEvent("PLAYER_DEAD")
    Mock.Advance(0.1)
    eq(Automation:IsReleaseBlocked(), true, "donjon")
    Mock.altDown = true
    Mock.Advance(0.5)
    Mock.altDown = false
    Mock.Advance(0.1)
    eq(Automation:IsReleaseBlocked(), true, "relâcher recommence")
    Mock.altDown = true
    Mock.Advance(1.1)
    eq(Automation:IsReleaseBlocked(), false, "libérable")
end)

test("suppression rapide : mot de confirmation pré-rempli", function()
    reset()
    eq(StaticPopup_Show("DELETE_GOOD_ITEM").editBox:GetText(), "DELETE")
    NS.db.modules.automation.fastDelete = false
    eq(StaticPopup_Show("DELETE_GOOD_ITEM").editBox:GetText(), nil)
    NS.db.modules.automation.fastDelete = true
end)

test("butin rapide : tout, du dernier au premier ; Maj = à la main", function()
    reset()
    Mock.lootCount = 3
    Mock.FireEvent("LOOT_READY")
    eq(table.concat(Mock.looted, ","), "3,2,1")
    Mock.looted = {}
    Mock.shift = true
    Mock.FireEvent("LOOT_READY")
    eq(#Mock.looted, 0, "Maj : rien")
end)

test("quêtes : acceptées/rendues, jamais de choix de récompense, Maj suspend", function()
    reset()
    Mock.FireEvent("QUEST_DETAIL")
    eq(#Mock.questLog, 0, "coupé par défaut")
    NS.db.modules.automation.autoQuests = true
    Mock.FireEvent("QUEST_DETAIL")
    Mock.questCompletable = true
    Mock.FireEvent("QUEST_PROGRESS")
    Mock.questChoices = 1
    Mock.FireEvent("QUEST_COMPLETE")
    Mock.questChoices = 3
    Mock.FireEvent("QUEST_COMPLETE")
    eq(table.concat(Mock.questLog, ","), "accept,complete,reward:1", "pas de récompense à choix multiple")
    Mock.questLog = {}
    Mock.gossip = { active = { { questID = 7, isComplete = true } }, available = { { questID = 9 } } }
    Mock.FireEvent("GOSSIP_SHOW")
    eq(Mock.questLog[1], "gossip-turnin:7", "rendre avant d'accepter")
    Mock.shift = true
    Mock.FireEvent("QUEST_DETAIL")
    eq(#Mock.questLog, 1, "Maj : suspendu")
    NS.db.modules.automation.autoQuests = false
end)

test("quêtes : répétables et payantes laissées au joueur", function()
    reset()
    NS.db.modules.automation.autoQuests = true
    Mock.gossip = { active = { { questID = 7, isComplete = true, repeatable = true } },
                    available = { { questID = 8, frequency = 1 }, { questID = 9 } } }
    Mock.FireEvent("GOSSIP_SHOW")
    eq(table.concat(Mock.questLog, ","), "gossip-accept:9", "répétable ni rendue ni acceptée")
    Mock.questLog = {}
    Mock.questCompletable = true
    _G.GetQuestMoneyToGet = function() return 500 end
    Mock.FireEvent("QUEST_PROGRESS")
    eq(#Mock.questLog, 0, "or demandé : pas validée")
    _G.GetQuestMoneyToGet = nil
    Mock.gossip = { active = {}, available = {} }
    NS.db.modules.automation.autoQuests = false
end)

test("réinitialisation annoncée au groupe, seulement pour ce message", function()
    reset()
    NS.db.modules.automation.announceReset = true
    Mock.groupSize = 3
    Mock.FireEvent("CHAT_MSG_SYSTEM", "Deadmines has been reset.")
    Mock.FireEvent("CHAT_MSG_SYSTEM", "You have been reset? no.")
    eq(#Mock.chat, 1)
    eq(Mock.chat[1].channel, "PARTY")
    eq(Automation.GlobalToPattern("%s has been reset."), "^(.+) has been reset%.$")
    Mock.FireEvent("CHAT_MSG_SYSTEM", Mock.SetSecret("Stratholme has been reset."))
    eq(#Mock.chat, 1, "message secret (chat verrouillé) : ignoré sans erreur")
    NS.db.modules.automation.announceReset = false
end)
