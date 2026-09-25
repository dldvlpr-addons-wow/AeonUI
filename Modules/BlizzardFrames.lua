-- Modules/BlizzardFrames.lua
-- Cadres Blizzard déplaçables : gestionnaire de temps de recharge (quatre viewers), buffs et
-- débuffs du joueur. Systèmes Edit Mode : jamais reparentés, posés sur un support AeonUI
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
}

local defaults = { enabled = false }
for _, def in ipairs(FRAMES) do defaults[def.key] = "move" end   -- "move" | "keep"

local BlizzardFrames = NS.Modules:Register("blizzardframes", {
    titleKey = "BF_TITLE",
    descKey = "BF_DESC",
    yieldsTo = { "ElvUI" },
    secure = true,            -- systèmes Edit Mode protégés : tout hors combat
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
            if self.db[def.key] == "move" then
                Movers:Adopt(def.key, frame, L[def.label], def.default[1], def.default[2], def.default[3], def.anchor)
            else
                Movers:Release(def.key)
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
end

function BlizzardFrames:OnDisable()
    active = false
    events:UnregisterAllEvents()
    for _, def in ipairs(FRAMES) do Movers:Release(def.key) end
    NS.Print(L.MSG_BF_DISABLED_RELOAD)
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
