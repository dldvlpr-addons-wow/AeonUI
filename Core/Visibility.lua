-- Core/Visibility.lua
-- Visibilité commune : un réglage par élément (combat, groupe, raid, instance, monture, cible),
-- chaque condition « indifférent », « oui » ou « non », combinées par « toutes » ou « au moins une »,
-- plus « au survol seulement ». Un état partagé suivi une fois pour tous les modules.
--
-- Cadre sécurisé : les conditions deviennent un state driver (conditions macro), posé hors
-- combat ; l'instance n'a pas de condition macro et y est ignorée. Survol : alpha (permis en
-- combat), partagé par les cadres d'un même groupe de survol.
local _, NS = ...

local Visibility = { entries = {} }
NS.Visibility = Visibility

Visibility.CONDITIONS = { "combat", "group", "raid", "instance", "mounted", "target" }

-- Condition -> { vraie, fausse } en conditions macro. Absente : non exprimable (instance).
local MACRO = {
    combat = { "combat", "nocombat" },
    group = { "group", "nogroup" },
    raid = { "group:raid", "nogroup:raid" },
    mounted = { "mounted", "nomounted" },
    target = { "@target,exists", "@target,noexists" },
}

local HOVER_INTERVAL = 0.1

--- Réglage par défaut : toujours visible. `overrides` remplace des champs.
function Visibility.Spec(overrides)
    local spec = { match = "all", mouseover = false }
    for _, condition in ipairs(Visibility.CONDITIONS) do spec[condition] = "ignore" end
    for key, value in pairs(overrides or {}) do spec[key] = value end
    return spec
end

--------------------------------------------------------------------------------
-- Fonctions pures
--------------------------------------------------------------------------------

--- Conditions du réglage satisfaites par `state` ({ combat = bool, ... }). Aucune condition : vrai.
function Visibility.Evaluate(spec, state)
    local used, hits = 0, 0
    for _, condition in ipairs(Visibility.CONDITIONS) do
        local wanted = spec[condition]
        if wanted == "yes" or wanted == "no" then
            used = used + 1
            if (state[condition] and true or false) == (wanted == "yes") then hits = hits + 1 end
        end
    end
    if used == 0 then return true end
    if spec.match == "any" then return hits > 0 end
    return hits == used
end

