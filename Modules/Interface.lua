-- Modules/Interface.lua
-- Interface épurée : ce qui encombre l'écran, et les réglages Blizzard qu'on veut changer
-- sans fouiller le menu. Toute CVar passe par NS.CVars : sa valeur d'origine est gardée et
-- rendue quand l'option (ou le module) est coupée.
--   * messages d'erreur rouges (« Pas assez de mana »…) masqués ;
--   * tête parlante, tutoriels, message « Capture d'écran enregistrée » masqués ;
--   * alertes de sort (proc) : opacité réglable, ou masquées pour la classe du personnage ;
--   * barres d'action toujours visibles, même vides ;
--   * erreurs Lua masquées (pour qui ne développe pas) ;
--   * chiffres de recharge : le décompte natif du moteur, sur tous les boutons et icônes ;
--   * carte du monde : coordonnées (joueur, curseur) et niveaux de la zone, en option ;
--   * recharges MuscaUI colorées par palier : formateur natif, la durée secrète reste au moteur.
local _, NS = ...
local L = NS.L

local Interface = NS.Modules:Register("interface", {
    titleKey = "UI_TITLE",
    descKey = "UI_DESC",
    defaults = {
        enabled = true,
        hideErrors = false,
        hideTalkingHead = true,
        hideTutorials = true,
        hideScreenshotMessage = true,
        alertOpacity = false,
        alertOpacityValue = 0.65,
        hideProcClasses = {},      -- [classFile] = true : alertes de sort masquées pour cette classe
        alwaysShowBars = false,
        hideLuaErrors = false,
        cooldownNumbers = false,   -- secondes restantes écrites sur toutes les recharges (natif)
        cooldownColors = false,    -- recharges MuscaUI : texte coloré par palier (formateur natif)
        cooldownExpiring = 3,      -- sous ce seuil (s) : rouge, avec une décimale ; 0 = jamais
        cooldownColorExpiring = { r = 1, g = 0.2, b = 0.2 },
        cooldownColorSeconds = { r = 1, g = 0.9, b = 0.3 },
        cooldownColorMinutes = { r = 1, g = 1, b = 1 },
        mapCoords = false,         -- coordonnées du joueur et du curseur sur la carte du monde
        mapLevels = false,         -- niveaux de la zone affichée sur la carte du monde
        mapFade = false,           -- jeu visible derrière la carte maximisée (fond noir allégé)
        mapFadeMoving = false,     -- CVar mapFade : carte transparente pendant le déplacement
        slashWay = false,          -- /way x y pose un point de route sur la carte du joueur
        wayArrival = false,        -- point de route retiré quand le joueur arrive dessus
        slashCooldowns = false,    -- /cd ouvre le gestionnaire de recharges Blizzard
        fpsCounter = false,        -- compteur flottant : images par seconde et latence
        fpsLatency = true,
    },
})

local active = false

--- CVars gérées : [nom] = fonction(db) -> valeur voulue, ou nil pour rendre l'origine.
local CVAR_RULES = {
    showTutorials = function(db) return db.hideTutorials and "0" or nil end,
    spellActivationOverlayOpacity = function(db)
        return db.alertOpacity and string.format("%.2f", db.alertOpacityValue) or nil
    end,
    displaySpellActivationOverlays = function(db)
        local _, classFile = UnitClass("player")
        return db.hideProcClasses[classFile] and "0" or nil
    end,
    alwaysShowActionBars = function(db) return db.alwaysShowBars and "1" or nil end,
    mapFade = function(db) return db.mapFadeMoving and "1" or nil end,
    scriptErrors = function(db) return db.hideLuaErrors and "0" or nil end,
    -- Le texte coloré passe par le compte à rebours natif : il a besoin de la CVar lui aussi.
    countdownForCooldowns = function(db) return (db.cooldownNumbers or db.cooldownColors) and "1" or nil end,
}
Interface.CVAR_RULES = CVAR_RULES

function Interface:ApplyCVars()
    for name, rule in pairs(CVAR_RULES) do
        local wanted = active and rule(self.db) or nil
        if wanted then
            NS.CVars:Set(name, wanted)
        elseif NS.CVars:IsChanged(name) then
            NS.CVars:Restore(name)
        end
    end
end

--------------------------------------------------------------------------------
-- Messages d'erreur
--------------------------------------------------------------------------------

