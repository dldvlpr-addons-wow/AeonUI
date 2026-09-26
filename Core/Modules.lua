-- Core/Modules.lua
-- Registre des modules. Chaque module est une table :
--   name, title, description   identifiant et libellés
--   defaults                   fusionnés dans AeonUIDB.modules[name] (doit contenir enabled)
--   secure                     true si le module possède une frame sécurisée : ses
--                              activations/désactivations en combat sont différées
--   reloadOnDisable            true si les cadres Blizzard ne reviennent qu'au /reload : les
--                              options le proposent quand on coupe le module
--   OnEnable(self), OnDisable(self), OnRefresh(self)
-- Pendant l'exécution : module.db (sa table de réglages), module.enabled, module.failed.
--
-- Chaque callback est isolé par xpcall : un module en erreur est marqué `failed`,
-- l'erreur est affichée une fois, et les autres modules continuent.
local _, NS = ...
local L = NS.L

local Modules = {}
NS.Modules = Modules

local registry, order = {}, {}

function Modules:Register(name, module)
    assert(type(module.defaults) == "table" and module.defaults.enabled ~= nil,
        "module " .. name .. " : defaults.enabled manquant")
    module.name = name
    module.enabled = false
    -- Libellés lus par clé : la langue sauvegardée n'est connue qu'à ADDON_LOADED,
    -- après l'enregistrement. NS.SetLocale les rafraîchit.
    if module.titleKey then module.title = L[module.titleKey] end
    if module.descKey then module.description = L[module.descKey] end
    registry[name] = module
    order[#order + 1] = module
    return module
end

function Modules:Get(name) return registry[name] end

function Modules:List() return order end

-- Tri alphabétique sur le titre affiché, accents ramenés à la lettre nue (menu des options).
local ACCENTS = { ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["à"] = "a", ["â"] = "a", ["î"] = "i",
                  ["ï"] = "i", ["ô"] = "o", ["ù"] = "u", ["û"] = "u", ["ç"] = "c", ["É"] = "e", ["È"] = "e", ["À"] = "a" }
function Modules.SortKey(title)
    local key = tostring(title or ""):lower()
    for accent, plain in pairs(ACCENTS) do key = key:gsub(accent, plain) end
    return key
end
--- Copie de la liste triée par titre (les modules sans titre en fin, dans l'ordre d'enregistrement).
function Modules:SortedList()
    local sorted = {}
    for i, module in ipairs(order) do sorted[i] = module end
    table.sort(sorted, function(a, b)
        if not a.title or not b.title then return (a.title and 1 or 0) > (b.title and 1 or 0) end
        return Modules.SortKey(a.title) < Modules.SortKey(b.title)
    end)
    return sorted
end

local function Call(module, method)
    local fn = module[method]
    if not fn then return true end
    -- Module en cours : les movers enregistrés pendant l'appel savent à quel module ils appartiennent.
    local previous = Modules.calling
    Modules.calling = module.name
    local ok, err = xpcall(function() fn(module) end, function(e)
        return tostring(e) .. "\n" .. ((_G.debugstack and debugstack(2)) or "")
    end)
    Modules.calling = previous
    if not ok and not module.failed then
        module.failed = true
        NS.Print(string.format(L.MSG_MODULE_ERROR, module.title or module.name))
        NS.Print(tostring(err))
    end
    return ok
end

--- Addon tiers chargé qui prend la place de ce module (liste module.yieldsTo), ou nil.
-- L'utilisateur garde son réglage : le module revient seul quand l'addon tiers est absent.
function Modules:YieldedBy(name)
    local module = registry[name]
    if not (module and module.yieldsTo) then return nil end
    local api = _G.C_AddOns and C_AddOns.IsAddOnLoaded
    if not api then return nil end
    for _, addon in ipairs(module.yieldsTo) do
        local ok, loaded = pcall(api, addon)
        if ok and loaded then return addon end
    end
    return nil
end

function Modules:IsYielded(name) return self:YieldedBy(name) ~= nil end

--- Noms d'addons tiers connus (toutes listes yieldsTo) qui sont chargés, triés.
function Modules:LoadedThirdParty()
    local seen, names = {}, {}
    for _, module in ipairs(order) do
        for _, addon in ipairs(module.yieldsTo or {}) do
            if not seen[addon] and self:YieldedBy(module.name) == addon then
                seen[addon] = true
                names[#names + 1] = addon
            end
        end
    end
    table.sort(names)
    return names
end

local function Apply(module, enabled)
    if enabled == module.enabled then return end
    if enabled and Modules:IsYielded(module.name) then return end
    if enabled then
        module.enabled = Call(module, "OnEnable")
    else
        Call(module, "OnDisable")
        module.enabled = false
    end
    NS:Fire("MODULE_TOGGLED", module.name, module.enabled)
end

--- Active ou désactive un module et mémorise le choix.
-- Retourne "done", ou "deferred" si le changement attend la fin du combat.
function Modules:SetEnabled(name, enabled)
    local module = registry[name]
    if not module then return nil end
    module.db = NS.db.modules[name]
    module.db.enabled = enabled and true or false
    if module.secure and NS.InCombat() then
        NS:RunOutOfCombat(function() Apply(module, module.db.enabled) end)
        NS.Print(string.format(L.MSG_AFTER_COMBAT, module.title or name))
        return "deferred"
    end
    Apply(module, module.db.enabled)
    return "done"
end

--- Un réglage du module a changé : OnRefresh s'il est actif.
function Modules:Refresh(name)
    local module = registry[name]
    if not module or not module.enabled then return end
    if module.secure and NS.InCombat() then
        NS:RunOutOfCombat(function() if module.enabled then Call(module, "OnRefresh") end end)
        return
    end
    Call(module, "OnRefresh")
end

function Modules:RefreshAll()
    for _, module in ipairs(order) do self:Refresh(module.name) end
end

function Modules:EnableAll()
    for _, module in ipairs(order) do
        module.db = NS.db.modules[module.name]
        module.failed = nil
        if module.db.enabled then
            if module.secure then
                NS:RunOutOfCombat(function() Apply(module, true) end)
            else
                Apply(module, true)
            end
        end
    end
end

function Modules:DisableAll()
    for _, module in ipairs(order) do Apply(module, false) end
end

-- Les modules s'activent à PLAYER_LOGIN : GameTooltip, les popups et les sacs existent alors.
NS:On("LOGIN", function() Modules:EnableAll() end)
NS:On("THEME_CHANGED", function() Modules:RefreshAll() end)
