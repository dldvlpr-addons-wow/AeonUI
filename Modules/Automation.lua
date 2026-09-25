-- Modules/Automation.lua
-- Petits automatismes, chacun avec son interrupteur :
--   * réparation chez le marchand (banque de guilde d'abord si autorisé) ;
--   * vente des objets gris, par lots, arrêtée si le marchand se ferme ;
--   * libération de l'esprit protégée : maintenir ALT pour libérer (instances par défaut) ;
--   * acceptation des invitations venant d'amis, de Battle.net ou de la guilde ;
--   * suppression rapide : le mot de confirmation est pré-rempli ;
--   * butin rapide (Maj pour ramasser à la main) ;
--   * quêtes : acceptation et rendu automatiques (Maj pour suspendre), jamais de choix de
--     récompense à la place du joueur ;
--   * cinématiques passées, réinitialisation d'instance annoncée au groupe.
-- Aucune action protégée : tout est autorisé hors et en combat, mais les hooks posés
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
        skipCinematics = false,
        announceReset = false,
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

--- Liste les objets gris vendables : { bag, slot, itemID, value }.
function Automation:FindJunk()
    local junk = {}
    for bag = 0, NS.NUM_BAGS do
        for slot = 1, NS.GetBagSlots(bag) do
            local item = NS.GetBagItem(bag, slot)
            if item and item.quality == POOR and not item.hasNoValue and not item.isLocked then
                local price = NS.GetItemSellPrice(item.link or item.itemID)
                if price > 0 then
                    junk[#junk + 1] = { bag = bag, slot = slot, itemID = item.itemID,
                                        value = price * (item.stackCount or 1) }
                end
            end
        end
    end
    return junk
end

local function StopSelling(announce)
    if sellTimer then sellTimer:Cancel() sellTimer = nil end
    if announce and sellTotal > 0 then
        NS.Print(string.format(L.AUTO_SOLD, NS.FormatMoney(sellTotal)))
    end
    sellQueue, sellTotal = {}, 0
end

local function SellBatch()
    for _ = 1, SELL_BATCH do
        local entry = table.remove(sellQueue, 1)
        if not entry then break end
        -- La case a pu changer depuis l'inventaire (objet déplacé, déjà vendu).
        local item = NS.GetBagItem(entry.bag, entry.slot)
        if item and item.itemID == entry.itemID and not item.isLocked then
            NS.UseBagItem(entry.bag, entry.slot)
            sellTotal = sellTotal + entry.value
        end
    end
    if #sellQueue == 0 then StopSelling(true) end
end

function Automation:SellJunk()
    StopSelling(false)
    sellQueue = self:FindJunk()
    if #sellQueue == 0 then return 0 end
    local count = #sellQueue
    SellBatch()
    if #sellQueue > 0 then
        sellTimer = C_Timer.NewTicker(SELL_INTERVAL, SellBatch)
    end
    return count
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

-- Quête répétable (remise d'étoffes, réputation) : elle consommerait objets ou or à chaque
-- passage, le joueur la fait à la main. frequency : 0 = normale, sinon journalière/hebdo.
local function Repeatable(repeatable, frequency)
    return repeatable == true or (type(frequency) == "number" and frequency ~= 0)
end

function Automation:OnGossip()
    if QuestsPaused() or not C_GossipInfo then return nil end
    for _, quest in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
        if quest.isComplete and not Repeatable(quest.repeatable, quest.frequency) then
            C_GossipInfo.SelectActiveQuest(quest.questID)
            return "turnin"
        end
    end
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}) do
        if not Repeatable(quest.repeatable, quest.frequency) then
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
        local _, isComplete = GetActiveTitle(i)
        if isComplete then
            SelectActiveQuest(i)
            return "turnin"
        end
    end
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
        local frequency, isRepeatable
        if _G.GetAvailableQuestInfo then _, frequency, isRepeatable = GetAvailableQuestInfo(i) end
        if not Repeatable(isRepeatable, frequency) then
            SelectAvailableQuest(i)
            return "accept"
        end
    end
    return nil
end

local QUEST_HANDLERS = {
    QUEST_DETAIL = function() AcceptQuest() end,
    QUEST_ACCEPT_CONFIRM = function() ConfirmAcceptQuest() end,
    QUEST_PROGRESS = function()
        -- Quête qui demande de l'or : c'est au joueur de payer.
        if _G.GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then return end
        if IsQuestCompletable() then CompleteQuest() end
    end,
    -- Plusieurs récompenses au choix : c'est au joueur de trancher.
    QUEST_COMPLETE = function()
        local choices = GetNumQuestChoices()
        if choices <= 1 then GetQuestReward(choices) end
    end,
    GOSSIP_SHOW = function() Automation:OnGossip() end,
    QUEST_GREETING = function() Automation:OnQuestGreeting() end,
}

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
        StopSelling(true)
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
                             "PLAY_MOVIE", "CHAT_MSG_SYSTEM" }) do
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
    -- Activé alors que le joueur est déjà mort : armer tout de suite.
    if _G.UnitIsDead and UnitIsDead("player") then self:ArmReleaseGuard() end
end

function Automation:OnDisable()
    active = false
    events:UnregisterAllEvents()
    StopSelling(false)
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
    o:Title(L.OPT_AUTO_DEATH)
    o:Check("releaseGuard", L.OPT_AUTO_RELEASE)
    o:Check("releaseInstanceOnly", L.OPT_AUTO_RELEASE_INSTANCE, 36)
    o:Slider("releaseHold", L.OPT_AUTO_RELEASE_HOLD, 0.5, 3, 0.5, 36, "%.1f s")
    o:Title(L.OPT_AUTO_MISC)
    o:Check("acceptInvites", L.OPT_AUTO_INVITES)
    o:Check("fastDelete", L.OPT_AUTO_DELETE)
    o:Check("skipCinematics", L.OPT_AUTO_CINEMATICS)
    o:Check("announceReset", L.OPT_AUTO_RESET)
end