local errorsHidden = false

function Interface:ApplyErrors()
    local frame = _G.UIErrorsFrame
    if not frame then return end
    local hide = active and self.db.hideErrors
    if hide and not errorsHidden then
        frame:UnregisterEvent("UI_ERROR_MESSAGE")
        errorsHidden = true
    elseif not hide and errorsHidden then
        frame:RegisterEvent("UI_ERROR_MESSAGE")
        errorsHidden = false
    end
end

--------------------------------------------------------------------------------
-- Tête parlante et capture d'écran
--------------------------------------------------------------------------------

-- Système Edit Mode : ni Hide ni CloseImmediately depuis l'addon (relayout contaminé du
-- conteneur). On lui retire l'événement qui l'ouvre, et on le lui rend quand l'option est coupée.
function Interface:ApplyTalkingHead()
    local frame = _G.TalkingHeadFrame
    if not frame then return end
    if active and self.db.hideTalkingHead then
        frame:UnregisterEvent("TALKINGHEAD_REQUESTED")
    else
        NS.RegisterEventSafe(frame, "TALKINGHEAD_REQUESTED")
    end
end

--------------------------------------------------------------------------------
-- Carte du monde : coordonnées et niveaux
--------------------------------------------------------------------------------

local MAP_FADE_ALPHA = 0.2
local mapInfo   -- cadre enfant de WorldMapFrame, créé au premier besoin

local function Percent(x, y)
    if NS.IsSecret(x) or NS.IsSecret(y) or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return "--" end
    return string.format("%.1f, %.1f", x * 100, y * 100)
end

