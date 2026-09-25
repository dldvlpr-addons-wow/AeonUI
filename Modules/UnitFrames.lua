-- Modules/UnitFrames.lua
-- Cadres d'unité AeonUI : joueur, cible, cible de la cible, focus, cible du focus, familier,
-- boss 1 à 5 (un bloc de réglages commun). Remplacent
-- les cadres Blizzard (masqués, rendus au /reload après désactivation).
--
-- Chaque cadre est un bouton sécurisé (SecureUnitButtonTemplate : clic gauche cible, clic
-- droit menu, visibilité par RegisterUnitWatch), enfant d'UIParent, créé et dimensionné hors
-- combat. Ses éléments (NS.UnitFrameElements) sont des régions libres : mises à jour en combat.
-- Le module cède à ElvUI (yieldsTo) et se déplace par les movers (clés uf_<unité>).
local _, NS = ...
local L = NS.L
local Elements = NS.UnitFrameElements
local Movers = NS.Movers

local function Unit(width, height, overrides)
    local cfg = {
        enabled = true, width = width, height = height, powerHeight = 6,
        castbar = true, castbarHeight = 18, castbarDetached = false, castbarWidth = 260,
        auras = false, auraSize = 22, aurasAbove = false,
        buffs = false,            -- voie maison (filtre autre que tout/les miens) : buffs après les débuffs
        auraFilter = "all",       -- NS.AURA_FILTERS
        healthFormat = "",        -- format à jetons propre au cadre, prime sur healthText
        powerFormat = "",
        power = true, name = true, level = true, combo = false,
        fader = false,            -- estompé hors combat quand rien ne se passe
        portrait = false,         -- portrait 2D hors du cadre
        portraitSide = "RIGHT",   -- "LEFT" | "RIGHT"
    }
    for k, v in pairs(overrides or {}) do cfg[k] = v end
    return cfg
end

local UnitFrames = NS.Modules:Register("unitframes", {
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    titleKey = "UNITFRAMES_TITLE",
    descKey = "UNITFRAMES_DESC",
    yieldsTo = { "ElvUI" },
    secure = true,                -- création, tailles et attributs des boutons hors combat
    defaults = {
        enabled = false,          -- allumé par l'installation un clic (étape 7)
        classColor = true,
        healthGradient = false,   -- vie rouge-jaune-vert selon le pourcentage (prime sur la classe)
        healPrediction = true,    -- soins entrants et absorptions au bout de la vie
        healthText = "current",   -- préréglage : UnitFrameElements.TEXT_PRESETS
        powerText = "none",
        fadeAlpha = 0.35,         -- opacité d'un cadre estompé (option fader par unité)
        units = {
            player       = Unit(220, 42, { combo = true, portraitSide = "LEFT", auras = true, aurasAbove = true, buffs = true,
                                             totems = true, totemSize = 30 }),
            target       = Unit(220, 42, { auras = true }),
            targettarget = Unit(110, 24, { powerHeight = 0, castbar = false, power = false, level = false, name = true }),
            focus        = Unit(180, 36, { auras = true }),
            pet          = Unit(110, 24, { powerHeight = 4, castbar = false, level = false, portraitSide = "LEFT" }),
            focustarget  = Unit(110, 24, { enabled = false, powerHeight = 0, castbar = false, power = false, level = false }),
            boss         = Unit(200, 36, { auras = true, auraSize = 20 }),   -- boss1 à boss5
        },
    },
})

UnitFrames.UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss1", "boss2", "boss3", "boss4", "boss5" }
-- Réglages : un bloc par unité, un seul pour les cinq boss.
UnitFrames.SETTINGS_UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }
-- Cible de la cible, cible du focus : pas d'événements fiables, rafraîchies tant qu'elles sont visibles.
local POLLED = { targettarget = true, focustarget = true }
UnitFrames.frames = {}

local MOVER_DEFAULTS = {
    player       = { "CENTER", -300, -200 },
    target       = { "CENTER", 300, -200 },
    targettarget = { "CENTER", 300, -260 },
    focus        = { "CENTER", 0, -320 },
    pet          = { "CENTER", -300, -260 },
    focustarget  = { "CENTER", 0, -370 },
}
for i = 1, 5 do MOVER_DEFAULTS["boss" .. i] = { "RIGHT", -310, 260 - (i - 1) * 70 } end   -- à gauche du suivi de quêtes
-- Barre d'incantation détachée (option castbarDetached) : au-dessus des barres d'action.
local CASTBAR_MOVER_DEFAULTS = {
    player = { "CENTER", 0, -160 },
    target = { "CENTER", 0, -120 },
    focus  = { "CENTER", 0, 120 },
}
for i = 1, 5 do CASTBAR_MOVER_DEFAULTS["boss" .. i] = { "RIGHT", -310, 232 - (i - 1) * 70 } end

