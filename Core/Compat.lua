-- Core/Compat.lua
-- Seul fichier qui appelle une API susceptible de manquer ou de rendre une « valeur secrète ».
-- Les modules passent par NS.* et ne testent jamais eux-mêmes l'existence d'une fonction.
--
-- Moteur 12.x (WoW Forever 1.60) :
--   * COMBAT_LOG_EVENT_UNFILTERED est interdit aux addons : on ne l'enregistre jamais ;
--   * en combat, auras et incantations peuvent être secrètes (affichables, pas comparables) :
--     toute valeur lue ici qui pourrait l'être passe par NS.IsSecret avant d'être testée.
local ADDON_NAME, NS = ...
_G.AeonUI = NS
NS.addonName = ADDON_NAME

local isSecret = _G.issecretvalue or function() return false end
NS.IsSecret = isSecret

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
-- RegisterEvent lève une erreur sur un event inconnu : c'est le seul test fiable.

local probe = CreateFrame("Frame")
local eventExists = {}

function NS.EventExists(event)
    local cached = eventExists[event]
    if cached ~= nil then return cached end
    local ok = pcall(probe.RegisterEvent, probe, event)
    if ok then pcall(probe.UnregisterEvent, probe, event) end
    eventExists[event] = ok
    return ok
end

--- Enregistre un event s'il existe sur ce client. Retourne true si enregistré.
function NS.RegisterEventSafe(frame, event, ...)
    if not NS.EventExists(event) then return false end
    if frame.RegisterUnitEvent and select("#", ...) > 0 then
        if pcall(frame.RegisterUnitEvent, frame, event, ...) then return true end
    end
    frame:RegisterEvent(event)
    return true
end

--------------------------------------------------------------------------------
-- Sorts
--------------------------------------------------------------------------------

function NS.GetSpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name
    end
    if _G.GetSpellInfo then return (GetSpellInfo(id)) end
    return nil
end

function NS.GetSpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.iconID
    end
    return _G.GetSpellTexture and GetSpellTexture(id) or nil
end

--- Le joueur connaît-il ce sort ? En Classic, un sort a un id par rang : l'id du rang 1
-- ne dit rien du rang 6 appris. Le repli par nom couvre tous les rangs, le grimoire
-- étant indexé par nom (GetSpellInfo(nom) ne répond que pour un sort du grimoire).
function NS.KnowsSpell(id)
    if _G.IsPlayerSpell and IsPlayerSpell(id) then return true end
    if _G.IsSpellKnown and IsSpellKnown(id) then return true end
    local name = NS.GetSpellName(id)
    if not name then return false end
    if C_Spell and C_Spell.GetSpellInfo then
        return C_Spell.GetSpellInfo(name) ~= nil
    end
    return _G.GetSpellInfo ~= nil and GetSpellInfo(name) ~= nil
end

--------------------------------------------------------------------------------
-- Auras du joueur
--------------------------------------------------------------------------------

local function AuraName(index)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if not aura then return nil end
        return aura.name
    end
    if _G.UnitBuff then return (UnitBuff("player", index)) end
    if _G.UnitAura then return (UnitAura("player", index, "HELPFUL")) end
    return nil
end

--- Le joueur porte-t-il un buff dont le nom est dans `names` (table [nom] = true) ?
-- Retourne nil quand le client refuse de répondre (nom secret) : l'appelant s'abstient.
function NS.PlayerHasBuff(names)
    for index = 1, 40 do
        local name = AuraName(index)
        if isSecret(name) then return nil end
        if name == nil then return false end
        if names[name] then return true end
    end
    return false
end

--- Débuff n° `index` de `unit` : icône, durée, fin, stacks, type de dissipation, débuff de
-- boss, identifiant du sort, posé par le joueur (ou son familier). Tout peut être SECRET sur le moteur 12.x : l'appelant vérifie NS.IsSecret avant de
-- comparer, et passe le reste aux widgets tel quel.
-- nil quand il n'y en a plus, ou quand le client refuse de répondre.
function NS.GetDebuff(unit, index) return NS.GetAura(unit, index, "HARMFUL") end

--- Comme NS.GetDebuff, pour le filtre `filter` ("HARMFUL" ou "HELPFUL").
function NS.GetAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        if not ok or isSecret(aura) or aura == nil then return nil end
        return aura.icon, aura.duration, aura.expirationTime, aura.applications, aura.dispelName, aura.isBossAura,
            aura.spellId, aura.isFromPlayerOrPlayerPet
    end
    local legacy = filter == "HELPFUL" and _G.UnitBuff or _G.UnitDebuff
    if legacy then
        local _, icon, count, dispelType, duration, expirationTime, source, _, _, spellId, _, isBossDebuff = legacy(unit, index)
        local isMine
        if isSecret(source) then isMine = source
        else isMine = source == "player" or source == "pet" end
        return icon, duration, expirationTime, count, dispelType, isBossDebuff, spellId, isMine
    end
    return nil
end

--- Aura `spellID` sur `unit` (filtre "HELPFUL", "HARMFUL|PLAYER"…) : icône, durée, fin, stacks.
-- nil si absente, ou illisible (identifiant secret : le moteur le cache souvent en combat).
function NS.FindAuraBySpellID(unit, spellID, filter)
    for index = 1, 40 do
        local icon, duration, expiration, count, _, _, id = NS.GetAura(unit, index, filter)
        if not isSecret(icon) and icon == nil then return nil end
        if not isSecret(id) and id == spellID then return icon, duration, expiration, count end
    end
    return nil
end

--- Totem de l'emplacement `slot` (1 à 4) : présent, icône, début, durée. Valeurs brutes, peut-être
-- secrètes : l'appelant teste NS.IsSecret. nil si le client n'a pas l'API.
function NS.GetTotem(slot)
    if not _G.GetTotemInfo then return nil end
    local have, _, start, duration, icon = GetTotemInfo(slot)
    return have, icon, start, duration
end

--- Pose la recharge du sort `spellID` sur `cooldown`. Objet durée d'abord (le moteur l'affiche
-- même secret, en combat), sinon valeurs brutes quand elles sont lisibles.
function NS.SetSpellCooldown(cooldown, spellID)
    if C_Spell and C_Spell.GetSpellCooldownDuration and cooldown.SetCooldownFromDurationObject then
        local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if ok and duration then cooldown:SetCooldownFromDurationObject(duration) return end
    end
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then start, duration = info.startTime, info.duration end
    elseif _G.GetSpellCooldown then
        start, duration = GetSpellCooldown(spellID)
    end
    if isSecret(start) or isSecret(duration) then return end
    if start and duration and duration > 0 then cooldown:SetCooldown(start, duration) else cooldown:Clear() end
end