--- Texte affiché : niveaux de la zone, puis position du joueur et du curseur.
function Interface.MapText(db, mapID, cursorX, cursorY, playerX, playerY)
    local lines = {}
    if db.mapLevels and mapID and C_Map.GetMapLevels then
        local low, high = C_Map.GetMapLevels(mapID)
        if low and high and not NS.IsSecret(low) and not NS.IsSecret(high) and high > 0 then
            lines[#lines + 1] = string.format(L.UI_MAP_LEVELS, low, high)
        end
    end
    if db.mapCoords then
        lines[#lines + 1] = string.format(L.UI_MAP_PLAYER, Percent(playerX, playerY))
        lines[#lines + 1] = string.format(L.UI_MAP_CURSOR, Percent(cursorX, cursorY))
    end
    return table.concat(lines, "\n")
end

local function UpdateMapInfo()
    local map = _G.WorldMapFrame
    if not (mapInfo and map and map.GetMapID) then return end
    local mapID = map:GetMapID()
    local playerX, playerY
    if mapID and C_Map.GetPlayerMapPosition then
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if position and position.GetXY then playerX, playerY = position:GetXY() end
    end
    local cursorX, cursorY = map:GetNormalizedCursorPosition()
    mapInfo.text:SetText(Interface.MapText(Interface.db, mapID, cursorX, cursorY, playerX, playerY))
end

--- Crée (une fois) ou retire l'encart ; la carte est chargée à la demande (Blizzard_WorldMap).
function Interface:ApplyMap()
    local map = _G.WorldMapFrame
    local wanted = active and (self.db.mapCoords or self.db.mapLevels)
    if wanted and map and not mapInfo then
        mapInfo = CreateFrame("Frame", nil, map)
        mapInfo:SetSize(220, 50)
        mapInfo:SetPoint("BOTTOM", map, "BOTTOM", 0, 8)
        mapInfo:SetFrameStrata("HIGH")
        mapInfo.text = mapInfo:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mapInfo.text:SetAllPoints()
        local elapsed = 0
        mapInfo:SetScript("OnUpdate", function(_, delta)
            elapsed = elapsed + delta
            if elapsed < 0.1 then return end
            elapsed = 0
            UpdateMapInfo()
        end)
    end
    if mapInfo then mapInfo:SetShown(wanted and true or false) end
    -- Fond noir de la carte maximisée : opaque d'origine (alpha 1 de sa couleur).
    local blackout = map and map.BlackoutFrame and map.BlackoutFrame.Blackout
    if blackout then blackout:SetAlpha(active and self.db.mapFade and MAP_FADE_ALPHA or 1) end
end

--------------------------------------------------------------------------------
-- Compteur d'images par seconde
--------------------------------------------------------------------------------

--- /cd : ouvre (ou ferme) les réglages de recharges Blizzard ; enregistré au premier passage où l'option est cochée.
local function ToggleCooldownSettings()
    if not (active and Interface.db.slashCooldowns) then return end
    local settings = _G.CooldownViewerSettings
    if settings and settings.IsShown and settings:IsShown() then settings:Hide() return end
    NS.OpenCooldownViewerSettings()
end

local function RegisterCooldownSlash()
    if _G.SlashCmdList["MUSCAUICOOLDOWNS"] or not Interface.db.slashCooldowns then return end
    _G.SLASH_MUSCAUICOOLDOWNS1 = "/cd"
    _G.SlashCmdList["MUSCAUICOOLDOWNS"] = ToggleCooldownSettings
end

--- /way x y : point de route sur la carte où se trouve le joueur.
local function SetWaypoint(msg)
    if not (active and Interface.db.slashWay) then return end
    local x, y = (msg:gsub(",", " ")):match("^%s*(%d+%.?%d*)%s+(%d+%.?%d*)")
    x, y = tonumber(x), tonumber(y)
    if not (x and y) or x > 100 or y > 100 then NS.Print(L.MSG_WAY_USAGE) return end
    NS.Print(NS.SetUserWaypoint(x, y) and string.format(L.MSG_WAY_SET, x, y) or L.MSG_WAY_FAILED)
end

--- Enregistré comme /cd, et seulement si aucun addon (TomTom…) n'a déjà pris /way.
local function RegisterWaySlash()
    if _G.SlashCmdList["MUSCAUIWAY"] or not Interface.db.slashWay then return end
    for key in pairs(_G.SlashCmdList) do
        for i = 1, 9 do
            local command = _G["SLASH_" .. key .. i]
            if not command then break end
            if command:lower() == "/way" then return end
        end
    end
    _G.SLASH_MUSCAUIWAY1 = "/way"
    _G.SlashCmdList["MUSCAUIWAY"] = SetWaypoint
end

local WAY_ARRIVAL_YARDS = 10
local wayTicker
local armedPoint   -- point dont le joueur s'est déjà éloigné : un point posé sous ses pieds reste

local function CheckWayArrival()
    local distance, point = NS.UserWaypointDistance()
    if not distance then return end
    local key = point.uiMapID .. ":" .. point.position.x .. ":" .. point.position.y
    if distance > WAY_ARRIVAL_YARDS then
        armedPoint = key
    elseif armedPoint == key then
        armedPoint = nil
        NS.ClearUserWaypoint()
        NS.Print(L.MSG_WAY_ARRIVED)
    end
end

function Interface:ApplyWayArrival()
    if active and self.db.wayArrival then
        wayTicker = wayTicker or C_Timer.NewTicker(1, CheckWayArrival)
    elseif wayTicker then
        wayTicker:Cancel()
        wayTicker = nil
    end
end

local fpsFrame, fpsTicker

local function UpdateFps()
    local text = math.floor(GetFramerate() + 0.5) .. " " .. L.OPT_G_QOL_FPS_UNIT
    if Interface.db.fpsLatency and _G.GetNetStats then
        local _, _, home, world = GetNetStats()
        text = text .. "  " .. math.max(home or 0, world or 0) .. " ms"
    end
    fpsFrame.text:SetText(text)
    fpsFrame:SetSize(math.max(60, fpsFrame.text:GetStringWidth() + 12), 20)
end

function Interface:ApplyFps()
    local wanted = active and self.db.fpsCounter
    if wanted and not fpsFrame then
        fpsFrame = CreateFrame("Frame", "MuscaUIFpsCounter", UIParent)
        fpsFrame.text = NS.Media:CreateText(fpsFrame, "OVERLAY", 0, "OUTLINE")
        fpsFrame.text:SetPoint("CENTER")
    end
    if wanted then
        fpsTicker = fpsTicker or C_Timer.NewTicker(1, UpdateFps)
        NS.Movers:Register("fpsCounter", fpsFrame, L.OPT_G_QOL_FPS_COUNTER, "TOPRIGHT", -20, -20)
        NS.Movers:Load("fpsCounter")
        UpdateFps()
        fpsFrame:Show()
    else
        if fpsTicker then fpsTicker:Cancel() fpsTicker = nil end
        if fpsFrame then
            NS.Movers:Unregister("fpsCounter")
            fpsFrame:Hide()
        end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_TalkingHeadUI" then Interface:ApplyTalkingHead() end
        if name == "Blizzard_WorldMap" then Interface:ApplyMap() end
    elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
        if Interface.db.hideScreenshotMessage then
            -- Le message s'affiche dans la même frame ; le cacher une frame plus tard.
            C_Timer.After(0, function() if _G.ActionStatus then ActionStatus:Hide() end end)
        end
    end
end)

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Texte de recharge coloré
--------------------------------------------------------------------------------

function Interface:ApplyCooldownText()
    local db = self.db
    if active and db.cooldownColors then
        NS.CooldownText.config = {
            expiring = db.cooldownExpiring,
            colors = { expiring = db.cooldownColorExpiring, seconds = db.cooldownColorSeconds, minutes = db.cooldownColorMinutes },
        }
    else
        NS.CooldownText.config = nil
    end
    NS.RefreshCooldowns()
end

function Interface:OnEnable()
    active = true
    for _, event in ipairs({ "ADDON_LOADED", "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED" }) do
        NS.RegisterEventSafe(events, event)
    end
    self:ApplyCVars()
    self:ApplyErrors()
    self:ApplyTalkingHead()
    self:ApplyCooldownText()
    self:ApplyMap()
    self:ApplyFps()
    self:ApplyWayArrival()
    RegisterCooldownSlash()
    RegisterWaySlash()
end

function Interface:OnDisable()
    active = false
    events:UnregisterAllEvents()
    self:ApplyCVars()
    self:ApplyErrors()
    self:ApplyTalkingHead()
    self:ApplyCooldownText()
    self:ApplyMap()
    self:ApplyFps()
    self:ApplyWayArrival()
end

function Interface:OnRefresh()
    self:ApplyCVars()
    self:ApplyErrors()
    self:ApplyTalkingHead()
    self:ApplyCooldownText()
    self:ApplyMap()
    self:ApplyFps()
    self:ApplyWayArrival()
    RegisterCooldownSlash()
    RegisterWaySlash()
end

-- Réglages du jeu sans menu Blizzard : liés à la CVar elle-même (compte entier, pas au profil),
-- par NS.CVars pour garder l'origine. La case caméra de l'assistant pose la même CVar.
local GAME_SLIDERS = {
    { name = "cameraDistanceMaxZoomFactor", label = "OPT_UI_CAMERA", min = 1, max = 2.6, step = 0.1, format = "%.1f" },
    { name = "SpellQueueWindow", label = "OPT_UI_SPELL_QUEUE", min = 0, max = 400, step = 10, format = "%d ms" },
}

-- Texte de combat flottant (CombatText Blizzard) : une case par CVar réellement présente sur le client.
local FLOATING_TEXT_TOGGLES = {
    { "enableFloatingCombatText", "OPT_UI_FCT_ENABLE" },
    { "floatingCombatTextDodgeParryMiss_v2", "OPT_UI_FCT_DODGE" },
    { "floatingCombatTextDamageReduction_v2", "OPT_UI_FCT_REDUCTION" },
    { "floatingCombatTextAuras_v2", "OPT_UI_FCT_AURAS" },
    { "floatingCombatTextAuraFade_v2", "OPT_UI_FCT_AURA_FADE" },
    { "floatingCombatTextLowManaHealth_v2", "OPT_UI_FCT_LOW" },
    { "floatingCombatTextEnergyGains_v2", "OPT_UI_FCT_ENERGY" },
    { "floatingCombatTextComboPoints_v2", "OPT_UI_FCT_COMBO" },
    { "floatingCombatTextCombatState_v2", "OPT_UI_FCT_COMBAT_STATE" },
    { "floatingCombatTextReactives_v2", "OPT_UI_FCT_REACTIVES" },
    { "floatingCombatTextFriendlyHealers_v2", "OPT_UI_FCT_HEALERS" },
    { "floatingCombatTextHonorGains_v2", "OPT_UI_FCT_HONOR" },
    { "floatingCombatTextRepChanges_v2", "OPT_UI_FCT_REPUTATION" },
}
Interface.FLOATING_TEXT_TOGGLES = FLOATING_TEXT_TOGGLES

local function GameSettings(o)
    o:Title(L.OPT_UI_GAME)
    for _, entry in ipairs(GAME_SLIDERS) do
        if NS.CVars:Exists(entry.name) then
            o.layout:Slider(L[entry.label], entry.min, entry.max, entry.step,
                function() return tonumber(NS.CVars:Get(entry.name)) or entry.max end,
                function(value) NS.CVars:Set(entry.name, tostring(value)) end, 20, entry.format)
        end
    end
    if NS.CVars:Exists("ActionButtonUseKeyDown") then
        o.layout:Check(L.OPT_UI_KEY_DOWN,
            function() return NS.CVars:Get("ActionButtonUseKeyDown") == "1" end,
            function(checked) NS.CVars:Set("ActionButtonUseKeyDown", checked and "1" or "0") end, 20)
    end
    local titled
    for _, toggle in ipairs(FLOATING_TEXT_TOGGLES) do
        local name = toggle[1]
        if NS.CVars:Exists(name) then
            if not titled then o:Title(L.OPT_UI_FCT); titled = true end
            o.layout:Check(L[toggle[2]], function() return NS.CVars:Get(name) == "1" end,
                function(checked) NS.CVars:Set(name, checked and "1" or "0") end, 20)
        end
    end
end

function Interface:BuildOptions(o)
    GameSettings(o)
    o:Title(L.OPT_UI_CLUTTER)
    o:Check("hideErrors", L.OPT_UI_ERRORS)
    o:Check("hideTalkingHead", L.OPT_UI_TALKING_HEAD)
    o:Check("hideTutorials", L.OPT_UI_TUTORIALS)
    o:Check("hideScreenshotMessage", L.OPT_UI_SCREENSHOT)
    o:Check("hideLuaErrors", L.OPT_UI_LUA_ERRORS)
    o:Title(L.OPT_UI_ALERTS)
    o:Check("alertOpacity", L.OPT_UI_ALERT_OPACITY)
    o:Slider("alertOpacityValue", L.OPT_UI_ALERT_OPACITY_VALUE, 0, 1, 0.05, 36, "%.2f")
    local localized, classFile = UnitClass("player")
    o.layout:Check(string.format(L.OPT_UI_HIDE_PROCS, localized or classFile or "?"),
        function() return NS.db.modules.interface.hideProcClasses[classFile] end,
        function(value)
            NS.db.modules.interface.hideProcClasses[classFile] = value or nil
            NS.Modules:Refresh("interface")
        end, 20)
    o:Title(L.OPT_UI_MAP)
    o:Check("mapCoords", L.OPT_UI_MAP_COORDS)
    o:Check("mapLevels", L.OPT_UI_MAP_LEVELS)
    o:Check("mapFade", L.OPT_G_QOL_MAP_FADE)
    o:Check("mapFadeMoving", L.OPT_M_QOL_MAP_FADE_MOVING)
    o:Check("slashWay", L.OPT_M_QOL_SLASH_WAY)
    o:Check("wayArrival", L.OPT_M_QOL_WAY_ARRIVAL)
    o:Title(L.OPT_G_QOL_FPS_COUNTER)
    o:Check("fpsCounter", L.OPT_G_QOL_FPS_COUNTER)
    o:Check("fpsLatency", L.OPT_G_QOL_FPS_LATENCY, 36)
    o:Title(L.OPT_UI_BARS)
    o:Check("alwaysShowBars", L.OPT_UI_ALWAYS_BARS)
    o:Check("slashCooldowns", L.OPT_G_QOL_SLASH_COOLDOWNS)
    o:Check("cooldownNumbers", L.OPT_UI_COOLDOWN_NUMBERS)
    o:Check("cooldownColors", L.OPT_UI_COOLDOWN_COLORS)
    if not NS.CooldownText.Supported() then o:Note(L.OPT_UI_COOLDOWN_COLORS_MISSING, 36) end
    o:Advanced()
    o:Slider("cooldownExpiring", L.OPT_UI_COOLDOWN_EXPIRING, 0, 10, 1, 36)
    o:Color("cooldownColorExpiring", L.OPT_UI_COOLDOWN_COLOR_EXPIRING, 36)
    o:Color("cooldownColorSeconds", L.OPT_UI_COOLDOWN_COLOR_SECONDS, 36)
    o:Color("cooldownColorMinutes", L.OPT_UI_COOLDOWN_COLOR_MINUTES, 36)
end
