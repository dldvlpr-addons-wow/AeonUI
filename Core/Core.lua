-- Core/Core.lua
-- Bus interne, file d'attente hors combat, chargement de la DB, commandes slash.
local ADDON_NAME, NS = ...
local L = NS.L

function NS.Print(...)
    print("|cff3fa9f5AeonUI|r: " .. strjoin(" ", tostringall(...)))
end

--------------------------------------------------------------------------------
-- Bus interne
--------------------------------------------------------------------------------
-- "DB_READY", "LOGIN", "THEME_CHANGED", "PIXEL_CHANGED", "UNLOCK"(bool), "MODULE_TOGGLED"(name, enabled)

local listeners = {}

function NS:On(event, fn)
    listeners[event] = listeners[event] or {}
    local list = listeners[event]
    list[#list + 1] = fn
end

function NS:Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    -- Un écouteur en erreur ne doit pas priver les suivants (PROFILE_READY puis LOGIN active les modules).
    local n, args = select("#", ...), { ... }
    for i = 1, #list do
        xpcall(function() list[i](unpack(args, 1, n)) end, geterrorhandler())
    end
end

--------------------------------------------------------------------------------
-- File hors combat
--------------------------------------------------------------------------------
-- Une frame sécurisée (ou une frame parente d'une frame sécurisée) ne se crée, ne se
-- déplace et ne se cache pas en combat. Tout ce qui y touche passe par ici.

local pending = {}
local combatFrame = CreateFrame("Frame")

function NS.InCombat()
    return (_G.InCombatLockdown and InCombatLockdown()) and true or false
end

--- Exécute fn tout de suite hors combat, sinon à la sortie du combat.
-- Retourne true si exécuté immédiatement.
function NS:RunOutOfCombat(fn)
    if not NS.InCombat() then
        fn()
        return true
    end
    pending[#pending + 1] = fn
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    return false
end

combatFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local queue = pending
    pending = {}
    for i = 1, #queue do
        local ok, err = pcall(queue[i])
        if not ok then NS.Print(tostring(err)) end
    end
end)

--------------------------------------------------------------------------------
-- Déverrouillage (déplacement des éléments mobiles)
--------------------------------------------------------------------------------

NS.unlocked = false

function NS:SetUnlocked(unlocked)
    self.unlocked = unlocked and true or false
    if NS.Movers then NS.Movers:SetUnlocked(self.unlocked) end
    self:Fire("UNLOCK", self.unlocked)
    NS.Print(self.unlocked and L.MSG_UNLOCKED or L.MSG_LOCKED)
end

--------------------------------------------------------------------------------
-- Chargement
--------------------------------------------------------------------------------

local function BindSaved()
    -- Ce client ne relit pas la SavedVariables de compte : Database:Load fournit les replis
    -- (table hôte Blizzard, puis miroir CVar).
    AeonUIDB = NS.Database:Attach(NS.Database:Load(AeonUIDB))
    NS.global = AeonUIDB
    NS.Database:HostGlobal()
    NS.SetLocale(NS.global.locale)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        BindSaved()
        NS:Fire("DB_READY")
    else
        -- Le nom du personnage (clé du profil) n'est fiable qu'à PLAYER_LOGIN.
        self:UnregisterEvent("PLAYER_LOGIN")
        -- Garde-fou : la globale remplacée entre ADDON_LOADED et PLAYER_LOGIN (NS.global orphelin).
        if AeonUIDB ~= NS.global then BindSaved() end
        NS.db = NS.Database:ActiveProfile()
        NS:Fire("PROFILE_READY")
        NS:Fire("LOGIN")
        -- Miroir : recopie toutes les 5 s par OnUpdate (pas C_Timer : règle de persistance Forever),
        -- n'écrit que si la table a changé, plus à la déconnexion.
        local mirror, elapsedTotal = CreateFrame("Frame"), 0
        mirror:SetScript("OnUpdate", function(_, elapsed)
            elapsedTotal = elapsedTotal + elapsed
            if elapsedTotal < 5 then return end
            elapsedTotal = 0
            NS.Database:WriteMirror()
        end)
    end
end)

--------------------------------------------------------------------------------
-- Profils
--------------------------------------------------------------------------------

--- Rebranche tous les modules sur un autre profil (hors combat : la barre est sécurisée).
-- Cadres Blizzard rendus par le nouveau profil : /reload proposé (BLIZZARD_FRAMES_RELEASED).
local function Reload(getProfile)
    NS:RunOutOfCombat(function()
        NS.Modules:DisableAll()
        NS.db = getProfile()
        NS.Modules:EnableAll()
        NS:Fire("THEME_CHANGED")
        NS:Fire("PROFILE_CHANGED")
    end)
end

function NS:SwitchProfile(name, copyFrom)
    Reload(function() return NS.Database:UseProfile(name, copyFrom) end)
end

function NS:ResetProfile()
    Reload(function() return NS.Database:ResetActiveProfile() end)
end

--- Importe une chaîne de profil (voir Database.Serialize) dans le profil actif.
function NS:ImportProfile(text)
    if not NS.Database.Deserialize(text) then
        NS.Print(L.MSG_IMPORT_FAILED)
        return false
    end
    Reload(function()
        local profile = NS.Database:ImportProfile(text)
        NS.Print(L.MSG_IMPORT_OK)
        return profile
    end)
    return true
end

--- Changement de spé (ou spé enfin connue après la connexion) : rebranche le profil qui lui
-- est lié s'il n'est pas déjà actif.
function NS:CheckSpecProfile()
    if not (NS.global and NS.db) then return end
    local spec = NS.GetActiveSpec()
    if spec then NS.global.lastSpec[NS.Database.CharacterKey()] = spec end
    if NS.db ~= NS.Database:ActiveProfile() then
        Reload(function()
            NS.Print(string.format(L.MSG_PROFILE, NS.Database:ActiveProfileName()))
            return NS.Database:ActiveProfile()
        end)
    end
end

local specEvents = CreateFrame("Frame")
NS.RegisterEventSafe(specEvents, "PLAYER_SPECIALIZATION_CHANGED", "player")
NS.RegisterEventSafe(specEvents, "ACTIVE_TALENT_GROUP_CHANGED")
NS.RegisterEventSafe(specEvents, "PLAYER_ENTERING_WORLD")
specEvents:SetScript("OnEvent", function() NS:CheckSpecProfile() end)

--------------------------------------------------------------------------------
-- Désinstallation
--------------------------------------------------------------------------------

--- Rend les CVars d'origine et coupe tous les modules. Idempotent.
-- `silent` : à la déconnexion, sans message ni file hors combat (elle ne se viderait jamais).
function NS:Uninstall(silent)
    local function run()
        NS.Modules:DisableAll()
        -- Tous les profils, pas seulement l'actif : un autre personnage ne doit rien rallumer.
        -- Pas à la déconnexion (addon décoché, parfois pour ce seul personnage) : les réglages
        -- restent, l'addon ne se charge plus de toute façon.
        if not silent then
            for _, profile in pairs(NS.global.profiles) do
                for _, module in ipairs(NS.Modules:List()) do
                    local settings = profile.modules and profile.modules[module.name]
                    if settings then settings.enabled = false end
                end
                if profile.theme then profile.theme.pixelPerfect, profile.theme.uiScale = false, 1 end
            end
        end
        if not silent then NS.Pixel:Apply() end   -- rend l'échelle d'UIParent (inutile à la déconnexion)
        NS.CVars:RestoreAll(silent)
        -- Compte entier : pas à la déconnexion, un autre personnage peut encore utiliser AeonUI.
        if not silent then NS.global.addonPlacements = nil end   -- DBM et BigWigs plus reposés
        if not silent then NS.Print(L.MSG_UNINSTALLED) end
    end
    if silent then
        run()
    elseif not NS:RunOutOfCombat(run) then
        NS.Print(string.format(L.MSG_AFTER_COMBAT, ADDON_NAME))
    end
end

StaticPopupDialogs["AEONUI_UNINSTALL"] = {
    text = "",   -- posé à l'ouverture : la langue peut changer après le chargement
    button1 = YES,
    button2 = NO,
    OnAccept = function() NS:Uninstall() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Addon désactivé dans la liste des addons : rendre les réglages Blizzard avant qu'il ne
-- cesse de charger. L'ordre des arguments de GetAddOnEnableState a changé entre versions :
-- on sonde les deux contre nous-même au login ; sans réponse cohérente, on ne fait rien.
local ENABLED_STATE_NONE = 0

local function EnableState(order)
    if not (C_AddOns and C_AddOns.GetAddOnEnableState) then return nil end
    local a, b = ADDON_NAME, (UnitName("player"))
    if order == 2 then a, b = b, a end
    local ok, state = pcall(C_AddOns.GetAddOnEnableState, a, b)
    if ok and type(state) == "number" then return state end
    return nil
end

local argumentOrder

local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_LOGIN")
watch:RegisterEvent("PLAYER_LOGOUT")
watch:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Nous tournons : la seule réponse cohérente est « activé ».
        argumentOrder = nil
        for _, order in ipairs({ 1, 2 }) do
            local state = EnableState(order)
            if state and state ~= ENABLED_STATE_NONE then argumentOrder = order break end
        end
        if C_AddOns and C_AddOns.DisableAddOn then
            hooksecurefunc(C_AddOns, "DisableAddOn", function(name)
                if name == ADDON_NAME then NS.Print(L.MSG_WILL_RESTORE) end
            end)
        end
    elseif argumentOrder and NS.db and EnableState(argumentOrder) == ENABLED_STATE_NONE then
        NS:Uninstall(true)
    end
    if event == "PLAYER_LOGOUT" then NS.Database:WriteMirror() end
end)

--- Icône du compartiment d'addons (minimap) : clic gauche = options, clic droit = déverrouiller.
function _G.AeonUI_AddonCompartmentFunc(_, button)
    if button == "RightButton" then NS:SetUnlocked(not NS.unlocked) else NS.OpenOptions() end
end

--------------------------------------------------------------------------------
-- Slash
--------------------------------------------------------------------------------

local commands = {}

function commands.unlock() NS:SetUnlocked(true) end
function commands.lock() NS:SetUnlocked(false) end

--- /aeon kb : mode raccourcis des barres d'action AeonUI.
function commands.kb()
    local bars = NS.Modules:Get("actionbars")
    if bars and bars.ToggleKeyBind then bars:ToggleKeyBind() end
end

function commands.setup()
    if NS.FirstRun then NS.FirstRun:Show() end
end

--- /aeon install [complete|light] [dps|heal|tank]
-- /aeon install dps|heal|tank : profil de base du rôle. /aeon install complete|light [rôle] : préréglage
-- sur le profil actif.
function commands.install(args)
    local first, second = (args or ""):match("^(%S*)%s*(%S*)")
    if NS.Install.ROLES[first] then
        NS:RunOutOfCombat(function() NS.Install:Apply(first) end)
        return
    end
    if first == "" then NS.Print(L.MSG_INSTALL_USAGE) return end
    if second == "" then second = nil end
    if not NS.Install.PRESETS[first] or (second and not NS.Install.ROLES[second]) then NS.Print(L.MSG_INSTALL_USAGE) return end
    NS:RunOutOfCombat(function() NS.Install:ApplyPreset(first, second) end)
end

function commands.status()
    NS.Print(string.format(L.MSG_PROFILE, NS.Database:ActiveProfileName()))
    for _, module in ipairs(NS.Modules:List()) do
        local state = module.enabled and L.STATUS_ON or L.STATUS_OFF
        if module.failed then state = L.STATUS_FAILED end
        NS.Print(string.format("%s : %s", module.title or module.name, state))
    end
end

function commands.reset()
    NS:ResetProfile()
    NS.Print(L.MSG_RESET)
end

function commands.diag()
    for _, line in ipairs(NS.Diagnostic()) do NS.Print(line) end
end

function commands.uninstall()
    StaticPopupDialogs.AEONUI_UNINSTALL.text = L.MSG_UNINSTALL_CONFIRM
    StaticPopup_Show("AEONUI_UNINSTALL")
end

SLASH_AEONUI1 = "/aeon"
SLASH_AEONUI2 = "/aeonui"
SlashCmdList.AEONUI = function(msg)
    local command, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local handler = commands[command]
    if handler then
        handler(rest)
    elseif command == "" then
        NS.OpenOptions()
    else
        NS.Print(L.MSG_HELP)
    end
end
