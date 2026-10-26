-- Modules/Automation.lua
-- Petits automatismes, chacun avec son interrupteur :
--   * réparation chez le marchand (banque de guilde d'abord si autorisé) ;
--   * vente des objets gris et des objets marqués camelote (sacs : Alt + clic gauche), par lots,
--     arrêtée si le marchand se ferme ; total compté à la fin du verrou de chaque case ;
--   * sorts remontés de rang sur les barres d'action quand un rang supérieur est appris ;
--   * libération de l'esprit protégée : maintenir ALT pour libérer (instances par défaut) ;
--   * acceptation des invitations venant d'amis, de Battle.net ou de la guilde ;
--   * suppression rapide : le mot de confirmation est pré-rempli ;
--   * butin rapide (Maj pour ramasser à la main) ;
--   * quêtes : acceptation et rendu automatiques (Maj pour suspendre), jamais de choix de
--     récompense à la place du joueur ;
--   * repère sur la récompense au choix la plus chère à la revente (le joueur choisit toujours) ;
--   * cinématiques passées, réinitialisation d'instance annoncée au groupe.
-- Aucune action protégée, sauf la pose d'un sort sur une barre : différée hors combat. Les hooks posés
-- sur Blizzard ne se retirent pas, d'où le test `active` au début de chacun.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local SELL_BATCH = 10
local SELL_INTERVAL = 0.2
local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

local Automation = NS.Modules:Register("automation", {
    titleKey = "AUTO_TITLE",
    descKey = "AUTO_DESC",
    defaults = {
        enabled = true,
        repair = true,
        repairGuild = true,
        sellJunk = true,
        releaseGuard = true,
        releaseInstanceOnly = true,
        releaseHold = 1.0,
        acceptInvites = false,
        fastDelete = true,
        quickLoot = true,
        autoQuests = false,
        questRewardMark = true,
        skipCinematics = false,
        announceReset = false,
        uprank = true,
    },
})

local active = false
local events = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- Réparation
--------------------------------------------------------------------------------

local function RepairSelf(cost)
    if GetMoney() >= cost then
        RepairAllItems()
        NS.Print(string.format(L.AUTO_REPAIRED, NS.FormatMoney(cost)))
        return "self"
    end
    NS.Print(string.format(L.AUTO_REPAIR_NO_MONEY, NS.FormatMoney(cost)))
    return "poor"
end

function Automation:Repair()
    if not (_G.CanMerchantRepair and CanMerchantRepair()) then return nil end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return nil end

    if self.db.repairGuild and _G.CanGuildBankRepair and CanGuildBankRepair() then
        local allowance = _G.GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
        -- -1 = retraits illimités (maître de guilde).
        if allowance == -1 or allowance >= cost then
            RepairAllItems(true)
            -- La réparation passe par le serveur : GetRepairAllCost ne baisse qu'après son retour.
            -- Relu trop tôt, il annonçait l'or perso alors que la guilde avait payé.
            C_Timer.After(0.5, function()
                -- Marchand fermé entre-temps : le coût lu ne voudrait plus rien dire.
                if not CanMerchantRepair() then return end
                local remaining = GetRepairAllCost()
                if not remaining or remaining <= 0 then
                    NS.Print(string.format(L.AUTO_REPAIRED_GUILD, NS.FormatMoney(cost)))
                elseif CanMerchantRepair() then
                    -- Banque vide ou partielle : l'or perso ne couvre que le reste.
                    RepairSelf(remaining)
                end
            end)
            return "guild"
        end
    end
    return RepairSelf(cost)
end

--------------------------------------------------------------------------------
-- Vente des gris
--------------------------------------------------------------------------------

local sellQueue, sellTimer, sellTotal = {}, nil, 0
local sellPending = {}   -- [bag * 1000 + slot] = { bag, slot, itemID, value } : vente envoyée, verrou en cours

local function BagsList(key)
    local bags = NS.db and NS.db.modules and NS.db.modules.bags
    return NS.ParseSpellList(bags and bags[key] or "")
end

--- Objets à vendre : gris et marqués camelote (`junkMarked` des sacs), { bag, slot, itemID, value },
-- puis le nombre d'objets gardés (sans prix, ensemble d'équipement, épinglés, remboursables).
function Automation:FindJunk()
    local junk, kept = {}, 0
    local marked, pinned = BagsList("junkMarked"), BagsList("pinned")
    for bag = 0, NS.NUM_BAGS do
        for slot = 1, NS.GetBagSlots(bag) do
            local item = NS.GetBagItem(bag, slot)
            local isMarked = item and marked[item.itemID]
            if item and not item.isLocked and (isMarked or (item.quality == POOR and not item.hasNoValue)) then
                local price = NS.GetItemSellPrice(item.link or item.itemID)
                if price <= 0 or pinned[item.itemID] or NS.IsBagItemInEquipmentSet(bag, slot)
                        or NS.IsBagItemRefundable(bag, slot) then
                    if isMarked or price > 0 then kept = kept + 1 end
                else
                    junk[#junk + 1] = { bag = bag, slot = slot, itemID = item.itemID,
                                        value = price * (item.stackCount or 1) }
                end
            end
        end
    end
    return junk, kept
