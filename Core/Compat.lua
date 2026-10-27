-- Core/Compat.lua
-- Seul fichier qui appelle une API susceptible de manquer ou de rendre une « valeur secrète ».
-- Les modules passent par NS.* et ne testent jamais eux-mêmes l'existence d'une fonction.
--
-- Moteur 12.x (WoW Forever 1.60) :
--   * COMBAT_LOG_EVENT_UNFILTERED est interdit aux addons : on ne l'enregistre jamais ;
--   * en combat, auras et incantations peuvent être secrètes (affichables, pas comparables) :
--     toute valeur lue ici qui pourrait l'être passe par NS.IsSecret avant d'être testée.
local ADDON_NAME, NS = ...
_G.MuscaUI = NS
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

--- Coût en mana du sort, ou nil (aucun coût en mana, type illisible). Un coût secret est rendu
-- tel quel : l'appelant ne le passe qu'à un widget (SetValue), sans le comparer.
function NS.GetSpellManaCost(id)
    local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(id)
    local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    for _, cost in ipairs(costs or {}) do
        local kind, amount = cost.type, cost.cost
        if not isSecret(kind) and kind == mana then
            if isSecret(amount) then return amount end
            if amount and amount > 0 then return amount end
        end
    end
    return nil
end

--- Vrai si le sort coûte du mana.
function NS.SpellCostsMana(id)
    local cost = NS.GetSpellManaCost(id)
    return isSecret(cost) or cost ~= nil
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
-- Réponses lisibles du grimoire, vidées à SPELLS_CHANGED (sort ou rang appris).
local knownSpellIDs = {}
local spellsWatcher = CreateFrame("Frame")
spellsWatcher:RegisterEvent("SPELLS_CHANGED")
spellsWatcher:SetScript("OnEvent", function() wipe(knownSpellIDs) end)

function NS.KnownSpellID(id)
    local cached = knownSpellIDs[id]
    if cached then return cached end
    local name = NS.GetSpellName(id)
    local info = name and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
    local known = type(info) == "table" and info.spellID
    if not known or isSecret(known) then return id end
    knownSpellIDs[id] = known
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

local function Plain(value)
    if isSecret(value) then return nil end
    return value
end