--- Conditions macro du réglage (« [combat,mounted] show; hide ») ; nil sans condition exprimable.
function Visibility.Macro(spec)
    local parts = {}
    for _, condition in ipairs(Visibility.CONDITIONS) do
        local wanted, macro = spec[condition], MACRO[condition]
        if macro and (wanted == "yes" or wanted == "no") then
            parts[#parts + 1] = macro[wanted == "yes" and 1 or 2]
        end
    end
    if #parts == 0 then return nil end
    if spec.match == "any" then
        local clauses = {}
        for _, part in ipairs(parts) do clauses[#clauses + 1] = "[" .. part .. "] show" end
        return table.concat(clauses, "; ") .. "; hide"
    end
    return "[" .. table.concat(parts, ",") .. "] show; hide"
end

--- Clauses « hide » à poser devant le pilote propre d'un cadre sécurisé (« [nocombat] hide; ») :
-- cachent le cadre quand le réglage n'est pas satisfait. "" sans condition exprimable.
function Visibility.HideClauses(spec)
    local fails = {}
    for _, condition in ipairs(Visibility.CONDITIONS) do
        local wanted, macro = spec[condition], MACRO[condition]
        if macro and (wanted == "yes" or wanted == "no") then
            fails[#fails + 1] = macro[wanted == "yes" and 2 or 1]
        end
    end
    if #fails == 0 then return "" end
    if spec.match == "any" then return "[" .. table.concat(fails, ",") .. "] hide; " end
    return "[" .. table.concat(fails, "] hide; [") .. "] hide; "
end

--------------------------------------------------------------------------------
-- État partagé
--------------------------------------------------------------------------------

local inCombat = false   -- PLAYER_REGEN_DISABLED arrive avant que InCombatLockdown ne réponde vrai

--- État courant. `event` : l'événement en cours de traitement chez l'appelant (l'ordre des
-- gestionnaires n'est pas garanti, PLAYER_REGEN_* fait foi).
function Visibility.State(event)
    local _, instanceType = IsInInstance()
    local combat = inCombat or NS.InCombat()
    if event == "PLAYER_REGEN_DISABLED" then combat = true elseif event == "PLAYER_REGEN_ENABLED" then combat = false end
    return {
        combat = combat,
        group = (_G.IsInGroup and IsInGroup()) or (GetNumGroupMembers() > 0),
        raid = IsInRaid() == true,
        instance = instanceType ~= nil and instanceType ~= "none",
        mounted = _G.IsMounted and IsMounted() or false,
        target = UnitExists("target") and true or false,
    }
end

--------------------------------------------------------------------------------
-- Éléments enregistrés
--------------------------------------------------------------------------------
-- opts : secure (state driver), prefix (conditions macro posées avant, « [petbattle] hide; »),
-- hoverGroup (survol partagé), alpha() (opacité visible, 1 par défaut), apply(frame, visible)
-- (application propre au module à la place de SetShown), forceVisible() (vrai : rien de caché).

local hoverFrame = CreateFrame("Frame")
hoverFrame.elapsed = 0

local function Hovered(entry)
    if entry.frame:IsShown() and entry.frame:IsMouseOver() then return true end
    local group = entry.opts.hoverGroup
    if not group then return false end
    for _, other in pairs(Visibility.entries) do
        if other ~= entry and other.opts.hoverGroup == group and other.frame:IsShown() and other.frame:IsMouseOver() then
            return true
        end
    end
    return false
end

local function ApplyAlpha(entry)
    local spec = entry.getSpec()
    local base = entry.opts.alpha and entry.opts.alpha() or 1
    local forced = entry.opts.forceVisible and entry.opts.forceVisible()
    local hidden = spec.mouseover and not forced and not Hovered(entry)
    entry.frame:SetAlpha(hidden and 0 or base)
end

local function NeedsHover()
    for _, entry in pairs(Visibility.entries) do
        if entry.getSpec().mouseover then return true end
    end
    return false
end

local function RunHover()
    if NeedsHover() then
        hoverFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed < HOVER_INTERVAL then return end
            self.elapsed = 0
            for _, entry in pairs(Visibility.entries) do
                if entry.getSpec().mouseover then ApplyAlpha(entry) end
            end
        end)
    else
        hoverFrame:SetScript("OnUpdate", nil)
    end
end

--- Cadre sécurisé : state driver (hors combat). Autre : SetShown ou opts.apply.
local function Apply(entry, state)
    local spec, opts = entry.getSpec(), entry.opts
    if opts.secure then
        NS:RunOutOfCombat(function()
            if Visibility.entries[entry.key] ~= entry then return end
            local macro = Visibility.Macro(spec)
            if macro or opts.prefix then
                RegisterStateDriver(entry.frame, "visibility", (opts.prefix or "") .. (macro or "show"))
            else
                UnregisterStateDriver(entry.frame, "visibility")
                entry.frame:Show()
            end
        end)
    else
        local visible = (opts.forceVisible and opts.forceVisible()) or Visibility.Evaluate(spec, state or Visibility.State())
        if opts.apply then opts.apply(entry.frame, visible) else entry.frame:SetShown(visible) end
    end
    ApplyAlpha(entry)
end

--- Suit la visibilité de `frame` selon le réglage rendu par `getSpec()`. Remplace une entrée de même clé.
function Visibility:Register(key, frame, getSpec, opts)
    local entry = { key = key, frame = frame, getSpec = getSpec, opts = opts or {} }
    self.entries[key] = entry
    Apply(entry)
    RunHover()
    return entry
end

--- Oublie l'entrée ; un cadre sécurisé perd son state driver (hors combat) et l'alpha revient à 1.
function Visibility:Unregister(key)
    local entry = self.entries[key]
    if not entry then return end
    self.entries[key] = nil
    if entry.opts.secure then
        NS:RunOutOfCombat(function()
            if not self.entries[key] then UnregisterStateDriver(entry.frame, "visibility") end
        end)
    end
    entry.frame:SetAlpha(1)
    RunHover()
end

--- Réapplique une entrée (réglage changé), ou toutes sans clé.
function Visibility:Refresh(key)
    local state = Visibility.State()
    for entryKey, entry in pairs(self.entries) do
        if key == nil or entryKey == key then Apply(entry, state) end
    end
    RunHover()
end

--- Alpha seulement (survol, forceVisible changé) : sans toucher aux drivers.
function Visibility:RefreshAlpha()
    for _, entry in pairs(self.entries) do ApplyAlpha(entry) end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
                         "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED" }) do
    NS.RegisterEventSafe(events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then inCombat = true elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false end
    -- Les drivers suivent seuls leurs conditions : seuls les cadres non sécurisés sont recalculés.
    local state = Visibility.State(event)
    for _, entry in pairs(Visibility.entries) do
        if not entry.opts.secure then Apply(entry, state) end
    end
end)