end

local function StopSelling(announce)
    if sellTimer then sellTimer:Cancel() sellTimer = nil end
    if announce and sellTotal > 0 then
        NS.Print(string.format(L.AUTO_SOLD, NS.FormatMoney(sellTotal)))
    end
    sellQueue, sellTotal, sellPending = {}, 0, {}
end

--- Fin de verrou : case vidée ou changée = vendue ; même objet déverrouillé = refusé.
local function SettleSales()
    for key, entry in pairs(sellPending) do
        local item = NS.GetBagItem(entry.bag, entry.slot)
        if not item or item.itemID ~= entry.itemID then
            sellTotal = sellTotal + entry.value
            sellPending[key] = nil
        elseif not item.isLocked then
            sellPending[key] = nil
        end
    end
    if not sellTimer and #sellQueue == 0 and not next(sellPending) then StopSelling(true) end
end

local function SellBatch()
    for _ = 1, SELL_BATCH do
        local entry = table.remove(sellQueue, 1)
        if not entry then break end
        -- La case a pu changer depuis l'inventaire (objet déplacé, déjà vendu).
        local item = NS.GetBagItem(entry.bag, entry.slot)
        if item and item.itemID == entry.itemID and not item.isLocked then
            NS.UseBagItem(entry.bag, entry.slot)
            sellPending[entry.bag * 1000 + entry.slot] = entry
        end
    end
    if #sellQueue == 0 and sellTimer then sellTimer:Cancel() sellTimer = nil end
end

function Automation:SellJunk()
    StopSelling(false)
    local kept
    sellQueue, kept = self:FindJunk()
    if kept > 0 then NS.Print(string.format(L.AUTO_JUNK_KEPT, kept)) end
    if #sellQueue == 0 then return 0 end
    local count = #sellQueue
    SellBatch()
    if #sellQueue > 0 then
        sellTimer = C_Timer.NewTicker(SELL_INTERVAL, SellBatch)
    end
    return count
end

--------------------------------------------------------------------------------
-- Rangs supérieurs sur les barres d'action
--------------------------------------------------------------------------------
-- Sort appris (LEARNED_SPELL_IN_SKILL_LINE) : traité dès que le grimoire le connaît (tout de suite
-- ou au SPELLS_CHANGED suivant), hors combat et curseur vide. Chaque emplacement qui porte un rang
-- inférieur du même sort (même nom) reçoit le nouveau rang. Macros non touchées.

local uprankPending, uprankWaiting = {}, false
local uprankReplaced, uprankToken = {}, 0   -- sorts remplacés, annoncés ensemble après UPRANK_REPORT_DELAY
local UPRANK_REPORT_DELAY = 2