local BLIZZARD = {
    player       = { "PlayerFrame" },
    target       = { "TargetFrame", "ComboFrame" },
    targettarget = { "TargetFrameToT" },
    focus        = { "FocusFrame", "FocusFrameToT" },
    pet          = { "PetFrame" },
    focustarget  = {},
    boss1        = { "BossTargetFrameContainer", "Boss1TargetFrame" },
}
for i = 2, 5 do BLIZZARD["boss" .. i] = { "Boss" .. i .. "TargetFrame" } end

local PLAYER_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING",
                        "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_LEVEL_UP" }
local TOT_INTERVAL = 0.5

local active = false

--------------------------------------------------------------------------------
-- Cadres
--------------------------------------------------------------------------------

local RunFader   -- fondu hors combat, défini plus bas

local function Settings(unit)
    return UnitFrames.db.units[unit:match("^boss%d$") and "boss" or unit]
end

local function OnUnitEvent(frame, event)
    if not active then return end
    if Elements.OnEvent(frame, event) then return end
    if event == "RAID_TARGET_UPDATE" then Elements.UpdateRaidIcon(frame) return end
    if event == "PLAYER_LEVEL_UP" then Elements.UpdateLevel(frame) return end
    Elements.UpdateIndicators(frame)   -- PLAYER_REGEN_*, PLAYER_UPDATE_RESTING, groupe
end

local function Create(unit)
    local frame = CreateFrame("Button", "AeonUI_UF_" .. unit, UIParent, "SecureUnitButtonTemplate")
    frame.unit = unit
    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")
    frame:SetFrameStrata("LOW")
    NS.Media:CreateBackdrop(frame)
    frame.cfg, frame.global = Settings(unit), UnitFrames.db
    Elements.Build(frame)

    for event in pairs(Elements.UNIT_EVENTS) do NS.RegisterEventSafe(frame, event, unit) end
    for _, event in ipairs(Elements.CAST_EVENTS) do NS.RegisterEventSafe(frame, event, unit) end
    NS.RegisterEventSafe(frame, "RAID_TARGET_UPDATE")
    if unit == "player" then
        for _, event in ipairs(PLAYER_EVENTS) do NS.RegisterEventSafe(frame, event) end
    end
    frame:SetScript("OnEvent", OnUnitEvent)
    if POLLED[unit] then
        frame.elapsed = 0
        frame:SetScript("OnUpdate", function(self, dt)
            self.elapsed = self.elapsed + dt
            if self.elapsed < TOT_INTERVAL then return end
            self.elapsed = 0
            if active then Elements.UpdateAll(self) end
        end)
    end
    UnitFrames.frames[unit] = frame
    return frame
end

local function MoverLabel(unit)
    local boss = unit:match("^boss(%d)$")
    if boss then return string.format(L.MOVER_UF_BOSS, boss) end
    return L["MOVER_UF_" .. unit:upper()] or unit
end

--- Pose tailles, éléments, mover et visibilité d'un cadre (hors combat).
local function Setup(unit)
    local frame = UnitFrames.frames[unit] or Create(unit)
    frame.cfg, frame.global = Settings(unit), UnitFrames.db
    Elements.Layout(frame)
    Elements.BuildAuras(frame)
    Elements.LayoutAuras(frame)
    local d = MOVER_DEFAULTS[unit]
    Movers:Register("uf_" .. unit, frame, MoverLabel(unit), d[1], d[2], d[3])
    Movers:Load("uf_" .. unit)
    if frame.cfg.castbar and frame.cfg.castbarDetached then
        local c = CASTBAR_MOVER_DEFAULTS[unit] or CASTBAR_MOVER_DEFAULTS.player
        Movers:Register("uf_castbar_" .. unit, frame.castbar, string.format(L.MOVER_UF_CASTBAR, MoverLabel(unit)), c[1], c[2], c[3])
        Movers:Load("uf_castbar_" .. unit)
    else
        Movers:Unregister("uf_castbar_" .. unit)
    end
    if not frame.watched then
        frame.watched = true
        RegisterUnitWatch(frame)
    end
    Elements.UpdateAll(frame)
    -- Systèmes Edit Mode : événements coupés et cachés, jamais reparentés (taint).
    for _, name in ipairs(BLIZZARD[unit]) do NS.HideBlizzardFrame(name, true) end
    if unit == "player" then
        -- Géré par Edit Mode : événements coupés et caché, jamais reparenté (taint).
        if frame.cfg.castbar then NS.HideBlizzardFrame("PlayerCastingBarFrame", true)
        else NS.ShowBlizzardFrame("PlayerCastingBarFrame") end
    end