--- Sort hors recharge ? Charges : prêt au maximum de charges. Sinon : pas de vraie recharge
-- (le GCD compte comme prêt). isActive et isOnGCD restent lisibles en combat ; une valeur
-- secrète compte comme « pas prêt ».
function NS.IsSpellReady(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return false end
    local charges = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
    if charges and not isSecret(charges.maxCharges) and (charges.maxCharges or 0) > 1 then
        if isSecret(charges.isActive) then return false end
        return not charges.isActive
    end
    local cd = C_Spell.GetSpellCooldown(spellID)
    if not cd then return true end
    if isSecret(cd.isActive) or isSecret(cd.isOnGCD) then return false end
    return not (cd.isActive and not cd.isOnGCD)
end

--- Charges d'un sort : current, max, début, durée de recharge ; nil si le sort n'a pas de
-- charges ou si une valeur est secrète.
function NS.GetSpellCharges(spellID)
    local info
    if C_Spell and C_Spell.GetSpellCharges then
        info = C_Spell.GetSpellCharges(spellID)
    elseif _G.GetSpellCharges then
        local current, max, start, duration = GetSpellCharges(spellID)
        info = current and { currentCharges = current, maxCharges = max, cooldownStartTime = start, cooldownDuration = duration }
    end
    if type(info) ~= "table" then return nil end
    local current, max = info.currentCharges, info.maxCharges
    local start, duration = info.cooldownStartTime, info.cooldownDuration
    if isSecret(current) or isSecret(max) or isSecret(start) or isSecret(duration) then return nil end
    if type(current) ~= "number" or type(max) ~= "number" then return nil end
    return current, max, start or 0, duration or 0
end

--------------------------------------------------------------------------------
-- Spécialisation (profils par spé)
--------------------------------------------------------------------------------

--- Index de la spécialisation active (1, 2...) ; repli sur le groupe de talents (double spé) ;
-- nil si le client n'en donne pas encore (juste après la connexion).
function NS.GetActiveSpec()
    -- Même source que GetSpecList : spécialisations si le client en liste, sinon groupes de talents.
    local specs = _G.GetNumSpecializations and select(2, pcall(GetNumSpecializations))
    if type(specs) == "number" and not isSecret(specs) and specs > 0 and _G.GetSpecialization then
        local ok, index = pcall(GetSpecialization)
        if ok and type(index) == "number" and not isSecret(index) and index > 0 then return index end
        return nil
    end
    if _G.GetActiveTalentGroup then
        local ok, group = pcall(GetActiveTalentGroup)
        if ok and type(group) == "number" and not isSecret(group) and group > 0 then return group end
    end
    return nil
end

--- Spécialisations du personnage : { { index, name } }, vide si le client n'en expose pas.
function NS.GetSpecList()
    local list = {}
    if _G.GetNumSpecializations and _G.GetSpecializationInfo then
        local ok, count = pcall(GetNumSpecializations)
        for i = 1, (ok and type(count) == "number") and count or 0 do
            local infoOk, _, name = pcall(GetSpecializationInfo, i)
            if infoOk and type(name) == "string" and not isSecret(name) then list[#list + 1] = { index = i, name = name } end
        end
    end
    if #list == 0 and _G.GetNumTalentGroups then
        local ok, count = pcall(GetNumTalentGroups)
        for i = 1, (ok and type(count) == "number") and count or 0 do
            list[#list + 1] = { index = i, name = string.format(NS.L.PROFILE_TALENT_GROUP, i) }
        end
    end
    return list
end

--------------------------------------------------------------------------------
-- Gestionnaire de recharges Blizzard (C_CooldownViewer)
--------------------------------------------------------------------------------

--- Sort d'un cooldownID du gestionnaire : identifiant d'origine et identifiant courant
-- (talent de remplacement). nil si l'API manque ou rend une valeur secrète.
function NS.GetCooldownViewerSpell(cooldownID)
    if isSecret(cooldownID) or not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return nil end
    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
    if not ok or not info or isSecret(info.spellID) or not info.spellID then return nil end
    local live = info.overrideSpellID
    if isSecret(live) or not live or live == 0 then live = info.spellID end
    return info.spellID, live
end

--- Sorts appris de la catégorie `category` (0 essentiel, 1 utilitaire, 2 icônes de buff,
-- 3 barres de buff) : { { spellID, name, icon } } dans l'ordre Blizzard.
function NS.GetCooldownViewerSpells(category)
    local list = {}
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then return list end
    local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, false)
    for _, cooldownID in ipairs(ok and ids or {}) do
        local spellID, live = NS.GetCooldownViewerSpell(cooldownID)
        if spellID then
            list[#list + 1] = { spellID = spellID, name = NS.GetSpellName(live) or NS.GetSpellName(spellID) or tostring(spellID),
                                icon = NS.GetSpellTexture(live) or NS.GetSpellTexture(spellID) }
        end
    end
    return list
end

--------------------------------------------------------------------------------
-- Filtres d'auras partagés (cadres d'unité, plaques, co-tank)
--------------------------------------------------------------------------------

-- Ce que chaque classe dissipe en Classic (le démoniste via son chasseur corrompu).
-- ponytail: pas de vérification du sort de dissipation appris ; à ajouter si un bas niveau se plaint.
NS.DISPEL_BY_CLASS = {
    PRIEST = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    SHAMAN = { Poison = true, Disease = true },
    DRUID = { Curse = true, Poison = true },
    MAGE = { Curse = true },
    WARLOCK = { Magic = true },
}

NS.AURA_FILTERS = { "all", "mine", "important", "dispellable", "boss" }

--- Choix des filtres pour un o:Dropdown.
function NS.AuraFilterChoices()
    local list = {}
    for _, mode in ipairs(NS.AURA_FILTERS) do
        list[#list + 1] = { name = NS.L["AURA_FILTER_" .. mode:upper()], value = mode }
    end
    return list
end

--- Le joueur sait-il dissiper ce type ? nil si la classe ou le type est secret.
function NS.PlayerCanDispel(dispelName)
    if isSecret(dispelName) then return nil end
    if dispelName == nil then return false end
    local _, classFile = UnitClass("player")
    if isSecret(classFile) then return nil end
    local dispels = classFile and NS.DISPEL_BY_CLASS[classFile]
    return dispels and dispels[dispelName] == true or false
end

local spellLists, spellListCount = {}, 0
--- Texte « 1234, 5678 » -> ensemble { [1234] = true }. Mis en cache (saisie : cache vidé à 32).
function NS.ParseSpellList(text)
    text = text or ""
    local set = spellLists[text]
    if set then return set end
    if spellListCount >= 32 then spellLists, spellListCount = {}, 0 end
    set = {}
    for id in text:gmatch("%d+") do set[tonumber(id)] = true end
    spellLists[text], spellListCount = set, spellListCount + 1
    return set
end

--- L'aura passe-t-elle le filtre `mode` ? Listes du profil d'abord (identifiant lisible
-- seulement) : liste blanche = toujours montrée, liste noire = toujours cachée.
-- Un champ secret ne se compare pas : l'aura est gardée.
function NS.AuraPasses(mode, spellId, dispelName, isBoss, isMine)
    local lists = NS.db and NS.db.auraLists
    if lists and not isSecret(spellId) and spellId ~= nil then
        if NS.ParseSpellList(lists.whitelist)[spellId] then return true end
        if NS.ParseSpellList(lists.blacklist)[spellId] then return false end
    end
    if mode == nil or mode == "all" then return true end
    if mode == "mine" then
        if isSecret(isMine) then return true end
        return isMine == true
    end
    if mode == "boss" then return isSecret(isBoss) or isBoss == true end
    local dispellable = NS.PlayerCanDispel(dispelName)
    if dispellable == nil then return true end
    if mode == "dispellable" then return dispellable end
    return isSecret(isBoss) or isBoss == true or dispellable   -- "important"
end

--- Arme principale enchantée (poison, arme de chaman…). nil si le client ne sait pas répondre.
function NS.HasMainHandEnchant()
    if not _G.GetWeaponEnchantInfo then return nil end
    local has = GetWeaponEnchantInfo()
    if isSecret(has) then return nil end
    return has and true or false
end

--------------------------------------------------------------------------------
-- Sacs
--------------------------------------------------------------------------------

local Container = _G.C_Container or {}
NS.NUM_BAGS = _G.NUM_BAG_SLOTS or 4

function NS.GetBagSlots(bag)
    local fn = Container.GetContainerNumSlots or _G.GetContainerNumSlots
    return fn and fn(bag) or 0
end

function NS.GetBagFreeSlots(bag)
    local fn = Container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots
    if not fn then return 0 end
    return (fn(bag)) or 0
end

--- { itemID, quality, stackCount, hasNoValue, isLocked, link, icon } ou nil pour une case vide.
function NS.GetBagItem(bag, slot)
    if Container.GetContainerItemInfo then
        local info = Container.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        return {
            itemID = info.itemID, quality = info.quality, stackCount = info.stackCount or 1,
            hasNoValue = info.hasNoValue, isLocked = info.isLocked, link = info.hyperlink,
            icon = info.iconFileID,
        }
    end
    if _G.GetContainerItemInfo then
        local icon, count, locked, quality, _, _, link, _, noValue, itemID = GetContainerItemInfo(bag, slot)
        if not itemID then return nil end
        return { itemID = itemID, quality = quality, stackCount = count or 1,
                 hasNoValue = noValue, isLocked = locked, link = link, icon = icon }
    end
    return nil
end

function NS.UseBagItem(bag, slot)
    local fn = Container.UseContainerItem or _G.UseContainerItem
    if fn then fn(bag, slot) end
end

--- Prix de vente unitaire en cuivre (0 si inconnu ou pas encore en cache).
function NS.GetItemSellPrice(item)
    local fn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if not fn then return 0 end
    local price = select(11, fn(item))
    return tonumber(price) or 0
end

function NS.GetItemCount(itemID)
    local fn = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    return fn and (fn(itemID) or 0) or 0
end

--- Temps de recharge restant d'un objet en secondes (0 = prêt).
function NS.GetItemCooldownRemaining(itemID)
    local fn = Container.GetItemCooldown or (C_Item and C_Item.GetItemCooldown) or _G.GetItemCooldown
    if not fn then return 0 end
    local start, duration = fn(itemID)
    if isSecret(start) or isSecret(duration) then return 0 end
    if not start or start == 0 or not duration or duration == 0 then return 0 end
    local remaining = start + duration - GetTime()
    return remaining > 0 and remaining or 0
end

--------------------------------------------------------------------------------
-- Équipement
--------------------------------------------------------------------------------

--- Durabilité de la pièce la plus abîmée, en pourcentage (nil si rien d'usable n'est porté).
function NS.GetLowestDurability()
    if not _G.GetInventoryItemDurability then return nil end
    local lowest
    for slot = 1, 18 do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            local pct = current / maximum * 100
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    return lowest
end

--- Lien et qualité de la pièce portée à l'emplacement `slotName` ("Head", "Chest"…).
function NS.GetEquipped(slotName)
    if not (_G.GetInventorySlotInfo and _G.GetInventoryItemLink) then return nil end
    local slotID = GetInventorySlotInfo(slotName .. "Slot")
    if not slotID then return nil end
    local link = GetInventoryItemLink("player", slotID)
    if not link then return nil end
    return link, _G.GetInventoryItemQuality and GetInventoryItemQuality("player", slotID) or nil
end

function NS.GetItemLevel(link)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local level = C_Item.GetDetailedItemLevelInfo(link)
        if level then return level end
    end
    if _G.GetDetailedItemLevelInfo then
        local level = GetDetailedItemLevelInfo(link)
        if level then return level end
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    return getInfo and select(4, getInfo(link)) or nil
end

function NS.QualityColor(quality)
    if C_Item and C_Item.GetItemQualityColor and quality then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then return r, g, b end
    end
    local color = _G.ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

--- Niveau d'objet moyen équipé, nil si le client ne le donne pas.
function NS.GetAverageItemLevel()
    if not _G.GetAverageItemLevel then return nil end
    return (select(2, GetAverageItemLevel()))
end

--- Forme actuelle (id de forme), nil si l'API manque.
function NS.GetShapeshiftFormID()
    return _G.GetShapeshiftFormID and GetShapeshiftFormID() or nil
end

--------------------------------------------------------------------------------
-- Nameplates
--------------------------------------------------------------------------------

function NS.GetTargetNamePlate()
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    if not UnitExists("target") then return nil end
    return C_NamePlate.GetNamePlateForUnit("target")
end

--- `unit` désigne-t-il la cible ? nil quand la réponse est secrète : l'appelant s'abstient.
function NS.IsTarget(unit)
    if not unit or not _G.UnitIsUnit then return false end
    local same = UnitIsUnit(unit, "target")
    if isSecret(same) then return nil end
    return same and true or false
end

--------------------------------------------------------------------------------
-- Social
--------------------------------------------------------------------------------

function NS.GetOnlineFriends()
    local wow = 0
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
        wow = C_FriendList.GetNumOnlineFriends() or 0
    elseif _G.GetNumFriends then
        wow = select(2, GetNumFriends()) or 0
    end
    local bnet = 0
    if _G.BNGetNumFriends then bnet = select(2, BNGetNumFriends()) or 0 end
    return wow, bnet
end

function NS.GetOnlineGuildMembers()
    if not (_G.IsInGuild and IsInGuild()) or not _G.GetNumGuildMembers then return nil end
    local total, online = GetNumGuildMembers()
    return online or 0, total or 0
end

function NS.GetNumGuildMembers()
    return _G.GetNumGuildMembers and (GetNumGuildMembers()) or 0
end

--- name, rank, rankIndex, level, class, zone, note, officerNote, online, status, classFile
function NS.GetGuildRosterInfo(index)
    if not _G.GetGuildRosterInfo then return nil end
    return GetGuildRosterInfo(index)
end

function NS.RequestGuildRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif _G.GuildRoster then
        GuildRoster()
    end
end

--- L'inviteur est-il un ami (WoW ou Battle.net) ou un membre de la guilde ?
function NS.IsTrustedPlayer(guid, name)
    if not isSecret(guid) and guid then
        if C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then return true end
        if C_BattleNet and C_BattleNet.GetAccountInfoByGUID and C_BattleNet.GetAccountInfoByGUID(guid) then
            return true
        end
        if _G.IsGuildMember and IsGuildMember(guid) then return true end
    end
    if not isSecret(name) and name and C_FriendList and C_FriendList.GetFriendInfo then
        -- Repli par nom : un inviteur d'un autre royaume n'a pas toujours de GUID exploitable.
        if C_FriendList.GetFriendInfo(name) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Fenêtres Blizzard
--------------------------------------------------------------------------------

function NS.ToggleFriends()
    if _G.ToggleFriendsFrame then ToggleFriendsFrame(1) end
end

function NS.ToggleGuild()
    if _G.ToggleGuildFrame then
        ToggleGuildFrame()
    elseif _G.ToggleFriendsFrame then
        ToggleFriendsFrame(3)
    end
end

function NS.ToggleClock()
    if _G.ToggleCalendar then
        ToggleCalendar()
    elseif _G.TimeManager_Toggle then
        TimeManager_Toggle()
    end
end

function NS.ToggleCharacterSheet()
    if _G.ToggleCharacter then ToggleCharacter("PaperDollFrame") end
end

function NS.ToggleBags()
    if _G.ToggleAllBags then ToggleAllBags() elseif _G.OpenAllBags then OpenAllBags() end
end

--- Le joueur est-il maître du butin ? nil quand le client ne sait pas le dire.
-- GetLootMethod rend ("master", partyID, raidID) ; partyID 0 = le joueur lui-même.
function NS.IsMasterLooter()
    local getMethod = _G.GetLootMethod or (_G.C_PartyInfo and C_PartyInfo.GetLootMethod)
    if not getMethod then return nil end
    local ok, method, partyID, raidID = pcall(getMethod)
    if not ok or NS.IsSecret(method) or NS.IsSecret(partyID) or NS.IsSecret(raidID) then return nil end
    local master = method == "master"
        or (_G.Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter ~= nil and method == Enum.LootMethod.Masterlooter)
    if not master then return false end
    if partyID == 0 then return true end
    if partyID then return false end   -- 1 à 4 : un autre membre du groupe
    if raidID and _G.UnitIsUnit then
        local same = UnitIsUnit("raid" .. raidID, "player")
        if not NS.IsSecret(same) then return same == true end
    end
    return nil
end

--- Fenêtre StaticPopup visible pour `which`. StaticPopup_Visible rend (nom) sur les vieux
-- clients et (visible, frame) sur les récents : on accepte les deux formes.
function NS.GetVisiblePopup(which)
    if not _G.StaticPopup_Visible then return nil end
    local a, b = StaticPopup_Visible(which)
    if type(b) == "table" then return b end
    if type(a) == "table" then return a end
    if type(a) == "string" then return _G[a] end
    return nil
end

function NS.GetPopupButton(popup, index)
    if popup.GetButton then
        local button = popup:GetButton(index)
        if button then return button end
    end
    return popup["button" .. index] or (popup.GetName and _G[(popup:GetName() or "") .. "Button" .. index])
end

function NS.GetPopupEditBox(popup)
    if popup.GetEditBox then
        local box = popup:GetEditBox()
        if box then return box end
    end
    return popup.editBox or popup.EditBox or (popup.GetName and _G[(popup:GetName() or "") .. "EditBox"])
end

--------------------------------------------------------------------------------
-- Sons
--------------------------------------------------------------------------------
-- Presets : uniquement des sons du client (SOUNDKIT), aucun fichier tiers embarqué.
-- Le joueur peut importer le sien (NS.PlayCustomSound). Chaque preset liste des variantes du MÊME son, les noms changeant d'un client à l'autre.

NS.SOUND_PRESETS = {
    alarm      = { "UI_RAID_BOSS_WHISPER_WARNING", "RAID_WARNING" },
    raidwarning = { "RAID_WARNING" },
    readycheck = { "READY_CHECK", "READY_CHECK_WARNING" },
    ping       = { "IG_MAINMENU_OPTION_CHECKBOX_ON", "IG_MAINMENU_OPEN" },
    bell       = { "ALARM_CLOCK_WARNING_1", "ALARM_CLOCK_WARNING_2" },
}
NS.SOUND_PRESET_ORDER = { "ping", "bell", "readycheck", "raidwarning", "alarm" }

--- Son importé par le joueur : chemin depuis le dossier du jeu (fichier .ogg ou .mp3 posé avant
-- le lancement du client) ou FileDataID. Faux si vide ou illisible : l'appelant joue son son par défaut.
function NS.PlayCustomSound(file)
    if type(file) ~= "string" or not _G.PlaySoundFile then return false end
    file = file:match("^%s*(.-)%s*$")
    if file == "" then return false end
    local ok, willPlay = pcall(PlaySoundFile, tonumber(file) or file, "Master")
    return ok and willPlay ~= false
end

--- Joue `file` s'il est lisible, sinon le preset `name`.
function NS.PlayPreset(name, file)
    if NS.PlayCustomSound(file) then return true end
    local kits = _G.SOUNDKIT
    local candidates = NS.SOUND_PRESETS[name]
    if not kits or not candidates or not _G.PlaySound then return false end
    for i = 1, #candidates do
        local id = kits[candidates[i]]
        if id then
            local ok, willPlay = pcall(PlaySound, id, "Master")
            if ok and willPlay ~= false then return true end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Rendu
--------------------------------------------------------------------------------

function NS.SetSolidColor(texture, r, g, b, a)
    if texture.SetColorTexture then
        texture:SetColorTexture(r, g, b, a or 1)
    else
        texture:SetTexture(r, g, b, a or 1)
    end
end

function NS.ClassColor(classFile)
    local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
    local c = colors and classFile and colors[classFile]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

--- "Guerrier" / "Warrior" -> "WARRIOR". C_FriendList ne donne que le nom localisé de la classe,
-- alors que les tables de couleurs sont indexées par jeton.
function NS.ClassTokenFromLocalized(localized)
    if not localized or isSecret(localized) then return nil end
    for _, names in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE or {}, _G.LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
        for token, name in pairs(names) do
            if name == localized then return token end
        end
    end
    return nil
end

--- Polices du jeu (toujours présentes) + celles de LibSharedMedia si un autre addon l'embarque.
function NS.GetFontList()
    local fonts = {
        { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
        { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
        { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
        { name = "Skurri",        path = "Fonts\\SKURRI.TTF" },
    }
    local LSM = _G.LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local known = {}
        for _, f in ipairs(fonts) do known[f.path] = true end
        for name, path in pairs(LSM:HashTable("font")) do
            if not known[path] then fonts[#fonts + 1] = { name = name, path = path } end
        end
        table.sort(fonts, function(a, b) return a.name < b.name end)
    end
    return fonts
end

--- Sélecteur de couleur : API SetupColorPickerAndShow sur les clients récents.
function NS.OpenColorPicker(color, onChange)
    local picker = _G.ColorPickerFrame
    if not picker or not picker.SetupColorPickerAndShow then return false end
    -- Opacité proposée dès que la couleur porte un alpha (fond, bordure, chat).
    local hasOpacity = color.a ~= nil
    local function apply(r, g, b, a)
        color.r, color.g, color.b = r, g, b
        if hasOpacity and a then color.a = a end
        onChange()
    end
    local function alpha()
        if not hasOpacity then return nil end
        if picker.GetColorAlpha then return picker:GetColorAlpha() end
        return _G.OpacitySliderFrame and (1 - OpacitySliderFrame:GetValue()) or color.a
    end
    picker:SetupColorPickerAndShow({
        r = color.r, g = color.g, b = color.b, hasOpacity = hasOpacity, opacity = color.a,
        swatchFunc = function() local r, g, b = picker:GetColorRGB() apply(r, g, b, alpha()) end,
        opacityFunc = function() local r, g, b = picker:GetColorRGB() apply(r, g, b, alpha()) end,
        cancelFunc = function(prev) apply(prev.r, prev.g, prev.b, prev.opacity or prev.a) end,
    })
    return true
end

--------------------------------------------------------------------------------
-- Panneau d'options (API Settings)
--------------------------------------------------------------------------------

--- Enregistre la page d'Options > AddOns (un bouton vers la fenêtre AeonUI). Retourne la catégorie.
function NS.RegisterOptionsPanel(panel, name)
    panel.name = name
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, name)
        Settings.RegisterAddOnCategory(category)
        NS.optionsPanel = panel
        NS.optionsCategoryId = category:GetID()
        return category
    elseif _G.InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        NS.optionsPanel = panel
        return name
    end
end

--- Fenêtre d'options AeonUI (Config/Options.lua), sur `page` si donnée.
function NS.OpenOptions(page)
    if NS.Options then NS.Options:Open(page) end
end

--------------------------------------------------------------------------------
-- Dispositions : Edit Mode et Cooldown Manager
--------------------------------------------------------------------------------
-- Les API existent sur Forever (/aeon diag) mais leurs signatures ne sont pas toutes
-- vérifiées en jeu : tout est en pcall. Chaque import touche des cadres sécurisés :
-- l'appelant passe par NS:RunOutOfCombat.

--- Dispositions livrées par AeonUI : chaînes exportées depuis le jeu.
-- editMode : export Edit Mode capturé sur Forever 1.60.1 (build 69913) le 2026-09-20, format v3,
-- 59 systèmes. Point de départ proche du modèle Blizzard « Moderne » : la disposition AeonUI
-- définitive viendra avec les cadres propres (étape 7, construite par code sur les movers).
-- Retouche à la main : chat (système 8) posé en bas à gauche à 10, 100, symétrique du chat
-- butin/commerce de l'installation (Config/AddonPlacements.lua).
-- cooldown : vide tant que l'export du Cooldown Manager n'est pas capturé : l'assistant grise le bouton.
NS.PRESET_LAYOUTS = {
    editMode = [==[3 59 0 0 1 8 6 MicroMenuContainer -4.5 -4.0 -1 ##$$%/&('%)$+#,$ 0 1 1 7 7 UIParent 0.0 0.0 -1 ##$$%/&('%(#,$ 0 2 1 7 7 UIParent 0.0 0.0 -1 ##$$%/&('%(#,$ 0 3 1 5 5 UIParent -5.0 -77.0 -1 #$$$%/&('%(#,$ 0 4 1 5 5 UIParent -5.0 -77.0 -1 #$$$%/&('%(#,$ 0 5 1 1 4 UIParent 0.0 0.0 -1 ##$$%/&('%(#,$ 0 6 1 1 4 UIParent 0.0 -50.0 -1 ##$$%/&('%(#,$ 0 7 1 1 4 UIParent 0.0 -100.0 -1 ##$$%/&('%(#,$ 0 10 1 7 7 UIParent 0.0 -4.0 -1 ##$$&('% 0 11 1 7 7 UIParent 0.0 -4.0 -1 ##$$&('%,# 0 12 1 7 7 UIParent 0.0 -4.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%(&( 3 0 1 0 0 UIParent 4.0 -4.0 -1 $#3# 3 1 1 0 0 UIParent 250.0 -4.0 -1 %#3# 3 2 1 0 0 UIParent 500.0 -240.0 -1 %#&#3# 3 3 1 0 2 CompactRaidFrameManager 0.0 -7.0 -1 '#(#)#-=.+/#1$3#5#6(7-7$8(9( 3 4 1 0 2 CompactRaidFrameManager 0.0 -5.0 -1 ,#-=.+/#0#1#2(3#5#6(7-7$8(9( 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 1 5 5 UIParent 0.0 0.0 -1 -=.+/#4$5#6(7-7$8(9( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 1 7 7 UIParent 0.0 -4.0 -1 # 5 -1 1 7 7 UIParent 0.0 -4.0 -1 # 6 0 1 2 2 UIParent -255.0 -10.0 -1 ##$#%#&.(()( 6 1 1 2 2 UIParent -270.0 -155.0 -1 ##$#%#'+(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 1 7 7 UIParent 0.0 -4.0 -1 # 8 -1 1 6 6 UIParent 10.0 100.0 -1 #)$r%+&# 9 -1 1 7 7 UIParent 0.0 -4.0 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 1 8 8 UIParent -9.0 85.0 -1 # 12 -1 1 2 2 UIParent -110.0 -275.0 -1 #K$#%# 13 -1 1 7 7 UIParent 116.5 6.0 -1 ##$#%) 14 -1 1 6 8 MicroMenuContainer 7.0 -4.0 -1 ##$#%( 15 0 1 7 7 UIParent 0.0 0.0 -1 &- 15 1 1 7 7 UIParent 0.0 17.0 -1 &- 16 -1 1 5 5 UIParent 0.0 0.0 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 1 5 5 UIParent 0.0 0.0 -1 #- 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 1 7 7 UIParent 0.0 310.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 1 7 7 UIParent 0.0 240.0 -1 ##$*%$&('%(-($)#+$,$-$ 20 2 1 7 7 UIParent 0.0 370.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 1 7 7 UIParent 420.0 430.0 -1 #$$$%#&('((-($)#*#+$,$-$.-.$ 21 -1 1 7 7 UIParent -410.0 380.0 -1 ##%#&#'((()#*-*$+#,&-#.#/(0#1# 22 0 1 8 7 UIParent -457.0 336.0 -1 #$$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+% 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&7&%'7(%)U+$,$-$.(/U 24 -1 1 1 1 UIParent 0.0 -182.0 -1 # 25 -1 1 5 7 UIParent -28.0 128.0 -1 # 26 0 1 5 3 MainActionBar 30.0 5.0 -1 ## 26 1 1 3 5 BagsBar -30.0 5.0 -1 ## 27 -1 1 4 4 Minimap -68.0 -68.0 -1 #- 28 -1 1 4 4 UIParent 0.0 0.0 -1 #( 29 0 1 7 7 UIParent 0.0 450.0 -1 #($U%#&D&%'2($)$ 29 1 1 7 7 UIParent 0.0 425.0 -1 #($U%#&D&%'2($)$ 29 2 1 7 7 UIParent 0.0 400.0 -1 #($U%#&D&%'2($)$]==],
    cooldown = "",
}

NS.MAX_EDIT_MODE_LAYOUTS = 5

local function PresetCount()
    local meta = _G.Enum and Enum.EditModePresetLayoutsMeta
    return meta and meta.NumValues or 2
end

--- Chaîne de la disposition Edit Mode active, ou nil (prédéfinie Blizzard : rien à exporter).
function NS.ExportEditModeLayout()
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.ConvertLayoutInfoToString) then return nil end
    local ok, layouts = pcall(C_EditMode.GetLayouts)
    if not ok or type(layouts) ~= "table" then return nil end
    local info = layouts.layouts and layouts.layouts[(layouts.activeLayout or 0) - PresetCount()]
    if not info then return nil end
    local converted, text = pcall(C_EditMode.ConvertLayoutInfoToString, info)
    return converted and text or nil
end

--- Importe `text` comme disposition Edit Mode nommée `name` (remplace l'homonyme) et l'active.
-- Retourne true, ou false + "absent" | "full" | "invalid".
function NS.ImportEditModeLayout(text, name)
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.ConvertStringToLayoutInfo
            and C_EditMode.SaveLayouts) then return false, "absent" end
    local ok, layouts = pcall(C_EditMode.GetLayouts)
    if not ok or type(layouts) ~= "table" or type(layouts.layouts) ~= "table" then return false, "absent" end
    local list = layouts.layouts
    for i = #list, 1, -1 do
        if list[i].layoutName == name then tremove(list, i) end
    end
    if #list >= NS.MAX_EDIT_MODE_LAYOUTS then return false, "full" end
    local converted, info = pcall(C_EditMode.ConvertStringToLayoutInfo, text or "")
    if not converted or type(info) ~= "table" then return false, "invalid" end
    info.layoutName = name
    local kind = _G.Enum and Enum.EditModeLayoutType
    if kind then info.layoutType = kind.Account end
    list[#list + 1] = info
    local index = PresetCount() + #list
    layouts.activeLayout = index
    if not pcall(C_EditMode.SaveLayouts, layouts) then return false, "absent" end
    if C_EditMode.OnLayoutAdded then pcall(C_EditMode.OnLayoutAdded, index, true, true) end
    if C_EditMode.SetActiveLayout then pcall(C_EditMode.SetActiveLayout, index) end
    return true
end

local function CooldownLayoutManager()
    local settings = _G.CooldownViewerSettings
    if not (settings and settings.GetLayoutManager) then return nil end
    local ok, manager = pcall(settings.GetLayoutManager, settings)
    return ok and manager or nil
end

-- ponytail: noms sondés, aucun confirmé en jeu ; si aucun ne répond l'assistant masque l'export.
local COOLDOWN_EXPORT_METHODS = { "GetSerializedLayoutData", "GetSerializedData", "SerializeLayout", "ExportLayout" }
-- En jeu (1.60.1) le gestionnaire expose GetSerializer() : les méthodes du sérialiseur sont
-- sondées par /aeon diag avant d'être branchées ici.

-- Source Blizzard (CooldownViewerSettingsLayoutManager.lua) : CopyLayoutToClipboard(layout) fait
-- GetSerializer():SerializeLayouts(layoutID) ; CreateLayoutsFromSerializedData(text) fait
-- DeserializeLayouts(text, true). Format "<version>|<base64 deflate CBOR>". Même chemin ici.
-- GetActiveLayoutID est nil tant que le joueur n'a pas créé sa propre disposition (modèle Blizzard).
local function CooldownSerializer(manager)
    if type(manager.GetSerializer) ~= "function" then return nil end
    local ok, serializer = pcall(manager.GetSerializer, manager)
    return ok and serializer or nil
end

function NS.CanExportCooldownLayout()
    local manager = CooldownLayoutManager()
    if not manager then return false end
    local serializer = CooldownSerializer(manager)
    if serializer and type(serializer.SerializeLayouts) == "function" and type(manager.GetActiveLayoutID) == "function" then
        return true
    end
    for _, method in ipairs(COOLDOWN_EXPORT_METHODS) do
        if type(manager[method]) == "function" then return true end
    end
    return false
end

--- Chaîne sérialisée de la disposition Cooldown Manager active, ou nil + "default" si le
-- joueur est sur un modèle Blizzard (rien à exporter), nil + "absent" sinon.
function NS.ExportCooldownLayout()
    local manager = CooldownLayoutManager()
    if not manager then return nil, "absent" end
    local serializer = CooldownSerializer(manager)
    if serializer and type(serializer.SerializeLayouts) == "function" and type(manager.GetActiveLayoutID) == "function" then
        local okID, layoutID = pcall(manager.GetActiveLayoutID, manager)
        if not okID or layoutID == nil then return nil, "default" end
        local ok, text = pcall(serializer.SerializeLayouts, serializer, layoutID)
        if ok and type(text) == "string" and text ~= "" then return text end
        return nil, "absent"
    end
    for _, method in ipairs(COOLDOWN_EXPORT_METHODS) do
        if type(manager[method]) == "function" then
            local ok, text = pcall(manager[method], manager)
            if ok and type(text) == "string" and text ~= "" then return text end
        end
    end
    return nil, "absent"
end

--- Crée les dispositions Cooldown Manager du blob et active la première.
-- Pas de spécialisation sur Forever : pas de choix par nom de spé.
function NS.ImportCooldownLayout(text)
    local manager = CooldownLayoutManager()
    if not (manager and manager.CreateLayoutsFromSerializedData) then return false, "absent" end
    local ok, ids = pcall(manager.CreateLayoutsFromSerializedData, manager, text or "")
    if not ok or type(ids) ~= "table" or not ids[1] then return false, "invalid" end
    if manager.SetActiveLayoutByID then pcall(manager.SetActiveLayoutByID, manager, ids[1]) end
    if manager.SaveLayouts then pcall(manager.SaveLayouts, manager) end
    return true
end

--------------------------------------------------------------------------------
-- Formatage
--------------------------------------------------------------------------------

--- 123456 -> "12g 34s 56c" avec les couleurs des pièces. Les zéros de tête sont omis.
function NS.FormatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "|cffffd700g|r" end
    if gold > 0 or silver > 0 then parts[#parts + 1] = silver .. "|cffc7c7cfs|r" end
    parts[#parts + 1] = rest .. "|cffeda55fc|r"
    return table.concat(parts, " ")
end

--- 75 -> "1:15", 3725 -> "1:02:05".
function NS.FormatDuration(seconds)
    seconds = math.floor(seconds + 0.5)
    local h = math.floor(seconds / 3600)
    local m = math.floor(seconds / 60) % 60
    local s = seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

--------------------------------------------------------------------------------
-- Cadres Blizzard remplacés (cadres d'unité ; party/raid à l'étape 4)
--------------------------------------------------------------------------------
-- Un cadre Blizzard ne se détruit pas : on coupe ses événements, on le cache et on le
-- reparente sous un cadre caché. Blizzard le reparente parfois (Edit Mode) : le hook le
-- ramène. Les événements ne reviennent qu'au /reload : ShowBlizzardFrame rend le parent et
-- cesse de garder le cadre caché, sans l'afficher (un Show() venu de l'addon lance son OnShow
-- en exécution contaminée : comparaison de valeurs secrètes, erreur dans UnitFrame.lua). Le
-- cadre réapparaît au /reload ; l'appelant prévient l'utilisateur.

-- Les systèmes Edit Mode remplacent Hide, SetPoint et ClearAllPoints par des versions Lua qui
-- relancent la mise en page Blizzard (EditModeSystemMixin, EditModeActionBarMixin). Appelées
-- par l'addon, cette mise en page tourne contaminée et contamine les champs qu'elle écrit :
-- taint.log, MainActionBar.flyoutDirection puis optionTable des cadres de groupe, erreurs de
-- valeurs secrètes à l'ouverture du mode Édition. Les méthodes d'origine restent sous *Base.
function NS.HideRaw(frame) (frame.HideBase or frame.Hide)(frame) end
function NS.ClearPointsRaw(frame) (frame.ClearAllPointsBase or frame.ClearAllPoints)(frame) end
function NS.SetPointRaw(frame, ...) (frame.SetPointBase or frame.SetPoint)(frame, ...) end

local hiddenParent
local hiddenState = setmetatable({}, { __mode = "k" })   -- [frame] = { parent, active }

local function HiddenParent()
    if not hiddenParent then
        hiddenParent = CreateFrame("Frame", "AeonUI_Hidden", UIParent)
        hiddenParent:Hide()
    end
    return hiddenParent
end

local BLIZZARD_CHILD_KEYS = {
    "healthbar", "HealthBar", "manabar", "ManaBar", "castBar", "spellbar", "CastingBarFrame",
    "BuffFrame", "DebuffFrame", "AurasFrame", "PetFrame", "petFrame", "totFrame", "CcRemoverFrame",
    "powerBarAlt", "PowerBarAlt",
}

local function UnregisterChild(child)
    if type(child) == "table" and child.UnregisterAllEvents then child:UnregisterAllEvents() end
end

--- Coupe et cache un cadre Blizzard. Différé hors combat si le cadre est protégé.
-- `noReparent` : événements coupés et caché seulement (cadres gérés par Edit Mode : les
-- reparenter risque un taint). Retourne false si le cadre n'existe pas.
function NS.HideBlizzardFrame(frame, noReparent)
    if type(frame) == "string" then frame = _G[frame] end
    if type(frame) ~= "table" then return false end
    local function hide()
        local state = hiddenState[frame]
        if not state then
            state = { parent = frame:GetParent(), reparent = not noReparent }
            hiddenState[frame] = state
            if state.reparent then
                hooksecurefunc(frame, "SetParent", function(self, parent)
                    local current = hiddenState[self]
                    if current and current.active and parent ~= HiddenParent() then
                        NS:RunOutOfCombat(function()
                            if hiddenState[self] and hiddenState[self].active then self:SetParent(HiddenParent()) end
                        end)
                    end
                end)
            end
        end
        state.active = true
        frame:UnregisterAllEvents()
        NS.HideRaw(frame)
        if state.reparent then frame:SetParent(HiddenParent()) end
        for _, key in ipairs(BLIZZARD_CHILD_KEYS) do UnregisterChild(frame[key]) end
        local container = frame.HealthBarsContainer
        if type(container) == "table" then UnregisterChild(container.healthBar or container.HealthBar) end
    end
    if frame.IsProtected and frame:IsProtected() then NS:RunOutOfCombat(hide) else hide() end
    return true
end

--- Cache une région ou un cadre de décor Blizzard (texture, bouton) et le garde caché si
-- Blizzard le remontre. Réversible par NS.ShowRegion. Pas de reparentage ni d'événements
-- coupés (l'objet doit revivre tel quel au ShowRegion). Cadre protégé : caché hors combat.
local hiddenRegions = setmetatable({}, { __mode = "k" })   -- [objet] = true tant que caché
local function HideRegionNow(object)
    if not hiddenRegions[object] then return end
    if object.IsProtected and object:IsProtected() and NS.InCombat() then
        NS:RunOutOfCombat(function() if hiddenRegions[object] then NS.HideRaw(object) end end)
    else
        NS.HideRaw(object)
    end
end
function NS.HideRegion(object)
    if type(object) == "string" then object = _G[object] end
    if type(object) ~= "table" or not object.Hide then return false end
    if hiddenRegions[object] == nil then
        hooksecurefunc(object, "Show", HideRegionNow)
        -- Barre Edit Mode (postures, familier) : réaffichée par ShowBase, hors du hook de Show.
        if object.UpdateVisibility then hooksecurefunc(object, "UpdateVisibility", HideRegionNow) end
    end
    hiddenRegions[object] = true
    HideRegionNow(object)
    return true
end

function NS.ShowRegion(object)
    if type(object) == "string" then object = _G[object] end
    if type(object) ~= "table" or not hiddenRegions[object] then return false end
    hiddenRegions[object] = false
    -- Barre Edit Mode : ShowOverride relancerait la mise en page contaminée. ShowBase seulement
    -- si Blizzard la veut visible (lire isShownExternal ne contamine rien).
    if object.ShowBase then
        if object.isShownExternal then object:ShowBase() end
    else
        object:Show()
    end
    return true
end

function NS.IsRegionHidden(object)
    if type(object) == "string" then object = _G[object] end
    return type(object) == "table" and hiddenRegions[object] == true
end

--- Rend le parent d'origine d'un cadre masqué par HideBlizzardFrame. Pas de Show() : voir plus haut.
function NS.ShowBlizzardFrame(frame)
    if type(frame) == "string" then frame = _G[frame] end
    local state = type(frame) == "table" and hiddenState[frame] or nil
    if not state or not state.active then return false end
    local function show()
        state.active = false
        if state.reparent then frame:SetParent(state.parent or UIParent) end
        -- Une frame plus tard : toujours rendu (pas re-caché par un changement de profil qui garde
        -- le module) -> BLIZZARD_FRAMES_RELEASED, les options proposent /reload.
        C_Timer.After(0, function()
            if not state.active then NS:Fire("BLIZZARD_FRAMES_RELEASED") end
        end)
    end
    if frame.IsProtected and frame:IsProtected() then NS:RunOutOfCombat(show) else show() end
    return true
end

function NS.IsBlizzardFrameHidden(frame)
    if type(frame) == "string" then frame = _G[frame] end
    local state = type(frame) == "table" and hiddenState[frame] or nil
    return state ~= nil and state.active == true
end

--------------------------------------------------------------------------------
-- Conteneur d'auras du moteur (Blizzard_AuraContainer)
--------------------------------------------------------------------------------
-- Le moteur lit, trie et affiche les auras lui-même : aucune donnée secrète ne passe par
-- l'addon. Sondé une fois ; le cadre de sonde reste caché.

-- NS.auraContainerProbe : nil = pas encore sondé (les tests le remettent à nil).
function NS.AuraContainerAvailable()
    if NS.auraContainerProbe ~= nil then return NS.auraContainerProbe end
    NS.auraContainerProbe = false
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    local ok, probeFrame = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if ok and type(probeFrame) == "table" and type(probeFrame.AddAuraGroup) == "function" then
        probeFrame:Hide()
        NS.auraContainerProbe = true
    end
    return NS.auraContainerProbe
end

--------------------------------------------------------------------------------
-- Diagnostic (/aeon diag)
--------------------------------------------------------------------------------
-- Ce que ce client expose vraiment. Volontairement non traduit : sert à remonter un bug.

--------------------------------------------------------------------------------
-- Midnight : afficher une valeur secrète sans la lire (étape 10)
--------------------------------------------------------------------------------
-- Le moteur 12.x offre des API qui prennent une valeur secrète et l'affichent lui-même :
-- couleur de vie par courbe, alpha par booléen, texte de recharge par formateur. Le Lua ne
-- compare jamais la valeur. Chaque fonction a un repli quand le client n'a pas l'API.

--- Identité de l'unité masquée par le moteur (nom, classe, rôle illisibles).
function NS.IsSecretUnit(unit)
    local api = (_G.C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret) or _G.ShouldUnitIdentityBeSecret
    if not api or not unit or isSecret(unit) then return false end
    local ok, secret = pcall(api, unit)
    return ok and not isSecret(secret) and secret == true
end

--------------------------------------------------------------------------------
-- Fenêtres de chat (installation)
--------------------------------------------------------------------------------
-- Fonctions FCF_* et ChatFrame_* : globales sur le client, parfois méthodes du cadre sur le
-- moteur 12.x. Chaque appel en pcall : une fonction absente ou refusée n'arrête pas le reste.

local function ChatCall(frame, globalName, method, ...)
    if method and frame[method] then return pcall(frame[method], frame, ...) end
    local fn = _G[globalName]
    if fn then return pcall(fn, frame, ...) end
    return false
end

--- Chat à la manière d'ElvUI : fenêtres remises à zéro, ChatFrame1 garde général et système,
-- seconde fenêtre détachée (butin, commerce, argent, réputation, XP) posée par `spec.point`
-- { point, x, y, largeur, hauteur }. Retourne la seconde fenêtre, ou nil si le client refuse.
-- ChatFrame1 est un système Edit Mode : sa place vient de la disposition importée, pas d'ici.
function NS.SetupChatWindows(spec)
    if not (_G.FCF_ResetChatWindows and _G.FCF_OpenNewWindow and _G.ChatFrame1) then return nil end
    if not pcall(FCF_ResetChatWindows) then return nil end
    local ok, right = pcall(FCF_OpenNewWindow, spec.name)
    if not ok or not right then return nil end
    if _G.FCF_UnDockFrame then pcall(FCF_UnDockFrame, right) end
    local p = spec.point
    right:ClearAllPoints()
    right:SetPoint(p[1], UIParent, p[1], p[2], p[3])
    right:SetSize(p[4], p[5])
    if _G.FCF_SavePositionAndDimensions then pcall(FCF_SavePositionAndDimensions, right) end
    for frame, groups in pairs({ [ChatFrame1] = spec.mainGroups, [right] = spec.rightGroups }) do
        ChatCall(frame, "ChatFrame_RemoveAllMessageGroups", "RemoveAllMessageGroups")
        for _, group in ipairs(groups) do ChatCall(frame, "ChatFrame_AddMessageGroup", "AddMessageGroup", group) end
        if _G.SetChatWindowSize and frame.GetID then pcall(SetChatWindowSize, frame:GetID(), spec.fontSize) end
    end
    if spec.general then ChatCall(ChatFrame1, "ChatFrame_AddChannel", "AddChannel", spec.general) end
    if spec.trade then
        ChatCall(ChatFrame1, "ChatFrame_RemoveChannel", "RemoveChannel", spec.trade)
        ChatCall(right, "ChatFrame_AddChannel", "AddChannel", spec.trade)
    end
    if _G.ChangeChatColor then
        for channel, color in pairs(spec.channelColors or {}) do pcall(ChangeChatColor, channel, unpack(color)) end
    end
    return right
end

--- Unité affichée par une infobulle. Moteur : TooltipUtil (tooltip:GetUnit n'existe plus sur Forever).
function NS.TooltipUnit(tooltip)
    if _G.TooltipUtil and TooltipUtil.GetDisplayedUnit then
        return select(2, TooltipUtil.GetDisplayedUnit(tooltip))
    end
    if tooltip.GetUnit then return select(2, tooltip:GetUnit()) end
    return nil
end

-- Dégradé de vie : rouge, jaune, vert (mêmes teintes que la réaction).
local GRADIENT = { { 0, 0.85, 0.2, 0.2 }, { 0.5, 0.9, 0.8, 0.2 }, { 1, 0.2, 0.75, 0.2 } }

--- Couleur du dégradé pour une fraction 0-1 (repli Lua quand les valeurs sont lisibles).
function NS.GradientRGB(fraction)
    fraction = math.max(0, math.min(1, fraction))
    for i = 2, #GRADIENT do
        local a, b = GRADIENT[i - 1], GRADIENT[i]
        if fraction <= b[1] then
            local t = (fraction - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
        end
    end
    local last = GRADIENT[#GRADIENT]
    return last[2], last[3], last[4]
end

local healthCurve   -- nil : pas encore construite, false : API absente
local function HealthCurve()
    if healthCurve == nil then
        healthCurve = false
        local api = _G.C_CurveUtil and C_CurveUtil.CreateColorCurve
        if api and _G.CreateColor then
            local ok, curve = pcall(api)
            if ok and curve and curve.AddPoint then
                for _, point in ipairs(GRADIENT) do curve:AddPoint(point[1], CreateColor(point[2], point[3], point[4])) end
                healthCurve = curve
            end
        end
    end
    return healthCurve or nil
end

--- Couleur de vie en dégradé : applied, r, g, b. Moteur : UnitHealthPercent avec courbe ; les
-- composantes peuvent alors être secrètes (elles trahiraient le pourcentage) : l'appelant teste
-- `applied`, jamais r, et passe r, g, b tels quels à SetStatusBarColor.
-- Repli : fraction calculée si vie et vie max sont lisibles. false : rien de possible.
function NS.HealthGradient(unit)
    local curve = HealthCurve()
    if curve and _G.UnitHealthPercent then
        local ok, color = pcall(UnitHealthPercent, unit, true, curve)
        if ok and type(color) == "table" and color.GetRGB then return true, color:GetRGB() end
    end
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if isSecret(cur) or isSecret(max) or type(max) ~= "number" or max <= 0 then return false end
    return true, NS.GradientRGB(cur / max)
end

--- Alpha d'après la portée. Moteur : SetAlphaFromBoolean (booléen secret accepté).
-- Repli : test en Lua, plein si la portée est secrète. Portée non vérifiée (soi-même) : plein.
function NS.SetRangeAlpha(frame, unit, outsideAlpha)
    if not _G.UnitInRange then frame:SetAlpha(1) return end
    local inRange, checked = UnitInRange(unit)
    if not isSecret(checked) and not checked then frame:SetAlpha(1) return end
    -- Vérification secrète : soi-même et les membres hors ligne restent pleins (état lisible).
    local isSelf = UnitIsUnit(unit, "player")
    local connected = _G.UnitIsConnected and UnitIsConnected(unit)
    if (not isSecret(isSelf) and isSelf) or (not isSecret(connected) and connected ~= nil and not connected) then
        frame:SetAlpha(1)
        return
    end
    if frame.SetAlphaFromBoolean then
        frame:SetAlphaFromBoolean(inRange, 1, outsideAlpha)
    elseif isSecret(inRange) then
        frame:SetAlpha(1)
    else
        frame:SetAlpha(inRange and 1 or outsideAlpha)
    end
end

--------------------------------------------------------------------------------
-- Texte de recharge coloré (formateur natif)
--------------------------------------------------------------------------------
-- Chaque recharge AeonUI s'enregistre ici. Avec un réglage actif (posé par le module
-- Interface), le moteur écrit lui-même le temps restant, coloré par palier : il ne passe
-- jamais la durée au Lua. Sans formateur natif, seule la CVar countdownForCooldowns agit.

local cooldowns = setmetatable({}, { __mode = "k" })
NS.CooldownText = { config = nil }   -- { expiring = s, colors = { expiring, seconds, minutes } }

local function Byte(v) return math.floor(math.max(0, math.min(1, v or 1)) * 255 + 0.5) end
local function Hex(c) return string.format("ff%02x%02x%02x", Byte(c.r), Byte(c.g), Byte(c.b)) end
local function Wrap(c, fmt) return "|c" .. Hex(c) .. fmt .. "|r" end

--- Paliers du formateur, par seuil croissant : décimales sous le seuil d'expiration, secondes,
-- minutes, heures, jours.
function NS.CooldownBreakpoints(cfg)
    local rounding = _G.Enum and Enum.NumericRuleFormatRounding
    local up = rounding and rounding.Up or 1
    local c = cfg.colors
    local points = {}
    if (cfg.expiring or 0) > 0 then
        points[#points + 1] = { threshold = 0, format = Wrap(c.expiring, "%.1f"), step = 0.1 }
    end
    points[#points + 1] = { threshold = cfg.expiring or 0, format = Wrap(c.seconds, "%.0f"), rounding = up, step = 1 }
    points[#points + 1] = { threshold = 59, format = Wrap(c.minutes, "%.0fm"), components = { { div = 60 } } }
    -- Chaque palier démarre une unité plus tôt (59 s, 59 min, 23 h) : jamais « 60m » ni « 24h ».
    points[#points + 1] = { threshold = 3540, format = Wrap(c.minutes, "%.0fh"), components = { { div = 3600 } } }
    points[#points + 1] = { threshold = 82800, format = Wrap(c.minutes, "%.0fd"), components = { { div = 86400 } } }
    return points
end

local function CanFormat(cooldown)
    return cooldown.SetCountdownFormatter and _G.C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
end
NS.CooldownText.Supported = function()
    return _G.C_StringUtil ~= nil and C_StringUtil.CreateNumericRuleFormatter ~= nil
end

--- Applique (ou retire) le texte coloré sur une recharge.
function NS.StyleCooldown(cooldown)
    if not CanFormat(cooldown) then return end
    local cfg = NS.CooldownText.config
    if cfg then
        cooldown.foreverFormatter = cooldown.foreverFormatter or C_StringUtil.CreateNumericRuleFormatter()
        cooldown.foreverFormatter:SetBreakpoints(NS.CooldownBreakpoints(cfg))
        cooldown:SetCountdownFormatter(cooldown.foreverFormatter)
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(false) end
        cooldown.foreverStyled = true
    elseif cooldown.foreverStyled then
        pcall(cooldown.SetCountdownFormatter, cooldown, nil)
        -- Valeur par défaut du modèle : la CVar countdownForCooldowns décide ensuite.
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(false) end
        cooldown.foreverStyled = nil
    end
end

function NS.RegisterCooldown(cooldown)
    if not cooldown then return end
    cooldowns[cooldown] = true
    NS.StyleCooldown(cooldown)
end

--- Réglage changé : toutes les recharges enregistrées suivent.
function NS.RefreshCooldowns()
    for cooldown in pairs(cooldowns) do NS.StyleCooldown(cooldown) end
end

--- Présence des API Midnight utilisées ci-dessus (ligne de /aeon diag).
local midnightProbe   -- cadre et recharge de sonde, créés une fois
function NS.DiagnosticMidnight()
    if not midnightProbe then
        local frame = CreateFrame("Frame")
        midnightProbe = { frame = frame, cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate") }
    end
    local probeFrame, probeCooldown = midnightProbe.frame, midnightProbe.cooldown
    local checks = {
        { "formateur de recharge", NS.CooldownText.Supported() and probeCooldown.SetCountdownFormatter ~= nil },
        { "courbe de couleurs", _G.C_CurveUtil ~= nil and C_CurveUtil.CreateColorCurve ~= nil },
        { "UnitHealthPercent", _G.UnitHealthPercent ~= nil },
        { "SetAlphaFromBoolean", probeFrame.SetAlphaFromBoolean ~= nil },
        { "identité secrète", (_G.C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret or _G.ShouldUnitIdentityBeSecret) ~= nil },
        { "recharge par objet durée", probeCooldown.SetCooldownFromDurationObject ~= nil },
    }
    local parts = {}
    for _, check in ipairs(checks) do parts[#parts + 1] = check[1] .. (check[2] and " oui" or " non") end
    return table.concat(parts, ", ")
end

local DIAG_APIS = {
    "C_CooldownViewer", "CooldownViewerSettings", "C_EditMode", "C_ToyBox", "C_LFGList",
    "ToggleCalendar", "GetSpecialization", "GetActiveTalentGroup", "C_SwingTimer", "UnitGroupRolesAssigned", "GetPartyAssignment",
    "C_UnitAuras", "C_Container", "C_DamageMeter", "issecretvalue", "TooltipDataProcessor",
    "MinimapCluster", "CompactUnitFrame_UpdateName", "UnitFrameHealthBar_Update",
    "TalkingHeadFrame", "CinematicFrame", "MovieFrame", "C_GossipInfo", "BuffFrame",
    "PlayerFrame", "TargetFrame", "CharacterFrame", "RegisterStateDriver",
}
local DIAG_CVARS = {
    "spellActivationOverlayOpacity", "displaySpellActivationOverlays", "cooldownViewerEnabled",
    "scriptErrors", "autoLootDefault", "showTutorials", "nameplateShowEnemies", "countdownForCooldowns",
}

function NS.Diagnostic()
    local _, build, _, iface = GetBuildInfo()
    local lines = { string.format("client %s (build %s), interface %s", tostring((GetBuildInfo())),
        tostring(build), tostring(iface)) }
    local present, missing = {}, {}
    for _, name in ipairs(DIAG_APIS) do
        if _G[name] ~= nil then present[#present + 1] = name else missing[#missing + 1] = name end
    end
    lines[#lines + 1] = "API ok : " .. table.concat(present, ", ")
    lines[#lines + 1] = "API absentes : " .. (#missing > 0 and table.concat(missing, ", ") or "-")
    local cvars = {}
    for _, name in ipairs(DIAG_CVARS) do
        cvars[#cvars + 1] = name .. "=" .. tostring(NS.CVars:Get(name))
    end
    lines[#lines + 1] = "CVars : " .. table.concat(cvars, ", ")
    -- Chaque sonde isolée : une API qui lève ne doit pas priver des autres lignes.
    local function probe(label, fn)
        local ok, text = pcall(fn)
        lines[#lines + 1] = label .. " : " .. (ok and tostring(text) or ("erreur : " .. tostring(text)))
    end
    probe("Edit Mode", NS.DiagnosticEditMode)
    probe("Cooldown Manager", NS.DiagnosticCooldownManager)
    probe("Menace", NS.DiagnosticThreat)
    probe("Unit frames", NS.DiagnosticUnitFrames)
    probe("Midnight", NS.DiagnosticMidnight)
    local thirdParty = NS.Modules and NS.Modules:LoadedThirdParty() or {}
    lines[#lines + 1] = "Addons tiers chargés : " .. (#thirdParty > 0 and table.concat(thirdParty, ", ") or "-")
    return lines
end

--- Disposition active et longueur de la chaîne exportable (la chaîne elle-même passe par l'assistant).
function NS.DiagnosticEditMode()
    if not (C_EditMode and C_EditMode.GetLayouts) then return "API absente" end
    local ok, layouts = pcall(C_EditMode.GetLayouts)
    if not ok or type(layouts) ~= "table" then return "GetLayouts en erreur" end
    local custom = type(layouts.layouts) == "table" and #layouts.layouts or 0
    local text = NS.ExportEditModeLayout()
    return string.format("active=%s, personnalisées=%d/%d, export=%s",
        tostring(layouts.activeLayout), custom, NS.MAX_EDIT_MODE_LAYOUTS,
        text and (#text .. " caractères") or "prédéfinie Blizzard (rien à exporter)")
end

local COOLDOWN_METHOD_PATTERNS = { "Serial", "Export", "Import", "String", "Layout", "Save" }

--- Méthodes du gestionnaire de dispositions du Cooldown Manager qui ressemblent à un import/export.
-- Sert à confirmer en jeu les noms sondés dans COOLDOWN_EXPORT_METHODS.
function NS.DiagnosticCooldownManager()
    local manager = CooldownLayoutManager()
    if not manager then return "gestionnaire absent" end
    local seen, names = {}, {}
    local function collect(source)
        if type(source) ~= "table" then return end
        for key, value in pairs(source) do
            if type(key) == "string" and type(value) == "function" and not seen[key] then
                for _, pattern in ipairs(COOLDOWN_METHOD_PATTERNS) do
                    if key:find(pattern, 1, true) then seen[key] = true; names[#names + 1] = key; break end
                end
            end
        end
    end
    collect(manager)
    local meta = getmetatable(manager)
    collect(meta and meta.__index)
    table.sort(names)
    if #names == 0 then return "aucune méthode import/export" end
    local text = string.format("%d méthodes : %s", #names, table.concat(names, ", "))
    -- En jeu (1.60.1) : GetSerializer, CopyLayoutToClipboard, ImportLayout, CreateLayoutsFromSerializedData.
    -- Le sérialiseur porte l'export : on liste ses méthodes pour brancher NS.ExportCooldownLayout.
    if type(manager.GetSerializer) == "function" then
        local ok, serializer = pcall(manager.GetSerializer, manager)
        local methods = {}
        local function collectAll(source)
            if type(source) ~= "table" then return end
            for key, value in pairs(source) do
                if type(key) == "string" and type(value) == "function" then methods[#methods + 1] = key end
            end
        end
        if ok and serializer then
            collectAll(serializer)
            local meta = getmetatable(serializer)
            collectAll(meta and meta.__index)
        end
        table.sort(methods)
        text = text .. " | sérialiseur : " .. (#methods > 0 and table.concat(methods, ", ") or tostring(serializer))
    end
    return text
end

--- Ce que l'API de menace renvoie sur la cible : nil, valeur secrète ou nombre.
function NS.DiagnosticThreat()
    if not UnitThreatSituation then return "API absente" end
    local ok, value = pcall(UnitThreatSituation, "player", "target")
    if not ok then return "erreur : " .. tostring(value) end
    if NS.IsSecret and NS.IsSecret(value) then return "valeur secrète" end
    return tostring(value)
end

local probeBar   -- une seule StatusBar de sonde, jamais recréée
--- API du moteur 12.x dont dépendent les cadres d'unité (chaque absence a son repli).
function NS.DiagnosticUnitFrames()
    local names = { "UnitHealthPercent", "UnitPowerPercent", "AbbreviateNumbers",
                    "UnitCastingDuration", "UnitChannelDuration", "loadstring", "SecureGroupHeader_Update" }
    local present, missing = {}, {}
    for _, name in ipairs(names) do
        if _G[name] ~= nil then present[#present + 1] = name else missing[#missing + 1] = name end
    end
    local bar = probeBar or CreateFrame("StatusBar")
    probeBar = bar
    bar:Hide()
    if type(bar.SetTimerDuration) == "function" then present[#present + 1] = "StatusBar:SetTimerDuration"
    else missing[#missing + 1] = "StatusBar:SetTimerDuration" end
    if Enum and Enum.StatusBarTimerDirection then present[#present + 1] = "Enum.StatusBarTimerDirection"
    else missing[#missing + 1] = "Enum.StatusBarTimerDirection" end
    if _G.ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.UnregisterFrame then present[#present + 1] = "ActionBarButtonEventsFrame:UnregisterFrame"
    else missing[#missing + 1] = "ActionBarButtonEventsFrame:UnregisterFrame" end
    if C_ActionBar and C_ActionBar.GetActionCooldownDuration then present[#present + 1] = "C_ActionBar.GetActionCooldownDuration"
    else missing[#missing + 1] = "C_ActionBar.GetActionCooldownDuration" end
    if NS.AuraContainerAvailable() then present[#present + 1] = "CustomAuraContainerTemplate"
    else missing[#missing + 1] = "CustomAuraContainerTemplate" end
    return "ok : " .. (#present > 0 and table.concat(present, ", ") or "-")
        .. " ; absentes : " .. (#missing > 0 and table.concat(missing, ", ") or "-")
end