-- Un seul message par session d'apprentissage : chaque remplacement relance le délai.
local function ReportUpranks()
    uprankToken = uprankToken + 1
    local token = uprankToken
    C_Timer.After(UPRANK_REPORT_DELAY, function()
        if token ~= uprankToken or not next(uprankReplaced) then return end
        local list = {}
        for text in pairs(uprankReplaced) do list[#list + 1] = text end
        table.sort(list)
        uprankReplaced = {}
        NS.Print(string.format(L.AUTO_UPRANKED, table.concat(list, ", ")))
    end)
end

local function ReplaceLowerRanks()
    uprankWaiting = false
    if not (active and Automation.db.uprank) then wipe(uprankPending) return end
    if not next(uprankPending) then return end
    if NS.InCombat() then
        uprankWaiting = true
        events:UnregisterEvent("CURSOR_CHANGED")
        NS:RunOutOfCombat(ReplaceLowerRanks)
        return
    end
    if not NS.CursorEmpty() then
        uprankWaiting = true
        NS.RegisterEventSafe(events, "CURSOR_CHANGED")
        return
    end
    events:UnregisterEvent("CURSOR_CHANGED")
    local replaced = false
    for spellID in pairs(uprankPending) do
        local name = NS.GetPlainSpellName(spellID)
        -- Sort pas encore au plus haut rang du grimoire : gardé pour le SPELLS_CHANGED suivant.
        local ready = name and NS.IsTopRankSpellbookSpell(spellID)
        if not name or ready then uprankPending[spellID] = nil end
        if ready then
            local placed = false
            for slot = 1, NS.NUM_ACTION_SLOTS do
                local current = NS.GetActionSpellID(slot)
                if current and current ~= spellID and NS.GetPlainSpellName(current) == name
                        and NS.PlaceSpellInActionSlot(spellID, slot) then
                    placed = true
                end
            end
            if placed then
                local rank = NS.GetSpellRankText(spellID)
                uprankReplaced[rank and string.format("%s (%s)", name, rank) or name] = true
                replaced = true
            end
        end
    end
    if replaced then ReportUpranks() end
end

local function ScheduleUprank()
    if not uprankWaiting and next(uprankPending) then ReplaceLowerRanks() end
end

function Automation:OnSpellLearned(spellID)
    if not self.db.uprank or type(spellID) ~= "number" or NS.IsSecret(spellID) then return end
    uprankPending[spellID] = true
    if NS.IsTopRankSpellbookSpell(spellID) then ScheduleUprank() end
end

--------------------------------------------------------------------------------
-- Libération de l'esprit protégée
--------------------------------------------------------------------------------
-- Un bouton transparent couvre « Libérer l'esprit » et avale les clics. Maintenir ALT
-- pendant `releaseHold` secondes le retire. Relâcher ALT recommence le décompte.

local blocker, pressStart, armedHold

local function HoldLabel(seconds)
    return string.format(L.AUTO_HOLD_ALT, seconds)
end

local releaseCleared = false   -- ALT maintenu jusqu'au bout : ne pas réarmer sur cette mort

local function Disarm()
    pressStart = nil
    if blocker then
        blocker:SetScript("OnUpdate", nil)
        blocker:Hide()
    end
end

local function OnHoldUpdate()
    if not IsAltKeyDown() then
        -- Alt-tab : aucune touche relâchée n'arrive, le décompte doit repartir de zéro.
        pressStart = nil
        blocker.label:SetText(HoldLabel(armedHold))
        return
    end
    pressStart = pressStart or GetTime()
    local left = armedHold - (GetTime() - pressStart)
    if left <= 0 then
        releaseCleared = true
        Disarm()
        return
    end
    blocker.label:SetText(HoldLabel(math.ceil(left * 10) / 10))
end

local function BuildBlocker(button)
    if not blocker then
        blocker = CreateFrame("Button", nil, button)
        blocker:SetFrameStrata("DIALOG")
        blocker:RegisterForClicks("AnyUp", "AnyDown")
        blocker:SetScript("OnClick", function() end)   -- avale le clic
        blocker.bg = blocker:CreateTexture(nil, "BACKGROUND")
        blocker.bg:SetAllPoints()
        NS.SetSolidColor(blocker.bg, 0.08, 0.08, 0.1, 0.92)
        blocker.label = Media:CreateText(blocker, "OVERLAY", 0, "OUTLINE")
        blocker.label:SetPoint("CENTER")
    end
    -- Blizzard recycle les popups : le bouton peut changer d'une mort à l'autre.
    blocker:SetParent(button)
    blocker:ClearAllPoints()
    blocker:SetAllPoints(button)
    return blocker
end

function Automation:ArmReleaseGuard()
    if not active or not self.db.releaseGuard or releaseCleared then return false end
    if self.db.releaseInstanceOnly then
        local _, instanceType = IsInInstance()
        if instanceType ~= "party" and instanceType ~= "raid" then return false end
    end
    local popup = NS.GetVisiblePopup("DEATH")
    local button = popup and NS.GetPopupButton(popup, 1)
    if not button then
        Disarm()   -- le popup a bougé ou disparu : ne pas laisser le voile sur un autre bouton
        return false
    end
    BuildBlocker(button)
    armedHold = self.db.releaseHold
    pressStart = nil
    blocker.label:SetText(HoldLabel(armedHold))
    blocker:Show()
    blocker:SetScript("OnUpdate", OnHoldUpdate)
    return true
end

function Automation:IsReleaseBlocked()
    return blocker ~= nil and blocker:IsShown()
end

--------------------------------------------------------------------------------
-- Invitations
--------------------------------------------------------------------------------

function Automation:OnInvite(name, guid)
    if not self.db.acceptInvites then return false end
    if _G.IsInGroup and IsInGroup() then return false end
    if not NS.IsTrustedPlayer(guid, name) then return false end
    AcceptGroup()
    -- Sans ce drapeau, l'OnHide du popup Blizzard appelle DeclineGroup juste après.
    local popup = NS.GetVisiblePopup("PARTY_INVITE")
    if popup then popup.inviteAccepted = 1 end
    if _G.StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
    NS.Print(string.format(L.AUTO_INVITE_ACCEPTED, tostring(name)))
    return true
end

--------------------------------------------------------------------------------
-- Suppression rapide
--------------------------------------------------------------------------------

local DELETE_POPUPS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
local deleteHooked = false

local function FillDeleteConfirmation(which)
    if not active or not Automation.db.fastDelete or not DELETE_POPUPS[which] then return end
    local popup = NS.GetVisiblePopup(which)
    local box = popup and NS.GetPopupEditBox(popup)
    if box and _G.DELETE_ITEM_CONFIRM_STRING then
        box:SetText(DELETE_ITEM_CONFIRM_STRING)
    end
end

--------------------------------------------------------------------------------
-- Butin rapide
--------------------------------------------------------------------------------

--- Ramasse tout, du dernier emplacement au premier (les indices se décalent sinon).
function Automation:QuickLoot()
    if not self.db.quickLoot or IsShiftKeyDown() then return 0 end
    local count = GetNumLootItems and GetNumLootItems() or 0
    for slot = count, 1, -1 do LootSlot(slot) end
    return count
end

--------------------------------------------------------------------------------
-- Quêtes
--------------------------------------------------------------------------------
-- Une action par event : le client renvoie l'event suivant (QUEST_DETAIL, QUEST_COMPLETE…)
-- une fois l'action faite. Maj maintenue = le joueur reprend la main.

local function QuestsPaused()
    return not Automation.db.autoQuests or IsShiftKeyDown()
end

-- Anti double : une quête déjà choisie il y a moins de 30 s est laissée au joueur (journal
-- plein, récompense à choisir) ; sans ça le PNJ la reproposerait en boucle. clé nil : pas de garde.
local QUEST_RETRY_DELAY = 30
local questTried = {}
local function FirstTry(key)
    if key == nil then return true end
    local now = GetTime()
    if questTried[key] and now - questTried[key] < QUEST_RETRY_DELAY then return false end
    questTried[key] = now
    return true
end

local function CurrentQuestKey(prefix)
    local questID = _G.GetQuestID and GetQuestID()
    return questID and questID ~= 0 and (prefix .. questID) or nil
end

-- Quête répétable (remise d'étoffes, réputation) : elle consommerait objets ou or à chaque
-- passage, le joueur la fait à la main. frequency : 0 = normale, sinon journalière/hebdo.
local function Repeatable(repeatable, frequency)
    return repeatable == true or (type(frequency) == "number" and frequency ~= 0)
end

function Automation:OnGossip()
    if QuestsPaused() or not C_GossipInfo then return nil end
    for _, quest in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
        if quest.isComplete and not Repeatable(quest.repeatable, quest.frequency)
            and FirstTry("turnin:" .. quest.questID) then
            C_GossipInfo.SelectActiveQuest(quest.questID)
            return "turnin"
        end
    end
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}) do
        if not Repeatable(quest.repeatable, quest.frequency) and FirstTry("accept:" .. quest.questID) then
            C_GossipInfo.SelectAvailableQuest(quest.questID)
            return "accept"
        end
    end
    return nil
