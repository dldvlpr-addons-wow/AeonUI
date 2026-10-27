-- Modules/BlizzardFrames.lua
-- Cadres Blizzard déplaçables : gestionnaire de temps de recharge (quatre viewers), buffs et
-- débuffs du joueur. Systèmes Edit Mode : jamais reparentés, posés sur un support MuscaUI
-- (Movers:Adopt) ou laissés à Blizzard. Les viewers se chargent à la demande
-- (Blizzard_CooldownViewer) : rattrapés sur ADDON_LOADED.
local _, NS = ...
local L = NS.L
local Movers = NS.Movers

local FRAMES = {
    { key = "cdm_essential", names = { "EssentialCooldownViewer" }, label = "MOVER_CDM_ESSENTIAL", default = { "BOTTOM", 0, 236 }, anchor = "CENTER" },
    { key = "cdm_utility",   names = { "UtilityCooldownViewer" },   label = "MOVER_CDM_UTILITY",   default = { "BOTTOM", 0, 288 }, anchor = "CENTER" },
    { key = "cdm_bufficon",  names = { "BuffIconCooldownViewer" },  label = "MOVER_CDM_BUFFICON",  default = { "CENTER", 0, -40 }, anchor = "CENTER" },
    { key = "cdm_buffbar",   names = { "BuffBarCooldownViewer" },   label = "MOVER_CDM_BUFFBAR",   default = { "CENTER", 330, -120 }, anchor = "CENTER" },
    { key = "buffs",         names = { "BuffFrame" },               label = "MOVER_BUFFS",         default = { "TOPRIGHT", -230, -60 }, anchor = "TOPRIGHT" },
    { key = "debuffs",       names = { "DebuffFrame" },             label = "MOVER_DEBUFFS",       default = { "TOPRIGHT", -230, -180 }, anchor = "TOPRIGHT" },
    -- Toasts (succès, butin gagné...) : empilés au-dessus de ce cadre, position d'origine de Blizzard.
    { key = "toasts",        names = { "AlertFrame" },              label = "MOVER_TOASTS",        default = { "BOTTOM", 0, 128 }, anchor = "BOTTOM", size = { 300, 40 } },   -- AlertFrame fait 10x10 : support saisissable
    -- Fenêtre de butin Blizzard : « keep » d'office (position Edit Mode). Laissée à Blizzard quand le
    -- butin est sous la souris ou quand la fenêtre MuscaUI la remplace. Les jets de groupe
    -- (GroupLootContainer) sont gérés par la pile de cadres du bas de l'écran : non déplaçables ici,
    -- le module Butin a son propre mover de jets.
    { key = "lootframe",     names = { "LootFrame" },               label = "MOVER_BLIZZ_LOOT",    default = { "LEFT", 300, 100 }, anchor = "TOPLEFT", keep = true,
      skip = function()
          local loot = NS.Modules:Get("loot")
          -- Blizzard ancre au curseur (CVar, ou manette) : on ne réancre pas. Relu sur CVAR_UPDATE.
          return NS.CVars:Get("lootUnderMouse") == "1" or NS.CVars:Get("GamePadEnable") == "1"
              or (loot and loot.enabled and loot.db.window)
      end },
}

local defaults = { enabled = false }
for _, def in ipairs(FRAMES) do defaults[def.key] = def.keep and "keep" or "move" end   -- "move" | "keep"

local BlizzardFrames = NS.Modules:Register("blizzardframes", {
    titleKey = "BF_TITLE",
    descKey = "BF_DESC",
    secure = true,            -- systèmes Edit Mode protégés : tout hors combat
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    defaults = defaults,
})

BlizzardFrames.FRAMES = FRAMES
local active = false

local function Resolve(def)
    for _, name in ipairs(def.names) do
        if _G[name] then return _G[name] end
    end
    return nil
end

function BlizzardFrames:Apply()
    for _, def in ipairs(FRAMES) do
        local frame = Resolve(def)
        if frame then
            if self.db[def.key] == "move" and not (def.skip and def.skip()) then
                local holder = Movers:Adopt(def.key, frame, L[def.label], def.default[1], def.default[2], def.default[3], def.anchor)
                if def.size then holder:SetSize(def.size[1], def.size[2]) end
            elseif Movers.adopted[def.key] and Movers.adopted[def.key].active then
                -- « move » -> « keep » : le cadre reste posé sur le support jusqu'au /reload.
                Movers:Release(def.key)
                NS:Fire("BLIZZARD_FRAMES_RELEASED")
            end
        end
    end
end

local events = CreateFrame("Frame")
-- Par Modules:Refresh : les movers repris ici savent qu'ils appartiennent à ce module.
events:SetScript("OnEvent", function()
    if active then NS.Modules:Refresh("blizzardframes") end
end)

function BlizzardFrames:OnEnable()
    active = true
    self:Apply()
    NS.RegisterEventSafe(events, "ADDON_LOADED")
    NS.RegisterEventSafe(events, "PLAYER_ENTERING_WORLD")
    NS.RegisterEventSafe(events, "CVAR_UPDATE")
end

function BlizzardFrames:OnDisable()
    active = false
    events:UnregisterAllEvents()
    local released = false
    for _, def in ipairs(FRAMES) do
        local entry = Movers.adopted[def.key]
        if entry and entry.active then released = true end
        Movers:Release(def.key)
    end
    -- Coupure par profil (DisableAll) : /reload proposé, sauf si le nouveau profil rallume le module.
    if released then
        C_Timer.After(0, function() if not active then NS:Fire("BLIZZARD_FRAMES_RELEASED") end end)
    end
end

function BlizzardFrames:OnRefresh()
    if active then self:Apply() end
end

function BlizzardFrames:BuildOptions(o)
    o.layout:Note(L.NOTE_BF, 20)
    local choices = { { name = L.AB_SIDE_MOVE, value = "move" }, { name = L.AB_SIDE_KEEP, value = "keep" } }
    for _, def in ipairs(FRAMES) do o:Dropdown(def.key, L[def.label], choices) end
    o.layout:Button(L.OPT_UF_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
end
