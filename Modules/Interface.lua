-- Modules/Interface.lua
-- Interface épurée : ce qui encombre l'écran, et les réglages Blizzard qu'on veut changer
-- sans fouiller le menu. Toute CVar passe par NS.CVars : sa valeur d'origine est gardée et
-- rendue quand l'option (ou le module) est coupée.
--   * messages d'erreur rouges (« Pas assez de mana »…) masqués ;
--   * tête parlante, tutoriels, message « Capture d'écran enregistrée » masqués ;
--   * alertes de sort (proc) : opacité réglable, ou masquées pour la classe du personnage ;
--   * barres d'action toujours visibles, même vides (mode débutant de NaowhUI) ;
--   * erreurs Lua masquées (pour qui ne développe pas) ;
--   * chiffres de recharge : le décompte natif du moteur, sur tous les boutons et icônes ;
--   * recharges AeonUI colorées par palier : formateur natif, la durée secrète reste au moteur.
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
        cooldownColors = false,    -- recharges AeonUI : texte coloré par palier (formateur natif)
        cooldownExpiring = 3,      -- sous ce seuil (s) : rouge, avec une décimale ; 0 = jamais
        cooldownColorExpiring = { r = 1, g = 0.2, b = 0.2 },
        cooldownColorSeconds = { r = 1, g = 0.9, b = 0.3 },
        cooldownColorMinutes = { r = 1, g = 1, b = 1 },
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

local talkingHooked = false

local function HookTalkingHead()
    local frame = _G.TalkingHeadFrame
    if talkingHooked or not frame or not frame.PlayCurrent then return end
    talkingHooked = true
    hooksecurefunc(frame, "PlayCurrent", function(self)
        if active and Interface.db.hideTalkingHead then
            if self.CloseImmediately then self:CloseImmediately() else self:Hide() end
        end
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_TalkingHeadUI" then HookTalkingHead() end
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
    HookTalkingHead()
    for _, event in ipairs({ "ADDON_LOADED", "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED" }) do
        NS.RegisterEventSafe(events, event)
    end
    self:ApplyCVars()
    self:ApplyErrors()
    self:ApplyCooldownText()
end

function Interface:OnDisable()
    active = false
    events:UnregisterAllEvents()
    self:ApplyCVars()
    self:ApplyErrors()
    self:ApplyCooldownText()
end

function Interface:OnRefresh()
    self:ApplyCVars()
    self:ApplyErrors()
    self:ApplyCooldownText()
end

function Interface:BuildOptions(o)
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
    o:Title(L.OPT_UI_BARS)
    o:Check("alwaysShowBars", L.OPT_UI_ALWAYS_BARS)
    o:Check("cooldownNumbers", L.OPT_UI_COOLDOWN_NUMBERS)
    o:Check("cooldownColors", L.OPT_UI_COOLDOWN_COLORS)
    if not NS.CooldownText.Supported() then o:Note(L.OPT_UI_COOLDOWN_COLORS_MISSING, 36) end
    o:Slider("cooldownExpiring", L.OPT_UI_COOLDOWN_EXPIRING, 0, 10, 1, 36)
    o:Color("cooldownColorExpiring", L.OPT_UI_COOLDOWN_COLOR_EXPIRING, 36)
    o:Color("cooldownColorSeconds", L.OPT_UI_COOLDOWN_COLOR_SECONDS, 36)
    o:Color("cooldownColorMinutes", L.OPT_UI_COOLDOWN_COLOR_MINUTES, 36)
end