end

--- PNJ « à l'ancienne » (QuestFrame avec liste) : même logique, par index.
function Automation:OnQuestGreeting()
    if QuestsPaused() then return nil end
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
        local title, isComplete = GetActiveTitle(i)
        if isComplete and not NS.IsActiveQuestRepeatable(i) and FirstTry("turnin:" .. tostring(title)) then
            SelectActiveQuest(i)
            return "turnin"
        end
    end
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
        local frequency, isRepeatable
        if _G.GetAvailableQuestInfo then _, frequency, isRepeatable = GetAvailableQuestInfo(i) end
        local title = _G.GetAvailableTitle and GetAvailableTitle(i)
        if not Repeatable(isRepeatable, frequency) and FirstTry("accept:" .. tostring(title)) then
            SelectAvailableQuest(i)
            return "accept"
        end
    end
    return nil
end

local QUEST_HANDLERS = {
    QUEST_DETAIL = function() if FirstTry(CurrentQuestKey("detail:")) then AcceptQuest() end end,
    QUEST_ACCEPT_CONFIRM = function() ConfirmAcceptQuest() end,
    QUEST_PROGRESS = function()
        -- Quête qui demande de l'or : c'est au joueur de payer.
        if _G.GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then return end
        if NS.IsCurrentQuestRepeatable() then return end
        if IsQuestCompletable() then CompleteQuest() end
    end,
    -- Plusieurs récompenses au choix : c'est au joueur de trancher.
    QUEST_COMPLETE = function()
        local choices = GetNumQuestChoices()
        if choices <= 1 and FirstTry(CurrentQuestKey("reward:")) then GetQuestReward(choices) end
    end,
    GOSSIP_SHOW = function() Automation:OnGossip() end,
    QUEST_GREETING = function() Automation:OnQuestGreeting() end,
}

