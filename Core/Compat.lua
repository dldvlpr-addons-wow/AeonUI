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
    if C_Spell and C_Spell.GetSpellTexture then return (C_Spell.GetSpellTexture(id)) end
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

--- Identifiant du rang appris de `id` (Classic : un id par rang), à passer aux API de
-- recharge, qui ne cherchent que par identifiant. `id` lui-même si le grimoire ne répond pas.
-- Par le nom d'abord : le grimoire rend le rang le plus haut (portée, recharge), alors que les
-- rangs inférieurs restent connus (IsPlayerSpell vrai sur le rang 1).
function NS.KnownSpellID(id)
    local name = NS.GetSpellName(id)
    local info = name and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
    local known = type(info) == "table" and info.spellID
    if not known or isSecret(known) then return id end
    return known
end

--- Quête répétable (remise d'étoffes, réputation) ? false si l'API manque ou refuse.
function NS.IsRepeatableQuest(questID)
    if not questID or not (C_QuestLog and C_QuestLog.IsRepeatableQuest) then return false end
    local ok, repeatable = pcall(C_QuestLog.IsRepeatableQuest, questID)
    return ok and not isSecret(repeatable) and repeatable == true
end

--- Quête active n° `index` de la liste d'un PNJ (QuestGreeting) : répétable ?
function NS.IsActiveQuestRepeatable(index)
    return NS.IsRepeatableQuest(_G.GetActiveQuestID and GetActiveQuestID(index))
end

--- Objet utilisable d'une quête du journal (lien) : quêtes suivies d'abord ; nil sinon.
function NS.GetQuestItemLink()
    local itemInfo = _G.GetQuestLogSpecialItemInfo
    if not (itemInfo and C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return nil end
    local fallback
    for index = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local link = itemInfo(index)
        if link then
            local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(index)
            if info and C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(info.questID) then return link end
            fallback = fallback or link
        end
    end
    return fallback
end

--- Quête affichée dans QuestFrame (QUEST_PROGRESS, QUEST_DETAIL) : répétable ?
function NS.IsCurrentQuestRepeatable()
    return NS.IsRepeatableQuest(_G.GetQuestID and GetQuestID())
end

--- Type PvP de la zone ("sanctuary", "contested", "hostile"…) ; nil si le client ne le donne pas.
function NS.GetZonePVPInfo()
    if C_PvP and C_PvP.GetZonePVPInfo then return (C_PvP.GetZonePVPInfo()) end
    if _G.GetZonePVPInfo then return (GetZonePVPInfo()) end
    return nil
end

--- Unité en Feindre la mort ? false si l'API manque, nil si la valeur est secrète (l'appelant s'abstient).
function NS.IsFeignDeath(unit)
    if not _G.UnitIsFeignDeath then return false end
    local feign = UnitIsFeignDeath(unit)
    if isSecret(feign) then return nil end
    return feign == true
end

--------------------------------------------------------------------------------
-- Auras du joueur
--------------------------------------------------------------------------------

local function AuraName(unit, index)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        -- Aura secrète (en combat) : le moteur lève une erreur au lieu de répondre.
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
        if not ok then return nil, true end
        if isSecret(aura) then return aura end
        if not aura then return nil end
        return aura.name
    end
    if _G.UnitBuff then return (UnitBuff(unit, index)) end
    if _G.UnitAura then return (UnitAura(unit, index, "HELPFUL")) end
    return nil
end

--- `unit` porte-t-il un buff dont le nom est dans `names` (table [nom] = true) ?
-- Retourne nil quand le client refuse de répondre (nom secret) : l'appelant s'abstient.
function NS.UnitHasBuff(unit, names)
    for index = 1, 40 do
        local name, refused = AuraName(unit, index)
        if refused or isSecret(name) then return nil end
        if name == nil then return false end
        if names[name] then return true end
    end
    return false
end

--- Comme NS.UnitHasBuff, pour le joueur.
function NS.PlayerHasBuff(names) return NS.UnitHasBuff("player", names) end

--- Débuff n° `index` de `unit` : icône, durée, fin, stacks, type de dissipation, débuff de
-- boss, identifiant du sort, posé par le joueur (ou son familier), identifiant d'instance. Tout peut être SECRET sur le moteur 12.x : l'appelant vérifie NS.IsSecret avant de
-- comparer, et passe le reste aux widgets tel quel.
-- nil quand il n'y en a plus, ou quand le client refuse de répondre.
function NS.GetDebuff(unit, index) return NS.GetAura(unit, index, "HARMFUL") end

--- Comme NS.GetDebuff, pour le filtre `filter` ("HARMFUL" ou "HELPFUL").
function NS.GetAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        if not ok or isSecret(aura) or aura == nil then return nil end
        return aura.icon, aura.duration, aura.expirationTime, aura.applications, aura.dispelName, aura.isBossAura,
            aura.spellId, aura.isFromPlayerOrPlayerPet, aura.auraInstanceID, aura.name
    end
    local legacy = filter == "HELPFUL" and _G.UnitBuff or _G.UnitDebuff
    if legacy then
        local name, icon, count, dispelType, duration, expirationTime, source, _, _, spellId, _, isBossDebuff = legacy(unit, index)
        local isMine
        if isSecret(source) then isMine = source
        else isMine = source == "player" or source == "pet" end
        return icon, duration, expirationTime, count, dispelType, isBossDebuff, spellId, isMine, nil, name
    end
    return nil
end

--- Le client refuse-t-il de lire les auras de `unit` (auras secrètes en combat, code tainted) ?
-- NS.GetAura rend alors nil comme pour « plus d'aura » : l'appelant garde son affichage.
function NS.AurasRefused(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
    return not pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HELPFUL")
end

local crowdControl = {}
--- Débuffs de contrôle (étourdissement, peur, métamorphose…) de `unit` : { [auraInstanceID] = true }.
-- Table réutilisée, à lire tout de suite. Le moteur les désigne lui-même (filtre CROWD_CONTROL),
-- sans lire d'identifiant de sort, donc aussi en combat.
-- ponytail: filtre supposé présent avec les valeurs secrètes (moteur 12.x) ; sans lui, aucun contrôle signalé.
function NS.CrowdControlAuras(unit)
    wipe(crowdControl)
    if not (_G.issecretvalue and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return crowdControl end
    for index = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HARMFUL|CROWD_CONTROL")
        if not ok or isSecret(aura) or aura == nil then break end
        local id = aura.auraInstanceID
        if id ~= nil and not isSecret(id) then crowdControl[id] = true end
    end
    return crowdControl
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

--- Anime `bar` par le moteur (SetTimerDuration sur un objet durée) de `start` à `start + duration`,
-- qui se vide (`remaining`) ou se remplit. false sans l'API : l'appelant anime lui-même.
function NS.SetBarTimer(bar, start, duration, remaining)
    local util, dirs = _G.C_DurationUtil, Enum and Enum.StatusBarTimerDirection
    if not (util and util.CreateDuration and bar.SetTimerDuration and dirs) then return false end
    bar.durationObject = bar.durationObject or util.CreateDuration()
    bar.durationObject:SetTimeFromStart(start, duration)
    local immediate = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or nil
    bar:SetTimerDuration(bar.durationObject, immediate, remaining and dirs.RemainingTime or dirs.ElapsedTime)
    return true
end

--- Anime `bar` sur la durée restante d'une aura par l'objet durée du moteur (valable même
-- secrète, en combat). false sans l'API : l'appelant lit les valeurs brutes s'il le peut.
-- ponytail: C_UnitAuras.GetAuraDuration supposé présent avec le moteur 12.x.
function NS.SetAuraBarTimer(bar, unit, auraInstanceID)
    local api, dirs = C_UnitAuras and C_UnitAuras.GetAuraDuration, Enum and Enum.StatusBarTimerDirection
    if not (api and bar.SetTimerDuration and dirs) or auraInstanceID == nil or isSecret(auraInstanceID) then return false end
    local ok, duration = pcall(api, unit, auraInstanceID)
    if not ok or not duration then return false end
    local immediate = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or nil
    bar:SetTimerDuration(duration, immediate, dirs.RemainingTime)
    return true
end

--- Portée d'attaque suivie par le moteur pour ce type de coup (Enum.PlayerSwingType).
-- L'événement PLAYER_SWING_RANGE_UPDATE signale ensuite chaque changement.
function NS.SetSwingRangeCheck(swingType, on)
    local api = _G.C_SwingTimer and C_SwingTimer.EnableRangeCheck
    if api then pcall(api, swingType, on and true or false) end
end

--- La cible est-elle à portée de ce type de coup ? nil : aucune vérification possible (pas de
-- cible, pas d'arme, API absente, valeur secrète).
function NS.IsSwingTargetInRange(swingType)
    local api = _G.C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange
    if not api then return nil end
    local ok, inRange = pcall(api, swingType)
    if not ok or isSecret(inRange) or type(inRange) ~= "boolean" then return nil end
    return inRange
end

--- Humeur du familier de chasseur : bonheur (1 mécontent, 2 content, 3 heureux), part des dégâts
-- en %, tendance de loyauté. nil sans familier de chasseur, sans l'API ou valeur secrète.
-- Forever : C_PetInfo.GetPetHappiness ; clients Classic : GetPetHappiness globale.
function NS.GetPetHappiness()
    local api = (_G.C_PetInfo and C_PetInfo.GetPetHappiness) or _G.GetPetHappiness
    if not api or not _G.HasPetUI then return nil end
    local _, hunterPet = HasPetUI()
    if isSecret(hunterPet) or not hunterPet then return nil end
    local ok, happiness, damage, loyalty = pcall(api)
    if not ok or isSecret(happiness) or type(happiness) ~= "number" then return nil end
    if isSecret(damage) then damage = nil end
    if isSecret(loyalty) then loyalty = nil end
    return happiness, damage, loyalty
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

--- L'unité est-elle tank : rôle choisi, ou tank principal du raid ? Valeur secrète : non.
function NS.IsTankUnit(unit)
    if _G.UnitGroupRolesAssigned then
        local role = UnitGroupRolesAssigned(unit)
        if not isSecret(role) and role == "TANK" then return true end
    end
    if _G.GetPartyAssignment then
        local assigned = GetPartyAssignment("MAINTANK", unit)
        if not isSecret(assigned) and assigned then return true end
    end
    return false
end

--- Un autre tank du groupe tient-il l'agro de `mob` ? Sans jeton composé (`nameplate1target` est
-- secret) : menace de chaque tank du groupe sur `mob`. Valeur secrète : non.
function NS.OtherTankHasAggro(mob)
    if not (_G.UnitThreatSituation and _G.GetNumGroupMembers) then return false end
    local inRaid = _G.IsInRaid and IsInRaid()
    local prefix, count = "raid", GetNumGroupMembers()
    if not inRaid then prefix, count = "party", count - 1 end
    for i = 1, count do
        -- Le joueur lui-même n'y passe pas : l'appelant a déjà écarté sa propre agro (statut 2 ou 3).
        local unit = prefix .. i
        if NS.IsTankUnit(unit) then
            local ok, status = pcall(UnitThreatSituation, unit, mob)
            if ok and not isSecret(status) and status and status >= 2 then return true end
        end
    end
    return false
end

--- Points de combo du joueur sur sa cible, tels quels (peut-être secrets) : pour StatusBar:SetValue.
function NS.ComboPointsRaw()
    if _G.GetComboPoints then return (GetComboPoints("player", "target")) end
    return UnitPower("player", Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4)
end

--- Points de combo du joueur sur sa cible, et leur maximum ; nil pour une classe qui n'en a pas ou si secrets.
-- GetComboPoints d'abord : UnitPower rend parfois 0 sur Forever pour ce type de puissance.
function NS.GetComboPoints()
    local points = NS.ComboPointsRaw()
    local max = UnitPowerMax("player", Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4)
    if isSecret(points) or isSecret(max) or type(points) ~= "number" then return nil end
    if type(max) ~= "number" or max <= 0 then return nil end   -- classe sans points de combo
    return points, max
end

local GLOBAL_COOLDOWN_SPELL = 61304   -- sort « Recharge globale » du moteur

--- Recharge globale en cours : début, durée (en s) ; nil hors recharge, sans l'API ou si secrète.
function NS.GetGlobalCooldown()
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, GLOBAL_COOLDOWN_SPELL)
    if not ok or type(info) ~= "table" then return nil end
    local start, duration = info.startTime, info.duration
    if isSecret(start) or isSecret(duration) or not start or not duration or duration <= 0 then return nil end
    return start, duration
end

--- Latence du monde en secondes (GetNetStats), 0 si inconnue.
function NS.WorldLatency()
    if not _G.GetNetStats then return 0 end
    local _, _, _, world = GetNetStats()
    if isSecret(world) or type(world) ~= "number" then return 0 end
    return world / 1000
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
-- charges ou si le maximum est secret. current peut être secret (combat) : l'appelant l'affiche
-- sans le comparer (SetFormattedText). Recharge secrète : début et durée à 0.
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
    if isSecret(max) or type(max) ~= "number" then return nil end
    if not isSecret(current) and type(current) ~= "number" then return nil end
    if isSecret(start) or isSecret(duration) then start, duration = 0, 0 end
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
    if _G.GetNumSpecializations and _G.GetSpecializationInfo and _G.GetSpecialization then
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

-- Motifs des lignes « Nom (30 min) » d'un enchantement temporaire, tirés des formats localisés.
local tempEnchantPatterns
local function TempEnchantPatterns()
    if tempEnchantPatterns then return tempEnchantPatterns end
    tempEnchantPatterns = {}
    for _, key in ipairs({ "ITEM_ENCHANT_TIME_LEFT_DAYS", "ITEM_ENCHANT_TIME_LEFT_HOURS",
                           "ITEM_ENCHANT_TIME_LEFT_MIN", "ITEM_ENCHANT_TIME_LEFT_SEC" }) do
        local format = _G[key]
        if type(format) == "string" then
            local pattern = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
                :gsub("|4[^;]*;", ".-")
                :gsub("%%%d?%$?s", ".+")
                :gsub("%%%d?%$?d", "%%d+")
            tempEnchantPatterns[#tempEnchantPatterns + 1] = "^" .. pattern .. "$"
        end
    end
    return tempEnchantPatterns
end

--- Ligne d'enchantement temporaire dans l'infobulle de l'arme principale. nil si texte secret.
local function MainHandTooltipHasTempEnchant()
    local info = _G.C_TooltipInfo
    local data = info and info.GetInventoryItem and info.GetInventoryItem("player", 16)
    if not (data and data.lines) then return false end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if isSecret(text) then return nil end
        if type(text) == "string" then
            for _, pattern in ipairs(TempEnchantPatterns()) do
                if text:match(pattern) then return true end
            end
        end
    end
    return false
end

--- Arme principale enchantée (poison, arme de chaman…). nil si le client ne sait pas répondre.
-- Forever ne remonte pas l'arme de chaman dans GetWeaponEnchantInfo (false alors que l'infobulle
-- affiche « Croque-roc (30 min) ») : repli sur l'infobulle.
function NS.HasMainHandEnchant()
    if not _G.GetWeaponEnchantInfo then return MainHandTooltipHasTempEnchant() end
    local has = GetWeaponEnchantInfo()
    if isSecret(has) then return nil end
    if has then return true end
    return MainHandTooltipHasTempEnchant()
end

--------------------------------------------------------------------------------
-- Sacs
--------------------------------------------------------------------------------

local Container = _G.C_Container or {}
NS.NUM_BAGS = _G.NUM_BAG_SLOTS or 4
-- Sac de réactifs (moteur retail) ; nil si le client n'en a pas.
NS.REAGENT_BAG = _G.Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or nil

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

--- Prend (ou pose, curseur chargé) l'objet de la case. Hors combat seulement pour l'appelant.
function NS.PickupBagItem(bag, slot)
    local fn = Container.PickupContainerItem or _G.PickupContainerItem
    if fn then fn(bag, slot) end
end

--- Objet arrivé depuis la dernière ouverture des sacs ? false sans l'API.
function NS.IsNewBagItem(bag, slot)
    local api = _G.C_NewItems and C_NewItems.IsNewItem
    return api and api(bag, slot) == true or false
end

--- Taille de pile maximale d'un objet, ou nil tant que le client ne la connaît pas.
function NS.GetItemMaxStack(itemID)
    if C_Item and C_Item.GetItemMaxStackSizeByID then return C_Item.GetItemMaxStackSizeByID(itemID) end
    local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    return getInfo and select(8, getInfo(itemID)) or nil
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
--- Lien et qualité portés dans un emplacement ; unit = "player" par défaut (inspection sinon).
function NS.GetEquipped(slotName, unit)
    unit = unit or "player"
    if not (_G.GetInventorySlotInfo and _G.GetInventoryItemLink) then return nil end
    -- Emplacement inconnu du client (AmmoSlot hors Classic) : erreur, pas nil.
    local ok, slotID = pcall(GetInventorySlotInfo, slotName .. "Slot")
    if not ok or not slotID then return nil end
    local link = GetInventoryItemLink(unit, slotID)
    if not link then return nil end
    return link, _G.GetInventoryItemQuality and GetInventoryItemQuality(unit, slotID) or nil
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
    -- Barre Edit Mode (postures, familier) : réaffichée par ShowBase, hors du hook de Show ; un
    -- hook sur ses méthodes contamine la mise en page (LayoutFrame « attempt to call a nil
    -- value »). Rendue transparente à la place, sans hook.
    if object.UpdateVisibility then
        hiddenRegions[object] = true
        object:SetAlpha(0)
        HideRegionNow(object)
        return true
    end
    if hiddenRegions[object] == nil then
        hooksecurefunc(object, "Show", HideRegionNow)
        -- SetShown(true) ne passe pas par Show (bouton d'extension de la minimap).
        hooksecurefunc(object, "SetShown", function(self, shown) if shown then HideRegionNow(self) end end)
    end
    hiddenRegions[object] = true
    HideRegionNow(object)
    return true
end

function NS.ShowRegion(object)
    if type(object) == "string" then object = _G[object] end
    if type(object) ~= "table" or not hiddenRegions[object] then return false end
    hiddenRegions[object] = false
    if object.UpdateVisibility then object:SetAlpha(1) end
    -- Barre Edit Mode : ShowOverride relancerait la mise en page contaminée. ShowBase seulement
    -- si Blizzard la veut visible (lire isShownExternal ne contamine rien).
    local function show()
        if hiddenRegions[object] then return end
        if object.ShowBase then
            if object.isShownExternal then object:ShowBase() end
        else
            object:Show()
        end
    end
    if object.IsProtected and object:IsProtected() and NS.InCombat() then NS:RunOutOfCombat(show) else show() end
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

--- Conteneur d'auras du moteur sous `parent`, ou nil si le client n'en a pas. Les boutons sont
-- posés par le moteur (flux) ; l'appelant ancre le conteneur. L'unité se pose en dernier
-- (NS.SetAuraContainerUnit) : le moteur n'écoute UNIT_AURA que pour des groupes déclarés.
function NS.CreateAuraContainer(parent)
    if not NS.AuraContainerAvailable() then return nil end
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or type(container) ~= "table" then return nil end
    container:SetSize(1, 1)   -- rect affichable dès le premier passage de mise en page
    container.declared = {}
    return container
end

--- Sens de remplissage : point d'ancrage, croissance horizontale ("LEFT"/"RIGHT") et verticale
-- ("UP"/"DOWN"), longueur de ligne en pixels (nil : sans retour à la ligne). `column` : les
-- éléments s'empilent verticalement (barres).
function NS.SetAuraContainerFlow(container, anchor, horizontal, vertical, lineSize, column)
    local direction = _G.AnchorUtil and AnchorUtil.FlowDirection
    local axis = _G.AnchorUtil and AnchorUtil.FlowLayoutAxis
    if axis then pcall(container.SetFlowLayoutAxis, container, column and axis.Vertical or axis.Horizontal) end
    pcall(container.SetFlowLayoutAnchorPoint, container, anchor)
    if direction then
        pcall(container.SetFlowLayoutGrowthDirection, container,
            horizontal == "LEFT" and direction.Left or direction.Right,
            vertical == "UP" and direction.Up or direction.Down)
    end
    pcall(container.SetFlowLayoutMaximumLineSize, container, lineSize)
end

--- Tri du moteur : `sort` = "expiration" (la plus courte d'abord), sinon priorité des débuffs
-- (boss, dissipables) si `prioritize`, sinon l'ordre du jeu.
local function AuraSort(sort, prioritize)
    local methods, directions = _G.AuraContainerSortMethod, _G.AuraContainerSortDirection
    if not (methods and directions) then return nil, nil end
    if sort == "expiration" then return methods.Expiration, directions.Normal end
    return prioritize and methods.UnitFrameDebuff or methods.Default, directions.Normal
end

--- Filtre du moteur pour un mode d'AeonUI (NS.AURA_FILTERS). « important » (boss ou dissipable)
-- ne s'exprime pas en un filtre : tout passe, trié boss et dissipables d'abord (prioritize).
function NS.AuraEngineFilter(kind, mode)
    if mode == "mine" then return kind .. "|PLAYER" end
    if mode == "dispellable" then return kind .. "|RAID" end
    return kind
end

--- Filtres candidats d'un mode (boss) et des identifiants à écarter (liste noire). Le moteur
-- n'écarte par identifiant que là où il le permet (buffs d'alliés, débuffs d'ennemis, sorts jamais secrets).
function NS.AuraEngineCandidates(mode, exclude)
    return { isBossAura = mode == "boss" or nil, excludeSpellIDs = exclude }
end

--- Déclare ou met à jour le groupe `key`. Un groupe ne se retire pas et crée ses boutons par
-- lots de 10 : tant que `spec.max` vaut 0, il n'est pas déclaré ; ensuite, 0 le vide.
-- spec : { filter, max, index (ordre dans le flux), newLine, size (ou width, height), spacing, sort,
-- prioritize, candidates, init }.
-- Rend false si le moteur refuse la déclaration (filtre invalide).
function NS.SetAuraGroup(container, key, spec)
    local max = spec.max or 0
    local sortMethod, sortDirection = AuraSort(spec.sort, spec.prioritize)
    local layout = { elementSpacing = spec.spacing or 0, lineSpacing = spec.spacing or 0, groupSpacing = 0,
                     groupLineSpacing = spec.spacing or 0, forceNewLine = spec.newLine == true,
                     elementWidth = spec.width or spec.size, elementHeight = spec.height or spec.size,
                     layoutIndex = spec.index }
    if not container.declared[key] then
        if max == 0 then return true end
        local ok = pcall(container.AddAuraGroup, container, key, spec.filter, {
            maxFrameCount = max, sortMethod = sortMethod, sortDirection = sortDirection,
            candidateFilters = spec.candidates, layout = layout, initializeFrame = spec.init,
        })
        container.declared[key] = ok or nil
        return ok
    end
    pcall(container.SetAuraGroupFilterString, container, key, spec.filter)
    pcall(container.SetAuraGroupCandidateFilters, container, key, spec.candidates)
    if sortMethod then pcall(container.SetAuraGroupSortMethod, container, key, sortMethod, sortDirection) end
    pcall(container.SetAuraGroupLayout, container, key, layout)
    pcall(container.SetAuraGroupMaxFrameCount, container, key, max)
    return true
end

--- Emplacement d'une seule aura (le moteur ne le place pas : `init` l'ancre). Déclaré au premier
-- `enabled`, ensuite seulement activé ou coupé. Rend son bouton.
function NS.SetAuraSlot(container, key, filter, enabled, init, candidates)
    if not container.declared[key] then
        if not enabled then return nil end
        local ok, button = pcall(container.AddAuraSlot, container, key, filter,
            { initializeFrame = init, candidateFilters = candidates })
        container.declared[key] = ok and button or nil
        return container.declared[key]
    end
    pcall(container.SetAuraSlotFilterString, container, key, filter)
    pcall(container.SetAuraSlotCandidateFilters, container, key, candidates)
    pcall(container.SetAuraSlotEnabled, container, key, enabled == true)
    return container.declared[key]
end

--- Unité suivie ("none" : aucune). `refresh` : tout relire même sans changement d'unité
-- (le moteur ne relit pas seul au changement de cible).
function NS.SetAuraContainerUnit(container, unit, refresh)
    unit = unit or "none"
    if container:GetUnit() ~= unit then
        container:SetUnit(unit)
        refresh = true
    end
    if refresh then container:UpdateAllAuras() end
end

--- Boutons déjà créés du groupe `key` (pour les retailler).
function NS.AuraGroupButtons(container, key)
    local buttons = {}
    if not container.declared[key] then return buttons end
    local ok, count = pcall(container.GetAuraGroupFrameCount, container, key)
    for i = 1, ok and count or 0 do
        local found, button = pcall(container.GetAuraGroupFrame, container, key, i)
        if found and button then buttons[#buttons + 1] = button end
    end
    return buttons
end

local DISPEL_EDGES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

--- Texture blanche que le moteur teinte à la couleur du type de dissipation de l'aura de `button`
-- (débuffs seulement) et montre ou cache. `always` : texture gardée (remplissage d'une barre),
-- montrée aussi sans type (couleur « aucun »). false si le client n'offre pas ce style.
function NS.AddDispelTexture(button, texture, always)
    local styles = _G.Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    if not always then
        texture:SetColorTexture(1, 1, 1, 1)
        texture:Hide()   -- écrit avant l'enregistrement : ensuite, l'alpha et l'affichage sont au moteur
    end
    if not (styles and styles.PreserveAsset) then return false end
    return (pcall(button.AddDispelTypeTexture, button, texture, { style = styles.PreserveAsset,
        showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = always == true }))
end

--- Quatre bords d'épaisseur `px` autour de `host` (écartés de `inset`), teintés comme ci-dessus.
-- `host` descend de `button`.
function NS.AddDispelEdges(button, host, px, inset)
    local o = inset or 0
    for _, side in ipairs(DISPEL_EDGES) do
        local edge = host:CreateTexture(nil, "OVERLAY", nil, 1)
        if side == "TOP" or side == "BOTTOM" then
            local y = side == "TOP" and o or -o
            edge:SetPoint(side .. "LEFT", host, side .. "LEFT", -o, y)
            edge:SetPoint(side .. "RIGHT", host, side .. "RIGHT", o, y)
            edge:SetHeight(px)
        else
            local x = side == "LEFT" and -o or o
            edge:SetPoint("TOP" .. side, host, "TOP" .. side, x, o)
            edge:SetPoint("BOTTOM" .. side, host, "BOTTOM" .. side, x, -o)
            edge:SetWidth(px)
        end
        NS.AddDispelTexture(button, edge)
    end
end

--- Prépare un bouton du moteur (appelé par initializeFrame, seule fenêtre où le bouton se touche
-- librement). Les régions vivent dans `holder`, enfant du bouton ancré ici une fois : ensuite le
-- rect du bouton est refusé tant que les auras sont secrètes. opts : { size, dispel (bordure
-- teintée par le type de dissipation), highlight (couleur d'un liseré fixe : groupe de contrôles),
-- noNumbers (balayage sans chiffres), durationText (temps restant écrit sous l'icône) }.
function NS.InitAuraButton(button, opts)
    if opts.size then pcall(button.SetSize, button, opts.size, opts.size) end
    pcall(button.SetMouseClickEnabled, button, false)   -- les clics vont au cadre dessous
    pcall(button.SetMouseMotionEnabled, button, false)
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints(button)
    holder:EnableMouse(false)
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(holder)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local cooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    cooldown:SetAllPoints(holder)
    if opts.noNumbers then
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
    else
        NS.RegisterCooldown(cooldown)
    end
    local top = CreateFrame("Frame", nil, holder)   -- bordure et compteur au-dessus du balayage
    top:SetAllPoints(holder)
    top:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    NS.Media:CreateBorder(top)
    local count = NS.Media:CreateText(top, "OVERLAY", -2, "OUTLINE")   -- police posée avant l'enregistrement
    count:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
    pcall(button.SetIcon, button, icon)
    pcall(button.SetDurationCooldown, button, cooldown)
    pcall(button.SetApplicationCount, button, count)
    if opts.durationText then
        local text = NS.Media:CreateText(top, "OVERLAY", 0, "OUTLINE")
        text:SetPoint("TOP", top, "BOTTOM", 0, -2)
        pcall(button.SetDurationText, button, text, {})
    end
    if opts.dispel then NS.AddDispelEdges(button, top, NS.Pixel:Scale(NS.db and NS.db.theme.borderSize or 1)) end
    if opts.highlight then
        local ring = CreateFrame("Frame", nil, top)   -- un cadre par bordure : le thème les repeint chacune
        ring:SetAllPoints(top)
        NS.Media:CreateBorder(ring, opts.highlight, 1)
    end
    holder.count = count   -- alpha libre (le moteur tient le texte et l'affichage)
    return holder
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

--- Chat réorganisé : fenêtres remises à zéro, ChatFrame1 garde général et système,
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

local stepCurves, stepCurveCount = {}, 0
--- Courbe du moteur en paliers (deux points à chaque bord), mise en cache par clé ; nil sans API.
local function StepCurve(key, steps, r, g, b)
    local curve = stepCurves[key]
    if curve ~= nil then return curve or nil end
    if stepCurveCount >= 64 then stepCurves, stepCurveCount = {}, 0 end
    curve = false
    local api = _G.C_CurveUtil and C_CurveUtil.CreateColorCurve
    if api and _G.CreateColor then
        local ok, made = pcall(api)
        if ok and made and made.AddPoint then
            local previous = 0
            for _, step in ipairs(steps) do
                made:AddPoint(previous, CreateColor(step[2], step[3], step[4]))
                made:AddPoint(math.max(previous, step[1] - 0.0001), CreateColor(step[2], step[3], step[4]))
                previous = step[1]
            end
            made:AddPoint(previous, CreateColor(r, g, b))
            made:AddPoint(1, CreateColor(r, g, b))
            curve = made
        end
    end
    stepCurves[key], stepCurveCount = curve, stepCurveCount + 1
    return curve or nil
end

--- Couleur par paliers de `kind` ("health" ou "power") : applied, r, g, b. `steps` = liste croissante
-- de { fraction, r, g, b } : sous `fraction`, cette couleur ; au-dessus du dernier palier, r, g, b.
-- Comme NS.HealthGradient : composantes peut-être secrètes, l'appelant ne teste que `applied`.
function NS.StepColor(unit, kind, steps, r, g, b)
    if #steps == 0 or isSecret(r) or isSecret(g) or isSecret(b) then return false end
    local parts = { kind, r, g, b }
    for _, step in ipairs(steps) do parts[#parts + 1] = table.concat(step, ",") end
    local curve = StepCurve(table.concat(parts, ";"), steps, r, g, b)
    local percent = kind == "health" and _G.UnitHealthPercent or _G.UnitPowerPercent
    if curve and percent then
        local ok, color
        if kind == "health" then ok, color = pcall(percent, unit, true, curve)
        else ok, color = pcall(percent, unit, nil, false, curve) end
        if ok and type(color) == "table" and color.GetRGB then return true, color:GetRGB() end
    end
    local cur, max
    if kind == "health" then cur, max = UnitHealth(unit), UnitHealthMax(unit)
    else cur, max = UnitPower(unit), UnitPowerMax(unit) end
    if isSecret(cur) or isSecret(max) or type(max) ~= "number" or max <= 0 then return false end
    local fraction = cur / max
    for _, step in ipairs(steps) do
        if fraction < step[1] then return true, step[2], step[3], step[4] end
    end
    return true, r, g, b
end

-- Sort de référence par classe pour la portée d'une unité hostile : portée d'attaque habituelle
-- (sort à distance, sinon coup de mêlée). Appelé par l'identifiant du rang appris (NS.KnownSpellID).
local ATTACK_RANGE_SPELL = {
    MAGE = 133, WARLOCK = 686, PRIEST = 585, DRUID = 5176, SHAMAN = 403, HUNTER = 75,
    PALADIN = 20271, WARRIOR = 78, ROGUE = 1752,
}

--- Alpha d'une plaque hostile d'après la portée d'attaque du joueur : `inside` à portée, `outside`
-- au-delà. Booléen secret (combat) : le moteur choisit (SetAlphaFromBoolean). Aucun sort de
-- référence ou pas de réponse : `inside`.
function NS.SetAttackRangeAlpha(frame, unit, inside, outside)
    local _, classFile = UnitClass("player")
    local spell = not isSecret(classFile) and ATTACK_RANGE_SPELL[classFile or ""]
    local api = C_Spell and C_Spell.IsSpellInRange
    if not (spell and api) then frame:SetAlpha(inside) return end
    local ok, inRange = pcall(api, NS.KnownSpellID(spell), unit)
    if not ok then frame:SetAlpha(inside) return end
    if isSecret(inRange) then
        if frame.SetAlphaFromBoolean then frame:SetAlphaFromBoolean(inRange, inside, outside)
        else frame:SetAlpha(inside) end
        return
    end
    frame:SetAlpha(inRange == false and outside or inside)
end

-- Interruptions des classes Classic ; démoniste : Verrou magique du chasseur corrompu (grimoire du familier).
local INTERRUPT_SPELLS = {
    WARRIOR = { 6552, 72 }, ROGUE = { 1766 }, MAGE = { 2139 }, SHAMAN = { 8042 }, PRIEST = { 15487 },
    WARLOCK = { 19244, 19647 },
}
local interruptSpell   -- identifiant du rang appris de l'interruption ; false : aucun ; nil : à relire

local function KnownInterrupt()
    if interruptSpell ~= nil then return interruptSpell end
    interruptSpell = false
    local _, classFile = UnitClass("player")
    local book = _G.C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
    local petBank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    for _, id in ipairs(not isSecret(classFile) and INTERRUPT_SPELLS[classFile or ""] or {}) do
        local known = (_G.IsPlayerSpell and IsPlayerSpell(id))
            or (book and (book(id) or (petBank and book(id, petBank))))
        -- Autre rang que celui de la table : le nom est trouvé dans le grimoire.
        local name = NS.GetSpellName(id)
        if not known and name and C_Spell and C_Spell.GetSpellInfo then known = C_Spell.GetSpellInfo(name) ~= nil end
        if known then interruptSpell = NS.KnownSpellID(id) break end
    end
    return interruptSpell
end

local interruptEvents = CreateFrame("Frame")
interruptEvents:SetScript("OnEvent", function() interruptSpell = nil end)
NS.RegisterEventSafe(interruptEvents, "SPELLS_CHANGED")
NS.RegisterEventSafe(interruptEvents, "UNIT_PET", "player")

--- Couleur d'une barre d'incantation interruptible : `ready` si l'interruption du joueur est
-- disponible, sinon (r, g, b). Recharge secrète : le moteur choisit (EvaluateColorValueFromBoolean).
function NS.InterruptReadyColor(ready, r, g, b)
    local spell = KnownInterrupt()
    local api = C_Spell and C_Spell.GetSpellCooldownDuration
    local pick = _G.C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if not (spell and api and pick) then return r, g, b end
    local ok, duration = pcall(api, spell)
    if not ok or not duration or not duration.IsZero then return r, g, b end
    local available = duration:IsZero()
    return pick(available, ready.r, r), pick(available, ready.g, g), pick(available, ready.b, b)
end

--- Deux couleurs selon un booléen peut-être secret (vrai : première). Sans l'API, un secret
-- donne la seconde.
function NS.ColorFromBoolean(value, r1, g1, b1, r2, g2, b2)
    if not isSecret(value) then
        if value then return r1, g1, b1 end
        return r2, g2, b2
    end
    local pick = _G.C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if not pick then return r2, g2, b2 end
    return pick(value, r1, r2), pick(value, g1, g2), pick(value, b1, b2)
end

--- Soins entrants, absorptions et soins absorbés calculés par le moteur (plafonnés à la vie
-- manquante, peut-être secrets) ; nil sans l'API. Un calculateur par cadre, gardé dans holder.
function NS.GetHealPrediction(holder, unit)
    local create, fill = _G.CreateUnitHealPredictionCalculator, _G.UnitGetDetailedHealPrediction
    if not (create and fill) then return nil end
    local calc = holder.healCalculator
    if not calc then
        calc = create()
        holder.healCalculator = calc
        local enum = _G.Enum or {}
        if enum.UnitIncomingHealClampMode then
            pcall(calc.SetIncomingHealClampMode, calc, enum.UnitIncomingHealClampMode.MissingHealth)
        end
        if enum.UnitHealAbsorbMode then
            pcall(calc.SetHealAbsorbMode, calc, enum.UnitHealAbsorbMode.ReducedByIncomingHeals)
        end
        if enum.UnitHealAbsorbClampMode then
            pcall(calc.SetHealAbsorbClampMode, calc, enum.UnitHealAbsorbClampMode.CurrentHealth)
        end
    end
    if not pcall(fill, unit, nil, calc) then return nil end
    local function amount(value) if isSecret(value) then return value end return value or 0 end
    return amount((calc:GetIncomingHeals())), amount((calc:GetDamageAbsorbs())), amount((calc:GetHealAbsorbs()))
end

--- Sort marqué important par le client (booléen peut-être secret) ; nil sans l'API ou sans sort.
function NS.IsSpellImportant(spellID)
    local api = C_Spell and C_Spell.IsSpellImportant
    if not api or (not isSecret(spellID) and spellID == nil) then return nil end
    local ok, important = pcall(api, spellID)
    if ok then return important end
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
        local ok = pcall(function()
            cooldown.foreverFormatter = cooldown.foreverFormatter or C_StringUtil.CreateNumericRuleFormatter()
            cooldown.foreverFormatter:SetBreakpoints(NS.CooldownBreakpoints(cfg))
            cooldown:SetCountdownFormatter(cooldown.foreverFormatter)
        end)
        if not ok then return end
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
    local failed = NS.Database and NS.Database.migrationErrors or {}
    lines[#lines + 1] = "Migrations en échec : " .. (#failed > 0 and table.concat(failed, " ; ") or "-")
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

--- Charge d'AeonUI : temps moyen récent par image en ms (profileur d'addons du moteur récent,
-- nil sans lui) et mémoire en Ko (nil si le client ne la donne pas). Relevé à la demande.
function NS.AddOnUsage()
    local cpu, memory
    local profiler, metrics = _G.C_AddOnProfiler, _G.Enum and Enum.AddOnProfilerMetric
    if profiler and profiler.GetAddOnMetric and metrics and metrics.RecentAverageTime then
        local ok, value = pcall(profiler.GetAddOnMetric, "AeonUI", metrics.RecentAverageTime)
        if ok and type(value) == "number" and not NS.IsSecret(value) then cpu = value end
    end
    if _G.UpdateAddOnMemoryUsage and _G.GetAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
        local ok, value = pcall(GetAddOnMemoryUsage, "AeonUI")
        if ok and type(value) == "number" then memory = value end
    end
    return cpu, memory
end

--- Icône de l'emplacement d'action `slot` (nil si vide ou illisible).
function NS.GetActionTexture(slot)
    local get = (C_ActionBar and C_ActionBar.GetActionTexture) or _G.GetActionTexture
    if not get then return nil end
    local ok, texture = pcall(get, slot)
    if ok and texture and not NS.IsSecret(texture) then return texture end
    return nil
end