end

--- Cache un cadre et rend les cadres Blizzard de l'unité (hors combat).
local function Teardown(unit)
    local frame = UnitFrames.frames[unit]
    if frame and frame.watched then
        UnregisterUnitWatch(frame)
        frame.watched = false
    end
    if frame then frame:Hide() end
    Movers:Unregister("uf_" .. unit)
    Movers:Unregister("uf_castbar_" .. unit)
    for _, name in ipairs(BLIZZARD[unit]) do NS.ShowBlizzardFrame(name) end
    if unit == "player" then NS.ShowBlizzardFrame("PlayerCastingBarFrame") end
end

--- Crée, relaie ou retire chaque cadre selon les réglages. Toujours hors combat (module secure).
function UnitFrames:Reconcile()
    for _, unit in ipairs(self.UNITS) do
        if Settings(unit).enabled then Setup(unit) else Teardown(unit) end
    end
    self:ReconcileTotems()
    RunFader()
end

function UnitFrames:Refresh(unit)
    local frame = self.frames[unit]
    if frame and frame.watched then Elements.UpdateAll(frame) end
end

function UnitFrames:GetFrame(unit) return self.frames[unit] end

--------------------------------------------------------------------------------
-- Fondu hors combat
--------------------------------------------------------------------------------
-- Un cadre « estompé » passe à fadeAlpha tant que rien ne se passe, et revient plein en combat,
-- avec une cible, pendant une incantation, blessé ou survolé. SetAlpha est permis en combat
-- sur un cadre protégé. Une valeur secrète compte comme « il se passe quelque chose ».

local FADE_INTERVAL = 0.2
local fader = CreateFrame("Frame")
fader.elapsed = 0

local function Busy(frame)
    if NS.InCombat() or frame:IsMouseOver() then return true end
    local hasTarget = UnitExists("target")
    if NS.IsSecret(hasTarget) or hasTarget then return true end
    for _, info in ipairs({ UnitCastingInfo, _G.UnitChannelInfo }) do
        local spell = info("player")
        if NS.IsSecret(spell) or spell ~= nil then return true end
    end
    local health, maxHealth = UnitHealth(frame.unit), UnitHealthMax(frame.unit)
    if NS.IsSecret(health) or NS.IsSecret(maxHealth) then return true end
    return health < maxHealth
end
UnitFrames.Busy = Busy

function UnitFrames:UpdateFade()
    for unit, frame in pairs(self.frames) do
        if frame.watched then
            local faded = active and Settings(unit).fader and not Busy(frame)
            frame:SetAlpha(faded and self.db.fadeAlpha or 1)
        end
    end
end

function RunFader()
    local needed = false
    for _, unit in ipairs(UnitFrames.SETTINGS_UNITS) do
        local cfg = Settings(unit)
        if cfg.enabled and cfg.fader then needed = true end
    end
    if active and needed then
        fader:SetScript("OnUpdate", function(self, dt)
            self.elapsed = self.elapsed + dt
            if self.elapsed < FADE_INTERVAL then return end
            self.elapsed = 0
            UnitFrames:UpdateFade()
        end)
    else
        fader:SetScript("OnUpdate", nil)
    end
    UnitFrames:UpdateFade()
end

--------------------------------------------------------------------------------
-- Totems
--------------------------------------------------------------------------------
-- Le cadre des totems Blizzard vit dans PlayerFrame, caché avec lui : barre AeonUI sur son
-- mover (uf_totems). Boutons sécurisés (clic droit : détruire le totem) créés hors combat et
-- jamais cachés : un emplacement vide passe à alpha 0 (SetAlpha est permis en combat).

local MAX_TOTEMS = 4
local totemBar

local function BuildTotems()
    totemBar = CreateFrame("Frame", "AeonUI_Totems", UIParent)
    totemBar.buttons = {}
    for slot = 1, MAX_TOTEMS do
        local button = CreateFrame("Button", "AeonUI_Totem" .. slot, totemBar, "SecureActionButtonTemplate")
        button:RegisterForClicks("RightButtonUp")
        button:SetAttribute("type2", "destroytotem")
        button:SetAttribute("totem-slot", slot)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        NS.Media:CreateBorder(button)
        button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        button.cooldown:SetAllPoints()
        NS.RegisterCooldown(button.cooldown)
        button:SetAlpha(0)
        totemBar.buttons[slot] = button
    end