--------------------------------------------------------------------------------
-- Récompense la plus chère
--------------------------------------------------------------------------------
-- Indépendant de autoQuests et de Maj : c'est un repère, jamais un choix. Accroché à
-- l'affichage du panneau de récompense (les boutons y sont remplis), relu quand le client
-- reçoit un objet encore inconnu.

local rewardMark, rewardPending
local rewardHooked = false

--- Choix au prix de revente le plus haut parmi `count` ; nil si aucun ne vaut rien.
-- Second retour vrai : un prix encore inconnu, à relire.
function Automation.BestReward(count, price)
    local best, bestPrice
    for i = 1, count do
        local value = price(i)
        if value == nil then return nil, true end
        if value > 0 and (not bestPrice or value > bestPrice) then best, bestPrice = i, value end
    end
    return best, false
end

local function RewardPrice(index)
    local link = _G.GetQuestItemLink and GetQuestItemLink("choice", index)
    if not link or not (C_Item and C_Item.GetItemInfo) then return nil end
    return (select(11, C_Item.GetItemInfo(link)))
end

local function MarkBestReward()
    rewardPending = false
    if rewardMark then rewardMark:Hide() end
    if not (active and Automation.db.questRewardMark) then return end
    local count = _G.GetNumQuestChoices and GetNumQuestChoices() or 0
    if count <= 1 then return end
    local best
    best, rewardPending = Automation.BestReward(count, RewardPrice)
    local rewards = _G.QuestInfoRewardsFrame
    -- Bouton du choix : type "choice" et GetID() = indice (RewardButtons[i] n'est pas toujours le choix i).
    for _, rewardButton in ipairs(best and rewards and rewards.RewardButtons or {}) do
        if rewardButton:IsShown() and rewardButton.type == "choice" and rewardButton:GetID() == best then
            if not rewardMark then
                rewardMark = CreateFrame("Frame")
                rewardMark:SetSize(16, 16)
                rewardMark.texture = rewardMark:CreateTexture(nil, "OVERLAY")
                rewardMark.texture:SetAllPoints()
                rewardMark.texture:SetAtlas("coin-gold")
            end
            rewardMark:SetParent(rewardButton)
            rewardMark:SetFrameLevel(rewardButton:GetFrameLevel() + 5)
            rewardMark:ClearAllPoints()
            rewardMark:SetPoint("TOPLEFT", rewardButton, "TOPLEFT", -2, 2)
            rewardMark:Show()
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Cinématiques et réinitialisation d'instance
--------------------------------------------------------------------------------

local function SkipCinematic()
    if not Automation.db.skipCinematics then return end
    C_Timer.After(0, function()
        if _G.CinematicFrame_CancelCinematic then CinematicFrame_CancelCinematic()
        elseif _G.StopCinematic then StopCinematic() end
    end)
end

local function SkipMovie()
    if not Automation.db.skipCinematics then return end
    C_Timer.After(0, function()
        if _G.MovieFrame and MovieFrame.StopMovie then MovieFrame:StopMovie()
        elseif _G.GameMovieFinished then GameMovieFinished() end
    end)
end

-- "%s has been reset." -> motif Lua ancré.
local function GlobalToPattern(text)
    return "^" .. text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
end
Automation.GlobalToPattern = GlobalToPattern

function Automation:OnSystemMessage(message)
    if not self.db.announceReset or not _G.INSTANCE_RESET_SUCCESS then return false end
    if NS.IsSecret(message) or type(message) ~= "string" then return false end   -- chat verrouillé
    if not (IsInGroup and IsInGroup()) then return false end
    if not message:match(GlobalToPattern(INSTANCE_RESET_SUCCESS)) then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    if not send then return false end
    send(message, IsInRaid() and "RAID" or "PARTY")
    return true
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

events:SetScript("OnEvent", function(_, event, ...)
    if event == "MERCHANT_SHOW" then
        if Automation.db.repair then Automation:Repair() end
        if Automation.db.sellJunk then Automation:SellJunk() end
    elseif event == "MERCHANT_CLOSED" then
        SettleSales()
        StopSelling(true)
    elseif event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED" then
        if next(sellPending) then SettleSales() end
    elseif event == "LEARNED_SPELL_IN_SKILL_LINE" then
        Automation:OnSpellLearned((...))
    elseif event == "SPELLS_CHANGED" or event == "CURSOR_CHANGED" then
        if event == "CURSOR_CHANGED" then uprankWaiting = false end
        ScheduleUprank()
    elseif event == "PLAYER_DEAD" then
        releaseCleared = false
        -- Le popup se construit pendant PLAYER_DEAD : son bouton n'existe qu'une frame plus tard.
        C_Timer.After(0.05, function() Automation:ArmReleaseGuard() end)
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        releaseCleared = false
        Disarm()
    elseif event == "PARTY_INVITE_REQUEST" then
        local name, _, _, _, _, _, guid = ...
        Automation:OnInvite(name, guid)
    elseif event == "LOOT_READY" then
        Automation:QuickLoot()
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "QUEST_ITEM_UPDATE" then
        if rewardPending and _G.QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() then MarkBestReward() end
    elseif QUEST_HANDLERS[event] then
        if not QuestsPaused() then QUEST_HANDLERS[event]() end
    elseif event == "CINEMATIC_START" then
        SkipCinematic()
    elseif event == "PLAY_MOVIE" then
        SkipMovie()
    elseif event == "CHAT_MSG_SYSTEM" then
        Automation:OnSystemMessage((...))
    end
end)

function Automation:OnEnable()
    active = true
    for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_DEAD", "PLAYER_ALIVE",
                             "PLAYER_UNGHOST", "PARTY_INVITE_REQUEST", "LOOT_READY", "CINEMATIC_START",
                             "PLAY_MOVIE", "CHAT_MSG_SYSTEM", "GET_ITEM_INFO_RECEIVED", "QUEST_ITEM_UPDATE",
                             "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
                             "SPELLS_CHANGED" }) do
        NS.RegisterEventSafe(events, event)
    end
    for event in pairs(QUEST_HANDLERS) do
        NS.RegisterEventSafe(events, event)
    end
    if not deleteHooked and _G.StaticPopup_Show then
        hooksecurefunc("StaticPopup_Show", FillDeleteConfirmation)
        -- La pile de popups se recompacte : tant que le joueur est mort, réarmer sur le bon bouton
        -- (couvre aussi un popup DEATH absent 0,05 s après PLAYER_DEAD).
        local function RearmIfDead()
            if active and _G.UnitIsDead and UnitIsDead("player") then
                C_Timer.After(0, function() Automation:ArmReleaseGuard() end)
            end
        end
        hooksecurefunc("StaticPopup_Show", RearmIfDead)
        if _G.StaticPopup_Hide then hooksecurefunc("StaticPopup_Hide", RearmIfDead) end
        deleteHooked = true
    end
    if not rewardHooked and _G.QuestFrameRewardPanel then
        QuestFrameRewardPanel:HookScript("OnShow", MarkBestReward)
        rewardHooked = true
    end
    -- Activé alors que le joueur est déjà mort : armer tout de suite.
    if _G.UnitIsDead and UnitIsDead("player") then self:ArmReleaseGuard() end
