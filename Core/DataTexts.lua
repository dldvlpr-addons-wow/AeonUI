-- Core/DataTexts.lua
-- Registre des textes d'information (data texts) partagés par la barre du haut et les panneaux
-- de données. Un data text :
--   text()            -> chaîne, ou (motif, valeurs...) passés à SetFormattedText (valeurs secrètes)
--   tooltip(tt)       -> remplit GameTooltip (facultatif)
--   click(button, mouseButton)                  (facultatif)
--   events            -> événements qui rafraîchissent le texte (facultatif)
--   interval          -> secondes entre deux rafraîchissements par minuterie (facultatif)
--   secret            -> le texte peut être secret : largeur inconnue, exclu des emplacements
--                        qui se dimensionnent au texte (barre du haut)
-- Les textes de la barre du haut (amis, guilde, heure, or…) sont inscrits par Modules/TopBar.lua.
local _, NS = ...
local L = NS.L

local DataTexts = { registry = {} }
NS.DataTexts = DataTexts

function DataTexts:Register(key, def)
    def.key = key
    self.registry[key] = def
end

function DataTexts:Get(key) return self.registry[key] end

--- Choix pour un o:Dropdown : « aucun » puis les data texts par nom. `sizedSlot` écarte les secrets.
function DataTexts:Choices(sizedSlot)
    local list = {}
    for key, def in pairs(self.registry) do
        if not (sizedSlot and def.secret) then
            list[#list + 1] = { name = L["DATATEXT_" .. key:upper()] or key, value = key }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    table.insert(list, 1, { name = L.DATATEXT_NONE, value = "none" })
    return list
end

local function Render(fontString, ok, first, ...)
    if not ok then fontString:SetText("") return end
    if select("#", ...) == 0 then fontString:SetText(first or "") return end
    fontString:SetFormattedText(first, ...)   -- valeurs peut-être secrètes : jamais lues ici
end

--- Pose le texte d'un data text sur un FontString (chaîne simple ou motif et valeurs).
function DataTexts.Render(def, fontString)
    Render(fontString, pcall(def.text))
end

local function Dim(text) return "|cff9d9d9d" .. text .. "|r" end
local isSecret = NS.IsSecret

local function Known(value)
    if isSecret(value) or value == nil then return nil end
    return value
end

--------------------------------------------------------------------------------
-- Coordonnées
--------------------------------------------------------------------------------

--- Position du joueur en pourcentage de la carte, ou nil (instance, API absente, secret).
function DataTexts.PlayerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local map = Known(C_Map.GetBestMapForUnit("player"))
    if not map then return nil end
    local position = C_Map.GetPlayerMapPosition(map, "player")
    if isSecret(position) or position == nil then return nil end
    local x, y
    if position.GetXY then x, y = position:GetXY() else x, y = position.x, position.y end
    x, y = Known(x), Known(y)
    if not (x and y) or (x == 0 and y == 0) then return nil end
    return x * 100, y * 100
end

DataTexts:Register("coords", {
    interval = 0.5,
    text = function()
        local x, y = DataTexts.PlayerPosition()
        if not x then return Dim(L.DATATEXT_COORDS_SHORT) .. " -" end
        return string.format("%.1f, %.1f", x, y)
    end,
    tooltip = function(tt)
        tt:AddLine(Known(_G.GetZoneText and GetZoneText()) or L.DATATEXT_COORDS)
        local sub = Known(_G.GetSubZoneText and GetSubZoneText())
        if sub and sub ~= "" then tt:AddLine(sub, 0.8, 0.8, 0.8) end
        tt:AddLine(L.DATATEXT_COORDS_TIP, 0.5, 0.5, 0.5)
    end,
    click = function() if _G.ToggleWorldMap then ToggleWorldMap() end end,
    events = { "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS" },
})

--------------------------------------------------------------------------------
-- Quêtes
--------------------------------------------------------------------------------

--- Quêtes du journal (en-têtes exclus) et maximum du client.
function DataTexts.QuestCount()
    local count = 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader then count = count + 1 end
        end
    elseif _G.GetNumQuestLogEntries then
        local _, quests = GetNumQuestLogEntries()
        count = quests or 0
    end
    local max = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept())
        or _G.MAX_QUESTLOG_QUESTS or 20
    return count, max
end

DataTexts:Register("quests", {
    text = function()
        local count, max = DataTexts.QuestCount()
        local color = count >= max and "|cffff4040" or "|cffffffff"
        return Dim(L.DATATEXT_QUESTS_SHORT) .. " " .. color .. count .. "/" .. max .. "|r"
    end,
    tooltip = function(tt)
        tt:AddLine(L.DATATEXT_QUESTS)
        tt:AddLine(L.DATATEXT_CLICK_QUESTLOG, 0.5, 0.5, 0.5)
    end,
    click = function() if _G.ToggleQuestLog then ToggleQuestLog() end end,
    events = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED" },
})