end

--- Icône et durée de chaque emplacement. Appelé en combat : aucune taille, aucun Show/Hide.
function UnitFrames:UpdateTotems()
    if not (totemBar and totemBar:IsShown()) then return end
    for slot, button in ipairs(totemBar.buttons) do
        local have, icon, start, duration = NS.GetTotem(slot)
        local present
        if NS.IsSecret(have) or NS.IsSecret(icon) then present = true   -- illisible : affiché
        else present = have and icon ~= nil and icon ~= "" and icon ~= 0 end
        if present then
            button.icon:SetTexture(icon)
            if not NS.IsSecret(start) and not NS.IsSecret(duration) and start and duration and duration > 0 then
                button.cooldown:SetCooldown(start, duration)
            else
                button.cooldown:Clear()
            end
        end
        button:SetAlpha(present and 1 or 0)
    end
end

--- Taille, mover et visibilité de la barre (hors combat).
local function SetupTotems()
    if not totemBar then BuildTotems() end
    local size = Settings("player").totemSize
    for slot, button in ipairs(totemBar.buttons) do
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("LEFT", totemBar, "LEFT", (slot - 1) * (size + 4), 0)
    end
    totemBar:SetSize(MAX_TOTEMS * (size + 4) - 4, size)
    -- À gauche du cadre du joueur : sous lui, le calque du familier le recouvrait.
    Movers:Register("uf_totems", totemBar, L.MOVER_UF_TOTEMS, "CENTER", -490, -200)
    Movers:Load("uf_totems")
    totemBar:Show()
    UnitFrames:UpdateTotems()
end

local function TeardownTotems()
    Movers:Unregister("uf_totems")
    if totemBar then totemBar:Hide() end
end

--- Barre posée tant que le cadre du joueur et son option totems sont actifs (hors combat).
function UnitFrames:ReconcileTotems()
    local cfg = Settings("player")
    if active and cfg.enabled and cfg.totems then SetupTotems() else TeardownTotems() end
end

function UnitFrames:GetTotemBar() return totemBar end

--------------------------------------------------------------------------------
-- Événements globaux
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if not active then return end
    if event == "PLAYER_TOTEM_UPDATE" then
        UnitFrames:UpdateTotems()
    elseif event == "PLAYER_TARGET_CHANGED" then
        UnitFrames:Refresh("target")
        UnitFrames:Refresh("targettarget")
        UnitFrames:Refresh("player")   -- points de combo
    elseif event == "PLAYER_FOCUS_CHANGED" then
        UnitFrames:Refresh("focus")
        UnitFrames:Refresh("focustarget")
    elseif event == "UNIT_PET" then
        if unit == "player" then UnitFrames:Refresh("pet") end
    elseif event == "UNIT_TARGET" then
        if unit == "target" then UnitFrames:Refresh("targettarget") end
        if unit == "focus" then UnitFrames:Refresh("focustarget") end
    else
        for _, u in ipairs(UnitFrames.UNITS) do UnitFrames:Refresh(u) end
    end
end)

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function UnitFrames:OnEnable()
    active = true
    self:Reconcile()
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD",
                             "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "PLAYER_TOTEM_UPDATE" }) do
        NS.RegisterEventSafe(events, event)
    end
    NS.RegisterEventSafe(events, "UNIT_PET", "player")
    NS.RegisterEventSafe(events, "UNIT_TARGET", "target", "focus")
end

function UnitFrames:OnDisable()
    active = false
    RunFader()
    events:UnregisterAllEvents()
    local hadFrames = false
    for _, unit in ipairs(self.UNITS) do
        if self.frames[unit] then hadFrames = true end
        Teardown(unit)
    end
    self:ReconcileTotems()   -- active = false : barre retirée
    if hadFrames then NS.Print(L.MSG_UF_DISABLED_RELOAD) end
end

function UnitFrames:OnRefresh()
    self:Reconcile()
end

-- Thème ou échelle : tailles au pixel à reposer (hors combat, cadres protégés).
local function Relayout()
    if not active then return end
    NS:RunOutOfCombat(function() if active then UnitFrames:Reconcile() end end)
end
NS:On("PIXEL_CHANGED", Relayout)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