end

function Automation:OnDisable()
    active = false
    events:UnregisterAllEvents()
    StopSelling(false)
    wipe(uprankPending)
    uprankWaiting = false
    Disarm()
end

function Automation:OnRefresh()
    if not self.db.releaseGuard then Disarm() end
end

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function Automation:BuildOptions(o)
    o:Title(L.OPT_AUTO_MERCHANT)
    o:Check("repair", L.OPT_AUTO_REPAIR)
    o:Check("repairGuild", L.OPT_AUTO_REPAIR_GUILD, 36)
    o:Check("sellJunk", L.OPT_AUTO_SELL)
    o:Title(L.OPT_AUTO_LOOT_QUESTS)
    o:Check("quickLoot", L.OPT_AUTO_QUICK_LOOT)
    o:Check("autoQuests", L.OPT_AUTO_QUESTS)
    o:Check("questRewardMark", L.OPT_AUTO_QUEST_REWARD_MARK)
    o:Title(L.OPT_AUTO_DEATH)
    o:Check("releaseGuard", L.OPT_AUTO_RELEASE)
    o:Check("releaseInstanceOnly", L.OPT_AUTO_RELEASE_INSTANCE, 36)
    o:Advanced()
    o:Slider("releaseHold", L.OPT_AUTO_RELEASE_HOLD, 0.5, 3, 0.5, 36, "%.1f s")
    o:EndAdvanced()
    o:Title(L.OPT_AUTO_MISC)
    o:Check("acceptInvites", L.OPT_AUTO_INVITES)
    o:Check("fastDelete", L.OPT_AUTO_DELETE)
    o:Check("skipCinematics", L.OPT_AUTO_CINEMATICS)
    o:Check("announceReset", L.OPT_AUTO_RESET)
    o:Check("uprank", L.OPT_AUTO_UPRANK)
    o:Hint(L.OPT_AUTO_UPRANK_HINT)
end
