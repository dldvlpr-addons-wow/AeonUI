-- Core/CVars.lua
-- Toute CVar modifiée par AeonUI passe par ici : la valeur d'origine est mémorisée
-- (AeonUIDB.cvarBackup, compte entier) avant la première modification, et rendue quand
-- le module qui l'a changée est coupé, ou par /aeon uninstall.
-- Certaines CVars sont protégées en combat : les écritures attendent la fin du combat.
local _, NS = ...

local CVars = {}
NS.CVars = CVars
CVars.pending = {}   -- [name] = jeton entre Restore en combat et l'écriture

local function Get(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return _G.GetCVar and GetCVar(name)
end

local function Write(name, value)
    if C_CVar and C_CVar.SetCVar then
        return C_CVar.SetCVar(name, value)
    elseif _G.SetCVar then
        return SetCVar(name, value)
    end
end

--- La CVar existe-t-elle sur ce client ?
function CVars:Exists(name)
    return Get(name) ~= nil
end

function CVars:Get(name) return Get(name) end

--- Change une CVar en gardant sa valeur d'origine. Ignore une CVar inconnue du client.
function CVars:Set(name, value)
    value = tostring(value)
    if Get(name) == nil then return false end
    -- Sauvegarde immédiate : IsChanged et Restore sont fiables même pendant que l'écriture attend.
    local backup = NS.global.cvarBackup
    -- Restore encore en attente (couper puis remettre en combat) : annulée, sinon elle
    -- effacerait la sauvegarde à la sortie du combat et l'origine serait perdue.
    CVars.pending[name] = nil
    if backup[name] == nil then backup[name] = Get(name) end
    NS:RunOutOfCombat(function()
        if Get(name) ~= value then Write(name, value) end
    end)
    return true
end

--- Rend la valeur d'origine d'une CVar, si AeonUI l'avait changée.
function CVars:Restore(name)
    local original = NS.global.cvarBackup[name]
    if original == nil then return false end
    -- La sauvegarde reste jusqu'à l'écriture (déconnexion en combat : RestoreAll la retrouve),
    -- mais IsChanged reflète tout de suite le choix de l'utilisateur.
    local token = {}
    CVars.pending[name] = token
    NS:RunOutOfCombat(function()
        if CVars.pending[name] ~= token then return end   -- annulée par Set, ou rendue par RestoreAll
        CVars.pending[name] = nil
        if NS.global.cvarBackup[name] == nil then return end
        Write(name, original)
        NS.global.cvarBackup[name] = nil
    end)
    return true
end

--- `immediate` : écrit tout de suite, même en combat (déconnexion : la file ne se viderait jamais).
function CVars:RestoreAll(immediate)
    local backup = NS.global.cvarBackup
    for name in pairs(backup) do
        if immediate then
            -- Écriture refusée (CVar protégée en combat) : la sauvegarde reste pour la prochaine fois.
            if Write(name, backup[name]) ~= false then backup[name] = nil end
            CVars.pending[name] = nil
        else
            self:Restore(name)
        end
    end
end

function CVars:IsChanged(name)
    return NS.global.cvarBackup[name] ~= nil and not CVars.pending[name]
end