local TEXT_MODES = Elements.TextModeChoices

function UnitFrames:BuildOptions(o)
    local layout = o.layout
    layout:Note(L.NOTE_UF_RELOAD, 20)
    o:Check("classColor", L.OPT_UF_CLASS_COLOR)
    o:Check("healthGradient", L.OPT_UF_HEALTH_GRADIENT)
    o:Check("healPrediction", L.OPT_UF_HEAL_PREDICTION)
    o:Dropdown("healthText", L.OPT_UF_HEALTH_TEXT, TEXT_MODES)
    o:Dropdown("powerText", L.OPT_UF_POWER_TEXT, TEXT_MODES)
    o:Slider("fadeAlpha", L.OPT_UF_FADE_ALPHA, 0, 0.9, 0.05, nil, "%.2f")
    layout:Note(L.NOTE_UF_TEXT_TOKENS, 20)
    layout:Title(L.OPT_AURA_LISTS)
    layout:Note(L.NOTE_AURA_LISTS, 20)
    local function ListSetter(field)
        return function(value) NS.db.auraLists[field] = value or "" NS.Modules:RefreshAll() end
    end
    layout:EditBox(L.OPT_AURA_WHITELIST, function() return NS.db.auraLists.whitelist end, ListSetter("whitelist"), 1, 20)
    layout:EditBox(L.OPT_AURA_BLACKLIST, function() return NS.db.auraLists.blacklist end, ListSetter("blacklist"), 1, 20)
    layout:Button(L.OPT_UF_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
    -- Un onglet par unité ; « Copier depuis » reprend les réglages d'une autre unité.
    local sources = {}
    for _, unit in ipairs(self.SETTINGS_UNITS) do
        sources[#sources + 1] = { name = L["UF_UNIT_" .. unit:upper()], value = "units." .. unit }
    end
    for _, unit in ipairs(self.SETTINGS_UNITS) do
        local key = "units." .. unit .. "."
        o:Tab(L["UF_UNIT_" .. unit:upper()])
        o:Check(key .. "enabled", L.OPT_UF_UNIT_ENABLED)
        o:CopyFrom("units." .. unit, sources, 36)
        o:Slider(key .. "width", L.OPT_UF_WIDTH, 60, 400, 2, 36)
        o:Slider(key .. "height", L.OPT_UF_HEIGHT, 12, 80, 1, 36)
        o:Check(key .. "name", L.OPT_UF_UNIT_NAME, 36)
        o:Check(key .. "level", L.OPT_UF_UNIT_LEVEL, 36)
        o:Check(key .. "fader", L.OPT_UF_UNIT_FADER, 36)
        o:Check(key .. "portrait", L.OPT_UF_UNIT_PORTRAIT, 36)
        if unit == "player" then
            o:Check(key .. "combo", L.OPT_UF_UNIT_COMBO, 36)
            o:Check(key .. "totems", L.OPT_UF_UNIT_TOTEMS, 36)
            o:Slider(key .. "totemSize", L.OPT_UF_TOTEM_SIZE, 16, 60, 2, 52)
        end
        o:Check(key .. "power", L.OPT_UF_UNIT_POWER, 36)
        o:Slider(key .. "powerHeight", L.OPT_UF_POWER_HEIGHT, 0, 16, 1, 52)
        o:Check(key .. "castbar", L.OPT_UF_UNIT_CASTBAR, 36)
        o:Slider(key .. "castbarHeight", L.OPT_UF_CASTBAR_HEIGHT, 8, 30, 1, 52)
        o:Check(key .. "castbarDetached", L.OPT_UF_CASTBAR_DETACHED, 52)
        o:Slider(key .. "castbarWidth", L.OPT_UF_CASTBAR_WIDTH, 100, 500, 2, 68)
        o:Check(key .. "auras", L.OPT_UF_UNIT_AURAS, 36)
        o:Check(key .. "aurasAbove", L.OPT_UF_AURAS_ABOVE, 52)
        o:Slider(key .. "auraSize", L.OPT_UF_AURA_SIZE, 12, 40, 1, 52)
        o:Dropdown(key .. "auraFilter", L.OPT_AURA_FILTER, NS.AuraFilterChoices, 52)
        o:EditBox(key .. "healthFormat", L.OPT_UF_HEALTH_FORMAT, 1, 36)
        if unit ~= "targettarget" and unit ~= "focustarget" then
            o:EditBox(key .. "powerFormat", L.OPT_UF_POWER_FORMAT, 1, 36)
        end
    end
end