--- Quêtes suivies, dans l'ordre du suivi ; liste vide si l'API manque.
function NS.GetWatchedQuestIDs()
    local list = {}
    local api = C_QuestLog
    if not (api and api.GetNumQuestWatches and api.GetQuestIDForQuestWatchIndex) then return list end
    for index = 1, Plain(api.GetNumQuestWatches()) or 0 do
        local questID = Plain(api.GetQuestIDForQuestWatchIndex(index))
        if questID then list[#list + 1] = questID end
    end
    return list
end

--- Champs d'une quête du journal utiles au tri et aux filtres du suivi ; nil si elle n'y est plus.
function NS.GetQuestFacts(questID)
    local api = C_QuestLog
    if not (api and api.GetLogIndexForQuestID and api.GetInfo) then return nil end
    local logIndex = Plain(api.GetLogIndexForQuestID(questID))
    local info = logIndex and api.GetInfo(logIndex)
    if type(info) ~= "table" or Plain(info.isHeader) then return nil end
    return {
        logIndex = logIndex,
        title = Plain(info.title) or "",
        level = Plain(info.level) or 0,
        frequency = Plain(info.frequency) or 0,
        onMap = Plain(info.isOnMap) == true,
        complete = api.IsComplete and Plain(api.IsComplete(questID)) == true or false,
        trivial = api.IsQuestTrivial and Plain(api.IsQuestTrivial(questID)) == true or false,
    }
end

--- Quêtes du journal sur la carte courante (zone, donjon), dans l'ordre du journal.
function NS.GetQuestIDsOnMap()
    local list = {}
    local api = C_QuestLog
    if not (api and api.GetNumQuestLogEntries and api.GetInfo) then return list end
    for index = 1, Plain(api.GetNumQuestLogEntries()) or 0 do
        local info = api.GetInfo(index)
        if type(info) == "table" and Plain(info.isOnMap) == true and not Plain(info.isHeader)
            and not Plain(info.isHidden) and not Plain(info.isTask) and not Plain(info.isBounty) then
            list[#list + 1] = Plain(info.questID)
        end
    end
    return list
end

--- Suit (true) ou ne suit plus (false) une quête ; false si l'API manque, échoue ou lève une erreur.
function NS.SetQuestWatched(questID, watched)
    local api = C_QuestLog and (watched and C_QuestLog.AddQuestWatch or C_QuestLog.RemoveQuestWatch)
    if not api then return false end
    local ok, result = pcall(api, questID)
    return ok and result ~= false
end

--- Nombre de lignes du journal de quêtes (en-têtes compris) ; 0 tant qu'il n'est pas chargé.
function NS.GetNumQuestLogEntries()
    local api = C_QuestLog
    return api and api.GetNumQuestLogEntries and Plain(api.GetNumQuestLogEntries()) or 0
end

--- Rencontre de boss en cours ; false si l'API manque.
function NS.IsEncounterInProgress()
    return _G.IsEncounterInProgress and Plain(IsEncounterInProgress()) == true or false
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

-- Tank : rôle choisi, ou tank principal du raid. nil si la réponse est secrète.
local function TankRole(unit)
    local secret = false
    if _G.UnitGroupRolesAssigned then
        local role = UnitGroupRolesAssigned(unit)
        if isSecret(role) then secret = true elseif role == "TANK" then return true end
    end
    if _G.GetPartyAssignment then
        local assigned = GetPartyAssignment("MAINTANK", unit)
        if isSecret(assigned) then secret = true elseif assigned then return true end
    end
    if secret then return nil end
    return false
end

--- L'unité est-elle tank : rôle choisi, ou tank principal du raid ? Valeur secrète : non.
function NS.IsTankUnit(unit) return TankRole(unit) == true end

-- Tanks du groupe (joueur compris en raid), vidés à chaque changement de groupe ou de rôle ; gardés
-- seulement si tous les rôles étaient lisibles.
local groupTanks
local rosterWatcher = CreateFrame("Frame")
rosterWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterWatcher:RegisterEvent("PLAYER_ROLES_ASSIGNED")
rosterWatcher:SetScript("OnEvent", function() groupTanks = nil end)

local function GroupTanks()
    if groupTanks then return groupTanks end
    local tanks, readable = {}, true
    local inRaid = _G.IsInRaid and IsInRaid()
    local prefix, count = "raid", GetNumGroupMembers()
    if not inRaid then prefix, count = "party", count - 1 end
    for i = 1, count do
        local unit = prefix .. i
        local tank = TankRole(unit)
        if tank == nil then readable = false elseif tank then tanks[#tanks + 1] = unit end
    end
    if readable then groupTanks = tanks end
    return tanks
end

--- Un autre tank du groupe tient-il l'agro de `mob` ? Sans jeton composé (`nameplate1target` est
-- secret) : menace de chaque tank du groupe sur `mob`. Valeur secrète : non.
function NS.OtherTankHasAggro(mob)
    if not (_G.UnitThreatSituation and _G.GetNumGroupMembers) then return false end
    -- Le joueur lui-même n'y passe pas : l'appelant a déjà écarté sa propre agro (statut 2 ou 3).
    for _, unit in ipairs(GroupTanks()) do
        local ok, status = pcall(UnitThreatSituation, unit, mob)
        if ok and not isSecret(status) and status and status >= 2 then return true end
    end
    return false
end

--- Menace du joueur sur `unit` : % (100 = il prend l'agro) et statut (0 à 3, nil si secret).
-- nil sans liste de menace, sans l'API ou si le % est secret (restriction des valeurs de menace) ;
-- troisième retour vrai dans ce dernier cas.
function NS.GetThreatPercent(unit)
    if not _G.UnitDetailedThreatSituation then return nil end
    local ok, _, status, scaled = pcall(UnitDetailedThreatSituation, "player", unit)
    if ok and isSecret(scaled) then return nil, nil, true end
    if not ok or type(scaled) ~= "number" then return nil end
    return scaled, not isSecret(status) and status or nil
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

-- Sort « Recharge globale » : 61304 sur le moteur, 29515 sur les clients Classic (Forever d'après
-- EllesmereUI, non vérifié en jeu). Le premier qui rapporte une recharge gagne.
local GLOBAL_COOLDOWN_SPELLS = { 61304, 29515 }

--- Recharge globale en cours : début, durée (en s) ; nil hors recharge, sans l'API ou si secrète.
function NS.GetGlobalCooldown()
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    for _, spellID in ipairs(GLOBAL_COOLDOWN_SPELLS) do
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then
            local start, duration = info.startTime, info.duration
            if not isSecret(start) and not isSecret(duration) and start and duration and duration > 0 then
                return start, duration
            end
        end
    end
    return nil
end

--- Latence du monde en secondes (GetNetStats), 0 si inconnue.
function NS.WorldLatency()
    if not _G.GetNetStats then return 0 end
    local _, _, _, world = GetNetStats()
    if isSecret(world) or type(world) ~= "number" then return 0 end
    return world / 1000
end

--- Sort hors recharge ? Charges : prêt au maximum de charges (`anyCharge` : dès une charge, lu
-- sur la recharge du sort). Sinon : pas de vraie recharge (le GCD compte comme prêt). isActive
-- et isOnGCD restent lisibles en combat ; nil si l'API manque ou si la réponse est secrète.
function NS.IsSpellReady(spellID, anyCharge)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local charges = not anyCharge and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
    if charges and not isSecret(charges.maxCharges) and (charges.maxCharges or 0) > 1 then
        if isSecret(charges.isActive) then return nil end
        return not charges.isActive
    end
    local cd = C_Spell.GetSpellCooldown(spellID)
    if not cd then return true end
    if isSecret(cd.isActive) or isSecret(cd.isOnGCD) then return nil end
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

--- Sort utilisable (ressource, forme) ? nil si l'API manque ou si la réponse est secrète.
function NS.IsSpellUsable(spellID)
    if not (C_Spell and C_Spell.IsSpellUsable) then return nil end
    local ok, usable = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok or isSecret(usable) then return nil end
    return usable and true or false
end

--- Sort en surbrillance (proc) ? false si l'API manque ou si la réponse est secrète.
function NS.IsSpellOverlayed(spellID)
    local api = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or _G.IsSpellOverlayed
    if not api or not spellID then return false end
    local ok, on = pcall(api, spellID)
    return ok and not isSecret(on) and on == true
end

--- Emplacements d'action qui portent le sort `spellID` (sort de base) : liste, vide sans API.
function NS.FindSpellActionSlots(spellID)
    local slots = {}
    if isSecret(spellID) or not (C_ActionBar and C_ActionBar.FindSpellActionButtons) then return slots end
    local ok, found = pcall(C_ActionBar.FindSpellActionButtons, spellID)
    for _, slot in ipairs(ok and type(found) == "table" and found or {}) do
        if not isSecret(slot) then slots[#slots + 1] = slot end
    end
    return slots
end

--- Texte court de la première touche liée à la commande `command` (« ACTIONBUTTON1 ») ; nil si
-- aucune touche ou réponse illisible.
function NS.GetBindingText(command)
    if not (_G.GetBindingKey and _G.GetBindingText) then return nil end
    local key = GetBindingKey(command)
    if not key or isSecret(key) then return nil end
    local text = GetBindingText(key, 1)
    if not text or isSecret(text) or text == "" then return nil end
    return text
end

--- Recharge de l'objet porté à l'emplacement `slot` (13, 14 : bijoux) : début, durée, GCD ?
-- nil sans API ou si la réponse est secrète. Durée 0 : pas de recharge (ou objet sans usage).
function NS.GetInventorySlotCooldown(slot)
    if not _G.GetInventoryItemCooldown then return nil end
    local ok, start, duration, _, isOnGCD = pcall(GetInventoryItemCooldown, "player", slot)
    if not ok or isSecret(start) or isSecret(duration) or isSecret(isOnGCD) then return nil end
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    return start, duration, isOnGCD and true or false
end

--- Objet de l'emplacement `slot` hors recharge (le GCD compte comme prêt) ; nil si illisible.
function NS.IsInventorySlotReady(slot)
    local start, duration, isOnGCD = NS.GetInventorySlotCooldown(slot)
    if not start then return nil end
    return isOnGCD or duration == 0 or start + duration <= GetTime()
end

--- Nom et icône de l'objet porté à l'emplacement `slot` ; nil si vide ou illisible.
function NS.GetInventorySlotItem(slot)
    local link = _G.GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if not link or isSecret(link) then return nil end
    local icon = _G.GetInventoryItemTexture and GetInventoryItemTexture("player", slot)
    if isSecret(icon) then icon = nil end
    return link:match("%[(.-)%]") or link, icon
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

--- Sort d'un cooldownID du gestionnaire : clé de réglage, identifiant courant (talent de
-- remplacement) et emplacement d'équipement. Objet porté (bijou) : clé « slot13 », pas de sort,
-- emplacement. nil si l'API manque ou rend une valeur secrète.
function NS.GetCooldownViewerSpell(cooldownID)
    if isSecret(cooldownID) or not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return nil end
    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
    if not ok or not info then return nil end
    local slot = info.equipSlot
    if slot and not isSecret(slot) then return "slot" .. slot, nil, slot end
    if isSecret(info.spellID) or not info.spellID then return nil end
    local live = info.overrideSpellID
    if isSecret(live) or not live or live == 0 then live = info.spellID end
    return info.spellID, live
end

--- Entrées des catégories `categories` (nombre ou liste ; 0 essentiel, 1 utilitaire, 2 icônes de
-- buff, 3 barres de buff, 5 à 8 communs et équipement) : { { spellID, name, icon, slot } } dans
-- l'ordre Blizzard, sans doublon. spellID : clé de réglage (« slot13 » pour un objet porté).
-- `allowUnlearned` : sorts non appris compris.
function NS.GetCooldownViewerSpells(categories, allowUnlearned)
    local list, seen = {}, {}
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then return list end
    for _, category in ipairs(type(categories) == "table" and categories or { categories }) do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, allowUnlearned and true or false)
        for _, cooldownID in ipairs(ok and type(ids) == "table" and ids or {}) do
            local key, live, slot = NS.GetCooldownViewerSpell(cooldownID)
            if key and not seen[key] then
                seen[key] = true
                local name, icon
                if slot then
                    name, icon = NS.GetInventorySlotItem(slot)
                else
                    name = NS.GetSpellName(live) or NS.GetSpellName(key)
                    icon = NS.GetSpellTexture(live) or NS.GetSpellTexture(key)
                end
                list[#list + 1] = { spellID = key, name = name or tostring(key), icon = icon, slot = slot }
            end
        end
    end
    return list
end

--- Opacité Edit Mode (0 à 1) d'une visionneuse du gestionnaire de recharges ; 1 si illisible.
function NS.GetCooldownViewerOpacity(viewer)
    local setting = _G.Enum and Enum.EditModeCooldownViewerSetting and Enum.EditModeCooldownViewerSetting.Opacity
    if not (setting and viewer.GetSettingValue) then return 1 end
    local ok, value = pcall(viewer.GetSettingValue, viewer, setting)
    if not ok or type(value) ~= "number" or value <= 0 then return 1 end
    return value / 100
end

--- Mode édition Blizzard ouvert ?
function NS.IsEditModeActive()
    local manager = _G.EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

--- Appelle `fn` à l'entrée et à la sortie du mode édition Blizzard (EventRegistry).
function NS.OnEditModeToggle(owner, fn)
    local registry = _G.EventRegistry
    if not (registry and registry.RegisterCallback) then return end
    registry:RegisterCallback("EditMode.Enter", fn, owner)
    registry:RegisterCallback("EditMode.Exit", fn, owner)
end

--- Ouvre la fenêtre de réglages du gestionnaire de recharges Blizzard (hors combat) ; faux sinon.
function NS.OpenCooldownViewerSettings()
    local settings = _G.CooldownViewerSettings
    if NS.InCombat() or not (settings and settings.ShowUIPanel) then return false end
    settings:ShowUIPanel()
    return true
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

-- Emplacements d'inventaire des armes, dans l'ordre d'Enum.WeaponSlot (MainHand 0, OffHand 1, Ranged 2).
local WEAPON_INVENTORY_SLOTS = { 16, 17, 18 }
local weaponEnchantDurations = {}   -- ["slot:enchantID"] = plus long temps restant vu (durée totale)

--- Enchantements temporaires des armes, tous types (imprégnation, huile, pierre, poison) :
-- { slot, enchantID, icon, name, charges, expiration, duration }. expiration et duration nil :
-- sans durée. Une valeur illisible (secrète) écarte l'entrée ; second retour vrai alors.
-- ponytail: durée totale = plus long temps restant vu ; après un /reload, la barre repart pleine.
function NS.GetWeaponEnchants()
    local list, unreadable = {}, false
    local api = C_Item and C_Item.GetWeaponEnchantInfo
    if not api then return list, false end
    local now = GetTime()
    for weaponSlot, slot in ipairs(WEAPON_INVENTORY_SLOTS) do
        for _, enchant in ipairs(api(weaponSlot - 1) or {}) do
            local has, timeLeft, charges, icon, id = enchant.hasEnchant, enchant.timeLeft, enchant.charges,
                enchant.enchantIconID, enchant.enchantID
            if isSecret(has) or isSecret(timeLeft) or isSecret(charges) or isSecret(icon) or isSecret(id) then
                unreadable = true
            elseif has then
                local link = _G.GetInventoryItemLink and GetInventoryItemLink("player", slot)
                local name = not isSecret(link) and type(link) == "string" and link:match("%[(.-)%]") or nil
                if not icon or icon == 0 then icon = _G.GetInventoryItemTexture and GetInventoryItemTexture("player", slot) end
                local entry = { slot = slot, enchantID = id, icon = icon, name = name,
                                charges = charges and charges > 0 and charges or nil }
                if timeLeft and timeLeft > 0 then
                    local key = slot .. ":" .. tostring(id)
                    local seconds = timeLeft / 1000
                    weaponEnchantDurations[key] = math.max(weaponEnchantDurations[key] or 0, seconds)
                    entry.expiration, entry.duration = now + seconds, weaponEnchantDurations[key]
                end
                list[#list + 1] = entry
            end
        end
    end
    return list, unreadable
end

--- Arme principale enchantée (poison, arme de chaman…). nil si le client ne sait pas répondre.
function NS.HasMainHandEnchant()
    if not (C_Item and C_Item.GetWeaponEnchantInfo) then return nil end
    local list, unreadable = NS.GetWeaponEnchants()
    for _, entry in ipairs(list) do
        if entry.slot == WEAPON_INVENTORY_SLOTS[1] then return true end
    end
    if unreadable then return nil end
    return false
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

--- Sac du trousseau (Forever : Enum.BagIndex.Keyring, -1) ; nil si le client n'en montre pas.
function NS.GetKeyringBag()
    local shouldShow = _G.C_ActionBar and C_ActionBar.ShouldShowKeyring
    if not (shouldShow and shouldShow()) then return nil end
    return _G.Enum and Enum.BagIndex and Enum.BagIndex.Keyring or nil
end

--- Places libres d'un sac. generalOnly : 0 pour un sac spécial (carquois, sac d'âme, d'herbes…),
-- qui n'accepte que certains objets.
function NS.GetBagFreeSlots(bag, generalOnly)
    local fn = Container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots
    if not fn then return 0 end
    local free, bagType = fn(bag)
    if generalOnly and bagType and bagType ~= 0 then return 0 end
    return free or 0
end

--- Sac général (type 0) ? Faux pour un sac spécial.
function NS.IsGeneralBag(bag)
    if bag == NS.GetKeyringBag() then return false end   -- les clés ne comptent pas dans les places libres
    local fn = Container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots
    if not fn then return true end
    local _, bagType = fn(bag)
    return not bagType or bagType == 0
end

--- { itemID, quality, stackCount, hasNoValue, isLocked, link, icon, isBound, hasLoot } ou nil pour une case vide.
function NS.GetBagItem(bag, slot)
    if Container.GetContainerItemInfo then
        local info = Container.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        return {
            itemID = info.itemID, quality = info.quality, stackCount = info.stackCount or 1,
            hasNoValue = info.hasNoValue, isLocked = info.isLocked, link = info.hyperlink,
            icon = info.iconFileID, isBound = info.isBound, hasLoot = info.hasLoot,
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

--------------------------------------------------------------------------------
-- Banque
--------------------------------------------------------------------------------

local function BankAPI() return _G.C_Bank or {} end

--- Onglets achetés d'un type de banque, consultable et sans verrou : { { bag, name } }, sac lu
-- dans l'ID de l'onglet (jamais par position). Liste vide sans l'API ou banque fermée au joueur.
function NS.GetBankTabs(bankType)
    local Bank = BankAPI()
    local tabs = {}
    if bankType == nil or not Bank.FetchPurchasedBankTabData then return tabs end
    if Bank.CanViewBank and not Bank.CanViewBank(bankType) then return tabs end
    if Bank.FetchBankLockedReason and Bank.FetchBankLockedReason(bankType) ~= nil then return tabs end
    for _, data in ipairs(Bank.FetchPurchasedBankTabData(bankType) or {}) do
        if data.ID then tabs[#tabs + 1] = { bag = data.ID, name = data.name } end
    end
    return tabs
end

--- Emplacements-sacs des onglets de banque Forever (BankItemButtonBagTemplate, Camelot/BankFrame.lua) :
-- { { slot, bag, purchased } }. Le sac posé dans l'onglet `slot` (2 et suivants, le premier n'en porte
-- pas) vit dans un pseudo-sac (Characterbanktab / Accountbanktab) ; `purchased` : onglet acheté.
function NS.GetBankBagSlots(bankType)
    local Bank = BankAPI()
    local index = _G.Enum and Enum.BagIndex
    local types = _G.Enum and Enum.BankType
    local slots = {}
    if not (index and types and Bank.FetchMaxNumBankTabs and Bank.FetchPurchasedBankTabData) then return slots end
    local bag = (bankType == types.Character and index.Characterbanktab) or (bankType == types.Account and index.Accountbanktab)
    if not bag then return slots end
    local purchased = Bank.FetchPurchasedBankTabData(bankType) or {}
    for slot = 2, Bank.FetchMaxNumBankTabs(bankType) or 0 do
        -- Pseudo-sac : Blizzard lit le sac posé par ItemLocation, pas par GetContainerItemInfo.
        local icon
        if _G.ItemLocation and _G.C_Item and C_Item.DoesItemExist and C_Item.GetItemIcon then
            local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
            if C_Item.DoesItemExist(location) then icon = C_Item.GetItemIcon(location) end
        end
        slots[#slots + 1] = { slot = slot, bag = bag, purchased = purchased[slot] ~= nil, icon = icon }
    end
    return slots
end

--- Dépôt automatique possible pour ce type de banque ?
function NS.BankSupportsAutoDeposit(bankType)
    local Bank = BankAPI()
    if not Bank.AutoDepositItemsIntoBank then return false end
    if Bank.DoesBankTypeSupportAutoDeposit then return Bank.DoesBankTypeSupportAutoDeposit(bankType) == true end
    return bankType == (_G.Enum and Enum.BankType and Enum.BankType.Character)
end

function NS.BankAutoDeposit(bankType)
    local Bank = BankAPI()
    if Bank.AutoDepositItemsIntoBank then Bank.AutoDepositItemsIntoBank(bankType) end
end

--- Or déposé dans ce type de banque, nil s'il n'accepte pas l'argent.
function NS.GetBankMoney(bankType)
    local Bank = BankAPI()
    if not (Bank.DoesBankTypeSupportMoneyTransfer and Bank.FetchDepositedMoney) then return nil end
    if not Bank.DoesBankTypeSupportMoneyTransfer(bankType) then return nil end
    return Bank.FetchDepositedMoney(bankType)
end

--- Range un type de banque (tri du client). Faux sans l'API.
function NS.SortBank(bankType)
    if not Container.SortBank then return false end
    Container.SortBank(bankType)
    return true
end

--- Tri des sacs « vers le bas » (objets rangés de la fin vers le début). nil sans l'API.
function NS.GetSortToBottom()
    if not Container.GetSortBagsRightToLeft then return nil end
    return Container.GetSortBagsRightToLeft() == true
end

function NS.SetSortToBottom(enabled)
    if not Container.SetSortBagsRightToLeft then return false end
    Container.SetSortBagsRightToLeft(enabled and true or false)
    return true
end

--- Achat d'un onglet possible pour ce type ? Règle de la BankFrame Camelot : le premier onglet
-- de bataillon ne s'achète pas au guichet du personnage.
function NS.CanPurchaseBankTab(bankType)
    local Bank = BankAPI()
    if not (Bank.CanPurchaseBankTab and Bank.FetchNumPurchasedBankTabs) then return false end
    if bankType == Enum.BankType.Account and Bank.FetchNumPurchasedBankTabs(bankType) == 0 then return false end
    return Bank.CanPurchaseBankTab(bankType) == true
end

--- Bouton d'achat d'onglet : modèle prévu par Blizzard pour les addons (type lu dans l'attribut
-- overrideBankType, popup ouverte sans taint, C_Bank.PurchaseBankTab étant restreint). Sans le
-- modèle, popup ouverte par l'addon.
function NS.CreateBankPurchaseButton(parent)
    if _G.BankPanelPurchaseTabButtonMixin then
        return CreateFrame("Button", nil, parent, "BankPanelPurchaseButtonScriptTemplate")
    end
    local button = CreateFrame("Button", nil, parent)
    button:SetScript("OnClick", function(self)
        if _G.StaticPopupDialogs and StaticPopupDialogs.CONFIRM_BUY_BANK_TAB then
            StaticPopup_Show("CONFIRM_BUY_BANK_TAB", nil, nil, { bankType = self:GetAttribute("overrideBankType") })
        end
    end)
    return button
end

function NS.CloseBank()
    local Bank = BankAPI()
    if Bank.CloseBankFrame then Bank.CloseBankFrame() elseif _G.CloseBankFrame then CloseBankFrame() end
end

--- Guichet ouvert sur un banquier de bataillon (banque portable) : seuls les onglets de compte.
function NS.IsAccountBanker()
    local manager = _G.C_PlayerInteractionManager
    local kind = _G.Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.AccountBanker
    return kind ~= nil and manager ~= nil and manager.IsInteractingWithNpcOfType ~= nil
        and manager.IsInteractingWithNpcOfType(kind) == true
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

--- Type de liaison (Enum.ItemBind : 1 à la prise, 2 à l'équipement, 9 au compte jusqu'à
-- l'équipement), ou nil tant que le client ne connaît pas l'objet.
function NS.GetItemBindType(item)
    local fn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if not fn or not item then return nil end
    return select(14, fn(item))
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

--- Niveau d'objet moyen : total (sacs compris), équipé. nil si le client ne les donne pas.
function NS.GetAverageItemLevels()
    if not _G.GetAverageItemLevel then return nil end
    local total, equipped = GetAverageItemLevel()
    return total, equipped
end

--- Volume principal (0 à 1), nil si la CVar manque.
function NS.GetMasterVolume()
    return tonumber(NS.CVars:Get("Sound_MasterVolume"))
end

--- Pose le volume principal, sans mémoire d'origine : c'est le choix de l'utilisateur.
function NS.SetMasterVolume(volume)
    if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar("Sound_MasterVolume", volume)
    elseif _G.SetCVar then SetCVar("Sound_MasterVolume", volume) end
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

--- `unit` désigne-t-il le focus ? nil quand la réponse est secrète.
function NS.IsFocus(unit)
    if not unit or not _G.UnitIsUnit then return false end
    local same = UnitIsUnit(unit, "focus")
    if isSecret(same) then return nil end
    return same and true or false
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

--- Enregistre la page d'Options > AddOns (un bouton vers la fenêtre MuscaUI). Retourne la catégorie.
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

--- Fenêtre d'options MuscaUI (Config/Options.lua), sur `page` si donnée.
function NS.OpenOptions(page)
    if NS.Options then NS.Options:Open(page) end
end

--------------------------------------------------------------------------------
-- Dispositions : Edit Mode et Cooldown Manager
--------------------------------------------------------------------------------
-- Les API existent sur Forever (/musca diag) mais leurs signatures ne sont pas toutes
-- vérifiées en jeu : tout est en pcall. Chaque import touche des cadres sécurisés :
-- l'appelant passe par NS:RunOutOfCombat.

--- Dispositions livrées par MuscaUI : chaînes exportées depuis le jeu.
-- editMode : export Edit Mode capturé sur Forever 1.60.1 (build 69913) le 2026-09-20, format v3,
-- 59 systèmes. Point de départ proche du modèle Blizzard « Moderne » : la disposition MuscaUI
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
        -- La disposition « AeonUI » (ancien nom de l'addon) est remplacée par « MuscaUI ».
        local old = list[i].layoutName
        if old == name or (name == "MuscaUI" and old == "AeonUI") then tremove(list, i) end
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
-- sondées par /musca diag avant d'être branchées ici.

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

--- Comme FormatMoney, mais en icônes de pièces quand le client sait les écrire (repli : lettres colorées).
function NS.FormatMoneyIcons(copper)
    local getCoinTexture = _G.C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
    if getCoinTexture then
        local ok, text = pcall(getCoinTexture, math.floor(tonumber(copper) or 0))
        if ok and text then return text end
    end
    return NS.FormatMoney(copper)
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
        hiddenParent = CreateFrame("Frame", "MuscaUI_Hidden", UIParent)
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

--- Tri du moteur : `sort` = "expiration" (la plus courte d'abord), "expirationLongest" (la plus longue), "name", sinon priorité des débuffs
-- (boss, dissipables) si `prioritize`, sinon l'ordre du jeu.
local function AuraSort(sort, prioritize)
    local methods, directions = _G.AuraContainerSortMethod, _G.AuraContainerSortDirection
    if not (methods and directions) then return nil, nil end
    if sort == "expiration" then return methods.Expiration, directions.Normal end
    if sort == "expirationLongest" then return methods.Expiration, directions.Reverse end
    if sort == "name" then return methods.Name, directions.Normal end
    return prioritize and methods.UnitFrameDebuff or methods.Default, directions.Normal
end

--- Filtre du moteur pour un mode d'MuscaUI (NS.AURA_FILTERS). « important » (boss ou dissipable)
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
-- montrée aussi sans type (couleur « aucun »). `stealable` : à l'inverse, buffs volables seulement
-- (filtre du moteur, qui lit lui-même le drapeau de l'aura). false si le client n'offre pas ce style.
function NS.AddDispelTexture(button, texture, always, stealable)
    local styles = _G.Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    local filters = _G.Enum and Enum.CustomAuraButtonDispelTypeStealableFilter
    if not always then
        texture:SetColorTexture(1, 1, 1, 1)
        texture:Hide()   -- écrit avant l'enregistrement : ensuite, l'alpha et l'affichage sont au moteur
    end
    if not (styles and styles.PreserveAsset) then return false end
    local options = { style = styles.PreserveAsset, showWhenHarmful = true, showWhenHelpful = false,
                      showWithoutDispelType = always == true }
    if stealable then
        if not filters then return false end
        options.showWhenHarmful, options.showWhenHelpful, options.showWithoutDispelType = false, true, true
        options.stealableFilter = filters.Stealable
    end
    return (pcall(button.AddDispelTypeTexture, button, texture, options))
end

--- Quatre bords d'épaisseur `px` autour de `host` (écartés de `inset`), teintés comme ci-dessus.
-- `host` descend de `button`. Rend les quatre bords (haut, bas, gauche, droite), pour les réépaissir.
function NS.AddDispelEdges(button, host, px, inset, stealable)
    local o = inset or 0
    local edges = {}
    for _, side in ipairs(DISPEL_EDGES) do
        local edge = host:CreateTexture(nil, "OVERLAY", nil, 1)
        edges[#edges + 1] = edge
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
        NS.AddDispelTexture(button, edge, nil, stealable)
    end
    return edges
end

local auraHolders = setmetatable({}, { __mode = "k" })   -- bouton du moteur -> holder de InitAuraButton

--- Réglages d'un bouton préparé par InitAuraButton avec `opts.style` : texte des piles (taille,
-- coin, affichage), texte de durée (« swipe » : chiffres du balayage, « text » : texte propre posé
-- dans un coin, « none »), lueur des buffs volables. Ne lit aucune valeur d'aura.
-- style : { count, countSize, countPoint, countOffsetX/Y, duration, durationSize, durationPoint,
-- durationOffsetX/Y, stealable, cancel, border, borderSize }.
-- `border` false : ni bordure du thème ni bordure de dissipation ; `borderSize` (px, > 0) : épaisseur de
-- la bordure de dissipation (nil : celle du thème). Sans ces champs, rendu inchangé.
-- `cancel` (true, false ou nil pour ne pas y toucher) : clic droit pour annuler l'aura (buffs du joueur).
function NS.StyleAuraHolder(holder, style)
    if not (holder and holder.top and style) then return end
    local count, top = holder.count, holder.top
    NS.Media:SetTextSizeDelta(count, style.countSize or -2)
    local point = style.countPoint or "BOTTOMRIGHT"
    count:ClearAllPoints()
    count:SetPoint(point, top, point, style.countOffsetX or 0, style.countOffsetY or 0)
    count:SetAlpha(style.count == false and 0 or 1)
    local mode = style.duration or "swipe"
    local cooldown, text = holder.cooldown, holder.durationText
    cooldown.foreverHideNumbers = mode ~= "swipe" or nil
    if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(mode ~= "swipe") end
    if text then
        text:SetShown(mode == "text")
        NS.Media:SetTextSizeDelta(text, style.durationSize or -1)
        local textPoint = style.durationPoint or "CENTER"
        text:ClearAllPoints()
        text:SetPoint(textPoint, top, textPoint, style.durationOffsetX or 0, style.durationOffsetY or 0)
    end
    if holder.stealHost then holder.stealHost:SetShown(style.stealable == true) end
    local bordered = style.border ~= false
    for _, edge in pairs(holder.borderEdges or {}) do edge:SetShown(bordered) end
    if holder.dispelHost then holder.dispelHost:SetShown(bordered) end   -- cadre à part : masqué sans toucher aux bords du moteur
    if holder.dispelEdges then
        -- Le moteur garde l'affichage et la couleur de ces bords : on n'en change que l'épaisseur.
        local thickness = tonumber(style.borderSize) or 0
        local px = NS.Pixel:Scale(thickness > 0 and thickness or (NS.db and NS.db.theme.borderSize or 1))
        for index, edge in ipairs(holder.dispelEdges) do
            if index <= 2 then edge:SetHeight(px) else edge:SetWidth(px) end
        end
    end
    if style.cancel ~= nil and holder.button then
        -- Clic droit : le moteur annule lui-même l'aura (code Blizzard, rien de protégé côté addon).
        -- Clics coupés en combat ; sinon les clics vont au cadre dessous.
        local active = style.cancel == true
        pcall(holder.button.SetCancelAuraButtons, holder.button, active and "RightButtonUp" or nil)
        pcall(holder.button.SetMouseClickEnabled, holder.button, active and not NS.InCombat())
    end
end

--- Réapplique `style` au bouton du moteur `button` (sans effet s'il n'a pas été préparé avec un style).
function NS.StyleAuraButton(button, style)
    NS.StyleAuraHolder(auraHolders[button], style)
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
    local borderEdges = NS.Media:CreateBorder(top)
    local count = NS.Media:CreateText(top, "OVERLAY", -2, "OUTLINE")   -- police posée avant l'enregistrement
    count:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
    pcall(button.SetIcon, button, icon)
    pcall(button.SetDurationCooldown, button, cooldown)
    pcall(button.SetApplicationCount, button, count)
    holder.top, holder.cooldown, holder.count, holder.button, holder.icon = top, cooldown, count, button, icon
    holder.borderEdges = borderEdges
    if opts.durationText or opts.style then
        -- Avec un style, le texte existe toujours : le moteur le tient, le réglage le montre ou non.
        local text = NS.Media:CreateText(top, "OVERLAY", 0, "OUTLINE")
        text:SetPoint("TOP", top, "BOTTOM", 0, -2)
        pcall(button.SetDurationText, button, text, {})
        holder.durationText = text
        if opts.style then text:Hide() end
    end
    if opts.dispel then
        holder.dispelHost = CreateFrame("Frame", nil, top)
        holder.dispelHost:SetAllPoints(top)
        holder.dispelEdges = NS.AddDispelEdges(button, holder.dispelHost, NS.Pixel:Scale(NS.db and NS.db.theme.borderSize or 1))
    end
    if opts.style then
        -- Lueur des buffs volables : cadre à part, que le réglage montre ou cache.
        local steal = CreateFrame("Frame", nil, top)
        steal:SetAllPoints(top)
        steal:Hide()
        NS.AddDispelEdges(button, steal, NS.Pixel:Scale(2), NS.Pixel:Scale(2), true)
        holder.stealHost = steal
    end
    if opts.highlight then
        local ring = CreateFrame("Frame", nil, top)   -- un cadre par bordure : le thème les repeint chacune
        ring:SetAllPoints(top)
        NS.Media:CreateBorder(ring, opts.highlight, 1)
    end
    auraHolders[button] = holder
    NS.StyleAuraHolder(holder, opts.style)
    return holder
end

--------------------------------------------------------------------------------
-- Diagnostic (/musca diag)
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
-- Courbe déjà résolue pour une table de paliers (Elements.Bands en refait une à chaque réglage).
local curveBySteps = setmetatable({}, { __mode = "k" })

function NS.StepColor(unit, kind, steps, r, g, b)
    if #steps == 0 or isSecret(r) or isSecret(g) or isSecret(b) then return false end
    local resolved = curveBySteps[steps]
    if not (resolved and resolved.kind == kind and resolved.r == r and resolved.g == g and resolved.b == b) then
        local parts = { kind, r, g, b }
        for _, step in ipairs(steps) do parts[#parts + 1] = table.concat(step, ",") end
        resolved = { kind = kind, r = r, g = g, b = b, curve = StepCurve(table.concat(parts, ";"), steps, r, g, b) }
        curveBySteps[steps] = resolved
    end
    local curve = resolved.curve
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

local function HealAmount(value) if isSecret(value) then return value end return value or 0 end

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
    return HealAmount((calc:GetIncomingHeals())), HealAmount((calc:GetDamageAbsorbs())), HealAmount((calc:GetHealAbsorbs()))
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
-- Chaque recharge MuscaUI s'enregistre ici. Avec un réglage actif (posé par le module
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
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(cooldown.foreverHideNumbers == true) end
        cooldown.foreverStyled = true
    elseif cooldown.foreverStyled then
        pcall(cooldown.SetCountdownFormatter, cooldown, nil)
        -- Valeur par défaut du modèle : la CVar countdownForCooldowns décide ensuite.
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(cooldown.foreverHideNumbers == true) end
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

--- Présence des API Midnight utilisées ci-dessus (ligne de /musca diag).
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

--- Charge d'MuscaUI : temps moyen récent par image en ms (profileur d'addons du moteur récent,
-- nil sans lui) et mémoire en Ko (nil si le client ne la donne pas). Relevé à la demande.
function NS.AddOnUsage()
    local cpu, memory
    local profiler, metrics = _G.C_AddOnProfiler, _G.Enum and Enum.AddOnProfilerMetric
    if profiler and profiler.GetAddOnMetric and metrics and metrics.RecentAverageTime then
        local ok, value = pcall(profiler.GetAddOnMetric, "MuscaUI", metrics.RecentAverageTime)
        if ok and type(value) == "number" and not NS.IsSecret(value) then cpu = value end
    end
    if _G.UpdateAddOnMemoryUsage and _G.GetAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
        local ok, value = pcall(GetAddOnMemoryUsage, "MuscaUI")
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

--- Action Blizzard liée à la touche `key` (« ALT-F »), nil si la touche est libre.
function NS.KeyBindingAction(key)
    local action = _G.GetBindingAction and GetBindingAction(key)
    if type(action) == "string" and action ~= "" then return action end
    return nil
end

--- Vrai si le joueur a une macro de ce nom ; vrai aussi sans API (aucun avertissement à tort).
function NS.MacroExists(name)
    if not _G.GetMacroInfo then return true end
    return GetMacroInfo(name) ~= nil
end

--- Vrai si le client connaît l'objet (nom d'un objet porté ou `item:ID`) ; vrai aussi sans API.
function NS.ItemKnown(item)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if not instant then return true end
    return instant(item) ~= nil
end

--- Emplacement d'équipement ("INVTYPE_…", "" si inconnu), classe et sous-classe d'un objet (lien, nom ou ID).
function NS.GetItemEquipInfo(item)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if not instant then return "" end
    local _, _, _, equipLoc, _, classID, subclassID = instant(item)
    return type(equipLoc) == "string" and equipLoc or "", classID, subclassID
end

--------------------------------------------------------------------------------
-- Rangs de sorts sur les barres d'action
--------------------------------------------------------------------------------

-- Emplacements d'action : 15 pages (barre principale et multibarres) de NUM_ACTIONBAR_BUTTONS.
-- Le client n'a pas de constante du total.
NS.NUM_ACTION_SLOTS = 15 * (_G.NUM_ACTIONBAR_BUTTONS or 12)

--- Sort posé à l'emplacement `slot` : spellID lisible, nil sinon (vide, macro, objet, secret).
function NS.GetActionSpellID(slot)
    if not _G.GetActionInfo then return nil end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok or isSecret(kind) or isSecret(id) or kind ~= "spell" or type(id) ~= "number" then return nil end
    return id
end

--- Nom du sort, nil s'il est illisible.
function NS.GetPlainSpellName(id)
    local name = NS.GetSpellName(id)
    if name == nil or isSecret(name) then return nil end
    return name
end

--- Rang affiché du sort (« Rang 4 »), nil s'il n'en a pas ou s'il est illisible.
function NS.GetSpellRankText(id)
    local api = C_Spell and C_Spell.GetSpellSubtext
    local text = api and api(id)
    if text == nil or isSecret(text) or type(text) ~= "string" or text == "" then return nil end
    return text
end

--- Sort du grimoire actif du joueur et à son plus haut rang ? false sans l'API.
function NS.IsTopRankSpellbookSpell(id)
    local book = _G.C_SpellBook
    if not (book and book.FindSpellBookSlotForSpell and book.IsSpellBookItemLowRank) then return false end
    local ok, slot, bank = pcall(book.FindSpellBookSlotForSpell, id, false, false, false, false)
    if not ok or slot == nil or isSecret(slot) or isSecret(bank) then return false end
    local player = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    if bank ~= player then return false end
    local okRank, low = pcall(book.IsSpellBookItemLowRank, slot, bank)
    return okRank and not isSecret(low) and not low
end

--- Curseur vide (ni objet, ni sort, ni argent) ? false sans l'API.
function NS.CursorEmpty()
    if not _G.GetCursorInfo then return false end
    return GetCursorInfo() == nil
end

--- Pose `spellID` à l'emplacement `slot` ; le sort remplacé, rendu au curseur, est lâché.
-- Hors combat seulement. false sans l'API.
function NS.PlaceSpellInActionSlot(spellID, slot)
    local pickup = C_Spell and C_Spell.PickupSpell
    if not (pickup and _G.PlaceAction and _G.ClearCursor) or InCombatLockdown() then return false end
    pickup(spellID)
    PlaceAction(slot)
    ClearCursor()
    return true
end

--------------------------------------------------------------------------------
-- Vols (maître de vol)
--------------------------------------------------------------------------------

--- Le joueur est-il en vol de maître de vol ? false sans l'API.
function NS.OnTaxi()
    if not _G.UnitOnTaxi then return false end
    local on = UnitOnTaxi("player")
    return not isSecret(on) and on == true
end

--- Heure du serveur en secondes, nil sans l'API.
function NS.ServerTime()
    local now = _G.GetServerTime and GetServerTime()
    if type(now) ~= "number" or isSecret(now) then return nil end
    return now
end

--- Nœuds de la carte de vol ouverte : { [slotIndex] = { nodeID, name, current } }, vide sans API.
function NS.GetTaxiNodes()
    local nodes = {}
    local api = C_TaxiMap and C_TaxiMap.GetAllTaxiNodes
    local map = _G.GetTaxiMapID and GetTaxiMapID()
    if not (api and map) or isSecret(map) then return nodes end
    local ok, list = pcall(api, map)
    local current = Enum and Enum.FlightPathState and Enum.FlightPathState.Current or 0
    for _, info in ipairs(ok and type(list) == "table" and list or {}) do
        local slot, node, state = info.slotIndex, info.nodeID, info.state
        if slot and node and not (isSecret(slot) or isSecret(node) or isSecret(state)) then
            local name = info.name
            nodes[slot] = { nodeID = node, name = not isSecret(name) and name or nil, current = state == current }
        end
    end
    return nodes
end

--- Accroche le départ (`onTake(slotIndex)`) et la demande d'atterrissage anticipé (`onEarlyLanding()`).
-- Une seule fois par session : hooksecurefunc ne se retire pas.
function NS.HookTaxi(onTake, onEarlyLanding)
    if _G.TakeTaxiNode then hooksecurefunc("TakeTaxiNode", onTake) end
    if _G.TaxiRequestEarlyLanding then hooksecurefunc("TaxiRequestEarlyLanding", onEarlyLanding) end
end

--------------------------------------------------------------------------------
-- Statistiques du personnage
--------------------------------------------------------------------------------

local STAT_SIDE_BY_CLASS = { WARRIOR = "melee", ROGUE = "melee", HUNTER = "ranged",
                             MAGE = "spell", PRIEST = "spell", WARLOCK = "spell" }
local DRUID_MELEE_FORMS = { [1] = true, [5] = true, [8] = true }   -- félin, ours, ours redoutable

--- Côté qui compte pour le joueur : "melee", "ranged" ou "spell", d'après la classe, le rôle
-- choisi et, pour le druide, la forme. Arguments facultatifs (tests) : sinon lus sur le joueur.
function NS.GetStatSide(class, role, formID)
    if not class then
        local _, token = UnitClass("player")
        class = not isSecret(token) and token or nil
    end
    if STAT_SIDE_BY_CLASS[class] then return STAT_SIDE_BY_CLASS[class] end
    if not role then
        local assigned = _G.UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
        role = not isSecret(assigned) and assigned or "NONE"
        if role == "NONE" and NS.IsTankUnit("player") then role = "TANK" end
    end
    if role == "HEALER" then return "spell" end
    if class == "DRUID" then
        formID = formID or (_G.GetShapeshiftFormID and GetShapeshiftFormID())
        return not isSecret(formID) and DRUID_MELEE_FORMS[formID] and "melee" or "spell"
    end
    if class == "SHAMAN" and role ~= "TANK" and role ~= "DAMAGER" then return "spell" end
    return "melee"
end

-- Lit `fn(...)` sous pcall : premier retour lisible, nil sinon.
local function PlainStat(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or value == nil or isSecret(value) or type(value) ~= "number" then return nil end
    return value
end

-- Meilleure valeur de `fn(school)` sur les écoles de magie 2 à 7 ; nil si l'une est illisible.
local function BestSchool(fn)
    local best
    for school = 2, 7 do
        local value = PlainStat(fn, school)
        if value == nil then return nil end
        if not best or value > best then best = value end
    end
    return best
end

-- Soigneur (rôle choisi) : bonus de soins ; sinon meilleur bonus de dégâts des écoles 2 à 7.
local function SpellPower()
    local role = _G.UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if not isSecret(role) and role == "HEALER" then return PlainStat(_G.GetSpellBonusHealing) end
    return BestSchool(_G.GetSpellBonusDamage)
end

local function AttackPower(ranged)
    local fn = ranged and _G.UnitRangedAttackPower or _G.UnitAttackPower
    if not fn then return nil end
    local ok, base, pos, neg = pcall(fn, "player")
    if not ok or isSecret(base) or isSecret(pos) or isSecret(neg) or type(base) ~= "number" then return nil end
    return base + (pos or 0) + (neg or 0)
end

local STAT_READERS = {
    crit = {
        melee = function() return PlainStat(_G.GetCritChance) end,
        ranged = function() return PlainStat(_G.GetRangedCritChance) end,
        spell = function() return BestSchool(_G.GetSpellCritChance) end,
    },
    haste = {
        melee = function() return PlainStat(_G.GetMeleeHaste) end,
        ranged = function() return PlainStat(_G.GetRangedHaste) end,
        spell = function() return PlainStat(_G.UnitSpellHaste, "player") end,
    },
    hit = {
        melee = function() return PlainStat(_G.GetHitModifier) end,
        ranged = function() return PlainStat(_G.GetHitModifier) end,
        spell = function() return PlainStat(_G.GetSpellHitModifier) end,
    },
    power = {
        melee = function() return AttackPower(false) end,
        ranged = function() return AttackPower(true) end,
        spell = SpellPower,
    },
}

--- Valeur de la statistique `key` du côté `side` (défaut : NS.GetStatSide()), nil si secrète ou
-- sans l'API. `avoidance` rend esquive, parade, blocage ; `armor` l'armure effective.
function NS.GetStat(key, side)
    if key == "armor" then
        if not _G.UnitArmor then return nil end
        local ok, _, effective = pcall(UnitArmor, "player")
        if not ok or isSecret(effective) or type(effective) ~= "number" then return nil end
        return effective
    end
    if key == "avoidance" then
        local dodge, parry, block = PlainStat(_G.GetDodgeChance), PlainStat(_G.GetParryChance),
            PlainStat(_G.GetBlockChance)
        if not (dodge and parry and block) then return nil end
        return dodge, parry, block
    end
    local readers = STAT_READERS[key]
    if not readers then return nil end
    return readers[side or NS.GetStatSide()]()
end

--------------------------------------------------------------------------------
-- Butin : analyse des lignes du chat
--------------------------------------------------------------------------------

local function EscapePattern(text) return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

--- Phrase de format du client (« Butin : %s.», « %2$s … %1$d ») en motif Lua ancré, et ordre des
-- arguments de chaque capture.
local function FormatToPattern(format)
    local parts, order, pos, auto = { "^" }, {}, 1, 0
    while true do
        local first, last, index, kind = format:find("%%(%d*)%$?[%.%d]*([sdf])", pos)
        if not first then break end
        parts[#parts + 1] = EscapePattern(format:sub(pos, first - 1))
        auto = auto + 1
        order[#order + 1] = tonumber(index) or auto
        parts[#parts + 1] = kind == "d" and "(%d+)" or kind == "f" and "([%d%.,]+)" or "(.-)"
        pos = last + 1
    end
    parts[#parts + 1] = EscapePattern(format:sub(pos)) .. "$"
    return table.concat(parts), order
end
NS.FormatToPattern = FormatToPattern

-- Arguments de `text` selon `format`, rangés dans l'ordre du format d'origine ; nil si pas de correspondance.
local function MatchFormat(text, format)
    if type(format) ~= "string" then return nil end
    local pattern, order = FormatToPattern(format)
    local captures = { text:match(pattern) }
    if #captures == 0 then return nil end
    local args = {}
    for i, index in ipairs(order) do args[index] = captures[i] end
    return args
end

--- Somme en cuivre d'un texte d'argent du client (« 1 Or, 2 Argent, 3 Cuivre »), nil si illisible.
local function ParseMoney(text)
    local total, found = 0, false
    for _, coin in ipairs({ { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }) do
        local format = _G[coin[1]]
        if type(format) == "string" then
            local pattern = FormatToPattern(format)
            local amount = text:match((pattern:sub(2, -2)))   -- sans les ancres ^ et $
            if amount then total, found = total + tonumber(amount) * coin[2], true end
        end
    end
    return found and total or nil
end

local ITEM_FORMATS = {   -- versions « multiple » d'abord : la simple avalerait « x5 »
    "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
    "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_CREATED_SELF",
}
local MONEY_FORMATS = { "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT" }
-- Gain de réputation, variantes avec bonus d'abord ; globales absentes ignorées par MatchFormat.
local FACTION_FORMATS = { "FACTION_STANDING_INCREASED_DOUBLE_BONUS", "FACTION_STANDING_INCREASED_ACH_BONUS",
                          "FACTION_STANDING_INCREASED_BONUS", "FACTION_STANDING_INCREASED_ACCOUNT_WIDE",
                          "FACTION_STANDING_INCREASED" }

--- Ligne de butin du joueur : { kind = "item", link, itemID, quantity }, { kind = "money", copper }
-- ou { kind = "faction", name, quantity } ; nil si le texte est secret, d'un autre joueur ou inconnu.
function NS.ParseLootLine(text)
    if text == nil or isSecret(text) or type(text) ~= "string" then return nil end
    for _, global in ipairs(ITEM_FORMATS) do
        local args = MatchFormat(text, _G[global])
        if args then
            local link = args[1]
            local itemID = tonumber(link:match("item:(%d+)"))
            return { kind = "item", link = link, itemID = itemID, quantity = tonumber(args[2]) or 1 }
        end
    end
    for _, global in ipairs(MONEY_FORMATS) do
        local args = MatchFormat(text, _G[global])
        local copper = args and ParseMoney(args[1])
        if copper then return { kind = "money", copper = copper } end
    end
    for _, global in ipairs(FACTION_FORMATS) do
        local args = MatchFormat(text, _G[global])
        if args then return { kind = "faction", name = args[1], quantity = tonumber(args[2]) or 0 } end
    end
    return nil
end

--- Nom et icône d'une monnaie, nil si illisibles.
function NS.GetCurrencyDisplay(currencyType)
    local api = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
    if not api or currencyType == nil or isSecret(currencyType) then return nil end
    local ok, info = pcall(api, currencyType)
    if not ok or type(info) ~= "table" or isSecret(info.name) then return nil end
    return info.name, info.iconFileID
end

--- Icône d'un objet par son ID, nil tant que le client ne la connaît pas.
function NS.GetItemIcon(itemID)
    local api = C_Item and C_Item.GetItemIconByID
    return api and itemID and api(itemID) or nil
end

--------------------------------------------------------------------------------
-- Sacs : objets à ne jamais vendre
--------------------------------------------------------------------------------

--- L'objet de la case appartient-il à un ensemble d'équipement ? false sans l'API.
function NS.IsBagItemInEquipmentSet(bag, slot)
    local api = Container.GetContainerItemEquipmentSetInfo
    if not api then return false end
    local ok, inSet = pcall(api, bag, slot)
    return ok and not isSecret(inSet) and inSet == true
end

--- L'objet de la case est-il encore remboursable chez le marchand ? false sans l'API.
function NS.IsBagItemRefundable(bag, slot)
    local api = Container.GetContainerItemPurchaseInfo
    if not api then return false end
    local ok, info = pcall(api, bag, slot, false)
    local seconds = ok and type(info) == "table" and info.refundSeconds or nil
    return seconds ~= nil and not isSecret(seconds) and type(seconds) == "number" and seconds > 0
end

--------------------------------------------------------------------------------
-- Manette
--------------------------------------------------------------------------------

--- Mode manette actif (C_GamePad.IsEnabled, lu par l'interface Blizzard) ; false sans l'API.
function NS.GamepadActive()
    local pad = _G.C_GamePad
    if not (pad and pad.IsEnabled) then return false end
    local ok, enabled = pcall(pad.IsEnabled)
    if not (ok and enabled == true) then return false end
    local using = _G.IsUsingGamepad
    if not using then return true end
    local okUsing, active = pcall(using)
    return okUsing and active == true
end