--------------------------------------------------------------------------------
-- Régénération de mana
--------------------------------------------------------------------------------

--- Mana par 5 s : hors incantation (règle des 5 s) et en incantation. nil si illisible.
function DataTexts.ManaRegen()
    if not _G.GetManaRegen then return nil end
    local base, casting = GetManaRegen()
    base, casting = Known(base), Known(casting)
    if not (base and casting) then return nil end
    return base * 5, casting * 5
end

DataTexts:Register("regen", {
    interval = 1,
    text = function()
        local base, casting = DataTexts.ManaRegen()
        if not base then return Dim(L.DATATEXT_REGEN_SHORT) .. " -" end
        return Dim(L.DATATEXT_REGEN_SHORT) .. " " .. math.floor(base + 0.5) .. Dim(" | ")
            .. math.floor(casting + 0.5)
    end,
    tooltip = function(tt)
        tt:AddLine(L.DATATEXT_REGEN)
        local base, casting = DataTexts.ManaRegen()
        if base then
            tt:AddDoubleLine(L.DATATEXT_REGEN_BASE, string.format("%.1f", base), 0.8, 0.8, 0.8, 1, 1, 1)
            tt:AddDoubleLine(L.DATATEXT_REGEN_CASTING, string.format("%.1f", casting), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end,
    events = { "UNIT_AURA", "PLAYER_EQUIPMENT_CHANGED", "UNIT_STATS" },
})

--------------------------------------------------------------------------------
-- Vitesse
--------------------------------------------------------------------------------

local BASE_SPEED = _G.BASE_MOVEMENT_SPEED or 7

--- Vitesse actuelle en pourcentage de la course de base, ou nil si illisible.
function DataTexts.Speed()
    if not _G.GetUnitSpeed then return nil end
    local current, run = GetUnitSpeed("player")
    current, run = Known(current), Known(run)
    if not current then return nil end
    if current == 0 then current = run or 0 end   -- à l'arrêt : vitesse de course possible
    return current / BASE_SPEED * 100
end

DataTexts:Register("speed", {
    interval = 0.5,
    text = function()
        local speed = DataTexts.Speed()
        if not speed then return Dim(L.DATATEXT_SPEED_SHORT) .. " -" end
        return Dim(L.DATATEXT_SPEED_SHORT) .. " " .. math.floor(speed + 0.5) .. "%"
    end,
    tooltip = function(tt) tt:AddLine(L.DATATEXT_SPEED) end,
})

--------------------------------------------------------------------------------
-- DPS (compteur de dégâts natif)
--------------------------------------------------------------------------------

--- Dégâts par seconde du joueur dans la séance en cours, via C_DamageMeter. Valeur peut-être
-- secrète (passée telle quelle à AbbreviateNumbers et SetFormattedText) ; nil sans l'API.
function DataTexts.PlayerDPS()
    local meter = _G.C_DamageMeter
    local enum = _G.Enum
    if not (meter and meter.GetCombatSessionFromType and enum and enum.DamageMeterSessionType
            and enum.DamageMeterType) then
        return nil
    end
    local ok, session = pcall(meter.GetCombatSessionFromType, enum.DamageMeterSessionType.Current,
        enum.DamageMeterType.DamageDone)
    if not ok or isSecret(session) or type(session) ~= "table" or type(session.combatSources) ~= "table" then
        return nil
    end
    for _, source in ipairs(session.combatSources) do
        if not isSecret(source.isLocalPlayer) and source.isLocalPlayer then return source.amountPerSecond end
    end
    return nil
end

DataTexts:Register("dps", {
    interval = 1,
    secret = true,
    text = function()
        local dps = DataTexts.PlayerDPS()
        if not isSecret(dps) and dps == nil then return Dim(L.DATATEXT_DPS_SHORT) .. " -" end
        local text = dps   -- chaîne peut-être secrète : jamais testée (pas de « or »)
        if _G.AbbreviateNumbers then text = AbbreviateNumbers(dps) end
        return Dim(L.DATATEXT_DPS_SHORT) .. " %s", text
    end,
    tooltip = function(tt)
        tt:AddLine(L.DATATEXT_DPS)
        if not _G.C_DamageMeter then tt:AddLine(L.DATATEXT_DPS_UNAVAILABLE, 0.6, 0.6, 0.6) end
    end,
    events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
})
